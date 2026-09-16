import 'package:flutter/animation.dart'
    show Animation, AnimationController, Curve, CurvedAnimation, Curves;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        SingleTickerProviderStateMixin,
        State,
        StatefulWidget,
        Widget;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../geometry/offset3d.dart';
import '../widgets/framework.dart';
import 'motion.dart';
import 'node_transform.dart';
import 'tweens.dart';

/// The declarative form of [NodeTransform3d]: a subtree whose geometry is
/// moved by an animation the layout never hears about.
///
/// Give it animations rather than values. The box subscribes to them and
/// writes each tick straight onto its scene node, so the widget below it is
/// built once and no box is ever marked dirty, however long the animation
/// runs.
///
/// ```dart
/// SceneNodeTransform3d(
///   offset: _lift,   // an Animation<Offset3d> the State owns
///   child: const SceneContainer3d(width: 1, height: 1),
/// )
/// ```
class SceneNodeTransform3d extends SingleChildLayout3dWidget {
  /// Creates a node-only animation box.
  const SceneNodeTransform3d({
    super.key,
    this.offset,
    this.transform,
    super.child,
  });

  /// The animation driving the node's offset, in layout units.
  final Animation<Offset3d>? offset;

  /// The animation driving the node's transform.
  final Animation<Matrix4>? transform;

  @override
  NodeTransform3d createLayout(BuildContext context) =>
      NodeTransform3d(offsetAnimation: offset, transformAnimation: transform);

  @override
  void updateLayout(BuildContext context, NodeTransform3d layout) {
    layout
      ..offsetAnimation = offset
      ..transformAnimation = transform;
  }
}

/// Slides its child by [offset], animating whenever the offset changes,
/// without ever laying anything out.
///
/// The first user of the node-only path and the proof that the category is
/// real: this is Flutter's `AnimatedSlide`, except that where Flutter's
/// rebuilds a `FractionalTranslation` on every frame, this one rebuilds
/// nothing. A target change costs one rebuild; the run costs one `Matrix4`
/// per frame, written onto one scene node.
///
/// Because nothing moves in the layout, a ray still finds the child where
/// layout put it. That is what you want of a hover lift or a press
/// depression, and what you do not want if the slide is meant to carry the
/// control's touch target with it — for that, animate a real
/// [ScenePositioned3d] inset with [SceneAnimatedPositioned3d] and pay for the
/// relayout.
///
/// [offset] is in layout units, not fractions of the child: a scene has a
/// unit contract ([Layout3dMetrics]) and a lift is naturally stated in it.
///
/// ```dart
/// SceneAnimatedSlide3d(
///   duration: const Duration(milliseconds: 120),
///   curve: Curves.easeOut,
///   // Toward the viewer is negative depth.
///   offset: pressed ? const Offset3d(0, 0, 0.01) : Offset3d.zero,
///   child: button,
/// )
/// ```
class SceneAnimatedSlide3d extends StatefulWidget {
  /// Creates a node-only slide.
  const SceneAnimatedSlide3d({
    super.key,
    required this.offset,
    required this.duration,
    this.curve = Curves.linear,
    this.child,
  });

  /// Where the child's geometry sits, relative to where layout put it.
  final Offset3d offset;

  /// How long a change takes to settle.
  final Duration duration;

  /// The curve the slide follows.
  final Curve curve;

  /// The widget below this one in the tree.
  final Widget? child;

  @override
  State<SceneAnimatedSlide3d> createState() => _SceneAnimatedSlide3dState();
}

class _SceneAnimatedSlide3dState extends State<SceneAnimatedSlide3d>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: widget.duration,
    value: 1.0,
    vsync: this,
  );
  late CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );
  late final Offset3dTween _tween = Offset3dTween(
    begin: widget.offset,
    end: widget.offset,
  );
  late Animation<Offset3d> _animation = _tween.animate(_curved);

  @override
  void didUpdateWidget(SceneAnimatedSlide3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (widget.curve != oldWidget.curve) {
      final previous = _curved;
      _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
      _animation = _tween.animate(_curved);
      previous.dispose();
    }
    if (widget.offset == oldWidget.offset) return;
    // Retarget in place: the animation object handed to the box below stays
    // the same instance, so the retarget costs one rebuild of this widget and
    // nothing at all below it.
    _tween
      ..begin = _animation.value
      ..end = widget.offset;
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
      SceneNodeTransform3d(offset: _animation, child: widget.child);
}

/// The declarative form of [MotionTransition3d]: a subtree that arrives.
///
/// Give it the animation a route carries and a [Motion3d] saying where the
/// content starts, and the subtree moves from there to rest without anything
/// being laid out again:
///
/// ```dart
/// SceneMotionTransition3d(
///   animation: route.animation,
///   motion: const Motion3d.grow(),
///   child: Dialog3d(child: choices),
/// )
/// ```
///
/// A route built with `WidgetPageRoute3d(motion: ...)` is already wrapped in
/// one of these, so this is for the content that wants the box somewhere
/// other than around the whole page — inside a scrim rather than around it,
/// which is exactly where a catalogue's own modal frame puts it.
class SceneMotionTransition3d extends SingleChildLayout3dWidget {
  /// Creates a box that moves [child] from [motion] to rest.
  const SceneMotionTransition3d({
    super.key,
    this.animation,
    this.motion = Motion3d.none,
    super.child,
  });

  /// How far the content has arrived, from 0 to 1, or null for arrived.
  final Animation<double>? animation;

  /// Where the content stands before it has arrived.
  final Motion3d motion;

  @override
  MotionTransition3d createLayout(BuildContext context) =>
      MotionTransition3d(animation: animation, motion: motion);

  @override
  void updateLayout(BuildContext context, MotionTransition3d layout) {
    layout
      ..animation = animation
      ..motion = motion;
  }
}
