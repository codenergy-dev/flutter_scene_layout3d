// Shared helpers for the layout tests.

import 'package:flutter/foundation.dart' show ChangeNotifier, FlutterError;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// A leaf that asks for [preferred] and settles for what the constraints
/// allow, standing in for real content.
class TestBox extends Layout3d {
  TestBox(this._preferred, {this.pointable = false, this.minimum, super.name});

  /// Whether this box answers hit tests on its own account, the way a
  /// [NodeBox3d] holding real content does.
  final bool pointable;

  /// What this box reports as its minimum intrinsic extent, when that should
  /// differ from [preferred].
  final Size3d? minimum;

  /// How many intrinsic queries have reached this box, so a test can tell a
  /// cached answer from a recomputed one.
  int intrinsicQueries = 0;

  /// The limits of the most recent intrinsic query.
  Size3d? lastIntrinsicLimits;

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) {
    intrinsicQueries++;
    lastIntrinsicLimits = limits;
    return (minimum ?? _preferred).alongAxis(axis);
  }

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) {
    intrinsicQueries++;
    lastIntrinsicLimits = limits;
    return _preferred.alongAxis(axis);
  }

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

/// A box that asks for a size stated in logical pixels, the way a component
/// in the catalogue will.
///
/// The point of it is that the size is not a constant: it is read back out of
/// the tree's [Layout3d.metrics] on every layout, so a change to the unit
/// contract shows up as a different box.
class DpBox extends Layout3d {
  DpBox(this.widthDp, this.heightDp, {this.depthDp = 0.0, super.name});

  /// The width this box asks for, in logical pixels.
  final double widthDp;

  /// The height this box asks for, in logical pixels.
  final double heightDp;

  /// The depth this box asks for, in logical pixels.
  final double depthDp;

  /// How many times this box has been laid out.
  int layoutCount = 0;

  @override
  void performLayout() {
    layoutCount++;
    size = constraints.constrain(
      Size3d(metrics.dp(widthDp), metrics.dp(heightDp), metrics.dp(depthDp)),
    );
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
  Layout3dMetrics metrics = Layout3dMetrics.standard,
  Alignment3d origin = Alignment3d.center,
}) {
  final surface = Layout3dSurface(
    constraints: constraints,
    basis: basis,
    metrics: metrics,
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

void _noop() {}

/// Whether [notifier] has been disposed.
///
/// A `ChangeNotifier` keeps no public flag for it; the only thing it will say
/// is that it refuses to be used again, so that is what this asks. Debug mode
/// only, which is where tests run.
bool isDisposed(ChangeNotifier notifier) {
  try {
    notifier.addListener(_noop);
  } on FlutterError {
    return true;
  }
  notifier.removeListener(_noop);
  return false;
}
