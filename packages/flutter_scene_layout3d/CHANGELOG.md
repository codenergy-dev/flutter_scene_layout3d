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
