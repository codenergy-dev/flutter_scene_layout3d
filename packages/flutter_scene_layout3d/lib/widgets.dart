/// The declarative layer of `flutter_scene_layout3d`: 3D layout described
/// from a Flutter `build` method.
///
/// Each widget owns one of the layout objects from the imperative library and
/// applies property changes to it on rebuild, so an unchanged rebuild writes
/// nothing. The widgets live in the element tree (as zero-sized boxes that
/// paint nothing), which is what reconciles the layout tree: added, removed,
/// moved, and reordered children are handled by the same machinery every
/// other Flutter widget uses.
///
/// Start with [SceneLayout3d], the surface, among a `SceneView`'s children.
/// The value types ([Size3d], [Constraints3d], [EdgeInsets3d],
/// [Alignment3d], the alignment enums) are re-exported here, so this import
/// is usually all a declarative app needs.
///
/// ```dart
/// SceneView.declarative(
///   children: [
///     SceneLayout3d(
///       size: const Size3d(4, 3, 0.5),
///       child: SceneRow3d(
///         mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
///         children: [
///           SceneNodeBox3d(content: cube),
///           SceneExpanded3d(child: SceneNodeBox3d(content: banner)),
///         ],
///       ),
///     ),
///   ],
/// )
/// ```
library;

export 'src/boxes/flex.dart'
    show CrossAxisAlignment3d, FlexFit3d, MainAxisAlignment3d, MainAxisSize3d;
export 'src/boxes/node_box.dart' show BoxFit3d;
export 'src/boxes/stack.dart' show StackFit3d;
export 'src/geometry/alignment3d.dart' show Alignment3d;
export 'src/geometry/basis3d.dart' show LayoutBasis3d;
export 'src/geometry/constraints3d.dart' show Constraints3d;
export 'src/geometry/edge_insets3d.dart' show EdgeInsets3d;
export 'src/geometry/offset3d.dart' show Axis3d, Offset3d;
export 'src/geometry/size3d.dart' show Size3d;
export 'src/hit_test.dart' show HitTestEntry3d, HitTestResult3d, Ray3d;
export 'src/input/pointer.dart' show Layout3dPointer;
export 'src/layout3d.dart' show Layout3d;
export 'src/scroll/scroll_controller.dart' show Scroll3dController;
export 'src/scroll/scrollable.dart' show Scrollable3d;
export 'src/surface.dart' show Layout3dSurface;
export 'src/widgets/framework.dart'
    show Layout3dWidget, SingleChildLayout3dWidget;
export 'src/widgets/layouts.dart'
    show
        SceneAbsorbPointer3d,
        SceneAlign3d,
        SceneCenter3d,
        SceneColumn3d,
        SceneConstrainedBox3d,
        SceneContainer3d,
        SceneDepth3d,
        SceneExpanded3d,
        SceneFlex3d,
        SceneFlexible3d,
        SceneIgnorePointer3d,
        SceneListView3d,
        SceneNodeBox3d,
        ScenePadding3d,
        ScenePositioned3d,
        SceneRow3d,
        SceneSizedBox3d,
        SceneSpacer3d,
        SceneStack3d,
        SceneTransform3d,
        SceneViewport3d;
export 'src/widgets/surface.dart' show Layout3dController, SceneLayout3d;
