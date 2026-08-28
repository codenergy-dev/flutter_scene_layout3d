---
status: in progress
reason: >
  Phases 1 to 5 have landed and are covered by 62 headless tests. Two items
  are open, both of them needing something this repository cannot run today.
  (1) No lane compiles the shipped `assets/box_decoration3d.fmat`, so the
  panel shader is checked for its parameter contract and never for what it
  draws — which leaves the plan's render-level silhouette-versus-shadow check
  and the worked raised-card example undone. That lane is now planned as
  `2026_08_28_render_coverage.md`, phase 5, which is the thing to do before
  picking this item up. (2) Phase 6's
  subtree opacity is designed and not implemented: it needs a per-node
  opacity or tint in `flutter_scene` that the materials honour, and the plan
  itself says not to ship an `Opacity3d` that only works on
  `BoxDecoration3d`. Phase 6's other half, clip planes, did land.
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-27T12:52:08Z
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

  **The design, written and not implemented.** It wants one addition to the
  engine: an opacity on `Node` that composes down the graph the way a
  transform does, and that every material multiplies into its output alpha
  (which is already premultiplied, so it is a scalar on the whole colour).
  Given that, `Opacity3d` is a `ProxyLayout3d` that writes `node.opacity` and
  nothing else — no relayout, no repaint, the same shape `Visibility3d` has,
  and it works on `Text3d`, `NodeBox3d` and a loaded model alike rather than
  only on decorations. Without it the only honest options are a per-material
  alpha the caller sets by hand, or nothing; this package ships nothing.
  Two details for whoever implements it: a fading subtree has to move to the
  translucent pass and back, which is a material-level state change rather
  than a uniform, and a subtree fading as a whole is *not* the same picture as
  each of its parts fading — overlapping children double-expose. Flutter pays
  for a `saveLayer` to avoid exactly that, and a scene has nowhere to put one,
  so the engine contract should say plainly that it is the cheap
  approximation.
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

- [x] **Phase 1 — the interface and the easy boxes.** `Decoration3d`,
      `Decoration3dPainter`, `Decoration3dPaintRequest`,
      `Decoration3dPainterCache` (on `Layout3dOwner`, so it is per-surface),
      `DecoratedBox3d`, `Visibility3d`, `Offstage3d`.
      `lib/src/decoration/decoration.dart`,
      `lib/src/decoration/decorated_box.dart`,
      `lib/src/boxes/visibility.dart`.
- [x] **Phase 2 — `BoxDecoration3d` on the SDF shader.** Colour, radius
      (`BorderRadius3d`, per corner, resolved against the box), border
      (`Border3d`), bevel; `BoxDecoration3dUniforms` is the uniform block and
      is pure arithmetic, so it is tested; `assets/box_decoration3d.fmat` is
      the shader and `BoxDecoration3dPainter` drives it over a shared unit
      slab. The discard/shadow check is **not** done — see *What the plan got
      wrong* below.
- [x] **Phase 3 — elevation.** `metrics.dp(elevation)` toward the viewer, as
      a `localTransform` on the decorated box with `hitTestTransform` null, so
      the lift moves geometry and not the layout box. Surface tint is a
      uniform, its amount from Material 3's published table
      (`BoxDecoration3d.surfaceTintOpacityFor`). The worked example against
      the engine's shadows is not done, for the same reason the shader is not
      exercised.
- [x] **Phase 4 — state layers.** `StateLayer3d`, carried on
      `DecoratedBox3d.stateLayer` rather than on the decoration, which makes
      the no-relayout rule structural instead of a promise: the setter
      repaints and calls `requestVisualUpdate`, and touches the layout
      pipeline nowhere.
- [x] **Phase 5 — the mesh-generating fallback.** Delivered as the open seam
      rather than a second concrete decoration: `Decoration3d` is
      subclassable and its painter may generate whatever it likes, and
      `BoxDecoration3dPainter.createGeometry` substitutes a mesh into the
      shipped painter without touching anything else. There is no shape in
      this plan's scope that the SDF cannot express, so a concrete fallback
      would have been an unused class.
- [~] **Phase 6 — the two engine-dependent items.** Clip planes landed, and
      the contract is `ClipPlane3d` / `Clip3dRegion` / `ClipBox3d` in
      `lib/src/clip.dart` (see *The clip contract* below). Subtree opacity is
      designed and not implemented; it is waiting on the engine.

## Tests

`test/decoration_test.dart`, `test/clip_test.dart` and
`test/decoration_material_test.dart`, 62 tests, all green beside the 399 that
were there before.

- [x] A `DecoratedBox3d` at two sizes produces one painter and two paints.
- [x] Two equal decorations share a painter; unequal ones do not; the cache
      disposes a painter when the last box lets go.
- [x] A state-layer change requests a frame, repaints, and marks nothing
      dirty for layout. So does a decoration change.
- [x] `Offstage3d` reports zero size, answers intrinsics with nothing, and its
      child is unreachable by a ray; `Visibility3d(visible: false)` reports
      the child's size and is still unreachable.
- [x] Elevation moves the node toward the viewer by the expected number of
      units for a given dp and metrics, follows a metrics change, and moves
      neither the layout box nor what a ray reaches.
- [x] The uniform block: dp to units, radii clamped to the box, a border that
      cannot cross itself, the state layer's opacity folded into its alpha,
      the surface-tint table.
- [x] The clip contract: plane arithmetic, pull-back through a transform,
      nested axis-aligned clips folding to six planes, whole-node culling and
      what it deliberately cannot do.
- [x] The shipped `.fmat` parses, emits GLSL, and declares every parameter
      `BoxDecoration3dUniforms.applyTo` writes — which is the failure that
      would otherwise be silent.
- [ ] A render-level check that a rounded panel's silhouette and its cast
      shadow agree. **Not done**: no lane compiles the material.

## The clip contract, for the plans waiting on it

Owned here, per the overview. Consumed by
[persistent headers](2026_08_25_persistent_sliver_headers.md) and
[overlays](2026_08_25_overlays_and_layered_surfaces.md).

- **`ClipPlane3d(normal, distance)`** keeps `dot(normal, p) + distance >= 0`.
  `shifted(delta)` translates it; `transformed(m)` pulls it back through a
  transform by the transpose, which stays correct under a non-uniform scale.
- **`Clip3dRegion`** is an intersection of planes, expressed in *one box's own
  layout frame*. `Clip3dRegion.rect(size)` is four planes and leaves the
  thickness alone (the default: a raised card in a scrolling list should stand
  proud of it); `Clip3dRegion.box(size)` is six.
- **`Layout3d.clipRegion`** is what a consumer reads. It walks up rather than
  being pushed down, so a tree with no clip in it pays nothing.
  `clipRegionForChild` is the override point: `ClipBox3d` intersects its own
  extent in, and a header that clips a band rather than a box overrides the
  same method.
- **`intersect` folds parallel planes**, so nesting axis-aligned clips stays
  at six — `Clip3dRegion.maxPlanes`, the number a consumer must honour.
  `toPlaneBlock()` packs it as six `vec4`s padded with `(0,0,0,1)`, and
  *throws* rather than dropping planes when a rotation has produced more.
- **Three tiers, and a consumer picks one.** Whole-node culling
  (`excludes` plus `node.visible = false`, what `ClipBox3d` does today, exact
  for whole boxes and free); clip planes in the material (`toPlaneBlock`, what
  clips *part* of a child — the shipped panel shader reads them, no other
  material does yet); or nothing, which `isUnbounded` makes cheap to detect.

**For persistent headers:** a pinned bar wants the scrolling content clipped
at the bar's trailing edge, which is one plane, not a box. Build it as a
`Clip3dRegion` of a single `ClipPlane3d` and override `clipRegionForChild` on
the sliver that owns the band; do not reach for `ClipBox3d`, which is a box by
construction. Whole-node culling will not be enough — the point is a row
*half* under the bar — so this is the first consumer that needs tier two on a
material other than the panel shader.

**For overlays:** a menu clipping its own scroll is exactly `ClipBox3d`, and
the culling tier is enough for a list of whole items. A sheet with a rounded
corner clipping its content is *not* a clip — a plane region is convex and a
rounded corner is not — it is the corner radius of the decoration underneath
it, which the panel shader already carves out. Do not try to express a radius
as planes.

## What the plan got wrong

- **`Decoration3dPainter` had to be shareable, which changes its shape.** The
  plan says equal decorations share a painter keyed by `cacheKey`, and also
  that a painter "owns mesh + material". Both cannot be true: two panels of
  the same shape at different sizes need different uniform values, so they
  cannot share a material. The resolution is that a painter owns the *shared*
  resource (the mesh) and keys everything per-box on
  `Decoration3dPaintRequest.node`, with `release(node)` to say when one is
  finished with. That is now the documented rule.
- **A `.fmat` fragment shader cannot tell where in the box a fragment is.**
  It is handed a world position, a normal and a UV, and none of those is an
  object-space coordinate — which an SDF over a slab needs. The shipped slab
  is therefore a unit cube whose *vertex colours are its own object-space
  coordinates*, biased into `[0, 1]`; the shader recovers the position with a
  subtract and a multiply, exactly, because a cube's face is planar. Nothing
  in the plan anticipated this and it is the one piece of the design that
  would have blocked it.
- **The slab is authored in layout axes, not scene axes.** `NodeBox3d` undoes
  the surface basis so a model keeps the orientation it was authored with. A
  decoration has no authored orientation to keep and its faces should line up
  with the box, so `Decoration3dPaintRequest.basis` is deliberately unused by
  the shipped painter.
- **The figures are logical pixels, not world units.** The plan says a radius
  is expressed "in dp through the metrics contract" but leaves where the
  conversion happens open. Doing it at paint time rather than at construction
  is what lets one `const BoxDecoration3d` be correct on two surfaces at
  different scales, and it is the same choice `Text3d` makes with
  `TextStyle.fontSize`.
- **The state layer belongs on the box, not the decoration.** Putting it on
  the decoration would have routed a hover through `shouldRebuild`, which is
  the path the plan wanted it to avoid. On the box, the no-relayout rule is
  structural.
- **The discard-versus-shadow caveat is real and is unresolved.** The plan
  asked for it to be checked rather than assumed, and it cannot be checked
  here: nothing in this repository compiles the material. What is *known* from
  the engine's shape is that a shadow pass does not run a surface material's
  `Surface()`, so a rounded panel casts the shadow of its whole slab. At a
  12dp radius on a card that is a small error; on a pill-shaped button it is
  not. Whoever wires the shader into a render lane should look at this first.
- **Whole-node culling cannot use a "wholly inside" early exit.** The first
  implementation stopped descending at a box entirely within the clip. That is
  wrong here in a way it is not in a 2D compositor: a child may overflow its
  parent's extent (a `Column3d` taller than the room it was given is the
  ordinary case), so a parent being inside says nothing about its children.
  The sweep now always descends, stopping only at a transform.

## Out of scope

Material's actual token set (colours, shape scales, elevation levels) — that
is `flutter_scene_material3d`. Text ([its own plan](2026_08_25_text_in_a_3d_layout.md)).
Gradients and images in decorations, until the flat-colour path is proven.
