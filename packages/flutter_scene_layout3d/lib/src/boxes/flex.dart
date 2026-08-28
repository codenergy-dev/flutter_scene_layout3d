import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        DiagnosticsProperty,
        DoubleProperty,
        EnumProperty,
        IntProperty;

import '../debug/overflow.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// How a [Flex3d] distributes leftover room along its main axis, the 3D
/// analogue of [MainAxisAlignment].
enum MainAxisAlignment3d {
  /// Children packed at the low end (left, top, or front).
  start,

  /// Children packed at the high end (right, bottom, or back).
  end,

  /// Children packed toward the middle.
  center,

  /// Free space split evenly between children.
  spaceBetween,

  /// Free space split evenly between children, half as much at the ends.
  spaceAround,

  /// Free space split evenly between children and at the ends.
  spaceEvenly,
}

/// How a [Flex3d] positions children on a cross axis, the 3D analogue of
/// [CrossAxisAlignment].
enum CrossAxisAlignment3d {
  /// Children at the low end of the cross axis.
  start,

  /// Children at the high end of the cross axis.
  end,

  /// Children centered on the cross axis.
  center,

  /// Children forced to fill the cross axis.
  ///
  /// Requires the flex to be bounded on that axis.
  stretch,

  /// Children lined up on the baselines they declare along that cross axis.
  ///
  /// Content of different extents sits on one line rather than sharing an
  /// edge or a centre. A child with no baseline of its own falls back to its
  /// far edge, exactly as in Flutter, which is what lets a line mix the two.
  baseline,
}

/// Whether a [Flex3d] should be as big as possible along its main axis or as
/// small as its children allow, the 3D analogue of [MainAxisSize].
enum MainAxisSize3d {
  /// Shrink-wrap the children.
  min,

  /// Fill the room the parent offered, when it is bounded.
  max,
}

/// How a [Flexible3d] child fills the space allotted to it, the 3D analogue
/// of [FlexFit].
enum FlexFit3d {
  /// The child must exactly fill its share.
  tight,

  /// The child may be smaller than its share.
  loose,
}

/// Marks a child of a [Flex3d] as taking a share of the leftover main-axis
/// space, the 3D analogue of [Flexible].
///
/// Unlike Flutter's, this is a real layout rather than a parent-data widget:
/// it sits in the tree, sizes itself to its child, and the enclosing [Flex3d]
/// reads [flex] and [fit] off it.
class Flexible3d extends ProxyLayout3d {
  /// Creates a flexible child.
  Flexible3d({
    int flex = 1,
    FlexFit3d fit = FlexFit3d.loose,
    super.child,
    super.name,
  }) : _flex = flex,
       _fit = fit,
       assert(flex >= 0, 'Flexible3d.flex must not be negative.');

  int _flex;

  /// This child's share of the leftover space, relative to its siblings.
  int get flex => _flex;

  set flex(int value) {
    if (_flex == value) return;
    assert(value >= 0);
    _flex = value;
    markParentNeedsLayout();
  }

  FlexFit3d _fit;

  /// Whether the child must fill its share.
  FlexFit3d get fit => _fit;

  set fit(FlexFit3d value) {
    if (_fit == value) return;
    _fit = value;
    markParentNeedsLayout();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IntProperty('flex', flex));
    properties.add(EnumProperty<FlexFit3d>('fit', fit));
  }
}

/// A [Flexible3d] whose child must fill its share, the 3D analogue of
/// [Expanded].
class Expanded3d extends Flexible3d {
  /// Creates an expanding child.
  Expanded3d({super.flex, super.child, super.name})
    : super(fit: FlexFit3d.tight);
}

/// Empty space that takes a share of a [Flex3d]'s main axis, the 3D analogue
/// of [Spacer].
class Spacer3d extends Flexible3d {
  /// Creates a flexible gap.
  Spacer3d({super.flex, super.name})
    : super(fit: FlexFit3d.tight, child: _EmptyBox3d());
}

class _EmptyBox3d extends Layout3d {
  @override
  bool get sizedByParent => true;

  @override
  void performResize() {
    size = constraints.smallest;
  }

  @override
  void performLayout() {}
}

/// Lays children out in a line along one axis, the 3D analogue of [Flex].
///
/// The protocol is Flutter's: inflexible children are laid out first with
/// unbounded room along the main axis, whatever is left over is divided among
/// the [Flexible3d] children by their flex factors, and then the whole line is
/// positioned by [mainAxisAlignment].
///
/// The 3D difference is that a line has *two* cross axes. Which enum applies
/// to which axis follows canonical `x`, `y`, `z` order with the main axis
/// removed: for a [Row3d] (main `x`) [crossAxisAlignment] is vertical and
/// [depthAxisAlignment] is depth; for a [Column3d] (main `y`)
/// [crossAxisAlignment] is horizontal and [depthAxisAlignment] is depth; for
/// a [Depth3d] (main `z`) they are horizontal and vertical.
class Flex3d extends MultiChildLayout3d<ParentData3d>
    with Layout3dOverflowReportingMixin {
  /// Creates a flex line along [direction].
  Flex3d({
    required Axis3d direction,
    MainAxisAlignment3d mainAxisAlignment = MainAxisAlignment3d.start,
    MainAxisSize3d mainAxisSize = MainAxisSize3d.max,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.center,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double spacing = 0.0,
    super.children,
    super.name,
  }) : _direction = direction,
       _mainAxisAlignment = mainAxisAlignment,
       _mainAxisSize = mainAxisSize,
       _crossAxisAlignment = crossAxisAlignment,
       _depthAxisAlignment = depthAxisAlignment,
       _spacing = spacing,
       assert(spacing >= 0, 'Flex3d.spacing must not be negative.');

  Axis3d _direction;

  /// The axis children are laid out along.
  Axis3d get direction => _direction;

  set direction(Axis3d value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  MainAxisAlignment3d _mainAxisAlignment;

  /// How leftover main-axis space is distributed.
  MainAxisAlignment3d get mainAxisAlignment => _mainAxisAlignment;

  set mainAxisAlignment(MainAxisAlignment3d value) {
    if (_mainAxisAlignment == value) return;
    _mainAxisAlignment = value;
    markNeedsLayout();
  }

  MainAxisSize3d _mainAxisSize;

  /// Whether to fill or shrink-wrap the main axis.
  MainAxisSize3d get mainAxisSize => _mainAxisSize;

  set mainAxisSize(MainAxisSize3d value) {
    if (_mainAxisSize == value) return;
    _mainAxisSize = value;
    markNeedsLayout();
  }

  CrossAxisAlignment3d _crossAxisAlignment;

  /// How children are positioned on the first cross axis.
  CrossAxisAlignment3d get crossAxisAlignment => _crossAxisAlignment;

  set crossAxisAlignment(CrossAxisAlignment3d value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  CrossAxisAlignment3d _depthAxisAlignment;

  /// How children are positioned on the second cross axis.
  CrossAxisAlignment3d get depthAxisAlignment => _depthAxisAlignment;

  set depthAxisAlignment(CrossAxisAlignment3d value) {
    if (_depthAxisAlignment == value) return;
    _depthAxisAlignment = value;
    markNeedsLayout();
  }

  double _spacing;

  /// A fixed gap inserted between adjacent children.
  double get spacing => _spacing;

  set spacing(double value) {
    if (_spacing == value) return;
    assert(value >= 0);
    _spacing = value;
    markNeedsLayout();
  }

  /// The two axes that are not [direction], in canonical order.
  (Axis3d, Axis3d) get crossAxes => _direction.others;

  static int _flexOf(Layout3d child) => child is Flexible3d ? child.flex : 0;

  static FlexFit3d _fitOf(Layout3d child) =>
      child is Flexible3d ? child.fit : FlexFit3d.tight;

  CrossAxisAlignment3d _alignmentFor(Axis3d axis) {
    final (first, _) = crossAxes;
    return axis == first ? _crossAxisAlignment : _depthAxisAlignment;
  }

  Constraints3d _childConstraints(double minMain, double maxMain) {
    var result = const Constraints3d().withAxis(
      _direction,
      min: minMain,
      max: maxMain,
    );
    final (firstCross, secondCross) = crossAxes;
    for (final axis in <Axis3d>[firstCross, secondCross]) {
      final limit = constraints.maxAlong(axis);
      final stretch =
          _alignmentFor(axis) == CrossAxisAlignment3d.stretch && limit.isFinite;
      assert(
        _alignmentFor(axis) != CrossAxisAlignment3d.stretch || limit.isFinite,
        'Flex3d cannot stretch on $axis: it was given unbounded constraints '
        'on that axis. Give the flex a bounded size, or use '
        'CrossAxisAlignment3d.center.',
      );
      result = result.withAxis(axis, min: stretch ? limit : 0.0, max: limit);
    }
    return result;
  }

  /// A line's baseline along a cross axis is the highest of its children's,
  /// because they lie side by side and hang from it together; along the main
  /// axis it is the first child's, because there they are stacked and the
  /// first one leads.
  ///
  /// This is Flutter's rule, which distinguishes a `Row` from a `Column`, put
  /// in terms of the axis being asked about rather than the direction of the
  /// flex.
  @override
  double? computeDistanceToActualBaseline(Axis3d axis) => axis == _direction
      ? defaultComputeDistanceToFirstActualBaseline(axis)
      : defaultComputeDistanceToHighestActualBaseline(axis);

  double _childIntrinsic(
    Layout3d child,
    Axis3d axis,
    Size3d limits, {
    required bool min,
  }) => min
      ? child.getMinIntrinsicExtent(axis, limits)
      : child.getMaxIntrinsicExtent(axis, limits);

  /// The line's intrinsic extent, ported from Flutter's `RenderFlex`.
  ///
  /// Along the main axis the children add up, and a flexible child sets the
  /// pace for every other: the run has to be long enough that the largest
  /// "extent per flex unit" any child asks for is satisfied everywhere.
  ///
  /// Across it the children overlap instead of adding up, so the answer is
  /// the largest of theirs — but each child has to be asked with the
  /// main-axis room it would actually get, since what a child needs across
  /// the line usually depends on how much of the line it was given.
  double _flexIntrinsic(Axis3d axis, Size3d limits, {required bool min}) {
    final totalSpacing = _spacing * math.max(0, childCount - 1);
    if (axis == _direction) {
      var totalFlex = 0;
      var inflexibleSpace = 0.0;
      var maxFlexFraction = 0.0;
      for (final child in children) {
        final flex = _flexOf(child);
        totalFlex += flex;
        final extent = _childIntrinsic(child, axis, limits, min: min);
        if (flex > 0) {
          maxFlexFraction = math.max(maxFlexFraction, extent / flex);
        } else {
          inflexibleSpace += extent;
        }
      }
      return maxFlexFraction * totalFlex + inflexibleSpace + totalSpacing;
    }

    final available = limits.alongAxis(_direction);
    final mainLimits = limits.withAxis(axis, double.infinity);
    var totalFlex = 0;
    var inflexibleSpace = 0.0;
    var maxCross = 0.0;
    for (final child in children) {
      final flex = _flexOf(child);
      totalFlex += flex;
      if (flex > 0) continue;
      final mainExtent = child.getMaxIntrinsicExtent(_direction, mainLimits);
      inflexibleSpace += mainExtent;
      maxCross = math.max(
        maxCross,
        _childIntrinsic(
          child,
          axis,
          limits.withAxis(_direction, mainExtent),
          min: min,
        ),
      );
    }
    if (totalFlex > 0) {
      final spacePerFlex = math.max(
        0.0,
        (available - inflexibleSpace - totalSpacing) / totalFlex,
      );
      for (final child in children) {
        final flex = _flexOf(child);
        if (flex == 0) continue;
        maxCross = math.max(
          maxCross,
          _childIntrinsic(
            child,
            axis,
            limits.withAxis(_direction, spacePerFlex * flex),
            min: min,
          ),
        );
      }
    }
    return maxCross;
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _flexIntrinsic(axis, limits, min: true);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _flexIntrinsic(axis, limits, min: false);

  @override
  void performLayout() {
    final constraints = this.constraints;
    final mainAxis = _direction;
    final (firstCross, secondCross) = crossAxes;
    final maxMainSize = constraints.maxAlong(mainAxis);
    final canFlex = maxMainSize.isFinite;
    final totalSpacing = _spacing * math.max(0, childCount - 1);

    var allocatedSize = 0.0;
    var firstCrossSize = 0.0;
    var secondCrossSize = 0.0;
    var totalFlex = 0;

    // Baseline alignment needs two numbers per cross axis it applies to: how
    // far the deepest baseline sits from the origin corner, and how much room
    // the children need past their own. The line is as thick as those two
    // added together, which is usually more than its thickest child, because
    // lining content up on a line inside it pushes the extremes apart.
    final aboveBaseline = <Axis3d, double>{};
    final belowBaseline = <Axis3d, double>{};

    void measureCross(Layout3d child) {
      final childSize = child.size;
      for (final axis in <Axis3d>[firstCross, secondCross]) {
        var extent = childSize.alongAxis(axis);
        if (_alignmentFor(axis) == CrossAxisAlignment3d.baseline) {
          final distance = child.getDistanceToBaseline(axis, onlyReal: true);
          if (distance != null) {
            final above = math.max(aboveBaseline[axis] ?? 0.0, distance);
            final below = math.max(
              belowBaseline[axis] ?? 0.0,
              extent - distance,
            );
            aboveBaseline[axis] = above;
            belowBaseline[axis] = below;
            extent = math.max(extent, above + below);
          }
        }
        if (axis == firstCross) {
          firstCrossSize = math.max(firstCrossSize, extent);
        } else {
          secondCrossSize = math.max(secondCrossSize, extent);
        }
      }
    }

    // Pass one: the children that do not flex, with all the main-axis room
    // they ask for.
    for (final child in children) {
      final flex = _flexOf(child);
      if (flex > 0) {
        totalFlex += flex;
        continue;
      }
      child.layout(
        _childConstraints(0.0, double.infinity),
        parentUsesSize: true,
      );
      allocatedSize += child.size.alongAxis(mainAxis);
      measureCross(child);
    }

    // Pass two: divide what is left among the flexible children.
    if (totalFlex > 0) {
      assert(
        canFlex,
        'Flex3d has flexible children but was given unbounded constraints '
        'along $mainAxis, so there is no free space to divide. Give the flex '
        'a bounded extent on that axis, or size the children directly.',
      );
      final freeSpace = math.max(
        0.0,
        (canFlex ? maxMainSize : 0.0) - allocatedSize - totalSpacing,
      );
      final spacePerFlex = freeSpace / totalFlex;
      var allocatedFlexSpace = 0.0;
      var remainingFlex = totalFlex;
      for (final child in children) {
        final flex = _flexOf(child);
        if (flex == 0) continue;
        remainingFlex -= flex;
        // The last flexible child mops up the rounding error.
        final maxChildExtent = remainingFlex == 0
            ? math.max(0.0, freeSpace - allocatedFlexSpace)
            : spacePerFlex * flex;
        final minChildExtent = _fitOf(child) == FlexFit3d.tight
            ? maxChildExtent
            : 0.0;
        child.layout(
          _childConstraints(minChildExtent, maxChildExtent),
          parentUsesSize: true,
        );
        allocatedSize += child.size.alongAxis(mainAxis);
        allocatedFlexSpace += maxChildExtent;
        measureCross(child);
      }
    }

    // The line's own size.
    final idealMainSize = _mainAxisSize == MainAxisSize3d.max && canFlex
        ? maxMainSize
        : allocatedSize + totalSpacing;
    size = constraints.constrain(
      Size3d.zero
          .withAxis(mainAxis, idealMainSize)
          .withAxis(firstCross, firstCrossSize)
          .withAxis(secondCross, secondCrossSize),
    );

    final actualMainSize = size.alongAxis(mainAxis);
    final actualFirstCross = size.alongAxis(firstCross);
    final actualSecondCross = size.alongAxis(secondCross);
    final remainingSpace = math.max(
      0.0,
      actualMainSize - (allocatedSize + totalSpacing),
    );
    // What the children asked for against what the line got. Flutter reports
    // the same number as a stripe when it paints; there is nothing to paint
    // here, so the line says so out loud instead.
    debugReportOverflow(
      Size3d.zero
          .withAxis(mainAxis, allocatedSize + totalSpacing - actualMainSize)
          .withAxis(firstCross, firstCrossSize - actualFirstCross)
          .withAxis(secondCross, secondCrossSize - actualSecondCross),
      hint:
          'Either the children are too big for the room this $runtimeType '
          'was given, or one of them should be Flexible3d so it takes only '
          'what is left over.',
    );
    final gaps = math.max(0, childCount - 1);
    final (leadingSpace, betweenSpace) = switch (_mainAxisAlignment) {
      MainAxisAlignment3d.start => (0.0, 0.0),
      MainAxisAlignment3d.end => (remainingSpace, 0.0),
      MainAxisAlignment3d.center => (remainingSpace / 2.0, 0.0),
      MainAxisAlignment3d.spaceBetween => (
        0.0,
        gaps > 0 ? remainingSpace / gaps : 0.0,
      ),
      MainAxisAlignment3d.spaceAround => () {
        final between = childCount > 0 ? remainingSpace / childCount : 0.0;
        return (between / 2.0, between);
      }(),
      MainAxisAlignment3d.spaceEvenly => () {
        final between = remainingSpace / (childCount + 1);
        return (between, between);
      }(),
    };

    double crossOffsetFor(Layout3d child, Axis3d axis, double extent) {
      final alignment = _alignmentFor(axis);
      if (alignment == CrossAxisAlignment3d.baseline) {
        // Every child is pushed down by the difference between its own
        // baseline and the deepest one in the line, which is what puts them
        // all on the same line. A child that has no baseline of its own sits
        // at the start, as it does in Flutter.
        final deepest = aboveBaseline[axis];
        final distance = child.getDistanceToBaseline(axis, onlyReal: true);
        if (deepest == null || distance == null) return 0.0;
        return deepest - distance;
      }
      return _crossOffset(alignment, extent, child.size.alongAxis(axis));
    }

    var mainPosition = leadingSpace;
    for (final child in children) {
      final childSize = child.size;
      final firstCrossOffset = crossOffsetFor(
        child,
        firstCross,
        actualFirstCross,
      );
      final secondCrossOffset = crossOffsetFor(
        child,
        secondCross,
        actualSecondCross,
      );
      child.place(
        Offset3d.zero
            .withAxis(mainAxis, mainPosition)
            .withAxis(firstCross, firstCrossOffset)
            .withAxis(secondCross, secondCrossOffset),
      );
      mainPosition += childSize.alongAxis(mainAxis) + betweenSpace + _spacing;
    }
  }

  static double _crossOffset(
    CrossAxisAlignment3d alignment,
    double extent,
    double childExtent,
  ) => switch (alignment) {
    CrossAxisAlignment3d.start ||
    CrossAxisAlignment3d.stretch ||
    CrossAxisAlignment3d.baseline => 0.0,
    CrossAxisAlignment3d.end => extent - childExtent,
    CrossAxisAlignment3d.center => (extent - childExtent) / 2.0,
  };

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<Axis3d>('direction', direction));
    properties.add(
      EnumProperty<MainAxisAlignment3d>('mainAxisAlignment', mainAxisAlignment),
    );
    properties.add(EnumProperty<MainAxisSize3d>('mainAxisSize', mainAxisSize));
    properties.add(
      EnumProperty<CrossAxisAlignment3d>(
        'crossAxisAlignment',
        crossAxisAlignment,
      ),
    );
    properties.add(
      EnumProperty<CrossAxisAlignment3d>(
        'depthAxisAlignment',
        depthAxisAlignment,
        defaultValue: CrossAxisAlignment3d.center,
      ),
    );
    properties.add(DoubleProperty('spacing', spacing, defaultValue: 0.0));
    properties.add(
      DiagnosticsProperty<Size3d>(
        'overflow',
        debugOverflow,
        defaultValue: Size3d.zero,
      ),
    );
  }
}

/// A [Flex3d] running left to right, the 3D analogue of [Row].
class Row3d extends Flex3d {
  /// Creates a horizontal line of children.
  Row3d({
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.depthAxisAlignment,
    super.spacing,
    super.children,
    super.name,
  }) : super(direction: Axis3d.horizontal);
}

/// A [Flex3d] running top to bottom, the 3D analogue of [Column].
///
/// Top to bottom means toward `-y` in the scene under the default
/// [LayoutBasis3d.xy]: the first child is the highest one on the plane, the
/// way the first child of a Flutter `Column` is the topmost.
class Column3d extends Flex3d {
  /// Creates a vertical line of children.
  Column3d({
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.depthAxisAlignment,
    super.spacing,
    super.children,
    super.name,
  }) : super(direction: Axis3d.vertical);
}

/// A [Flex3d] running away from the viewer, the axis Flutter does not have.
///
/// The first child is the one closest to the viewer.
class Depth3d extends Flex3d {
  /// Creates a line of children receding from the viewer.
  Depth3d({
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.depthAxisAlignment,
    super.spacing,
    super.children,
    super.name,
  }) : super(direction: Axis3d.depth);
}
