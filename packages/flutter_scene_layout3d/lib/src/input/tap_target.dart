import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty;

import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';

/// Guarantees the pointer a minimum area to aim at, without changing what
/// layout measured.
///
/// Material's rule is that anything you can press is at least 48dp across,
/// however small the thing drawn inside it: a 24dp icon in a dense toolbar is
/// still a 48dp target. Flutter spends layout on that — its `_InputPadding`
/// grows the box — which pushes the neighbours apart and is exactly what a
/// dense toolbar was trying to avoid.
///
/// This does it in the hit test instead. The box is its child's size, sits
/// where layout put it, and takes no more room; it simply answers a ray that
/// passes within half the shortfall of its extent. So the icons stay 24dp
/// apart and the targets overlap, which is the right trade: a ray can only be
/// in one place, and the nearest target wins by being tested first.
///
/// ```dart
/// TapTarget3d(                       // 48dp of reach in every direction
///   child: GestureDetector3d(
///     onTap: _mute,
///     child: Icon3d(size: metrics.dp(24)),
///   ),
/// )
/// ```
///
/// The extra reach is on the width and height axes only. Depth is left alone:
/// a ray from the camera crosses a panel's face whatever its thickness, and
/// growing the depth would put the target in front of whatever is meant to be
/// stacked on it.
class TapTarget3d extends ProxyLayout3d {
  /// Creates a target at least [minimumSize] across.
  ///
  /// A null [minimumSize] means the Material minimum, 48dp square, resolved
  /// through the tree's [Layout3d.metrics] at the time of the hit test — so a
  /// surface bound to a camera keeps its targets 48dp as the view changes.
  TapTarget3d({Size3d? minimumSize, super.child, super.name})
    : _minimumSize = minimumSize;

  /// The Material minimum touch target, in logical pixels.
  static const double materialMinimum = 48.0;

  Size3d? _minimumSize;

  /// The smallest area the pointer is given, or null for the Material 48dp
  /// default.
  ///
  /// In world units, like every other extent in the package. Costs nothing to
  /// change: the hit test reads it as it walks.
  // ignore: unnecessary_getters_setters
  Size3d? get minimumSize => _minimumSize;

  set minimumSize(Size3d? value) {
    _minimumSize = value;
  }

  /// The minimum in force, with the default resolved.
  Size3d get effectiveMinimumSize =>
      _minimumSize ??
      Size3d(metrics.dp(materialMinimum), metrics.dp(materialMinimum), 0.0);

  /// How far outside its own extent this box answers, per axis.
  Offset3d get slop {
    if (!hasSize) return Offset3d.zero;
    final minimum = effectiveMinimumSize;
    double shortfall(double have, double want) =>
        want > have ? (want - have) / 2.0 : 0.0;
    return Offset3d(
      shortfall(size.width, minimum.width),
      shortfall(size.height, minimum.height),
      0.0,
    );
  }

  /// This box always answers for itself, over the grown extent: a target
  /// that only answered where its child does would not be a target.
  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  bool hitTest(HitTestResult3d result, {required Ray3d ray}) {
    if (!hasSize) return false;
    final slop = this.slop;
    if (slop == Offset3d.zero) return super.hitTest(result, ray: ray);
    // The grown box has its origin corner at -slop, so the ray moves the
    // other way to be expressed in it.
    final grown = ray.shifted(-slop);
    final range = grown.intersectBox(
      Size3d(
        size.width + slop.x * 2.0,
        size.height + slop.y * 2.0,
        size.depth + slop.z * 2.0,
      ),
    );
    if (range == null) return false;
    final entry = ray.at(range.near);
    if (!entry.isFinite) return false;
    // The recorded position is the true one in this box's frame, so a press
    // in the margin reports a point outside the extent rather than a clamped
    // fiction. A ripple centred there is centred where the finger was.
    // Children are still only reachable where they are: the reach this box
    // adds is its own, so a press in the margin is a press on the target
    // rather than on whatever the child would have said.
    hitTestChildren(result, ray: ray.clampedTo(range.near, range.far));
    result.add(HitTestEntry3d(this, entry));
    return true;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<Size3d>(
        'minimumSize',
        minimumSize,
        defaultValue: null,
      ),
    );
    properties.add(
      DiagnosticsProperty<Size3d>('effectiveMinimumSize', effectiveMinimumSize),
    );
  }
}
