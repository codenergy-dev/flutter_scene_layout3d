import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;

import '../geometry/offset3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import '../scroll/scrollable.dart';
import '../surface.dart';

/// A pointer aimed at a layout surface: hit testing, plus the drag that
/// scrolls what it grabbed.
///
/// Feed it the ray the camera makes from a screen position and call [down],
/// [move], and [up] as the events arrive:
///
/// ```dart
/// Listener(
///   onPointerDown: (event) => pointer.down(rayFor(event)),
///   onPointerMove: (event) => pointer.move(rayFor(event)),
///   onPointerUp: (event) => pointer.up(),
///   child: SceneView(scene: scene, camera: camera),
/// )
///
/// Ray rayFor(PointerEvent event) =>
///     camera.screenPointToRay(event.localPosition, viewSize);
/// ```
///
/// The drag measures where the pointer lands *on the grabbed view's own
/// plane*, not how far it moved across the screen, so the content stays under
/// the finger whatever angle the plane is seen from, and perspective is
/// accounted for by construction. Once a view is grabbed it keeps the drag
/// until [up], the ordinary pointer-capture rule, so sliding off the end of a
/// list does not drop it.
///
/// There is no fling: [Scroll3dController] holds a position and nothing else
/// (see its own docs for why). A release stops the movement dead. An
/// application that wants momentum can read [draggedScrollable] on [up] and
/// drive the controller from its own animation.
class Layout3dPointer {
  /// Creates a pointer into [surface].
  Layout3dPointer(this.surface);

  /// The surface this pointer tests against.
  final Layout3dSurface surface;

  HitTestResult3d _lastHit = HitTestResult3d();

  /// What the last [hitTest], [down], or [move] found.
  HitTestResult3d get lastHit => _lastHit;

  Layout3d? _dragged;
  Axis3d _dragAxis = Axis3d.vertical;
  double _dragDepth = 0.0;
  double _lastAlong = 0.0;

  /// The view this pointer is dragging, or null.
  Scrollable3d? get draggedScrollable => _dragged as Scrollable3d?;

  /// Whether a drag is in progress.
  bool get isDragging => _dragged != null;

  /// What [worldRay] hits, without touching the drag state.
  HitTestResult3d hitTest(Ray worldRay) =>
      _lastHit = surface.hitTestRay(worldRay);

  /// Starts a press along [worldRay].
  ///
  /// Returns true when it grabbed a scrolling view, which is the caller's cue
  /// that later moves mean something. A press that hits something else still
  /// records [lastHit]; a press that hits nothing clears it.
  bool down(Ray worldRay) {
    final hit = hitTest(worldRay);
    final entry = hit.entryOf<Scrollable3d>();
    if (entry == null) {
      _dragged = null;
      return false;
    }
    final scrollable = entry.layout as Scrollable3d;
    _dragged = entry.layout;
    _dragAxis = scrollable.scrollAxis;
    _dragDepth = entry.localPosition.z;
    _lastAlong = entry.localPosition.alongAxis(_dragAxis);
    return true;
  }

  /// Continues the drag along [worldRay].
  ///
  /// Returns true when the scroll position moved. False means either that
  /// nothing was grabbed, or that the ray now runs parallel to the grabbed
  /// view's plane and there is no sensible place to say the pointer is.
  bool move(Ray worldRay) {
    final dragged = _dragged;
    if (dragged == null) return false;
    final position = _positionOn(dragged, worldRay, _dragDepth);
    if (position == null) return false;
    final along = position.alongAxis(_dragAxis);
    final delta = along - _lastAlong;
    _lastAlong = along;
    if (delta == 0.0) return false;
    // Dragging the content one way moves the window the other way, the same
    // sense as a finger on a Flutter list.
    (dragged as Scrollable3d).controller.jumpBy(-delta);
    return true;
  }

  /// Ends the press. Safe to call when nothing was grabbed.
  void up() => _dragged = null;

  /// Where [worldRay] crosses the plane at [depth] in [layout]'s own frame,
  /// or null when it runs parallel to it.
  ///
  /// The plane is the one the grab happened on, so a drag that wanders off
  /// the view, or off the surface entirely, still resolves to a position the
  /// view can be scrolled by.
  static Offset3d? _positionOn(Layout3d layout, Ray worldRay, double depth) {
    final toLayout = Matrix4.zero();
    if (toLayout.copyInverse(layout.worldTransform) == 0.0) return null;
    final origin = toLayout.transformed3(Vector3.copy(worldRay.origin));
    final direction = toLayout.rotated3(Vector3.copy(worldRay.direction));
    if (direction.z.abs() < _parallel) return null;
    final t = (depth - origin.z) / direction.z;
    if (!t.isFinite || t < 0.0) return null;
    return Offset3d(
      origin.x + direction.x * t,
      origin.y + direction.y * t,
      origin.z + direction.z * t,
    );
  }

  static const double _parallel = 1e-9;
}
