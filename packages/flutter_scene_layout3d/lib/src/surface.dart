import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'geometry/alignment3d.dart';
import 'geometry/basis3d.dart';
import 'geometry/constraints3d.dart';
import 'geometry/offset3d.dart';
import 'geometry/size3d.dart';
import 'layout3d.dart';

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
  /// [plane] node's origin, and defaults to the center.
  Layout3dSurface({
    Constraints3d constraints = const Constraints3d(),
    LayoutBasis3d? basis,
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
    markNeedsLayout();
    applyNodeTransform();
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
    _plane.remove(node);
  }
}
