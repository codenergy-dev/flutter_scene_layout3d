import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import 'geometry/alignment3d.dart';
import 'geometry/offset3d.dart';
import 'layout3d.dart';

/// Putting one box over another when neither is the other's parent.
///
/// The problem an overlay creates and does not solve: an [Overlay3dEntry] is
/// placed by the overlay's own [Stack3d.alignment], which is nowhere near the
/// box that asked for it. A menu belongs at its button, a tooltip under the
/// control it describes, and a picked-up card over the row it came from —
/// three components, one piece of arithmetic, and Flutter's answer to it
/// (`CompositedTransformTarget` and `CompositedTransformFollower`) has no
/// analogue here.
///
/// The arithmetic is a change of frame. Both boxes know where they are in the
/// world — [Layout3d.worldTransform] is exactly that — so the offset from one
/// to the other is the anchor's point taken into the world and back out
/// again in the follower's own frame.
extension Layout3dAnchoring on Layout3d {
  /// The [nodeOffset] that puts this box's [self] point on [anchor]'s
  /// [target] point.
  ///
  /// **Assign it, do not add it:**
  ///
  /// ```dart
  /// final placed = menu.anchorOffsetTo(button, self: Alignment3d.topLeft);
  /// if (placed != null) menu.nodeOffset = placed;
  /// ```
  ///
  /// An absolute position rather than a delta, and the reason is worth
  /// knowing: [worldTransform] deliberately reports the frame layout put this
  /// box in, with [nodeOffset], [sceneOffset] and [nodeTransform] undone. So
  /// the arithmetic never sees where the box has already been nudged to, and
  /// what comes back is where it should be nudged to — which makes
  /// re-anchoring after a scroll or a resize another assignment rather than
  /// an accumulation that drifts.
  ///
  /// **It writes nothing and lays nothing out.** [nodeOffset] is the node
  /// tier — one matrix a frame, no `markNeedsLayout` — which is the only tier
  /// a component may re-anchor on per frame. See *Staying off the relayout
  /// path* in `docs/traps.md`.
  ///
  /// Null when either box has not been laid out yet, or when this box's
  /// transform cannot be inverted (a degenerate scale). A caller that has
  /// just inserted an overlay entry gets null on the frame it inserted it —
  /// the entry has no size until the surface has been flushed — and asks
  /// again on the next one.
  ///
  /// The depth axis is left at whatever [nodeOffset] already carries unless
  /// [includeDepth] is set, and that default is the one that is not obvious.
  /// An entry is lifted toward the viewer by its layer's lift precisely so
  /// that it does not fight the content it is carried over; anchoring in
  /// depth as well would put the follower back on the anchor's own plane and
  /// hand the depth test a coin toss. `Draggable3d` learned that from a
  /// render probe, and this default is that lesson.
  ///
  /// One assumption, the same one the drag lane makes: this box's
  /// [nodeTransform] is the identity. [nodeOffset] is applied before it, so a
  /// rotated follower would need the result rotated back out — which no
  /// caller here wants, since a follower rotated relative to its anchor is
  /// not following it.
  Offset3d? anchorOffsetTo(
    Layout3d anchor, {
    Alignment3d self = Alignment3d.center,
    Alignment3d target = Alignment3d.center,
    bool includeDepth = false,
  }) {
    if (!hasSize || !anchor.hasSize) return null;
    final intoSelf = Matrix4.zero();
    if (intoSelf.copyInverse(worldTransform) == 0.0) return null;
    final wanted = intoSelf.transformed3(
      anchor.worldTransform.transformed3(_pointOf(anchor, target)),
    );
    final here = _pointOf(this, self);
    return Offset3d(
      wanted.x - here.x,
      wanted.y - here.y,
      includeDepth ? wanted.z - here.z : nodeOffset.z,
    );
  }
}

Vector3 _pointOf(Layout3d layout, Alignment3d alignment) {
  final point = alignment.alongSize(layout.size);
  return Vector3(point.x, point.y, point.z);
}
