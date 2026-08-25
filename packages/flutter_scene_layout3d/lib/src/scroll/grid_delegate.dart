import 'dart:math' as math;

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
