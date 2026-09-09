import 'package:flutter/widgets.dart' show Builder;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlays_support.dart';
import 'support.dart' show SceneTestBox, TestBox;

/// A tooltip over a counting box, in the top-left corner of the panel.
class PumpedTooltip {
  PumpedTooltip(this.controller, this.overlayController, this.builds);

  final Layout3dController controller;
  final Overlay3dController overlayController;

  /// How many times the tooltip's child has been built.
  final List<int> builds;

  /// The child box, which counts its own layouts.
  TestBox? child;

  Layout3dSurface get surface => controller.surface!;
  Overlay3d get overlay => overlayController.overlay!;
  List<DecoratedBox3d> get panels => boxesOf<DecoratedBox3d>(surface);
}

Future<PumpedTooltip> pumpTooltip(
  WidgetTester tester, {
  String message = 'Compose',
  bool enabled = true,
}) async {
  final controller = Layout3dController();
  final overlayController = Overlay3dController();
  final builds = <int>[0];
  TestBox? child;
  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      size: const Size3d(8, 6, 1),
      controller: controller,
      child: SceneTheme3d(
        data: Theme3dData.light,
        child: SceneOverlay3d(
          controller: overlayController,
          child: ScenePositioned3d(
            left: 0,
            top: 0,
            front: 0,
            child: Tooltip3d(
              message: message,
              enabled: enabled,
              child: Builder(
                builder: (context) {
                  builds[0]++;
                  return SceneTestBox(
                    const Size3d(0.4, 0.4, 0.02),
                    (box) => child = box,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return PumpedTooltip(controller, overlayController, builds)..child = child;
}

/// Moves a pointer onto the control in the corner, then off it.
void hover(Layout3dSurface surface, Layout3dPointer pointer) =>
    pointer.hover(rayAt(surface, const Offset3d(0.2, 0.2, 0)));

void away(Layout3dSurface surface, Layout3dPointer pointer) =>
    pointer.hover(rayAt(surface, const Offset3d(7.5, 5.5, 0)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the tokens', () {
    test('a tooltip is the inverse surface, and a thin one', () {
      const theme = Theme3dData.light;
      final style = TooltipStyle3d.of(theme);
      expect(style.container, theme.colorScheme.inverseSurface);
      expect(style.contentColor, theme.colorScheme.onInverseSurface);
      expect(style.shape, theme.shape.extraSmall);
      // Flat, and the thinnest thing in the catalogue that is not a rule.
      expect(style.elevation, theme.elevation.level0);
      expect(style.thickness, theme.thickness.thin);
      // Transcriptions, all three: Flutter's tooltip figures are private
      // constants and `TooltipThemeData` answers with an application's
      // overrides rather than the resolved defaults. There is no drift alarm
      // to be had here, and saying so is better than pretending.
      expect(style.verticalOffset, 24.0);
      expect(style.waitDuration, const Duration(milliseconds: 500));
      expect(style.showDuration, const Duration(milliseconds: 1500));
    });
  });

  group('the wait', () {
    testWidgets('shows nothing until the wait is over', (tester) async {
      final pumped = await pumpTooltip(tester);
      final pointer = Layout3dPointer(pumped.surface);
      final style = TooltipStyle3d.of(Theme3dData.light);

      hover(pumped.surface, pointer);
      await tester.pump();
      expect(pumped.overlay.entries, isEmpty);

      await tester.pump(style.waitDuration - const Duration(milliseconds: 1));
      expect(pumped.overlay.entries, isEmpty);

      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));
    });

    testWidgets('waiting rebuilds and relayouts nothing at all', (
      tester,
    ) async {
      final pumped = await pumpTooltip(tester);
      final pointer = Layout3dPointer(pumped.surface);
      final builds = pumped.builds.single;
      final layouts = pumped.child!.layoutCount;

      hover(pumped.surface, pointer);
      await tester.pump(const Duration(milliseconds: 400));

      // The whole of a hover that has not matured is one Timer. Nothing was
      // rebuilt and nothing was laid out.
      expect(pumped.builds.single, builds);
      expect(pumped.child!.layoutCount, layouts);
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('a pointer that leaves before the wait shows nothing', (
      tester,
    ) async {
      final pumped = await pumpTooltip(tester);
      final pointer = Layout3dPointer(pumped.surface);

      hover(pumped.surface, pointer);
      await tester.pump(const Duration(milliseconds: 200));
      away(pumped.surface, pointer);
      await tester.pump(const Duration(seconds: 5));

      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('a disabled tooltip never shows', (tester) async {
      final pumped = await pumpTooltip(tester, enabled: false);
      final pointer = Layout3dPointer(pumped.surface);
      hover(pumped.surface, pointer);
      await tester.pump(const Duration(seconds: 5));
      expect(pumped.overlay.entries, isEmpty);
    });
  });

  group('the label', () {
    testWidgets('goes away when the pointer leaves', (tester) async {
      final pumped = await pumpTooltip(tester);
      final pointer = Layout3dPointer(pumped.surface);

      hover(pumped.surface, pointer);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));

      away(pumped.surface, pointer);
      await tester.pump();
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('goes away on its own after the show duration', (tester) async {
      final pumped = await pumpTooltip(tester);
      final pointer = Layout3dPointer(pumped.surface);
      final style = TooltipStyle3d.of(Theme3dData.light);

      hover(pumped.surface, pointer);
      await tester.pump(style.waitDuration + const Duration(milliseconds: 1));
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));

      await tester.pump(style.showDuration);
      await tester.pump();
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('sits under the control, not in the middle of the panel', (
      tester,
    ) async {
      final pumped = await pumpTooltip(tester);
      final pointer = Layout3dPointer(pumped.surface);
      hover(pumped.surface, pointer);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      final anchor = oneOf<Anchor3d>(pumped.surface);
      final follower = oneOf<Follower3d>(pumped.surface);
      expect(follower.nodeOffset, isNot(Offset3d.zero));
      final wanted = follower.anchorOffsetTo(
        anchor,
        self: Alignment3d.topCenter,
        target: Alignment3d.bottomCenter,
      )!;
      // A loose tolerance on purpose: the position makes a round trip through
      // the scene node's transform, which is single precision.
      expect(follower.nodeOffset.x, closeTo(wanted.x, 1e-5));
      expect(follower.nodeOffset.y, closeTo(wanted.y, 1e-5));
    });

    testWidgets('lets every ray through', (tester) async {
      final pumped = await pumpTooltip(tester);
      final pointer = Layout3dPointer(pumped.surface);
      hover(pumped.surface, pointer);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));

      // No barrier and no absorbing label: a tooltip that took the ray would
      // dismiss itself the instant it appeared.
      expect(boxesOf<ModalBarrier3d>(pumped.surface), isEmpty);
      expect(boxesOf<IgnorePointer3d>(pumped.surface), isNotEmpty);
    });

    testWidgets('the description is on the control, not on the label', (
      tester,
    ) async {
      final pumped = await pumpTooltip(tester);
      final semantics = boxesOf<Semantics3d>(pumped.surface).single;
      expect(semantics.properties.tooltip, 'Compose');
    });

    testWidgets('it goes with the control that leaves the tree', (
      tester,
    ) async {
      final pumped = await pumpTooltip(tester);
      final pointer = Layout3dPointer(pumped.surface);
      hover(pumped.surface, pointer);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 6, 1),
          child: const SceneSizedBox3d.cube(1),
        ),
      );
      expect(pumped.overlayController.overlay, isNull);
    });
  });
}
