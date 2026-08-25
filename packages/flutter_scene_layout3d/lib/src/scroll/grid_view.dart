import 'dart:math' as math;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../built_children.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'scroll_controller.dart';
import 'scrollable.dart';

/// Builds the layout for one cell of a [GridView3d.builder].
@Deprecated(
  'Use Layout3dItemBuilder, which every builder in the package shares. '
  'This alias will be removed in a future release.',
)
typedef Grid3dItemBuilder = Layout3dItemBuilder;

/// The cell grid a [GridView3d] places its children on, the 3D analogue of
/// [SliverGridLayout].
///
/// Every position is arithmetic: given an index, the offsets fall out without
/// measuring anything. That is what makes a grid exactly lazy where a list of
/// free-sized items can only estimate.
class Grid3dLayout {
  /// Creates a grid of equal cells.
  const Grid3dLayout({
    required this.crossAxisCount,
    required this.cellCrossAxisExtent,
    required this.cellMainAxisExtent,
    this.crossAxisSpacing = 0.0,
    this.mainAxisSpacing = 0.0,
  }) : assert(crossAxisCount > 0),
       assert(cellCrossAxisExtent >= 0.0),
       assert(cellMainAxisExtent >= 0.0);

  /// How many cells sit side by side across the scroll axis.
  final int crossAxisCount;

  /// The extent of one cell across the scroll axis.
  final double cellCrossAxisExtent;

  /// The extent of one cell along the scroll axis.
  final double cellMainAxisExtent;

  /// The gap between neighbouring cells across the scroll axis.
  final double crossAxisSpacing;

  /// The gap between neighbouring rows along the scroll axis.
  final double mainAxisSpacing;

  /// The distance from one row's start to the next.
  double get mainAxisStride => cellMainAxisExtent + mainAxisSpacing;

  /// The distance from one column's start to the next.
  double get crossAxisStride => cellCrossAxisExtent + crossAxisSpacing;

  /// How many rows [childCount] children fill.
  int rowCountFor(int childCount) =>
      childCount <= 0 ? 0 : (childCount / crossAxisCount).ceil();

  /// The extent [childCount] children occupy along the scroll axis.
  double mainExtentFor(int childCount) {
    final rows = rowCountFor(childCount);
    return rows == 0 ? 0.0 : rows * mainAxisStride - mainAxisSpacing;
  }

  /// Where the cell at [index] starts along the scroll axis.
  double mainAxisOffsetOf(int index) =>
      (index ~/ crossAxisCount) * mainAxisStride;

  /// Where the cell at [index] starts across the scroll axis.
  double crossAxisOffsetOf(int index) =>
      (index % crossAxisCount) * crossAxisStride;

  /// The first index of the row covering [mainOffset], never below zero.
  int firstIndexAt(double mainOffset) {
    if (mainAxisStride <= 0.0) return 0;
    final row = math.max(0, (mainOffset / mainAxisStride).floor());
    return row * crossAxisCount;
  }

  /// The last index of the row covering [mainOffset], never past the end.
  int lastIndexAt(double mainOffset, int childCount) {
    if (childCount <= 0) return -1;
    if (mainAxisStride <= 0.0) return childCount - 1;
    final row = math.max(0, (mainOffset / mainAxisStride).floor());
    return math.min(childCount - 1, (row + 1) * crossAxisCount - 1);
  }

  @override
  String toString() =>
      'Grid3dLayout($crossAxisCount x $cellCrossAxisExtent by '
      '$cellMainAxisExtent)';
}

/// Decides the cell grid from the room a [GridView3d] has across its scroll
/// axis, the 3D analogue of [SliverGridDelegate].
abstract class Grid3dDelegate {
  /// Allows subclasses to be const.
  const Grid3dDelegate();

  /// The grid to use when [crossAxisExtent] is available across the scroll
  /// axis.
  Grid3dLayout layoutFor(double crossAxisExtent);

  /// Whether a grid built by [oldDelegate] has to be laid out again.
  ///
  /// The declarative layer hands over a fresh delegate on every rebuild, so
  /// this is what keeps an unchanged one from relaying out the grid.
  bool shouldRelayout(covariant Grid3dDelegate oldDelegate);
}

/// A grid of a fixed number of cells across, the 3D analogue of
/// [SliverGridDelegateWithFixedCrossAxisCount].
class Grid3dDelegateWithFixedCrossAxisCount extends Grid3dDelegate {
  /// Creates a delegate laying out [crossAxisCount] cells side by side.
  const Grid3dDelegateWithFixedCrossAxisCount({
    required this.crossAxisCount,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.childAspectRatio = 1.0,
    this.mainAxisExtent,
  }) : assert(crossAxisCount > 0),
       assert(mainAxisSpacing >= 0.0),
       assert(crossAxisSpacing >= 0.0),
       assert(childAspectRatio > 0.0),
       assert(mainAxisExtent == null || mainAxisExtent >= 0.0);

  /// How many cells sit side by side.
  final int crossAxisCount;

  /// The gap between rows.
  final double mainAxisSpacing;

  /// The gap between columns.
  final double crossAxisSpacing;

  /// A cell's cross extent divided by its main extent, used when
  /// [mainAxisExtent] is null.
  final double childAspectRatio;

  /// A fixed main-axis extent for a cell, overriding [childAspectRatio].
  final double? mainAxisExtent;

  @override
  Grid3dLayout layoutFor(double crossAxisExtent) {
    final usable = math.max(
      0.0,
      crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
    );
    final cellCross = usable / crossAxisCount;
    return Grid3dLayout(
      crossAxisCount: crossAxisCount,
      cellCrossAxisExtent: cellCross,
      cellMainAxisExtent: mainAxisExtent ?? cellCross / childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }

  @override
  bool shouldRelayout(Grid3dDelegateWithFixedCrossAxisCount oldDelegate) =>
      oldDelegate.crossAxisCount != crossAxisCount ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing ||
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.childAspectRatio != childAspectRatio ||
      oldDelegate.mainAxisExtent != mainAxisExtent;
}

/// A grid of as many cells as fit within a maximum cell size, the 3D
/// analogue of [SliverGridDelegateWithMaxCrossAxisExtent].
class Grid3dDelegateWithMaxCrossAxisExtent extends Grid3dDelegate {
  /// Creates a delegate whose cells are at most [maxCrossAxisExtent] across.
  const Grid3dDelegateWithMaxCrossAxisExtent({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.childAspectRatio = 1.0,
    this.mainAxisExtent,
  }) : assert(maxCrossAxisExtent > 0.0),
       assert(mainAxisSpacing >= 0.0),
       assert(crossAxisSpacing >= 0.0),
       assert(childAspectRatio > 0.0),
       assert(mainAxisExtent == null || mainAxisExtent >= 0.0);

  /// The largest a cell may be across the scroll axis.
  final double maxCrossAxisExtent;

  /// The gap between rows.
  final double mainAxisSpacing;

  /// The gap between columns.
  final double crossAxisSpacing;

  /// A cell's cross extent divided by its main extent, used when
  /// [mainAxisExtent] is null.
  final double childAspectRatio;

  /// A fixed main-axis extent for a cell, overriding [childAspectRatio].
  final double? mainAxisExtent;

  @override
  Grid3dLayout layoutFor(double crossAxisExtent) {
    final count = math.max(
      1,
      (crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing)).ceil(),
    );
    final usable = math.max(
      0.0,
      crossAxisExtent - crossAxisSpacing * (count - 1),
    );
    final cellCross = usable / count;
    return Grid3dLayout(
      crossAxisCount: count,
      cellCrossAxisExtent: cellCross,
      cellMainAxisExtent: mainAxisExtent ?? cellCross / childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }

  @override
  bool shouldRelayout(Grid3dDelegateWithMaxCrossAxisExtent oldDelegate) =>
      oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing ||
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.childAspectRatio != childAspectRatio ||
      oldDelegate.mainAxisExtent != mainAxisExtent;
}

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
class GridView3d extends MultiChildLayout3d<ParentData3d>
    with Layout3dBuiltChildrenMixin<ParentData3d>
    implements Scrollable3d {
  /// Creates a grid over an explicit set of children.
  GridView3d({
    required Grid3dDelegate gridDelegate,
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double cacheExtent = 0.0,
    List<Layout3d> children = const <Layout3d>[],
    super.name,
  }) : _gridDelegate = gridDelegate,
       _axis = scrollDirection,
       _controller = controller ?? Scroll3dController(),
       _ownsController = controller == null,
       _depthAxisAlignment = depthAxisAlignment,
       _cacheExtent = cacheExtent,
       _builder = null,
       assert(cacheExtent >= 0.0),
       super(children: children) {
    _controller.addListener(_handleScrollChanged);
  }

  /// Creates a grid that builds its cells on demand.
  GridView3d.builder({
    required Grid3dDelegate gridDelegate,
    required int itemCount,
    required Layout3dItemBuilder itemBuilder,
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double cacheExtent = 0.0,
    super.name,
  }) : _gridDelegate = gridDelegate,
       _axis = scrollDirection,
       _controller = controller ?? Scroll3dController(),
       _ownsController = controller == null,
       _depthAxisAlignment = depthAxisAlignment,
       _cacheExtent = cacheExtent,
       _builder = itemBuilder,
       assert(itemCount >= 0),
       assert(cacheExtent >= 0.0) {
    declaredItemCount = itemCount;
    _controller.addListener(_handleScrollChanged);
  }

  Grid3dDelegate _gridDelegate;

  /// Decides the cell grid from the room available.
  Grid3dDelegate get gridDelegate => _gridDelegate;

  set gridDelegate(Grid3dDelegate value) {
    if (identical(_gridDelegate, value)) return;
    final old = _gridDelegate;
    _gridDelegate = value;
    if (value.runtimeType != old.runtimeType || value.shouldRelayout(old)) {
      markNeedsLayout();
    }
  }

  Axis3d _axis;

  /// The axis the grid scrolls along.
  Axis3d get scrollDirection => _axis;

  @override
  Axis3d get scrollAxis => _axis;

  set scrollDirection(Axis3d value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  Scroll3dController _controller;
  bool _ownsController;

  /// The scroll position, and the metrics this grid measured.
  @override
  Scroll3dController get controller => _controller;

  /// Sets the position, or hands ownership back with null.
  ///
  /// Null means "make one of your own", the same thing it means in the
  /// constructor, so a declarative caller that stops passing a controller gets
  /// a fresh one rather than keeping the last one it happened to pass. A
  /// controller supplied from outside belongs to whoever supplied it and is
  /// never disposed here; one this view made is.
  set controller(Scroll3dController? value) {
    if (identical(_controller, value)) return;
    _controller.removeListener(_handleScrollChanged);
    if (_ownsController) _controller.dispose();
    _ownsController = value == null;
    _controller = (value ?? Scroll3dController())
      ..addListener(_handleScrollChanged);
    markNeedsLayout();
  }

  CrossAxisAlignment3d _depthAxisAlignment;

  /// How a cell's child sits on the depth axis.
  CrossAxisAlignment3d get depthAxisAlignment => _depthAxisAlignment;

  set depthAxisAlignment(CrossAxisAlignment3d value) {
    if (_depthAxisAlignment == value) return;
    _depthAxisAlignment = value;
    markNeedsLayout();
  }

  double _cacheExtent;

  /// How far beyond each end of the window cells are kept alive.
  double get cacheExtent => _cacheExtent;

  set cacheExtent(double value) {
    if (_cacheExtent == value) return;
    assert(value >= 0.0);
    _cacheExtent = value;
    markNeedsLayout();
  }

  final Layout3dItemBuilder? _builder;

  @override
  Layout3dItemBuilder? get itemBuilder => _builder;

  @override
  String get itemNoun => 'cells';

  /// The grid the delegate last produced, for callers that want to know where
  /// a cell landed. Null until the first layout.
  Grid3dLayout? _layout;

  /// The cell grid in force after the most recent layout.
  Grid3dLayout? get gridLayout => _layout;

  /// A scroll position that moved needs a new layout, unless it moved
  /// *during* one — and [markNeedsLayout] already ignores that case.
  void _handleScrollChanged() => markNeedsLayout();

  /// Opaque to hits across the whole window, the gaps between cells
  /// included, so a drag that starts between two cells still scrolls.
  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  void performLayout() => runLayoutPass(_performGridLayout);

  void _performGridLayout() {
    final axis = _axis;
    final (crossAxis, depthAxis) = axis.others;
    final boundedMain = constraints.hasBoundedAlong(axis);
    final crossExtent = constraints.hasBoundedAlong(crossAxis)
        ? constraints.maxAlong(crossAxis)
        : 0.0;
    assert(
      constraints.hasBoundedAlong(crossAxis),
      'GridView3d needs a bounded extent on $crossAxis to divide into cells, '
      'but was given unbounded constraints there. Give the grid a size, or '
      'put it in a box that has one.',
    );

    final grid = _layout = _gridDelegate.layoutFor(crossExtent);
    final count = itemCount;
    final contentExtent = grid.mainExtentFor(count);
    final mainSize = boundedMain ? constraints.maxAlong(axis) : contentExtent;

    // The window, in content coordinates. Read before the metrics are
    // reported so the range and the placement agree on one offset.
    final offset = _controller.offset.clamp(
      0.0,
      math.max(0.0, contentExtent - mainSize),
    );
    final windowStart = offset - _cacheExtent;
    final windowEnd = offset + mainSize + _cacheExtent;
    final firstIndex = math.max(0, grid.firstIndexAt(windowStart));
    final lastIndex = math.min(count - 1, grid.lastIndexAt(windowEnd, count));

    final depthLimit = constraints.maxAlong(depthAxis);
    final stretchDepth =
        _depthAxisAlignment == CrossAxisAlignment3d.stretch &&
        depthLimit.isFinite;
    final childConstraints = Constraints3d.tight(Size3d.zero)
        .withAxis(
          axis,
          min: grid.cellMainAxisExtent,
          max: grid.cellMainAxisExtent,
        )
        .withAxis(
          crossAxis,
          min: grid.cellCrossAxisExtent,
          max: grid.cellCrossAxisExtent,
        )
        .withAxis(
          depthAxis,
          min: stretchDepth ? depthLimit : 0.0,
          max: depthLimit,
        );

    var depthExtent = 0.0;
    if (_builder == null) {
      for (final child in children) {
        child.layout(childConstraints, parentUsesSize: true);
        depthExtent = math.max(depthExtent, child.size.alongAxis(depthAxis));
      }
    } else {
      for (var index = firstIndex; index <= lastIndex; index++) {
        final child = obtainChild(index, childConstraints);
        depthExtent = math.max(depthExtent, child.size.alongAxis(depthAxis));
      }
      releaseOutside(firstIndex, lastIndex);
    }

    size = constraints.constrain(
      Size3d.zero
          .withAxis(axis, mainSize)
          .withAxis(crossAxis, crossExtent)
          .withAxis(depthAxis, depthLimit.isFinite ? depthLimit : depthExtent),
    );

    final actualMain = size.alongAxis(axis);
    _controller.applyViewportMetrics(
      maxScrollExtent: math.max(0.0, contentExtent - actualMain),
      viewportExtent: actualMain,
      contentExtent: contentExtent,
    );
    final scrollOffset = _controller.offset;
    final actualDepth = size.alongAxis(depthAxis);

    for (final (index, child) in positionedChildren()) {
      final start = grid.mainAxisOffsetOf(index);
      child.place(
        Offset3d.zero
            .withAxis(axis, start - scrollOffset)
            .withAxis(crossAxis, grid.crossAxisOffsetOf(index))
            .withAxis(
              depthAxis,
              scrollCrossOffset(
                _depthAxisAlignment,
                actualDepth,
                child.size.alongAxis(depthAxis),
              ),
            ),
      );
      child.node.visible =
          start + grid.cellMainAxisExtent > scrollOffset - _cacheExtent &&
          start < scrollOffset + actualMain + _cacheExtent;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScrollChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}
