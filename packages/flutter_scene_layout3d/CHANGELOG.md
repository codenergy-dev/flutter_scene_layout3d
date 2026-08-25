## Unreleased

- **Breaking:** `Offset3dBox` is gone. It was undocumented, untested, had no
  widget, and was the one public type that did not end in `3d`;
  `Transform3d.translate` does the same thing.
- **Deprecated:** `Grid3dItemBuilder` and `Sliver3dItemBuilder`, which were
  identical to `Layout3dItemBuilder`. That one name now lives beside the
  protocol in `layout3d.dart` and every builder takes it; the two aliases still
  work and will be removed in a later release.
- A `ListView3d.builder`, `GridView3d.builder`, `SliverList3d.builder` or
  `SliverGrid3d.builder` now asserts when its child list is edited from
  outside. A built view tracks its children by index, so a child inserted that
  way was never laid out and never released; the failure used to surface much
  later as a size assert on a box nobody remembered adding. Items come from the
  builder: set `itemCount`, or call `refresh()`.
- `_lastIndexBefore` in `ListView3d` and `SliverList3d` is a binary search
  rather than a linear scan, so the cost of a layout no longer climbs with how
  far the list has ever been scrolled.
- `GridView3d.dispose` clears the map of built cells, as `ListView3d` already
  did.
- Documented what was already true: a `SliverList3d.builder` with no
  `itemExtent` revises its estimated length silently and issues no
  `scrollOffsetCorrection`, so content after it shifts as items are measured;
  `Viewport3d` neither culls nor clips, unlike the lists; the declarative layer
  builds every child widget up front, and lazy *widgets* need a
  `RenderObjectElement` this layer does not have (the old note promised the
  sliver work would bring it, which it did not); `Layout3dController` reaches
  the surface and its plane node, not measured sizes or scroll positions; and
  `examples/smoke_render` has five layout scenes, not two.

- Fixed: `Stack3d.depthStep` moved its children in the *layout*, which broke
  the two things the stack promises. A `Positioned3d` pinned to a face landed
  short of it by the step, and a coplanar child was pushed in front of the
  stack's own front face, where the ray gate could not reach it — so on a flat
  stack, the child on top became the one hit testing could not find, the exact
  inverse of the documented rule. The step is now written to
  `ParentData3d.sceneOffset`, a new per-child offset that moves the scene node
  and nothing else: the geometry separates in the depth buffer, and the layout,
  the pins and the hit test are untouched. `Stack3d` sizing is unchanged.
- `ParentData3d.sceneOffset` and `Layout3d.sceneOffset`, for a parent that
  needs to nudge a child's geometry without moving its box.
  `Layout3d.worldTransform` undoes it, so it still describes the layout frame.
- Fixed: `ListView3d.itemCount` reported the count captured when the list was
  built, so it went stale as soon as a child was added or removed. It now
  follows the child list, as `GridView3d`, `SliverList3d` and `SliverGrid3d`
  already did.
- A non-sliver child of a `CustomScrollView3d` now asserts as it is adopted,
  naming `SliverToBoxAdapter3d`, instead of failing as a bare cast error in the
  middle of layout. The constructor was typed, but `add`, `insert` and
  `syncChildren` come from the child-list mixin and the declarative layer
  passes plain widgets.

## 0.5.0

- Intrinsic sizing: `Layout3d.getMinIntrinsicExtent` and `getMaxIntrinsicExtent`
  ask a box how much room it would like, one axis at a time. Flutter's four
  methods would be six with a third axis, so the axis is a parameter and the
  `Size3d` beside it carries the limits on the other two.
- `IntrinsicWidth3d`, `IntrinsicHeight3d` and `IntrinsicDepth3d` (over a shared
  `IntrinsicExtent3d`), which size their child to the extent it asks for, with
  Flutter's `stepWidth` under the name `step`.
- Baselines: `Layout3d.getDistanceToBaseline`, `Baseline3d`, and
  `CrossAxisAlignment3d.baseline`, so a line of content can hang from a line
  inside it rather than from an edge. A baseline belongs to an axis here, and
  `Baseline3d` declares one outright, because nothing in a scene reports one
  the way text does.
- Every box answers for itself: `NodeBox3d` measures the content it holds,
  `Padding3d` and `Container3d` add their insets, `SizedBox3d` answers from its
  fixed extents without asking the child, and `Flex3d`, `Stack3d` and `Wrap3d`
  are ported from their Flutter counterparts. A `Wrap3d`'s answer across its
  runs is the one-run lower bound; the rest are exact.
- The scrolling views refuse the question, as Flutter's viewport does: a
  viewport's content is whatever length it is, and the view exists so that it
  need not grow to match.
- Answers are cached until the box goes dirty, and a box whose answer was taken
  pushes its dirt up past its own relayout boundary, because a parent decided
  something from a number that has just gone stale.
- `SceneIntrinsicWidth3d`, `SceneIntrinsicHeight3d`, `SceneIntrinsicDepth3d` and
  `SceneBaseline3d` in the declarative layer.
- `Constraints3d.hasTightAlong` and `tightenAlong`, `EdgeInsets3d.alongAxis` and
  `lowAlong`.

## 0.4.0

- The sliver protocol: `SliverConstraints3d` and `SliverGeometry3d`, and
  `Sliver3d`, a layout that answers a window rather than a size. The box
  protocol is the wrong shape for "there are ten thousand of these and you can
  see nine"; this is the one Flutter reaches for, ported.
- `CustomScrollView3d`, a viewport that puts several sections on one scroll
  position and gives each only the part of the window it can see. It honours
  `SliverGeometry3d.scrollOffsetCorrection`, so a sliver that finds its content
  elsewhere mid-layout can move the offset and have the pass run again.
- `SliverList3d`, `SliverGrid3d` (sharing `GridView3d`'s `Grid3dDelegate`) and
  `SliverToBoxAdapter3d`, the glue that gives an ordinary box its turn.
- `SceneCustomScrollView3d`, `SceneSliverList3d`, `SceneSliverGrid3d` and
  `SceneSliverToBoxAdapter3d` in the declarative layer. Child widgets are still
  built up front there; only the imperative builders are lazy.
- `Layout3dWithChildMixin` and `Layout3dWithChildrenMixin`, extracted from
  `SingleChildLayout3d` and `MultiChildLayout3d` so a sliver can hold children
  without being a box.
- `Scroll3dController.correctBy`, for a viewport applying a correction during
  its own layout.
- Fixed: `Scroll3dController.contentExtent` reported the viewport's extent for
  content shorter than the window, because the scroll range alone cannot tell
  the two apart. Views now report the extent they measured.

## 0.3.0

- `Wrap3d`, which breaks into runs where a flex would overflow. Runs stack on
  the first cross axis only; the depth axis aligns children rather than
  wrapping them, so a wrap of models stays a readable plane.
- `GridView3d`, laying cells out on a grid a `Grid3dDelegate` decides from the
  room across the scroll axis, with `Grid3dDelegateWithFixedCrossAxisCount`
  and `Grid3dDelegateWithMaxCrossAxisExtent` provided.
- `GridView3d.builder` is exactly lazy: cell positions are arithmetic, so the
  total extent is known without building anything, and only the window (plus
  `cacheExtent`) is ever built.
- `Grid3dLayout` exposes that arithmetic on its own, for callers that want to
  know where a cell lands without asking the view.
- `SceneWrap3d` and `SceneGridView3d` in the declarative layer. An unchanged
  grid delegate does not relayout, the way Flutter's `shouldRelayout` works.

## 0.2.0

- Hit testing, the other half of the layout protocol. `Layout3d.hitTest` walks
  the tree with a `Ray3d` rather than a point, because in a scene the pointer
  is a direction and the boxes stand at different depths; a box bounds the
  stretch of ray its children can be found in, which is the 3D form of
  Flutter's `size.contains(position)` gate.
- `Layout3dSurface.hitTestRay` brings a camera ray into layout space (the
  surface node already carries the basis, so its inverse world transform is
  the whole conversion), and `hitTestAt` asks with a point on the plane.
- `HitTestResult3d` reports the boxes hit, deepest first, with
  `firstOf<T>()` to pick an ancestor such as the list a finger landed in.
- `Layout3dPointer` turns pointer rays into scrolling. It measures the drag on
  the grabbed view's own plane rather than across the screen, so content stays
  under the finger at any viewing angle, and it keeps the grab until release.
- `Scrollable3d`, implemented by `Viewport3d` and `ListView3d`, which are now
  opaque to hits across their whole window so a drag can start on a gap.
- `IgnorePointer3d` and `AbsorbPointer3d`, plus their `Scene`-prefixed
  widgets. `NodeBox3d` answers hits on its own account; boxes that only
  arrange others do not. `Transform3d` neither answers nor gates, matching
  Flutter's `RenderTransform`.
- `Layout3d.worldTransform`, the transform from a box's own frame to world
  space.

## 0.1.0

- Initial release. Flutter's box layout protocol in three dimensions, laid out
  on a freely transformable plane in a flutter_scene scene.
- Core protocol: `Layout3dSurface`, `Layout3d`, `SingleChildLayout3d`,
  `MultiChildLayout3d`, `ProxyLayout3d`, `Layout3dOwner`, with relayout
  boundaries and a dirty-list flush.
- Value types: `Constraints3d`, `Size3d`, `Offset3d`, `Alignment3d`,
  `EdgeInsets3d`, `Axis3d`, and `LayoutBasis3d` for mapping layout space onto
  the plane (`xy` upright, `xz` on the ground, or any invertible matrix).
- Layouts: `Container3d`, `Padding3d`, `Align3d`, `Center3d`, `SizedBox3d`,
  `ConstrainedBox3d`, `Transform3d`, `Row3d`, `Column3d`, `Depth3d`,
  `Flexible3d`, `Expanded3d`, `Spacer3d`, `Stack3d`, `Positioned3d`.
- `NodeBox3d`, which measures engine content through
  `Node.combinedLocalBounds` and fits it into the box.
- Scrolling: `Viewport3d`, `ListView3d` (explicit children or a lazy
  `ListView3d.builder`), and `Scroll3dController`.
- A declarative widget layer in `package:flutter_scene_layout3d/widgets.dart`:
  `SceneLayout3d` plus a `Scene`-prefixed widget for every layout, reconciled
  through the Flutter element tree.
- The built-in bases follow the engine's screen convention (flutter_scene
  builds its camera basis with `right = up x forward`, so world `-x` is screen
  right for a camera facing a plane), which is what makes a `Row3d` read left
  to right on screen.
- `BoxFit3d` follows `FittedBox`: the box takes the size the constraints and
  the measurement give it, and the fit scales the content into that box, so a
  loose parent never inflates the box and an axis with no room does not
  collapse the content.
