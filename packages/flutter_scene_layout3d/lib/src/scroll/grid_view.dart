import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../geometry/offset3d.dart';
import '../layout3d.dart';
import '../sliver/sliver_grid.dart';
import 'box_scroll_view.dart';
import 'grid_delegate.dart';
import 'scroll_controller.dart';

/// Builds the layout for one cell of a [GridView3d.builder].
@Deprecated(
  'Use Layout3dItemBuilder, which every builder in the package shares. '
  'This alias will be removed in a future release.',
)
typedef Grid3dItemBuilder = Layout3dItemBuilder;

/// A scrollable grid of equal cells, the 3D analogue of [GridView].
///
/// [gridDelegate] turns the room available across the scroll axis into a cell
/// grid, and the children are laid out into it tightly. Because every cell
/// position is arithmetic, [GridView3d.builder] is exactly lazy: nothing
/// outside the window (plus [cacheExtent]) is ever built, with no estimating
/// and no measuring pass.
///
/// The depth axis is the one the grid does not use. Cells are given the depth
/// available and [depthAxisAlignment] places a shallower child inside it, so
/// a grid of models of different thicknesses lines up on whichever face you
/// choose.
///
/// A grid is a viewport over one [SliverGrid3d], the way Flutter's `GridView`
/// is a `ScrollView` over one `SliverGrid`, and that sliver is where the
/// cells are placed. [children] still means the cells; see [BoxScrollView3d].
class GridView3d extends BoxScrollView3d<SliverGrid3d> {
  /// Creates a grid over an explicit set of children.
  GridView3d({
    required Grid3dDelegate gridDelegate,
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double cacheExtent = 0.0,
    List<Layout3d> children = const <Layout3d>[],
    String? name,
  }) : this._(
         SliverGrid3d(
           gridDelegate: gridDelegate,
           depthAxisAlignment: depthAxisAlignment,
           children: children,
         ),
         scrollDirection: scrollDirection,
         controller: controller,
         cacheExtent: cacheExtent,
         name: name,
       );

  /// Creates a grid that builds its cells on demand.
  GridView3d.builder({
    required Grid3dDelegate gridDelegate,
    required int itemCount,
    required Layout3dItemBuilder itemBuilder,
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double cacheExtent = 0.0,
    String? name,
  }) : this._(
         SliverGrid3d.builder(
           gridDelegate: gridDelegate,
           itemCount: itemCount,
           itemBuilder: itemBuilder,
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
  GridView3d._(
    SliverGrid3d sliver, {
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

  @override
  String get itemNoun => 'cells';

  /// Decides the cell grid from the room available.
  Grid3dDelegate get gridDelegate => sliver.gridDelegate;

  set gridDelegate(Grid3dDelegate value) => sliver.gridDelegate = value;

  /// How a cell's child sits on the depth axis.
  CrossAxisAlignment3d get depthAxisAlignment => sliver.depthAxisAlignment;

  set depthAxisAlignment(CrossAxisAlignment3d value) =>
      sliver.depthAxisAlignment = value;

  /// The cell grid in force after the most recent layout.
  Grid3dLayout? get gridLayout => sliver.gridLayout;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<Grid3dDelegate>('gridDelegate', gridDelegate),
    );
    properties.add(
      DiagnosticsProperty<Grid3dLayout>(
        'gridLayout',
        gridLayout,
        defaultValue: null,
      ),
    );
  }
}
