import 'dart:math' as math;

import '../geometry/alignment3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// How a [Stack3d] sizes its non-positioned children, the 3D analogue of
/// [StackFit].
enum StackFit3d {
  /// Children may be any size up to the stack's constraints.
  loose,

  /// Children are forced to fill the stack.
  expand,

  /// Children receive the stack's own constraints unchanged.
  passthrough,
}

/// Anchors a child of a [Stack3d] to the stack's faces, the 3D analogue of
/// [Positioned].
///
/// Give at most two of the three values on an axis: an inset from the low
/// face, an inset from the high face, and a fixed extent. Two of them fix
/// both the position and the size; one leaves the other to the child and the
/// stack's alignment.
class Positioned3d extends ProxyLayout3d {
  /// Creates a positioned child.
  Positioned3d({
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? front,
    double? back,
    double? width,
    double? height,
    double? depth,
    super.child,
    super.name,
  }) : _left = left,
       _top = top,
       _right = right,
       _bottom = bottom,
       _front = front,
       _back = back,
       _width = width,
       _height = height,
       _depth = depth,
       assert(
         left == null || right == null || width == null,
         'Give at most two of left, right, and width.',
       ),
       assert(
         top == null || bottom == null || height == null,
         'Give at most two of top, bottom, and height.',
       ),
       assert(
         front == null || back == null || depth == null,
         'Give at most two of front, back, and depth.',
       );

  double? _left;

  /// Inset from the stack's left face.
  double? get left => _left;

  set left(double? value) {
    if (_left == value) return;
    _left = value;
    markParentNeedsLayout();
  }

  double? _top;

  /// Inset from the stack's top face.
  double? get top => _top;

  set top(double? value) {
    if (_top == value) return;
    _top = value;
    markParentNeedsLayout();
  }

  double? _right;

  /// Inset from the stack's right face.
  double? get right => _right;

  set right(double? value) {
    if (_right == value) return;
    _right = value;
    markParentNeedsLayout();
  }

  double? _bottom;

  /// Inset from the stack's bottom face.
  double? get bottom => _bottom;

  set bottom(double? value) {
    if (_bottom == value) return;
    _bottom = value;
    markParentNeedsLayout();
  }

  double? _front;

  /// Inset from the stack's front face, the one toward the viewer.
  double? get front => _front;

  set front(double? value) {
    if (_front == value) return;
    _front = value;
    markParentNeedsLayout();
  }

  double? _back;

  /// Inset from the stack's back face.
  double? get back => _back;

  set back(double? value) {
    if (_back == value) return;
    _back = value;
    markParentNeedsLayout();
  }

  double? _width;

  /// A fixed width.
  double? get width => _width;

  set width(double? value) {
    if (_width == value) return;
    _width = value;
    markParentNeedsLayout();
  }

  double? _height;

  /// A fixed height.
  double? get height => _height;

  set height(double? value) {
    if (_height == value) return;
    _height = value;
    markParentNeedsLayout();
  }

  double? _depth;

  /// A fixed depth.
  double? get depth => _depth;

  set depth(double? value) {
    if (_depth == value) return;
    _depth = value;
    markParentNeedsLayout();
  }

  /// Whether this child pins itself to the stack rather than being aligned
  /// with the non-positioned ones.
  bool get isPositioned =>
      left != null ||
      top != null ||
      right != null ||
      bottom != null ||
      front != null ||
      back != null ||
      width != null ||
      height != null ||
      depth != null;

  double? _lowOf(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => left,
    Axis3d.vertical => top,
    Axis3d.depth => front,
  };

  double? _highOf(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => right,
    Axis3d.vertical => bottom,
    Axis3d.depth => back,
  };

  double? _extentOf(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => width,
    Axis3d.vertical => height,
    Axis3d.depth => depth,
  };
}

/// Overlays its children, the 3D analogue of [Stack].
///
/// Non-positioned children are sized according to [fit] and placed by
/// [alignment]; [Positioned3d] children are pinned to the stack's faces. The
/// stack sizes itself to its largest non-positioned child.
///
/// Depth is where a 3D stack parts ways with Flutter's. Two children that
/// share the same `z` are coplanar and will fight for the depth buffer, so
/// [depthStep] pulls each successive child toward the viewer by a fixed
/// amount, reproducing "later children paint on top" with real geometry. It
/// does not affect the stack's size.
class Stack3d extends MultiChildLayout3d<ParentData3d> {
  /// Creates a stack of overlaid children.
  Stack3d({
    Alignment3d alignment = Alignment3d.topLeftFront,
    StackFit3d fit = StackFit3d.loose,
    double depthStep = 0.0,
    super.children,
    super.name,
  }) : _alignment = alignment,
       _fit = fit,
       _depthStep = depthStep;

  Alignment3d _alignment;

  /// Where non-positioned children sit, and how partly-positioned children
  /// resolve the axes they left open.
  Alignment3d get alignment => _alignment;

  set alignment(Alignment3d value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  StackFit3d _fit;

  /// How non-positioned children are sized.
  StackFit3d get fit => _fit;

  set fit(StackFit3d value) {
    if (_fit == value) return;
    _fit = value;
    markNeedsLayout();
  }

  double _depthStep;

  /// How far toward the viewer each successive child is pulled.
  double get depthStep => _depthStep;

  set depthStep(double value) {
    if (_depthStep == value) return;
    _depthStep = value;
    markNeedsLayout();
  }

  /// The largest of the non-positioned children's intrinsic extents.
  ///
  /// Positioned children are pinned to faces the stack does not have yet
  /// while the question is being asked, so, as in Flutter, they are left out
  /// of it.
  double _stackIntrinsic(Axis3d axis, Size3d limits, {required bool min}) {
    var extent = 0.0;
    for (final child in children) {
      if (child is Positioned3d && child.isPositioned) continue;
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
      _stackIntrinsic(axis, limits, min: true);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _stackIntrinsic(axis, limits, min: false);

  /// Overlaid children all hang from the same corner, so the stack's baseline
  /// is the highest one among them.
  @override
  double? computeDistanceToActualBaseline(Axis3d axis) =>
      defaultComputeDistanceToHighestActualBaseline(axis);

  @override
  void performLayout() {
    final constraints = this.constraints;
    final nonPositionedConstraints = switch (_fit) {
      StackFit3d.loose => constraints.loosen(),
      StackFit3d.expand => Constraints3d.tight(constraints.biggest),
      StackFit3d.passthrough => constraints,
    };

    var hasNonPositioned = false;
    var width = constraints.minWidth;
    var height = constraints.minHeight;
    var depth = constraints.minDepth;

    for (final child in children) {
      if (child is Positioned3d && child.isPositioned) continue;
      hasNonPositioned = true;
      child.layout(nonPositionedConstraints, parentUsesSize: true);
      final childSize = child.size;
      width = math.max(width, childSize.width);
      height = math.max(height, childSize.height);
      depth = math.max(depth, childSize.depth);
    }

    size = hasNonPositioned
        ? constraints.constrain(Size3d(width, height, depth))
        : _biggestOrSmallest(constraints);

    final stackSize = size;
    var index = 0;
    for (final child in children) {
      final positioned = child is Positioned3d && child.isPositioned
          ? child
          : null;
      final Offset3d anchor;
      if (positioned == null) {
        anchor = _alignment.inscribe(child.size, stackSize);
      } else {
        child.layout(
          _positionedConstraints(positioned, stackSize),
          parentUsesSize: true,
        );
        anchor = _positionedOffset(positioned, child.size, stackSize);
      }
      child.place(anchor - Offset3d(0, 0, index * _depthStep));
      index++;
    }
  }

  static Size3d _biggestOrSmallest(Constraints3d constraints) => Size3d(
    constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth,
    constraints.hasBoundedHeight
        ? constraints.maxHeight
        : constraints.minHeight,
    constraints.hasBoundedDepth ? constraints.maxDepth : constraints.minDepth,
  );

  Constraints3d _positionedConstraints(Positioned3d child, Size3d stackSize) {
    var result = const Constraints3d();
    for (final axis in Axis3d.values) {
      final low = child._lowOf(axis);
      final high = child._highOf(axis);
      final extent = child._extentOf(axis);
      final double? tight;
      if (low != null && high != null) {
        tight = math.max(0.0, stackSize.alongAxis(axis) - low - high);
      } else {
        tight = extent;
      }
      if (tight != null) {
        result = result.withAxis(axis, min: tight, max: tight);
      } else {
        // Flutter leaves an unpinned axis unconstrained, which in 2D means a
        // too-large child simply overflows on screen. In 3D it means geometry
        // poking out through the plane, and depth is the axis a caller
        // reaching for a 2D habit forgets, so the stack caps it instead.
        result = result.withAxis(
          axis,
          min: 0.0,
          max: stackSize.alongAxis(axis),
        );
      }
    }
    return result;
  }

  Offset3d _positionedOffset(
    Positioned3d child,
    Size3d childSize,
    Size3d stackSize,
  ) {
    var result = Offset3d.zero;
    final aligned = _alignment.inscribe(childSize, stackSize);
    for (final axis in Axis3d.values) {
      final low = child._lowOf(axis);
      final high = child._highOf(axis);
      final double value;
      if (low != null) {
        value = low;
      } else if (high != null) {
        value = stackSize.alongAxis(axis) - high - childSize.alongAxis(axis);
      } else {
        value = aligned.alongAxis(axis);
      }
      result = result.withAxis(axis, value);
    }
    return result;
  }
}
