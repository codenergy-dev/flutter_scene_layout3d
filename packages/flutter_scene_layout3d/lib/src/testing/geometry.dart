import '../geometry/offset3d.dart';
import '../layout3d.dart';
import 'scene.dart';

/// Where a box is, asked the way a test asks it.
extension Layout3dTestGeometry on Layout3d {
  /// Where this box's front, top, left corner is **drawn**, in the layout
  /// frame of the surface at the root of its tree.
  ///
  /// Every offset between the surface and the box counts, the box's own
  /// included: the one layout gave each box, the depth step a `Stack3d`
  /// writes into `sceneOffset`, and the `nodeOffset` and `nodeTransform` an
  /// animation or a lift puts on the node. That is where the geometry is, so
  /// it is the frame to compare two boxes' depths in, and the frame a ray aimed
  /// straight down the surface's depth axis at a point of the box is aimed in.
  ///
  /// The name says which frame on purpose. A box's own `offset` is relative to
  /// its parent, and the sum of those alone is where layout put the slot — a
  /// different answer whenever anything above the box was nudged. This
  /// repository's own tests carried two helpers called `offsetInSurface`, one
  /// that summed the `sceneOffset` and one that did not, and nothing said
  /// which a test was getting.
  ///
  /// Meaningful once the box is mounted and laid out; a box that is not under
  /// a surface throws a [StateError].
  Offset3d get drawnOffsetInSurface {
    final surface = rootSurfaceOf(this);
    if (surface == null) {
      throw StateError('${describeBox3d(this)} is not under a surface.');
    }
    return drawnCornerIn(surface, this);
  }
}
