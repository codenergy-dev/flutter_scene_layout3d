---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-09-01T16:30:00Z
commit: 657eef80eb8dc8085c3b3a84a8069273495506be
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
      slab. The discard/shadow check is answered rather than done, and the
      answer is not the one this plan expected — see *What the plan got
      wrong* below.
- [x] **Phase 3 — elevation.** `metrics.dp(elevation)` toward the viewer, as
      a `localTransform` on the decorated box with `hitTestTransform` null, so
      the lift moves geometry and not the layout box. Surface tint is a
      uniform, its amount from Material 3's published table
      (`BoxDecoration3d.surfaceTintOpacityFor`). The worked example against
      the engine's shadows is not there, and cannot be: the panel material is
      not a shadow caster in this engine at all. `examples/render_probe`'s
      `panel_shadow` scene is what stands in its place, and the elevation
      probe beside it checks the thing that *is* real — the lift, through the
      perspective it produces.
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
- [x] **Phase 6 — the two engine-dependent items.** Clip planes landed, and
      the contract is `ClipPlane3d` / `Clip3dRegion` / `ClipBox3d` in
      `lib/src/clip.dart` (see *The clip contract* below). Subtree opacity is
      **designed and deliberately not shipped**, by this plan's own rule: it
      needs a per-node opacity in `flutter_scene` and there is none, so an
      `Opacity3d` here could only fade a `BoxDecoration3d` and the plan says
      not to write that. See *Subtree opacity, and exactly what is missing*
      below for what the engine would have to grow. That makes it out of
      scope here rather than an open item.

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

And on a GPU, in `examples/render_probe` — twenty-one scenes and nineteen
named tests there today, five scenes and four tests of them this plan's:

- [x] A 60dp radius carves the corners away, against a square control.
- [x] Elevation lifts the panel *toward the viewer*: the lifted panel projects
      wider than the identical flat one, and the frame has geometry between
      the two projected edges where the flat one has none.
- [x] A border draws in its own colour at the rim and not in the middle —
      asserted as a direction (which colour is where) rather than a distance,
      which is what caught the shader drawing it inside out.
- [x] A state layer lightens the same panel, against the same control.
- [x] A rounded panel's silhouette and its cast shadow. **Answered, not
      checked**: there is no cast shadow to compare a silhouette against.
      `panel_shadow` draws an opaque cube and a decorated panel side by side
      over a ground plane under one shadow-casting light; the cube's shadow is
      the control that proves the light and the receiving ground work, and the
      panel leaves the ground unchanged. The engine reason is in *What the
      plan got wrong*.

## What happened

All six phases landed. The shader bet paid: one `.fmat`, one shared slab, and
a card, a button, an app bar and a dialog are that object with different
numbers in it. A size change writes sixteen floats and a state change writes
one colour; nothing on either path allocates.

The plan stayed open long after the code was written, for one reason: nothing
in this repository could draw. `2026_08_28_render_coverage.md` fixed that —
`examples/render_probe`'s build hook is the first thing in either repository
to run `impellerc` over `assets/box_decoration3d.fmat` — and the remaining
items were then either ordinary work or an engine question with an answer.
Both are now done.

**The probes found a bug in the shipped shader.** The border was drawn inside
out: `1.0 - smoothstep(-border - aa, -border + aa, d)` is 1 deep inside the
panel and 0 at its edge, so a bordered panel came out entirely in the border
colour with the fill as a thin rim around it — the exact inverse of a border.
Sixty-two headless tests and a parse-and-declare check of the `.fmat` all
passed over it, because every one of them is about the parameters and not
about the picture. The fix is dropping the `1.0 -`. Nothing else in this
package changed.

Measured, by putting the old line back and running the lane again: on a panel
filled `0xFF1B3A6B` with a 40dp `0xFFEA9F26` border, a disc a tenth of a unit
in from the top edge — squarely inside the border band — read
`(r 0.545, g 0.558, b 0.592)`. Blue-dominant: the *fill*, where the amber
border should be. With the fix it is red-dominant, and all forty render tests
pass.

**The shadow question turned out to have a different answer than the plan
assumed**, and a sharper one: not "the shadow is the slab's" but "there is no
shadow". See below.

**The plan's own front matter had lost its `created_at`, `updated_at` and
`commit` fields** somewhere in an earlier edit, which quietly made the
overview's claim that every plan's `commit:` resolves false. Restored to the
values its ten siblings carry.

## Subtree opacity, and exactly what is missing

Checked against `flutter_scene` 0.23.0, so the next reader does not have to
re-derive it. **`Node` has no opacity and no tint.** Its per-node rendering
dials are `visible`, `highlightColor` (a selection *outline* colour that the
selection-outline pass reads — it explicitly "does not affect the node's
normal rendering", so it is not a tint), `layers`, `lightChannelMask`,
`castsShadows`, `shadowStatic` and `raycastable`. The only `opacity` anywhere
in the engine's public surface belongs to `SplatComponent` / `SplatGeometry`,
a global multiplier on a Gaussian-splat cloud, which composes down nothing.

So the design in *Visibility, opacity and clipping* stands unimplemented and
unchanged: an `Opacity3d` written here could only reach `BoxDecoration3d`,
whose alpha this package does control, and would silently do nothing to a
`Text3d`, a `NodeBox3d` or a loaded model. That is the thing the plan told its
implementer not to ship, and it is still the right call.

What the engine would have to add, in one sentence: **an opacity on `Node`
that composes down the graph the way a transform does and that every material
multiplies into its already-premultiplied output**, plus the pass move that
comes with it — a fading subtree has to go to the translucent pass and back,
which is material state rather than a uniform. Given that, `Opacity3d` is a
`ProxyLayout3d` that writes `node.opacity` and nothing else.

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
- **The discard-versus-shadow caveat was right to raise and wrong about the
  answer.** The plan asked for the shadow to be checked rather than assumed,
  and every later revision of this file recorded the guess as though it were
  the finding: *a shadow pass does not run `Surface()`, so a rounded panel
  casts the shadow of its whole slab.* Now that a lane compiles and draws the
  material, the real answer is one step further along and simpler: **a
  decorated panel casts no shadow at all.**

  Two engine facts, in the order they bite, both in `flutter_scene` 0.23.0:

  1. `ShadowEncoder._submit` rejects an item outright when
     `!item.material.isOpaque()`, and a `PreprocessedMaterial` is opaque only
     when its `.fmat` declares `blending: opaque`. `box_decoration3d.fmat`
     declares `blending: alpha`, because the SDF's coverage is an alpha and
     the outline would otherwise be a staircase. So the panel never reaches a
     shadow map, and the silhouette question cannot even be posed. The same
     gate is `depthPrepassParticipates`, so it is out of the depth prepass
     too.
  2. If it *were* opaque, the guess would then be correct and the shadow
     would be the whole rectangular slab: the shadow pass pairs the geometry's
     vertex shader with the engine's `DepthOnlyFragment` and never runs the
     material's own `Surface()`, so neither the SDF nor its `discard` is
     evaluated. The one cutout path the engine offers — `depthAlphaMasked`,
     which switches the pass to `DepthOnlyMaskedFragment` — is driven by
     `configureDepthAlphaMask(texture: ...)`, a *texture's* alpha and a
     cutoff. A silhouette computed in the fragment shader has no texture to
     hand it, so that path is closed to this material as written.

  `examples/render_probe`'s `panel_shadow` scene is the demonstration, and it
  is built as a pair for the usual reason: an opaque cube beside the panel,
  the same size at the same height under the same light, casts a shadow that
  darkens the ground by a clear margin, and the panel's patch of ground is
  within a few per cent of the unshaded one. The test asserts that defect on
  purpose, and says so, so that the day the engine changes it fails and
  someone rereads this.

  So *Elevation, which 3D gets for free* is wrong where it says "the shadow
  comes from the scene's own lighting", and so was every later doc that
  repeated it. What elevation actually costs a component library: it is a real
  height and a real parallax, and it is *not* a contact shadow. A raised card
  reads as raised because it moves and occludes, not because it is grounded.
  Anything wanting the shadow has to put it there itself — the engine's
  `ShadowCatcherMaterial` on a plane under the card is the shape of that, and
  it is a component-library decision rather than a layout one.

- **A shader's arithmetic being tested is not the same as its picture being
  tested, and the border proved it.** `BoxDecoration3dUniforms` is pinned down
  by unit tests, the `.fmat` is parsed and checked to declare every parameter
  the Dart side writes, and the border was still drawn inside out — the fill
  as a rim around a panel entirely in the border colour. The first probe ever
  aimed at a bordered panel found it. The general form is worth carrying: a
  test that asserts a *difference* between two points ("the rim is not the
  middle") passes just as happily when the two are swapped. The probe here
  asks which colour is where, by a channel comparison that lighting, exposure
  and tone mapping cannot reorder.

- **A projection follows an elevated panel's geometry, not its layout box.**
  `Layout3d.worldTransform` undoes `hitTestTransform`, and `DecoratedBox3d`
  returns null from it so that a ray keeps reaching the box where layout put
  it — which means the elevation's `localTransform` is *not* undone, and
  `screenCenter`, `screenPointOf` and `screenBounds` all report the lifted
  position. That is the right answer for a render probe and a debug overlay,
  and it is a surprise if you came from the elevation dartdoc, which is all
  about what the lift deliberately does not move. Both halves are true: the
  geometry moves and the hit test does not.
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
