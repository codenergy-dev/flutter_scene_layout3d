// A key that reaches a box: Flutter's shortcuts, intents and actions, walked
// over the layout tree because a focus node on a plane has no context and no
// ancestors a `Shortcuts` widget could be.
//
// These are widget tests even where no widget is built, because a key event
// only reaches the focus manager through the binding's keyboard: the surfaces
// are imperative, and `tester.sendKeyEvent` is the platform.

import 'dart:math' as math;

import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show
        Action,
        ActivateIntent,
        Alignment,
        CallbackAction,
        Focus,
        DoNothingAndStopPropagationIntent,
        FocusManager,
        FocusNode,
        Intent,
        KeyEventResult,
        ShortcutActivator,
        SingleActivator,
        SizedBox,
        Stack,
        Widget;
import 'package:flutter_scene/scene.dart' show Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support.dart';

/// Applies whatever focus change was asked for, which the manager otherwise
/// does on a microtask of its own.
void settleFocus() => FocusManager.instance.applyFocusChangesIfNeeded();

/// A focusable unit box.
Focus3d box({String? name}) =>
    Focus3d(name: name, child: TestBox(const Size3d(1, 1, 0)));

/// An intent of this file's own, so a test can tell its binding from a
/// default.
class SaveIntent extends Intent {
  const SaveIntent();
}

/// An action that writes down that it ran, and can be switched off.
class Recording<T extends Intent> extends Action<T> {
  Recording(this.log, this.label, {this.enabled = true});

  final List<String> log;
  final String label;
  bool enabled;

  @override
  bool isEnabled(T intent) => enabled;

  @override
  Object? invoke(T intent) {
    log.add(label);
    return null;
  }
}

/// Lays [child] out on a surface of [size], disposed at the end of the test.
Layout3dSurface surfaceOf(
  Layout3d child, {
  Size3d size = const Size3d(3, 3, 0),
}) {
  final surface = laidOut(child, constraints: Constraints3d.tight(size));
  addTearDown(surface.dispose);
  return surface;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    FocusManager.instance.primaryFocus?.unfocus();
    settleFocus();
  });

  group('the walk', () {
    testWidgets('Enter invokes the nearest activation above the focus', (
      tester,
    ) async {
      final log = <String>[];
      final button = box();
      surfaceOf(
        Actions3d(
          actions: <Type, Action<Intent>>{
            ActivateIntent: Recording<ActivateIntent>(log, 'outer'),
          },
          child: Actions3d(
            actions: <Type, Action<Intent>>{
              ActivateIntent: Recording<ActivateIntent>(log, 'inner'),
            },
            child: button,
          ),
        ),
      );
      button.requestFocus();
      settleFocus();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isTrue);

      expect(log, <String>['inner', 'inner']);
    });

    testWidgets('a disabled binding does not fall through to an outer one', (
      tester,
    ) async {
      // Flutter's rule: the nearest binding for the type is *the* binding,
      // and a disabled one leaves the key unhandled rather than trying the
      // next one up.
      final log = <String>[];
      final button = box();
      surfaceOf(
        Actions3d(
          actions: <Type, Action<Intent>>{
            ActivateIntent: Recording<ActivateIntent>(log, 'outer'),
          },
          child: Actions3d(
            actions: <Type, Action<Intent>>{
              ActivateIntent: Recording<ActivateIntent>(
                log,
                'inner',
                enabled: false,
              ),
            },
            child: button,
          ),
        ),
      );
      button.requestFocus();
      settleFocus();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      expect(log, isEmpty);
    });

    testWidgets('a nearer shortcut overrides a default', (tester) async {
      final log = <String>[];
      final button = box();
      surfaceOf(
        Shortcuts3d(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): SaveIntent(),
            SingleActivator(LogicalKeyboardKey.space):
                DoNothingAndStopPropagationIntent(),
          },
          child: Actions3d(
            actions: <Type, Action<Intent>>{
              SaveIntent: Recording<SaveIntent>(log, 'save'),
              ActivateIntent: Recording<ActivateIntent>(log, 'activate'),
            },
            child: button,
          ),
        ),
      );
      button.requestFocus();
      settleFocus();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
      // Switched off: the key stops here, is not handled, and never reaches
      // the default that would have activated.
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isFalse);

      expect(log, <String>['save']);
    });

    testWidgets('a Focus3d around a region hears the keys inside it', (
      tester,
    ) async {
      // The bubbling Flutter's `Focus` has and a flat focus tree cannot give.
      final heard = <String>[];
      final inner = box(name: 'inner');
      surfaceOf(
        Focus3d(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            // A key sent in a test is a down and an up; the up is ignored
            // everywhere below, so only the down is interesting here.
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            heard.add(event.logicalKey.keyLabel);
            return event.logicalKey == LogicalKeyboardKey.keyA
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          },
          child: inner,
        ),
      );
      inner.requestFocus();
      settleFocus();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyA), isTrue);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyB), isFalse);

      expect(heard, <String>['A', 'B']);
    });

    testWidgets('the focused box hears its keys before any binding', (
      tester,
    ) async {
      final log = <String>[];
      final button = Focus3d(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          log.add('own');
          return KeyEventResult.handled;
        },
        child: TestBox(const Size3d(1, 1, 0)),
      );
      surfaceOf(
        Actions3d(
          actions: <Type, Action<Intent>>{
            ActivateIntent: Recording<ActivateIntent>(log, 'activate'),
          },
          child: button,
        ),
      );
      button.requestFocus();
      settleFocus();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(log, <String>['own']);
    });

    testWidgets('a node handed in keeps its handler, and gets it back', (
      tester,
    ) async {
      final log = <String>[];
      KeyEventResult own(FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent) log.add('node');
        return KeyEventResult.ignored;
      }

      final node = FocusNode(onKeyEvent: own);
      addTearDown(node.dispose);
      final button = Focus3d(
        focusNode: node,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      surfaceOf(button);
      button.requestFocus();
      settleFocus();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      expect(log, <String>['node']);

      button.focusNode = null;
      expect(node.onKeyEvent, same(own));
    });

    test('an intent can be fired with no key behind it', () {
      final log = <String>[];
      final button = box();
      surfaceOf(
        Actions3d(
          actions: <Type, Action<Intent>>{
            SaveIntent: CallbackAction<SaveIntent>(
              onInvoke: (_) {
                log.add('saved');
                return 'done';
              },
            ),
          },
          child: button,
        ),
      );

      final (enabled, result) = Actions3d.maybeInvoke(
        button,
        const SaveIntent(),
      );

      expect(enabled, isTrue);
      expect(result, 'done');
      expect(log, <String>['saved']);
      expect(Actions3d.maybeInvoke(button, const ActivateIntent()).$1, isFalse);
    });

    test('a key binding does not cut off a tap target\'s reach', () {
      // Wrapped round a target, a box the size of the control would gate the
      // ray on that size and the margin the target grants would be dead.
      final log = <String>[];
      final target = TapTarget3d(
        minimumSize: const Size3d(2, 2, 0),
        child: GestureDetector3d(
          onTapDown: (_) => log.add('down'),
          child: TestBox(const Size3d(1, 1, 0)),
        ),
      );
      final surface = surfaceOf(
        Center3d(
          child: Actions3d(child: Shortcuts3d(child: target)),
        ),
      );

      final hit = surface.hitTestAt(const Offset3d(1.1, 1.5, 0));

      expect(hit.firstOf<TapTarget3d>(), same(target));
    });
  });

  group('the defaults', () {
    testWidgets('Tab and Shift-Tab walk the boxes and wrap round', (
      tester,
    ) async {
      final a = box(name: 'a');
      final b = box(name: 'b');
      final c = box(name: 'c');
      surfaceOf(Row3d(children: <Layout3d>[a, b, c]));
      a.requestFocus();
      settleFocus();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(b.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(a.hasPrimaryFocus, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(c.hasPrimaryFocus, isTrue);
    });

    testWidgets('an arrow moves the focus that way on the plane', (
      tester,
    ) async {
      final a = box(name: 'a');
      final b = box(name: 'b');
      final c = box(name: 'c');
      surfaceOf(
        Column3d(
          children: <Layout3d>[
            Row3d(children: <Layout3d>[a, b]),
            Row3d(children: <Layout3d>[c]),
          ],
        ),
        size: const Size3d(2, 2, 0),
      );
      a.requestFocus();
      settleFocus();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(b.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(c.hasPrimaryFocus, isTrue);
    });

    testWidgets('a surface holding the focus itself tabs to its first box', (
      tester,
    ) async {
      // Where Flutter puts the focus when the focused box is taken out of the
      // tree: the scope above it, with nothing focused inside.
      final a = box(name: 'a');
      final b = box(name: 'b');
      final surface = surfaceOf(Row3d(children: <Layout3d>[a, b]));
      surface.owner!.focusScope.requestFocus();
      settleFocus();
      expect(
        FocusManager.instance.primaryFocus,
        same(surface.owner!.focusScope),
      );
      expect(Focus3d.layoutFor(surface.owner!.focusScope), same(surface));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);

      expect(a.hasPrimaryFocus, isTrue);
    });

    testWidgets('Page Down scrolls the list the focus is in', (tester) async {
      final rows = List.generate(8, (index) => box(name: 'row $index'));
      final list = ListView3d(children: rows);
      surfaceOf(list, size: const Size3d(1, 2, 0));
      rows.first.requestFocus();
      settleFocus();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.pageDown), isTrue);
      await tester.pumpAndSettle();

      // Eighty per cent of a two-unit window.
      expect(list.controller.offset, closeTo(1.6, 1e-6));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // A line is fifty logical pixels, half a unit at the standard metrics.
      expect(list.controller.offset, closeTo(1.1, 1e-6));
    });

    testWidgets('Page Down with no list around the focus goes unhandled', (
      tester,
    ) async {
      final a = box();
      surfaceOf(a);
      a.requestFocus();
      settleFocus();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.pageDown), isFalse);
    });
  });

  group('a modal entry', () {
    ({Layout3dSurface surface, Overlay3d overlay, Focus3d opener}) page() {
      final opener = box(name: 'opener');
      final overlay = Overlay3d(children: <Layout3d>[opener]);
      final surface = surfaceOf(overlay, size: const Size3d(4, 3, 0));
      opener.requestFocus();
      settleFocus();
      return (surface: surface, overlay: overlay, opener: opener);
    }

    testWidgets('takes the focus off the control that opened it', (
      tester,
    ) async {
      final host = page();
      final log = <String>[];
      host.overlay.insertEntry(
        Overlay3dEntry(
          modal: true,
          builder: (_) => Actions3d(
            actions: <Type, Action<Intent>>{
              ActivateIntent: Recording<ActivateIntent>(log, 'dialog'),
            },
            child: box(name: 'inside'),
          ),
        ),
      );
      host.surface.flush();
      settleFocus();

      expect(host.opener.hasFocus, isFalse);

      // Enter behind the barrier would have opened the dialog again. Here it
      // has nothing focused to activate, and the opener does not hear it.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, <String>['dialog']);
    });

    testWidgets('a box inside with autofocus still gets the focus', (
      tester,
    ) async {
      final host = page();
      final inside = Focus3d(
        autofocus: true,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      host.overlay.insertEntry(
        Overlay3dEntry(modal: true, builder: (_) => inside),
      );
      host.surface.flush();
      settleFocus();

      expect(inside.hasPrimaryFocus, isTrue);
    });

    testWidgets('closes on Escape, and hands the focus back', (tester) async {
      final host = page();
      late final Overlay3dEntry entry;
      entry = Overlay3dEntry(
        modal: true,
        onDismiss: () => entry.remove(),
        builder: (_) => box(name: 'inside'),
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();
      settleFocus();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
      settleFocus();

      expect(entry.isInserted, isFalse);
      expect(host.opener.hasPrimaryFocus, isTrue);
    });

    testWidgets('that must be answered ignores Escape', (tester) async {
      final host = page();
      late final Overlay3dEntry entry;
      entry = Overlay3dEntry(
        modal: true,
        dismissible: false,
        onDismiss: () => entry.remove(),
        builder: (_) => box(name: 'inside'),
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();
      settleFocus();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
      expect(entry.isInserted, isTrue);
    });

    testWidgets('a route pops on Escape', (tester) async {
      final host = page();
      final navigator = Navigator3d(host.overlay);
      final popped = navigator.push(
        PageRoute3d<String>(builder: (_) => box(name: 'inside')),
      );
      host.surface.flush();
      settleFocus();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);

      expect(await popped, isNull);
    });

    testWidgets('an entry that is neither modal nor trapping keeps Escape '
        'out of it', (tester) async {
      // A snack bar: Escape with its action focused is not a dismissal.
      final host = page();
      var dismissed = false;
      final action = box(name: 'action');
      host.overlay.insertEntry(
        Overlay3dEntry(
          onDismiss: () => dismissed = true,
          builder: (_) => action,
        ),
      );
      host.surface.flush();
      action.requestFocus();
      settleFocus();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
      expect(dismissed, isFalse);
    });
  });

  group('SceneInput3d', () {
    PerspectiveCamera camera() => PerspectiveCamera(
      fovRadiansY: math.pi / 4,
      position: Vector3(0, 0, 5),
      target: Vector3(0, 0, 0),
    );

    Widget scene({
      required List<Widget> children,
      bool autofocus = false,
      Input3dController? controller,
    }) => SceneInput3d(
      camera: camera(),
      autofocus: autofocus,
      controller: controller,
      child: SizedBox.expand(
        child: Stack(
          alignment: Alignment.topLeft,
          children: <Widget>[
            SceneLayout3d(
              parent: Node(),
              size: const Size3d(4, 4, 0.2),
              child: SceneRow3d(children: children),
            ),
          ],
        ),
      ),
    );

    testWidgets('autofocus hands the keyboard to the first box', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        scene(
          autofocus: true,
          children: <Widget>[
            for (final label in <String>['first', 'second'])
              SceneActions3d(
                actions: <Type, Action<Intent>>{
                  ActivateIntent: Recording<ActivateIntent>(log, label),
                },
                child: const SceneFocus3d(child: SceneSizedBox3d.cube(1)),
              ),
          ],
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(log, <String>['first', 'second']);
    });

    testWidgets('without autofocus the scene leaves the keyboard alone', (
      tester,
    ) async {
      await tester.pumpWidget(
        scene(
          children: const <Widget>[
            SceneFocus3d(child: SceneSizedBox3d.cube(1)),
          ],
        ),
      );
      await tester.pump();

      final focused = FocusManager.instance.primaryFocus;
      expect(focused == null ? null : Focus3d.layoutFor(focused), isNull);
    });

    testWidgets('the keyboard comes back to where it was', (tester) async {
      final controller = Input3dController();
      final log = <String>[];
      // A focusable widget beside the scene, for the keyboard to wander off
      // to. `unfocus()` would not do: it deliberately erases the scope's
      // memory of what had the focus, which is exactly what this checks.
      final elsewhere = FocusNode(debugLabel: 'elsewhere');
      addTearDown(elsewhere.dispose);
      await tester.pumpWidget(
        Stack(
          alignment: Alignment.topLeft,
          children: <Widget>[
            Focus(focusNode: elsewhere, child: const SizedBox()),
            scene(
              controller: controller,
              children: <Widget>[
                for (final label in <String>['first', 'second'])
                  SceneActions3d(
                    actions: <Type, Action<Intent>>{
                      ActivateIntent: Recording<ActivateIntent>(log, label),
                    },
                    child: const SceneFocus3d(child: SceneSizedBox3d.cube(1)),
                  ),
              ],
            ),
          ],
        ),
      );

      expect(controller.host!.requestSceneFocus(), isTrue);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);

      elsewhere.requestFocus();
      await tester.pump();
      expect(elsewhere.hasPrimaryFocus, isTrue);
      expect(controller.host!.requestSceneFocus(), isTrue);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(log, <String>['second']);
    });

    testWidgets('a shortcut binding updates in place', (tester) async {
      final log = <String>[];
      Widget frame(LogicalKeyboardKey key) => scene(
        autofocus: true,
        children: <Widget>[
          SceneShortcuts3d(
            shortcuts: <ShortcutActivator, Intent>{
              SingleActivator(key): const SaveIntent(),
            },
            child: SceneActions3d(
              actions: <Type, Action<Intent>>{
                SaveIntent: Recording<SaveIntent>(log, key.keyLabel),
              },
              child: const SceneFocus3d(child: SceneSizedBox3d.cube(1)),
            ),
          ),
        ],
      );

      await tester.pumpWidget(frame(LogicalKeyboardKey.keyS));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);

      await tester.pumpWidget(frame(LogicalKeyboardKey.keyD));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);

      expect(log, <String>['S', 'D']);
    });
  });
}
