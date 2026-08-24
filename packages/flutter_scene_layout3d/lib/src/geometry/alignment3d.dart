import 'offset3d.dart';
import 'size3d.dart';

/// A point within a box, expressed as a fraction of the box's extents, the 3D
/// analogue of [Alignment].
///
/// Each component runs from `-1` at the low face to `+1` at the high face,
/// with `0` at the center: `x` is `-1` at the left, `y` is `-1` at the top,
/// and `z` is `-1` at the front (the face toward the viewer).
class Alignment3d {
  /// Creates an alignment from its three fractional components.
  const Alignment3d(this.x, this.y, this.z);

  /// The fraction along `x`: `-1` left, `+1` right.
  final double x;

  /// The fraction along `y`: `-1` top, `+1` bottom.
  final double y;

  /// The fraction along `z`: `-1` front, `+1` back.
  final double z;

  /// The center of the box on every axis.
  static const Alignment3d center = Alignment3d(0, 0, 0);

  /// Center of the top left edge, centered in depth.
  static const Alignment3d topLeft = Alignment3d(-1, -1, 0);

  /// Center of the top face, centered in depth.
  static const Alignment3d topCenter = Alignment3d(0, -1, 0);

  /// Center of the top right edge, centered in depth.
  static const Alignment3d topRight = Alignment3d(1, -1, 0);

  /// Center of the left face, centered in depth.
  static const Alignment3d centerLeft = Alignment3d(-1, 0, 0);

  /// Center of the right face, centered in depth.
  static const Alignment3d centerRight = Alignment3d(1, 0, 0);

  /// Center of the bottom left edge, centered in depth.
  static const Alignment3d bottomLeft = Alignment3d(-1, 1, 0);

  /// Center of the bottom face, centered in depth.
  static const Alignment3d bottomCenter = Alignment3d(0, 1, 0);

  /// Center of the bottom right edge, centered in depth.
  static const Alignment3d bottomRight = Alignment3d(1, 1, 0);

  /// Center of the front face, the one facing the viewer.
  static const Alignment3d frontCenter = Alignment3d(0, 0, -1);

  /// Center of the back face, the one facing away from the viewer.
  static const Alignment3d backCenter = Alignment3d(0, 0, 1);

  /// The origin corner: left, top, front.
  static const Alignment3d topLeftFront = Alignment3d(-1, -1, -1);

  /// The far corner: right, bottom, back.
  static const Alignment3d bottomRightBack = Alignment3d(1, 1, 1);

  /// The offset of this alignment's point from the origin corner of a box of
  /// [size].
  ///
  /// [Alignment3d.center] of a `2 x 2 x 2` box is `Offset3d(1, 1, 1)`.
  Offset3d alongSize(Size3d size) => Offset3d(
    (1.0 + x) / 2.0 * size.width,
    (1.0 + y) / 2.0 * size.height,
    (1.0 + z) / 2.0 * size.depth,
  );

  /// The offset of this alignment's point from the center of a box of [size].
  Offset3d alongOffset(Size3d size) => Offset3d(
    x * size.width / 2.0,
    y * size.height / 2.0,
    z * size.depth / 2.0,
  );

  /// The origin corner of a [child] box placed inside a [container] box at
  /// this alignment.
  ///
  /// This is the positioning rule every aligning layout uses: `Align3d`,
  /// `Center3d`, `Container3d`, `Stack3d`, and the cross axes of `Flex3d`.
  Offset3d inscribe(Size3d child, Size3d container) => Offset3d(
    (1.0 + x) / 2.0 * (container.width - child.width),
    (1.0 + y) / 2.0 * (container.height - child.height),
    (1.0 + z) / 2.0 * (container.depth - child.depth),
  );

  /// A copy with the given components replaced.
  Alignment3d copyWith({double? x, double? y, double? z}) =>
      Alignment3d(x ?? this.x, y ?? this.y, z ?? this.z);

  Alignment3d operator +(Alignment3d other) =>
      Alignment3d(x + other.x, y + other.y, z + other.z);

  Alignment3d operator -(Alignment3d other) =>
      Alignment3d(x - other.x, y - other.y, z - other.z);

  Alignment3d operator -() => Alignment3d(-x, -y, -z);

  Alignment3d operator *(double scale) =>
      Alignment3d(x * scale, y * scale, z * scale);

  /// Linearly interpolates between two alignments.
  static Alignment3d lerp(Alignment3d a, Alignment3d b, double t) =>
      Alignment3d(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is Alignment3d && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Alignment3d($x, $y, $z)';
}
