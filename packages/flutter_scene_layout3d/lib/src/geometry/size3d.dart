import 'package:vector_math/vector_math.dart' show Vector3;

import 'offset3d.dart';

/// The extent of a box in layout space, the 3D analogue of [Size].
///
/// A size is three non-negative magnitudes, not a position: a box of this size
/// spans `[0, width] x [0, height] x [0, depth]` from its origin corner.
class Size3d {
  /// Creates a size from its three extents.
  const Size3d(this.width, this.height, this.depth);

  /// A cube [extent] on a side.
  const Size3d.cube(double extent)
    : width = extent,
      height = extent,
      depth = extent;

  /// A size with the same extent on every axis as [value] has along [axis],
  /// and zero on the others.
  const Size3d.along(Axis3d axis, double value)
    : width = axis == Axis3d.horizontal ? value : 0.0,
      height = axis == Axis3d.vertical ? value : 0.0,
      depth = axis == Axis3d.depth ? value : 0.0;

  /// Extent along `x`.
  final double width;

  /// Extent along `y`.
  final double height;

  /// Extent along `z`.
  final double depth;

  /// A box with no extent.
  static const Size3d zero = Size3d(0, 0, 0);

  /// A box that is infinite on every axis.
  static const Size3d infinite = Size3d(
    double.infinity,
    double.infinity,
    double.infinity,
  );

  /// The extent along [axis].
  double alongAxis(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => width,
    Axis3d.vertical => height,
    Axis3d.depth => depth,
  };

  /// A copy with the extent along [axis] replaced by [value].
  Size3d withAxis(Axis3d axis, double value) => switch (axis) {
    Axis3d.horizontal => Size3d(value, height, depth),
    Axis3d.vertical => Size3d(width, value, depth),
    Axis3d.depth => Size3d(width, height, value),
  };

  /// Whether every extent is finite.
  bool get isFinite => width.isFinite && height.isFinite && depth.isFinite;

  /// Whether any extent is infinite.
  bool get isInfinite =>
      width == double.infinity ||
      height == double.infinity ||
      depth == double.infinity;

  /// Whether every extent is zero or greater and no extent is NaN.
  bool get isNonNegative => width >= 0.0 && height >= 0.0 && depth >= 0.0;

  /// The volume enclosed.
  double get volume => width * height * depth;

  /// The offset of the box's center from its origin corner.
  Offset3d get center => Offset3d(width / 2.0, height / 2.0, depth / 2.0);

  /// The offset of the corner diagonally opposite the origin corner.
  Offset3d get farCorner => Offset3d(width, height, depth);

  /// The extents as a mutable vector.
  Vector3 toVector3() => Vector3(width, height, depth);

  /// Whether a box of this size contains the point at [offset], measured from
  /// this box's origin corner.
  bool contains(Offset3d offset) =>
      offset.x >= 0.0 &&
      offset.x < width &&
      offset.y >= 0.0 &&
      offset.y < height &&
      offset.z >= 0.0 &&
      offset.z < depth;

  Size3d operator +(Size3d other) =>
      Size3d(width + other.width, height + other.height, depth + other.depth);

  Size3d operator -(Size3d other) =>
      Size3d(width - other.width, height - other.height, depth - other.depth);

  Size3d operator *(double scale) =>
      Size3d(width * scale, height * scale, depth * scale);

  Size3d operator /(double divisor) =>
      Size3d(width / divisor, height / divisor, depth / divisor);

  /// Linearly interpolates between two sizes.
  static Size3d lerp(Size3d a, Size3d b, double t) => Size3d(
    a.width + (b.width - a.width) * t,
    a.height + (b.height - a.height) * t,
    a.depth + (b.depth - a.depth) * t,
  );

  @override
  bool operator ==(Object other) =>
      other is Size3d &&
      other.width == width &&
      other.height == height &&
      other.depth == depth;

  @override
  int get hashCode => Object.hash(width, height, depth);

  @override
  String toString() =>
      'Size3d(${width.toStringAsFixed(3)}, ${height.toStringAsFixed(3)}, '
      '${depth.toStringAsFixed(3)})';
}
