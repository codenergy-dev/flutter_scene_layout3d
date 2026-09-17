import 'package:flutter/animation.dart'
    show Animation, AnimationController, Curve, CurvedAnimation, Curves, Tween;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        SingleTickerProviderStateMixin,
        State,
        StatefulWidget,
        Widget;

import '../opacity.dart';
import 'framework.dart';

/// The declarative form of [Opacity3d]: a subtree drawn at a fraction of its
/// strength.
///
/// ```dart
/// SceneOpacity3d(
///   opacity: enabled ? 1.0 : 0.38,
///   child: const SceneContainer3d(width: 1, height: 0.3),
/// )
/// ```
///
/// Rebuilding this with a new [opacity] writes one uniform per box below that
/// draws — a panel's, a label's, the wall around a label's letters — and lays
/// nothing out. What that costs and how it differs from Flutter's own
/// `Opacity` is in [Opacity3d]'s own documentation, and the short version is
/// that it is coverage rather than a `saveLayer`: exact at both ends, exact
/// in ordering, and a little generous with a label over a faded card in the
/// middle.
///
/// For a fade driven by an animation, prefer [SceneFadeTransition3d] — it
/// subscribes to the animation and rebuilds nothing at all — or
/// [SceneAnimatedOpacity3d] when what you have is a target rather than a
/// controller.
class SceneOpacity3d extends SingleChildLayout3dWidget {
  /// Creates a box that draws [child] at [opacity].
  const SceneOpacity3d({super.key, required this.opacity, super.child});

  /// How much of the subtree below survives, from 0 to 1.
  final double opacity;

  @override
  Opacity3d createLayout(BuildContext context) => Opacity3d(opacity: opacity);

  @override
  void updateLayout(BuildContext context, Opacity3d layout) {
    layout.opacity = opacity;
  }
}

/// The declarative form of [FadeTransition3d]: a subtree that fades as an
/// animation runs.
///
/// Flutter's `FadeTransition`, and the same bargain the rest of this
/// package's transitions make — give it the animation rather than the value,
/// and the widget below is built once while the box subscribes:
///
/// ```dart
/// SceneFadeTransition3d(
///   opacity: route.animation,
///   child: Dialog3d(child: choices),
/// )
/// ```
///
/// A route built with `WidgetPageRoute3d(motion: Motion3d(opacity: 0))`
/// already fades, through [MotionTransition3d], which does this and the slide
/// and the scale together. This is for the content that wants the fade
/// somewhere other than around the whole page — over the dialog but not over
/// the scrim that dims behind it, which is exactly where a catalogue's modal
/// frame puts it.
class SceneFadeTransition3d extends SingleChildLayout3dWidget {
  /// Creates a box that draws [child] at whatever [opacity] currently says.
  const SceneFadeTransition3d({super.key, this.opacity, super.child});

  /// The animation driving the opacity, or null for no fade.
  final Animation<double>? opacity;

  @override
  FadeTransition3d createLayout(BuildContext context) =>
      FadeTransition3d(opacity: opacity);

  @override
  void updateLayout(BuildContext context, FadeTransition3d layout) {
    layout.animation = opacity;
  }
}

/// Fades its child whenever the opacity it is given changes.
///
/// Flutter's `AnimatedOpacity`, and the same shape as
/// [SceneAnimatedSlide3d]: a target change costs one rebuild of this widget,
/// and the run costs nothing below it at all — the box holds the animation
/// and writes each tick straight through.
///
/// ```dart
/// SceneAnimatedOpacity3d(
///   duration: const Duration(milliseconds: 200),
///   curve: Curves.easeOut,
///   opacity: selected ? 1.0 : 0.0,
///   child: badge,
/// )
/// ```
///
/// **A faded-out subtree is still where it was**, to layout and to a ray
/// alike: an opacity is a property of the picture and of nothing else here.
/// Wrap it in a `SceneIgnorePointer3d` for a control that should stop being
/// pressable as it goes, or use `SceneVisibility3d` when what is wanted is
/// for it to stop taking up room.
class SceneAnimatedOpacity3d extends StatefulWidget {
  /// Creates a fade that follows its target.
  const SceneAnimatedOpacity3d({
    super.key,
    required this.opacity,
    required this.duration,
    this.curve = Curves.linear,
    this.child,
  });

  /// How much of the subtree below is drawn, from 0 to 1.
  final double opacity;

  /// How long a change takes to settle.
  final Duration duration;

  /// The curve the fade follows.
  final Curve curve;

  /// The widget below this one in the tree.
  final Widget? child;

  @override
  State<SceneAnimatedOpacity3d> createState() => _SceneAnimatedOpacity3dState();
}

class _SceneAnimatedOpacity3dState extends State<SceneAnimatedOpacity3d>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: widget.duration,
    // At the end of an arrival that never happened, so the first frame draws
    // the opacity that was asked for rather than fading up to it.
    value: 1.0,
    vsync: this,
  );
  late CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );
  late final Tween<double> _tween = Tween<double>(
    begin: widget.opacity,
    end: widget.opacity,
  );
  late Animation<double> _animation = _tween.animate(_curved);

  @override
  void didUpdateWidget(SceneAnimatedOpacity3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (widget.curve != oldWidget.curve) {
      final previous = _curved;
      _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
      _animation = _tween.animate(_curved);
      previous.dispose();
    }
    if (widget.opacity == oldWidget.opacity) return;
    // Retarget in place, exactly as `SceneAnimatedSlide3d` does: the animation
    // object the box below holds stays the same instance, so the retarget
    // costs one rebuild of this widget and nothing below it.
    _tween
      ..begin = _animation.value
      ..end = widget.opacity;
    _controller
      ..value = 0.0
      ..forward();
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SceneFadeTransition3d(opacity: _animation, child: widget.child);
}
