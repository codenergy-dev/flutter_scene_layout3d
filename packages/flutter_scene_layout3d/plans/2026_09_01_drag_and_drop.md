---
status: in progress
reason: phases 1 and 2 have landed; phases 3 to 8 (cross-surface, Dismissible3d,
  targetPlane anchoring, ReorderableList3d, autoscroll, render probes and docs)
  have not been started
created_at: 2026-09-01T15:40:55Z
updated_at: 2026-09-01T19:24:00Z
commit: e78eb5e28533b37a92779379f8f00c0095023521
---

# A drag that carries something, and a target that catches it

Every drag this package has is a drag of the thing under the finger: a
scrolling view moves because the pointer grabbed it. Nothing carries a
*payload*. A press captures a path and every later event goes back along that
path — which is exactly the rule that makes a scroll drag work, and exactly
the rule a drag-and-drop breaks, because a drag-and-drop is defined by moving
*away* from what it started on and asking what is underneath now.

That gap is the last thing
[the boxes still missing](2026_08_25_the_boxes_still_missing.md) is waiting
on. Its final open item — `Dismissible3d`, `Draggable3d`, `DragTarget3d`,
reorderable lists — is four thin components over one piece of machinery that
does not exist, and
[pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md) put that
machinery in its own *Out of scope* section rather than guessing at it. This
is the plan for it. It is also the last item in the
[readiness](2026_08_25_material3d_readiness_overview.md) work that needs no
GPU: a drag is arithmetic and state, and almost all of it can be pinned down
headlessly.

## What is already here, and what it is worth

More than it looks, because the scroll drag is a working prototype of half of
this and nobody called it one.

- **`Layout3dPointer` already re-hit-tests on every move.** `move()` sets
  `_lastHit = surface.hitTestRay(worldRay)` before it touches the captured
  path, and its dartdoc says so in as many words: "during a drag it is *not*
  the captured path: it is what is under the pointer now." The continuous
  search a drop target needs is already being paid for on one surface. What
  is missing is that nothing is told about it.
- **`_Sequence` is a hand-rolled drag recognizer already.** It is a
  `GestureArenaMember` that accumulates travel on one axis, compares it
  against `computeHitSlop` taken through the metrics, and resolves
  `accepted` — the whole shape of a drag gesture, owing Flutter's recognizer
  classes nothing. Fifty lines, and they work headlessly.
- **`Layout3dPointerGroup` walks surfaces front to back and stops at the
  first that answers**, with a per-pointer capture set. A drop across
  surfaces is a walk it already knows how to do.
- **`Overlay3d` hosts content above everything**, in-plane or on a surface of
  its own, and an entry disposes its subtree when it is removed.
- **The node-only tier exists and is the cheapest thing in the package.**
  `nodeOffset` and `nodeTransform` write one matrix and never dirty layout —
  which is what a piece of feedback following a pointer, and a row sliding
  aside to open a gap, must both be built out of.

And two constraints from the same plan that this one has to design around
rather than wish away: the gesture arena is **global** and can only be
reached on a private pointer id, and in this Flutter build
`LongPressGestureRecognizer` never fires while `DragGestureRecognizer`
delivers `onStart` and nothing after it — reproduced with no code from this
package involved.

## The design

### The payload keeps its generics; the machinery does not see them

`Draggable3d<T>` and `DragTarget3d<T>`, as in Flutter, because the type is
the whole ergonomic value: a target that accepts a `Photo` should not have to
test for one. But the machinery cannot be generic. The drag session is found
through a hit-test path of bare `Layout3d`s, is driven by a pointer that
knows nothing about payloads, and may have to cross surfaces; parameterising
`Layout3dPointer` on `T` is absurd, and `HitTestResult3d.firstOf<T>()` cannot
find `DragTarget3d<Photo>` without the caller naming `Photo` at the search
site.

So the seam under the generics is **non-generic**, exactly as
`HitTestTarget3d` is the non-generic seam under `Listener3d`:

```
abstract interface class Drag3dTarget {
  bool willAcceptDrag3d(Drag3dDetails details);
  void handleDrag3d(Drag3dEvent event);   // enter, move, leave, drop
}
```

`Drag3dDetails` carries `Object? data`, the origin, and the position in the
target's own frame. `DragTarget3d<T>` implements the interface and answers
`willAcceptDrag3d` with `details.data is T` plus the caller's own
`onWillAccept`. **The type test happens inside the target, not in the
machinery** — which is the same place Flutter puts it, and it means a
component in `flutter_scene_material3d` can implement `Drag3dTarget` directly
without inheriting a generic class it does not want.

What this costs, said plainly: a target of `DragTarget3d<Object>` accepts
everything (Flutter's trap, inherited), and there is no compile-time
guarantee that a scene contains a target for a given draggable. Neither is
worth a redesign.

### The feedback lives in an overlay and is moved by `nodeOffset`

Feedback geometry has to be above the content and outside its parent's
bounds, which is `Overlay3d`'s whole job. So: at the moment a drag is
recognized, the session builds `Draggable3d.feedbackBuilder`'s subtree,
wraps it in an `IgnorePointer3d`, and inserts it as an `Overlay3dEntry` into
the overlay found by walking up from the draggable (`Overlay3d.of`), or into
one named explicitly.

**In-plane by default.** `OverlayLayer3d.inPlane` is one surface, one layout
pass, one plane node, and the stack's own ordering is already right; the lift
toward the viewer is what a picked-up card does in Material anyway. A
detached entry is the opt-in for a drag that has to leave the panel it
started on.

**It is laid out once and moved on the node tier.** Every move writes one
`Offset3d` onto the feedback host's `nodeOffset`. Nothing is re-laid out,
nothing is rebuilt, no shader uniform changes; a drag at 120Hz costs one
matrix write a frame. This is not an optimisation, it is the rule
[docs/traps.md](../../../docs/traps.md) sets for anything on a per-frame
path, and a drag is the most per-frame path there is. Note which channel: not
`ParentData3d.sceneOffset`, which belongs to the parent and which
`Stack3d.depthStep` rewrites on every placement — and `Overlay3d` *is* a
`Stack3d`, so an offset stored there would be silently erased.

There is a happy consequence. Hit testing deliberately ignores `nodeOffset`,
so a feedback subtree moved that way is invisible to the ray that is moving
it and cannot steal its own drop. The `IgnorePointer3d` is still mandatory —
the feedback's *laid-out* position is still hit-testable, a `Text3d` in it
would answer on its own account, and a detached feedback entry would
otherwise be a surface that absorbs everything behind it in the group's walk.
(`Layout3dSurface` does not answer hits on its own account, so an
`IgnorePointer3d` at the root of a detached feedback surface makes the whole
surface answer empty, and `Layout3dPointerGroup` walks straight past it. That
is the mechanism; it needs no change to the group.)

**Disposal is the session's, and it is one path.** The entry is removed —
which disposes the built subtree and, for a detached entry, its surface — in
exactly one place, reached by every ending: drop accepted, drop rejected,
pointer cancelled, draggable disposed mid-drag, overlay disposed. A drop
animation delays that removal and nothing else; it is a node-tier tween back
to the origin or onto the accepted target, and the removal happens in its
completion callback.

### Finding a target: a second pass, deliberately

The core mechanism, and the part that is genuinely new.

A live drag adds one pass per move: **re-hit-test, resolve targets, diff
against last time**. On a single surface the hit test is already done — reuse
`Layout3dPointer.lastHit` rather than paying for it twice. Across surfaces it
is not: `Layout3dPointerGroup.move` visits only the surfaces that *captured*
the press, by design, so a dialog the drag wandered onto is never tested. The
group therefore grows a drag-aware move: while a session is live, walk every
member front to back with `hitTest` (the ordinary ordering and absorption
rules, unchanged) and hand the winning path to the session. **Capture governs
where events go; the drag search deliberately ignores capture.** Those are
two different questions and conflating them is what makes a drag impossible.

From the winning path the session collects every entry whose layout is a
`Drag3dTarget` and asks each `willAcceptDrag3d`. Then:

- **enter and leave go to every accepting target on the path**, diffed
  against the previous set, so a list and the row inside it can both light
  up. Same shape as hover's path diff, same reasons.
- **the drop goes to the deepest acceptor**, which is the first one the ray
  meets.

Cost: one hit test per surface per move while a drag is live, which is what
every mouse move already costs for hover. Hit testing allocates nothing but a
result list and is arithmetic all the way down.

### What "over a target" means when targets sit at different depths

A ray through a scene can pass through several planes. The rule is the one a
press already uses: **the nearest acceptor along the ray wins**, ordered by
the hit path within a surface and by the group's front-to-back walk between
them. The argument for it is consistency and not much else, but consistency
is enough: *a drop lands where a tap would land*. Any other rule means the
viewer cannot predict a drop from what they know about pressing.

The sharp edge that comes with it is already in the traps file:
`Stack3d.depthStep` does not separate children thicker than the step, so a
slab that reaches further toward the viewer than the step can win the depth
test while sitting behind in the stack. Where that happens the ray order and
the *visual* order disagree, and a drop lands on what looks like the back
card. This is a documentation item and a layout rule for catalogue
components — keep drop targets thin relative to the step — not something the
drag machinery can fix.

**Where the feedback sits is a separate question from which target is
active**, and the plan takes a position on it: `Drag3dAnchor`.

- **`originPlane` (the default, phase 2).** The feedback stays on the plane
  the drag started on, the same plane `PointerEvent3d.localPosition` is
  measured on and the same one the scroll drag resolves against with
  `pointOnPlane(ray, depth)`. No new arithmetic, exact at any camera angle,
  and it keeps the card in the panel it came from — which is what almost
  every real drag wants: a reorder inside one list, a move between two lists
  on one surface.
- **`targetPlane` (phase 5, and the least certain thing here).** When the
  active target is on another surface, the feedback re-anchors to that
  surface's plane, animated on the node tier, so a card visibly lands on the
  table it is being dropped onto. Re-anchoring means moving the entry to the
  target surface's overlay, which is an insert and a remove and therefore a
  build — so it happens **on target change, never per move**.
- Holding the feedback at a fixed distance along the pointer ray, facing the
  viewer, is a third answer and is out of scope; a billboard-bound detached
  entry is the shape it would take.

### The drag recognizer is ours

Flutter's `Draggable` is built on `MultiDragGestureRecognizer`. That is not
available to us in any useful form: `DragGestureRecognizer` delivers only
`onStart` in this build, `LongPressGestureRecognizer` never fires at all, and
both findings were reproduced with no layout3d code involved. Building
long-press-to-drag on a recognizer that does not fire would produce a feature
that cannot be tested and cannot be demonstrated.

So **the package recognizes the drag itself, as a `GestureArenaMember` on the
sequence, exactly as the scroll drag already does.** That code exists, is
tested, and depends on Flutter only for the arena — which is the one part
that does work. A `Drag3dGesture` accumulates travel from
`PointerEvent3d.localPosition` (world units, on the box's own plane),
compares it against `computeHitSlop` taken through
`metrics.unitsPerLogicalPixel`, and resolves `accepted` when it crosses. The
update stream then comes from `handleEvent` along the **captured** path,
which is the draggable's own path, so the drag keeps receiving moves long
after the pointer has left the box it started on. Nothing about this needs a
recognizer.

One new seam is required. Today a target says it is competing through
`PointerSequence3d.addPointerToRecognizer`, which takes a
`GestureRecognizer`. Add `addArenaMember(GestureArenaMember)` beside it,
doing the same two things: mark the sequence contested, and add the member to
the global arena on `arenaPointer`. The contested flag is what makes a
`Scrollable3d` under the draggable wait for the slop instead of scrolling out
from under it — and the ordering already works, because the down is
dispatched along the whole path *before* `_armDrag` reads the flag.

Start modes, mirroring Flutter's semantics without its classes:

- **`immediate`** — claims on the first travel past the slop. What a
  `Dismissible3d` and a desktop drag want.
- **`longPress(Duration)`** — a `Timer` started at the press, cancelled by
  travel past the slop or by the pointer coming up; on fire it resolves
  `accepted` and the drag begins in place. A plain timer, not a recognizer,
  for the reason above. Testable under `testWidgets` with `tester.pump`.
- An **axis** on the draggable, so a horizontally-dismissible row inside a
  vertical list claims on horizontal travel while the list claims on
  vertical — the first to cross its own slop on its own axis wins the arena,
  which is how Flutter's horizontal and vertical drag recognizers compete.

### A reorderable list moves nothing until the drop

The requirement is a gap that opens where the item would land, without
rebuilding geometry per frame and without fighting the lazily built children.
Both fall out of one decision:

**The child list is not reordered until the drop.** During the drag the
dragged item stays exactly where it is in the list — hidden with
`node.visible = false`, the trick `IndexedStack3d` and the scrolling views
already use, which costs no layout — so its extent stays in the flow and *is*
the gap. Every other visible child is pushed forward or back by that extent
with `nodeOffset`, driven by a short per-item animation on the node tier.

That answers both halves at once. The lazy machinery is untouched because the
index-to-child map never changes during a drag: no `createChild`, no
`removeChild`, no rebuild. And nothing lands on the relayout path, because
every visible change in the list is a matrix write.

The insert index is read from the drag's position in scroll space against the
leading edges of the children the view currently holds — which is all the
view knows and all it needs, since the pointer is inside the window by
definition and anything further away is autoscroll's problem. At the drop the
list reports `(oldIndex, newIndex)` once, the caller reorders its data, and
one ordinary rebuild puts everything where it belongs.

Two consequences worth writing down. Items of unequal extent make the gap
exactly the dragged item's extent and nothing smarter, which is what Flutter
does and which jitters slightly; and because this package has **no
keep-alive** (the README says so), an item scrolled out of the cache during a
long drag is disposed — so the session must hold the payload and the
feedback, **never the source layout**. A drag whose source has been disposed
still drops correctly.

### Autoscroll is on a ticker, not on the move stream

A finger held still at the edge of a viewport sends no move events, so
autoscroll cannot be driven by moves. The session owns a `Ticker` — the
`Scroll3dController` already has a `vsync` and the same shape of ticker for
`animateTo` and `fling`, and the fling tests already drive one under
`tester.pump`, so this is proven ground.

When the drag's position on the current path's nearest `Scrollable3d` falls
within an edge band (`metrics.dp(50)` by default, stated in dp because it is
a Material figure), the ticker starts and moves the position by a velocity
proportional to how far into the band the pointer is, clamped, converted from
dp/s through the metrics. It stops at the band's edge, at the extent's end,
and when the drag ends.

Through `jumpBy`, not `applyUserOffset`: an autoscroll is not a user scroll,
it must not bounce past the end, and it must not fling on release. And
`stopAnimation()` first, so it does not fight a running simulation.

The detail that is easy to miss and expensive to find: **as the view scrolls
under a stationary pointer, the insert index changes.** So target resolution
has to be callable from the autoscroll tick and not only from a pointer
move — `Drag3dSession.tick()` re-runs the whole update against the last ray.

## The work

Take them in order; each phase is a thing that can be demonstrated.

- [x] **Phase 1 — the session and its seams.** `Drag3dSession`,
      `Drag3dTarget`, `Drag3dDetails`, `Drag3dEvent`, `Drag3dAnchor`, and
      `PointerSequence3d.addArenaMember`. `Layout3dPointer` gains a
      registry of live sessions keyed by pointer, and hands each one the
      fresh hit it already computes. No feedback and no components yet: a
      test drives a session by hand and asserts enter, leave and drop.
- [x] **Phase 2 — `Draggable3d<T>` and `DragTarget3d<T>`.** The drag gesture
      (immediate and long-press modes, axis, slop through the metrics), the
      overlay-hosted feedback on `originPlane`, `nodeOffset` tracking, the
      drop animation, and the single disposal path. The widget forms
      `SceneDraggable3d` and `SceneDragTarget3d` land with them, per the
      package convention.
- [ ] **Phase 3 — across surfaces.** The drag-aware pass in
      `Layout3dPointerGroup`: while a session is live, hit-test every member
      front to back rather than only the captured ones. A drag that starts on
      a panel and drops on a dialog in front of it.
- [ ] **Phase 4 — `Dismissible3d`.** The thinnest consumer, and the one that
      needs no drop target at all: an axis, a fraction threshold, a fling
      threshold, background and secondary background, and the resize-away
      that follows a confirmed dismiss. The resize is the one part of this
      plan that is genuinely an implicit animation rather than a node one,
      because an extent really does change.
- [ ] **Phase 5 — `targetPlane` anchoring.** Re-anchoring the feedback to
      the surface of a target on another plane, on target change only. The
      least certain phase; see *Where I am unsure*.
- [ ] **Phase 6 — `ReorderableList3d`.** The hidden source item, the
      node-tier gap, the insert-index arithmetic against the visible
      children, and `onReorder(oldIndex, newIndex)`. Built over
      `SliverList3d` so `ListView3d`'s placement is not written twice.
- [ ] **Phase 7 — autoscroll.** The ticker, the edge band, the velocity
      ramp, and `tick()` re-running target resolution. Last because it is the
      only piece that improves an interaction which already works without it.
- [ ] **Phase 8 — the render probe scenes**, and the documentation pass: a
      *Dragging things around* section in the package README, the counterpart
      rows for the four new components, and the depth-ordering trap above
      added to `docs/traps.md` under *Pointers*.

## What is testable headlessly, and what is not

Nearly all of it, which is the good news about a drag being arithmetic and
state. In `test/drag_test.dart`, with the `rayAt` helper the pointer plan
already added:

- the session state machine: enter, leave, re-enter, drop, cancel, and a
  target that refuses by type;
- the arena competition, both ways round — a drag inside a `ListView3d`
  claims the pointer past the slop and the list is left alone; a scroll past
  the slop first cancels the pending drag; a horizontal draggable and a
  vertical list each win on their own axis;
- the long-press mode under `tester.pump(duration)`, and the timer being
  cancelled by movement;
- feedback tracking: **`surface.needsFlush` is false for the whole drag**,
  which is this plan's version of the promise the animation plan made and the
  pointer plan kept — if a drag ever dirties layout, that test fails first.
  (As landed: false for every *move*, with the insertion of the feedback entry
  and its removal the two layout passes a drag unavoidably costs. See *What
  the original reasoning got wrong*.);
- disposal: the entry is removed exactly once on every ending, including a
  draggable disposed mid-drag and an overlay disposed under a live drag;
- cross-surface: two surfaces in a `Layout3dPointerGroup`, a drag starting on
  the back one and entering a target on the front one, and the assertion that
  the *captured* surface set did not change;
- the reorder arithmetic: insert index against uneven extents, the gap
  offsets as `nodeOffset` values, and that no `createChild`/`removeChild` call
  happens between the drag starting and the drop;
- autoscroll under `tester.pump`, including that the insert index moves while
  the pointer does not.

What needs a GPU, and so goes in `examples/render_probe` as new scenes:

- **`drag_feedback_depth`** — feedback lifted over the row it is over
  occludes it at the projected pixel. The claim is the same shape as
  `stack_depth`, and it is the one thing no arithmetic can check: that the
  lift actually wins the depth test.
- **`drag_feedback_detached`** — a detached feedback entry draws where
  `screenPointOf` says, overhanging the panel it came from, which is the
  visual difference between the two layers and the reason to offer both.

Both must be driven by the test's own clock — a drop animation settling on
its own schedule is the flake the render plan warns about.

## What the original reasoning got wrong

Written as phases 1 and 2 landed, so the next reader does not trust the parts
that turned out to be untrue.

- **"`surface.needsFlush` is false for the whole drag" is not quite
  achievable, and the test says so.** Putting the feedback into the overlay is
  a layout pass and taking it out is another, because an overlay entry is a
  child of a `Stack3d` and adding a child dirties layout. There is no way
  around either. What *is* true, and is what the test now asserts, is that the
  drag costs exactly those two and no more: `test/drag_test.dart` runs twenty
  moves through a live drag and asserts `needsFlush == false` after every one
  of them, with the insertion before the loop and the removal after it. The
  promise the plan meant to make survives; the sentence it made it in did not.
- **The feedback's initial placement needed arithmetic the plan did not
  mention.** An overlay entry is placed by the overlay's own alignment, which
  is nowhere near the box the drag was picked up from, so tracking the pointer
  by travel alone would make the card jump to the middle of the panel at the
  moment it is picked up. `Draggable3d._homeOver` computes the correction that
  covers the source — the source's centre taken into the feedback's own frame
  through both `worldTransform`s — and every move is that correction plus the
  travel. It is computed lazily, because the feedback has no size on the frame
  it is inserted, and cached once it succeeds, because the source may be
  disposed under a long drag.
- **`Drag3dSession` needed a terminal state the plan did not name.** A drop
  animation has to know whether the drag was taken and by what, and the
  session has already cleared its target list by the time anyone is told it
  ended. Hence `wasAccepted` and `acceptedBy`, which outlive the session, and
  `addEndListener`, which is the single path every ending goes through — an
  accepted drop, a rejected one, a cancel, a disposed draggable and a disposed
  pointer all arrive there.
- **A `Layout3d` does not promote through an interface it does not declare.**
  `if (layout is! Drag3dTarget)` leaves the static type at `Layout3d`, so the
  dispatch spells out an explicit cast — which is exactly what
  `Layout3dPointer._deliver` already does for `HitTestTarget3d`, and the
  reason was not obvious until it bit here too.
- **`DragTarget3d` is `HitTestBehavior3d.translucent`, not `opaque`.** A drop
  zone that swallowed every ray aimed at what is inside or behind it would
  break the buttons in the card it wraps. Flutter's `DragTarget` is
  translucent for the same reason. Ancestors are on the hit path regardless,
  so a list and the row inside it still both light up.

## Out of scope

- **Dragging between the layout tree and Flutter's widget tree.** A
  `Draggable` on a widget surface dropping onto a plane, or the reverse,
  needs a bridge between two pointer-id spaces and belongs with whatever
  finally reconciles `Layout3dPointer` and `ScenePointer`. They stay
  parallel, as the pointer plan decided.
- **Platform drag-and-drop** — files dragged in from the OS, or out of it.
- **Multi-item drags**, where a selection of several things is carried at
  once. The session is built around one payload; carrying a list *as* the
  payload works today, animating several sources does not.
- **Six-degree-of-freedom manipulation** — grabbing a piece of geometry and
  turning it in space. That is scene editing, not layout drag-and-drop, and
  it wants a different abstraction entirely.
- **Keyboard and screen-reader reordering.** Flutter's `ReorderableListView`
  publishes "move up" / "move down" custom semantic actions, and a catalogue
  will want them. `Semantics3d` takes Flutter's own `SemanticsProperties`,
  which carries `customSemanticsActions`, so this is probably a small
  addition rather than a plan — but whether the component behind
  `Semantics3d` forwards them has not been checked, and claiming
  accessibility that has not been verified is worse than not claiming it.
  Named here so the next reader knows it is missing.
- **Keep-alive**, which this plan works around rather than fixes.

## What the plans downstream of this one inherit

- **[The boxes still missing](2026_08_25_the_boxes_still_missing.md) closes**
  when phases 2, 4 and 6 land. Its `reason:` says in as many words that the
  dependency does not exist and that writing this plan is the next step;
  reread it when this one completes, and reread the README's roadmap
  (sections 1 and 2 and *What is next*), which says the same thing in three
  places.
- **`flutter_scene_material3d`** gets the four components and, more usefully,
  `Drag3dTarget` as a bare interface: a Material drop zone can implement it
  without inheriting a generic class, and its highlight is a
  `DecoratedBox3d.stateLayer` write, which is the repaint tier and dirties
  nothing.
- **`PointerSequence3d.addArenaMember` is general**, and it landed with
  `PointerSequence3d.startDrag` beside it: the seam a target reaches for once
  it has decided a press is a drag, which forwards to
  `Layout3dPointer.startDrag`. Both are on `PointerEvent3d` too, next to
  `addPointerToRecognizer`. Anything that wants to
  compete for a pointer without a Flutter recognizer — a knob, a slider, a
  rotation handle — uses it, and given that two of Flutter's four recognizers
  do not work in this build, that is likely to be most things.
- **The drag-aware pass in `Layout3dPointerGroup`** is the first thing that
  needs "test every surface, not the captured ones". The seam it wants is
  already there: `Drag3dSession.update(HitTestResult3d)` takes a path and asks
  nothing about where it came from, and `Layout3dPointer.drags` enumerates
  what is in flight on one surface. A group only has to walk its members and
  hand the winning path to the session it finds. Cross-surface focus
  traversal, which the pointer plan left open, needs the same walk.
- **The node-tier gap** in the reorderable list is the worked example of
  animating a list's arrangement without relayout. A staggered list-entry
  animation is the same technique.

## Where I am unsure

Said plainly, because a plan that pretends otherwise is worse than one that
names the question.

1. **Re-anchoring feedback to another surface's plane (phase 5) may not be
   worth what it costs.** Moving an overlay entry between overlays is an
   insert and a remove, which rebuilds the feedback subtree; animating the
   plane change means interpolating between two planes that may have
   different bases and different camera bindings, and there is no existing
   interpolation for that. It might be that the honest answer is "feedback
   stays on the plane it started on, always", and that a cross-surface drop
   simply lands. **What would settle it: build phase 3 first and drag between
   two angled surfaces in the gallery.** If it reads as wrong, phase 5 is
   worth the work; if it reads fine, phase 5 becomes an `Out of scope` entry.
2. ~~**Whether the arena accepts a member added during the down dispatch in
   every ordering.**~~ **Settled in phase 1**, by three tests under *the arena
   seam* in `test/drag_test.dart`. Three findings, and the third was not
   anticipated:

   * **A member may resolve long after `close`.** `close` ends the window for
     *adding*, not the arena. A member entered during the down dispatch and
     resolved twenty milliseconds later still rejects everyone else, so
     long-press-to-drag works exactly as the plan hoped.
   * **What ends the arena is the `sweep` at the up.** A resolution after that
     does nothing, silently — no throw, no callback. So the long-press timer
     has to be *cancelled* by the up rather than left to lose the arena, which
     is what `_Drag3dGesture.finish` does.
   * **A member cannot be added after `close` at all.** `GestureArenaManager.add`
     asserts `isOpen`. Everything that wants to compete has to enter during
     the down dispatch. This is why `_Drag3dGesture` joins the arena at the
     press even in long-press mode, half a second before it knows whether it
     wants the pointer.
   * **A member alone in the arena wins by default**, in a microtask, as soon
     as `close` runs. So *winning the arena* and *recognizing the gesture* are
     two different events and a recognizer with a threshold of its own must
     keep them apart: `acceptGesture` on `_Drag3dGesture` records a flag and
     starts nothing. Nothing in the plan said this, and getting it wrong would
     have made every draggable with no `Scrollable3d` under it start dragging
     on the press.
3. **The insert index with items of very unequal extent.** The arithmetic is
   easy; whether it *feels* right when a 40dp row is dragged past a 200dp
   card is not something a headless test can answer, and Flutter's own answer
   visibly jitters. Worth building the gallery page for before tuning.
4. **Whether autoscroll should go through the physics after all.** `jumpBy`
   is the right call for the ordinary case, but a drag held past the end of a
   bouncing list will simply stop dead rather than resist, which may read as
   broken. `applyUserOffset` would resist correctly and would also make the
   release fling, which is certainly wrong. There may be a third answer —
   applying the boundary conditions without the user-scroll bookkeeping — and
   `Scroll3dPhysics.applyBoundaryConditions` is public, so it is available if
   the simple version reads badly.
5. **The count of surfaces a drag search can afford.** One hit test per
   surface per move is fine for a panel and two dialogs, which is what an
   application has. It is not obviously fine for a scene with fifty
   layout surfaces, and nothing here has ever been profiled with more than a
   handful. If that becomes real, the fix is to test only the surfaces whose
   bounds the ray crosses — but that wants a broad-phase the group does not
   have, and inventing one now would be speculative.
