import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// A box that holds two of its axes in a fixed ratio, the 3D analogue of
/// [AspectRatio].
///
/// ## A ratio between which axes
///
/// "Aspect ratio" names two extents, and a box here has three, so the ratio
/// has to say which two it is about. There were three plausible answers: a
/// pair of axes plus a number, a whole [Size3d] the box is scaled to fit, or
/// the plane's width : height with depth left alone. This class takes the
/// first, with the third as its default, for two reasons.
///
/// A whole-`Size3d` ratio is a different operation wearing this name: it is
/// "make this subtree that shape and scale it into the room", which is
/// [FittedBox3d] for a laid-out subtree and `NodeBox3d.fit` for engine
/// content. Neither of those constrains the child; this one does, which is
/// the whole point of an aspect ratio in a layout protocol — the child is
/// *told* it is 16 : 9 and lays itself out accordingly.
///
/// And a caller who writes `AspectRatio3d(aspectRatio: 16 / 9)` means the
/// plane. That is the 2D habit and it is the right default here: a surface is
/// a thing you look at, so its long axes are width and height, and depth is
/// the thickness of the panel rather than a term in its shape. So the ratio
/// is [axis] : [relativeTo], defaulting to horizontal : vertical, and the
/// third axis is passed through untouched — the child gets the depth
/// constraints this box was given, and this box reports the depth the child
/// chose.
///
/// State the axes to get any other pairing:
///
/// ```dart
/// // A slab twice as wide as it is thick, with its height free.
/// AspectRatio3d(
///   aspectRatio: 2,
///   relativeTo: Axis3d.depth,
///   child: panel,
/// )
/// ```
///
/// ## Sizing
///
/// The algorithm is Flutter's, per axis: take the largest [axis] extent
/// allowed, derive the [relativeTo] extent from the ratio, and walk the
/// result back inside the constraints if it landed outside them. An [axis]
/// with no upper bound is derived from [relativeTo] instead; with neither
/// bounded there is nothing to be a ratio of, and the box says so.
class AspectRatio3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a box with a fixed ratio between [axis] and [relativeTo].
  AspectRatio3d({
    required double aspectRatio,
    Axis3d axis = Axis3d.horizontal,
    Axis3d relativeTo = Axis3d.vertical,
    super.child,
    super.name,
  }) : _aspectRatio = aspectRatio,
       _axis = axis,
       _relativeTo = relativeTo,
       assert(aspectRatio > 0.0 && aspectRatio.isFinite),
       assert(axis != relativeTo, 'A ratio is between two different axes.');

  double _aspectRatio;

  /// The extent along [axis] divided by the extent along [relativeTo].
  double get aspectRatio => _aspectRatio;

  set aspectRatio(double value) {
    if (_aspectRatio == value) return;
    assert(value > 0.0 && value.isFinite);
    _aspectRatio = value;
    markNeedsLayout();
  }

  Axis3d _axis;

  /// The numerator of the ratio.
  Axis3d get axis => _axis;

  set axis(Axis3d value) {
    if (_axis == value) return;
    assert(value != _relativeTo);
    _axis = value;
    markNeedsLayout();
  }

  Axis3d _relativeTo;

  /// The denominator of the ratio.
  Axis3d get relativeTo => _relativeTo;

  set relativeTo(Axis3d value) {
    if (_relativeTo == value) return;
    assert(value != _axis);
    _relativeTo = value;
    markNeedsLayout();
  }

  /// The axis the ratio says nothing about, which is left to the child.
  Axis3d get freeAxis {
    for (final candidate in Axis3d.values) {
      if (candidate != _axis && candidate != _relativeTo) return candidate;
    }
    throw StateError('Every axis is spoken for.');
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _intrinsic(axis, limits, min: true);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _intrinsic(axis, limits, min: false);

  /// The ratio applied to the limit on the other axis, when there is one.
  ///
  /// This is the whole value of an aspect ratio to an intrinsic query: asked
  /// how wide it wants to be in a space 9 tall, a 16 : 9 box answers 16
  /// without asking the child anything at all.
  double _intrinsic(Axis3d queried, Size3d limits, {required bool min}) {
    if (queried == _axis) {
      final other = limits.alongAxis(_relativeTo);
      if (other.isFinite) return other * _aspectRatio;
    } else if (queried == _relativeTo) {
      final other = limits.alongAxis(_axis);
      if (other.isFinite) return other / _aspectRatio;
    }
    final child = this.child;
    if (child == null) return 0.0;
    return min
        ? child.getMinIntrinsicExtent(queried, limits)
        : child.getMaxIntrinsicExtent(queried, limits);
  }

  /// The pair of extents satisfying both the ratio and [constraints], as far
  /// as the two can be satisfied together.
  (double, double) _applyRatio(Constraints3d constraints) {
    final main = _axis;
    final cross = _relativeTo;
    if (constraints.hasTightAlong(main) && constraints.hasTightAlong(cross)) {
      return (constraints.minAlong(main), constraints.minAlong(cross));
    }

    var mainExtent = constraints.maxAlong(main);
    double crossExtent;
    if (mainExtent.isFinite) {
      crossExtent = mainExtent / _aspectRatio;
    } else {
      crossExtent = constraints.maxAlong(cross);
      assert(
        crossExtent.isFinite,
        'AspectRatio3d was given no upper bound on either $main or $cross, so '
        'there is no extent for the ratio to be a ratio of. Bound one of them '
        '— a SizedBox3d around this box, an Expanded3d in a flex, or a sized '
        'surface — or drop the aspect ratio.',
      );
      if (!crossExtent.isFinite) return (0.0, 0.0);
      mainExtent = crossExtent * _aspectRatio;
    }

    // Walk back inside the constraints, following the ratio each time, the
    // way Flutter's RenderAspectRatio does: the last clamp wins, and the
    // final constrain() is what keeps the answer legal when the constraints
    // and the ratio genuinely cannot both hold.
    if (mainExtent > constraints.maxAlong(main)) {
      mainExtent = constraints.maxAlong(main);
      crossExtent = mainExtent / _aspectRatio;
    }
    if (crossExtent > constraints.maxAlong(cross)) {
      crossExtent = constraints.maxAlong(cross);
      mainExtent = crossExtent * _aspectRatio;
    }
    if (mainExtent < constraints.minAlong(main)) {
      mainExtent = constraints.minAlong(main);
      crossExtent = mainExtent / _aspectRatio;
    }
    if (crossExtent < constraints.minAlong(cross)) {
      crossExtent = constraints.minAlong(cross);
      mainExtent = crossExtent * _aspectRatio;
    }
    return (
      constraints.constrainAlong(main, mainExtent),
      constraints.constrainAlong(cross, crossExtent),
    );
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    final (mainExtent, crossExtent) = _applyRatio(constraints);
    final free = freeAxis;
    var childConstraints = constraints
        .withAxis(_axis, min: mainExtent, max: mainExtent)
        .withAxis(_relativeTo, min: crossExtent, max: crossExtent);
    childConstraints = childConstraints.withAxis(
      free,
      min: 0.0,
      max: constraints.maxAlong(free),
    );

    final child = this.child;
    var freeExtent = constraints.minAlong(free);
    if (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      freeExtent = child.size.alongAxis(free);
    }

    size = Size3d.zero
        .withAxis(_axis, mainExtent)
        .withAxis(_relativeTo, crossExtent)
        .withAxis(free, constraints.constrainAlong(free, freeExtent));
    child?.place(Offset3d.zero);
  }
}
