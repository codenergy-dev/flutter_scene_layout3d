import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_scene/scene.dart' show Camera;
import 'package:vector_math/vector_math.dart' show Vector3;

import '../geometry/offset3d.dart';
import '../layout3d.dart';

/// Where a laid-out box ended up on screen.
///
/// Layout knows where every box is. A camera knows how to turn a world point
/// into a pixel. Composing the two answers a question nothing else here can:
/// *which pixels should this box be covering?* That is what makes a render
/// test able to check the picture against the layout rather than against a
/// stored image — the layout is the oracle, and a golden file is not needed.
///
/// It is also the honest way to drive a debug overlay, an editor selection
/// rectangle, or a tooltip anchored to a box in the scene.
///
/// Everything here needs the box to be **mounted in a scene and laid out**;
/// [Layout3d.worldTransform] is meaningless before that. A projection is only
/// as current as the last flush, so read it after one, not before.
extension Layout3dScreenProjection on Layout3d {
  /// The box's centre, projected to a pixel in a view of [viewSize].
  ///
  /// Null when the centre is at or behind the camera plane, where it has no
  /// on-screen position at all. A point merely *outside* the view still
  /// returns an offset — negative, or past [viewSize] — because "off to the
  /// left" and "behind you" are different answers and callers usually want to
  /// tell them apart.
  Offset? screenCenter(Camera camera, Size viewSize) =>
      screenPointOf(const Offset3d(0.5, 0.5, 0.5), camera, viewSize);

  /// A point inside the box, given as a fraction of its own extent, projected
  /// to a pixel.
  ///
  /// `Offset3d.zero` is the box's origin corner (left, top, front — see the
  /// coordinate model), `Offset3d(1, 1, 1)` the opposite one, and
  /// `Offset3d(0.5, 0.5, 0.5)` the centre. Fractions outside `[0, 1]` are
  /// allowed and project the space around the box, which is how a test checks
  /// that a *gap* is empty.
  Offset? screenPointOf(Offset3d fraction, Camera camera, Size viewSize) {
    if (!hasSize) return null;
    final extent = size;
    final local = Vector3(
      extent.width * fraction.x,
      extent.height * fraction.y,
      extent.depth * fraction.z,
    );
    return camera.worldToScreen(worldTransform.transformed3(local), viewSize);
  }

  /// The screen-space bounding box of the box's eight corners.
  ///
  /// A perspective projection does not map a cuboid to a rectangle, so this is
  /// the *bounds* of the projected shape and not its outline: it is the right
  /// thing for "is there geometry roughly here", and the wrong thing for a
  /// precise silhouette. Null when the box is not laid out, or when any corner
  /// falls at or behind the camera plane — a partially-behind box has no
  /// meaningful screen rectangle.
  Rect? screenBounds(Camera camera, Size viewSize) {
    if (!hasSize) return null;
    double? left, top, right, bottom;
    for (var corner = 0; corner < 8; corner++) {
      final point = screenPointOf(
        Offset3d(
          (corner & 1) == 0 ? 0 : 1,
          (corner & 2) == 0 ? 0 : 1,
          (corner & 4) == 0 ? 0 : 1,
        ),
        camera,
        viewSize,
      );
      if (point == null) return null;
      left = left == null ? point.dx : (point.dx < left ? point.dx : left);
      right = right == null ? point.dx : (point.dx > right ? point.dx : right);
      top = top == null ? point.dy : (point.dy < top ? point.dy : top);
      bottom = bottom == null
          ? point.dy
          : (point.dy > bottom ? point.dy : bottom);
    }
    return Rect.fromLTRB(left!, top!, right!, bottom!);
  }
}
