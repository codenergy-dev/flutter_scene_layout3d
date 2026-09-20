import 'package:flutter/animation.dart' show Animation;
import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty, FlagProperty;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../anchoring.dart';
import '../boxes/ignore_pointer.dart';
import '../boxes/sized.dart';
import '../geometry/alignment3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import '../overlay/overlay.dart';
import '../widgets/framework.dart';

/// Which way a flight is going.
///
/// What a [Hero3dFlightBuilder] reads when the thing that flies should differ
/// by direction. Most do not care: a flight is the same object either way,
/// which is the whole illusion.
enum Hero3dFlightDirection {
  /// A route arrived over the one that holds the other end.
  push,

  /// A route left, uncovering the one that holds the other end.
  pop,
}

/// How a flight's geometry is scaled to reach each end.
///
/// The flight is laid out once and scaled on the node tier — a size that
/// changed every frame would be a relayout every frame, which is the one tier
/// this package keeps off the animation path. What is left to choose is
/// whether the three axes scale together.
///
/// **When the two ends have the same aspect ratio the two members are
/// identical**, and that is the common case: an avatar to an avatar, a card
/// to a card. The choice only bites where the shapes differ.
enum Hero3dFit {
  /// Each axis scales on its own, so both ends are matched exactly.
  ///
  /// What Flutter's `Hero` achieves with a `RectTween`, by a means not
  /// available here. Content whose proportions matter — a letter, a circle —
  /// is distorted in between when the two ends disagree about them.
  stretch,

  /// One factor for all three axes, so nothing is ever distorted.
  ///
  /// The factor is the smaller of the two plane factors, which is `contain`
  /// semantics: the flight fits inside the box at each end rather than
  /// overhanging it. A flight carrying type wants this.
  uniform,
}

/// What a [Hero3dFlightBuilder] is told about the flight it is building.
///
/// [size] is the size the flight is laid out at, and it is the size of the
/// end the flight *starts* from — so the flight is exact at the moment it
/// replaces that end, and reaches the other by scale.
class Hero3dFlight {
  /// Creates a description of a flight.
  const Hero3dFlight({
    required this.tag,
    required this.size,
    required this.direction,
    required this.animation,
  });

  /// The tag the two ends matched on.
  final Object tag;

  /// The size the flight is laid out at: the size of the end it starts from.
  final Size3d size;

  /// Which way this flight is going.
  final Hero3dFlightDirection direction;

  /// The route's own clock, from 0 at the covered end to 1 at the covering
  /// one.
  ///
  /// **It runs backwards on a pop**, from 1 to 0, because it is the same
  /// animation read from the other end. A builder that wants "how far along
  /// is this flight" regardless of direction takes
  /// `direction == Hero3dFlightDirection.push ? value : 1 - value`.
  final Animation<double> animation;

  @override
  String toString() => 'Hero3dFlight($tag, $direction, $size)';
}

/// Builds what flies between two [Hero3d] boxes.
///
/// Called once, when the flight starts, and the subtree it returns belongs to
/// the overlay entry that hosts it: it is disposed when the flight ends,
/// whatever ended it.
typedef Hero3dFlightBuilder = Layout3d Function(Hero3dFlight flight);

/// A box whose content appears to fly to the matching box on another route.
///
/// The 3D analogue of Flutter's `Hero`, with one difference that is forced
/// rather than chosen: **nothing is reparented.** Flutter lifts the hero's
/// own subtree into the overlay for the duration of the flight; this stack
/// cannot, for the reason `Draggable3d` found first — building a second copy
/// of a widget-built child lays a render box out, and a flight begins in the
/// middle of a route transition. So a hero is built twice, like a drag's
/// feedback is:
///
/// ```dart
/// Layout3d avatar() => Image3d(image: photo, fit: BoxFit3d.cover);
///
/// Hero3d(
///   tag: photo.id,
///   flightBuilder: (_) => avatar(),
///   child: avatar(),
/// )
/// ```
///
/// A hero with no partner on the other side does not fly, and says nothing
/// about it. That is Flutter's behaviour and the only sane one: a screen
/// whose heroes do not all match is the normal case.
///
/// ## What drives it
///
/// [Route3d.animation], and nothing else. A flight has **no ticker of its
/// own**, so it takes the route's duration and the route's curve for free —
/// and none of the ticker discipline that has cost this repository time
/// twice, because there is no second clock to stop, restart or leave
/// spinning. A route pushed with [Route3dTransition.none] has a clock that
/// never ticks, so its heroes correctly do not fly.
///
/// ## What it costs per frame
///
/// One offset and one matrix, per flight. The flight is laid out once, when
/// it starts, and every frame after that writes [Layout3d.nodeOffset] and
/// [Layout3d.nodeTransform] — the node tier, which never calls
/// `markNeedsLayout`. A size that changed every frame would be a relayout
/// every frame, which is why the size change is a scale; see [Hero3dFit].
///
/// The depth axis is deliberately left alone. An entry is lifted toward the
/// viewer by its layer's lift precisely so it does not fight what it is
/// carried over, and correcting z as well would put the flight back on the
/// content's own plane and hand the depth test a coin toss — which is what
/// `drag_feedback_depth` in `examples/render_probe` caught for the drag lane.
///
/// ## A route motion moves the other end out from under it
///
/// A flight lands where *layout* put the far end, because
/// [Layout3d.worldTransform] undoes the node tier — which is what makes it
/// safe to recompute every frame. A route whose content is sliding in has its
/// heroes at their resting places while the content is drawn somewhere else,
/// so the flight lands correctly and the thing it hands over to is still in
/// transit. The two are answers to the same question and the flight is the
/// better one: give a route carrying heroes `Motion3d.fade()`, or no motion
/// at all.
class Hero3d extends ProxyLayout3d {
  /// Creates a hero that flies to the box carrying the same [tag].
  Hero3d({
    required this.tag,
    required this.flightBuilder,
    this.fit = Hero3dFit.stretch,
    super.child,
    super.name = 'Hero3d',
  });

  /// What this box matches on.
  ///
  /// Any object with a sane `==`. Two heroes carrying the same tag on the
  /// same route is a mistake — which end would fly? — and asserts in debug.
  Object tag;

  /// Builds what flies, when this end is the one a flight starts from.
  Hero3dFlightBuilder flightBuilder;

  /// How the flight is scaled to reach each end.
  ///
  /// Read from the end the flight starts from, since that is the end whose
  /// builder made the geometry being scaled.
  Hero3dFit fit;

  bool _flying = false;

  /// Whether a flight is standing in for this box.
  ///
  /// While it is, this box is hidden — and hit testing honours the same flag,
  /// so a hero mid-flight is unpointable as well as unseen, which is right
  /// and is what Flutter does.
  bool get isFlying => _flying;

  void _setFlying(bool value) {
    if (_flying == value) return;
    _flying = value;
    node.visible = !value;
    owner?.requestVisualUpdate();
  }

  @override
  void performLayout() {
    super.performLayout();
    // The scrolling views cull by writing this flag too, and the last writer
    // during a layout pass should be the box that owns the decision — the
    // same rule `Visibility3d` keeps.
    node.visible = !_flying;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Object>('tag', tag))
      ..add(DiagnosticsProperty<Hero3dFit>('fit', fit))
      ..add(FlagProperty('isFlying', value: isFlying, ifTrue: 'flying'));
  }
}

/// Collects the heroes under [root], keyed by tag, first one winning.
///
/// Prunes at anything in [stopAt], which is how the page under an overlay is
/// searched without descending into the entries standing on it. Does not
/// descend into a hero it has found: a hero inside a hero is pathological,
/// and the outer one is the flight.
void collectHero3ds(
  Layout3d root,
  Map<Object, Hero3d> into, {
  Set<Layout3d> stopAt = const <Layout3d>{},
}) {
  if (stopAt.contains(root)) return;
  if (root is Hero3d) {
    assert(
      !into.containsKey(root.tag),
      'Two Hero3d boxes carry the tag ${root.tag} on one route. A tag names '
      'one box per route, or a flight cannot tell which end it has.',
    );
    into.putIfAbsent(root.tag, () => root);
    return;
  }
  root.visitChildren((child) => collectHero3ds(child, into, stopAt: stopAt));
}

/// Builds the overlay entry that carries one flight.
///
/// [aSide] is the hero on the covered route, [bSide] the one on the covering
/// route, and [animation] runs 0 at the first to 1 at the second — which is
/// the route's own clock in both directions, read from opposite ends.
Overlay3dEntry buildHero3dFlightEntry({
  required Object tag,
  required Hero3d aSide,
  required Hero3d bSide,
  required Hero3dFlightDirection direction,
  required Animation<double> animation,
  OverlayLayer3d layer = const OverlayLayer3d.inPlane(),
}) {
  // The end the flight starts from builds it and sets its size, so that the
  // frame where the flight replaces a real box is exact. On a push that is
  // the covered side; on a pop it is the side that is leaving — in both
  // cases, the thing the viewer was just looking at.
  final from = direction == Hero3dFlightDirection.push ? aSide : bSide;
  final size = from.size;
  return Overlay3dEntry(
    layer: layer,
    debugLabel: 'Hero3d flight ($tag)',
    builder: (_) => Hero3dFlightBox(
      animation: animation,
      aSide: aSide,
      bSide: bSide,
      fit: from.fit,
      child: SizedBox3d.fromSize(
        size,
        // Mandatory rather than tidy, for the reason the drag lane states:
        // hit testing ignores `nodeOffset`, so the flight's laid-out position
        // is still reachable even though it is drawn somewhere else, and
        // anything inside would answer a ray on its own account.
        child: IgnorePointer3d(
          child: from.flightBuilder(
            Hero3dFlight(
              tag: tag,
              size: size,
              direction: direction,
              animation: animation,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The box that moves a flight, and hides the two ends while it is up.
///
/// Public so that a test can find one; built by [buildHero3dFlightEntry] and
/// not usefully constructed by hand.
class Hero3dFlightBox extends ProxyLayout3d {
  /// Creates a flight between [aSide] and [bSide].
  Hero3dFlightBox({
    required Animation<double> animation,
    required this.aSide,
    required this.bSide,
    this.fit = Hero3dFit.stretch,
    super.child,
    super.name = 'Hero3dFlightBox',
  }) : _animation = animation {
    animation.addListener(_handleTick);
  }

  final Animation<double> _animation;

  /// The hero on the covered route, where the flight stands at 0.
  final Hero3d aSide;

  /// The hero on the covering route, where the flight stands at 1.
  final Hero3d bSide;

  /// How this flight is scaled to reach each end.
  final Hero3dFit fit;

  bool _placed = false;

  /// Whether this flight has managed to place itself at least once.
  ///
  /// The two ends stay visible until it has. A flight that hid them and then
  /// could not place itself would leave a frame with nothing in it at all,
  /// which is the most visible defect a motion can have.
  bool get hasPlaced => _placed;

  @override
  void performLayout() {
    super.performLayout();
    // After the size, because every factor below is measured against it.
    _apply();
  }

  void _handleTick() => _apply();

  void _apply() {
    if (!hasSize) return;
    final a = _placementOf(aSide);
    final b = _placementOf(bSide);
    // The far end has no size on the frame its entry was inserted, so a
    // flight parks on the end it can see and asks again next tick. This is
    // also what makes it self-correcting under a scroll or a resize.
    final from = a ?? b;
    final to = b ?? a;
    if (from == null || to == null) return;
    final t = _animation.value.clamp(0.0, 1.0);
    nodeOffset = Offset3d.lerp(from.offset, to.offset, t);
    nodeTransform = _scaleAbout(
      Size3d(
        from.size.width + (to.size.width - from.size.width) * t,
        from.size.height + (to.size.height - from.size.height) * t,
        from.size.depth + (to.size.depth - from.size.depth) * t,
      ),
    );
    if (!_placed) {
      _placed = true;
      aSide._setFlying(true);
      bSide._setFlying(true);
    }
  }

  /// Where this flight would stand to cover [hero], and how big [hero] is.
  ///
  /// Null while [hero] has no size, which is every frame before its entry has
  /// been flushed.
  ({Offset3d offset, Size3d size})? _placementOf(Hero3d hero) {
    if (!hero.hasSize) return null;
    final offset = anchorOffsetTo(hero);
    if (offset == null) return null;
    return (offset: offset, size: hero.size);
  }

  /// The node transform that makes this flight look [wanted] big.
  ///
  /// Null when it asks for no scaling at all, so a flight between two boxes
  /// of one size carries no extra multiply — the rule every node-tier box in
  /// this package keeps.
  Matrix4? _scaleAbout(Size3d wanted) {
    double factor(double target, double own) => own == 0.0 ? 1.0 : target / own;
    var x = factor(wanted.width, size.width);
    var y = factor(wanted.height, size.height);
    var z = factor(wanted.depth, size.depth);
    if (fit == Hero3dFit.uniform) {
      // `contain` semantics: the flight fits inside the box at each end
      // rather than overhanging it.
      x = y = z = x < y ? x : y;
    }
    if (x == 1.0 && y == 1.0 && z == 1.0) return null;
    final pivot = Alignment3d.center.alongSize(size);
    return Matrix4.translationValues(pivot.x, pivot.y, pivot.z)
      ..multiply(Matrix4.diagonal3Values(x, y, z))
      ..multiply(Matrix4.translationValues(-pivot.x, -pivot.y, -pivot.z));
  }

  @override
  void dispose() {
    _animation.removeListener(_handleTick);
    // The single un-hiding path: every ending reaches it, whatever ended the
    // flight — the animation settling, the route being popped mid-push, or
    // the navigator going away.
    aSide._setFlying(false);
    bSide._setFlying(false);
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Object>('tag', aSide.tag))
      ..add(DiagnosticsProperty<Hero3dFit>('fit', fit))
      ..add(FlagProperty('hasPlaced', value: hasPlaced, ifTrue: 'placed'));
  }
}

/// The declarative form of [Hero3d].
///
/// ```dart
/// SceneHero3d(
///   tag: photo.id,
///   flightBuilder: (_) => avatar(),
///   child: SceneImage3d(image: photo),
/// )
/// ```
///
/// The flight itself is *not* built from the widget layer, and cannot be: it
/// belongs to an overlay entry that is inserted from inside a route
/// transition, where there is no element to build into. So
/// [flightBuilder] returns a [Layout3d] here as it does on [Hero3d] — the
/// same seam `Draggable3d.feedbackBuilder` has, for the same reason.
class SceneHero3d extends SingleChildLayout3dWidget {
  /// Creates a hero that flies to the box carrying the same [tag].
  const SceneHero3d({
    super.key,
    required this.tag,
    required this.flightBuilder,
    this.fit = Hero3dFit.stretch,
    super.child,
  });

  /// What this box matches on.
  final Object tag;

  /// Builds what flies, when this end is the one a flight starts from.
  final Hero3dFlightBuilder flightBuilder;

  /// How the flight is scaled to reach each end.
  final Hero3dFit fit;

  @override
  Hero3d createLayout(BuildContext context) =>
      Hero3d(tag: tag, flightBuilder: flightBuilder, fit: fit);

  @override
  void updateLayout(BuildContext context, Hero3d layout) {
    layout
      ..tag = tag
      ..flightBuilder = flightBuilder
      ..fit = fit;
  }
}
