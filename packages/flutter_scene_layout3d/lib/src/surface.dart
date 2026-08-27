import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;

import 'geometry/alignment3d.dart';
import 'geometry/basis3d.dart';
import 'geometry/constraints3d.dart';
import 'geometry/offset3d.dart';
import 'geometry/size3d.dart';
import 'hit_test.dart';
import 'layout3d.dart';
import 'metrics.dart';

/// The root of a 3D layout: the plane its children are arranged on.
///
/// The surface is where the two coordinate systems meet. Everything above it
/// in this package works in layout space (`x` right, `y` down, `z` away),
/// so the layouts are ports of Flutter's; the surface applies a
/// [LayoutBasis3d] once, at the root, to put that plane into the scene.
///
/// Mount [plane] in the scene graph and transform *that* node to move, turn,
/// or scale the whole layout; the children are its descendants, so they
/// follow. Do not write to the surface's own [node]: it carries the basis and
/// is rewritten on every layout.
///
/// ```dart
/// final surface = Layout3dSurface(
///   constraints: Constraints3d.tight(const Size3d(4, 3, 0.5)),
///   child: Column3d(
///     mainAxisAlignment: MainAxisAlignment3d.center,
///     children: [NodeBox3d(content: cube), NodeBox3d(content: sphere)],
///   ),
/// );
/// scene.root.add(surface.plane);
/// surface.plane.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), 0.4);
/// surface.flush();
/// ```
class Layout3dSurface extends SingleChildLayout3d {
  /// Creates a layout surface.
  ///
  /// [constraints] is what the root child is laid out against; a tight one
  /// gives the plane a fixed extent, an unbounded one lets it shrink-wrap its
  /// content. [origin] says which point of the laid-out box sits at the
  /// [plane] node's origin, and defaults to the center. [metrics] is the unit
  /// contract the whole tree is specified in, and defaults to the authored
  /// one; bind the surface to a camera to have it derived instead.
  Layout3dSurface({
    Constraints3d constraints = const Constraints3d(),
    LayoutBasis3d? basis,
    Layout3dMetrics metrics = Layout3dMetrics.standard,
    Alignment3d origin = Alignment3d.center,
    VoidCallback? onNeedVisualUpdate,
    super.child,
    String? name,
  }) : _configuration = constraints,
       _origin = origin,
       super(name: name ?? 'Layout3dSurface.basis') {
    _plane.name = name ?? 'Layout3dSurface';
    _plane.add(node);
    _owner
      ..basis = basis ?? LayoutBasis3d.xy
      ..metrics = metrics
      ..onNeedVisualUpdate = onNeedVisualUpdate;
    attach(_owner);
    applyNodeTransform();
  }

  final Layout3dOwner _owner = Layout3dOwner();

  final Node _plane = Node();

  /// The node to mount in the scene and transform.
  ///
  /// Its transform is yours: set `position`, `rotation`, and `scale` on it to
  /// place the plane in the world. Everything laid out on the surface hangs
  /// below it.
  Node get plane => _plane;

  Constraints3d _configuration;

  /// The constraints the root child is laid out against.
  Constraints3d get configuration => _configuration;

  set configuration(Constraints3d value) {
    if (_configuration == value) return;
    assert(value.isNormalized);
    _configuration = value;
    markNeedsLayout();
  }

  Alignment3d _origin;

  /// The point of the laid-out box that sits at [plane]'s origin.
  Alignment3d get origin => _origin;

  set origin(Alignment3d value) {
    if (_origin == value) return;
    _origin = value;
    applyNodeTransform();
  }

  @override
  LayoutBasis3d get basis => _owner.basis;

  /// Sets the mapping from layout space to the plane's scene space.
  ///
  /// Changing it relayouts, because content measured through the old basis
  /// (a [NodeBox3d] reading a model's bounds) can report a different size
  /// through the new one.
  set basis(LayoutBasis3d value) {
    if (identical(_owner.basis, value)) return;
    _owner.basis = value;
    // The whole subtree, not just this box: a leaf reads the basis directly
    // rather than being handed it, so a child whose constraints did not
    // change would otherwise be skipped with a stale measurement.
    markSubtreeNeedsLayout();
    applyNodeTransform();
  }

  @override
  Layout3dMetrics get metrics => _owner.metrics;

  /// Sets the unit contract for the whole tree: how many world units a
  /// logical pixel is worth, and the dials a component library reads beside
  /// it.
  ///
  /// The root owns it and every box below reads it through
  /// [Layout3d.metrics]. Set it by hand for a panel whose scale is authored,
  /// or let a [Layout3dCameraBinding] derive it from the view.
  ///
  /// Changing it relayouts the whole subtree, for the same reason changing
  /// the [basis] does: content measured at one density reports a different
  /// size at another. A component sized `metrics.dp(48)` is a different box
  /// after the number changes, and since the number never reaches it as a
  /// constraint, nothing else would tell it so.
  set metrics(Layout3dMetrics value) {
    if (_owner.metrics == value) return;
    _owner.metrics = value;
    markSubtreeNeedsLayout();
  }

  /// Called when something in the tree goes dirty, so a host can schedule a
  /// [flush].
  VoidCallback? get onNeedVisualUpdate => _owner.onNeedVisualUpdate;

  set onNeedVisualUpdate(VoidCallback? value) {
    _owner.onNeedVisualUpdate = value;
  }

  /// Whether anything in this tree is waiting to be laid out.
  bool get needsFlush => needsLayout || _owner.hasPendingLayout;

  /// Lays out everything that changed since the last call.
  ///
  /// Cheap when nothing is dirty, so calling it once per frame before
  /// rendering is fine; the widget layer does exactly that.
  void flush() {
    layout(_configuration);
    _owner.flushLayout();
  }

  // ------------------------------------------------------------ hit testing

  /// What [worldRay] hits on this surface, deepest layout first.
  ///
  /// The bridge from the scene to the layout tree. Take the ray from the
  /// camera and hand it here:
  ///
  /// ```dart
  /// final ray = camera.screenPointToRay(event.localPosition, viewSize);
  /// final hit = surface.hitTestRay(ray);
  /// hit.firstOf<Scrollable3d>()?.controller.jumpBy(0.1);
  /// ```
  ///
  /// The surface's own node carries the [basis] and the [origin] shift, so
  /// inverting its world transform lands the ray directly in layout space;
  /// everything below that is plain layout arithmetic. Returns an empty
  /// result when the ray misses, and when the surface has not been laid out.
  HitTestResult3d hitTestRay(Ray worldRay) {
    final result = HitTestResult3d();
    if (!hasSize) return result;
    final worldToLayout = Matrix4.zero();
    if (worldToLayout.copyInverse(node.globalTransform) == 0.0) return result;
    final origin = worldToLayout.transformed3(Vector3.copy(worldRay.origin));
    final direction = worldToLayout.rotated3(Vector3.copy(worldRay.direction));
    hitTest(
      result,
      ray: Ray3d(
        Offset3d(origin.x, origin.y, origin.z),
        Offset3d(direction.x, direction.y, direction.z),
      ),
    );
    return result;
  }

  /// What sits at [point] on the plane, looked at head on.
  ///
  /// The 2D-style question, for when the pointer has already been resolved
  /// to a spot on the surface (a widget texture's local position, a test).
  /// The line runs along the depth axis and extends both ways, so content in
  /// front of the plane is found too.
  HitTestResult3d hitTestAt(Offset3d point) {
    final result = HitTestResult3d();
    if (!hasSize) return result;
    hitTest(result, ray: Ray3d.through(point));
    return result;
  }

  /// The surface's basis is not a layout-space transform: it is the change of
  /// space between the plane's node and layout space, and [hitTestRay] has
  /// already undone it by the time the walk starts. The children below sit in
  /// the same frame the surface measures itself in.
  @override
  Matrix4? get hitTestTransform => null;

  @override
  Matrix4? get localTransform {
    final matrix = basis.toSceneMatrix;
    if (!hasSize) return matrix;
    final shift = _origin.alongSize(size);
    return matrix.multiplied(
      Matrix4.translationValues(-shift.x, -shift.y, -shift.z),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size3d.zero);
      applyNodeTransform();
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(child.size);
    child.place(Offset3d.zero);
    // The basis transform depends on the size just chosen, through [origin].
    applyNodeTransform();
  }

  @override
  void dispose() {
    super.dispose();
    _owner.dispose();
    _plane.remove(node);
  }
}
