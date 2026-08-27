import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'size3d.dart';

/// The four in-plane corner radii of a box.
///
/// A panel in a 3D layout is a slab, and a slab has twelve edges — but only
/// four of them are the corners a component spec talks about. Material's
/// shape scale rounds the outline you see face-on: the top-left, top-right,
/// bottom-left and bottom-right of the plane. The other eight edges are the
/// slab's *thickness*, and rounding those is a different dial
/// (`BoxDecoration3d.bevel`), because a card wants a 12dp face radius and a
/// 0.5dp softened rim, not the same number on both.
///
/// The figures carry no unit of their own: they are in whatever frame the
/// holder states. [BoxDecoration3d] states them in logical pixels, the way a
/// Material shape token is written, and the metrics turn them into world
/// units at paint time; a caller working directly in world units states them
/// in world units.
///
/// [resolve] holds the radii down to what the box can actually fit, the same
/// way Flutter's `RRect` scales a rounded rectangle whose radii overlap. A
/// painter should resolve before it packs anything, so that a card animating
/// down to nothing degrades into a lozenge and then a point instead of
/// folding inside out.
class BorderRadius3d {
  /// Creates a radius per corner.
  const BorderRadius3d({
    this.topLeft = 0.0,
    this.topRight = 0.0,
    this.bottomLeft = 0.0,
    this.bottomRight = 0.0,
  }) : assert(topLeft >= 0.0),
       assert(topRight >= 0.0),
       assert(bottomLeft >= 0.0),
       assert(bottomRight >= 0.0);

  /// The same radius on all four corners.
  const BorderRadius3d.circular(double radius)
    : this(
        topLeft: radius,
        topRight: radius,
        bottomLeft: radius,
        bottomRight: radius,
      );

  /// A radius on the top two corners, none on the bottom.
  const BorderRadius3d.vertical({double top = 0.0, double bottom = 0.0})
    : this(
        topLeft: top,
        topRight: top,
        bottomLeft: bottom,
        bottomRight: bottom,
      );

  /// A radius on the left two corners, none on the right.
  const BorderRadius3d.horizontal({double left = 0.0, double right = 0.0})
    : this(
        topLeft: left,
        topRight: right,
        bottomLeft: left,
        bottomRight: right,
      );

  /// Square corners.
  static const BorderRadius3d zero = BorderRadius3d();

  /// The radius at the box's origin corner (minimum `x`, minimum `y`).
  final double topLeft;

  /// The radius at maximum `x`, minimum `y`.
  final double topRight;

  /// The radius at minimum `x`, maximum `y`.
  final double bottomLeft;

  /// The radius at maximum `x`, maximum `y`.
  final double bottomRight;

  /// Whether every corner is square.
  bool get isZero =>
      topLeft == 0.0 &&
      topRight == 0.0 &&
      bottomLeft == 0.0 &&
      bottomRight == 0.0;

  /// The largest radius of the four.
  double get largest =>
      math.max(math.max(topLeft, topRight), math.max(bottomLeft, bottomRight));

  /// These radii, held down to what [size] can fit.
  ///
  /// Two radii sharing an edge cannot together exceed that edge, and a corner
  /// cannot exceed half the box on either axis. When they do, every radius is
  /// scaled by the same factor, which is what keeps a shrinking panel's
  /// corners in proportion rather than letting the tightest one collapse
  /// first. Flutter's `RRect.scaleRadii` does the same arithmetic in two
  /// dimensions.
  BorderRadius3d resolve(Size3d size) {
    if (isZero) return this;
    var scale = 1.0;
    scale = _limit(scale, topLeft + topRight, size.width);
    scale = _limit(scale, bottomLeft + bottomRight, size.width);
    scale = _limit(scale, topLeft + bottomLeft, size.height);
    scale = _limit(scale, topRight + bottomRight, size.height);
    if (scale >= 1.0) return this;
    return this * scale;
  }

  static double _limit(double scale, double sum, double extent) {
    if (sum <= 0.0) return scale;
    if (!extent.isFinite) return scale;
    if (extent <= 0.0) return 0.0;
    return math.min(scale, extent / sum);
  }

  /// Every radius multiplied by [factor].
  BorderRadius3d operator *(double factor) => BorderRadius3d(
    topLeft: topLeft * factor,
    topRight: topRight * factor,
    bottomLeft: bottomLeft * factor,
    bottomRight: bottomRight * factor,
  );

  /// A copy with the given corners replaced.
  BorderRadius3d copyWith({
    double? topLeft,
    double? topRight,
    double? bottomLeft,
    double? bottomRight,
  }) => BorderRadius3d(
    topLeft: topLeft ?? this.topLeft,
    topRight: topRight ?? this.topRight,
    bottomLeft: bottomLeft ?? this.bottomLeft,
    bottomRight: bottomRight ?? this.bottomRight,
  );

  /// Linearly interpolates between two radii.
  static BorderRadius3d lerp(BorderRadius3d a, BorderRadius3d b, double t) =>
      BorderRadius3d(
        topLeft: lerpDouble(a.topLeft, b.topLeft, t)!,
        topRight: lerpDouble(a.topRight, b.topRight, t)!,
        bottomLeft: lerpDouble(a.bottomLeft, b.bottomLeft, t)!,
        bottomRight: lerpDouble(a.bottomRight, b.bottomRight, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is BorderRadius3d &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomLeft == bottomLeft &&
      other.bottomRight == bottomRight;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomLeft, bottomRight);

  @override
  String toString() {
    if (isZero) return 'BorderRadius3d.zero';
    if (topLeft == topRight &&
        topLeft == bottomLeft &&
        topLeft == bottomRight) {
      return 'BorderRadius3d.circular($topLeft)';
    }
    return 'BorderRadius3d($topLeft, $topRight, $bottomLeft, $bottomRight)';
  }
}
