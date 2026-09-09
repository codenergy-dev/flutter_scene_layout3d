import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Offset3d, Ripple3d, Size3d;

/// How long a press ripple takes, and on what curve.
///
/// Material's motion for the press state layer, as four numbers a theme or a
/// component can replace. The figures are Flutter's own `InkRipple` timings,
/// reduced to the two phases this design has: the circle grows to cover the
/// control while the finger is down, and fades where it stands once the
/// finger is lifted.
///
/// There is no *unconfirmed* phase, and that is a deliberate difference from
/// Flutter. On a screen a ripple starts at the pointer down and creeps
/// outward until the gesture arena decides the press was a press; here the
/// ripple starts when [InkWell3d] reports the highlight, which is already
/// arena-resolved — a press that turns into a scroll never lights anything up
/// in the first place, so there is nothing to creep. See
/// `InkWell3d.onHighlightChanged`.
class InkRipple3dStyle {
  /// Creates a set of ripple timings.
  ///
  /// Every duration must be zero or positive, and it is not asserted: a
  /// `Duration`'s comparisons are method calls, which a `const` constructor's
  /// assert cannot evaluate, and giving up `const` here to check a figure
  /// nobody passes by accident is the worse trade. A zero or negative
  /// duration is treated as instantaneous by [InkRipple3dRun] rather than
  /// producing an infinity.
  const InkRipple3dStyle({
    this.fadeIn = const Duration(milliseconds: 75),
    this.expand = const Duration(milliseconds: 225),
    this.fadeOut = const Duration(milliseconds: 375),
    this.curve = Curves.ease,
  });

  /// Flutter's own figures: 75ms in, 225ms to grow, 375ms out.
  static const InkRipple3dStyle material = InkRipple3dStyle();

  /// How long the wash takes to reach its full opacity.
  final Duration fadeIn;

  /// How long the circle takes to cover the control.
  final Duration expand;

  /// How long the wash takes to disappear once the finger is lifted.
  final Duration fadeOut;

  /// The curve the radius follows. The opacity is linear on both ramps.
  final Curve curve;

  /// A copy with the given fields replaced.
  InkRipple3dStyle copyWith({
    Duration? fadeIn,
    Duration? expand,
    Duration? fadeOut,
    Curve? curve,
  }) => InkRipple3dStyle(
    fadeIn: fadeIn ?? this.fadeIn,
    expand: expand ?? this.expand,
    fadeOut: fadeOut ?? this.fadeOut,
    curve: curve ?? this.curve,
  );

  @override
  bool operator ==(Object other) =>
      other is InkRipple3dStyle &&
      other.fadeIn == fadeIn &&
      other.expand == expand &&
      other.fadeOut == fadeOut &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(fadeIn, expand, fadeOut, curve);

  @override
  String toString() =>
      'InkRipple3dStyle(in: $fadeIn, expand: $expand, out: $fadeOut)';
}

/// One press ripple, as a function of elapsed time.
///
/// The whole animation with no ticker, no widget and no box in it: say where
/// the press landed, how far the circle has to reach and how strong the wash
/// is, and ask what it looks like at a moment. [MutableInkController3d] drives
/// one of these from a `Ticker` and writes the answer onto a
/// `DecoratedBox3d.stateLayer`; a test drives it with a `for` loop.
///
/// Splitting it out this way is not tidiness. The claim phase 8 has to make is
/// that a whole ripple costs no build and no layout, and the only way to make
/// that claim about *arithmetic* is to have the arithmetic somewhere a test
/// can reach without a frame.
///
/// ## The two phases, and the flat part between them
///
/// A run has three stretches, and the middle one is the one worth knowing
/// about:
///
///  * **Growing.** The radius follows [InkRipple3dStyle.curve] from nothing to
///    [targetRadius] over [InkRipple3dStyle.expand], while the opacity ramps
///    linearly to [opacity] over [InkRipple3dStyle.fadeIn].
///  * **Held.** A finger still down after the expand is finished leaves a
///    circle that covers the control at its full opacity — which is pixel for
///    pixel the uniform press wash this package shipped before there was a
///    ripple. [isSettledAt] says so, and it is what lets the controller
///    **stop its ticker**: a button held down for a minute costs nothing at
///    all after the first quarter second.
///  * **Fading.** [release] starts the opacity down over
///    [InkRipple3dStyle.fadeOut]. The radius carries on growing through it if
///    it had not finished, because a ripple that stopped expanding the instant
///    the finger left would read as being snatched away.
class InkRipple3dRun {
  /// Creates a run centred on [origin], reaching [targetRadius].
  ///
  /// Both are in **world units**, in the washed box's own frame — see
  /// [Ripple3d], which explains why these are the one pair of figures in this
  /// package that are not in logical pixels.
  InkRipple3dRun({
    required this.origin,
    required this.targetRadius,
    required this.opacity,
    this.style = InkRipple3dStyle.material,
  }) : assert(targetRadius >= 0.0),
       assert(opacity >= 0.0 && opacity <= 1.0);

  /// A run that covers a box of [size] from wherever [origin] landed on it.
  ///
  /// The radius Material's ripple ends at, which is further from a corner than
  /// from the middle.
  factory InkRipple3dRun.covering({
    required Size3d size,
    required Offset3d origin,
    required double opacity,
    InkRipple3dStyle style = InkRipple3dStyle.material,
  }) => InkRipple3dRun(
    origin: origin,
    targetRadius: Ripple3d.radiusCovering(size, origin),
    opacity: opacity,
    style: style,
  );

  /// Where the press landed, in the washed box's own frame, in world units.
  final Offset3d origin;

  /// How far the circle grows, in world units.
  final double targetRadius;

  /// The wash's opacity at full strength, which is Material's press figure.
  final double opacity;

  /// The timings this run follows.
  final InkRipple3dStyle style;

  Duration? _releasedAt;

  /// When the finger came up, or null while it is still down.
  Duration? get releasedAt => _releasedAt;

  /// Records that the press ended at [elapsed], starting the fade.
  ///
  /// Idempotent: a second release — a cancel arriving after an up, which the
  /// gesture arena can produce — keeps the first one's timing rather than
  /// restarting the fade.
  void release(Duration elapsed) => _releasedAt ??= elapsed;

  /// The ripple at [elapsed] since the press was reported.
  Ripple3d rippleAt(Duration elapsed) => Ripple3d(
    origin: origin,
    radius: radiusAt(elapsed),
    opacity: opacityAt(elapsed),
  );

  /// The circle's radius at [elapsed], in world units.
  double radiusAt(Duration elapsed) =>
      targetRadius * style.curve.transform(_fraction(elapsed, style.expand));

  /// The wash's opacity at [elapsed].
  double opacityAt(Duration elapsed) {
    final released = _releasedAt;
    final arrived = _fraction(elapsed, style.fadeIn);
    if (released == null) return opacity * arrived;
    final left = 1.0 - _fraction(elapsed - released, style.fadeOut);
    return opacity * arrived * (left < 0.0 ? 0.0 : left);
  }

  /// Whether nothing about this run will change again without a [release].
  ///
  /// True once the circle has finished growing and the wash has finished
  /// arriving, and false forever after a release — which is the whole rule a
  /// driver needs to know when it may stop asking for frames.
  bool isSettledAt(Duration elapsed) =>
      _releasedAt == null && elapsed >= style.expand && elapsed >= style.fadeIn;

  /// Whether the ripple has faded out and can be dropped.
  bool isDoneAt(Duration elapsed) {
    final released = _releasedAt;
    return released != null && elapsed - released >= style.fadeOut;
  }

  static double _fraction(Duration elapsed, Duration total) {
    if (total <= Duration.zero) return 1.0;
    final t = elapsed.inMicroseconds / total.inMicroseconds;
    if (t <= 0.0) return 0.0;
    return t >= 1.0 ? 1.0 : t;
  }

  @override
  String toString() =>
      'InkRipple3dRun($origin, to: $targetRadius, at: $opacity'
      '${_releasedAt == null ? '' : ', released'})';
}
