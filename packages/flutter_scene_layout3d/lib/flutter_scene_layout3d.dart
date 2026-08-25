/// Flutter's box layout protocol, in three dimensions, for flutter_scene.
///
/// Constraints go down, sizes come up, and the parent decides where the child
/// sits, exactly as in Flutter; the difference is that a box has three
/// extents, a position is a point in space, and the output of layout is a
/// tree of scene [Node] transforms rather than a display list.
///
/// The pieces:
///
///  * [Layout3dSurface], the root. It owns the plane the elements are
///    arranged on; mount its [Layout3dSurface.plane] node in the scene and
///    transform that node to move, turn, or scale the whole layout.
///  * [Layout3d], the box protocol itself ([Layout3d.layout],
///    [Layout3d.performLayout], [Layout3d.place]), with
///    [SingleChildLayout3d] and [MultiChildLayout3d] to build on.
///  * [Constraints3d], [Size3d], [Offset3d], [Alignment3d], [EdgeInsets3d],
///    the value types, each the 3D counterpart of a Flutter one.
///  * [NodeBox3d], the leaf that puts engine content into a layout and
///    measures its bounds to answer how big it is.
///  * [Layout3dSurface.hitTestRay] and [Layout3dPointer], the input half:
///    what a camera ray reaches, and the drag that scrolls it.
///  * [Container3d], [Padding3d], [Align3d], [Center3d], [SizedBox3d],
///    [ConstrainedBox3d], [Transform3d], [Row3d], [Column3d], [Depth3d],
///    [Stack3d], [Positioned3d], [Wrap3d], [Viewport3d], [ListView3d],
///    [GridView3d], the layouts.
///  * [Layout3d.getMaxIntrinsicExtent] and [Layout3d.getDistanceToBaseline],
///    the measurement protocol, with [IntrinsicWidth3d] and [Baseline3d] as
///    the boxes that use it.
///  * [CustomScrollView3d] and the slivers ([SliverList3d], [SliverGrid3d],
///    [SliverToBoxAdapter3d]), a second protocol for sections that share one
///    scroll position.
///  * [Layout3dBuiltChildrenMixin] and [Layout3dMeasuredChildrenMixin], the
///    bookkeeping every view built from an [Layout3dItemBuilder] needs, for
///    writing one of your own.
///
/// The declarative widget layer, which describes the same tree from a Flutter
/// `build` method, is in `package:flutter_scene_layout3d/widgets.dart`.
library;

export 'src/boxes/container.dart' show Container3d;
export 'src/boxes/flex.dart'
    show
        Column3d,
        CrossAxisAlignment3d,
        Depth3d,
        Expanded3d,
        Flex3d,
        FlexFit3d,
        Flexible3d,
        MainAxisAlignment3d,
        MainAxisSize3d,
        Row3d,
        Spacer3d;
export 'src/boxes/ignore_pointer.dart' show AbsorbPointer3d, IgnorePointer3d;
export 'src/boxes/intrinsic.dart'
    show
        Baseline3d,
        IntrinsicDepth3d,
        IntrinsicExtent3d,
        IntrinsicHeight3d,
        IntrinsicWidth3d;
export 'src/boxes/node_box.dart' show BoxFit3d, NodeBox3d;
export 'src/boxes/shifted.dart'
    show Align3d, Center3d, Padding3d, ShiftedLayout3d;
export 'src/boxes/sized.dart' show ConstrainedBox3d, SizedBox3d, Transform3d;
export 'src/boxes/stack.dart' show Positioned3d, Stack3d, StackFit3d;
export 'src/boxes/wrap.dart' show Wrap3d, WrapAlignment3d, WrapCrossAlignment3d;
export 'src/built_children.dart'
    show Layout3dBuiltChildrenMixin, Layout3dMeasuredChildrenMixin;
export 'src/geometry/alignment3d.dart' show Alignment3d;
export 'src/geometry/basis3d.dart' show LayoutBasis3d;
export 'src/geometry/constraints3d.dart' show Constraints3d;
export 'src/geometry/edge_insets3d.dart' show EdgeInsets3d;
export 'src/geometry/offset3d.dart' show Axis3d, Offset3d;
export 'src/geometry/size3d.dart' show Size3d;
export 'src/hit_test.dart' show HitTestEntry3d, HitTestResult3d, Ray3d;
export 'src/input/pointer.dart' show Layout3dPointer;
export 'src/layout3d.dart'
    show
        Layout3d,
        Layout3dChildIntrinsicsMixin,
        Layout3dItemBuilder,
        Layout3dWithChildMixin,
        Layout3dWithChildrenMixin,
        Layout3dOwner,
        MultiChildLayout3d,
        ParentData3d,
        ProxyLayout3d,
        SingleChildLayout3d;
export 'src/scroll/grid_view.dart'
    show
        Grid3dDelegate,
        Grid3dDelegateWithFixedCrossAxisCount,
        Grid3dDelegateWithMaxCrossAxisExtent,
        Grid3dItemBuilder,
        Grid3dLayout,
        GridView3d;
export 'src/scroll/list_view.dart' show ListView3d;
export 'src/scroll/scroll_controller.dart' show Scroll3dController;
export 'src/scroll/scrollable.dart' show Scrollable3d, noIntrinsicExtent;
export 'src/sliver/custom_scroll_view.dart' show CustomScrollView3d;
export 'src/sliver/sliver.dart' show Sliver3d, SliverToBoxAdapter3d;
export 'src/sliver/sliver_constraints.dart'
    show SliverConstraints3d, SliverGeometry3d;
export 'src/sliver/sliver_grid.dart' show SliverGrid3d;
export 'src/sliver/sliver_list.dart' show Sliver3dItemBuilder, SliverList3d;
export 'src/scroll/viewport.dart' show Viewport3d;
export 'src/surface.dart' show Layout3dSurface;
