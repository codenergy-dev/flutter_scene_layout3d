import 'package:flutter/animation.dart' show Animation;
import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DoubleProperty, protected;

import 'layout3d.dart';

/// The behaviour of a box that fades everything below it.
///
/// Mixed into [Opacity3d], which is the box a caller reaches for, and into
/// [MotionTransition3d], which fades an arrival alongside the slide, scale
/// and turn it was already applying. Both do the same two things: multiply
/// their own factor into what they inherit, and republish the subtree when it
/// changes.
///
/// The republish is the whole reason this is a mixin rather than two copies.
/// [Layout3d.inheritedOpacity] is computed by walking *up*, so nothing below
/// finds out that the value changed unless it is told — and being told is
/// [Layout3d.refreshOpacity], one uniform per box that draws. Forget the
/// republish and an opacity is correct for whatever was laid out afterwards
/// and stale for everything else, which is the kind of defect that only shows
/// up in the one frame nobody photographed.
mixin Layout3dOpacityMixin on Layout3d {
  double _opacity = 1.0;

  /// How much of the subtree below this box survives, from 0 to 1.
  ///
  /// Composes with whatever is already in force above, so an [Opacity3d] at
  /// 0.5 inside another at 0.5 draws a quarter, exactly as two nested
  /// `Opacity` widgets do.
  ///
  /// Setting it lays nothing out and rebuilds no geometry: it walks the
  /// subtree writing one uniform per box that draws, and asks the host for a
  /// frame. That is what makes an opacity legal to animate.
  double get imposedOpacity => _opacity;

  set imposedOpacity(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_opacity == clamped) return;
    _opacity = clamped;
    refreshOpacitySubtree();
    owner?.requestVisualUpdate();
  }

  /// Sets the value without republishing anything, for a constructor.
  ///
  /// A brand-new box has a brand-new subtree that has never drawn, so there
  /// is nothing below to tell — and a constructor that walks a tree is a
  /// surprise nobody needs. Every later write goes through [imposedOpacity].
  @protected
  void initialOpacity(double value) => _opacity = value.clamp(0.0, 1.0);

  @override
  double opacityForChild(Layout3d child) =>
      super.opacityForChild(child) * _opacity;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DoubleProperty('imposedOpacity', imposedOpacity, defaultValue: 1.0),
    );
  }
}

/// A box that fades everything below it.
///
/// The 3D analogue of `Opacity`, and the only box in this package that
/// publishes an opacity. Layout is untouched — the child is laid out against
/// the same constraints and this box takes the child's size, exactly as a
/// [ProxyLayout3d] does — and so is the geometry. What changes is how much of
/// the subtree's fragments are drawn.
///
/// ```dart
/// Opacity3d(
///   opacity: 0.38,
///   child: SizedBox3d(width: 1, height: 0.3, child: disabledButton),
/// )
/// ```
///
/// ## What a reader coming from Flutter should expect, and what is different
///
/// Correct at both ends, correct in ordering, and **about half again as much
/// label as Flutter would draw at 30%**. The reason is that this is *screen
/// door coverage* and not a `saveLayer`: a faded box keeps roughly `opacity`
/// of its fragments and discards the rest, and the survivors draw at full
/// strength and write depth exactly as an unfaded box's do. So a panel at 30%
/// lets 70% of the backdrop through, which is right, and a label on that
/// panel keeps 30% of its own pixels *over* a panel that kept 30% of its own
/// — where Flutter would composite the pair first and fade the result once,
/// so the label's contrast against its card would fall linearly.
///
/// The difference was measured rather than estimated: the label read 0.140
/// against a predicted 0.095 at 30%. It is zero at either end and largest
/// exactly in the middle, which is where everything is moving.
///
/// **It buys ordering, and that is not a small thing.** The approaches that
/// get group opacity exactly right were built and photographed too, and both
/// of the plausible ones fail at opacity **1.0** — one by letting a backdrop
/// paint over the panel in front of it, the other by burying whatever stands
/// in front of the faded subtree under a composited texture. A fade that is
/// wrong when nothing is being faded is worse than a fade that is slightly
/// too visible in the middle. The whole comparison, with pictures, is in
/// `plans/2026_09_16_a_box_that_fades.md`.
///
/// ## What it reaches
///
/// Everything this package draws: a [DecoratedBox3d]'s panel, a [Text3d] or
/// [RichText3d]'s glyphs, and the wall around those glyphs. It does **not**
/// reach geometry an application brought itself — see [NodeBox3d.onFade],
/// which is how such a box says it can fade, and which asserts in debug when
/// it is in a faded subtree and cannot.
///
/// ## What a ray sees
///
/// Everything, at every opacity, including zero. An opacity is a property of
/// the picture and nothing else here — the same bargain
/// [Layout3d.nodeOffset] makes. Wrap the subtree in an `IgnorePointer3d` to
/// take a faded-out control out of reach as well, exactly as Flutter's own
/// `Opacity` leaves you to.
class Opacity3d extends ProxyLayout3d with Layout3dOpacityMixin {
  /// Creates a box that draws [child] at [opacity].
  Opacity3d({double opacity = 1.0, super.child, super.name = 'Opacity3d'}) {
    initialOpacity(opacity);
  }

  /// How much of the subtree below survives, from 0 to 1.
  ///
  /// The same value as [Layout3dOpacityMixin.imposedOpacity], under the name
  /// a caller of this box writes. Note that it is what this box *imposes*,
  /// not what is in force on it: an `Opacity3d` at 0.5 inside another at 0.5
  /// reports 0.5 here and draws its subtree at 0.25.
  double get opacity => imposedOpacity;

  set opacity(double value) => imposedOpacity = value;
}

/// Fades its child as an animation runs, without laying anything out.
///
/// Flutter's `FadeTransition`, on the same tier as [NodeTransform3d]: the box
/// subscribes to the animation and writes each tick straight through as an
/// opacity, so no widget is rebuilt and no box is marked dirty for the whole
/// run. What a tick costs is one uniform per box below that draws.
///
/// ```dart
/// FadeTransition3d(
///   opacity: route.animation,
///   child: dialog,
/// )
/// ```
///
/// The parameter is named [opacity] rather than `animation` because that is
/// what Flutter's own is called, and because this box has a second thing it
/// could plausibly be given: [Opacity3d.opacity], a plain number. Both are
/// here — set the number for a fade that is not animated, hand over the
/// animation for one that is — and the animation wins while it is attached.
///
/// **A stopped animation must stop asking for frames.** That is the ticker
/// rule this package pays for everywhere, and it lives with whoever owns the
/// controller: this box only listens. See
/// `plans/2026_09_16_a_route_that_arrives_instead_of_appearing.md`.
class FadeTransition3d extends Opacity3d {
  /// Creates a box that draws [child] at whatever [opacity] currently says.
  FadeTransition3d({
    Animation<double>? opacity,
    super.child,
    super.name = 'FadeTransition3d',
  }) : _animation = opacity,
       super(opacity: opacity?.value ?? 1.0) {
    opacity?.addListener(_handleTick);
  }

  Animation<double>? _animation;

  /// The animation driving the opacity, or null for a fixed one.
  Animation<double>? get animation => _animation;

  set animation(Animation<double>? value) {
    if (identical(_animation, value)) return;
    _animation?.removeListener(_handleTick);
    _animation = value?..addListener(_handleTick);
    if (value != null) imposedOpacity = value.value;
  }

  void _handleTick() => imposedOpacity = _animation!.value;

  @override
  void dispose() {
    _animation?.removeListener(_handleTick);
    _animation = null;
    super.dispose();
  }
}
