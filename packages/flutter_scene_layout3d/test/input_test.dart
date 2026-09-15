// The input host: the widget that turns the platform's pointers into rays
// and routes them to whichever surface is in front, with nothing wired by
// hand.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart'
    show Align, Alignment, SizedBox, Stack, Widget;
import 'package:flutter_scene/scene.dart' show Camera, Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support.dart';

/// A camera in front of the plane, on the `+z` side, which is the side
/// [LayoutBasis3d.xy] puts the viewer on.
///
/// At five units with a 45° lens it takes in a little over four units of
/// height, so a four-unit panel at the origin very nearly fills the 800×600
/// test view and the middle of the view is the middle of the panel.
PerspectiveCamera frontCamera({double distance = 5}) => PerspectiveCamera(
  fovRadiansY: math.pi / 4,
  position: Vector3(0, 0, distance),
  target: Vector3(0, 0, 0),
);

/// The middle of the test view, which is where every press below lands.
const Offset center = Offset(400, 300);

/// A host over [surfaces], filling the view.
///
/// The `SizedBox.expand` stands in for the `SceneView` an application would
/// put here: the host reads its own box to size the rays, and a layout host
/// box takes no space of its own.
Widget hosted(
  List<Widget> surfaces, {
  Camera? camera,
  Input3dController? controller,
  Input3dHitCallback? onHit,
}) => SceneInput3d(
  camera: camera ?? frontCamera(),
  controller: controller,
  onHit: onHit,
  // Non-directional alignment: these surfaces take no space, and a
  // Directionality is not what this file is testing.
  child: SizedBox.expand(
    child: Stack(alignment: Alignment.topLeft, children: surfaces),
  ),
);

/// A panel that logs the pointer events reaching it.
Widget panel(
  String label,
  List<String> log, {
  double zOrder = 0.0,
  bool absorbs = true,
  double z = 0.0,
  Layout3dController? controller,
  Widget? child,
}) => SceneLayout3d(
  parent: Node(),
  controller: controller,
  size: const Size3d(4, 4, 0.2),
  position: Vector3(0, 0, z),
  zOrder: zOrder,
  absorbsPointer: absorbs,
  child:
      child ??
      SceneListener3d(
        behavior: HitTestBehavior3d.opaque,
        onPointerDown: (_) => log.add('$label down'),
        onPointerUp: (_) => log.add('$label up'),
        onPointerHover: (_) => log.add('$label hover'),
        onPointerEnter: (_) => log.add('$label enter'),
        onPointerExit: (_) => log.add('$label exit'),
        child: const SceneSizedBox3d.cube(1),
      ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a surface announces itself', () {
    testWidgets('a press reaches a box with nothing wired by hand', (
      tester,
    ) async {
      final log = <String>[];
      final hits = <Input3dHit>[];
      await tester.pumpWidget(hosted([panel('panel', log)], onHit: hits.add));

      await tester.tapAt(center);

      expect(log, <String>['panel down', 'panel up']);
      // No LayoutBuilder, no Listener, no camera.screenPointToRay, no
      // addSurface from a tick: the surface was reachable from the frame it
      // was mounted in.
      expect(hits, hasLength(1));
      expect(hits.single.phase, Input3dHitPhase.press);
      expect(hits.single.result.isEmpty, isFalse);
    });

    testWidgets('a surface that leaves the tree stops answering', (
      tester,
    ) async {
      final log = <String>[];
      final controller = Input3dController();
      await tester.pumpWidget(
        hosted([panel('panel', log)], controller: controller),
      );
      expect(controller.host!.pointers.surfaces, hasLength(1));

      await tester.pumpWidget(hosted(const <Widget>[], controller: controller));

      expect(controller.host!.pointers.surfaces, isEmpty);
      await tester.tapAt(center);
      expect(log, isEmpty);
    });

    testWidgets('the host is reachable from inside the subtree', (
      tester,
    ) async {
      final controller = Input3dController();
      late Input3dHost found;
      await tester.pumpWidget(
        hosted(<Widget>[
          SceneLayout3d(
            parent: Node(),
            size: const Size3d(4, 4, 0.2),
            child: SceneLayoutBuilder3d(
              builder: (context, constraints) {
                found = SceneInput3d.of(context);
                return const SceneSizedBox3d.cube(1);
              },
            ),
          ),
        ], controller: controller),
      );

      expect(found, same(controller.host));
    });
  });

  group('what is in front of what', () {
    testWidgets('the declared order decides it, not the geometry', (
      tester,
    ) async {
      final log = <String>[];
      // `behind` is a unit further from the camera than `front` and declared
      // in front of it anyway. Geometry cannot answer this question for a
      // surface turned away from the viewer, so the statement wins.
      await tester.pumpWidget(
        hosted([
          panel('near', log, z: 0.5, zOrder: 0.0),
          panel('far', log, z: -0.5, zOrder: 1.0),
        ]),
      );

      await tester.tapAt(center);

      expect(log, <String>['far down', 'far up']);
    });

    testWidgets('the front surface absorbs the press by default', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        hosted([
          panel('front', log, z: 0.5, zOrder: 1.0),
          panel('back', log, z: -0.5, zOrder: 0.0),
        ]),
      );

      await tester.tapAt(center);

      expect(log, <String>['front down', 'front up']);
    });

    testWidgets('absorbsPointer: false lets the walk carry on', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        hosted([
          panel('front', log, z: 0.5, zOrder: 1.0, absorbs: false),
          panel('back', log, z: -0.5, zOrder: 0.0),
        ]),
      );

      await tester.tapAt(center);

      expect(log, <String>['front down', 'back down', 'front up', 'back up']);
    });

    testWidgets('a changed z-order is restated without a remount', (
      tester,
    ) async {
      final log = <String>[];
      Widget frame({required double frontOrder}) => hosted([
        panel('a', log, z: 0.5, zOrder: frontOrder),
        panel('b', log, z: -0.5, zOrder: 1.0),
      ]);

      await tester.pumpWidget(frame(frontOrder: 0.0));
      await tester.tapAt(center);
      expect(log, <String>['b down', 'b up']);

      log.clear();
      await tester.pumpWidget(frame(frontOrder: 2.0));
      await tester.tapAt(center);
      expect(log, <String>['a down', 'a up']);
    });
  });

  group('an overlay entry', () {
    testWidgets('a detached entry is pressable with nothing synced by hand', (
      tester,
    ) async {
      final log = <String>[];
      final overlay = Overlay3dController();
      await tester.pumpWidget(
        hosted([
          panel(
            'panel',
            log,
            child: SceneOverlay3d(
              controller: overlay,
              child: SceneListener3d(
                behavior: HitTestBehavior3d.opaque,
                onPointerDown: (_) => log.add('panel down'),
                child: const SceneSizedBox3d.cube(1),
              ),
            ),
          ),
        ]),
      );

      // Opened the way a component opens one: from a callback, into the
      // overlay, with no registration of its own.
      overlay.overlay!.insertEntry(
        Overlay3dEntry(
          layer: const OverlayLayer3d.detached(),
          builder: (_) => Listener3d(
            behavior: HitTestBehavior3d.opaque,
            onPointerDown: (_) => log.add('dialog down'),
            child: TestBox(const Size3d(2, 2, 0)),
          ),
        ),
      );
      await tester.pump();

      await tester.tapAt(center);

      // The dialog is a surface of its own, one whole step in front of the
      // panel whose overlay opened it, so the panel behind hears nothing.
      expect(log, <String>['dialog down']);
    });

    testWidgets('an overlay that leaves takes its entries with it', (
      tester,
    ) async {
      final log = <String>[];
      final overlay = Overlay3dController();
      final controller = Input3dController();
      Widget frame({required bool withOverlay}) => hosted([
        panel(
          'panel',
          log,
          child: withOverlay
              ? SceneOverlay3d(
                  controller: overlay,
                  child: const SceneSizedBox3d.cube(1),
                )
              : const SceneSizedBox3d.cube(1),
        ),
      ], controller: controller);

      await tester.pumpWidget(frame(withOverlay: true));
      overlay.overlay!.insertEntry(
        Overlay3dEntry(
          layer: const OverlayLayer3d.detached(),
          builder: (_) => TestBox(const Size3d(2, 2, 0), pointable: true),
        ),
      );
      await tester.pump();
      await tester.tapAt(center);
      expect(controller.host!.pointers.surfaces, hasLength(2));

      await tester.pumpWidget(frame(withOverlay: false));

      expect(controller.host!.pointers.surfaces, hasLength(1));
    });
  });

  group('hovering', () {
    testWidgets('a hover reaches the box and is reported', (tester) async {
      final log = <String>[];
      final hits = <Input3dHit>[];
      await tester.pumpWidget(hosted([panel('panel', log)], onHit: hits.add));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(center);
      await tester.pump();

      expect(log, contains('panel enter'));
      expect(hits.last.phase, Input3dHitPhase.hover);
      expect(hits.last.result.isEmpty, isFalse);
    });

    testWidgets('leaving the view takes the pointer off every surface', (
      tester,
    ) async {
      final log = <String>[];
      // Pinned to the corner so the host really is 400×300 and there is room
      // in the view to move the cursor off it.
      await tester.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: hosted([panel('panel', log)]),
          ),
        ),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(4, 4));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(const Offset(200, 150));
      await tester.pump();
      expect(log, contains('panel enter'));

      log.clear();
      // Out of the host's box entirely. Without the exit the box would keep
      // its hover state layer lit, because a hover only ends when a later one
      // lands somewhere else — and there is no later one.
      await mouse.moveTo(const Offset(700, 500));
      await tester.pump();

      expect(log, <String>['panel exit']);
    });
  });

  group('the ambient camera', () {
    testWidgets('reaches a bound surface that was given none', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        hosted(<Widget>[
          SceneLayout3d(
            parent: Node(),
            controller: controller,
            viewSize: const Size(800, 600),
            binding: const Layout3dCameraBinding.screenFilling(
              distance: 2,
              depth: 0.5,
            ),
            child: const SceneSizedBox3d.cube(0.2),
          ),
        ], camera: frontCamera()),
      );
      await tester.pump();

      // The height the frustum takes in two units out, from a camera this
      // surface was never handed.
      expect(
        controller.surface!.size.height,
        closeTo(2 * 2 * math.tan(math.pi / 8), 1e-4),
      );
    });
  });

  group('the group itself', () {
    test('one overlay\'s sync leaves another overlay\'s entries alone', () {
      // The defect this plan's wiring would have hit on the first application
      // with two panels: the bookkeeping was one flat set, so each sync took
      // out what the other had put in.
      ({Layout3dSurface surface, Overlay3d overlay}) makePanel() {
        final overlay = Overlay3d(
          children: <Layout3d>[TestBox(const Size3d(4, 3, 0))],
        );
        final surface = laidOut(
          overlay,
          constraints: Constraints3d.tight(const Size3d(4, 3, 0.5)),
        );
        addTearDown(surface.dispose);
        return (surface: surface, overlay: overlay);
      }

      final left = makePanel();
      final right = makePanel();
      for (final panel in <({Layout3dSurface surface, Overlay3d overlay})>[
        left,
        right,
      ]) {
        panel.overlay.insertEntry(
          Overlay3dEntry(
            layer: const OverlayLayer3d.detached(),
            builder: (_) => TestBox(const Size3d(1, 1, 0), pointable: true),
          ),
        );
        panel.surface.flush();
      }

      final group = Layout3dPointerGroup()
        ..addSurface(left.surface)
        ..addSurface(right.surface);
      addTearDown(group.dispose);

      group
        ..syncDetachedEntries(left.overlay)
        ..syncDetachedEntries(right.overlay);

      expect(group.surfaces, hasLength(4));
      expect(group.holds(left.overlay.detachedSurfaces.single), isTrue);
      expect(group.holds(right.overlay.detachedSurfaces.single), isTrue);

      // And syncing one again does not evict the other.
      group.syncDetachedEntries(left.overlay);
      expect(group.holds(right.overlay.detachedSurfaces.single), isTrue);
    });

    test('forgetting an overlay takes only its own entries out', () {
      final overlay = Overlay3d(
        children: <Layout3d>[TestBox(const Size3d(4, 3, 0))],
      );
      final surface = laidOut(
        overlay,
        constraints: Constraints3d.tight(const Size3d(4, 3, 0.5)),
      );
      addTearDown(surface.dispose);
      overlay.insertEntry(
        Overlay3dEntry(
          layer: const OverlayLayer3d.detached(),
          builder: (_) => TestBox(const Size3d(1, 1, 0), pointable: true),
        ),
      );
      surface.flush();

      final group = Layout3dPointerGroup()..addSurface(surface);
      addTearDown(group.dispose);
      group.syncDetachedEntries(overlay);
      expect(group.surfaces, hasLength(2));

      group.forgetDetachedEntries(overlay);

      expect(group.surfaces, <Layout3dSurface>[surface]);
    });
  });
}
