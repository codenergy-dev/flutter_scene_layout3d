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
///
/// ## A press in the margin is a press at the centre
///
/// The reach would be decorative if it only found *this* box: a target
/// dispatches no gestures of its own, so a path with nothing on it but a
/// target is a press that lands nowhere. So when the ray misses the child's
/// extent but is inside the grown region, the children are tested a second
/// time with the ray **aimed at the centre of this box**, and whatever they
/// report is reported at that centre.
///
/// Flutter's `_RenderInputPadding` — the box `ButtonStyleButton` wraps every
/// button in — does exactly this, with `MatrixUtils.forceToPoint`. Forcing the
/// centre rather than clamping to the nearest edge is what makes it reliable:
/// the centre is the one position every box down the chain agrees is inside
/// itself, however they are padded and aligned. The entry's *depth* is kept as
/// it was, because the reach is in-plane and the depth a ray entered at is the
/// plane every later position for that box is measured on.
///
/// Only the hit test that *captures* the path is affected. A pointer that goes
/// down in the margin and then drags reports real positions from the second
/// event onward, so the first one jumps; that is invisible for a tap, and a
/// control that cares should size its own target instead.
///
/// ## Put it outside every box whose extent you are growing
///
/// This is the rule that makes the reach work, and the one that is easy to get
/// wrong. **A `TapTarget3d` reaches beyond its own extent and its parent does
/// not.** Every box gates its children on its own size, so a target nested
/// inside something no bigger — a Material panel, say — is rejected a level
/// above and never sees the ray at all. Nothing inside this class can reach
/// past its own parent.
///
/// Flutter puts the input padding outside the material for this reason, and so
/// should a component here:
///
/// ```dart
/// SceneSemantics3d(
///   properties: const SemanticsProperties(button: true, label: 'Save'),
///   child: SceneTapTarget3d(          // outside the panel, not inside it
///     child: Material3d(
///       child: InkWell3d(minimumSize: Size3d.zero, onTap: save),
///     ),
///   ),
/// )
/// ```
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
    // This box's own entry records the true position, so a press in the
    // margin reports a point outside the extent rather than a clamped
    // fiction. A ripple centred there is centred where the finger was.
    final inside = ray.clampedTo(range.near, range.far);
    if (!hitTestChildren(result, ray: inside)) {
      // The ordinary test missed, which out here means the ray is in the
      // margin. Aim it at the middle of the control instead — the one point
      // every box below agrees is inside itself — so that the gesture
      // detector under this target actually receives the press. In-plane
      // only: the depth stays where the ray entered.
      final centre = Offset3d(size.width / 2.0, size.height / 2.0, entry.z);
      hitTestChildren(result, ray: inside.shifted(entry - centre));
    }
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
