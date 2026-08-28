import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DoubleProperty, EnumProperty;

import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'shifted.dart';

/// Sizes its child to the child's own preferred extent along one axis, the 3D
/// analogue of [IntrinsicWidth] and [IntrinsicHeight].
///
/// The box asks its child [Layout3d.getMaxIntrinsicExtent] along [axis] and
/// then hands the child that extent, tightly. Every child of a
/// [Column3d] inside an [IntrinsicWidth3d] is therefore as wide as the widest
/// of them, which is the classic reason to reach for one.
///
/// It is expensive, and for the same reason as in Flutter: answering the
/// question walks the whole subtree, and then the subtree is laid out again
/// for real. Use it when the alternative is not expressible, not as a
/// shortcut past deciding a size.
///
/// The axis is a constructor argument here rather than three separate render
/// objects, because a box has three of them; [IntrinsicWidth3d],
/// [IntrinsicHeight3d] and [IntrinsicDepth3d] are the names to reach for.
class IntrinsicExtent3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a box that sizes its child to its intrinsic extent along [axis].
  IntrinsicExtent3d({
    required Axis3d axis,
    double? step,
    super.child,
    super.name,
  }) : _axis = axis,
       _step = step,
       assert(
         step == null || step > 0.0,
         'IntrinsicExtent3d.step must be positive.',
       );

  Axis3d _axis;

  /// The axis the child is sized to its own preference along.
  Axis3d get axis => _axis;

  set axis(Axis3d value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  double? _step;

  /// If non-null, the extent is rounded up to a multiple of this.
  ///
  /// Flutter's `stepWidth`, under the name that fits a box with three axes.
  /// Useful when content that grows a little should not nudge everything
  /// beside it: give it a step and it grows in visible increments instead.
  double? get step => _step;

  set step(double? value) {
    if (_step == value) return;
    assert(value == null || value > 0.0);
    _step = value;
    markNeedsLayout();
  }

  double _stepped(double extent) {
    final step = _step;
    if (step == null || !extent.isFinite || extent <= 0.0) return extent;
    return (extent / step).ceil() * step;
  }

  /// [limits] with a finite extent along [axis], which is what the other two
  /// axes need before they can be asked anything.
  ///
  /// Asked how thick it is without being told how wide it may be, this box
  /// has an answer no other box has: it decides the width itself, so it
  /// decides it and then asks the child. Flutter's `RenderIntrinsicWidth`
  /// does the same.
  Size3d _resolvedLimits(Size3d limits) {
    if (limits.alongAxis(_axis).isFinite) return limits;
    final child = this.child;
    if (child == null) return limits.withAxis(_axis, 0.0);
    return limits.withAxis(
      _axis,
      _stepped(child.getMaxIntrinsicExtent(_axis, limits)),
    );
  }

  /// There is no room this box would give up anything for along [axis]: it
  /// takes the child's preferred extent and nothing less, so the minimum and
  /// the maximum are the same number.
  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) {
    if (axis == _axis) return computeMaxIntrinsicExtent(axis, limits);
    return child?.getMinIntrinsicExtent(axis, _resolvedLimits(limits)) ?? 0.0;
  }

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) {
    final child = this.child;
    if (child == null) return 0.0;
    if (axis == _axis) {
      return _stepped(child.getMaxIntrinsicExtent(axis, limits));
    }
    return child.getMaxIntrinsicExtent(axis, _resolvedLimits(limits));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    var childConstraints = constraints;
    // An axis the parent has already fixed leaves nothing to decide, and
    // asking anyway would walk the subtree for an answer that cannot be used.
    if (!childConstraints.hasTightAlong(_axis)) {
      final extent = child.getMaxIntrinsicExtent(
        _axis,
        childConstraints.biggest,
      );
      childConstraints = childConstraints.tightenAlong(_axis, _stepped(extent));
    }
    child.layout(childConstraints, parentUsesSize: true);
    size = child.size;
    child.place(Offset3d.zero);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<Axis3d>('axis', axis));
    properties.add(DoubleProperty('step', step, defaultValue: null));
  }
}

/// Sizes its child to its own preferred width, the 3D analogue of
/// [IntrinsicWidth].
class IntrinsicWidth3d extends IntrinsicExtent3d {
  /// Creates a width-shrinking box.
  IntrinsicWidth3d({super.step, super.child, super.name})
    : super(axis: Axis3d.horizontal);
}

/// Sizes its child to its own preferred height, the 3D analogue of
/// [IntrinsicHeight].
class IntrinsicHeight3d extends IntrinsicExtent3d {
  /// Creates a height-shrinking box.
  IntrinsicHeight3d({super.step, super.child, super.name})
    : super(axis: Axis3d.vertical);
}

/// Sizes its child to its own preferred depth, the axis Flutter does not
/// have.
class IntrinsicDepth3d extends IntrinsicExtent3d {
  /// Creates a depth-shrinking box.
  IntrinsicDepth3d({super.step, super.child, super.name})
    : super(axis: Axis3d.depth);
}

/// Positions its child so that the child's baseline lands at a given distance
/// from this box's origin corner, the 3D analogue of [Baseline].
///
/// This is the box that puts content *on* a line, and, in this package, the
/// box that gives content a line at all: it reports [baseline] as its own
/// baseline along [axis] whether or not the child had one to offer. Flutter
/// can be stricter because its text reports a real baseline of its own;
/// nothing in a scene does, so declaring one is what this box is for.
///
/// Line something up with it by asking for
/// [CrossAxisAlignment3d.baseline] on the enclosing flex.
class Baseline3d extends ShiftedLayout3d {
  /// Creates a box that puts its child's baseline at [baseline].
  Baseline3d({
    required double baseline,
    Axis3d axis = Axis3d.vertical,
    super.child,
    super.name,
  }) : _baseline = baseline,
       _axis = axis;

  double _baseline;

  /// Where the child's baseline sits, measured from this box's origin corner
  /// along [axis].
  double get baseline => _baseline;

  set baseline(double value) {
    if (_baseline == value) return;
    _baseline = value;
    markNeedsLayout();
  }

  Axis3d _axis;

  /// The axis the baseline is measured along.
  ///
  /// [Axis3d.vertical] by default, the axis a Flutter baseline runs across.
  Axis3d get axis => _axis;

  set axis(Axis3d value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(Axis3d axis) =>
      axis == _axis ? _baseline : super.computeDistanceToActualBaseline(axis);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    // A child with no baseline of its own is taken to rest on its far edge,
    // the substitution Flutter makes everywhere a baseline is missing.
    final childBaseline = child.getDistanceToBaseline(_axis)!;
    final shift = _baseline - childBaseline;
    final childSize = child.size;
    size = constraints.constrain(
      childSize.withAxis(_axis, shift + childSize.alongAxis(_axis)),
    );
    child.place(Offset3d.along(_axis, shift));
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('baseline', baseline));
    properties.add(EnumProperty<Axis3d>('axis', axis));
  }
}
