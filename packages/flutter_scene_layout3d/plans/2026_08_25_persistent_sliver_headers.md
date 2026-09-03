---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-09-03T22:20:00Z
commit: 657eef80eb8dc8085c3b3a84a8069273495506be
---

# Persistent sliver headers, and what pins them in a scene

`SliverAppBar` is the Material component that most defines the feel of a
Material app, and it is unbuildable here. The sliver protocol in this package
deliberately shipped without the fields a persistent header needs, and the
README says so: no pinned or floating headers, no `overlap` on
`SliverConstraints3d`, no `paintOrigin` on `SliverGeometry3d`, no growth
direction and no centre child.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).
Its central problem is clipping, which
[size-driven geometry](2026_08_25_size_driven_geometry.md) owns.

## What exists today

[SliverConstraints3d](../lib/src/sliver/sliver_constraints.dart) carries
`axis`, `scrollOffset`, `precedingScrollExtent`, `remainingPaintExtent`,
`crossAxisExtent`, `depthExtent`, `viewportMainAxisExtent`,
`remainingCacheExtent` and `cacheOrigin`, plus the `paintPortion` and
`cachePortion` helpers a sliver does its arithmetic with.
`SliverGeometry3d` carries `scrollExtent`, `paintExtent`, `layoutExtent`,
`maxPaintExtent`, `hitTestExtent`, `visible` and `scrollOffsetCorrection`.

`scrollOffsetCorrection` is honoured by
[CustomScrollView3d](../lib/src/sliver/custom_scroll_view.dart), which is the
facility a floating header needs and which no built-in sliver currently uses.

The viewport sets `sliver.node.visible = geometry.visible` and places each
sliver from its layout offset — so a sliver that reports a paint extent
different from its scroll extent is already expressible in the placement code.

## The gap, in protocol terms

Two fields and one sliver.

- **`overlap` on `SliverConstraints3d`**: how much of this sliver's leading
  edge is covered by a pinned sliver before it. Without it, content under a
  pinned bar cannot know it is covered.
- **`paintOrigin` on `SliverGeometry3d`**: where the sliver's visible part
  sits relative to its layout position, which is how a pinned header stays at
  the viewport's leading edge while its scroll offset advances. Also
  `maxScrollObstructionExtent`, the amount a pinned sliver permanently
  occludes.
- **`SliverPersistentHeader3d`** with a delegate:
  `minExtent`, `maxExtent`, `build(shrinkOffset, overlapsContent)`, and the
  `pinned` / `floating` variants.

That much is a faithful port and the arithmetic is Flutter's.

## The part that is not a port

**In two dimensions a pinned header simply paints over the content. Here
nothing paints, and there is no clipping.** Content scrolling "under" a pinned
bar in this package keeps drawing, because a scene has no scissor rectangle
and the scrolling views' only culling is whole-child visibility. So a pinned
header without further work shows the list sliding through it.

Three ways out, and the plan should take one and say so:

1. **Depth.** Lift the header toward the viewer with `sceneOffset` — the same
   mechanism `Stack3d.depthStep` uses — so content passes *behind* it rather
   than through it. Honest in 3D, needs no new machinery, and looks right for
   an opaque bar. It does not hide the content, which remains visible beyond
   the bar's silhouette; for a bar that spans the full cross axis that is
   exactly the 2D result, and for a narrower one it is not.
2. **Clip planes** from
   [size-driven geometry](2026_08_25_size_driven_geometry.md): the viewport
   passes a clip plane at its leading edge and fragments beyond it are
   discarded. The faithful answer, and the one that also fixes partial items
   at a viewport's edge everywhere else in the package.
3. **Cull harder.** Hide any child whose box intersects the obstructed
   region. Cheap, and wrong in the obvious way — a half-covered item vanishes
   entirely.

Recommend **(1) now, (2) when it exists**, with the header's lift kept as a
property so the two compose: a pinned bar wants to be in front *and* clipped
against.

## The adjacent items, deliberately not in this plan

`SliverPadding3d`, `SliverFillRemaining3d`, reverse growth direction and a
`center` sliver are all named in the README as absent. They are small,
independent, and each is a distraction from the header problem. List them,
build them when a component asks.

## The work

- [x] **Phase 1 — the fields.** `overlap` on the constraints,
      `paintOrigin` and `maxScrollObstructionExtent` on the geometry, threaded
      through `CustomScrollView3d`'s placement loop, with the existing sliver
      suite green.
- [x] **Phase 2 — `SliverPersistentHeader3d`** and its delegate, non-pinned
      first (a header that scrolls away and shrinks).
- [x] **Phase 3 — pinned**, with the depth lift.
- [x] **Phase 4 — floating**, ~~which is where `scrollOffsetCorrection`
      finally gets a built-in user~~ — it is not; see below.
- [x] **Phase 5 — clipping**, which the clip-plane contract already supports:
      the viewport publishes one plane at the obstruction's trailing edge.
- [x] **Phase 6 — README.**

## What the original reasoning got wrong

- **Floating headers do not use `scrollOffsetCorrection`, and should not.**
  The plan expected phase 4 to be the correction machinery's first built-in
  user. It is not, in Flutter either: `RenderSliverFloatingPersistentHeader`
  keeps a `_effectiveScrollOffset` of its own and reports a `paintExtent`
  larger than its `layoutExtent`, so the bar comes back *over* the content
  without moving it. Asking the viewport to move the scroll offset instead
  would drag the list under the viewer's finger, which is the opposite of
  what floating is for. Implemented Flutter's way; the correction machinery
  is still unused by any built-in, and the README still says so.

- **The choice between depth and clipping was not a choice.** The plan
  recommended "(1) now, (2) when it exists" and the clip contract landed
  first (plan 3), so both shipped together — and they are not alternatives.
  The lift alone leaves a row visible past the bar's silhouette; the clip
  alone leaves a material that ignores planes interpenetrating the bar. Both
  are on, and `lift: 0` turns the first off for a caller who has the second
  covered. The default lift is one logical pixel read from
  `Layout3d.metrics`, not a constant, so it is the same distance on any
  scale.

- **Nothing had to be added to make a material read the plane block.**
  `DecoratedBox3d` already passes its `clipRegion` into the paint request and
  `BoxDecoration3d` already packs `Clip3dRegion.toPlaneBlock()` into its
  uniforms, so publishing the plane from the viewport was the whole of tier
  two for the shipped decoration. A leaf holding an application's own
  material still ignores it, which is what the lift is for.

  *Corrected on 2026-09-03.* The wiring was there and it did not deliver.
  A box publishes its clip block from inside its own `performLayout`, so
  anything that learns its extent afterwards — a `ClipBox3d`, which takes its
  size from its child — imposed nothing on the layout that created the boxes
  under it, and a scroll places rows rather than relaying them out, so nothing
  replaced it. `Layout3d.refreshClipRegion` is what makes the tier actually
  fire; see
  [a clip that reaches the shader](2026_09_03_a_clip_that_reaches_the_shader.md).
  The sentence above is still true of *this* plan's own path — the viewport
  publishes the plane and the decoration packs it — and was never true of the
  package as a whole.

- **The delegate cannot be Flutter's `build` verbatim.** Flutter rebuilds a
  *widget* per layout and lets the element tree diff it; there is no element
  tree under this layer, and building a fresh `Layout3d` subtree every frame
  would churn scene nodes. `build(shrinkOffset, overlapsContent:)` keeps the
  plan's spelling and is still called every layout, but the header adopts
  what it is handed only when it is not what it already holds, and disposes
  what it drops — so the ordinary delegate keeps one subtree and mutates it.

- **`userScrollDirection` does not exist here**, so a floating header cannot
  gate its expansion on the drag direction the way Flutter's does. Any
  backwards movement of the offset brings the bar back by the same amount,
  which is what a viewer dragging the list down expects. If a fling that
  settles backwards ever looks wrong, the fix is a direction on
  `Scroll3dController`, not on the header.

- **Hit test order had to change.** A viewport's leading slivers are in
  *front* of the ones after them, not beside them, so `CustomScrollView3d`
  now tests its slivers in scroll order rather than taking
  `MultiChildLayout3d`'s back-to-front default. Flutter's viewport orders
  them the same way, for the same reason. The lift cannot do this job:
  `ParentData3d.sceneOffset` is undone by `worldTransform`, exactly so that
  moving geometry for the depth buffer does not move a box for a ray.

## Where it landed

- `lib/src/sliver/sliver_constraints.dart`: `SliverConstraints3d.overlap`,
  `SliverGeometry3d.paintOrigin` and
  `SliverGeometry3d.maxScrollObstructionExtent`.
- `lib/src/sliver/custom_scroll_view.dart`: the running paint offset that
  computes `overlap`, placement through `paintOrigin`, sliver-order hit
  testing, and `clipRegionForChild` publishing the obstruction plane.
- `lib/src/sliver/sliver_persistent_header.dart`: `SliverPersistentHeader3d`
  and `SliverPersistentHeader3dDelegate`, with `pinned`, `floating` and
  `lift`.
- `test/persistent_header_test.dart`: twenty tests, and the whole suite green.

## Tests

- A shrinking header reports the expected `scrollExtent`, `paintExtent` and
  `layoutExtent` across a sweep of scroll offsets.
- A pinned header stays at the leading edge: its node's placement is constant
  while the sliver after it moves.
- `overlap` reaches the sliver after a pinned header, and is zero without one.
- A floating header re-entering leaves the scroll position and the content
  where they are — the corrected expectation; see *What the original
  reasoning got wrong*.
- A ray aimed at the header finds the header, not the content behind it.
- Hit testing respects `hitTestExtent` for a partially visible header.

## Out of scope

`SliverPadding3d`, `SliverFillRemaining3d`, reverse growth and a `center`
sliver, as listed above; a declarative `SceneSliverPersistentHeader3d`, which
wants a build scope for the delegate the way the lazy list widgets have one
and is a widget-layer piece rather than a header one;
`NestedScrollView`, snapping animations (they belong to
[animation](2026_08_25_animation_and_scroll_physics.md)), and `SliverAppBar3d`
itself, which lives in the component package.
