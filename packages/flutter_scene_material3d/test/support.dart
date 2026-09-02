// Shared helpers for the material3d tests.

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:vector_math/vector_math.dart' show Ray, Vector3;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart' show Layout3dWidget;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';

/// A surface holding [child], already laid out.
Layout3dSurface laidOut(
  Layout3d child, {
  Constraints3d constraints = const Constraints3d(),
  Layout3dMetrics metrics = Layout3dMetrics.standard,
}) {
  final surface = Layout3dSurface(
    constraints: constraints,
    metrics: metrics,
    child: child,
  );
  surface.flush();
  return surface;
}

/// A box that sizes itself from the theme, the way a real component will.
///
/// It reads a token (a thickness, in logical pixels) and converts it with the
/// metrics, which is the one-way arrow the token layer exists to enforce:
/// the theme decides the dp figure, the metrics turns dp into world units.
class ThemedBox extends Layout3d {
  ThemedBox({super.name});

  /// How many times this box has been laid out.
  int layoutCount = 0;

  /// The theme seen on the last layout.
  Theme3dData? sawTheme;

  /// Whether a theme was actually published on the last layout.
  bool sawPublishedTheme = false;

  @override
  void performLayout() {
    layoutCount++;
    sawTheme = theme3d;
    sawPublishedTheme = hasTheme3d;
    final thickness = metrics.dp(theme3d.thickness.raised);
    final height = metrics.dp(40.0);
    size = constraints.constrain(Size3d(height, height, thickness));
  }
}

/// A leaf that asks for [preferred] and settles for what the constraints
/// allow, standing in for the content of a component.
///
/// A copy of the layout package's own `TestBox`, because a test package
/// cannot import another package's `test/` directory. It counts its layouts,
/// which is what the interaction tests are actually about.
class TestBox extends Layout3d {
  TestBox(this._preferred, {super.name});

  Size3d _preferred;

  /// What this box asks for, before the constraints have their say.
  Size3d get preferred => _preferred;

  set preferred(Size3d value) {
    if (_preferred == value) return;
    _preferred = value;
    markParentNeedsLayout();
  }

  /// How many times this box has been laid out.
  int layoutCount = 0;

  /// The constraints the parent handed down on the last layout.
  Constraints3d? lastConstraints;

  @override
  void performLayout() {
    layoutCount++;
    lastConstraints = constraints;
    size = constraints.constrain(_preferred);
  }
}

/// Hosts a [TestBox] in the widget tree and hands it back, so a test can
/// count the layouts a rebuild actually causes.
class SceneTestBox extends Layout3dWidget {
  const SceneTestBox(this.preferred, this.onCreated, {super.key});

  /// What the box asks for.
  final Size3d preferred;

  /// Called with the box the first time it is created.
  final void Function(TestBox box) onCreated;

  @override
  TestBox createLayout(BuildContext context) {
    final box = TestBox(preferred);
    onCreated(box);
    return box;
  }

  @override
  void updateLayout(BuildContext context, TestBox layout) {
    layout.preferred = preferred;
  }
}

/// The one [DecoratedBox3d] in [surface], which is the panel a `Material3d`
/// draws.
///
/// A component is a small tree — a decorated box over a container over the
/// child — and a test that reached for it by walking `child!.child!` would
/// break the first time the composition changed. This asks the tree what is
/// in it instead.
DecoratedBox3d decoratedBoxIn(Layout3dSurface surface) {
  final found = <DecoratedBox3d>[];
  void walk(Layout3d box) {
    if (box is DecoratedBox3d) found.add(box);
    box.visitChildren(walk);
  }

  walk(surface.child!);
  if (found.length != 1) {
    throw StateError('expected one DecoratedBox3d, found ${found.length}');
  }
  return found.single;
}

/// A ray aimed straight at [point] on [surface]'s plane, from in front of it.
///
/// A copy of the layout package's own test helper, for the same reason
/// [TestBox] is one.
Ray rayAt(Layout3dSurface surface, Offset3d point) {
  final toWorld = surface.node.globalTransform;
  final origin = toWorld.transformed3(
    Vector3(point.x, point.y, point.z - 10.0),
  );
  final direction = toWorld.rotated3(Vector3(0, 0, 1));
  return Ray.originDirection(origin, direction);
}

/// The one [Focus3d] in [surface], which is the focusable box an `InkWell3d`
/// installs.
///
/// Focusing it through this rather than through a bare `FocusNode` matters:
/// [Focus3d.requestFocus] is what reparents the node into the *surface's*
/// focus scope, and a node that was never parented there takes no focus at
/// all however often it is asked.
Focus3d focusIn(Layout3dSurface surface) {
  final found = <Focus3d>[];
  void walk(Layout3d box) {
    if (box is Focus3d) found.add(box);
    box.visitChildren(walk);
  }

  walk(surface.child!);
  if (found.length != 1) {
    throw StateError('expected one Focus3d, found ${found.length}');
  }
  return found.single;
}
