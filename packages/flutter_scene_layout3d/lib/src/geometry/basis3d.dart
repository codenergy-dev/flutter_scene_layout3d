import 'package:vector_math/vector_math.dart' show Aabb3, Matrix4, Vector3;

import 'offset3d.dart';
import 'size3d.dart';

/// The mapping between layout space and the scene space of the surface's
/// node.
///
/// Layout space is Flutter's coordinate system with a depth axis: `x` right,
/// `y` **down**, `z` **away from the viewer**. Scene space is the engine's:
/// `x` right, `y` up, `z` toward the viewer. Every layout in the tree does
/// its arithmetic in layout space, so `Column3d` and `Align3d` are direct
/// ports of their Flutter counterparts, and the surface applies this basis
/// once at the root to put the whole plane into the scene.
///
/// [xy] stands the plane up facing the camera, the default and the right
/// choice for panels and HUDs. [xz] lays it flat on the ground, for boards,
/// maps, and floor grids. [fromMatrix] takes any invertible matrix, so a
/// plane can sit at any angle; note that a non-axis-aligned basis makes an
/// element's measured size the size of its *enclosing* box in layout space.
///
/// This is only the plane's internal orientation. Moving, turning, or scaling
/// the whole plane is done on the surface's [Node], and the children follow
/// because they are its descendants.
class LayoutBasis3d {
  LayoutBasis3d._(this._toScene, this._toLayout, this.debugLabel);

  /// A basis from an arbitrary invertible [toScene] matrix, which maps a
  /// layout-space point to the surface node's local space.
  factory LayoutBasis3d.fromMatrix(Matrix4 toScene, {String? debugLabel}) {
    final forward = Matrix4.copy(toScene);
    final inverse = Matrix4.zero();
    final determinant = inverse.copyInverse(forward);
    assert(
      determinant != 0.0,
      'A LayoutBasis3d matrix must be invertible; $toScene is singular.',
    );
    return LayoutBasis3d._(forward, inverse, debugLabel ?? 'custom');
  }

  /// An upright plane facing the camera: layout `x` is scene `+x`, layout `y`
  /// (down) is scene `-y`, layout `z` (away) is scene `-z`.
  static final LayoutBasis3d xy = LayoutBasis3d._(
    Matrix4.diagonal3Values(1, -1, -1),
    Matrix4.diagonal3Values(1, -1, -1),
    'xy',
  );

  /// A plane lying on the ground, seen from above: layout `x` is scene `+x`,
  /// layout `y` (down the page) is scene `+z`, layout `z` (away from the
  /// viewer, into the page) is scene `-y`.
  static final LayoutBasis3d xz = LayoutBasis3d.fromMatrix(
    // Column major: layout x -> scene +x, layout y -> scene +z,
    // layout z -> scene -y.
    Matrix4(1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1),
    debugLabel: 'xz',
  );

  final Matrix4 _toScene;
  final Matrix4 _toLayout;

  /// A short name for this basis, used in `toString`.
  final String debugLabel;

  /// The matrix mapping layout space to the surface node's local space.
  ///
  /// A copy; mutating it does not affect this basis.
  Matrix4 get toSceneMatrix => Matrix4.copy(_toScene);

  /// The matrix mapping the surface node's local space to layout space.
  ///
  /// A copy; mutating it does not affect this basis.
  Matrix4 get toLayoutMatrix => Matrix4.copy(_toLayout);

  /// [offset] as a point in the surface node's local space.
  Vector3 offsetToScene(Offset3d offset) =>
      _toScene.transformed3(Vector3(offset.x, offset.y, offset.z));

  /// A point in the surface node's local space as a layout-space offset.
  Offset3d offsetToLayout(Vector3 point) {
    final mapped = _toLayout.transformed3(Vector3.copy(point));
    return Offset3d(mapped.x, mapped.y, mapped.z);
  }

  /// [bounds], measured in scene space, as an axis-aligned box in layout
  /// space.
  ///
  /// This is how content authored in the engine's coordinates reports a
  /// [Size3d] to the layout protocol. For an axis-aligned basis the extents
  /// are simply permuted; for a rotated one the result is the enclosing box,
  /// which is the conservative answer a layout can act on.
  Aabb3 boundsToLayout(Aabb3 bounds) =>
      Aabb3.copy(bounds)..transform(_toLayout);

  /// The layout-space extents of scene-space [bounds].
  Size3d sizeOfBounds(Aabb3 bounds) {
    final layoutBounds = boundsToLayout(bounds);
    final min = layoutBounds.min;
    final max = layoutBounds.max;
    return Size3d(max.x - min.x, max.y - min.y, max.z - min.z);
  }

  /// The layout-space center of scene-space [bounds].
  Offset3d centerOfBounds(Aabb3 bounds) {
    final center = boundsToLayout(bounds).center;
    return Offset3d(center.x, center.y, center.z);
  }

  @override
  String toString() => 'LayoutBasis3d.$debugLabel';
}
