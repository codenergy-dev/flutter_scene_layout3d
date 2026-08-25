---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
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

- [ ] **Phase 1 — the fields.** `overlap` on the constraints,
      `paintOrigin` and `maxScrollObstructionExtent` on the geometry, threaded
      through `CustomScrollView3d`'s placement loop, with the existing sliver
      suite green.
- [ ] **Phase 2 — `SliverPersistentHeader3d`** and its delegate, non-pinned
      first (a header that scrolls away and shrinks).
- [ ] **Phase 3 — pinned**, with the depth lift.
- [ ] **Phase 4 — floating**, which is where `scrollOffsetCorrection` finally
      gets a built-in user.
- [ ] **Phase 5 — clipping**, once the clip-plane contract exists.
- [ ] **Phase 6 — README.** The *How it differs from Flutter* bullet that
      says pinned and floating headers do not exist has to change in the same
      pass, and gain the depth-lift explanation.

## Tests

- A shrinking header reports the expected `scrollExtent`, `paintExtent` and
  `layoutExtent` across a sweep of scroll offsets.
- A pinned header stays at the leading edge: its node's placement is constant
  while the sliver after it moves.
- `overlap` reaches the sliver after a pinned header, and is zero without one.
- A floating header re-entering applies a `scrollOffsetCorrection` and the
  pass re-runs (the existing correction machinery, exercised for the first
  time by a built-in).
- A ray aimed at the header finds the header, not the content behind it.
- Hit testing respects `hitTestExtent` for a partially visible header.

## Out of scope

`NestedScrollView`, snapping animations (they belong to
[animation](2026_08_25_animation_and_scroll_physics.md)), and `SliverAppBar3d`
itself, which lives in the component package.
