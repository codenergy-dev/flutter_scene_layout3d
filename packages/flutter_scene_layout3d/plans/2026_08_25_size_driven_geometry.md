---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
---

# Geometry that follows the box, not the other way round

This package arranges content and never draws it. That is the right rule, and
it leaves a component library with no way to make a panel: the one leaf that
holds geometry, [NodeBox3d](../lib/src/boxes/node_box.dart), takes content
that already exists and *scales it* into the room available. Scaling a
rounded panel distorts its corners. A `Card3d` with a 4dp radius needs 4dp at
every size.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).
Needs the unit contract from
[camera-bound surfaces](2026_08_25_camera_bound_surfaces.md) to express a
radius or an elevation in dp.

## What exists today

- `Container3d`'s own class doc says it: *"This is a layout container. Making
  it visible (a panel, a frame, a backing plane) is a matter of putting a mesh
  in the tree, which is what `NodeBox3d` is for; nothing in this package draws
  on its own."*
- `NodeBox3d` owns its content node's `localTransform` and applies a
  `BoxFit3d` — measure, then scale. The inverse of what a decoration needs.
- Every `Layout3d` owns a scene `Node` whose transform is rewritten on each
  placement, and hanging extra content under it is explicitly allowed. So a
  decorating box has somewhere to put its mesh without fighting the protocol.
- Visibility is already used as a culling mechanism: the scrolling views set
  `node.visible` per child (`sliver_grid.dart:166`,
  `custom_scroll_view.dart:247`).
- `flutter_scene` supplies `MeshGeometry.fromArrays`, `GeometryBuilder`
  (`lib/src/geometry/mesh_geometry.dart:996`), `ShaderMaterial` with a
  documented output contract (`MATERIALS.md`), instancing, and real shadows.

## The design

### `Decoration3d` and the box that applies it

```
abstract class Decoration3d {
  bool shouldRebuild(covariant Decoration3d old);
  Object get cacheKey;
  Decoration3dPainter3d createPainter();   // owns mesh + material
}
```

with `BoxDecoration3d` as the concrete one: colour, corner radius, bevel,
border width and colour, and a material override. `DecoratedBox3d` is a
`SingleChildLayout3d` that lays its child out normally and, after sizing,
hands its own `size` to the painter, which produces or updates the geometry
under the box's node.

### The main design bet: a shader, not regenerated geometry

Three ways to make a rounded panel follow a size:

1. **Regenerate the mesh** whenever the size changes. Correct, and the wrong
   default: a screen of components animating produces mesh churn every frame,
   which is exactly the cost
   [animation](2026_08_25_animation_and_scroll_physics.md) must not pay.
2. **27-slice scaling** — the 3D form of a 9-slice. Corners stay rigid,
   middles stretch. No per-frame allocation, but the mesh is fixed-topology
   and cannot express a border or a bevel that changes with state.
3. **A signed-distance field in the fragment shader** over one shared cuboid,
   with the size, radius, border and state-layer colour as uniforms.
   Resolution-independent corners, no geometry work at any size, one mesh and
   one material class shared by every panel in the scene, and the state layer
   is a uniform rather than a second mesh.

**Take (3) as the default**, (1) as the escape hatch behind the
`Decoration3d` interface for anything a shader cannot express. The caveat to
write down and verify: an SDF on a cuboid gives a correct silhouette only if
fragments outside the rounded body are discarded, and discard interacts with
the depth prepass and with shadow casting — so the shadow a rounded panel
casts must be checked, not assumed.

### Material and mesh sharing

A hundred components must not mean a hundred materials. Decorations that
compare equal share a painter, keyed by `cacheKey`, in a per-surface cache.
Instancing (`InstancedMesh` in the engine) is the follow-up once the shared
path works; it is not phase one.

### Elevation, which 3D gets for free

Material's elevation is a shadow approximating height. Here the height is
real: the panel is geometry and the engine has shadows. So elevation maps to
a depth offset in layout units (dp through the metrics contract) and the
shadow comes from the scene's own lighting. This is the cheapest item in this
plan and the one that most makes a 3D Material look better than a flat one.

The tint half of Material 3's elevation (surface tint colour) stays a uniform
on the same shader.

### State layers

Hover, press, focus and drag overlays are a colour blended over the same
decoration. One uniform, driven by whatever
[pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md) reports. No
second box, no second mesh, and — important — **no relayout**: a state change
writes a uniform and requests a frame, it does not dirty layout.

### Visibility, opacity and clipping: three different problems

- **`Visibility3d` / `Offstage3d` are easy** and should land in phase one.
  Offstage reports zero size and hides the node; visible/invisible toggles
  `node.visible`, which hit testing already honours
  (`layout3d.dart:770` refuses a hidden child).
- **`Opacity3d` is not a wrapper.** Flutter's is a `saveLayer`; a scene has
  no such thing. Fading a subtree means multiplying an alpha into every
  material under it, which needs an engine-side contract (a per-node tint or
  opacity the materials honour). Write the design; the implementation may
  have to land in `flutter_scene` first. Do not ship a `Opacity3d` that
  silently only works on `BoxDecoration3d`.
- **Clipping has no answer yet and three candidates.** Per-child visibility
  culling (what the scrolling views already do — whole children only);
  stencil; or shader plane-clipping, where up to N clip planes are passed
  down to the materials and fragments outside are discarded. Only the third
  clips a *part* of a child, which is what a `Card3d` clipping its image and
  a menu clipping its scroll need. Recommend the third, and note that
  [persistent headers](2026_08_25_persistent_sliver_headers.md) and
  [overlays](2026_08_25_overlays_and_layered_surfaces.md) are both waiting on
  it. Whoever implements it owns the contract.

## The work

- [ ] **Phase 1 — the interface and the easy boxes.** `Decoration3d`,
      `DecoratedBox3d`, the painter cache, `Visibility3d`, `Offstage3d`.
- [ ] **Phase 2 — `BoxDecoration3d` on the SDF shader.** Colour, radius,
      border, bevel; the shared cuboid; the uniform block; the discard/shadow
      check.
- [ ] **Phase 3 — elevation.** dp-to-depth mapping, surface tint, and a
      worked example showing a raised card against the engine's shadows.
- [ ] **Phase 4 — state layers.** The uniform, and the rule that a state
      change never marks layout dirty.
- [ ] **Phase 5 — the mesh-generating fallback** for decorations the shader
      cannot express.
- [ ] **Phase 6 — the two engine-dependent items**, each its own follow-up:
      subtree opacity, and clip planes.

## Tests

- A `DecoratedBox3d` at two sizes produces one mesh and two uniform sets, not
  two meshes (the whole point of the bet).
- Two equal decorations share a painter; unequal ones do not.
- A state-layer change requests a frame and marks nothing dirty for layout.
- `Offstage3d` reports zero size and its child is unreachable by a ray;
  `Visibility3d(visible: false)` reports the child's size and is still
  unreachable.
- Elevation moves the node toward the viewer by the expected number of units
  for a given dp and metrics.
- A render-level check that a rounded panel's silhouette and its cast shadow
  agree.

## Out of scope

Material's actual token set (colours, shape scales, elevation levels) — that
is `flutter_scene_material3d`. Text ([its own plan](2026_08_25_text_in_a_3d_layout.md)).
Gradients and images in decorations, until the flat-colour path is proven.
