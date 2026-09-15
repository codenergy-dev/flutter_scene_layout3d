import 'dart:ui' show TextDirection;

import 'offset3d.dart';
import 'size3d.dart';

/// The base type of [Alignment3d] and [AlignmentDirectional3d], the 3D
/// analogue of [AlignmentGeometry].
///
/// A box that places a child inside itself takes one of these, and turns it
/// into a physical [Alignment3d] with [resolve] when it lays out, against the
/// reading direction it was given. Adding a physical alignment to a
/// directional one gives a private third kind that holds both until then.
///
/// **Depth has no direction.** Every kind has a physical `z`: `-1` is the
/// front, the face toward the viewer, in every language.
abstract class AlignmentGeometry3d {
  /// Abstract const constructor, so the subclasses can be const.
  const AlignmentGeometry3d();

  double get _x;
  double get _start;
  double get _y;
  double get _z;

  /// The sum of this alignment and [other], whatever kind either is.
  AlignmentGeometry3d add(AlignmentGeometry3d other) {
    final self = this;
    if (self is Alignment3d && other is Alignment3d) return self + other;
    if (self is AlignmentDirectional3d && other is AlignmentDirectional3d) {
      return self + other;
    }
    return _MixedAlignment3d(
      _x + other._x,
      _start + other._start,
      _y + other._y,
      _z + other._z,
    );
  }

  /// Every component scaled by [scale].
  AlignmentGeometry3d operator *(double scale);

  /// The physical alignment this stands for, read in [direction].
  ///
  /// A null direction reads left to right, which is where this package
  /// departs from Flutter's assertion: a layout here has always been allowed
  /// to say nothing about direction, and text already falls back the same way.
  Alignment3d resolve(TextDirection? direction);

  /// Linearly interpolates between two alignments of any kind.
  ///
  /// Null stands for the centre, as in Flutter.
  static AlignmentGeometry3d? lerp(
    AlignmentGeometry3d? a,
    AlignmentGeometry3d? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null) return b! * t;
    if (b == null) return a * (1.0 - t);
    if (a is Alignment3d && b is Alignment3d) return Alignment3d.lerp(a, b, t);
    if (a is AlignmentDirectional3d && b is AlignmentDirectional3d) {
      return AlignmentDirectional3d.lerp(a, b, t);
    }
    double mix(double x, double y) => x + (y - x) * t;
    return _MixedAlignment3d(
      mix(a._x, b._x),
      mix(a._start, b._start),
      mix(a._y, b._y),
      mix(a._z, b._z),
    );
  }

  /// Two alignments are equal when every component is, whatever their kinds:
  /// `Alignment3d.center == AlignmentDirectional3d.center`.
  @override
  bool operator ==(Object other) =>
      other is AlignmentGeometry3d &&
      other._x == _x &&
      other._start == _start &&
      other._y == _y &&
      other._z == _z;

  @override
  int get hashCode => Object.hash(_x, _start, _y, _z);

  @override
  String toString() {
    if (_start == 0.0) return 'Alignment3d($_x, $_y, $_z)';
    if (_x == 0.0) return 'AlignmentDirectional3d($_start, $_y, $_z)';
    return 'Alignment3d($_x, $_y, $_z) + AlignmentDirectional3d($_start, 0.0, '
        '0.0)';
  }
}

/// A point within a box, expressed as a fraction of the box's extents, the 3D
/// analogue of [Alignment].
///
/// Each component runs from `-1` at the low face to `+1` at the high face,
/// with `0` at the center: `x` is `-1` at the left, `y` is `-1` at the top,
/// and `z` is `-1` at the front (the face toward the viewer).
///
/// These are physical sides. An alignment that should follow the reading
/// direction is an [AlignmentDirectional3d].
class Alignment3d extends AlignmentGeometry3d {
  /// Creates an alignment from its three fractional components.
  const Alignment3d(this.x, this.y, this.z);

  /// The fraction along `x`: `-1` left, `+1` right.
  final double x;

  /// The fraction along `y`: `-1` top, `+1` bottom.
  final double y;

  /// The fraction along `z`: `-1` front, `+1` back.
  final double z;

  @override
  double get _x => x;
  @override
  double get _start => 0.0;
  @override
  double get _y => y;
  @override
  double get _z => z;

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

  /// Already physical, so the same alignment whatever [direction] is.
  @override
  Alignment3d resolve(TextDirection? direction) => this;

  /// A copy with the given components replaced.
  Alignment3d copyWith({double? x, double? y, double? z}) =>
      Alignment3d(x ?? this.x, y ?? this.y, z ?? this.z);

  Alignment3d operator +(Alignment3d other) =>
      Alignment3d(x + other.x, y + other.y, z + other.z);

  Alignment3d operator -(Alignment3d other) =>
      Alignment3d(x - other.x, y - other.y, z - other.z);

  Alignment3d operator -() => Alignment3d(-x, -y, -z);

  @override
  Alignment3d operator *(double scale) =>
      Alignment3d(x * scale, y * scale, z * scale);

  /// Linearly interpolates between two alignments.
  static Alignment3d lerp(Alignment3d a, Alignment3d b, double t) =>
      Alignment3d(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      );
}

/// A point within a box whose horizontal component follows the reading
/// direction, the 3D analogue of [AlignmentDirectional].
///
/// [start] is `-1` at the side the reading direction starts from — the left
/// in English, the right in Arabic — and `+1` at the other. [y] and [z] are
/// physical, as they are on [Alignment3d].
///
/// The direction belongs to the layout, not to whoever is looking at it: seen
/// from behind its plane, a box aligned to the start is still on the side it
/// was laid out on, the way a word printed on glass is.
class AlignmentDirectional3d extends AlignmentGeometry3d {
  /// Creates an alignment from its three fractional components.
  const AlignmentDirectional3d(this.start, this.y, this.z);

  /// The fraction along the reading direction: `-1` start, `+1` end.
  final double start;

  /// The fraction along `y`: `-1` top, `+1` bottom.
  final double y;

  /// The fraction along `z`: `-1` front, `+1` back.
  final double z;

  @override
  double get _x => 0.0;
  @override
  double get _start => start;
  @override
  double get _y => y;
  @override
  double get _z => z;

  /// The center of the box on every axis.
  static const AlignmentDirectional3d center = AlignmentDirectional3d(0, 0, 0);

  /// Center of the top edge on the start side, centered in depth.
  static const AlignmentDirectional3d topStart = AlignmentDirectional3d(
    -1,
    -1,
    0,
  );

  /// Center of the top face, centered in depth.
  static const AlignmentDirectional3d topCenter = AlignmentDirectional3d(
    0,
    -1,
    0,
  );

  /// Center of the top edge on the end side, centered in depth.
  static const AlignmentDirectional3d topEnd = AlignmentDirectional3d(1, -1, 0);

  /// Center of the start face, centered in depth.
  static const AlignmentDirectional3d centerStart = AlignmentDirectional3d(
    -1,
    0,
    0,
  );

  /// Center of the end face, centered in depth.
  static const AlignmentDirectional3d centerEnd = AlignmentDirectional3d(
    1,
    0,
    0,
  );

  /// Center of the bottom edge on the start side, centered in depth.
  static const AlignmentDirectional3d bottomStart = AlignmentDirectional3d(
    -1,
    1,
    0,
  );

  /// Center of the bottom face, centered in depth.
  static const AlignmentDirectional3d bottomCenter = AlignmentDirectional3d(
    0,
    1,
    0,
  );

  /// Center of the bottom edge on the end side, centered in depth.
  static const AlignmentDirectional3d bottomEnd = AlignmentDirectional3d(
    1,
    1,
    0,
  );

  /// The origin corner in reading order: start, top, front.
  static const AlignmentDirectional3d topStartFront = AlignmentDirectional3d(
    -1,
    -1,
    -1,
  );

  /// The far corner in reading order: end, bottom, back.
  static const AlignmentDirectional3d bottomEndBack = AlignmentDirectional3d(
    1,
    1,
    1,
  );

  @override
  Alignment3d resolve(TextDirection? direction) => switch (direction) {
    TextDirection.rtl => Alignment3d(-start, y, z),
    TextDirection.ltr || null => Alignment3d(start, y, z),
  };

  AlignmentDirectional3d operator +(AlignmentDirectional3d other) =>
      AlignmentDirectional3d(start + other.start, y + other.y, z + other.z);

  @override
  AlignmentDirectional3d operator *(double scale) =>
      AlignmentDirectional3d(start * scale, y * scale, z * scale);

  /// Linearly interpolates between two directional alignments.
  static AlignmentDirectional3d lerp(
    AlignmentDirectional3d a,
    AlignmentDirectional3d b,
    double t,
  ) => AlignmentDirectional3d(
    a.start + (b.start - a.start) * t,
    a.y + (b.y - a.y) * t,
    a.z + (b.z - a.z) * t,
  );
}

/// The sum of a physical and a directional alignment, kept apart until a
/// direction is known.
class _MixedAlignment3d extends AlignmentGeometry3d {
  const _MixedAlignment3d(this._x, this._start, this._y, this._z);

  @override
  final double _x;
  @override
  final double _start;
  @override
  final double _y;
  @override
  final double _z;

  @override
  _MixedAlignment3d operator *(double scale) =>
      _MixedAlignment3d(_x * scale, _start * scale, _y * scale, _z * scale);

  @override
  Alignment3d resolve(TextDirection? direction) => switch (direction) {
    TextDirection.rtl => Alignment3d(_x - _start, _y, _z),
    TextDirection.ltr || null => Alignment3d(_x + _start, _y, _z),
  };
}
