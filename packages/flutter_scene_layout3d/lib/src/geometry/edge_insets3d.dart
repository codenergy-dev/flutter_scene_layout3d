import 'dart:ui' show TextDirection;

import 'offset3d.dart';
import 'size3d.dart';

/// The base type of [EdgeInsets3d] and [EdgeInsetsDirectional3d], the 3D
/// analogue of [EdgeInsetsGeometry].
///
/// A box that insets its child takes one of these, so a caller can say
/// *left* or *start* as the design calls for, and the box turns it into a side
/// with [resolve] when it lays out, against the reading direction it was
/// given. Adding a physical inset to a directional one gives a third, private
/// kind that holds both until it is resolved.
///
/// **Depth has no direction.** Front is where the viewer is, whatever
/// language the text is in, so every kind has a physical `front` and `back`.
abstract class EdgeInsetsGeometry3d {
  /// Abstract const constructor, so the subclasses can be const.
  const EdgeInsetsGeometry3d();

  double get _left;
  double get _right;
  double get _start;
  double get _end;
  double get _top;
  double get _bottom;
  double get _front;
  double get _back;

  /// Whether every inset is zero or greater.
  bool get isNonNegative =>
      _left >= 0.0 &&
      _right >= 0.0 &&
      _start >= 0.0 &&
      _end >= 0.0 &&
      _top >= 0.0 &&
      _bottom >= 0.0 &&
      _front >= 0.0 &&
      _back >= 0.0;

  /// The total inset along `x`, which does not depend on the direction.
  double get horizontal => _left + _right + _start + _end;

  /// The total inset along `y`.
  double get vertical => _top + _bottom;

  /// The total inset along `z`.
  double get depth => _front + _back;

  /// The total inset along [axis], both faces together.
  double alongAxis(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => horizontal,
    Axis3d.vertical => vertical,
    Axis3d.depth => depth,
  };

  /// The size the insets consume on their own.
  Size3d get collapsedSize => Size3d(horizontal, vertical, depth);

  /// [size] shrunk by these insets, clamped at zero on every axis.
  Size3d deflateSize(Size3d size) => Size3d(
    (size.width - horizontal).clamp(0.0, double.infinity),
    (size.height - vertical).clamp(0.0, double.infinity),
    (size.depth - depth).clamp(0.0, double.infinity),
  );

  /// [size] grown by these insets.
  Size3d inflateSize(Size3d size) => Size3d(
    size.width + horizontal,
    size.height + vertical,
    size.depth + depth,
  );

  /// The sum of these insets and [other], whatever kind either is.
  ///
  /// Two of the same kind add to that kind; a physical and a directional one
  /// add to a kind that keeps both sides apart until [resolve].
  EdgeInsetsGeometry3d add(EdgeInsetsGeometry3d other) {
    final self = this;
    if (self is EdgeInsets3d && other is EdgeInsets3d) return self + other;
    if (self is EdgeInsetsDirectional3d && other is EdgeInsetsDirectional3d) {
      return self + other;
    }
    return _MixedEdgeInsets3d(
      _left + other._left,
      _right + other._right,
      _start + other._start,
      _end + other._end,
      _top + other._top,
      _bottom + other._bottom,
      _front + other._front,
      _back + other._back,
    );
  }

  /// Every inset scaled by [scale].
  EdgeInsetsGeometry3d operator *(double scale);

  /// The physical insets these stand for, read in [direction].
  ///
  /// A null direction reads left to right. Flutter asserts instead; a layout
  /// here has always been allowed to say nothing about direction, and a scene
  /// is not always under a `Directionality`, so the fallback is the one text
  /// already uses.
  EdgeInsets3d resolve(TextDirection? direction);

  /// Linearly interpolates between two insets of any kind.
  ///
  /// Null stands for no inset, as in Flutter.
  static EdgeInsetsGeometry3d? lerp(
    EdgeInsetsGeometry3d? a,
    EdgeInsetsGeometry3d? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null) return b! * t;
    if (b == null) return a * (1.0 - t);
    if (a is EdgeInsets3d && b is EdgeInsets3d) {
      return EdgeInsets3d.lerp(a, b, t);
    }
    if (a is EdgeInsetsDirectional3d && b is EdgeInsetsDirectional3d) {
      return EdgeInsetsDirectional3d.lerp(a, b, t);
    }
    double mix(double x, double y) => x + (y - x) * t;
    return _MixedEdgeInsets3d(
      mix(a._left, b._left),
      mix(a._right, b._right),
      mix(a._start, b._start),
      mix(a._end, b._end),
      mix(a._top, b._top),
      mix(a._bottom, b._bottom),
      mix(a._front, b._front),
      mix(a._back, b._back),
    );
  }

  /// Two insets are equal when every side is, whatever their kinds:
  /// `EdgeInsets3d.zero == EdgeInsetsDirectional3d.zero`.
  @override
  bool operator ==(Object other) =>
      other is EdgeInsetsGeometry3d &&
      other._left == _left &&
      other._right == _right &&
      other._start == _start &&
      other._end == _end &&
      other._top == _top &&
      other._bottom == _bottom &&
      other._front == _front &&
      other._back == _back;

  @override
  int get hashCode =>
      Object.hash(_left, _right, _start, _end, _top, _bottom, _front, _back);

  @override
  String toString() {
    if (_start == 0.0 && _end == 0.0) {
      return 'EdgeInsets3d($_left, $_top, $_right, $_bottom, $_front, $_back)';
    }
    if (_left == 0.0 && _right == 0.0) {
      return 'EdgeInsetsDirectional3d($_start, $_top, $_end, $_bottom, '
          '$_front, $_back)';
    }
    return 'EdgeInsets3d($_left, $_top, $_right, $_bottom, $_front, $_back) + '
        'EdgeInsetsDirectional3d($_start, 0.0, $_end, 0.0, 0.0, 0.0)';
  }
}

/// An immutable set of offsets on the six faces of a box, the 3D analogue of
/// [EdgeInsets].
///
/// The face names follow layout space: [top] is toward `-y`, [bottom] toward
/// `+y`, [front] toward `-z` (toward the viewer) and [back] toward `+z`.
///
/// These are physical sides. A padding that should follow the reading
/// direction — 16dp before a list tile's leading icon, whichever side that is
/// on — is an [EdgeInsetsDirectional3d].
class EdgeInsets3d extends EdgeInsetsGeometry3d {
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

  @override
  double get _left => left;
  @override
  double get _right => right;
  @override
  double get _start => 0.0;
  @override
  double get _end => 0.0;
  @override
  double get _top => top;
  @override
  double get _bottom => bottom;
  @override
  double get _front => front;
  @override
  double get _back => back;

  /// The total inset along `z`.
  @Deprecated(
    'Use depth, which matches horizontal and vertical and the depth argument '
    'of EdgeInsets3d.symmetric. This alias will be removed in a future '
    'release.',
  )
  double get alongDepth => depth;

  /// The inset on the face [axis] starts at, the one nearest the origin
  /// corner.
  double lowAlong(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => left,
    Axis3d.vertical => top,
    Axis3d.depth => front,
  };

  /// The offset of the inset box's origin corner.
  Offset3d get topLeftFront => Offset3d(left, top, front);

  /// Already physical, so the same insets whatever [direction] is.
  @override
  EdgeInsets3d resolve(TextDirection? direction) => this;

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

  @override
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
}

/// Insets whose horizontal sides follow the reading direction, the 3D analogue
/// of [EdgeInsetsDirectional].
///
/// [start] is the left in a left-to-right language and the right in a
/// right-to-left one; [end] is the other side. Top, bottom, front and back
/// are physical, as they are on [EdgeInsets3d].
///
/// The direction is a property of the layout, not of whoever is looking: a
/// row seen from behind its plane still has its start on the side it was laid
/// out on, the way a sign printed on glass does.
class EdgeInsetsDirectional3d extends EdgeInsetsGeometry3d {
  /// Creates insets from the given faces.
  const EdgeInsetsDirectional3d.only({
    this.start = 0.0,
    this.top = 0.0,
    this.end = 0.0,
    this.bottom = 0.0,
    this.front = 0.0,
    this.back = 0.0,
  });

  /// Insets in start, top, end, bottom, front, back order.
  const EdgeInsetsDirectional3d.fromSTEBFB(
    this.start,
    this.top,
    this.end,
    this.bottom,
    this.front,
    this.back,
  );

  /// The same inset on every face.
  const EdgeInsetsDirectional3d.all(double value)
    : start = value,
      top = value,
      end = value,
      bottom = value,
      front = value,
      back = value;

  /// Inset from the face the reading direction starts at.
  final double start;

  /// Inset from the top face (`-y`).
  final double top;

  /// Inset from the face the reading direction ends at.
  final double end;

  /// Inset from the bottom face (`+y`).
  final double bottom;

  /// Inset from the front face (`-z`, toward the viewer).
  final double front;

  /// Inset from the back face (`+z`, away from the viewer).
  final double back;

  /// No inset on any face.
  static const EdgeInsetsDirectional3d zero = EdgeInsetsDirectional3d.all(0);

  @override
  double get _left => 0.0;
  @override
  double get _right => 0.0;
  @override
  double get _start => start;
  @override
  double get _end => end;
  @override
  double get _top => top;
  @override
  double get _bottom => bottom;
  @override
  double get _front => front;
  @override
  double get _back => back;

  @override
  EdgeInsets3d resolve(TextDirection? direction) => switch (direction) {
    TextDirection.rtl => EdgeInsets3d.fromLTRBFB(
      end,
      top,
      start,
      bottom,
      front,
      back,
    ),
    TextDirection.ltr ||
    null => EdgeInsets3d.fromLTRBFB(start, top, end, bottom, front, back),
  };

  /// A copy with the given faces replaced.
  EdgeInsetsDirectional3d copyWith({
    double? start,
    double? top,
    double? end,
    double? bottom,
    double? front,
    double? back,
  }) => EdgeInsetsDirectional3d.fromSTEBFB(
    start ?? this.start,
    top ?? this.top,
    end ?? this.end,
    bottom ?? this.bottom,
    front ?? this.front,
    back ?? this.back,
  );

  EdgeInsetsDirectional3d operator +(EdgeInsetsDirectional3d other) =>
      EdgeInsetsDirectional3d.fromSTEBFB(
        start + other.start,
        top + other.top,
        end + other.end,
        bottom + other.bottom,
        front + other.front,
        back + other.back,
      );

  @override
  EdgeInsetsDirectional3d operator *(double scale) =>
      EdgeInsetsDirectional3d.fromSTEBFB(
        start * scale,
        top * scale,
        end * scale,
        bottom * scale,
        front * scale,
        back * scale,
      );

  /// Linearly interpolates between two sets of directional insets.
  static EdgeInsetsDirectional3d lerp(
    EdgeInsetsDirectional3d a,
    EdgeInsetsDirectional3d b,
    double t,
  ) => EdgeInsetsDirectional3d.fromSTEBFB(
    a.start + (b.start - a.start) * t,
    a.top + (b.top - a.top) * t,
    a.end + (b.end - a.end) * t,
    a.bottom + (b.bottom - a.bottom) * t,
    a.front + (b.front - a.front) * t,
    a.back + (b.back - a.back) * t,
  );
}

/// The sum of a physical and a directional inset, kept apart until a
/// direction is known.
class _MixedEdgeInsets3d extends EdgeInsetsGeometry3d {
  const _MixedEdgeInsets3d(
    this._left,
    this._right,
    this._start,
    this._end,
    this._top,
    this._bottom,
    this._front,
    this._back,
  );

  @override
  final double _left;
  @override
  final double _right;
  @override
  final double _start;
  @override
  final double _end;
  @override
  final double _top;
  @override
  final double _bottom;
  @override
  final double _front;
  @override
  final double _back;

  @override
  _MixedEdgeInsets3d operator *(double scale) => _MixedEdgeInsets3d(
    _left * scale,
    _right * scale,
    _start * scale,
    _end * scale,
    _top * scale,
    _bottom * scale,
    _front * scale,
    _back * scale,
  );

  @override
  EdgeInsets3d resolve(TextDirection? direction) => switch (direction) {
    TextDirection.rtl => EdgeInsets3d.fromLTRBFB(
      _end + _left,
      _top,
      _start + _right,
      _bottom,
      _front,
      _back,
    ),
    TextDirection.ltr || null => EdgeInsets3d.fromLTRBFB(
      _start + _left,
      _top,
      _end + _right,
      _bottom,
      _front,
      _back,
    ),
  };
}
