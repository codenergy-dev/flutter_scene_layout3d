import 'package:vector_math/vector_math.dart' show Matrix4;

import 'geometry/offset3d.dart';
import 'geometry/size3d.dart';
import 'layout3d.dart';

/// A ray through layout space, what a 3D hit test walks with.
///
/// Flutter hit-tests with a point, because a screen is flat and "where the
/// finger is" needs two numbers. In a scene the pointer is a direction from
/// the camera, and the boxes it passes through stand at different depths, so
/// the thing that descends the tree is a ray.
///
/// [origin] and [direction] are layout-space quantities (`x` right, `y`
/// down, `z` away from the viewer); [direction] need not be normalized.
/// [tMin] and [tMax] bound the useful stretch of the ray, and this is what
/// makes a box contain its children the way Flutter's `size.contains` does:
/// as the walk enters a box it clips the range to the part of the ray inside
/// that box, so a child scrolled out of a list or a model overflowing a panel
/// is not reachable through it.
///
/// Because a transform maps `at(t)` to `at(t)`, `t` means the same thing at
/// every level of the tree, whatever transforms sit between.
class Ray3d {
  /// Creates a ray from [origin] along [direction], over `[tMin, tMax]`.
  const Ray3d(
    this.origin,
    this.direction, {
    this.tMin = 0.0,
    this.tMax = double.infinity,
  });

  /// A line straight through [point], running along [axis].
  ///
  /// The 2D-style hit test: "what is at this spot on the plane", regardless
  /// of depth. Unlike a camera ray this extends both ways, so content in
  /// front of [point] is found too.
  factory Ray3d.through(Offset3d point, {Axis3d axis = Axis3d.depth}) =>
      Ray3d(point, Offset3d.along(axis, 1.0), tMin: double.negativeInfinity);

  /// Where the ray starts, in layout space.
  final Offset3d origin;

  /// Which way the ray runs, in layout space. Not necessarily unit length.
  final Offset3d direction;

  /// The smallest [at] parameter considered part of the ray.
  final double tMin;

  /// The largest [at] parameter considered part of the ray.
  final double tMax;

  /// The point at parameter [t].
  Offset3d at(double t) => origin + direction * t;

  /// This ray in the space of a child placed at [offset].
  Ray3d shifted(Offset3d offset) =>
      Ray3d(origin - offset, direction, tMin: tMin, tMax: tMax);

  /// This ray mapped through [matrix], which must be the *inverse* of the
  /// transform that takes the target space to this one.
  ///
  /// The range is carried over untouched: a point at parameter `t` maps to
  /// the point at parameter `t`, even under a non-uniform scale.
  Ray3d transformed(Matrix4 matrix) {
    final movedOrigin = matrix.transformed3(origin.toVector3());
    final movedDirection = matrix.rotated3(direction.toVector3());
    return Ray3d(
      Offset3d(movedOrigin.x, movedOrigin.y, movedOrigin.z),
      Offset3d(movedDirection.x, movedDirection.y, movedDirection.z),
      tMin: tMin,
      tMax: tMax,
    );
  }

  /// This ray restricted to `[near, far]`, never widening the range it
  /// already has.
  Ray3d clampedTo(double near, double far) => Ray3d(
    origin,
    direction,
    tMin: near > tMin ? near : tMin,
    tMax: far < tMax ? far : tMax,
  );

  /// The stretch of this ray inside the box spanning [Offset3d.zero] to
  /// [size], or null when it misses.
  ///
  /// Both faces of each slab count as inside, so a box with no extent on an
  /// axis (a flat panel with zero depth, a spacer) is still reachable.
  ({double near, double far})? intersectBox(Size3d size) {
    var near = tMin;
    var far = tMax;
    for (final axis in Axis3d.values) {
      final start = origin.alongAxis(axis);
      final along = direction.alongAxis(axis);
      final extent = size.alongAxis(axis);
      if (along == 0.0) {
        // Parallel to this pair of faces: inside them, or nowhere.
        if (start < -_tolerance || start > extent + _tolerance) return null;
        continue;
      }
      var enter = (0.0 - start) / along;
      var exit = (extent - start) / along;
      if (enter > exit) {
        final swap = enter;
        enter = exit;
        exit = swap;
      }
      if (enter > near) near = enter;
      if (exit < far) far = exit;
      if (near > far) return null;
    }
    return (near: near, far: far);
  }

  static const double _tolerance = 1e-9;

  @override
  String toString() => 'Ray3d($origin -> $direction, t=$tMin..$tMax)';
}

/// One layout the ray passed through, and where it entered.
class HitTestEntry3d {
  /// Records that [ray] entered [layout] at [localPosition].
  const HitTestEntry3d(this.layout, this.localPosition);

  /// The layout that was hit.
  final Layout3d layout;

  /// Where the ray entered, in [layout]'s own space.
  ///
  /// The origin corner of the box is `(0, 0, 0)`, so this reads the same way
  /// a Flutter `BoxHitTestEntry`'s local position does.
  final Offset3d localPosition;

  @override
  String toString() => '${layout.runtimeType} at $localPosition';
}

/// The layouts a ray hit, deepest first.
///
/// The 3D analogue of [BoxHitTestResult]: [target] is the box that answered
/// the hit, and [path] continues out through its ancestors to the surface,
/// which is what lets a caller ask "was this inside a list?" and find the
/// list even though the finger landed on an item.
class HitTestResult3d {
  /// Creates an empty result, ready to be filled by a hit test.
  HitTestResult3d();

  final List<HitTestEntry3d> _path = <HitTestEntry3d>[];

  /// The layouts hit, from the deepest one out to the surface.
  List<HitTestEntry3d> get path => List<HitTestEntry3d>.unmodifiable(_path);

  /// Whether the ray hit nothing.
  bool get isEmpty => _path.isEmpty;

  /// Whether the ray hit anything.
  bool get isNotEmpty => _path.isNotEmpty;

  /// The deepest layout hit, or null.
  Layout3d? get target => _path.isEmpty ? null : _path.first.layout;

  /// The entry for the deepest layout hit, or null.
  HitTestEntry3d? get targetEntry => _path.isEmpty ? null : _path.first;

  /// Records that a layout was hit. Called by [Layout3d.hitTest] on the way
  /// back up, so the deepest box lands first.
  void add(HitTestEntry3d entry) => _path.add(entry);

  /// The entry for the deepest layout that is a [T], or null.
  ///
  /// How a caller finds the scrollable under the finger:
  /// `result.entryOf<Scrollable3d>()`.
  HitTestEntry3d? entryOf<T extends Object>() {
    for (final entry in _path) {
      if (entry.layout is T) return entry;
    }
    return null;
  }

  /// The deepest layout that is a [T], or null.
  T? firstOf<T extends Object>() => entryOf<T>()?.layout as T?;

  @override
  String toString() =>
      _path.isEmpty ? 'HitTestResult3d(miss)' : 'HitTestResult3d($_path)';
}
