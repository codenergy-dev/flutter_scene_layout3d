import 'package:flutter/animation.dart' show Animation;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../geometry/offset3d.dart';
import '../layout3d.dart';

/// A box that moves its subtree's geometry without the layout ever hearing
/// about it: the node-only animation path.
///
/// ## The category
///
/// Some animations move nothing in the layout. A slide, a hover lift, a
/// pressed depression, a billboard turn — the box is exactly as big as it
/// was, its siblings are exactly where they were, and its children's offsets
/// have not changed. In Flutter that is still a repaint of a layer; here it
/// is one `Matrix4` written onto one scene node, and the layout pipeline is
/// not involved at all.
///
/// That matters more here than it sounds, because relayout cost compounds in
/// three dimensions. A dirty box is re-measured, and a re-measured box may ask
/// a [Text3d] to shape a string or a decorated box to re-derive a shader's
/// uniforms. Nothing on this path can reach any of that, by construction:
/// [Layout3d.nodeOffset] and [Layout3d.nodeTransform] are plain setters that
/// rewrite a transform and ask the host for a frame. Use it for every
/// animation that does not change a size, and reach for
/// [ImplicitlyAnimatedLayout3dWidget] only for the ones that do.
///
/// ## What it is not
///
/// It is not [Transform3d]. That box puts a real change of frame between
/// itself and its child: its child's offsets, the clip it inherits and the
/// ray that reaches it are all taken through the matrix, and changing it is a
/// relayout. This box's transform is invisible to every one of those. A ray
/// still finds the button where layout put it, which is exactly what you want
/// of a hover lift and exactly what you do not want of a genuine rotation
/// that the viewer is meant to aim at.
///
/// ## Using it
///
/// Drive it from an [Animation]; the box listens and writes each value
/// straight through, so no widget rebuilds and no box is marked dirty for the
/// whole run:
///
/// ```dart
/// final lift = Tween<Offset3d>(
///   begin: Offset3d.zero,
///   end: const Offset3d(0, 0, -0.05),
/// ).animate(pressController);
/// final button = NodeTransform3d(offsetAnimation: lift, child: chrome);
/// ```
///
/// A value that is not animated at all needs none of this: every box has
/// [Layout3d.nodeOffset], so a static nudge is a single assignment on the box
/// itself.
class NodeTransform3d extends ProxyLayout3d {
  /// Creates a node-only animation box driven by [offset] and [transform].
  NodeTransform3d({
    Animation<Offset3d>? offsetAnimation,
    Animation<Matrix4>? transformAnimation,
    super.child,
    super.name,
  }) : _offset = offsetAnimation,
       _transform = transformAnimation {
    offsetAnimation?.addListener(_handleOffsetChanged);
    transformAnimation?.addListener(_handleTransformChanged);
    if (offsetAnimation != null) nodeOffset = offsetAnimation.value;
    if (transformAnimation != null) nodeTransform = transformAnimation.value;
  }

  Animation<Offset3d>? _offset;

  /// The animation driving [Layout3d.nodeOffset], or null.
  ///
  /// Named for the animation rather than the value because [Layout3d.offset]
  /// is already taken, and means something quite different: where the parent
  /// put this box.
  Animation<Offset3d>? get offsetAnimation => _offset;

  set offsetAnimation(Animation<Offset3d>? value) {
    if (identical(_offset, value)) return;
    _offset?.removeListener(_handleOffsetChanged);
    _offset = value?..addListener(_handleOffsetChanged);
    nodeOffset = value?.value ?? Offset3d.zero;
  }

  Animation<Matrix4>? _transform;

  /// The animation driving [Layout3d.nodeTransform], or null.
  Animation<Matrix4>? get transformAnimation => _transform;

  set transformAnimation(Animation<Matrix4>? value) {
    if (identical(_transform, value)) return;
    _transform?.removeListener(_handleTransformChanged);
    _transform = value?..addListener(_handleTransformChanged);
    nodeTransform = value?.value;
  }

  void _handleOffsetChanged() => nodeOffset = _offset!.value;

  void _handleTransformChanged() => nodeTransform = _transform!.value;

  @override
  void dispose() {
    _offset?.removeListener(_handleOffsetChanged);
    _transform?.removeListener(_handleTransformChanged);
    super.dispose();
  }
}
