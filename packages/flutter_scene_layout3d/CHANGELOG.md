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
