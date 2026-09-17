import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
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
      await tester.pumpAndSettle();
      expect(await result, 'deleted');
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('the dialog stands in front of its own scrim', (tester) async {
      final pumped = await pumpOverlay(tester);
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pumpAndSettle();

      final barrier = oneOf<ModalBarrier3d>(pumped.surface);
      final scrim = scrimOf(pumped.surface)!;
      final dialog = boxesOf<DecoratedBox3d>(
        pumped.surface,
      ).firstWhere((box) => !identical(box, scrim));

      // Toward the viewer is negative z. The dialog is *entirely* in front of
      // the scrim — its back face clears the scrim's front one — which is the
      // claim that matters: two slabs that merely have different centres can
      // still overlap and z-fight where they do.
      final scrimZ = scrim.drawnOffsetInSurface.z;
      final dialogZ = dialog.drawnOffsetInSurface.z;
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
      await tester.pumpAndSettle();

      // Well outside the dialog, which is centred.
      final ray = rayAt(pumped.surface, const Offset3d(0.1, 0.1, 0));
      pumped.pointer.down(ray);
      pumped.pointer.up();
      await tester.pumpAndSettle();
      expect(await dismissed, isNull);
      expect(pumped.overlay.entries, isEmpty);

      final held = showDialog3d<String>(
        context: pumped.context,
        barrierDismissible: false,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pumpAndSettle();
      final second = Layout3dPointer(pumped.surface);
      second.down(rayAt(pumped.surface, const Offset3d(0.1, 0.1, 0)));
      second.up();
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, hasLength(1));

      Navigator3d.of(pumped.overlay)!.pop('kept');
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(taps, 1);

      showDialog3d<void>(
        context: pumped.context,
        barrierDismissible: false,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pumpAndSettle();

      tapAtCorner();
      await tester.pumpAndSettle();
      // The press landed on the barrier and went no further.
      expect(taps, 1);
      expect(pumped.overlay.entries, hasLength(1));
    });

    testWidgets('Escape pops it, unless it must be answered', (tester) async {
      final pumped = await pumpOverlay(tester);
      final dismissed = showDialog3d<String>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pumpAndSettle();

      // The dialog took the focus when it opened, so Escape reaches it with
      // nothing inside focused.
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
      await tester.pumpAndSettle();
      expect(await dismissed, isNull);
      expect(pumped.overlay.entries, isEmpty);

      final held = showDialog3d<String>(
        context: pumped.context,
        barrierDismissible: false,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pumpAndSettle();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, hasLength(1));

      Navigator3d.of(pumped.overlay)!.pop('kept');
      await tester.pumpAndSettle();
      expect(await held, 'kept');
    });

    testWidgets('it traps focus and hands it back on the pop', (tester) async {
      final pumped = await pumpOverlay(tester);
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      final scrim = scrimOf(pumped.surface)!;
      final dialog = boxesOf<DecoratedBox3d>(
        pumped.surface,
      ).firstWhere((box) => !identical(box, scrim));
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
      await tester.pumpAndSettle();

      expect(pumped.overlay.entries, hasLength(2));
      final navigator = Navigator3d.of(pumped.overlay)!;
      expect(navigator.routes, hasLength(2));
      navigator.pop();
      await tester.pumpAndSettle();
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
  group('a scrim dims by coverage', () {
    // The decision four photographed treatments settled, pinned so nobody
    // "fixes" it back into a blend. A blended scrim is composited in whatever
    // order the translucent pass sorts it, and every panel and glyph on a
    // Material screen writes depth — so the parts of the screen the sort put
    // after the scrim were erased rather than dimmed, and an app bar's title
    // came out as a bare outline while the navigation bar's labels were
    // untouched. See `scrimCoverage3d`.

    testWidgets('the slab is opaque and the alpha is the coverage', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester);
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pumpAndSettle();

      final style = DialogStyle3d.of(Theme3dData.light);
      expect(style.scrimColor.a, closeTo(0.32, 1e-6), reason: "Material's own");

      final scrim = scrimOf(pumped.surface)!;
      expect(
        (scrim.decoration as BoxDecoration3d).color.a,
        1.0,
        reason: 'the slab draws at full strength; the dim is the coverage',
      );
      expect(
        scrimCoverageOf(pumped.surface),
        closeTo(style.scrimColor.a, 1e-6),
        reason: "the style's alpha is spent as coverage, one for one",
      );
      expect(scrimCoverage3d(style.scrimColor), style.scrimColor.a);
    });

    testWidgets('it arrives with the route rather than snapping on', (
      tester,
    ) async {
      // The coverage composes with the route's own fade: a scrim part way
      // through an arrival covers part way, and neither replaces the other.
      final pumped = await pumpOverlay(tester);
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));

      final part = scrimCoverageOf(pumped.surface);
      expect(part, greaterThan(0.0));
      expect(part, lessThan(0.32));

      await tester.pumpAndSettle();
      expect(scrimCoverageOf(pumped.surface), closeTo(0.32, 1e-6));
    });
  });

  group('the scrim clears the screen it dims', () {
    // The drift alarm for a defect that 1825 headless tests and 108 render
    // probes passed over, and that a person found by opening a dialog on the
    // gallery and looking at the window: the scrim sat *behind* the app bar
    // and behind the floating action button and dimmed neither, because an
    // overlay's lift was measured from the middle of the panel rather than
    // from its front face. Nothing here was testing that the dimming reaches
    // anything.

    /// The frontmost face of any opaque panel on [screen], which is what a
    /// scrim has to be in front of to dim all of it.
    double frontmostPanel(Layout3d screen) {
      var front = double.infinity;
      void walk(Layout3d box) {
        if (box is DecoratedBox3d) {
          final decoration = box.decoration;
          if (decoration is BoxDecoration3d && decoration.color.a == 1.0) {
            final z = box.drawnOffsetInSurface.z;
            if (z < front) front = z;
          }
        }
        box.visitChildren(walk);
      }

      walk(screen);
      return front;
    }

    testWidgets('a dialog over a whole scaffold dims every slot of it', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: Scaffold3d(
          appBar: AppBar3d.text(title: 'Inbox'),
          body: const SceneSizedBox3d(width: 4, height: 3, depth: 0.05),
          bottomNavigationBar: NavigationBar3d(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: const <NavigationDestination3d>[
              NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'In'),
              NavigationDestination3d(icon: Icon3d(Icons.tune), label: 'Set'),
            ],
          ),
          floatingActionButton: FloatingActionButton3d(
            semanticLabel: 'Compose',
            onPressed: () {},
            child: const Icon3d(Icons.edit),
          ),
        ),
      );
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      await tester.pumpAndSettle();

      // The screen is the overlay's first child; the dialog is an entry after
      // it. Looked for in the whole tree, a "translucent panel" finds a
      // navigation bar's own pill long before it finds the scrim.
      final children = <Layout3d>[];
      pumped.overlay.visitChildren(children.add);
      final screen = frontmostPanel(children.first);
      final scrim = scrimOf(pumped.surface)!.drawnOffsetInSurface.z;

      expect(
        scrim,
        lessThan(screen),
        reason:
            'the scrim is behind something on the screen, so that something '
            'is not dimmed — the floating action button is the usual one, '
            'because it is the frontmost slot and carries an elevation of its '
            'own on top of its slot lift',
      );
    });
  });
}
