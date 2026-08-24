// Shared helpers for the layout tests.

import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// A leaf that asks for [preferred] and settles for what the constraints
/// allow, standing in for real content.
class TestBox extends Layout3d {
  TestBox(this._preferred, {this.pointable = false, super.name});

  /// Whether this box answers hit tests on its own account, the way a
  /// [NodeBox3d] holding real content does.
  final bool pointable;

  @override
  bool hitTestSelf(Offset3d position) => pointable;

  Size3d _preferred;

  Size3d get preferred => _preferred;

  set preferred(Size3d value) {
    if (_preferred == value) return;
    _preferred = value;
    markParentNeedsLayout();
  }

  /// How many times this box has been laid out.
  int layoutCount = 0;

  /// The constraints handed down by the parent on the last layout.
  Constraints3d? lastConstraints;

  @override
  void performLayout() {
    layoutCount++;
    lastConstraints = constraints;
    size = constraints.constrain(_preferred);
  }
}

/// The translation a layout's own node carries, in layout space.
Offset3d translationOf(Layout3d layout) {
  final translation = layout.node.localTransform.getTranslation();
  return Offset3d(translation.x, translation.y, translation.z);
}

/// Where a node sits in the scene, relative to the surface's plane node.
Vector3 scenePositionOf(Node node) => node.globalTransform.getTranslation();

/// A surface holding [child], already laid out.
Layout3dSurface laidOut(
  Layout3d child, {
  Constraints3d constraints = const Constraints3d(),
  LayoutBasis3d? basis,
  Alignment3d origin = Alignment3d.center,
}) {
  final surface = Layout3dSurface(
    constraints: constraints,
    basis: basis,
    origin: origin,
    child: child,
  );
  surface.flush();
  return surface;
}

/// Matcher-friendly rounding, so floating point noise does not fail a test.
Offset3d rounded(Offset3d offset, [int digits = 6]) {
  double round(double value) {
    final factor = 1.0 * (1 << (digits * 2)).toDouble();
    return (value * factor).roundToDouble() / factor;
  }

  return Offset3d(round(offset.x), round(offset.y), round(offset.z));
}
