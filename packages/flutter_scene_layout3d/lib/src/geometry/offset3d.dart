import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' show Vector3;

/// The three axes of layout space.
///
/// Layout space is Flutter's 2D coordinate system with a third axis added:
/// [horizontal] is `x` and grows to the right, [vertical] is `y` and grows
/// *downward*, and [depth] is `z` and grows *away from the viewer*. A box
/// therefore occupies `[0, width] x [0, height] x [0, depth]` from its own
/// origin corner, exactly the way a Flutter box occupies `[0, width] x
/// [0, height]` from its top left.
///
/// Nothing in the scene sees these coordinates: a [LayoutBasis3d] on the
/// surface maps them to the engine's Y-up scene space once, at the root.
enum Axis3d {
  /// The `x` axis, growing right.
  horizontal,

  /// The `y` axis, growing down.
  vertical,

  /// The `z` axis, growing away from the viewer.
  depth;

  /// The other two axes, in canonical (`x`, `y`, `z`) order.
  ///
  /// A [Flex3d] uses this to decide which axis its `crossAxisAlignment`
  /// applies to (the first) and which its `depthAxisAlignment` applies to
  /// (the second): a [Axis3d.horizontal] flex (a `Row3d`) crosses on `y` then
  /// `z`, a [Axis3d.vertical] flex (a `Column3d`) crosses on `x` then `z`.
  (Axis3d, Axis3d) get others => switch (this) {
    Axis3d.horizontal => (Axis3d.vertical, Axis3d.depth),
    Axis3d.vertical => (Axis3d.horizontal, Axis3d.depth),
    Axis3d.depth => (Axis3d.horizontal, Axis3d.vertical),
  };
}

/// An immutable position in layout space, the 3D analogue of [Offset].
///
/// Distinct from [Vector3] on purpose: a [Vector3] in this package is a scene
/// space vector (Y up, mutable), an [Offset3d] is a layout space position
/// (Y down, immutable). [toVector3] converts when you need to hand one to the
/// engine, though usually the surface's [LayoutBasis3d] does that for you.
class Offset3d {
  /// Creates an offset from its three components.
  const Offset3d(this.x, this.y, this.z);

  /// Creates an offset along a single [axis], zero on the other two.
  const Offset3d.along(Axis3d axis, double value)
    : x = axis == Axis3d.horizontal ? value : 0.0,
      y = axis == Axis3d.vertical ? value : 0.0,
      z = axis == Axis3d.depth ? value : 0.0;

  /// Rightward distance from the origin corner.
  final double x;

  /// Downward distance from the origin corner.
  final double y;

  /// Distance away from the viewer, from the origin corner.
  final double z;

  /// The origin corner.
  static const Offset3d zero = Offset3d(0, 0, 0);

  /// The component along [axis].
  double alongAxis(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => x,
    Axis3d.vertical => y,
    Axis3d.depth => z,
  };

  /// A copy with the component along [axis] replaced by [value].
  Offset3d withAxis(Axis3d axis, double value) => switch (axis) {
    Axis3d.horizontal => Offset3d(value, y, z),
    Axis3d.vertical => Offset3d(x, value, z),
    Axis3d.depth => Offset3d(x, y, value),
  };

  /// The distance from the origin corner.
  double get distance => math.sqrt(x * x + y * y + z * z);

  /// Whether every component is finite.
  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  /// A mutable scene-space vector with the same components.
  ///
  /// Only meaningful after a [LayoutBasis3d] has mapped this offset out of
  /// layout space; see [LayoutBasis3d.offsetToScene].
  Vector3 toVector3() => Vector3(x, y, z);

  Offset3d operator +(Offset3d other) =>
      Offset3d(x + other.x, y + other.y, z + other.z);

  Offset3d operator -(Offset3d other) =>
      Offset3d(x - other.x, y - other.y, z - other.z);

  Offset3d operator *(double scale) =>
      Offset3d(x * scale, y * scale, z * scale);

  Offset3d operator /(double divisor) =>
      Offset3d(x / divisor, y / divisor, z / divisor);

  Offset3d operator -() => Offset3d(-x, -y, -z);

  /// Linearly interpolates between two offsets.
  static Offset3d lerp(Offset3d a, Offset3d b, double t) => Offset3d(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.z + (b.z - a.z) * t,
  );

  @override
  bool operator ==(Object other) =>
      other is Offset3d && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() =>
      'Offset3d(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, '
      '${z.toStringAsFixed(3)})';
}
