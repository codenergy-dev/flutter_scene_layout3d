---
status: completed
created_at: 2026-09-01T15:40:55Z
updated_at: 2026-09-02T12:00:00Z
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
- [x] **Phase 3 — across surfaces.** The drag-aware pass in
      `Layout3dPointerGroup`: while a session is live, hit-test every member
      front to back rather than only the captured ones. A drag that starts on
      a panel and drops on a dialog in front of it.
- [x] **Phase 4 — `Dismissible3d`.** The thinnest consumer, and the one that
      needs no drop target at all: an axis, a fraction threshold, a fling
      threshold, background and secondary background, and the resize-away
      that follows a confirmed dismiss. The resize is the one part of this
      plan that is genuinely an implicit animation rather than a node one,
      because an extent really does change.
- [x] **Phase 5 — `targetPlane` anchoring.** *Decided against, not built.*
      `Drag3dAnchor.targetPlane` stays in the enum, reserved, and behaves as
      `originPlane`; its dartdoc now says so and says why. The mechanism this
      plan named — moving the overlay entry to the target surface's overlay —
      is the wrong one, and the right one is a different design. See
      *What the original reasoning got wrong*.
- [x] **Phase 6 — `ReorderableList3d`.** The hidden source item, the
      node-tier gap, the insert-index arithmetic against the visible
      children, and `onReorder(oldIndex, newIndex)`. Built over
      `SliverList3d` so `ListView3d`'s placement is not written twice:
      `SliverReorderableList3d` extends it, and `ReorderableList3d` is the
      viewport around one, exactly as `ListView3d` is around a `SliverList3d`.
      `test/reorderable_test.dart` holds the seventeen tests, including the
      twenty-move `needsFlush` run and the assertion that the index-to-child
      map does not move between the lift and the drop.
- [x] **Phase 7 — autoscroll.** The ticker, the edge band, the velocity
      ramp, and `tick()` re-running target resolution. Last because it is the
      only piece that improves an interaction which already works without it.
      Landed as `lib/src/input/autoscroll.dart` — `Drag3dAutoscroll` for the
      settings and `Drag3dAutoscroller` for the engine — plus
      `Drag3dSession.tick`, `pathResolver` and `addResolveListener`. On by
      default for `SliverReorderableList3d`, off by default for `Draggable3d`,
      the same split Flutter makes.
- [x] **Phase 8 — the render probe scenes**, and the documentation pass: a
      *Dragging things around* section in the package README, the counterpart
      rows for the four new components, and the depth-ordering trap above
      added to `docs/traps.md` under *Pointers*. `drag_feedback_depth` and
      `drag_feedback_detached` are in `examples/render_probe`, both driving a
      real pointer inside the scene's own `build()` so the captured frame has
      a live drag in it.

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
  happens between the drag starting and the drop. (As landed, in
  `test/reorderable_test.dart`: all three, plus the drop's index pair, the
  long press competing with the list's own scroll, and a surface torn down
  mid-flight.);
- autoscroll under `tester.pump`, including that the insert index moves while
  the pointer does not. (As landed: the ramp, the band at both ends and the
  stop at the extent's end in `test/drag_test.dart` under *autoscroll*, over a
  `Draggable3d` in a `ListView3d`; and the insert-index claim in
  `test/reorderable_test.dart`, where the scroll, a flush and one more tick
  move the landing slot with the finger stationary throughout. Twelve tests.)

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

As landed, neither needed a clock at all, which is better: a scene builds its
surface, flushes it, and drives a real `Layout3dPointer` inside `build()`, so
what the harness captures is a static frame that happens to have a live drag
in it. Nothing settles because nothing is animating. See *What happened* for
the flush in the middle, and for why the detached scene could not be written
the way this section describes it.

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

- **The group needed the pointer to *stop* resolving, which nothing
  anticipated.** `Layout3dPointer.move` already hands its live session the
  fresh hit it computes, and that is exactly right for one surface and wrong
  for a group: the session would be resolved twice a move, once against a path
  that stops at the surface the press captured. A target on the panel *behind*
  the dialog the drag has wandered onto would then enter and leave on every
  single move. Hence `Layout3dPointer.resolvesDrags`, which a
  `Layout3dPointerGroup` sets false on every pointer it holds and restores
  when it hands one back. Only `move` and `up` are gated; the resolution
  `startDrag` does is not, because a long-press drag is recognized by a timer,
  with no pointer event to hang a group pass on.
- **`Layout3dPointerGroup.up` has to resolve before it dispatches**, not
  after: the up is what drops the session, so by the time
  `Layout3dPointer.up` returns the drag is over and its targets are gone. The
  same fact, from the other end, is why the group's pass in `move` runs
  *after* the dispatch — a drag recognized by that very move has to resolve
  against the path the same event found.
- **The drag search reuses what the captured surfaces already computed.**
  `Layout3dPointer.move` hit-tests afresh before it dispatches, so its
  `lastHit` *is* this ray's answer for that surface; the walk only pays a new
  hit test for the surfaces that did not hold the press. A drag across a panel
  and a dialog therefore costs one extra hit test a move, not two.
- **A `Dismissible3d` has three slots and the widget layer can only mirror a
  list.** `adoptLayoutChildren` knows `Layout3dWithChildMixin` and
  `Layout3dWithChildrenMixin` and nothing else, so hand-rolled named slots
  would have made `SceneDismissible3d` impossible without changing the
  framework. The slots are therefore one ordered child list — child,
  background, secondary background — with two rules the constructor asserts: a
  background needs a child, and a secondary background needs a background.
  Flutter's `Dismissible` asserts the second one already, for its own reasons.
- **The resize does not resize the child.** Shrinking the box by laying its
  subtree out smaller every tick is the expensive reading of "an extent really
  changes", and it is not the one this needs: the row has already been carried
  off the box and hidden by then. So the child is laid out once, with the
  *same* constraints on every tick — an identical layout call is one the child
  skips — and only the dismissible's own extent shrinks. The parent relayouts,
  which is the point; nothing under the swiped row re-measures a string.
  The size it reports is deliberately not re-constrained, so a dismissible
  under a *tight* main-axis constraint closes up instantly rather than
  smoothly. There is no room for it to do anything else.
- **`Dismissible3d.offset` was not available.** `Layout3d.offset` is where the
  parent put the box, and a getter of that name on a box is already spoken
  for; the swipe's own displacement is `swipeOffset`.
- **The velocity tracker moved out of `pointer.dart`.** A dismissal can be won
  by speed rather than by distance, and the scroll drag's `_DragVelocity` was
  already the right arithmetic — Flutter's own `VelocityTracker` cannot be
  used here at all, for the reason its dartdoc gives. It is now
  `Drag3dVelocityTracker` in `input/velocity.dart`, internal to the package,
  used by both.
- **A `Ticker` started inside a frame takes that frame's timestamp as its
  start.** So the tick after it reports real elapsed time rather than zero,
  and a test that pumps the fly-out and the resize back to back sees the
  resize already under way. Worth knowing before writing the next animated
  test; it cost a wrong assertion here.

### Written as phases 5 and 6 landed

- **Phase 5 is not worth what it costs, and the mechanism this plan named is
  the wrong one.** `Drag3dAnchor.targetPlane` stays in the enum, reserved,
  behaving as `originPlane`, and its dartdoc now carries the reasoning so a
  reader who reaches for it is not left guessing. Three findings, in order of
  how much they matter:

  * **Moving the entry between overlays is two layout passes and a rebuild**,
    in the middle of the one interaction the whole design keeps off the
    relayout path — and with no hysteresis anywhere, a drag that wanders back
    and forth across the boundary between two surfaces pays them again on
    every crossing. "On target change, never per move" sounds bounded until
    you notice that a target change is a thing the finger can do at 120Hz.
  * **A rebuilt feedback has no size on the frame it arrives**, which is
    already recorded below as the reason `_homeOver` is computed lazily. At
    the *start* of a drag nobody sees it. In the middle of one it is a visible
    pop to the overlay's own alignment and back.
  * **Where the card should sit on the new plane is under-determined.** The
    grab offset — where in the card the finger is holding it — is measured on
    the origin plane and cannot be carried onto a plane with a different
    basis; the only well-defined answer is to centre the feedback on the ray's
    hit point on the target, which is a snap, not a re-anchoring. That is the
    "two planes with different bases" problem this plan flagged, and it does
    not go away by being renamed.

  **The design that would work is a different one**: a
  `OverlayLayer3d.detached` feedback owns a surface of its own, so re-anchoring
  is *re-aiming that surface's plane node* — a node write, no rebuild, no
  layout pass, and a rotation that interpolates. That is worth building if the
  gallery ever says the feature is wanted. It is not what this plan described,
  and building the described version would have shipped the worse of the two.
  The experiment that settles whether it is wanted at all is still the one
  named below, and it still needs a GPU.

- **Hiding the dragged item takes the list out of reach of the ray, exactly
  where it matters.** `Layout3d.hitTestChild` skips children whose node is
  hidden — "nothing invisible is pointable" — so the gap a reorder opens is a
  hole in the hit path, and the pointer spends most of a drag in it. Without
  something answering there the drag is over nothing the moment it stops being
  over a *neighbour*, and the gap sticks. Hence
  `SliverReorderableList3d.hitTestSelf`, which answers on the list's own
  account while and only while a reorder is live. Nothing in the plan
  anticipated it, and it is the one line without which none of this works.

- **`Layout3d.offset` and the hit point are already in the same frame, and
  that is what makes the gap stable.** Hit testing deliberately ignores
  `nodeOffset`, so the point that reaches the drop target is measured against
  the items where *layout* put them, not where the slide animation has moved
  them; and `child.offset` is the same unshifted slot. So the insert index is
  read off the leading edges of the laid-out slots, the answer does not change
  because something slid aside to reveal the gap, and the arithmetic needs no
  hysteresis. With equal extents the index does not oscillate at all.

- **The end of a reorder has to be the session's, not the draggable's.** A
  caller who reorders its data inside `onReorder` and calls `refresh` disposes
  every built item, the one under the finger included — and a disposed
  `Draggable3d` clears its own session before the end listeners run, so its
  `onDragEnd` never fires. The list therefore registers on
  `Drag3dSession.addEndListener` itself. The plan's own note that "the session
  must hold the payload and the feedback, never the source layout" is the same
  fact one step further on: nothing that has to survive the drop may hang off
  the item.

- **A reorder costs a third layout pass, at the end, and it should.** The
  dragged item is hidden, and what an item's visibility ought to be is a
  question only the window can answer — so the end of a drag calls
  `markNeedsLayout` rather than guessing. It is free: the feedback is coming
  out of the overlay on that same frame, which is a layout either way. The
  twenty-move assertion is untouched.

- **The dragged item has to outlive the window.** Disposing it would dispose
  the `Draggable3d` wrapped around it, which cancels the session, which ends
  the drag — the card would vanish mid-flight. `releaseOutside` is therefore
  widened to reach the dragged index. It costs nothing today, because a drag
  holds the pointer and the window cannot move under it; **phase 7 is what
  makes it matter**, and phase 7 is also what makes the kept run long. If that
  becomes real the fix is a release-with-exception in
  `Layout3dBuiltChildrenMixin`, not a wider range.

- **There is no `SceneReorderableList3d`, and there cannot be one without a
  new seam.** The list wraps every item in a `Draggable3d` of its own — which
  is what buys the whole of phase 2's machinery for free and is why this plan
  did not need a fourth hand-rolled recognizer. But a wrapped item is not what
  the child manager built, and the declarative layer's contract is that
  `Layout3dChildManager.removeChild(index, child)` is handed back the very
  layout `createChild` returned. Wrapping breaks it. The ways out are a hook
  in `Layout3dBuiltChildrenMixin` that lets a view adopt what the manager
  built (and a `removeChild` that unwraps), or a fifth recognizer on the list
  itself so items need no wrapper at all — which is also the design that would
  make an explicit child list possible. Neither is a line of this plan, and
  both are worth more thought than a widget form deserves on its own.

- **`onReorder`'s `newIndex` is where the item ends up.** Flutter's
  `ReorderableListView` reports an index measured *before* the item is taken
  out, so a caller who moved something down the list has to decrement it
  first; that off-by-one is the most reported confusion about that widget and
  there is nothing to be gained by inheriting it. `Reorder3dCallback` says so
  in as many words, because a reader will assume Flutter's semantics.

- **A reorderable list has no explicit-children constructor.** `onReorder`
  hands back a pair of indices into the caller's data and expects the next
  build to reflect them, so the list has to be a function of that data to mean
  anything at all. `itemCount` and `itemBuilder`, and `refresh` when the data
  changes. Supporting a child list as well would mean mapping the caller's
  boxes to the wrappers around them through `insert`, `remove`, `syncChildren`
  and the `children` getter — four places to get an index wrong, in aid of a
  spelling that cannot express what the callback is for.

## What happened

All eight phases are closed: seven built, and phase 5 decided against and
written up in place of being built. The package suite went from 849 tests to
861; `dart analyze` is clean from the repository root.

**The premise held.** A drag really is arithmetic and state, and nearly all of
it was pinned down headlessly — the session's state machine, the arena
competition both ways round, the long-press timer, the cross-surface walk, the
reorder arithmetic, and autoscroll under `tester.pump`. Two claims needed a
GPU and are the two new render probes.

**The seam under the generics was the right call and paid twice.**
`Drag3dTarget` is non-generic, so `SliverReorderableList3d` could *be* a drop
target for its own items without inheriting `DragTarget3d<T>` — which is what
made a reorderable list a thin layer over phase 2 rather than a second design.
`flutter_scene_material3d` inherits the same seam.

**Nothing in a drag reaches the relayout path except the two passes it cannot
avoid**, and one that phase 7 adds on purpose. Inserting the feedback into the
overlay is a layout and taking it out is another, because an overlay entry is a
child of a stack; a reorder adds a third at the end, to answer the question of
what an item's visibility should now be. Autoscroll relayouts by definition,
because the window really did move. Everything else — the feedback tracking the
pointer, the gap opening, a dismissible sliding, the items sliding aside — is a
matrix write, and `test/drag_test.dart` runs twenty moves asserting
`needsFlush` is false after each one.

**`PointerSequence3d.addArenaMember` turned out to be the most reusable thing
here.** Two of Flutter's four recognizers do not work in this build, so
anything that wants to compete for a pointer — a knob, a slider, a rotation
handle — needs this seam, and it is general: it marks the sequence contested
and enters the global arena on the private pointer id, and nothing about it is
drag-specific.

The two gaps left open are named rather than hidden: there is no
`SceneReorderableList3d` and no explicit-children constructor for the list
(both want a child-manager seam that does not exist), and
`Drag3dAnchor.targetPlane` is reserved because the mechanism this plan named
for it is the wrong one. Both are written up below and in the dartdoc a reader
would reach for first.

[The boxes still missing](2026_08_25_the_boxes_still_missing.md) is
`completed` as of this plan: its last item was these four components, and the
readiness overview's *Where to pick up* item 2 — "that plan has not been
written" — is no longer true and has been corrected.

### Written as phases 7 and 8 landed

- **Autoscroll needed a listener, not a poke, and the reason is an ordering
  nobody would guess.** The obvious wiring is for `Draggable3d` to nudge its
  autoscroller from the same place it tracks the feedback, inside
  `handleEvent`. That is one move too early: `Layout3dPointer.move` dispatches
  along the captured path *first* and resolves the session *after*, so
  anything reading `Drag3dSession.lastHit` from inside a `handleEvent` is
  reading the previous move's answer. A finger that arrives at the edge of a
  list and then stops would never start it scrolling — which is precisely the
  case autoscroll exists for. Hence `Drag3dSession.addResolveListener`, which
  fires after every resolution and is what the autoscroller listens to.
- **The tick's re-resolution needed a seam, and `refresh()` alone was not it.**
  `refresh()` re-reads the path the drag last saw, which is exactly enough for
  a reorderable list — it reasons in *scroll* coordinates, so an unmoved local
  position plus a changed scroll offset is a changed insert index, with no hit
  test at all. It is not enough for a plain `DragTarget3d` in a scrolling
  view, where the rows under the ray really did change. So
  `Drag3dSession.tick` goes through a `pathResolver` when one is installed:
  `Layout3dPointer` installs its own hit test, gated on `resolvesDrags` the
  same way `move` and `up` are, and `Layout3dPointerGroup` installs its
  front-to-back walk instead. Getting that gate wrong would not have been a
  missing feature but a wrong answer.
- **A ticker that runs for the whole drag is not affordable, for a reason that
  has nothing to do with cost.** It is cheap — one walk of the hit path a
  frame. But a drag would then never settle, and `pumpAndSettle` would never
  return. The autoscroller starts a ticker when the drag enters the band and
  stops it when it leaves, which is what the plan said, and now there is a
  second reason for it.
- **The first tick has to move nothing.** `Ticker` takes the timestamp of the
  frame it started in as its zero, which this plan already recorded for the
  dismissible's fly-out. For an animation that is a wrong assertion; for
  autoscroll it would be a visible jump at the instant the finger crossed into
  the band. So the first callback records the clock and scrolls nothing.
- **The clamp is by hand, and `jumpBy` alone would not have done it.** The
  plan chose `jumpBy` over `applyUserOffset` so a release does not fling, and
  that was right. What it missed is that `jumpBy` still goes through
  `Scroll3dPhysics.applyBoundaryConditions`, and a bouncing physics *permits*
  overscroll — so a drag held at the end of a bouncing list would have drifted
  off the content for as long as it was held. The autoscroller clamps the
  target to the scroll range itself before jumping. That settles open question
  4 in the conservative direction: autoscroll never overscrolls, and a drag
  held past the end stops dead rather than resisting.
- **The plan's sentence about `screenPointOf` was right, and the first attempt
  to "correct" it was wrong.** The plan said the detached scene would show
  feedback "draws where `screenPointOf` says", and it does. The near-miss:
  `Layout3d.worldTransform` undoes a box's **own** `nodeOffset`, so it looks
  as though a projection cannot see a node-tier move — but an *ancestor's*
  offset stays in `globalTransform` and therefore in the projection, and
  `Draggable3d` writes the offset onto the `IgnorePointer3d` it wraps the
  feedback in, which is above anything a caller can name. So
  `screenCenter('feedback')` follows the drag exactly.

  The first version of the probe reconstructed the drawn point from
  `box.nodeOffset` instead, through a `drawnCenterOf` helper. On a probed
  feedback box that offset is always zero, so the helper returned the
  laid-out point and the assertion compared a number with itself: it failed on
  the GPU with a distance of exactly 0.0. The helper is gone, and the scene
  compares the feedback against the card left behind instead. Verified
  headlessly on the way: the feedback's projected centre is 429 px with the
  panel's edge at 388, and in the in-plane scene it lands on row 2's centre to
  the pixel.

- **A probe scene's screen arithmetic can be checked without a GPU.**
  `Layout3dScreenProjection` is camera maths and runs headlessly, so a scratch
  test that builds the scene, drives the drag and prints `screenCenter` under a
  `PerspectiveCamera` settles where everything lands before the suite is run.
  Both bugs above — and a third, that the basis mirrors x on its way to the
  screen, so "carried toward larger layout x" is not reliably "further right in
  pixels" — were found that way rather than by a second GPU run. The detached
  scene's overhang assertion compares against both panel edges for that reason.

- **The render probe earned its keep: it found a phase 2 bug that every
  headless test had agreed with.** `Draggable3d._homeOver` corrected the
  feedback's position in all three axes, so the feedback landed exactly on the
  source box — cancelling `OverlayLayer3d.lift` and leaving a picked-up card
  *coplanar* with the rows it was dragged over. `lift` had no effect on drag
  feedback at all, at any value. Nothing arithmetic could see it: the card was
  in the right place on the plane, which is what every drag test checked, and
  the depth test between two surfaces at the same z is a coin toss. It showed
  up exactly as coplanar geometry always does here — `drag_feedback_depth`
  passed on one GPU run and failed on the next, the same signature
  `stack_depth`'s own comment records from when that scene was written.

  The fix is one line and the reasoning behind it is the useful part: **the
  correction exists to cancel the overlay's own alignment, which is a question
  about the plane.** Depth already has an answer, and it is the layer's. So
  `_homeOver` now returns `Offset3d(home.x, home.y, 0)`, the feedback keeps
  whatever depth the overlay gave the entry, and a card stands a full lift in
  front of what it is carried over. `test/drag_test.dart` pins it headlessly —
  "keeps the overlay lift the layer asked for" — now that there is something
  to pin, and `docs/traps.md` records the consequence a caller has to know:
  the default lift is eight dp, which is a depth-buffer separation rather than
  a distance, so rows with real thickness want a bigger one.

  Worth saying plainly, because it is the argument for this kind of test: the
  probe was written to check a claim everyone believed, and the claim was
  false.

- **A sparse scene fails the floor even when it is correct.** The first
  detached scene used a two-unit panel and a camera pulled back to z = 9 so the
  overhang stayed in frame, and covered 1.8% of the frame against the 2% floor
  every scene has to clear. The fix is bigger geometry at the ordinary camera
  distance rather than a lowered floor: a lowered floor is a weaker claim, and
  the floor is what catches "nothing drew".
- **A probe scene can hold a live interaction, and the flush in the middle is
  the step that is easy to miss.** Both drag scenes build their surface, flush
  it, and drive a real `Layout3dPointer` inside `build()`. The press and the
  first move insert the feedback; an overlay entry has no size on the frame it
  is inserted, so `Draggable3d` cannot yet compute the correction that covers
  the card; a flush gives it one; and only the *second* move writes the node
  offset the probe is there to look at. This is the same lazy-`_homeOver`
  fact recorded above, seen from the harness side.

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
  places. **All three of those phases have now landed**, so the dependency is
  discharged and only this plan's own tail — autoscroll and the documentation
  pass — stands between that plan and `completed`. Whoever closes phase 8
  closes it. **Closed**, and so are all three README statements, along with
  the readiness overview's *Where to pick up* item 2, which still said this
  plan had not been written.
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
   Phase 3 has landed, so the experiment is now available and nothing else
   blocks it: a cross-surface drop works today with the feedback left on the
   plane it was picked up from, and whether that reads as wrong is a question
   only the gallery can answer.

   **Answered as far as it can be without one: it does not ship.** Not because
   the question was settled, but because the *mechanism* was — it is the wrong
   one, for three reasons written up under *What the original reasoning got
   wrong*. The question of whether the feature is wanted is still open and
   still needs the gallery; if the answer turns out to be yes, build the
   detached-surface version described there rather than the one above.
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
   Half of it turned out not to be a question: because hit testing ignores
   `nodeOffset`, the index is read against the *unshifted* slots and cannot
   oscillate with what has slid aside — see *What the original reasoning got
   wrong*. The rule that landed is "the last leading edge the pointer passed",
   and the part still open is only how that reads when the extents differ by a
   factor of five.
4. **Whether autoscroll should go through the physics after all.** `jumpBy`
   is the right call for the ordinary case, but a drag held past the end of a
   bouncing list will simply stop dead rather than resist, which may read as
   broken. `applyUserOffset` would resist correctly and would also make the
   release fling, which is certainly wrong. There may be a third answer —
   applying the boundary conditions without the user-scroll bookkeeping — and
   `Scroll3dPhysics.applyBoundaryConditions` is public, so it is available if
   the simple version reads badly.

   **Answered conservatively, and the question was slightly wrong.** `jumpBy`
   does *not* stop dead at the end of a bouncing list on its own: it goes
   through `applyBoundaryConditions`, and a bouncing physics permits
   overscroll, so a drag held at the edge would have drifted off the content
   for as long as it was held. The autoscroller therefore clamps the target to
   the scroll range itself before jumping, which makes "stops dead" true by
   construction rather than by accident. Whether *resisting* reads better is
   still open, and still a question for the gallery.
5. **The count of surfaces a drag search can afford.** One hit test per
   surface per move is fine for a panel and two dialogs, which is what an
   application has. It is not obviously fine for a scene with fifty
   layout surfaces, and nothing here has ever been profiled with more than a
   handful. If that becomes real, the fix is to test only the surfaces whose
   bounds the ray crosses — but that wants a broad-phase the group does not
   have, and inventing one now would be speculative.
