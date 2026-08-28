import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DoubleProperty, EnumProperty;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../built_children.dart';
import '../geometry/offset3d.dart';
import '../layout3d.dart';
import '../sliver/sliver_list.dart';
import 'box_scroll_view.dart';
import 'scroll_controller.dart';

/// A scrollable line of children, the 3D analogue of [ListView].
///
/// Children are laid out one after another along [scrollDirection] and the
/// list shows the window at [controller]'s offset. Two ways to supply them:
///
///  * the default constructor takes an explicit list; every child is laid out
///    each pass, and the ones outside the window have their nodes hidden
///    rather than removed;
///  * [ListView3d.builder] builds items on demand and keeps only what is near
///    the window, disposing the rest. With [itemExtent] the offsets are
///    arithmetic and nothing off-screen is ever built; without it, items are
///    measured forward from the first and the rest of the extent is estimated
///    from the average, the same approximation Flutter's `SliverList` makes.
///    See [SliverList3d] for what that estimate costs — a scroll range that
///    moves, and a deep jump that measures everything before it. A
///    [prototypeItem] buys the arithmetic back when the items are uniform in
///    a size only the content knows; a [contentExtentEstimator] steadies the
///    range of a list whose items really do differ.
///
/// A list is a viewport over one [SliverList3d], the way Flutter's `ListView`
/// is a `ScrollView` over one `SliverList`: the items are placed by the
/// sliver, and this class is the window and the scroll position around it.
/// [children] still means the items; see [BoxScrollView3d] for what that
/// forwarding covers.
///
/// Unlike Flutter's `ListView`, children are not stretched across the cross
/// axes by default; [crossAxisAlignment] and [depthAxisAlignment] centre them
/// instead, which is the more useful default when the items are objects
/// rather than rows. Ask for [CrossAxisAlignment3d.stretch] to get the
/// Flutter behaviour.
class ListView3d extends BoxScrollView3d<SliverList3d> {
  /// Creates a list over an explicit set of children.
  ListView3d({
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    double spacing = 0.0,
    double? itemExtent,
    Layout3dPrototypeBuilder? prototypeItem,
    Layout3dContentExtentEstimator? contentExtentEstimator,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.center,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double cacheExtent = 0.0,
    List<Layout3d> children = const <Layout3d>[],
    String? name,
  }) : this._(
         SliverList3d(
           spacing: spacing,
           itemExtent: itemExtent,
           prototypeItem: prototypeItem,
           contentExtentEstimator: contentExtentEstimator,
           crossAxisAlignment: crossAxisAlignment,
           depthAxisAlignment: depthAxisAlignment,
           children: children,
         ),
         scrollDirection: scrollDirection,
         controller: controller,
         cacheExtent: cacheExtent,
         name: name,
       );

  /// Creates a list that builds its items on demand.
  ListView3d.builder({
    required int itemCount,
    required Layout3dItemBuilder itemBuilder,
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    double spacing = 0.0,
    double? itemExtent,
    Layout3dPrototypeBuilder? prototypeItem,
    Layout3dContentExtentEstimator? contentExtentEstimator,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.center,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double cacheExtent = 0.0,
    String? name,
  }) : this._(
         SliverList3d.builder(
           itemCount: itemCount,
           itemBuilder: itemBuilder,
           spacing: spacing,
           itemExtent: itemExtent,
           prototypeItem: prototypeItem,
           contentExtentEstimator: contentExtentEstimator,
           crossAxisAlignment: crossAxisAlignment,
           depthAxisAlignment: depthAxisAlignment,
         ),
         scrollDirection: scrollDirection,
         controller: controller,
         cacheExtent: cacheExtent,
         name: name,
       );

  // The sliver has to be built before it can be handed up, and an explicit
  // super call rules out super parameters, so the two constructors above
  // redirect here rather than each repeating the wiring.
  // ignore: use_super_parameters
  ListView3d._(
    SliverList3d sliver, {
    required Axis3d scrollDirection,
    required Scroll3dController? controller,
    required double cacheExtent,
    required String? name,
  }) : super(
         sliver: sliver,
         scrollDirection: scrollDirection,
         controller: controller,
         cacheExtent: cacheExtent,
         name: name,
       );

  /// The gap between adjacent items.
  double get spacing => sliver.spacing;

  set spacing(double value) => sliver.spacing = value;

  /// A fixed extent for every item along the scroll axis.
  ///
  /// Makes a built list exactly lazy, and is mutually exclusive with
  /// [prototypeItem].
  double? get itemExtent => sliver.itemExtent;

  set itemExtent(double? value) => sliver.itemExtent = value;

  /// An item built once and measured, standing for the extent of them all.
  ///
  /// See [Layout3dMeasuredChildrenMixin.prototypeItem].
  Layout3dPrototypeBuilder? get prototypeItem => sliver.prototypeItem;

  set prototypeItem(Layout3dPrototypeBuilder? value) =>
      sliver.prototypeItem = value;

  /// The total extent along the scroll axis, when the caller knows it.
  ///
  /// See [Layout3dMeasuredChildrenMixin.contentExtentEstimator].
  Layout3dContentExtentEstimator? get contentExtentEstimator =>
      sliver.contentExtentEstimator;

  set contentExtentEstimator(Layout3dContentExtentEstimator? value) =>
      sliver.contentExtentEstimator = value;

  /// How items are positioned on the first cross axis.
  CrossAxisAlignment3d get crossAxisAlignment => sliver.crossAxisAlignment;

  set crossAxisAlignment(CrossAxisAlignment3d value) =>
      sliver.crossAxisAlignment = value;

  /// How items are positioned on the second cross axis.
  CrossAxisAlignment3d get depthAxisAlignment => sliver.depthAxisAlignment;

  set depthAxisAlignment(CrossAxisAlignment3d value) =>
      sliver.depthAxisAlignment = value;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('spacing', spacing, defaultValue: 0.0));
    properties.add(
      DoubleProperty('itemExtent', itemExtent, defaultValue: null),
    );
    properties.add(
      EnumProperty<CrossAxisAlignment3d>(
        'crossAxisAlignment',
        crossAxisAlignment,
      ),
    );
  }
}
