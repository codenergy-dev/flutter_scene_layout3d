import 'dart:math' as math;

import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'flex.dart' show CrossAxisAlignment3d;

/// How wide one column of a [Table3d] is, the 3D analogue of
/// [TableColumnWidth].
///
/// A column width is a negotiation, not a number: the table asks each policy
/// what the column would like at minimum and at maximum, adds those up, and
/// then hands out whatever room is left over — or takes back whatever is
/// missing — according to [flex]. That is the whole reason a table is not
/// simply a `Column3d` of `Row3d`s: the columns of different rows have to
/// agree, and only something that sees the whole column can make them.
abstract class TableColumnWidth3d {
  /// Creates a column width policy.
  const TableColumnWidth3d();

  /// The narrowest this column can usefully be.
  double minIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth);

  /// The width this column would like.
  double maxIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth);

  /// This column's share of the room left over, or null if it takes none.
  double? flex(Iterable<Layout3d> cells) => null;
}

/// A column of a stated width, the 3D analogue of [FixedColumnWidth].
class FixedColumnWidth3d extends TableColumnWidth3d {
  /// Creates a column [width] wide.
  const FixedColumnWidth3d(this.width) : assert(width >= 0.0);

  /// The width, in layout units.
  final double width;

  @override
  double minIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth) =>
      width;

  @override
  double maxIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth) =>
      width;
}

/// A column sized to a fraction of the table's width, the 3D analogue of
/// [FractionColumnWidth].
///
/// A table in unbounded room has no width to take a fraction of, and answers
/// zero there rather than an infinity; give the table a width, or use
/// [IntrinsicColumnWidth3d].
class FractionColumnWidth3d extends TableColumnWidth3d {
  /// Creates a column taking [value] of the table's width.
  const FractionColumnWidth3d(this.value) : assert(value >= 0.0);

  /// The fraction taken, where 1.0 is the whole table.
  final double value;

  double _width(double containerWidth) =>
      containerWidth.isFinite ? containerWidth * value : 0.0;

  @override
  double minIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth) =>
      _width(containerWidth);

  @override
  double maxIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth) =>
      _width(containerWidth);
}

/// A column taking a share of whatever room is left over, the 3D analogue of
/// [FlexColumnWidth].
///
/// The default, and the one that behaves like a `Row3d` of [Expanded3d]
/// cells. With nothing to share out — an unbounded table — a flex column
/// falls back to what its cells want, which is what keeps a table usable on a
/// surface that was never given a size.
class FlexColumnWidth3d extends TableColumnWidth3d {
  /// Creates a column taking [value] shares of the room left over.
  const FlexColumnWidth3d([this.value = 1.0]) : assert(value > 0.0);

  /// This column's share.
  final double value;

  @override
  double minIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth) =>
      0.0;

  @override
  double maxIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth) {
    if (containerWidth.isFinite) return 0.0;
    // Nothing to be a share of. Fall back to what the cells ask for, so an
    // unbounded table is laid out rather than collapsed to nothing.
    var width = 0.0;
    for (final cell in cells) {
      width = math.max(
        width,
        cell.getMaxIntrinsicExtent(Axis3d.horizontal, Size3d.infinite),
      );
    }
    return width;
  }

  @override
  double? flex(Iterable<Layout3d> cells) => value;
}

/// A column as wide as its widest cell wants to be, the 3D analogue of
/// [IntrinsicColumnWidth].
///
/// It asks every cell in the column, which means walking every one of their
/// subtrees, so it is the expensive policy — the same warning Flutter gives.
/// It is also the only one that makes a column fit its content exactly.
class IntrinsicColumnWidth3d extends TableColumnWidth3d {
  /// Creates a column sized to its content, optionally taking a share of the
  /// room left over as well.
  const IntrinsicColumnWidth3d({this.flexFactor});

  /// A share of the leftover room on top of the intrinsic width, or null.
  final double? flexFactor;

  @override
  double minIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth) {
    var width = 0.0;
    for (final cell in cells) {
      width = math.max(
        width,
        cell.getMinIntrinsicExtent(Axis3d.horizontal, Size3d.infinite),
      );
    }
    return width;
  }

  @override
  double maxIntrinsicWidth(Iterable<Layout3d> cells, double containerWidth) {
    var width = 0.0;
    for (final cell in cells) {
      width = math.max(
        width,
        cell.getMaxIntrinsicExtent(Axis3d.horizontal, Size3d.infinite),
      );
    }
    return width;
  }

  @override
  double? flex(Iterable<Layout3d> cells) => flexFactor;
}

/// Where a cell sits in the row it shares, the 3D analogue of
/// [TableCellVerticalAlignment].
enum TableCellAlignment3d {
  /// The cell hangs from the top of the row.
  top,

  /// The cell is centred in the row.
  middle,

  /// The cell sits on the bottom of the row.
  bottom,

  /// The cell is stretched to the height of the row.
  fill,

  /// The cells of a row sit on a shared baseline.
  ///
  /// What a row of text and controls wants: the label and the number line up
  /// on the line the glyphs sit on rather than on the box edges. A cell with
  /// no baseline of its own falls back to [top].
  baseline,
}

/// A grid of cells whose columns are negotiated across every row, the 3D
/// analogue of [Table].
///
/// ## Why it is a plane
///
/// A table here arranges its cells on the surface plane — rows down, columns
/// across — and treats depth as an alignment axis, the choice [Wrap3d]
/// already made and for the same reason. A third axis of *cells* would be a
/// different structure with a different name (a volume, indexed three ways),
/// and nothing a component catalogue asks for wants one: a data table, a
/// keypad, a calendar and a settings grid are all flat things standing in
/// space. So the depth of a table is the depth of its thickest cell, every
/// cell is placed in it by [depthAxisAlignment], and no cell is ever behind
/// another.
///
/// ## The cells
///
/// Children are given in row-major order, [columnCount] to a row, the way
/// `RenderTable` holds them. A last row with fewer cells than the rest is
/// allowed; the missing cells are simply absent, and the columns they would
/// have been in are negotiated from the cells that are there.
///
/// ```dart
/// Table3d(
///   columnCount: 3,
///   columnWidths: const {0: IntrinsicColumnWidth3d()},
///   defaultVerticalAlignment: TableCellAlignment3d.baseline,
///   children: [nameLabel, quantityLabel, priceLabel, ...cells],
/// )
/// ```
///
/// ## Intrinsics
///
/// Implemented, and cheaply on the axis that matters: the width of a table is
/// the sum of its column widths, which is what the column policies already
/// compute. The height needs the columns resolved first, so an intrinsic
/// height query resolves them against the limit it was given and then asks
/// each row's cells — the same work a layout does, minus the placing.
class Table3d extends MultiChildLayout3d<ParentData3d> {
  /// Creates a table of [columnCount] columns.
  Table3d({
    required int columnCount,
    Map<int, TableColumnWidth3d> columnWidths = const {},
    TableColumnWidth3d defaultColumnWidth = const FlexColumnWidth3d(),
    TableCellAlignment3d defaultVerticalAlignment = TableCellAlignment3d.top,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double columnSpacing = 0.0,
    double rowSpacing = 0.0,
    super.children,
    super.name,
  }) : _columnCount = columnCount,
       _columnWidths = Map<int, TableColumnWidth3d>.unmodifiable(columnWidths),
       _defaultColumnWidth = defaultColumnWidth,
       _defaultVerticalAlignment = defaultVerticalAlignment,
       _depthAxisAlignment = depthAxisAlignment,
       _columnSpacing = columnSpacing,
       _rowSpacing = rowSpacing,
       assert(columnCount > 0, 'A Table3d needs at least one column.'),
       assert(columnSpacing >= 0.0),
       assert(rowSpacing >= 0.0);

  int _columnCount;

  /// How many cells make a row.
  int get columnCount => _columnCount;

  set columnCount(int value) {
    if (_columnCount == value) return;
    assert(value > 0);
    _columnCount = value;
    markNeedsLayout();
  }

  Map<int, TableColumnWidth3d> _columnWidths;

  /// The width policy of individual columns, by index.
  ///
  /// Columns not named here use [defaultColumnWidth].
  Map<int, TableColumnWidth3d> get columnWidths => _columnWidths;

  set columnWidths(Map<int, TableColumnWidth3d> value) {
    if (_mapEquals(_columnWidths, value)) return;
    _columnWidths = Map<int, TableColumnWidth3d>.unmodifiable(value);
    markNeedsLayout();
  }

  static bool _mapEquals(
    Map<int, TableColumnWidth3d> a,
    Map<int, TableColumnWidth3d> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  TableColumnWidth3d _defaultColumnWidth;

  /// The width policy of every column [columnWidths] does not name.
  TableColumnWidth3d get defaultColumnWidth => _defaultColumnWidth;

  set defaultColumnWidth(TableColumnWidth3d value) {
    if (_defaultColumnWidth == value) return;
    _defaultColumnWidth = value;
    markNeedsLayout();
  }

  TableCellAlignment3d _defaultVerticalAlignment;

  /// Where a cell sits in its row.
  TableCellAlignment3d get defaultVerticalAlignment =>
      _defaultVerticalAlignment;

  set defaultVerticalAlignment(TableCellAlignment3d value) {
    if (_defaultVerticalAlignment == value) return;
    _defaultVerticalAlignment = value;
    markNeedsLayout();
  }

  CrossAxisAlignment3d _depthAxisAlignment;

  /// Where a cell sits in the table's depth.
  ///
  /// [CrossAxisAlignment3d.stretch] gives every cell the table's whole depth;
  /// [CrossAxisAlignment3d.baseline] has no meaning across depth and behaves
  /// as `start`, the same fallback the scrolling views make.
  CrossAxisAlignment3d get depthAxisAlignment => _depthAxisAlignment;

  set depthAxisAlignment(CrossAxisAlignment3d value) {
    if (_depthAxisAlignment == value) return;
    _depthAxisAlignment = value;
    markNeedsLayout();
  }

  double _columnSpacing;

  /// The gap between adjacent columns.
  double get columnSpacing => _columnSpacing;

  set columnSpacing(double value) {
    if (_columnSpacing == value) return;
    assert(value >= 0.0);
    _columnSpacing = value;
    markNeedsLayout();
  }

  double _rowSpacing;

  /// The gap between adjacent rows.
  double get rowSpacing => _rowSpacing;

  set rowSpacing(double value) {
    if (_rowSpacing == value) return;
    assert(value >= 0.0);
    _rowSpacing = value;
    markNeedsLayout();
  }

  /// How many rows the children make, the last one possibly short.
  int get rowCount => (childCount + _columnCount - 1) ~/ _columnCount;

  /// The cell at [row], [column], or null when the last row stops short.
  Layout3d? cellAt(int row, int column) {
    final index = row * _columnCount + column;
    return index < childCount ? childAt(index) : null;
  }

  Iterable<Layout3d> _column(int column) sync* {
    for (var row = 0; row < rowCount; row++) {
      final cell = cellAt(row, column);
      if (cell != null) yield cell;
    }
  }

  TableColumnWidth3d _policyFor(int column) =>
      _columnWidths[column] ?? _defaultColumnWidth;

  /// The width of every column, negotiated against [availableWidth].
  ///
  /// Every policy is asked what it wants and what it can live with. If the
  /// wants fit, the room left over goes to the flexible columns; if they do
  /// not, the deficit is taken back from the columns with slack between their
  /// maximum and their minimum, in proportion to how much slack each has.
  /// Nothing is ever taken below its minimum, which is why a table can
  /// overflow rather than crushing a column to nothing.
  List<double> resolveColumnWidths(double availableWidth) {
    final widths = List<double>.filled(_columnCount, 0.0);
    final minimums = List<double>.filled(_columnCount, 0.0);
    final flexes = List<double?>.filled(_columnCount, null);
    var totalFlex = 0.0;
    var totalWidth = 0.0;
    var totalMinWidth = 0.0;

    for (var column = 0; column < _columnCount; column++) {
      final policy = _policyFor(column);
      final cells = _column(column).toList(growable: false);
      final maxWidth = policy.maxIntrinsicWidth(cells, availableWidth);
      final minWidth = math.min(
        policy.minIntrinsicWidth(cells, availableWidth),
        maxWidth,
      );
      widths[column] = maxWidth;
      minimums[column] = minWidth;
      totalWidth += maxWidth;
      totalMinWidth += minWidth;
      final flex = policy.flex(cells);
      if (flex != null && flex > 0.0) {
        flexes[column] = flex;
        totalFlex += flex;
      }
    }

    final spacing = _columnSpacing * (_columnCount - 1);
    if (!availableWidth.isFinite) return widths;
    final room = math.max(0.0, availableWidth - spacing);

    if (totalWidth < room && totalFlex > 0.0) {
      final remaining = room - totalWidth;
      for (var column = 0; column < _columnCount; column++) {
        final flex = flexes[column];
        if (flex == null) continue;
        widths[column] += remaining * flex / totalFlex;
      }
      return widths;
    }

    if (totalWidth > room) {
      // Take the deficit out of the slack, proportionally, and stop at the
      // minimums. A table whose minimums do not fit overflows instead.
      final deficit = totalWidth - room;
      final slack = totalWidth - totalMinWidth;
      if (slack <= 0.0) return widths;
      final taken = math.min(deficit, slack);
      for (var column = 0; column < _columnCount; column++) {
        final columnSlack = widths[column] - minimums[column];
        if (columnSlack <= 0.0) continue;
        widths[column] -= taken * columnSlack / slack;
      }
    }
    return widths;
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _intrinsic(axis, limits, min: true);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _intrinsic(axis, limits, min: false);

  double _intrinsic(Axis3d axis, Size3d limits, {required bool min}) {
    if (childCount == 0) return 0.0;
    switch (axis) {
      case Axis3d.horizontal:
        var total = _columnSpacing * (_columnCount - 1);
        for (var column = 0; column < _columnCount; column++) {
          final policy = _policyFor(column);
          final cells = _column(column).toList(growable: false);
          total += min
              ? policy.minIntrinsicWidth(cells, limits.width)
              : policy.maxIntrinsicWidth(cells, limits.width);
        }
        return total;
      case Axis3d.vertical:
        final widths = resolveColumnWidths(limits.width);
        var total = _rowSpacing * (rowCount - 1);
        for (var row = 0; row < rowCount; row++) {
          var rowHeight = 0.0;
          for (var column = 0; column < _columnCount; column++) {
            final cell = cellAt(row, column);
            if (cell == null) continue;
            final cellLimits = limits.withAxis(
              Axis3d.horizontal,
              widths[column],
            );
            rowHeight = math.max(
              rowHeight,
              min
                  ? cell.getMinIntrinsicExtent(Axis3d.vertical, cellLimits)
                  : cell.getMaxIntrinsicExtent(Axis3d.vertical, cellLimits),
            );
          }
          total += rowHeight;
        }
        return math.max(0.0, total);
      case Axis3d.depth:
        var depth = 0.0;
        for (final cell in heldChildren) {
          depth = math.max(
            depth,
            min
                ? cell.getMinIntrinsicExtent(Axis3d.depth, limits)
                : cell.getMaxIntrinsicExtent(Axis3d.depth, limits),
          );
        }
        return depth;
    }
  }

  /// The first row's shared baseline, which is the table's own.
  @override
  double? computeDistanceToActualBaseline(Axis3d axis) =>
      defaultComputeDistanceToFirstActualBaseline(axis);

  @override
  void performLayout() {
    final constraints = this.constraints;
    if (childCount == 0) {
      size = constraints.smallest;
      return;
    }

    final widths = resolveColumnWidths(constraints.maxWidth);
    final rows = rowCount;
    final maxDepth = constraints.maxDepth;
    final stretchDepth = _depthAxisAlignment == CrossAxisAlignment3d.stretch;
    assert(
      !stretchDepth || constraints.hasBoundedDepth,
      'Table3d.depthAxisAlignment is stretch, which fills the table\'s depth, '
      'and the table was given no depth to fill. Give it one with a '
      'SizedBox3d, or align the cells in depth instead.',
    );

    final rowHeights = List<double>.filled(rows, 0.0);
    final rowBaselines = List<double?>.filled(rows, null);
    var depthExtent = 0.0;

    // First pass: every cell at its natural height, which is what decides how
    // tall its row is.
    for (var row = 0; row < rows; row++) {
      var aboveBaseline = 0.0;
      var belowBaseline = 0.0;
      var height = 0.0;
      for (var column = 0; column < _columnCount; column++) {
        final cell = cellAt(row, column);
        if (cell == null) continue;
        cell.layout(
          Constraints3d(
            minWidth: widths[column],
            maxWidth: widths[column],
            minDepth: stretchDepth && maxDepth.isFinite ? maxDepth : 0.0,
            maxDepth: maxDepth,
          ),
          parentUsesSize: true,
        );
        final cellSize = cell.size;
        depthExtent = math.max(depthExtent, cellSize.depth);
        if (_defaultVerticalAlignment == TableCellAlignment3d.baseline) {
          final baseline = cell.getDistanceToBaseline(
            Axis3d.vertical,
            onlyReal: true,
          );
          if (baseline != null) {
            aboveBaseline = math.max(aboveBaseline, baseline);
            belowBaseline = math.max(belowBaseline, cellSize.height - baseline);
            continue;
          }
        }
        height = math.max(height, cellSize.height);
      }
      // A row of baseline-aligned cells is as tall as the tallest ascent plus
      // the deepest descent, which is more than the tallest cell whenever the
      // baselines do not agree.
      rowHeights[row] = math.max(height, aboveBaseline + belowBaseline);
      rowBaselines[row] = aboveBaseline > 0.0 ? aboveBaseline : null;
    }

    final contentWidth =
        widths.fold(0.0, (a, b) => a + b) + _columnSpacing * (_columnCount - 1);
    final contentHeight =
        rowHeights.fold(0.0, (a, b) => a + b) + _rowSpacing * (rows - 1);
    size = constraints.constrain(
      Size3d(contentWidth, contentHeight, depthExtent),
    );
    final tableDepth = size.depth;

    var y = 0.0;
    for (var row = 0; row < rows; row++) {
      var x = 0.0;
      for (var column = 0; column < _columnCount; column++) {
        final cell = cellAt(row, column);
        if (cell == null) {
          x += widths[column] + _columnSpacing;
          continue;
        }
        // Second pass, for the cells whose height depends on the row's: only
        // these are laid out twice, which is what keeps a fill cell from
        // costing every other cell a second measurement.
        if (_defaultVerticalAlignment == TableCellAlignment3d.fill &&
            cell.size.height != rowHeights[row]) {
          cell.layout(
            Constraints3d(
              minWidth: widths[column],
              maxWidth: widths[column],
              minHeight: rowHeights[row],
              maxHeight: rowHeights[row],
              minDepth: stretchDepth && maxDepth.isFinite ? maxDepth : 0.0,
              maxDepth: maxDepth,
            ),
            parentUsesSize: true,
          );
        }
        cell.place(
          Offset3d(
            x,
            y + _verticalOffset(cell, rowHeights[row], rowBaselines[row]),
            _depthOffset(cell, tableDepth),
          ),
        );
        x += widths[column] + _columnSpacing;
      }
      y += rowHeights[row] + _rowSpacing;
    }
  }

  double _verticalOffset(Layout3d cell, double rowHeight, double? rowBaseline) {
    final height = cell.size.height;
    switch (_defaultVerticalAlignment) {
      case TableCellAlignment3d.top:
      case TableCellAlignment3d.fill:
        return 0.0;
      case TableCellAlignment3d.middle:
        return (rowHeight - height) / 2.0;
      case TableCellAlignment3d.bottom:
        return rowHeight - height;
      case TableCellAlignment3d.baseline:
        final baseline = cell.getDistanceToBaseline(
          Axis3d.vertical,
          onlyReal: true,
        );
        if (baseline == null || rowBaseline == null) return 0.0;
        return rowBaseline - baseline;
    }
  }

  double _depthOffset(Layout3d cell, double tableDepth) {
    final depth = cell.size.depth;
    return switch (_depthAxisAlignment) {
      CrossAxisAlignment3d.start ||
      CrossAxisAlignment3d.stretch ||
      CrossAxisAlignment3d.baseline => 0.0,
      CrossAxisAlignment3d.end => tableDepth - depth,
      CrossAxisAlignment3d.center => (tableDepth - depth) / 2.0,
    };
  }
}
