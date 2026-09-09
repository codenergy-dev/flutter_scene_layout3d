import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlays_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the tokens', () {
    test('a dialog is the extra-large shape on surfaceContainerHigh', () {
      const theme = Theme3dData.light;
      final style = DialogStyle3d.of(theme);
      expect(style.container, theme.colorScheme.surfaceContainerHigh);
      expect(style.shape, theme.shape.extraLarge);
      expect(style.elevation, theme.elevation.level3);
      expect(style.thickness, theme.thickness.raised);
      expect(style.minWidth, 280.0);
    });

    test('the scrim is Material\'s black at 32%', () {
      const theme = Theme3dData.light;
      final style = DialogStyle3d.of(theme);
      expect(style.scrimColor.a, closeTo(0.32, 1e-9));
      expect(style.scrimColor.r, 0);
      expect(style.scrimColor.g, 0);
      expect(style.scrimColor.b, 0);
      // And it has a depth, because a scrim here is a slab: a zero-depth one
      // is coplanar with what it covers.
      expect(style.scrimThickness, theme.thickness.thin);
      expect(style.scrimThickness, greaterThan(0));
    });
  });

  group('the depth a dialog sits at', () {
    test('clears every slot a scaffold declares, by construction', () {
      const step = 12.0;
      final frontmost = Scaffold3d.liftFor(Scaffold3dSlot.values.last, step);
      expect(Scaffold3d.overlayLift(step), frontmost + step);
      // Every slot, not only the body: a dialog over a floating action
      // button is the case that fails if this is wrong.
      for (final slot in Scaffold3dSlot.values) {
        expect(
          Scaffold3d.overlayLift(step),
          greaterThan(Scaffold3d.liftFor(slot, step)),
        );
      }
    });

    test('is far more than the layout package\'s default lift', () {
      // `Overlay3d.defaultLift` is a depth-buffer separation between two
      // things with no thickness. A Material screen has spent four steps
      // before a dialog is asked for.
      expect(Scaffold3d.overlayLift(12.0), greaterThan(Overlay3d.defaultLift));
      expect(Scaffold3d.overlayLift(12.0), 60.0);
    });

    test('separates a dialog from the frontmost thing under it', () {
      const theme = Theme3dData.light;
      final step = theme.thickness.depthStep;
      // The gap between the frontmost slot and the overlay is one step, and
      // one step separates a raised slab from a structural one.
      expect(
        theme.thickness.separates(
          theme.thickness.structural,
          theme.thickness.raised,
          step: step,
        ),
        isTrue,
      );
    });
  });

  group('showDialog3d', () {
    testWidgets('puts the dialog in front on the next frame', (tester) async {
      final pumped = await pumpOverlay(tester);

      final result = showDialog3d<String>(
        context: pumped.context,
        builder: (context) => const Dialog3d(
          semanticLabel: 'Delete this file?',
          child: SceneSizedBox3d(width: 1, height: 0.4, depth: 0.02),
        ),
      );

      // The entry is in at once; the modal it describes — barrier, scrim and
      // dialog together — is a widget subtree, so it arrives on the next
      // frame. Flutter's own `showDialog` behaves the same way: inserting an
      // overlay entry marks the overlay for a rebuild.
      expect(pumped.overlay.entries, hasLength(1));
      expect(boxesOf<ModalBarrier3d>(pumped.surface), isEmpty);

      await tester.pump();
      expect(boxesOf<ModalBarrier3d>(pumped.surface), hasLength(1));

      // Two panels: the scrim and the dialog.
      expect(pumped.panels.length, greaterThanOrEqualTo(2));
      expect(
        boxesOf<Semantics3d>(
          pumped.surface,
        ).any((box) => box.properties.label == 'Delete this file?'),
        isTrue,
      );
      expect(result, isA<Future<String?>>());

      Navigator3d.of(pumped.overlay)!.pop('deleted');
      await tester.pump();
      expect(await result, 'deleted');
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('the dialog stands in front of its own scrim', (tester) async {
      final pumped = await pumpOverlay(tester);
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pump();

      final barrier = oneOf<ModalBarrier3d>(pumped.surface);
      final scrim = boxesOf<DecoratedBox3d>(
        pumped.surface,
      ).firstWhere((box) => (box.decoration as BoxDecoration3d).color.a < 1.0);
      final dialog = boxesOf<DecoratedBox3d>(
        pumped.surface,
      ).firstWhere((box) => (box.decoration as BoxDecoration3d).color.a == 1.0);

      // Toward the viewer is negative z. The dialog is *entirely* in front of
      // the scrim — its back face clears the scrim's front one — which is the
      // claim that matters: two slabs that merely have different centres can
      // still overlap and z-fight where they do.
      final scrimZ = offsetInSurface(scrim).z;
      final dialogZ = offsetInSurface(dialog).z;
      expect(dialogZ, lessThan(scrimZ));
      expect(dialogZ + dialog.size.depth, lessThan(scrimZ));
      // And the gap is at least the theme's own step, not a number this
      // component picked. (It is more, because the stack centres its children
      // in depth and the two slabs are not equally deep.)
      final step = Layout3dMetrics.standard.dp(
        Theme3dData.light.thickness.depthStep,
      );
      expect(scrimZ - dialogZ, greaterThanOrEqualTo(step));
      // The scrim is a slab, not a plane.
      expect(barrier.thickness, greaterThan(0));
    });

    testWidgets('a tap on the scrim pops it, and can be refused', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester);
      final dismissed = showDialog3d<String>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pump();

      // Well outside the dialog, which is centred.
      final ray = rayAt(pumped.surface, const Offset3d(0.1, 0.1, 0));
      pumped.pointer.down(ray);
      pumped.pointer.up();
      await tester.pump();
      expect(await dismissed, isNull);
      expect(pumped.overlay.entries, isEmpty);

      final held = showDialog3d<String>(
        context: pumped.context,
        barrierDismissible: false,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pump();
      final second = Layout3dPointer(pumped.surface);
      second.down(rayAt(pumped.surface, const Offset3d(0.1, 0.1, 0)));
      second.up();
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));

      Navigator3d.of(pumped.overlay)!.pop('kept');
      await tester.pump();
      expect(await held, 'kept');
    });

    testWidgets('the barrier swallows a press aimed at the screen', (
      tester,
    ) async {
      var taps = 0;
      final pumped = await pumpOverlay(
        tester,
        child: SceneGestureDetector3d(
          onTap: () => taps++,
          child: const SceneSizedBox3d(width: 8, height: 6, depth: 0.1),
        ),
      );

      void tapAtCorner() {
        final pointer = Layout3dPointer(pumped.surface);
        pointer.down(rayAt(pumped.surface, const Offset3d(0.2, 0.2, 0)));
        pointer.up();
      }

      tapAtCorner();
      await tester.pump();
      expect(taps, 1);

      showDialog3d<void>(
        context: pumped.context,
        barrierDismissible: false,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pump();

      tapAtCorner();
      await tester.pump();
      // The press landed on the barrier and went no further.
      expect(taps, 1);
      expect(pumped.overlay.entries, hasLength(1));
    });

    testWidgets('it traps focus and hands it back on the pop', (tester) async {
      final pumped = await pumpOverlay(tester);
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pump();

      final entry = pumped.overlay.entries.single;
      expect(entry.focusScope, isNotNull);
      expect(entry.trapFocus, isTrue);
      expect(entry.restoreFocus, isTrue);
    });

    testWidgets('the dialog shrink-wraps rather than filling the screen', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester);
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(
          child: SceneSizedBox3d(width: 0.5, height: 0.3, depth: 0.02),
        ),
      );
      await tester.pump();

      final dialog = boxesOf<DecoratedBox3d>(
        pumped.surface,
      ).firstWhere((box) => (box.decoration as BoxDecoration3d).color.a == 1.0);
      // 280dp minimum at a hundred logical pixels to the unit.
      expect(dialog.size.width, closeTo(2.8, 1e-9));
      // The height is the content plus 24dp of padding on each side, not the
      // six units the surface is tall.
      expect(dialog.size.height, closeTo(0.3 + 0.48, 1e-9));
      expect(dialog.size.depth, closeTo(0.04, 1e-9));
    });

    testWidgets('two dialogs stack, the later one in front', (tester) async {
      final pumped = await pumpOverlay(tester);
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pump();

      expect(pumped.overlay.entries, hasLength(2));
      final navigator = Navigator3d.of(pumped.overlay)!;
      expect(navigator.routes, hasLength(2));
      navigator.pop();
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));
    });
  });

  group('Dialog3d on its own', () {
    testWidgets('is a surface with the dialog tokens on it', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: const Dialog3d(child: SceneSizedBox3d.cube(0.2)),
      );
      final style = DialogStyle3d.of(Theme3dData.light);
      final panel = pumped.panels.single;
      final decoration = panel.decoration as BoxDecoration3d;
      expect(decoration.color, style.container);
      expect(decoration.borderRadius, style.shape);
      expect(decoration.elevation, style.elevation);
      // The tint is off: the container token already encodes the elevation.
      expect(decoration.surfaceTint!.a, 0);
    });

    testWidgets('announces itself as a route with the name it was given', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: const Dialog3d(
          semanticLabel: 'Sign in',
          child: SceneSizedBox3d.cube(0.2),
        ),
      );
      final semantics = oneOf<Semantics3d>(pumped.surface);
      expect(semantics.properties.label, 'Sign in');
      expect(semantics.properties.scopesRoute, isTrue);
      expect(semantics.properties.namesRoute, isTrue);
    });

    testWidgets('an unnamed dialog names no route', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: const Dialog3d(child: SceneSizedBox3d.cube(0.2)),
      );
      final semantics = oneOf<Semantics3d>(pumped.surface);
      expect(semantics.properties.label, isNull);
      expect(semantics.properties.namesRoute, isFalse);
    });
  });
}
