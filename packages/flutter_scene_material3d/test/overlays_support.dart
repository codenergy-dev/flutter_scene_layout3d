// Shared scaffolding for the phase-6 overlays: dialogs, menus, snack bars,
// tooltips and sheets.
//
// Everything here pumps a real surface with a real `SceneOverlay3d` in it,
// because that is the only place an overlay component works: the entries are
// inserted into the overlay and their content is reconciled by the widget
// layer one frame later.

import 'package:flutter/widgets.dart' show BuildContext, Builder, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Ray, Vector3;

/// Every box of type [T] in [surface], outermost first.
List<T> boxesOf<T extends Layout3d>(Layout3dSurface surface) {
  final found = <T>[];
  void walk(Layout3d box) {
    if (box is T) found.add(box);
    box.visitChildren(walk);
  }

  final child = surface.child;
  if (child != null) walk(child);
  return found;
}

/// The one box of type [T] in [surface].
T oneOf<T extends Layout3d>(Layout3dSurface surface) {
  final found = boxesOf<T>(surface);
  if (found.length != 1) {
    throw StateError('expected one $T, found ${found.length}');
  }
  return found.single;
}

/// Where [box] sits in the surface's own frame, summing the offsets its
/// parents gave it — the scene offsets included, since a `Stack3d`'s depth
/// step is written there and depth is the whole subject here.
Offset3d offsetInSurface(Layout3d box) {
  var total = Offset3d.zero;
  Layout3d? node = box;
  while (node != null && node is! Layout3dSurface) {
    total += node.offset + node.sceneOffset;
    node = node.parent;
  }
  return total;
}

/// A surface with a themed overlay in it, and the handles a test wants.
class PumpedOverlay {
  PumpedOverlay(this.controller, this.overlayController, this.context);

  final Layout3dController controller;
  final Overlay3dController overlayController;

  /// A context inside the overlay, which is what a component that opens
  /// something is handed.
  final BuildContext context;

  Layout3dSurface get surface => controller.surface!;
  Overlay3d get overlay => overlayController.overlay!;

  /// Every panel in the tree, outermost first.
  List<DecoratedBox3d> get panels => boxesOf<DecoratedBox3d>(surface);

  Layout3dPointer? _pointer;

  /// One pointer for the whole test: the sequence between a down and its up
  /// is what holds the captured path.
  Layout3dPointer get pointer => _pointer ??= Layout3dPointer(surface);
}

/// Pumps an overlay over [child], under [theme].
Future<PumpedOverlay> pumpOverlay(
  WidgetTester tester, {
  Widget? child,
  Theme3dData theme = Theme3dData.light,
  Size3d size = const Size3d(8, 6, 1),
  Layout3dMetrics metrics = Layout3dMetrics.standard,
}) async {
  final controller = Layout3dController();
  final overlayController = Overlay3dController();
  late BuildContext captured;
  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      size: size,
      metrics: metrics,
      controller: controller,
      child: SceneTheme3d(
        data: theme,
        child: SceneOverlay3d(
          controller: overlayController,
          child: Builder(
            builder: (context) {
              captured = context;
              return child ?? const SceneSizedBox3d.cube(1);
            },
          ),
        ),
      ),
    ),
  );
  return PumpedOverlay(controller, overlayController, captured);
}

/// A ray aimed straight at [point] on [surface]'s plane, from in front of it.
///
/// A copy of the layout package's own test helper: a test package cannot
/// import another package's `test/` directory.
Ray rayAt(Layout3dSurface surface, Offset3d point) {
  final toWorld = surface.node.globalTransform;
  final origin = toWorld.transformed3(
    Vector3(point.x, point.y, point.z - 10.0),
  );
  final direction = toWorld.rotated3(Vector3(0, 0, 1));
  return Ray.originDirection(origin, direction);
}
