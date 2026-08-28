import 'package:flutter/animation.dart' show Tween;

import '../decoration/box_decoration.dart';
import '../decoration/decoration.dart';
import '../geometry/alignment3d.dart';
import '../geometry/border_radius3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/edge_insets3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';

/// Interpolates between two [Size3d]s.
///
/// Every value type in this package already carries a static `lerp`, so a
/// tween is a two-line adapter onto Flutter's [Tween]. They exist so that the
/// implicit animations, and any [AnimationController] an application drives
/// itself, can use the ordinary `tween.animate(controller)` spelling rather
/// than reaching for the `lerp` by hand.
///
/// Like every [Tween], this one interpolates the *whole* value linearly:
/// three extents moving independently, which is what
/// [ImplicitlyAnimatedLayout3dWidget] wants and what a caller wanting
/// something else (a size that keeps its aspect ratio, say) should build with
/// a [TweenSequence] or a custom `lerp` instead.
class Size3dTween extends Tween<Size3d> {
  /// Creates a tween between two sizes.
  Size3dTween({super.begin, super.end});

  @override
  Size3d lerp(double t) => Size3d.lerp(begin!, end!, t);
}

/// Interpolates between two [Offset3d]s.
///
/// The tween behind [SceneAnimatedPositioned3d] and, on the node-only path,
/// [SceneAnimatedSlide3d].
class Offset3dTween extends Tween<Offset3d> {
  /// Creates a tween between two offsets.
  Offset3dTween({super.begin, super.end});

  @override
  Offset3d lerp(double t) => Offset3d.lerp(begin!, end!, t);
}

/// Interpolates between two [EdgeInsets3d]s.
class EdgeInsets3dTween extends Tween<EdgeInsets3d> {
  /// Creates a tween between two insets.
  EdgeInsets3dTween({super.begin, super.end});

  @override
  EdgeInsets3d lerp(double t) => EdgeInsets3d.lerp(begin!, end!, t);
}

/// Interpolates between two [Alignment3d]s.
class Alignment3dTween extends Tween<Alignment3d> {
  /// Creates a tween between two alignments.
  Alignment3dTween({super.begin, super.end});

  @override
  Alignment3d lerp(double t) => Alignment3d.lerp(begin!, end!, t);
}

/// Interpolates between two [Constraints3d].
///
/// Infinite bounds interpolate to themselves rather than through a finite
/// number, which is [Constraints3d.lerp]'s rule and not this class's; a tween
/// from a bounded to an unbounded constraint therefore snaps rather than
/// growing without limit.
class Constraints3dTween extends Tween<Constraints3d> {
  /// Creates a tween between two sets of constraints.
  Constraints3dTween({super.begin, super.end});

  @override
  Constraints3d lerp(double t) => Constraints3d.lerp(begin!, end!, t);
}

/// Interpolates between two [BorderRadius3d]s.
class BorderRadius3dTween extends Tween<BorderRadius3d> {
  /// Creates a tween between two corner radii.
  BorderRadius3dTween({super.begin, super.end});

  @override
  BorderRadius3d lerp(double t) => BorderRadius3d.lerp(begin!, end!, t);
}

/// Interpolates between two [BoxDecoration3d]s.
///
/// The cheapest animation in the package and the one Material asks for most:
/// [DecoratedBox3d.decoration] is a setter that repaints and never relayouts,
/// so a colour, a corner or an elevation animating through this tween writes
/// shader uniforms per frame and touches the layout pipeline not at all. Give
/// its value to the setter from an [AnimationController] listener rather than
/// from `setState`, and no box is ever marked dirty.
class BoxDecoration3dTween extends Tween<BoxDecoration3d> {
  /// Creates a tween between two decorations.
  BoxDecoration3dTween({super.begin, super.end});

  @override
  BoxDecoration3d lerp(double t) => BoxDecoration3d.lerp(begin!, end!, t);
}

/// Interpolates between two [StateLayer3d]s.
///
/// The hover, focus and press overlay a control wears. On the same
/// repaint-only path as [BoxDecoration3dTween]; see there.
class StateLayer3dTween extends Tween<StateLayer3d> {
  /// Creates a tween between two state layers.
  StateLayer3dTween({super.begin, super.end});

  @override
  StateLayer3d lerp(double t) => StateLayer3d.lerp(begin!, end!, t);
}
