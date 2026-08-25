---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
---

# Animation, and the scroll physics that is missing with it

Nothing in this package animates. Material is mostly animation: the ripple,
the elevation change under a press, the switch thumb, indeterminate progress,
the app bar reacting to a scroll, route transitions. And a list that stops
dead on release does not feel like a list.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).

## What already works, and should be said in the README

Because the declarative layouts are ordinary Flutter widgets, an
`AnimationController` driving `setState` or an `AnimatedBuilder` around a
`SceneContainer3d` **works today**. The value types are ready for it too:
`Size3d`, `Offset3d`, `EdgeInsets3d`, `Alignment3d` and `Constraints3d` all
have a static `lerp`. What is missing is the layer above — the tweens, the
implicit-animation base, and anything at all on the scroll side.

## What is missing

### Tweens and implicit animation

`Size3dTween`, `Offset3dTween`, `EdgeInsets3dTween`, `Alignment3dTween`,
`Constraints3dTween` — trivial, given the `lerp`s. Then
`ImplicitlyAnimatedLayout3dWidget` and its state, mirroring Flutter's
`ImplicitlyAnimatedWidget`/`AnimatedWidgetBaseState` with the same
`forEachTween` visitor, and on top: `AnimatedContainer3d`,
`AnimatedAlign3d`, `AnimatedPositioned3d`, `AnimatedSizedBox3d`, and
`AnimatedOpacity3d` once opacity exists
([size-driven geometry](2026_08_25_size_driven_geometry.md)).

### The cost, which is the interesting part

An implicit animation dirties layout every frame. In Flutter that is a
subtree relayout. Here a relayout also rewrites node transforms, which is
cheap — but if it reaches text measurement or geometry rebuilding it is not.
This is precisely why
[text](2026_08_25_text_in_a_3d_layout.md) is planned around a prepare/layout
split and
[decorations](2026_08_25_size_driven_geometry.md) around a shader rather than
regenerated meshes. Those two plans exist so that this one is affordable; a
change to either that puts shaping or mesh building back on the layout path
breaks this plan, and the tests in those plans are what catch it.

### The class of animation Flutter cannot have

Some animations move nothing in the layout. A slide, a hover lift, a pressed
depression, a billboard rotation: they change where a node *is*, not how big
any box is. `ParentData3d.sceneOffset` and `Layout3d.applyNodeTransform`
already express exactly that — an offset applied to the scene node that
layout, intrinsics and hit testing never see.

So design an explicit **node-only animation path**: a widget that writes
`sceneOffset` or a local transform and requests a frame without ever calling
`markNeedsLayout`. `AnimatedSlide3d`, a press depression, an overlay lift, and
the hover state layer all belong to it. This is a genuine 3D win and it should
be a named, documented category rather than an accident.

### Scroll: animation

[Scroll3dController](../lib/src/scroll/scroll_controller.dart) is deliberately
thin — a position, clamped, with `jumpTo`, `jumpBy`, `correctBy` and
`applyViewportMetrics`, and its doc says why: in a scene the gesture is the
application's to choose. That reasoning holds for *input* and not for
`animateTo`, which every menu, every focus traversal and every "scroll to top"
needs.

The obstacle is that the controller is a plain `ChangeNotifier` with no
ticker. Two options: `animateTo` takes a `TickerProvider` argument, or a
widget-level `Scroll3dPosition` created by a scrollable that has one.
Recommend the first for the imperative layer — it keeps the controller
dependency-free and matches how the package already asks callers to supply
what only they have — and add the widget attachment later if it proves
awkward.

`ensureVisible(Layout3d target, {alignment, duration, curve})` comes with it,
and is a hard requirement for focus traversal
([pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md)) and for menus.

### Scroll: physics

`Scroll3dPhysics` with `ClampingScroll3dPhysics` and
`BouncingScroll3dPhysics`, a simulation driven from a release velocity.
`Layout3dPointer` must track velocity to produce one; Flutter's
`VelocityTracker` works on 2D positions and the drag already resolves a
position on the grabbed view's own plane, so feed it that.

Overscroll in a scene need not be a glow. The content can bend, tilt, or
compress — a genuinely better answer than the 2D one. Note it as an option;
do not build it before clamping and bouncing work.

## The work

- [ ] **Phase 1 — tweens.** The five `Tween` subclasses, tested against the
      existing `lerp`s.
- [ ] **Phase 2 — implicit animation base** and `AnimatedContainer3d`,
      `AnimatedAlign3d`, `AnimatedPositioned3d`, `AnimatedSizedBox3d`.
- [ ] **Phase 3 — the node-only path.** The rule, the base widget, and
      `AnimatedSlide3d` as its first user.
- [ ] **Phase 4 — `animateTo` and `ensureVisible`.**
- [ ] **Phase 5 — physics and fling**, with velocity tracking in
      `Layout3dPointer`.
- [ ] **Phase 6 — README.** The Scrolling section currently states outright
      that there is no fling and that a release stops movement dead; it
      changes in the same pass.

## Tests

- Each tween's endpoints and midpoint agree with the corresponding `lerp`.
- An implicit animation reaches its target and rests there without further
  dirt.
- A node-only animation asserts that no layout was marked dirty across its
  whole run — the load-bearing test of phase 3.
- `animateTo` clamps to the scroll range and completes; a second call
  interrupts the first cleanly.
- `ensureVisible` finds an offset that puts a target inside the window, for a
  target above and below it.
- A fling decelerates to rest and stays clamped; a bouncing physics returns
  from beyond the end.

## Out of scope

Ripple rendering (that is a shader in the component package, driven from this
plan's press state), route transitions
([overlays](2026_08_25_overlays_and_layered_surfaces.md) owns the hook), and
physically simulated UI via the physics backends.
