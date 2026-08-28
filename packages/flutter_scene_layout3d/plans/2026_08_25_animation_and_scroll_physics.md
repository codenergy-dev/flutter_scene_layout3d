---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-28T14:52:00Z
commit: 657eef80eb8dc8085c3b3a84a8069273495506be
---

# Animation, and the scroll physics that is missing with it

> **Shipped.** Everything below from "What is missing" down to "Scroll:
> physics" is the reasoning as it was written, kept because it is why the
> shape is what it is; read *The work*, *Tests* and *What the original
> reasoning got wrong* for what is actually in the package now.

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

- [x] **Phase 1 — tweens.** `lib/src/animation/tweens.dart`. Eight rather
      than five: the plan's `Size3dTween`, `Offset3dTween`,
      `EdgeInsets3dTween`, `Alignment3dTween` and `Constraints3dTween`, plus
      `BorderRadius3dTween`, `BoxDecoration3dTween` and `StateLayer3dTween`,
      because the decoration `lerp`s already existed and the decoration setter
      is the *cheapest* animation path in the package — the one a Material
      catalogue reaches for first. Leaving them out would have pointed
      catalogue authors at the expensive path.
- [x] **Phase 2 — implicit animation base**,
      `lib/src/animation/implicit.dart`: `ImplicitlyAnimatedLayout3dWidget`,
      `ImplicitlyAnimatedLayout3dWidgetState`,
      `AnimatedLayout3dWidgetBaseState`, `Layout3dTweenVisitor` and
      `Layout3dTweenConstructor`, with `SceneAnimatedContainer3d`,
      `SceneAnimatedAlign3d`, `SceneAnimatedPositioned3d` and
      `SceneAnimatedSizedBox3d`.
- [x] **Phase 3 — the node-only path.** `Layout3d.nodeOffset` and
      `Layout3d.nodeTransform` in `layout3d.dart` (composed into
      `applyNodeTransform`, undone by `worldTransform`),
      `NodeTransform3d` in `lib/src/animation/node_transform.dart`, and
      `SceneNodeTransform3d` with `SceneAnimatedSlide3d` in
      `lib/src/animation/node_widgets.dart`.
- [x] **Phase 4 — `animateTo` and `ensureVisible`.**
      `Scroll3dController.animateTo`, `.fling`, `.stopAnimation`,
      `.isAnimating`, and free functions `ensureVisible3d` /
      `offsetToReveal3d` with `Scrollable3d.of` in `scrollable.dart`.
- [x] **Phase 5 — physics and fling.** `lib/src/scroll/scroll_physics.dart`
      with `Scroll3dPhysics`, `ClampingScroll3dPhysics` and
      `BouncingScroll3dPhysics`; velocity tracking and a fling on release in
      `Layout3dPointer`.
- [x] **Phase 6 — README.** The "no scroll physics" paragraph is now
      *Physics, flings, and going somewhere*; "there is still no fling"
      is gone from both places it appeared; there is a new *Animation*
      section covering the three paths, and roadmap item 8.

## Tests

All in `test/animation_test.dart` (25 tests; the suite is 618 and green,
`dart analyze` clean).

- [x] Each tween's endpoints and midpoint agree with the corresponding `lerp`.
- [x] An implicit animation reaches its target and rests there without further
      dirt (`needsFlush` false, no frame scheduled), and a retarget carries on
      from where it had got to.
- [x] A node-only animation marks nothing dirty across its whole run — asserted
      every frame, plus that the child's layout count and layout offset never
      move, plus that a ray still finds the box where layout put it.
- [x] `animateTo` clamps to the scroll range and completes; a second call
      interrupts the first cleanly and the interrupted future still answers.
- [x] `ensureVisible3d` for a target below the window, above it, already
      inside it, and at each `alignment`.
- [x] A fling decelerates to rest and stays clamped; a bouncing physics
      returns from beyond the end; a bouncing drag past the end moves less
      than the finger.
- [x] `debugTextParagraphCount` does not move while a `SceneAnimatedContainer3d`
      resizes a `SceneText3d` through fifty widths — plan 2's ask, and the
      test that fails first if measurement ever gets back onto the layout
      path.

## What the original reasoning got wrong

**Naming.** The plan called the widgets `AnimatedContainer3d`,
`AnimatedAlign3d`, `AnimatedPositioned3d`, `AnimatedSizedBox3d` and
`AnimatedSlide3d`. This package's convention is that a *widget* mounting an
object carries the `Scene` prefix, so they shipped as
`SceneAnimatedContainer3d` and so on, with the abstract bases
(`ImplicitlyAnimatedLayout3dWidget`) unprefixed the way `Layout3dWidget` and
`SingleChildLayout3dWidget` are. `AnimatedOpacity3d` is still waiting on a
per-node opacity, as the plan said.

**The node-only path needed a new field, not `sceneOffset`.** The plan
pointed at `ParentData3d.sceneOffset`, but that field belongs to the *parent*
and is rewritten on every `place` — `Stack3d.depthStep` writes it — so an
animation stored there is erased by the next relayout of a stack. The seam
shipped as `Layout3d.nodeOffset` and `Layout3d.nodeTransform`, the box's own,
composed with `sceneOffset` in `applyNodeTransform` and undone alongside it in
`worldTransform`.

**Flutter's `VelocityTracker` cannot be used here.** It timestamps its own
samples from `GestureBinding.instance.samplingClock`, which asserts that a
widget test is running; this package's pointer is driven from plain `test`
cases and, in an application, from whatever clock the host has. `_DragVelocity`
in `pointer.dart` does a straight least-squares fit over the timestamps the
caller already passes to `Layout3dPointer.move`. It refuses to estimate from
samples spanning under 2ms, which is what a synthesized drag looks like — so a
fling needs honest timestamps, and that is documented.

**Simulations are tuned in logical pixels, and this package measures in world
units.** A world unit is a hundred logical pixels by default, and
`ClampingScrollSimulation`'s duration goes as `v^0.735`, so feeding it layout
units would have made every fling about thirty times too short. The controller
therefore records `unitsPerLogicalPixel` from the view that laid it out (a new
optional argument to `applyViewportMetrics`), the physics runs Flutter's
simulations in pixels, and `Scroll3dPhysics.scaled` wraps the result back into
layout units.

**`applyBoundaryConditions` is not a clamp.** Flutter's clamping physics
deliberately lets an already-out-of-range position move *toward* the range, so
a plain `applyBoundaryConditions` in `applyViewportMetrics` would have stopped
a shrinking list from snapping its offset back this frame. `Scroll3dPhysics`
grew `allowsOverscroll`: a physics that cannot overscroll snaps, one that can
keeps the position and gets a ballistic settle.

**`userScrollDirection` was added after all.** Plan 7 flagged that the
floating `SliverPersistentHeader3d` was missing Flutter's
`SliverConstraints.userScrollDirection` term. Physics gave the position a
direction, so `ScrollDirection3d` and `Scroll3dController.userScrollDirection`
now exist, `SliverConstraints3d` carries it, and the floating header uses it
*only to refuse*: a backwards movement while the viewer is scrolling the other
way (a bouncing spring settling) no longer pulls the bar in, while a
programmatic `jumpTo` or `animateTo` still does.

**`ensureVisible` defaults to minimal scrolling.** Flutter's
`getOffsetToReveal` takes `alignment: 0.0`; `offsetToReveal3d` takes
`double? alignment` where null means "move as little as possible", because
that is what focus traversal actually wants and it was going to be written by
hand at every call site otherwise.

## Out of scope

Ripple rendering (that is a shader in the component package, driven from this
plan's press state), route transitions
([overlays](2026_08_25_overlays_and_layered_surfaces.md) owns the hook), and
physically simulated UI via the physics backends.

Two things this plan's own text defers, and which are therefore out of scope
rather than open: `AnimatedOpacity3d`, which waits on
[size-driven geometry](2026_08_25_size_driven_geometry.md) giving the engine a
per-node opacity; and the scene-native overscroll effect — content that bends,
tilts or compresses instead of glowing — which the plan says to note as an
option and not build before clamping and bouncing work.
`Scroll3dController.overscroll` is the number it would be driven from, and the
node-only path is where it belongs.
