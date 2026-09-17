import 'package:flutter/animation.dart' show Animation;
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import '../geometry/alignment3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import '../metrics.dart';
import '../opacity.dart';

/// Where a subtree stands before it has arrived — and where it goes as it
/// leaves.
///
/// A value, not a machine: it says how far off, how much smaller and how far
/// turned the content is at the start of its arrival, and
/// [MotionTransition3d] walks it back to [none] as an animation runs. A
/// dialog grows, a sheet comes up from below, a panel swings in about its
/// leading edge, and all three are one of these plus a duration.
///
/// ```dart
/// MotionTransition3d(
///   animation: route.animation,
///   motion: Motion3d.fromBelow,
///   child: sheet,
/// )
/// ```
///
/// ## The two ways of saying "how far"
///
/// [offset] is in **logical pixels** and [fraction] is in fractions of the
/// content's own size, and both are here because the two questions a real
/// transition asks are different ones. "Rise 24dp" is a figure a token set
/// states and a density resolves; "start one whole height below where you
/// belong" is a bottom sheet, and the height is whatever the sheet turned out
/// to be. They add, so a sheet that rises from just off its own bottom edge
/// is both.
///
/// ## The fade
///
/// [opacity] is where a dialog's own arrival is finished: everything else
/// here moves the content, and this is what makes it appear. It was left out
/// when this class was written, on the reasoning that there is no per-node
/// opacity in `flutter_scene` and a fade could therefore only reach a
/// decoration — a dialog whose panel dims and whose label does not, which is
/// worse than no fade at all.
///
/// **That reasoning was aimed at the wrong thing.** The engine's missing
/// `Node.opacity` never mattered, because this package draws with materials
/// it owns; what stood in the way was `depth_write`, and screen-door
/// coverage goes around it. So the fade reaches the panel, the label and the
/// wall around the label's letters alike. See [Opacity3d], which is what a
/// [MotionTransition3d] imposes on the subtree below it.
class Motion3d {
  /// Creates a motion from its parts; everything left out is at rest.
  const Motion3d({
    this.offset = Offset3d.zero,
    this.fraction = Offset3d.zero,
    this.scale = 1.0,
    this.turn = 0.0,
    this.opacity = 1.0,
    this.axis = const Offset3d(0, 1, 0),
    this.origin = Alignment3d.center,
  }) : assert(opacity >= 0.0 && opacity <= 1.0);

  /// Grows from [from] of its size, about [origin].
  ///
  /// Flutter's `ScaleTransition`, and a dialog's own arrival. [origin] is
  /// where the growth is pinned: the centre for a dialog, the corner a menu
  /// hangs from for a menu.
  const Motion3d.grow({
    double from = 0.85,
    Alignment3d origin = Alignment3d.center,
  }) : this(scale: from, origin: origin);

  /// Swings in from [radians] about [axis], pivoting on [origin].
  ///
  /// The one with no two-dimensional analogue. A panel hinged on its leading
  /// edge is `Motion3d.turn(radians: -0.6, origin: Alignment3d.centerLeft)`.
  const Motion3d.turn({
    double radians = 0.5,
    Offset3d axis = const Offset3d(0, 1, 0),
    Alignment3d origin = Alignment3d.center,
  }) : this(turn: radians, axis: axis, origin: origin);

  /// Fades in from [from], moving nothing.
  ///
  /// Flutter's `FadeTransition`, and the plainest arrival there is. It
  /// composes with the others through the ordinary constructor — a dialog
  /// that grows *and* fades is
  /// `Motion3d(scale: 0.85, opacity: 0.0)` — and it is here on its own
  /// because a scrim, a tooltip and a snack bar want exactly this and nothing
  /// else.
  const Motion3d.fade({double from = 0.0}) : this(opacity: from);

  /// Arrival itself: nothing moved, nothing scaled, nothing turned, nothing
  /// faded.
  static const Motion3d none = Motion3d();

  /// Comes up from one whole height below where it belongs: a bottom sheet.
  ///
  /// The one case where stating the distance in logical pixels would be
  /// wrong — a sheet has to start fully off the edge it comes from, whatever
  /// it turned out to be — and the reason it is a value rather than a
  /// constructor is that Dart will not let a `const` constructor build an
  /// [Offset3d] out of a parameter. A sheet that starts half off writes
  /// `Motion3d(fraction: Offset3d(0, 0.5, 0))`, which is the same sentence
  /// with the number in it.
  static const Motion3d fromBelow = Motion3d(fraction: Offset3d(0, 1, 0));

  /// Comes forward from 24dp further away than it belongs.
  ///
  /// The depth axis grows away from the viewer, so this starts the content
  /// behind where it lands and brings it toward the viewer. For the other
  /// direction, or another distance, write the offset:
  /// `Motion3d(offset: Offset3d(0, 0, -16))` settles back from in front,
  /// which is what a menu on a panel seen edge-on wants.
  static const Motion3d fromBehind = Motion3d(offset: Offset3d(0, 0, 24));

  /// How far off the content starts, in logical pixels.
  final Offset3d offset;

  /// How far off the content starts, in fractions of its own size.
  final Offset3d fraction;

  /// How big the content starts, as a fraction of its own size.
  final double scale;

  /// How far the content starts turned, in radians about [axis].
  final double turn;

  /// How much of the content is drawn at the start of its arrival, from 0
  /// to 1.
  ///
  /// One is no fade, which is the default: a motion says what it does and
  /// nothing else. Zero is the ordinary dialog, appearing out of nothing.
  ///
  /// **It is coverage rather than alpha**, which is what makes it reach a
  /// whole subtree instead of one decoration — a faded panel, its label and
  /// the wall around that label's letters all discard the same fragments.
  /// [Opacity3d] has what that costs in the picture, and it is not free:
  /// group opacity is approximated, and the approximation is largest exactly
  /// in the middle of an arrival. It is also invisible at both ends, which
  /// for something that lasts two hundred milliseconds is the trade worth
  /// making.
  final double opacity;

  /// The axis [turn] turns about, in layout space.
  final Offset3d axis;

  /// The point [scale] and [turn] pivot on.
  final Alignment3d origin;

  /// Whether this motion moves anything at all.
  bool get isAtRest =>
      offset == Offset3d.zero &&
      fraction == Offset3d.zero &&
      scale == 1.0 &&
      turn == 0.0 &&
      opacity == 1.0;

  /// The node offset this motion asks for, for content of [size] at
  /// [metrics].
  ///
  /// The [offset] half is taken through the unit contract and the [fraction]
  /// half through the size, which is why this needs both and why a box
  /// resolves it when it has been laid out rather than when it was built.
  Offset3d offsetIn(Size3d size, Layout3dMetrics metrics) => Offset3d(
    metrics.dp(offset.x) + fraction.x * size.width,
    metrics.dp(offset.y) + fraction.y * size.height,
    metrics.dp(offset.z) + fraction.z * size.depth,
  );

  /// The node transform this motion asks for, for content of [size], or null
  /// when it asks for none.
  ///
  /// Null rather than an identity matrix at rest, so content that only slides
  /// carries no extra multiply at all, which is the rule every node-tier box
  /// in this package keeps.
  Matrix4? transformFor(Size3d size) {
    if (scale == 1.0 && turn == 0.0) return null;
    final pivot = origin.alongSize(size);
    final transform = Matrix4.translationValues(pivot.x, pivot.y, pivot.z);
    if (turn != 0.0) {
      final direction = Vector3(axis.x, axis.y, axis.z);
      // A zero axis is no hinge at all; it turns nothing rather than
      // producing a matrix full of NaN.
      if (direction.length2 > 0.0) {
        transform.multiply(
          Matrix4.compose(
            Vector3.zero(),
            // Stated as an axis and an angle rather than as three of them:
            // `Quaternion.axisAngle` normalizes, so `(0, 2, 0)` is the same
            // hinge as `(0, 1, 0)`.
            Quaternion.axisAngle(direction, turn),
            Vector3(1, 1, 1),
          ),
        );
      }
    }
    if (scale != 1.0) {
      transform.multiply(Matrix4.diagonal3Values(scale, scale, scale));
    }
    return transform
      ..multiply(Matrix4.translationValues(-pivot.x, -pivot.y, -pivot.z));
  }

  /// Linearly interpolates between two motions.
  ///
  /// Every part interpolates on its own, including [axis] and [origin], which
  /// matters for a caller tweening between two whole motions rather than from
  /// one to [none].
  static Motion3d lerp(Motion3d a, Motion3d b, double t) => Motion3d(
    offset: Offset3d.lerp(a.offset, b.offset, t),
    fraction: Offset3d.lerp(a.fraction, b.fraction, t),
    scale: a.scale + (b.scale - a.scale) * t,
    turn: a.turn + (b.turn - a.turn) * t,
    opacity: (a.opacity + (b.opacity - a.opacity) * t).clamp(0.0, 1.0),
    axis: Offset3d.lerp(a.axis, b.axis, t),
    origin: Alignment3d.lerp(a.origin, b.origin, t),
  );

  /// This motion [t] of the way to arrival: itself at 0, [none] at 1.
  Motion3d arrived(double t) => t <= 0.0
      ? this
      : t >= 1.0
      ? none
      : lerp(this, none, t);

  @override
  bool operator ==(Object other) =>
      other is Motion3d &&
      other.offset == offset &&
      other.fraction == fraction &&
      other.scale == scale &&
      other.turn == turn &&
      other.opacity == opacity &&
      other.axis == axis &&
      other.origin == origin;

  @override
  int get hashCode =>
      Object.hash(offset, fraction, scale, turn, opacity, axis, origin);

  @override
  String toString() {
    if (isAtRest) return 'Motion3d.none';
    final parts = <String>[
      if (offset != Offset3d.zero) 'offset: $offset',
      if (fraction != Offset3d.zero) 'fraction: $fraction',
      if (scale != 1.0) 'scale: $scale',
      if (turn != 0.0) 'turn: $turn about $axis',
      if (opacity != 1.0) 'opacity: $opacity',
    ];
    return 'Motion3d(${parts.join(', ')}, from $origin)';
  }
}

/// Moves its child from a [Motion3d] to rest as an animation runs, without
/// laying anything out.
///
/// Flutter's `SlideTransition`, `ScaleTransition`, `RotationTransition` and
/// `FadeTransition` in one box: the whole run costs one matrix a frame plus
/// one uniform per box below that draws, no box is marked dirty, and no text
/// is re-shaped. It is what a route's content is
/// wrapped in, and what anything else that arrives — a snack bar, a tooltip,
/// a panel a component slides in — can use on its own.
///
/// ```dart
/// MotionTransition3d(
///   animation: route.animation,
///   motion: const Motion3d.grow(),
///   child: dialog,
/// )
/// ```
///
/// ## Why it is not [NodeTransform3d]
///
/// That box takes an `Animation<Offset3d>` or an `Animation<Matrix4>` — the
/// values themselves, already resolved. Two of the things a transition wants
/// to say cannot be resolved until the box has a size: a fraction of the
/// content's own height, and a pivot to grow about. **And the size arrives
/// after the first tick**, always: a ticker's first tick lands in the
/// animation phase, before the layout that would settle the size, and a
/// widget-built overlay entry's subtree does not exist at all until the build
/// after the insertion.
///
/// So this box re-applies from its own [performLayout] as well as on every
/// tick. Writing the node tier there is free of consequence by construction —
/// it does not dirty layout, and [Layout3d.worldTransform] undoes it — and it
/// is what keeps a route from showing one frame at rest before it starts.
///
/// ## What a ray sees
///
/// Where layout put the content, not where the motion has carried it. That is
/// the node tier's contract everywhere in this package, and for the couple of
/// hundred milliseconds an arrival lasts it is the right trade: a press lands
/// where the dialog is about to be.
class MotionTransition3d extends ProxyLayout3d with Layout3dOpacityMixin {
  /// Creates a box that moves [child] from [motion] to rest as [animation]
  /// runs.
  MotionTransition3d({
    Animation<double>? animation,
    Motion3d motion = Motion3d.none,
    super.child,
    super.name = 'MotionTransition3d',
  }) : _animation = animation,
       _motion = motion {
    animation?.addListener(_handleTick);
  }

  Animation<double>? _animation;

  /// How far the content has arrived: 0 is [motion], 1 is rest.
  ///
  /// Null is rest, which is what a route pushed without a transition has and
  /// what an entry that only wants the box for later gets.
  Animation<double>? get animation => _animation;

  set animation(Animation<double>? value) {
    if (identical(_animation, value)) return;
    _animation?.removeListener(_handleTick);
    _animation = value?..addListener(_handleTick);
    _apply();
  }

  Motion3d _motion;

  /// Where the content stands before it has arrived.
  Motion3d get motion => _motion;

  set motion(Motion3d value) {
    if (_motion == value) return;
    _motion = value;
    _apply();
  }

  /// How far the content has arrived, from 0 to 1.
  double get progress => (_animation?.value ?? 1.0).clamp(0.0, 1.0);

  @override
  void performLayout() {
    super.performLayout();
    // After the size, because half of what a motion says is a fraction of it.
    _apply();
  }

  void _handleTick() => _apply();

  void _apply() {
    if (!hasSize) return;
    final placed = _motion.arrived(progress);
    nodeOffset = placed.isAtRest
        ? Offset3d.zero
        : placed.offsetIn(size, metrics);
    nodeTransform = placed.isAtRest ? null : placed.transformFor(size);
    // The one part of a motion that is not the node tier. It is still not a
    // relayout: writing it walks the subtree handing each box that draws one
    // uniform, and does nothing at all while the motion carries no fade,
    // because the setter compares first.
    imposedOpacity = placed.opacity;
  }

  @override
  void dispose() {
    _animation?.removeListener(_handleTick);
    _animation = null;
    super.dispose();
  }
}
