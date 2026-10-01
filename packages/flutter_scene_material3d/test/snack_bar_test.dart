import 'package:flutter/widgets.dart' show Builder, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlays_support.dart';
import 'support.dart' show SceneTestBox, TestBox;

/// A surface with an overlay and a messenger in it.
class PumpedMessenger {
  PumpedMessenger(this.controller, this.overlayController, this.messenger);

  final Layout3dController controller;
  final Overlay3dController overlayController;
  final ScaffoldMessenger3dState messenger;

  /// The screen under the messenger, which counts its own layouts.
  TestBox? screen;

  Layout3dSurface get surface => controller.surface!;
  Overlay3d get overlay => overlayController.overlay!;
  List<DecoratedBox3d> get panels => boxesOf<DecoratedBox3d>(surface);

  /// Every label a reader would hear, in tree order.
  List<String?> get announced =>
      boxesOf<Semantics3d>(surface).map((box) => box.properties.label).toList();
}

Future<PumpedMessenger> pumpMessenger(
  WidgetTester tester, {
  List<int>? screenBuilds,
}) async {
  final controller = Layout3dController();
  final overlayController = Overlay3dController();
  late ScaffoldMessenger3dState messenger;
  TestBox? screen;
  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      size: const Size3d(8, 6, 1),
      controller: controller,
      child: SceneTheme3d(
        data: Theme3dData.light,
        child: SceneOverlay3d(
          controller: overlayController,
          child: ScaffoldMessenger3d(
            child: Builder(
              builder: (context) {
                messenger = ScaffoldMessenger3d.of(context);
                screenBuilds?[0]++;
                return SceneTestBox(
                  const Size3d(8, 6, 0.1),
                  (box) => screen = box,
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  return PumpedMessenger(controller, overlayController, messenger)
    ..screen = screen;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the tokens', () {
    test('a snack bar is the inverse surface, four seconds up', () {
      const theme = Theme3dData.light;
      final style = SnackBarStyle3d.of(theme);
      expect(style.container, theme.colorScheme.inverseSurface);
      expect(style.contentColor, theme.colorScheme.onInverseSurface);
      expect(style.actionColor, theme.colorScheme.inversePrimary);
      expect(style.shape, theme.shape.extraSmall);
      // Flutter's `_snackBarDisplayDuration`, transcribed: it is a private
      // constant with no accessor.
      expect(style.displayDuration, const Duration(milliseconds: 4000));
      expect(style.minHeight, 48.0);
    });

    test('a bar with an action label needs something for it to do', () {
      expect(
        () => SnackBar3d(message: 'Saved', actionLabel: 'Undo'),
        throwsAssertionError,
      );
    });
  });

  group('the queue', () {
    testWidgets('shows one bar, and the next only when the first goes', (
      tester,
    ) async {
      final pumped = await pumpMessenger(tester);
      final style = SnackBarStyle3d.of(Theme3dData.light);

      final first = pumped.messenger.show(const SnackBar3d(message: 'Saved'));
      final second = pumped.messenger.show(
        const SnackBar3d(message: 'Deleted'),
      );
      expect(pumped.messenger.length, 2);

      // Settled: a bar rises a quarter of a second before it is up.
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, hasLength(1));
      expect(pumped.announced, contains('Saved'));
      expect(pumped.announced, isNot(contains('Deleted')));

      // Just before the first bar's time is up, it is still the only one.
      await tester.pump(style.displayDuration - const Duration(seconds: 1));
      expect(pumped.announced, contains('Saved'));

      await tester.pump(const Duration(seconds: 1));
      expect(await first.closed, SnackBar3dClosedReason.timeout);

      // The handover is two animations end to end: the first sinks, its
      // entry comes out, and only then does the second rise. That is why
      // `_present` refuses to run while an entry is still in the overlay.
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, hasLength(1));
      expect(pumped.announced, contains('Deleted'));
      expect(pumped.announced, isNot(contains('Saved')));

      await tester.pump(style.displayDuration);
      expect(await second.closed, SnackBar3dClosedReason.timeout);
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('a bar honours its own duration', (tester) async {
      final pumped = await pumpMessenger(tester);
      final controller = pumped.messenger.show(
        const SnackBar3d(
          message: 'Quick',
          duration: Duration(milliseconds: 500),
        ),
      );
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));

      await tester.pump(const Duration(milliseconds: 499));
      expect(pumped.overlay.entries, hasLength(1));

      await tester.pump(const Duration(milliseconds: 2));
      expect(await controller.closed, SnackBar3dClosedReason.timeout);
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('a queued bar closed before its turn is dropped', (
      tester,
    ) async {
      final pumped = await pumpMessenger(tester);
      pumped.messenger.show(const SnackBar3d(message: 'First'));
      final queued = pumped.messenger.show(const SnackBar3d(message: 'Second'));
      await tester.pump();

      queued.close();
      expect(await queued.closed, SnackBar3dClosedReason.remove);
      expect(pumped.messenger.length, 1);

      // The first is untouched: closing a queued bar takes nothing down.
      expect(pumped.announced, contains('First'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('removeCurrent takes the bar down and starts the next', (
      tester,
    ) async {
      final pumped = await pumpMessenger(tester);
      final first = pumped.messenger.show(const SnackBar3d(message: 'First'));
      pumped.messenger.show(const SnackBar3d(message: 'Second'));
      await tester.pump();
      expect(pumped.announced, contains('First'));

      pumped.messenger.removeCurrent();
      expect(await first.closed, SnackBar3dClosedReason.remove);
      await tester.pumpAndSettle();
      expect(pumped.announced, contains('Second'));
    });

    testWidgets('clear empties the queue and completes every future', (
      tester,
    ) async {
      final pumped = await pumpMessenger(tester);
      final first = pumped.messenger.show(const SnackBar3d(message: 'One'));
      final second = pumped.messenger.show(const SnackBar3d(message: 'Two'));
      final third = pumped.messenger.show(const SnackBar3d(message: 'Three'));
      await tester.pump();

      pumped.messenger.clear();
      expect(await first.closed, SnackBar3dClosedReason.remove);
      expect(await second.closed, SnackBar3dClosedReason.remove);
      expect(await third.closed, SnackBar3dClosedReason.remove);
      expect(pumped.messenger.length, 0);
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('a messenger leaving the tree completes what it held', (
      tester,
    ) async {
      final pumped = await pumpMessenger(tester);
      final waiting = pumped.messenger.show(const SnackBar3d(message: 'Bye'));
      await tester.pump();

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 6, 1),
          child: const SceneSizedBox3d.cube(1),
        ),
      );
      expect(await waiting.closed, SnackBar3dClosedReason.dispose);
    });

    testWidgets('the action closes the bar and reports itself', (tester) async {
      final pumped = await pumpMessenger(tester);
      var undone = 0;
      final controller = pumped.messenger.show(
        SnackBar3d(
          message: 'Deleted',
          actionLabel: 'Undo',
          onAction: () => undone++,
        ),
      );
      // Settled before the press: the bar is aimed at where it is *drawn*,
      // and a rising bar is drawn somewhere a ray does not find it — the node
      // tier's contract, which the arrival is the catalogue's first customer
      // for.
      await tester.pumpAndSettle();

      final action = boxesOf<Semantics3d>(
        pumped.surface,
      ).firstWhere((box) => box.properties.label == 'Undo');
      final at = action.drawnOffsetInSurface;
      final pointer = Layout3dPointer(pumped.surface);
      pointer.down(
        rayAt(
          pumped.surface,
          Offset3d(
            at.x + action.size.width / 2,
            at.y + action.size.height / 2,
            0,
          ),
        ),
      );
      pointer.up();
      await tester.pumpAndSettle();

      expect(undone, 1);
      expect(await controller.closed, SnackBar3dClosedReason.action);
      expect(pumped.overlay.entries, isEmpty);
    });
  });

  group('what waiting costs', () {
    testWidgets('four seconds of waiting rebuild and relayout nothing', (
      tester,
    ) async {
      final screenBuilds = <int>[0];
      final pumped = await pumpMessenger(tester, screenBuilds: screenBuilds);
      pumped.messenger.show(const SnackBar3d(message: 'Saved'));
      await tester.pump();

      final buildsAfterShow = screenBuilds.single;
      final layoutsAfterShow = pumped.screen!.layoutCount;

      // Halfway through the bar's four seconds. The timer is the only thing
      // running and it touches nothing.
      await tester.pump(const Duration(seconds: 2));
      expect(screenBuilds.single, buildsAfterShow);
      expect(pumped.screen!.layoutCount, layoutsAfterShow);
    });

    testWidgets('showing a bar does not rebuild the screen under it', (
      tester,
    ) async {
      final screenBuilds = <int>[0];
      final pumped = await pumpMessenger(tester, screenBuilds: screenBuilds);
      final before = screenBuilds.single;

      pumped.messenger.show(const SnackBar3d(message: 'Saved'));
      await tester.pump();

      // The overlay rebuilds, because it has a new entry to mount; the screen
      // below the messenger does not.
      expect(screenBuilds.single, before);
      expect(pumped.overlay.entries, hasLength(1));
    });
  });

  group('SnackBar3d on its own', () {
    testWidgets('is a surface with the snack-bar tokens on it', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: const SnackBar3d(message: 'Saved'),
      );
      final style = SnackBarStyle3d.of(Theme3dData.light);
      final decoration = pumped.panels.first.decoration as BoxDecoration3d;
      expect(decoration.color, style.container);
      expect(decoration.borderRadius, style.shape);
      expect(decoration.elevation, style.elevation);
    });

    testWidgets('announces its message as a live region', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: const SnackBar3d(message: 'Saved'),
      );
      final semantics = boxesOf<Semantics3d>(pumped.surface).first;
      expect(semantics.properties.label, 'Saved');
      expect(semantics.properties.liveRegion, isTrue);
    });

    testWidgets('the action stands clear of the bar it is on', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: SnackBar3d(
          message: 'Deleted',
          actionLabel: 'Undo',
          onAction: () {},
        ),
      );
      // The bar's panel and the action's own, which is lifted so that its
      // wash is not coplanar with the bar it is drawn on.
      expect(pumped.panels, hasLength(2));
      final action = pumped.panels.last.decoration as BoxDecoration3d;
      expect(action.elevation, greaterThan(0));
      expect(action.color.a, 0);
    });
  });

  group('a second line', () {
    /// Where [box]'s origin is on the surface.
    Offset3d originOf(Layout3d box) {
      var at = Offset3d.zero;
      Layout3d? walk = box;
      while (walk != null) {
        at += walk.offset;
        walk = walk.parent;
      }
      return at;
    }

    /// A bar at the foot of the overlay, the way the messenger puts it: the
    /// surface's own constraints are tight, and a bar pumped straight onto
    /// them would be the size of the surface.
    Widget atFoot(SnackBar3d bar) =>
        SceneAlign3d(alignment: const Alignment3d(0, 1, -1), child: bar);

    Text3d labelled(Layout3dSurface surface, String text) =>
        boxesOf<Text3d>(surface).singleWhere((box) => box.data == text);

    const long =
        'This message is long enough that it has to be broken onto a second '
        'line to fit';

    testWidgets('a long message wraps, and the bar grows to hold it', (
      tester,
    ) async {
      final short = await pumpOverlay(
        tester,
        child: atFoot(const SnackBar3d(message: 'Saved')),
      );
      final oneLine = short.panels.first.size.height;

      final pumped = await pumpOverlay(
        tester,
        child: atFoot(const SnackBar3d(message: long)),
      );
      final bar = pumped.panels.first;
      expect(bar.size.height, greaterThan(oneLine));
      // And no wider than a bar may be: 600dp, inside the overlay.
      expect(bar.size.width, lessThanOrEqualTo(6.0 + 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide action goes on a line of its own, under the message', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: atFoot(
          SnackBar3d(
            message: 'Notifications are off',
            actionLabel: 'Open the notification settings',
            onAction: () {},
          ),
        ),
      );
      final message = labelled(pumped.surface, 'Notifications are off');
      final action = labelled(pumped.surface, 'Open the notification settings');
      final messageAt = originOf(message);
      final actionAt = originOf(action);
      expect(
        actionAt.y,
        greaterThanOrEqualTo(messageAt.y + message.size.height),
        reason: 'the action is under the message',
      );
      // At the trailing edge of a bar as wide as it may be.
      final bar = pumped.panels.first;
      expect(bar.size.width, closeTo(6.0, 1e-9));
      final barAt = originOf(bar);
      expect(
        actionAt.x + action.size.width,
        greaterThan(barAt.x + bar.size.width * 0.75),
      );
    });

    testWidgets('a narrow one stays beside it', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: atFoot(
          SnackBar3d(message: 'Deleted', actionLabel: 'Undo', onAction: () {}),
        ),
      );
      final message = labelled(pumped.surface, 'Deleted');
      final action = labelled(pumped.surface, 'Undo');
      final messageAt = originOf(message);
      final actionAt = originOf(action);
      expect(actionAt.x, greaterThan(messageAt.x + message.size.width));
      expect(actionAt.y, lessThan(messageAt.y + message.size.height));
      expect(actionAt.y + action.size.height, greaterThan(messageAt.y));
    });

    testWidgets('the threshold is the bar\'s to change', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: atFoot(
          SnackBar3d(
            message: 'Notifications are off',
            actionLabel: 'Open the notification settings',
            onAction: () {},
            actionOverflowThreshold: 1.0,
          ),
        ),
      );
      final message = labelled(pumped.surface, 'Notifications are off');
      final action = labelled(pumped.surface, 'Open the notification settings');
      expect(originOf(action).x, greaterThan(originOf(message).x));
      expect(
        originOf(action).y,
        lessThan(originOf(message).y + message.size.height),
      );
    });

    testWidgets('the action is labelLarge, as a TextButton\'s label is', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: atFoot(
          SnackBar3d(message: 'Deleted', actionLabel: 'Undo', onAction: () {}),
        ),
      );
      const theme = Theme3dData.light;
      final style = SnackBarStyle3d.of(theme);
      expect(style.actionTextStyle, Typography3dToken.labelLarge);
      expect(style.actionOverflowThreshold, 0.25);
      final undo = labelled(pumped.surface, 'Undo').style;
      final large = theme.textStyle(Typography3dToken.labelLarge);
      expect(undo.fontSize, large.fontSize);
      expect(undo.fontWeight, large.fontWeight);
      expect(undo.color, style.actionColor);
    });
  });
}
