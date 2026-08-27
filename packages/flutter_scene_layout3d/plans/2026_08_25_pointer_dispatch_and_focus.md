---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-27T13:45:00Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
---

# From a hit test to an event system

Hit testing here is finished and good. What comes after it is missing: there
is no way for a box to *receive* an event, so there is no tap, no hover, no
press state, no focus — and every interactive Material control is defined by
those four.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).
Drives the state layers in
[size-driven geometry](2026_08_25_size_driven_geometry.md); its focus half
needs `ensureVisible` from
[animation and scroll physics](2026_08_25_animation_and_scroll_physics.md).

## What exists today

[hit_test.dart](../lib/src/hit_test.dart) is the hard part and it is done: a
`Ray3d` walks the tree, each box clips the ray range to its own extent so a
child scrolled out of a list is unreachable, `HitTestResult3d.path` comes back
ordered deepest-first with a `localPosition` per entry, and
`firstOf<T>()`/`entryOf<T>()` find a typed ancestor.

[Layout3dPointer](../lib/src/input/pointer.dart) is where it stops. It does
exactly one thing: on `down` it looks for a `Scrollable3d` in the path, and
`move` drags it. A press that hits a button records `lastHit` and nothing
else. There is no dispatch, no recognition, no hover, no capture beyond the
scroll drag, and one pointer at a time.

Also relevant: `hitTestSelf` defaults to false, so a box that merely arranges
others is not a target — which means the padding around a button's label is
not tappable. `IgnorePointer3d` and `AbsorbPointer3d` exist.

## The design

The chain is **hit test → dispatch → recognition → state**. The first exists;
build the other three, in that order, and keep them separable.

### Dispatch

Mirror Flutter's shape, because `HitTestResult3d.path` is already the same
shape as `HitTestResult.path`:

```
abstract class HitTestTarget3d {
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry);
}
```

The pointer walks the recorded path deepest-first and calls `handleEvent` on
every layout that implements it. `PointerEvent3d` wraps Flutter's
`PointerEvent` — reuse the class, do not reinvent it — and adds the ray, the
entry, and the local position on the target's own frame.

**Capture is by path, not by box.** The path is recorded at `down` and reused
for `move`/`up`/`cancel`, which is what already keeps a scroll drag alive
when the finger leaves the list, and is the same rule Flutter uses.

### Behaviour

Add `HitTestBehavior3d { deferToChild, opaque, translucent }` and a wrapper
box that applies it, so a component can claim its whole box including padding.
Today the only self-answering boxes are `NodeBox3d` and the scrolling views;
a button made of a decoration and a label answers nothing.

### Recognition: reuse Flutter's arena

The observation that makes this cheap: a `GestureRecognizer` needs a pointer
id and a 2D position, nothing more. A hit on a box gives both — the entry's
`localPosition` projected onto the box's own plane is a perfectly good 2D
position, and it is *better* than a screen position, because it is already
perspective-corrected, which is the same insight `Layout3dPointer`'s drag is
built on.

So: synthesize Flutter `PointerEvent`s in the target's plane coordinates and
feed them to Flutter's own `GestureArenaManager`, `PointerRouter` and
recognizer classes (`TapGestureRecognizer`, `LongPressGestureRecognizer`,
`DragGestureRecognizer`, …), one router and one arena per surface. Material's
gesture semantics then match Flutter's exactly, for free, including the
disambiguation between a tap and a drag that a `ListTile` inside a
`ListView3d` needs on the first day.

The risk to check early: Flutter's recognizers assume a global pointer-id
space and `GestureBinding.instance.pointerRouter`. Owning a private router
and arena per surface is supported by the classes' public constructors, but
verify it before building on it — this is the one assumption the whole
approach rests on.

### Hover, enter and exit

A per-move pass that diffs the current path against the previous one and
emits enter/exit along the difference, the same thing `MouseTracker` does.
This is what drives the hover state layer. It needs the pointer to be fed
`move` events even when nothing is pressed, which today's API does not expect;
add `hover(Ray)` alongside `down`/`move`/`up`.

### Focus

Two halves, and only the second is novel.

- **The node graph is Flutter's.** `FocusNode`, `FocusScope`, `Shortcuts` and
  `Actions` all work in the declarative layer already, because these are real
  Flutter widgets. A `Focus3d` box ties a `FocusNode` to a layout so that a
  focus highlight can be drawn and so that `ensureVisible` can find the box.
- **Directional traversal is not.** Flutter's directional policy reasons about
  `Rect`s. Here a box has a `Size3d` and an offset in a 3D frame. The first
  cut is to project candidate boxes onto the surface plane and reuse the 2D
  policy; genuinely 3D traversal (and traversal *between* surfaces, which
  [overlays](2026_08_25_overlays_and_layered_surfaces.md) will need) is an
  open question this plan names and does not answer.

### Several pointers

`Layout3dPointer` holds one drag. Key the state by pointer id so two fingers
on two lists work, and so a VR controller and a mouse can coexist. While
there: `flutter_scene`'s
[ScenePointer](../../flutter_scene/lib/src/scene_pointer.dart) already solves
capture, hover state, layer masks and occlusion for widget surfaces. Decide
explicitly whether `Layout3dPointer` is built on it or stays parallel, and
write down the answer — two pointer abstractions in one scene with different
capture rules is a trap for users.

## The work

- [x] **Phase 1 — events and dispatch.** `PointerEvent3d`, `HitTestTarget3d`,
      path capture, `Listener3d`.
- [x] **Phase 2 — behaviour.** `HitTestBehavior3d` and its box.
- [x] **Phase 3 — recognizers.** ~~Private router and arena per surface~~ —
      the global binding, on a private pointer id; the plane-coordinate
      synthesis, in logical pixels; `GestureDetector3d` with tap, double tap,
      long press and pan. The arena assumption was verified first, and it was
      wrong; see below.
- [x] **Phase 4 — hover.** `hover(Ray)`, path diffing, enter/exit, and
      `exit()` for the pointer leaving the surface altogether.
- [x] **Phase 5 — focus.** `Focus3d`, the surface's focus scope, and the
      projected directional policy in `Focus3dTraversal`.
- [x] **Phase 6 — multiple pointers**, and the `ScenePointer` decision (they
      stay parallel; the reasoning is in `Layout3dPointer`'s dartdoc).

Also landed, which the plan did not ask for:

- [x] **`TapTarget3d`**, Material's 48dp minimum touch target. It belongs to
      this plan because it is where the unit contract meets input, and every
      icon button in the catalogue needs it. Unlike Flutter's `_InputPadding`
      it spends no layout: the box stays its child's size and its neighbours
      stay put, and it simply answers a ray that passes within half the
      shortfall of its extent.
- [x] **The widget forms**: `SceneListener3d`, `SceneGestureDetector3d`,
      `SceneHitTestArea3d`, `SceneTapTarget3d`, `SceneFocus3d`.
- [x] **`Layout3dOwner.focusScope`**, next to `basis`, `metrics` and
      `painters`, for the same reason those are there.

## Tests

54 new tests across `test/pointer_test.dart` (26), `test/gesture_test.dart`
(14) and `test/focus_test.dart` (14), plus a `rayAt(surface, point)` helper in
`test/support.dart` that aims a world ray at a named point on the plane, so an
input test needs no camera.

- [x] A synthesized ray taps a box three levels down; the path order is
      deepest-first; an `AbsorbPointer3d` in between takes it instead.
- [x] `opaque` behaviour makes a padded button's padding tappable;
      `deferToChild` does not. `translucent` hears the pointer and lets the
      ray through.
- [x] A drag that starts on a list still scrolls it — the existing tests in
      `hit_test_test.dart` are untouched and still pass, which was the point.
- [x] Tap versus drag disambiguation on an item inside a `ListView3d`, both
      ways round, including that a drag under the touch slop is still a tap
      and that a drag past it lands the whole travel rather than lagging by a
      slop.
- [x] Hover enter/exit sequences across a boundary, including leaving the
      surface entirely, and the outermost-first order of enter.
- [x] Two pointers driving two scrollables independently, and hovering
      independently.
- [x] A hidden node receives nothing.
- [x] A press and a hover drive `DecoratedBox3d.stateLayer` with
      `surface.needsFlush` false throughout, which is the promise that plan
      made and this one consumes.

## What the plan got wrong

Written down as it was found, because the next reader will believe the design
section above otherwise.

1. **A private router and arena per surface is not possible.** This was the
   named risk and it did not survive contact:
   `OneSequenceGestureRecognizer.startTrackingPointer` and
   `_addPointerToArena` reach for `GestureBinding.instance` directly
   (`recognizer.dart` lines 537 and 518), and a `GestureArenaTeam` only defers
   the same call. There is no seam. So recognition uses the **global** router
   and arena, and what is private instead is the **pointer id**: every
   sequence allocates one from `1 << 24` up, far above anything the engine's
   pointer converter reaches, so a gesture on the plane cannot collide in the
   arena with the real pointer the widget tree is still handling. The cost is
   that a tree with a `GestureDetector3d` in it needs Flutter's binding
   initialized. Hit testing, dispatch, hover and the plain scroll drag still
   need nothing, which is why the existing tests did not have to change.
2. **The synthesized positions need a unit, and it is the logical pixel.**
   The plan said "the target's plane coordinates" and stopped there. Plane
   coordinates are world units, and every constant Flutter's recognizers are
   tuned with — `kTouchSlop` at 18, `kDoubleTapSlop`, the drag thresholds —
   is in logical pixels. Eighteen world units is most of a panel: a pan would
   never start. The events are synthesized in dp, through
   `Layout3dMetrics.unitsPerLogicalPixel`, and that is what makes "reuse
   Flutter's recognizers" true rather than nearly true.
3. **The arena resolves an uncontested pointer on a microtask.**
   `GestureArenaManager.close` schedules `_resolveByDefault`, so a sole member
   cannot win synchronously. A scroll drag routed through the arena therefore
   could not start on the first `move` of a press, which is exactly what the
   existing `Layout3dPointer` tests pin and what a list under a finger has
   always done. The resolution: **a scrolling view joins the arena only when
   the press is contested** — when something armed a recognizer while the down
   was being dispatched. Uncontested, it drags immediately and touches no
   binding at all; contested, it waits out the touch slop, claims the pointer,
   and cancels the pending tap. `PointerSequence3d.addPointerToRecognizer` is
   how a target says it is competing, and it is the reason that flag exists.
4. **The down event has to be routed as well as dispatched.**
   `GestureBinding.handleEvent` routes *every* event, the down included, and
   several recognizers learn where the press was only from the routed down
   (`LongPressGestureRecognizer` sets `_initialButtons` there, not in
   `addPointer`). Dispatching to the path and skipping the router looked
   right and quietly broke half the recognizers.
5. **Flutter's directional policy cannot be reused, only its idea.**
   `DirectionalFocusTraversalPolicy` reads `FocusNode.rect`, which comes off
   the `RenderObject` behind the node's `BuildContext`; a box on a plane has
   neither. `Focus3dTraversal` projects each candidate's eight corners onto
   the surface plane and ranks the resulting rectangles itself. Two details
   the 2D version hides had to be decided here: direction is judged centre to
   centre, because two boxes in a row *touch* and an edge-gap rule finds
   nothing to the right of anything; and sharing an edge is not sharing a
   band, or the box diagonally below counts as "down".
6. **A `FocusNode` cannot be parented without a `BuildContext`** through the
   obvious route: `FocusAttachment.reparent` asserts `_node.context != null`
   before it looks at the parent it was handed. The way through is
   `FocusScopeNode.requestFocus(node)`, which parents an orphan node and
   focuses it in one go — which suits a box that only ever parents itself when
   it is being focused anyway. `node.attach(null)` is still needed, because
   `FocusAttachment.detach` is the only public way back *out* of the tree.
7. **`Listener3d` folds `MouseRegion`'s enter and exit in.** Flutter splits
   them because it has a separate mouse-tracking pass; here hover is a walk of
   the same path everything else is dispatched along, so one box serves both
   and a component wires four callbacks on one object instead of two.

## What this environment got wrong, which is not the plan's fault

`LongPressGestureRecognizer` never fires in this Flutter build, and
`DragGestureRecognizer` delivers `onStart` but never `onUpdate` or `onEnd`.
Both were reproduced with **no code from this package involved**: a plain
`GestureDetector(onLongPress: ...)` in a widget tree under
`tester.longPress` counts zero presses, and a bare `PanGestureRecognizer`
driven by hand through `GestureBinding.instance.pointerRouter` logs `start`
and nothing after it. `TapGestureRecognizer` is unaffected, which is why the
tap tests — including the arena disambiguation, which is the load-bearing one
— are real.

`GestureDetector3d` wires all four recognizers up regardless, because what
this package owes them is the events, and it delivers those; the tests assert
what can be asserted (the recognizer is armed and in `possible` state, the pan
starts at the right point in the right units) and say in a comment why they
stop there. Worth re-checking on the next SDK bump.

## Out of scope

Text selection gestures, drag-and-drop between surfaces, IME, and the cursor
appearance (which is a platform concern the host `SceneView` owns).

## What the plans downstream of this one inherit

- **Overlays** ([overlays and layered surfaces](2026_08_25_overlays_and_layered_surfaces.md))
  need a modal barrier and a focus trap, and neither is written here. What is
  here to build them on: a barrier is an `AbsorbPointer3d` (it answers the hit
  itself and never asks its children) or, if it also wants the events, a
  `Listener3d`/`HitTestArea3d` with `HitTestBehavior3d.opaque` — opaque stops
  the ray dead, which is exactly what "nothing behind this is reachable"
  means, and `translucent` is the setting that deliberately does not. What
  does **not** exist yet is a barrier across *surfaces*: `Layout3dPointer`
  tests one surface, so a `Layout3dPointerGroup` that walks surfaces front to
  back has to decide that a surface which answered stops the walk. Focus is
  the same shape: every `Focus3d` on a surface hangs under that surface's
  `Layout3dOwner.focusScope`, so trapping focus in a modal means giving the
  modal a scope of its own and pointing the traversal at it —
  `Focus3dTraversal`'s methods all take the root to search from, which is the
  hook for that, and `FocusScopeNode` already knows how to hold a
  `focusedChild`. Nothing here reads `FocusManager.instance.highlightMode`
  either; a Material focus ring should.
- **Animation and scroll physics** get `Layout3dPointer.draggedScrollableFor`
  and per-pointer sequences to hang a velocity tracker off; the drag applies
  its delta in one place (`_Sequence._apply`), which is where a fling would be
  started from.
- **Size-driven geometry** is consumed rather than extended: pressed, hovered
  and focused all drive `DecoratedBox3d.stateLayer`, and the tests pin that
  none of them dirties layout.
