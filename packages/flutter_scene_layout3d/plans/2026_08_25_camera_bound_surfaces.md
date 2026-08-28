---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-26T22:15:48Z
commit: 657eef80eb8dc8085c3b3a84a8069273495506be
---

# Camera-bound surfaces, and the unit contract that falls out of them

Two things that look separate and are the same mechanism: a surface whose
plane is tied to the camera's view, and the number that says how many world
units a logical pixel is worth.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md),
and the plan that goes first, because
[text](2026_08_25_text_in_a_3d_layout.md),
[decoration](2026_08_25_size_driven_geometry.md) and
[hit-test target sizes](2026_08_25_pointer_dispatch_and_focus.md) all need the
unit contract and none of them can invent it credibly on their own.

## The problem the binding solves

A `Layout3dSurface` today is unbounded on all three axes unless the caller
supplies constraints, and the README's Scrolling section already notes what
that costs: a list on a bare surface asserts, because nothing bounds it.
Flutter never has this problem — the screen bounds everything.

A camera-bound surface *is* a screen. Put the plane at distance `d` in front
of the camera, oriented to it, and the frustum at that distance gives an exact
world-space width and height. Those become the surface's constraints. A panel
so bound behaves like a Flutter window: it resizes when the view resizes, its
content reflows, and "how big is the screen" has an answer.

And once the surface fills the view, the conversion is forced rather than
chosen: the plane's world height covers exactly `viewSize.height` logical
pixels, so

```
unitsPerLogicalPixel = worldViewHeight / viewSize.height
```

That is the number the rest of the catalogue is specified in. A Material 48dp
touch target becomes `48 * unitsPerLogicalPixel` and lands as 48dp on screen.

## What exists to build on

- [camera.dart](../../flutter_scene/lib/src/camera.dart): `Camera` (abstract)
  with `position`, `forward`, `up`, `getViewMatrix()`,
  `getViewTransform(Size)` and `screenPointToRay`; `CameraProjection`
  (abstract, `getProjectionMatrix(aspectRatio)`) with `PerspectiveProjection`
  (`fovRadiansY`, `near`, `far`);
  and `PerspectiveCamera`.
- **There is no orthographic projection in `flutter_scene` today.** Only
  `PerspectiveProjection` ships. An orthographic path means adding an
  `OrthographicProjection` to the engine — `CameraProjection` is abstract and
  its one method takes an aspect ratio, so the change is small and separable,
  but it is an engine change and belongs in its own commit.
- `SceneView` already computes its own size: it wraps the scene in a
  `LayoutBuilder` and keeps `constraints.biggest`
  (`lib/src/widgets/scene_view.dart:622`), and supports a fractional
  `viewport` rect. The widget layer therefore has both camera and view size
  available to hand down.
- [Layout3dSurface](../lib/src/surface.dart) already has everything the
  binding drives: `configuration` (the constraints), `basis`, `origin`, and a
  `plane` node whose transform is explicitly the caller's to set. The
  `configuration` setter early-outs on equality, which matters below.
- [Layout3dOwner](../lib/src/layout3d.dart) is the existing tree-wide channel:
  it carries the `basis` and the visual-update callback, and every `Layout3d`
  reaches it through `owner`. The metrics belong here, next to the basis.

## The design

### The metrics contract

```
class Layout3dMetrics {
  final double unitsPerLogicalPixel;  // world units per logical pixel
  final double textScaleFactor;
  final VisualDensity density;        // or a 3D analogue
}
```

carried on `Layout3dOwner` beside `basis`, so both layers see it and a
`Layout3d` reaches it with `owner?.metrics`. Not an `InheritedWidget`: the
imperative layer has no `BuildContext`, and the basis already set the
precedent.

Changing it must relayout, for the same reason changing the basis does:
content measured at one density reports a different size at another.

Three ways to set it, and a component library needs all three:

- **Derived from a camera binding.** The surface fills the view; the number is
  computed. This is the honest case, and the reason this plan leads.
- **Authored.** A panel on a wall at some arbitrary angle is not a screen. The
  author states "this panel is drawn at 1 unit = 100 logical pixels" and every
  component inherits it. Same contract, supplied rather than derived.
- **Inherited.** A nested surface (an overlay layer, see
  [overlays](2026_08_25_overlays_and_layered_surfaces.md)) takes its host's
  metrics unless it declares its own.

### The bindings

```
Layout3dCameraBinding.screenFilling({double distance, ...})
Layout3dCameraBinding.billboard()          // app owns the position, camera owns the facing
Layout3dCameraBinding.fixedDensity(double unitsPerLogicalPixel)
```

`screenFilling` computes, for a perspective camera,
`height = 2 * distance * tan(fovRadiansY / 2)` and `width = height * aspect`
(`PerspectiveProjection.fovRadiansY` is the vertical field of view; the
horizontal one is derived from the aspect ratio at draw time), sets
`Layout3dSurface.configuration` to a tight `Size3d(width, height, depth)`,
derives the metrics, and writes the plane's transform from the camera's view
matrix. For an orthographic camera the extents come straight from the
projection and do not depend on distance — which is the reason a HUD wants
one, and the reason the engine-side `OrthographicProjection` is worth adding.

`depth` cannot be derived from the frustum and stays an explicit property; a
panel needs a thickness for content to stand in (a trap the README already
names).

### Where the per-frame update runs

- **Declarative:** `SceneLayout3d` gains `camera` and `binding`. It already
  lives under `SceneView`, so the view size can reach it; if that plumbing is
  awkward, the widget takes the size explicitly and `SceneView` gains a way
  to publish it. Deciding this is part of phase 2, and the choice must not
  require the caller to thread a size by hand for the common case.
- **Imperative:** a plain object the app ticks —
  `binding.update(camera: camera, viewSize: size)` — mirroring how the README
  already tells callers to drive `Layout3dPointer` from their own events.

### The cost, and the mitigation

A moving camera re-derives constraints every frame, and a changed
`configuration` marks the surface dirty. Two things keep that from being a
per-frame full relayout:

- The `configuration` setter already early-outs on an equal value, so a
  translating camera at fixed distance and fixed view size writes nothing.
- Only `screenFilling` derives constraints at all. `billboard` writes the
  plane's transform only, which is a node transform and touches no layout.

Round the derived extents to an epsilon before assigning, so floating-point
jitter in the view matrix does not dirty layout every frame. State the epsilon
and test it.

### The one that is left open

A panel that is *not* camera-bound sits at a varying distance from the
viewer, so its pixels-per-unit varies. Text rasterization scale
([text](2026_08_25_text_in_a_3d_layout.md), phase 4) therefore needs an LOD
story: an atlas bucket chosen per frame from the current distance, or one
generous bucket and an SDF. This plan does not solve it; it names it so the
text renderer is not designed as though density were constant.

## The work

- [x] **Phase 1 — the metrics.** `Layout3dMetrics` on `Layout3dOwner`, a
      setter on `Layout3dSurface` that relayouts, `Layout3d.metrics`,
      documented defaults, and the conversion helpers a component author uses
      (`dp(48)` → units). `lib/src/metrics.dart`, with `VisualDensity3d` as
      the 3D analogue the plan left open.
- [x] **Phase 2 — the binding.** `Layout3dCameraBinding` with the three modes,
      the frustum arithmetic, the plane transform, the epsilon, and the
      declarative wiring on `SceneLayout3d`. `lib/src/camera_binding.dart`.
- [x] **Phase 3 — orthographic**, on this package's side: there is no ortho
      *branch* in `screenFilling` and there does not need to be, because the
      extents are read out of the projection matrix rather than out of a
      `PerspectiveProjection`'s field of view (see below). Covered by a test
      with a projection defined in the test file.
      **Not done, deliberately:** `OrthographicProjection` in `flutter_scene`.
      The plan itself says that is a separate commit in the engine package, so
      it stays one; nothing on the layout side is waiting on it.
- [x] **Phase 4 — README.** *How the plane gets a screen, and what a logical
      pixel is worth*, with the unit contract, the authored-density
      alternative, and the three things worth knowing before reaching for any
      of it.

## Tests

`test/metrics_test.dart` (17) and `test/camera_binding_test.dart` (26).

- [x] Frustum arithmetic: a known fov, aspect and distance produce known world
      extents; the surface's constraints match; `unitsPerLogicalPixel` inverts
      correctly. Checked two ways: the plane's corners project to the view's
      corners, and a box of `metrics.dp(48)` measures 48 logical pixels across
      through `Camera.worldToScreen`.
- [x] A camera panning at a fixed distance relayouts nothing (the epsilon
      test), **and so does one translating along its forward axis** — see the
      correction below.
- [x] `billboard` writes no constraints, no metrics, and marks no layout
      dirty; it keeps the translation the application set and takes only the
      facing.
- [x] Metrics propagate to a deep child through `owner`, and a change
      relayouts.
- [x] An authored density and a derived one produce the same box sizes for the
      same inputs.
- [x] Extra: an orthographic lens covers the same extents at any distance; a
      still camera writes nothing at all, not even a node transform; a
      degenerate view is a no-op; the declarative wiring derives, and hands the
      contract back when the binding is dropped.

## What the original reasoning got wrong

**A camera translating along its forward axis does not re-derive.** The plan
predicted it would, and made it a test. It is wrong: `screenFilling` pins the
plane a fixed `distance` in front of the eye, so walking forward carries the
plane along and the frustum *at that distance* is unchanged. What actually
re-derives is a change of view size, field of view, or `distance`. The test
now asserts the true behaviour and says so in a comment, and there is a
separate test for the view-size case.

**Rounding to an epsilon is the wrong mechanism.** "Round the derived extents
to an epsilon before assigning" was implemented first and failed its own test:
an extent that happens to sit near a quantum boundary flips across it on
exactly the jitter the rounding was meant to absorb (the derived width did,
while the height did not). `extentEpsilon` is now a **dead band** measured
against the extent already in force — within it, the standing value is kept.
That has no boundaries in it, keeps the surface covering the view *exactly*
rather than on a grid, and still lets a slow genuine drift land, one epsilon
at a time. Default `1e-4` world units, a hundredth of a logical pixel at the
default metrics.

**`markNeedsLayout` at the root is not enough for a tree-wide value.**
`Layout3d.layout` skips a clean child whose constraints did not change, which
is exactly the case for a box that reads `metrics` directly. Added
`Layout3d.markSubtreeNeedsLayout()` and used it from the metrics setter. The
pre-existing `basis` setter had the same latent bug — its dartdoc promised a
relayout that a `NodeBox3d` deeper in the tree would never see — and was fixed
in the same pass.

**The binding takes the surface as an argument.** The plan wrote
`binding.update(camera: camera, viewSize: size)`, implying a binding holds a
surface. It is an immutable description instead —
`binding.update(surface, camera: ..., viewSize: ...)` — so a `const` binding
can live in a widget's build method and be applied to whichever surface that
widget owns. The hierarchy is closed (private subclasses behind three named
constructors).

**The orthographic branch is not a branch.** Rather than reading
`PerspectiveProjection.fovRadiansY`, `screenFilling` reads the projection
*matrix*: at view depth `z` the clip `w` is `m32 * z + m33`, so the visible
half-width there is `w / m00` and the half-height `w / m11`. For a perspective
lens that is the familiar `z * tan(fov / 2)`; for an orthographic one
(`m32 = 0`, `m33 = 1`) it collapses to a constant with no distance in it. One
expression covers both, and any caller's own `CameraProjection` besides.

**`SceneView` publishes no view size, and cannot easily.** Its declarative
children are laid out at a tight zero size (they exist to reconcile trees, not
to take space), so a `LayoutBuilder` under a `SceneLayout3d` sees nothing.
`SceneLayout3d` therefore resolves the size by walking to the nearest
*laid-out* ancestor box, which under a `SceneView` is the view's own box, with
`viewSize` as an explicit override. That walk must not happen during layout —
a box's size is only legible to its parent while a pass is running — so the
binding is applied from the enclosing scene's per-frame clock
(`SceneScope.elapsed`) and, for the first application and for hosts that do
not tick, from a post-frame callback. No caller threads a size by hand in the
common case, which was the plan's requirement.

**"Inherited" metrics had nothing to attach to.** The package has no nested
surfaces yet; inheritance inside one tree is what `owner.metrics` already
gives, and a nested surface (when [overlays](2026_08_25_overlays_and_layered_surfaces.md)
land) assigns its host's `metrics` to get the same contract.

## What the later plans need from this

- The number is `Layout3dMetrics.unitsPerLogicalPixel`, in
  `lib/src/metrics.dart`, carried on `Layout3dOwner.metrics` and read by any
  box as `metrics` (`Layout3d.metrics`, falling back to
  `Layout3dMetrics.standard` while detached). `metrics.dp(x)`,
  `metrics.sp(x)`, `metrics.toLogicalPixels(u)`, `metrics.dpSize(w, h, [d])`
  and `metrics.effectiveConstraints(c)` are the conversions.
- The authored default is `0.01`: one world unit to a hundred logical pixels.
- `metrics.logicalPixelsPerUnit` is the rasterization number
  ([text](2026_08_25_text_in_a_3d_layout.md) wants it), and it is *not* a
  promise about screen pixels unless the surface is camera-bound — the LOD
  question this plan leaves open is unchanged.
- Reading `metrics` in `performLayout` is safe and cheap; a change to it
  relayouts the whole subtree, so nothing on a per-frame animation path should
  write it.

## Out of scope

Stereo or per-eye viewports, curved surfaces, `viewport` sub-rects, and any
component-level use of the metrics — that is the catalogue's business, not
this package's.
