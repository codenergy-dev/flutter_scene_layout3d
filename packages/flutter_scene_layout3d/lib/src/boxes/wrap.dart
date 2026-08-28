import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DoubleProperty, EnumProperty;

import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// How a [Wrap3d] distributes leftover room, the 3D analogue of
/// [WrapAlignment].
///
/// Used twice over: along the main axis, to place the children inside a run,
/// and along the first cross axis, to place the runs inside the box.
enum WrapAlignment3d {
  /// Packed at the low end (left, top, or front).
  start,

  /// Packed at the high end (right, bottom, or back).
  end,

  /// Packed toward the middle.
  center,

  /// Free space split evenly between, none at the ends.
  spaceBetween,

  /// Free space split evenly between, half as much at the ends.
  spaceAround,

  /// Free space split evenly between and at the ends.
  spaceEvenly,
}

/// How a [Wrap3d] positions a child across its run, the 3D analogue of
/// [WrapCrossAlignment].
///
/// There is no `stretch` here, as in Flutter: a run is only as thick as its
/// tallest child, so stretching to it would be circular.
enum WrapCrossAlignment3d {
  /// At the low end of the run.
  start,

  /// At the high end of the run.
  end,

  /// Centred in the run.
  center,
}

/// One run of a [Wrap3d], measured during layout.
class _Run3d {
  _Run3d(this.start);

  final int start;
  int count = 0;
  double mainExtent = 0.0;
  double crossExtent = 0.0;
  double depthExtent = 0.0;

  int get end => start + count;
}

/// Lays children out in runs, starting a new one whenever the current run is
/// full, the 3D analogue of [Wrap].
///
/// A [Flex3d] given more children than fit overflows; a wrap breaks instead.
/// Children are placed one after another along [direction] until the next one
/// would not fit in the room available, and then a new run begins, offset
/// along the first cross axis. That is Flutter's algorithm exactly, and the
/// second cross axis (the depth axis of a `Row3d`-style wrap) is not a
/// wrapping axis but an alignment one: every child is placed in the depth the
/// thickest of them needs, according to [depthAxisAlignment].
///
/// Runs need a bound to break against. Given unbounded constraints along
/// [direction] every child lands in a single run, the same as Flutter.
class Wrap3d extends MultiChildLayout3d<ParentData3d> {
  /// Creates a wrapping box.
  Wrap3d({
    Axis3d direction = Axis3d.horizontal,
    WrapAlignment3d alignment = WrapAlignment3d.start,
    double spacing = 0.0,
    WrapAlignment3d runAlignment = WrapAlignment3d.start,
    double runSpacing = 0.0,
    WrapCrossAlignment3d crossAxisAlignment = WrapCrossAlignment3d.start,
    WrapCrossAlignment3d depthAxisAlignment = WrapCrossAlignment3d.center,
    super.children,
    super.name,
  }) : _direction = direction,
       _alignment = alignment,
       _spacing = spacing,
       _runAlignment = runAlignment,
       _runSpacing = runSpacing,
       _crossAxisAlignment = crossAxisAlignment,
       _depthAxisAlignment = depthAxisAlignment,
       assert(spacing >= 0.0),
       assert(runSpacing >= 0.0);

  Axis3d _direction;

  /// The axis a run advances along.
  Axis3d get direction => _direction;

  set direction(Axis3d value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  WrapAlignment3d _alignment;

  /// How the children of one run are distributed along it.
  WrapAlignment3d get alignment => _alignment;

  set alignment(WrapAlignment3d value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  double _spacing;

  /// The gap between adjacent children in a run.
  double get spacing => _spacing;

  set spacing(double value) {
    if (_spacing == value) return;
    assert(value >= 0.0);
    _spacing = value;
    markNeedsLayout();
  }

  WrapAlignment3d _runAlignment;

  /// How the runs are distributed across the first cross axis.
  WrapAlignment3d get runAlignment => _runAlignment;

  set runAlignment(WrapAlignment3d value) {
    if (_runAlignment == value) return;
    _runAlignment = value;
    markNeedsLayout();
  }

  double _runSpacing;

  /// The gap between adjacent runs.
  double get runSpacing => _runSpacing;

  set runSpacing(double value) {
    if (_runSpacing == value) return;
    assert(value >= 0.0);
    _runSpacing = value;
    markNeedsLayout();
  }

  WrapCrossAlignment3d _crossAxisAlignment;

  /// How a child sits across its own run.
  WrapCrossAlignment3d get crossAxisAlignment => _crossAxisAlignment;

  set crossAxisAlignment(WrapCrossAlignment3d value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  WrapCrossAlignment3d _depthAxisAlignment;

  /// How a child sits on the axis that does not wrap.
  WrapCrossAlignment3d get depthAxisAlignment => _depthAxisAlignment;

  set depthAxisAlignment(WrapCrossAlignment3d value) {
    if (_depthAxisAlignment == value) return;
    _depthAxisAlignment = value;
    markNeedsLayout();
  }

  /// The axis runs stack along, and the axis that only ever aligns.
  (Axis3d, Axis3d) get crossAxes => _direction.others;

  /// Along the run axis the answers are exact: the smallest a wrap can be is
  /// its widest single child, since nothing narrower could hold that child on
  /// a run of its own, and the largest it can use is every child on one run.
  ///
  /// Across it they are the one-run answer, which is a lower bound. Knowing
  /// how thick a wrap would be at a given width means knowing how many runs
  /// it would break into, and that is a layout, not a measurement: Flutter
  /// answers it with a dry layout, which this package does not have. The
  /// depth axis is exact even so, because a wrap never breaks on depth.
  double _wrapIntrinsic(Axis3d axis, Size3d limits, {required bool min}) {
    var extent = 0.0;
    if (axis == _direction && !min) {
      for (final child in children) {
        extent += child.getMaxIntrinsicExtent(axis, limits);
      }
      return extent + _spacing * math.max(0, childCount - 1);
    }
    for (final child in children) {
      extent = math.max(
        extent,
        min
            ? child.getMinIntrinsicExtent(axis, limits)
            : child.getMaxIntrinsicExtent(axis, limits),
      );
    }
    return extent;
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _wrapIntrinsic(axis, limits, min: true);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _wrapIntrinsic(axis, limits, min: false);

  @override
  void performLayout() {
    final constraints = this.constraints;
    final mainAxis = _direction;
    final (crossAxis, depthAxis) = crossAxes;
    final mainLimit = constraints.maxAlong(mainAxis);

    if (childCount == 0) {
      size = constraints.constrain(Size3d.zero);
      return;
    }

    final childConstraints = const Constraints3d()
        .withAxis(mainAxis, min: 0.0, max: mainLimit)
        .withAxis(crossAxis, min: 0.0, max: constraints.maxAlong(crossAxis))
        .withAxis(depthAxis, min: 0.0, max: constraints.maxAlong(depthAxis));

    final runs = <_Run3d>[];
    var run = _Run3d(0);
    var mainExtent = 0.0;
    var crossExtent = 0.0;
    var depthExtent = 0.0;

    for (var index = 0; index < childCount; index++) {
      final child = childAt(index);
      child.layout(childConstraints, parentUsesSize: true);
      final childSize = child.size;
      final childMain = childSize.alongAxis(mainAxis);

      // The break test is Flutter's: a run that already holds something and
      // would overrun its limit closes before this child rather than after.
      if (run.count > 0 && run.mainExtent + _spacing + childMain > mainLimit) {
        runs.add(run);
        crossExtent += run.crossExtent + (runs.length > 1 ? _runSpacing : 0.0);
        mainExtent = math.max(mainExtent, run.mainExtent);
        run = _Run3d(index);
      }

      run
        ..mainExtent += childMain + (run.count > 0 ? _spacing : 0.0)
        ..crossExtent = math.max(
          run.crossExtent,
          childSize.alongAxis(crossAxis),
        )
        ..depthExtent = math.max(
          run.depthExtent,
          childSize.alongAxis(depthAxis),
        )
        ..count += 1;
      depthExtent = math.max(depthExtent, run.depthExtent);
    }

    runs.add(run);
    crossExtent += run.crossExtent + (runs.length > 1 ? _runSpacing : 0.0);
    mainExtent = math.max(mainExtent, run.mainExtent);

    size = constraints.constrain(
      Size3d.zero
          .withAxis(mainAxis, mainExtent)
          .withAxis(crossAxis, crossExtent)
          .withAxis(depthAxis, depthExtent),
    );

    final actualMain = size.alongAxis(mainAxis);
    final actualCross = size.alongAxis(crossAxis);
    final actualDepth = size.alongAxis(depthAxis);

    final (runLead, runBetween) = _distribute(
      _runAlignment,
      actualCross - crossExtent,
      runs.length,
    );

    var crossPosition = runLead;
    for (final metrics in runs) {
      final (childLead, childBetween) = _distribute(
        _alignment,
        actualMain - metrics.mainExtent,
        metrics.count,
      );
      var mainPosition = childLead;
      for (var index = metrics.start; index < metrics.end; index++) {
        final child = childAt(index);
        final childSize = child.size;
        child.place(
          Offset3d.zero
              .withAxis(mainAxis, mainPosition)
              .withAxis(
                crossAxis,
                crossPosition +
                    _crossOffset(
                      _crossAxisAlignment,
                      metrics.crossExtent,
                      childSize.alongAxis(crossAxis),
                    ),
              )
              .withAxis(
                depthAxis,
                _crossOffset(
                  _depthAxisAlignment,
                  actualDepth,
                  childSize.alongAxis(depthAxis),
                ),
              ),
        );
        mainPosition += childSize.alongAxis(mainAxis) + _spacing + childBetween;
      }
      crossPosition += metrics.crossExtent + _runSpacing + runBetween;
    }
  }

  /// The leading gap and the gap between neighbours, for [free] space shared
  /// by [count] items.
  static (double, double) _distribute(
    WrapAlignment3d alignment,
    double free,
    int count,
  ) {
    final remaining = math.max(0.0, free);
    final gaps = math.max(0, count - 1);
    return switch (alignment) {
      WrapAlignment3d.start => (0.0, 0.0),
      WrapAlignment3d.end => (remaining, 0.0),
      WrapAlignment3d.center => (remaining / 2.0, 0.0),
      WrapAlignment3d.spaceBetween => (0.0, gaps > 0 ? remaining / gaps : 0.0),
      WrapAlignment3d.spaceAround => () {
        final between = count > 0 ? remaining / count : 0.0;
        return (between / 2.0, between);
      }(),
      WrapAlignment3d.spaceEvenly => () {
        final between = remaining / (count + 1);
        return (between, between);
      }(),
    };
  }

  static double _crossOffset(
    WrapCrossAlignment3d alignment,
    double extent,
    double childExtent,
  ) => switch (alignment) {
    WrapCrossAlignment3d.start => 0.0,
    WrapCrossAlignment3d.end => extent - childExtent,
    WrapCrossAlignment3d.center => (extent - childExtent) / 2.0,
  };

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<Axis3d>('direction', direction));
    properties.add(EnumProperty<WrapAlignment3d>('alignment', alignment));
    properties.add(DoubleProperty('spacing', spacing, defaultValue: 0.0));
    properties.add(EnumProperty<WrapAlignment3d>('runAlignment', runAlignment));
    properties.add(DoubleProperty('runSpacing', runSpacing, defaultValue: 0.0));
    properties.add(
      EnumProperty<WrapCrossAlignment3d>(
        'crossAxisAlignment',
        crossAxisAlignment,
      ),
    );
    properties.add(
      EnumProperty<WrapCrossAlignment3d>(
        'depthAxisAlignment',
        depthAxisAlignment,
      ),
    );
  }
}
