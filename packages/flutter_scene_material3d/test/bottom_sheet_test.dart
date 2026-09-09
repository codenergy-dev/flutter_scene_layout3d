import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlays_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the tokens', () {
    test('a sheet is structure, not a card', () {
      const theme = Theme3dData.light;
      final style = BottomSheetStyle3d.of(theme);
      expect(style.container, theme.colorScheme.surfaceContainerLow);
      expect(style.elevation, theme.elevation.level1);
      // Structural, like a bar — a sheet is a piece of the screen that has
      // slid into view, not an object resting on it.
      expect(style.thickness, theme.thickness.structural);
      expect(style.thickness, isNot(theme.thickness.raised));
      expect(style.maxWidth, 640.0);
      expect(style.scrimColor.a, closeTo(0.32, 1e-9));
    });
  });

  group('the edge', () {
    test('rounds the two corners away from what it is pinned to', () {
      const radius = 28.0;
      final bottom = Sheet3dEdge.bottom.shapeFor(radius);
      expect(bottom.topLeft, radius);
      expect(bottom.topRight, radius);
      expect(bottom.bottomLeft, 0);
      expect(bottom.bottomRight, 0);

      final right = Sheet3dEdge.right.shapeFor(radius);
      expect(right.topLeft, radius);
      expect(right.bottomLeft, radius);
      expect(right.topRight, 0);
      expect(right.bottomRight, 0);
    });

    test('every edge aligns to the front face, not to the middle', () {
      for (final edge in Sheet3dEdge.values) {
        // Centred in depth would put the sheet inside the lift that carries
        // it in front of the screen.
        expect(edge.alignment.z, -1, reason: '$edge');
      }
      expect(Sheet3dEdge.bottom.alignment.y, 1);
      expect(Sheet3dEdge.top.alignment.y, -1);
      expect(Sheet3dEdge.left.alignment.x, -1);
      expect(Sheet3dEdge.right.alignment.x, 1);
    });
  });

  group('BottomSheet3d', () {
    testWidgets('is a surface with the sheet tokens on it', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: const BottomSheet3d(child: SceneSizedBox3d.cube(0.4)),
      );
      final style = BottomSheetStyle3d.of(Theme3dData.light);
      final decoration = pumped.panels.single.decoration as BoxDecoration3d;
      expect(decoration.color, style.container);
      expect(decoration.elevation, style.elevation);
      expect(decoration.borderRadius.topLeft, style.shape.topLeft);
      expect(decoration.borderRadius.bottomLeft, 0);
    });

    testWidgets('announces itself as a route with the name it was given', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: const BottomSheet3d(
          semanticLabel: 'Share with',
          child: SceneSizedBox3d.cube(0.4),
        ),
      );
      final semantics = oneOf<Semantics3d>(pumped.surface);
      expect(semantics.properties.label, 'Share with');
      expect(semantics.properties.scopesRoute, isTrue);
    });
  });

  group('showModalBottomSheet3d', () {
    testWidgets('puts a sheet on the bottom edge over a scrim', (tester) async {
      final pumped = await pumpOverlay(tester);
      final result = showModalBottomSheet3d<String>(
        context: pumped.context,
        builder: (context) => const BottomSheet3d(
          child: SceneSizedBox3d(width: 2, height: 0.8, depth: 0.02),
        ),
      );
      await tester.pump();

      expect(boxesOf<ModalBarrier3d>(pumped.surface), hasLength(1));
      final sheet = boxesOf<DecoratedBox3d>(
        pumped.surface,
      ).firstWhere((box) => (box.decoration as BoxDecoration3d).color.a == 1.0);
      final scrim = boxesOf<DecoratedBox3d>(
        pumped.surface,
      ).firstWhere((box) => (box.decoration as BoxDecoration3d).color.a < 1.0);

      // Against the bottom of the six-unit-tall panel, and entirely in front
      // of its own scrim.
      final at = offsetInSurface(sheet);
      expect(at.y + sheet.size.height, closeTo(6.0, 1e-6));
      expect(at.z + sheet.size.depth, lessThan(offsetInSurface(scrim).z));

      Navigator3d.of(pumped.overlay)!.pop('picked');
      await tester.pump();
      expect(await result, 'picked');
    });

    testWidgets('a tap on the scrim pops it with nothing', (tester) async {
      final pumped = await pumpOverlay(tester);
      final result = showModalBottomSheet3d<String>(
        context: pumped.context,
        builder: (context) =>
            const BottomSheet3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pump();

      // High on the panel, well clear of a bottom sheet.
      pumped.pointer.down(rayAt(pumped.surface, const Offset3d(4, 0.3, 0)));
      pumped.pointer.up();
      await tester.pump();

      expect(await result, isNull);
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('a side sheet goes down the edge it names', (tester) async {
      final pumped = await pumpOverlay(tester);
      showModalBottomSheet3d<void>(
        context: pumped.context,
        edge: Sheet3dEdge.right,
        builder: (context) => const BottomSheet3d(
          edge: Sheet3dEdge.right,
          child: SceneSizedBox3d(width: 1.5, height: 2, depth: 0.02),
        ),
      );
      await tester.pump();

      final sheet = boxesOf<DecoratedBox3d>(
        pumped.surface,
      ).firstWhere((box) => (box.decoration as BoxDecoration3d).color.a == 1.0);
      final at = offsetInSurface(sheet);
      // Against the right edge of the eight-unit-wide panel, and full height.
      expect(at.x + sheet.size.width, closeTo(8.0, 1e-6));
      expect(sheet.size.height, closeTo(6.0, 1e-6));
    });
  });

  group('showBottomSheet3d', () {
    testWidgets('dims nothing and blocks nothing', (tester) async {
      var taps = 0;
      final pumped = await pumpOverlay(
        tester,
        child: SceneGestureDetector3d(
          onTap: () => taps++,
          child: const SceneSizedBox3d(width: 8, height: 6, depth: 0.1),
        ),
      );

      final result = showBottomSheet3d<String>(
        context: pumped.context,
        builder: (context) => const BottomSheet3d(
          child: SceneSizedBox3d(width: 2, height: 0.8, depth: 0.02),
        ),
      );
      await tester.pump();

      // No barrier, no scrim: the persistent form is part of the screen.
      expect(boxesOf<ModalBarrier3d>(pumped.surface), isEmpty);
      expect(pumped.overlay.entries, hasLength(1));

      // And the screen under it still works.
      final pointer = Layout3dPointer(pumped.surface);
      pointer.down(rayAt(pumped.surface, const Offset3d(4, 0.3, 0)));
      pointer.up();
      await tester.pump();
      expect(taps, 1);

      Navigator3d.of(pumped.overlay)!.pop('done');
      await tester.pump();
      expect(await result, 'done');
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('it takes no focus away from the screen', (tester) async {
      final pumped = await pumpOverlay(tester);
      showBottomSheet3d<void>(
        context: pumped.context,
        builder: (context) =>
            const BottomSheet3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pump();
      final entry = pumped.overlay.entries.single;
      expect(entry.trapFocus, isFalse);
      expect(entry.focusScope, isNull);
    });
  });
}
