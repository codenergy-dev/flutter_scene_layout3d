import 'offset3d.dart';
import 'size3d.dart';

/// An immutable set of offsets on the six faces of a box, the 3D analogue of
/// [EdgeInsets].
///
/// The face names follow layout space: [top] is toward `-y`, [bottom] toward
/// `+y`, [front] toward `-z` (toward the viewer) and [back] toward `+z`.
class EdgeInsets3d {
  /// Creates insets from the six face values.
  const EdgeInsets3d.only({
    this.left = 0.0,
    this.top = 0.0,
    this.right = 0.0,
    this.bottom = 0.0,
    this.front = 0.0,
    this.back = 0.0,
  });

  /// The same inset on every face.
  const EdgeInsets3d.all(double value)
    : left = value,
      top = value,
      right = value,
      bottom = value,
      front = value,
      back = value;

  /// Insets symmetric about each axis.
  const EdgeInsets3d.symmetric({
    double horizontal = 0.0,
    double vertical = 0.0,
    double depth = 0.0,
  }) : left = horizontal,
       right = horizontal,
       top = vertical,
       bottom = vertical,
       front = depth,
       back = depth;

  /// Insets in left, top, right, bottom, front, back order.
  const EdgeInsets3d.fromLTRBFB(
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.front,
    this.back,
  );

  /// Inset from the left face (`-x`).
  final double left;

  /// Inset from the top face (`-y`).
  final double top;

  /// Inset from the right face (`+x`).
  final double right;

  /// Inset from the bottom face (`+y`).
  final double bottom;

  /// Inset from the front face (`-z`, toward the viewer).
  final double front;

  /// Inset from the back face (`+z`, away from the viewer).
  final double back;

  /// No inset on any face.
  static const EdgeInsets3d zero = EdgeInsets3d.all(0);

  /// The total inset along `x`.
  double get horizontal => left + right;

  /// The total inset along `y`.
  double get vertical => top + bottom;

  /// The total inset along `z`.
  double get alongDepth => front + back;

  /// The total inset along [axis], both faces together.
  double alongAxis(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => horizontal,
    Axis3d.vertical => vertical,
    Axis3d.depth => alongDepth,
  };

  /// The inset on the face [axis] starts at, the one nearest the origin
  /// corner.
  double lowAlong(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => left,
    Axis3d.vertical => top,
    Axis3d.depth => front,
  };

  /// The size the insets consume on their own.
  Size3d get collapsedSize => Size3d(horizontal, vertical, alongDepth);

  /// The offset of the inset box's origin corner.
  Offset3d get topLeftFront => Offset3d(left, top, front);

  /// Whether every inset is zero or greater.
  bool get isNonNegative =>
      left >= 0.0 &&
      top >= 0.0 &&
      right >= 0.0 &&
      bottom >= 0.0 &&
      front >= 0.0 &&
      back >= 0.0;

  /// [size] shrunk by these insets, clamped at zero on every axis.
  Size3d deflateSize(Size3d size) => Size3d(
    (size.width - horizontal).clamp(0.0, double.infinity),
    (size.height - vertical).clamp(0.0, double.infinity),
    (size.depth - alongDepth).clamp(0.0, double.infinity),
  );

  /// [size] grown by these insets.
  Size3d inflateSize(Size3d size) => Size3d(
    size.width + horizontal,
    size.height + vertical,
    size.depth + alongDepth,
  );

  /// A copy with the given faces replaced.
  EdgeInsets3d copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? front,
    double? back,
  }) => EdgeInsets3d.fromLTRBFB(
    left ?? this.left,
    top ?? this.top,
    right ?? this.right,
    bottom ?? this.bottom,
    front ?? this.front,
    back ?? this.back,
  );

  EdgeInsets3d operator +(EdgeInsets3d other) => EdgeInsets3d.fromLTRBFB(
    left + other.left,
    top + other.top,
    right + other.right,
    bottom + other.bottom,
    front + other.front,
    back + other.back,
  );

  EdgeInsets3d operator *(double scale) => EdgeInsets3d.fromLTRBFB(
    left * scale,
    top * scale,
    right * scale,
    bottom * scale,
    front * scale,
    back * scale,
  );

  /// Linearly interpolates between two sets of insets.
  static EdgeInsets3d lerp(EdgeInsets3d a, EdgeInsets3d b, double t) =>
      EdgeInsets3d.fromLTRBFB(
        a.left + (b.left - a.left) * t,
        a.top + (b.top - a.top) * t,
        a.right + (b.right - a.right) * t,
        a.bottom + (b.bottom - a.bottom) * t,
        a.front + (b.front - a.front) * t,
        a.back + (b.back - a.back) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is EdgeInsets3d &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.front == front &&
      other.back == back;

  @override
  int get hashCode => Object.hash(left, top, right, bottom, front, back);

  @override
  String toString() =>
      'EdgeInsets3d($left, $top, $right, $bottom, $front, $back)';
}
