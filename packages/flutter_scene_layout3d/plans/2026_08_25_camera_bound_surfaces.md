---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
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

- [ ] **Phase 1 — the metrics.** `Layout3dMetrics` on `Layout3dOwner`, a
      setter on `Layout3dSurface` that relayouts, `Layout3d.metrics`,
      documented defaults, and the conversion helpers a component author uses
      (`dp(48)` → units).
- [ ] **Phase 2 — the binding.** `Layout3dCameraBinding` with the three modes,
      the frustum arithmetic, the plane transform, the epsilon, and the
      declarative wiring on `SceneLayout3d`.
- [ ] **Phase 3 — orthographic.** `OrthographicProjection` in `flutter_scene`
      (separate commit, engine package), and the ortho branch of
      `screenFilling`.
- [ ] **Phase 4 — README.** A section on what a camera-bound surface is, why
      it is how a 3D UI gets a "screen", and the authored-density alternative
      for panels that are not screens.

## Tests

- Frustum arithmetic: a known fov, aspect and distance produce known world
  extents; the surface's constraints match; `unitsPerLogicalPixel` inverts
  correctly (a box of `n` logical pixels projects to `n` pixels on screen,
  checked through `Camera.getViewTransform`).
- A camera translating along its forward axis with `screenFilling` re-derives
  and relayouts; a camera panning at fixed distance does not (the epsilon
  test).
- `billboard` writes no constraints and marks no layout dirty.
- Metrics propagate to a deep child through `owner`, and a change relayouts.
- An authored density and a derived one produce the same box sizes for the
  same inputs.

## Out of scope

Stereo or per-eye viewports, curved surfaces, `viewport` sub-rects, and any
component-level use of the metrics — that is the catalogue's business, not
this package's.
