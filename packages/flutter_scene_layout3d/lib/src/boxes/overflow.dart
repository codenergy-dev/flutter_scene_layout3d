import 'dart:math' as math;

import '../geometry/alignment3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// A box that caps an axis only when nothing else has, the 3D analogue of
/// [LimitedBox].
///
/// It is worth more here than in Flutter. A `Layout3dSurface` is unbounded on
/// all three axes unless it is given a size, and a `Viewport3d` hands its
/// child unbounded room along the scroll axis, so "no upper bound" is the
/// ordinary case rather than the error case. A box that would fill whatever
/// it is offered — an [Align3d], a [Stack3d] with a positioned child — has
/// nothing to fill when the offer is infinite; this states the fallback it
/// should use, and states it *only* for that case:
///
/// ```dart
/// LimitedBox3d(maxHeight: 2, child: Column3d(children: rows))
/// ```
///
/// A limit on an axis the parent already bounded is ignored outright, which
/// is what separates this from a [ConstrainedBox3d]. Use that one to impose a
/// cap that always applies.
class LimitedBox3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a box that limits its child's unbounded axes.
  LimitedBox3d({
    double maxWidth = double.infinity,
    double maxHeight = double.infinity,
    double maxDepth = double.infinity,
    super.child,
    super.name,
  }) : _maxWidth = maxWidth,
       _maxHeight = maxHeight,
       _maxDepth = maxDepth,
       assert(maxWidth >= 0.0),
       assert(maxHeight >= 0.0),
       assert(maxDepth >= 0.0);

  double _maxWidth;

  /// The width to use when the incoming width is unbounded.
  double get maxWidth => _maxWidth;

  set maxWidth(double value) {
    if (_maxWidth == value) return;
    assert(value >= 0.0);
    _maxWidth = value;
    markNeedsLayout();
  }

  double _maxHeight;

  /// The height to use when the incoming height is unbounded.
  double get maxHeight => _maxHeight;

  set maxHeight(double value) {
    if (_maxHeight == value) return;
    assert(value >= 0.0);
    _maxHeight = value;
    markNeedsLayout();
  }

  double _maxDepth;

  /// The depth to use when the incoming depth is unbounded.
  double get maxDepth => _maxDepth;

  set maxDepth(double value) {
    if (_maxDepth == value) return;
    assert(value >= 0.0);
    _maxDepth = value;
    markNeedsLayout();
  }

  /// The limit on [axis].
  double limitAlong(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => _maxWidth,
    Axis3d.vertical => _maxHeight,
    Axis3d.depth => _maxDepth,
  };

  Constraints3d _limit(Constraints3d constraints) {
    var result = constraints;
    for (final axis in Axis3d.values) {
      if (constraints.hasBoundedAlong(axis)) continue;
      result = result.withAxis(
        axis,
        max: math.max(constraints.minAlong(axis), limitAlong(axis)),
      );
    }
    return result;
  }

  /// The child's intrinsic extent, held to the limit on that axis.
  ///
  /// An intrinsic query is the unbounded case by definition — it asks how big
  /// the child would be with nothing stopping it — so the limit applies to
  /// every one of them, unlike in [performLayout] where it applies only to
  /// the axes the parent left open.
  double _limitedIntrinsic(Axis3d axis, Size3d limits, {required bool min}) {
    final child = this.child;
    if (child == null) return 0.0;
    final extent = min
        ? child.getMinIntrinsicExtent(axis, limits)
        : child.getMaxIntrinsicExtent(axis, limits);
    return math.min(extent, limitAlong(axis));
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _limitedIntrinsic(axis, limits, min: true);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _limitedIntrinsic(axis, limits, min: false);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = _limit(constraints).smallest;
      return;
    }
    child.layout(_limit(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
    child.place(Offset3d.zero);
  }
}

/// A box that hands its child more room than it was given itself, the 3D
/// analogue of [UnconstrainedBox].
///
/// The child is laid out with the chosen axes freed — no minimum, no maximum
/// — and then aligned inside the space this box actually gets, which is the
/// space its own parent allowed. A child bigger than that overflows: its
/// geometry sticks out of the box, and, because nothing here paints into a
/// rectangle, that is a thing the viewer simply sees rather than an error.
/// Wrap the result in a [ClipBox3d] to cut it off.
///
/// The usual reason to reach for it is measurement: a child laid out under
/// unbounded constraints reports the size it *wants*, which is what an
/// intrinsic query would tell you without paying for the extra pass.
///
/// [constrainedAxes] names the axes to leave alone. Freeing the plane while
/// keeping depth bounded — `constrainedAxes: {Axis3d.depth}` — is the common
/// case here: a panel may overflow across the surface without poking through
/// it.
class UnconstrainedBox3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a box that frees its child's constraints.
  UnconstrainedBox3d({
    Alignment3d alignment = Alignment3d.center,
    Set<Axis3d> constrainedAxes = const <Axis3d>{},
    super.child,
    super.name,
  }) : _alignment = alignment,
       _constrainedAxes = Set<Axis3d>.unmodifiable(constrainedAxes);

  Alignment3d _alignment;

  /// Where the child sits inside the room this box was given.
  Alignment3d get alignment => _alignment;

  set alignment(Alignment3d value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  Set<Axis3d> _constrainedAxes;

  /// The axes that keep the constraints this box was given.
  ///
  /// Everything not in here is handed down unbounded.
  Set<Axis3d> get constrainedAxes => _constrainedAxes;

  set constrainedAxes(Set<Axis3d> value) {
    if (_setEquals(_constrainedAxes, value)) return;
    _constrainedAxes = Set<Axis3d>.unmodifiable(value);
    markNeedsLayout();
  }

  static bool _setEquals(Set<Axis3d> a, Set<Axis3d> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    var childConstraints = const Constraints3d();
    for (final axis in _constrainedAxes) {
      childConstraints = childConstraints.withAxis(
        axis,
        min: constraints.minAlong(axis),
        max: constraints.maxAlong(axis),
      );
    }
    child.layout(childConstraints, parentUsesSize: true);
    size = constraints.constrain(child.size);
    child.place(_alignment.inscribe(child.size, size));
  }
}

/// A box that imposes constraints of its own and lets the child spill out of
/// the size it reports, the 3D analogue of [OverflowBox].
///
/// The difference from a [ConstrainedBox3d] is which side wins. A constrained
/// box combines what it wants with what it was given and reports the child's
/// size, so the parent's limits are never broken; this one *replaces* the
/// bounds it names outright, sizes itself to the room its parent offered, and
/// aligns the child inside — which is how a child comes to be bigger than the
/// box it is in.
///
/// The size it reports is the room offered on every axis the parent bounded.
/// On an unbounded axis there is no such room to report, so it shrink-wraps
/// the child there instead; that is the same choice [Align3d] makes, and it
/// keeps an infinite extent from ever reaching the scene.
///
/// ```dart
/// // A ripple that spreads past the button it belongs to.
/// OverflowBox3d(maxWidth: 4, maxHeight: 4, child: ripple)
/// ```
class OverflowBox3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a box that overrides the bounds given, per axis.
  OverflowBox3d({
    double? minWidth,
    double? maxWidth,
    double? minHeight,
    double? maxHeight,
    double? minDepth,
    double? maxDepth,
    Alignment3d alignment = Alignment3d.center,
    super.child,
    super.name,
  }) : _minWidth = minWidth,
       _maxWidth = maxWidth,
       _minHeight = minHeight,
       _maxHeight = maxHeight,
       _minDepth = minDepth,
       _maxDepth = maxDepth,
       _alignment = alignment;

  double? _minWidth;

  /// The minimum width handed down, or null to keep the incoming one.
  double? get minWidth => _minWidth;

  set minWidth(double? value) {
    if (_minWidth == value) return;
    _minWidth = value;
    markNeedsLayout();
  }

  double? _maxWidth;

  /// The maximum width handed down, or null to keep the incoming one.
  double? get maxWidth => _maxWidth;

  set maxWidth(double? value) {
    if (_maxWidth == value) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  double? _minHeight;

  /// The minimum height handed down, or null to keep the incoming one.
  double? get minHeight => _minHeight;

  set minHeight(double? value) {
    if (_minHeight == value) return;
    _minHeight = value;
    markNeedsLayout();
  }

  double? _maxHeight;

  /// The maximum height handed down, or null to keep the incoming one.
  double? get maxHeight => _maxHeight;

  set maxHeight(double? value) {
    if (_maxHeight == value) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  double? _minDepth;

  /// The minimum depth handed down, or null to keep the incoming one.
  double? get minDepth => _minDepth;

  set minDepth(double? value) {
    if (_minDepth == value) return;
    _minDepth = value;
    markNeedsLayout();
  }

  double? _maxDepth;

  /// The maximum depth handed down, or null to keep the incoming one.
  double? get maxDepth => _maxDepth;

  set maxDepth(double? value) {
    if (_maxDepth == value) return;
    _maxDepth = value;
    markNeedsLayout();
  }

  Alignment3d _alignment;

  /// Where the child sits inside the room this box reports.
  Alignment3d get alignment => _alignment;

  set alignment(Alignment3d value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  /// The constraints handed to the child: the incoming ones with every bound
  /// this box states replaced.
  Constraints3d childConstraints(Constraints3d constraints) => Constraints3d(
    minWidth: _minWidth ?? constraints.minWidth,
    maxWidth: _maxWidth ?? constraints.maxWidth,
    minHeight: _minHeight ?? constraints.minHeight,
    maxHeight: _maxHeight ?? constraints.maxHeight,
    minDepth: _minDepth ?? constraints.minDepth,
    maxDepth: _maxDepth ?? constraints.maxDepth,
  ).normalize();

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(childConstraints(constraints), parentUsesSize: true);
    // Bounded axes take the room offered, whether or not the child filled it;
    // unbounded ones have no room to take and follow the child.
    var chosen = Size3d.zero;
    for (final axis in Axis3d.values) {
      chosen = chosen.withAxis(
        axis,
        constraints.hasBoundedAlong(axis)
            ? constraints.maxAlong(axis)
            : constraints.constrainAlong(axis, child.size.alongAxis(axis)),
      );
    }
    size = chosen;
    child.place(_alignment.inscribe(child.size, size));
  }
}

/// A box that sizes its child to a fraction of the room it was given, the 3D
/// analogue of [FractionallySizedBox].
///
/// Each axis is independent, and an axis with no factor is left loose, so
/// `FractionallySizedBox3d(widthFactor: 0.5)` is "half as wide as the space,
/// as tall and deep as the child wants". A factor above one makes the child
/// larger than the box, which overflows exactly as an [OverflowBox3d] does.
///
/// A factor needs a finite extent to be a fraction *of*, and an unbounded axis
/// is the normal case on a surface, so an axis that has no upper bound is
/// left to the child and says so in debug mode. Give the box bounded room —
/// a `SizedBox3d` around it, or a surface with a size — rather than expecting
/// a fraction of infinity.
class FractionallySizedBox3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a box sizing its child to a fraction of its own room.
  FractionallySizedBox3d({
    double? widthFactor,
    double? heightFactor,
    double? depthFactor,
    Alignment3d alignment = Alignment3d.center,
    super.child,
    super.name,
  }) : _widthFactor = widthFactor,
       _heightFactor = heightFactor,
       _depthFactor = depthFactor,
       _alignment = alignment,
       assert(widthFactor == null || widthFactor >= 0.0),
       assert(heightFactor == null || heightFactor >= 0.0),
       assert(depthFactor == null || depthFactor >= 0.0);

  double? _widthFactor;

  /// The fraction of the available width the child is given.
  double? get widthFactor => _widthFactor;

  set widthFactor(double? value) {
    if (_widthFactor == value) return;
    assert(value == null || value >= 0.0);
    _widthFactor = value;
    markNeedsLayout();
  }

  double? _heightFactor;

  /// The fraction of the available height the child is given.
  double? get heightFactor => _heightFactor;

  set heightFactor(double? value) {
    if (_heightFactor == value) return;
    assert(value == null || value >= 0.0);
    _heightFactor = value;
    markNeedsLayout();
  }

  double? _depthFactor;

  /// The fraction of the available depth the child is given.
  double? get depthFactor => _depthFactor;

  set depthFactor(double? value) {
    if (_depthFactor == value) return;
    assert(value == null || value >= 0.0);
    _depthFactor = value;
    markNeedsLayout();
  }

  Alignment3d _alignment;

  /// Where the child sits inside this box.
  Alignment3d get alignment => _alignment;

  set alignment(Alignment3d value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  /// The factor on [axis], or null when that axis has none.
  double? factorAlong(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => _widthFactor,
    Axis3d.vertical => _heightFactor,
    Axis3d.depth => _depthFactor,
  };

  @override
  void performLayout() {
    final constraints = this.constraints;
    var childConstraints = constraints.loosen();
    for (final axis in Axis3d.values) {
      final factor = factorAlong(axis);
      if (factor == null) continue;
      assert(
        constraints.hasBoundedAlong(axis),
        'FractionallySizedBox3d was given a factor for $axis but no upper '
        'bound on it, and a fraction of an unbounded extent is not a length. '
        'Bound the axis — a SizedBox3d around this one, or a sized surface — '
        'or drop the factor and let the child choose.',
      );
      if (!constraints.hasBoundedAlong(axis)) continue;
      final extent = constraints.maxAlong(axis) * factor;
      childConstraints = childConstraints.withAxis(
        axis,
        min: extent,
        max: extent,
      );
    }

    final child = this.child;
    if (child == null) {
      // Nothing to wrap, so the box is as small as it is allowed to be —
      // the same answer Align3d gives with no child on a shrink-wrapped axis.
      size = constraints.smallest;
      return;
    }
    child.layout(childConstraints, parentUsesSize: true);
    // Like Align3d: fill a bounded axis, shrink-wrap an unbounded one.
    var chosen = Size3d.zero;
    for (final axis in Axis3d.values) {
      chosen = chosen.withAxis(
        axis,
        constraints.hasBoundedAlong(axis)
            ? constraints.maxAlong(axis)
            : constraints.constrainAlong(axis, child.size.alongAxis(axis)),
      );
    }
    size = chosen;
    child.place(_alignment.inscribe(child.size, size));
  }
}
