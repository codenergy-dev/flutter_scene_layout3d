// GestureDetector3d: Flutter's own recognizers, driven from a plane.
//
// These need Flutter's gesture binding, because a GestureRecognizer reaches
// for `GestureBinding.instance` itself — the arena and the pointer router are
// global, and that is the one assumption the whole design rests on.

import 'dart:ui' show Color;

import 'package:flutter/gestures.dart'
    show DragStartDetails, TapDownDetails, kPressTimeout;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a tap on a panel', () {
    test('fires, and reports where it landed in the box own frame', () {
      var taps = 0;
      TapDownDetails? down;
      final button = GestureDetector3d(
        onTap: () => taps++,
        onTapDown: (details) => down = details,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        Center3d(child: button),
        constraints: Constraints3d.tight(const Size3d(3, 3, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(1.25, 1.5, 0)));
      pointer.up();

      expect(taps, 1);
      // A quarter of the way into a box that starts at x = 1, in logical
      // pixels at the standard hundred to the unit.
      expect(down, isNotNull);
      expect(down!.localPosition.dx, closeTo(25.0, 1e-3));
      expect(down!.globalPosition.dx, closeTo(125.0, 1e-3));
    });

    test('the padding around the label is part of the target', () {
      var taps = 0;
      final button = GestureDetector3d(
        onTap: () => taps++,
        child: Padding3d(
          padding: const EdgeInsets3d.all(0.5),
          child: IgnorePointer3d(child: TestBox(const Size3d(1, 1, 0))),
        ),
      );
      final surface = laidOut(
        button,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      final pointer = Layout3dPointer(surface);

      // Inside the padding, outside the label.
      pointer.down(rayAt(surface, const Offset3d(0.25, 0.25, 0)));
      pointer.up();

      expect(taps, 1);
    });

    test('a press that wanders off the panel does not tap', () async {
      var taps = 0;
      var cancels = 0;
      final button = GestureDetector3d(
        onTap: () => taps++,
        onTapCancel: () => cancels++,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        Center3d(child: button),
        constraints: Constraints3d.tight(const Size3d(4, 4, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(2, 2, 0)));
      // A tap is only cancelled once it was announced, and it is announced on
      // Flutter's press deadline, so that a scroll starting a moment after
      // the finger lands does not flash the button.
      await Future<void>.delayed(kPressTimeout * 2);
      // A unit and a half away, well past the tap slop.
      pointer.move(rayAt(surface, const Offset3d(3.5, 2, 0)));
      pointer.up();

      expect(taps, 0);
      expect(cancels, 1);
    });

    test('a detector with no callbacks owns no recognizers', () {
      final detector = GestureDetector3d(child: TestBox(const Size3d(1, 1, 0)));
      final surface = laidOut(
        detector,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );

      Layout3dPointer(surface).down(rayAt(surface, const Offset3d(0.5, .5, 0)));

      expect(detector.recognizers, isEmpty);
    });

    test(
      'a callback set after the fact arms a recognizer at the next press',
      () {
        var taps = 0;
        final detector = GestureDetector3d(
          child: TestBox(const Size3d(1, 1, 0)),
        );
        final surface = laidOut(
          detector,
          constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
        );
        final pointer = Layout3dPointer(surface);

        detector.onTap = () => taps++;
        pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
        pointer.up();

        expect(taps, 1);
        expect(detector.recognizers, hasLength(1));
      },
    );
  });

  group('a tap against a drag', () {
    ({
      Layout3dSurface surface,
      ListView3d list,
      Layout3dPointer pointer,
      List<String> log,
    })
    listOfButtons() {
      final log = <String>[];
      final list = ListView3d(
        children: List.generate(
          8,
          (index) => GestureDetector3d(
            onTap: () => log.add('tap $index'),
            onTapCancel: () => log.add('cancel $index'),
            child: TestBox(const Size3d(1, 1, 0)),
          ),
        ),
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(1, 2, 0)),
      );
      return (
        surface: surface,
        list: list,
        pointer: Layout3dPointer(surface),
        log: log,
      );
    }

    test('a press and a lift is a tap, and the list stays put', () {
      final panel = listOfButtons();

      panel.pointer.down(rayAt(panel.surface, const Offset3d(0.5, 1.5, 0)));
      panel.pointer.up();
      panel.surface.flush();

      expect(panel.log, ['tap 1']);
      expect(panel.list.controller.offset, 0.0);
    });

    test('a press and a drag scrolls the list, and nothing is tapped', () {
      final panel = listOfButtons();

      panel.pointer.down(rayAt(panel.surface, const Offset3d(0.5, 1.5, 0)));
      panel.pointer.move(rayAt(panel.surface, const Offset3d(0.5, 1.0, 0)));
      panel.pointer.up();
      panel.surface.flush();

      expect(panel.log, isNot(contains('tap 1')));
      expect(panel.list.controller.offset, closeTo(0.5, 1e-6));
    });

    test('the content ends up where the finger is, slop included', () {
      final panel = listOfButtons();

      panel.pointer.down(rayAt(panel.surface, const Offset3d(0.5, 1.5, 0)));
      // One move, in one go: everything since the press has to arrive, or
      // the content lags the finger by a touch slop for ever after.
      panel.pointer.move(rayAt(panel.surface, const Offset3d(0.5, 1.2, 0)));
      panel.surface.flush();

      expect(panel.list.controller.offset, closeTo(0.3, 1e-6));
    });

    test('a drag under the slop moves nothing at all', () {
      final panel = listOfButtons();

      panel.pointer.down(rayAt(panel.surface, const Offset3d(0.5, 1.5, 0)));
      // Ten logical pixels, at the standard hundred to the unit: under the
      // 18dp Flutter calls a touch slop.
      panel.pointer.move(rayAt(panel.surface, const Offset3d(0.5, 1.4, 0)));
      panel.surface.flush();

      expect(panel.list.controller.offset, 0.0);

      panel.pointer.up();
      panel.surface.flush();

      expect(panel.log, ['tap 1'], reason: 'it was a tap after all');
    });

    test('a list with nothing competing scrolls from the first move', () {
      // The other half of the bargain: without a recognizer in the path
      // there is no arena, no binding and no waiting.
      final list = ListView3d(
        children: List.generate(
          8,
          (index) => TestBox(const Size3d(1, 1, 0), pointable: true),
        ),
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(1, 2, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 1.5, 0)));
      pointer.move(rayAt(surface, const Offset3d(0.5, 1.45, 0)));
      surface.flush();

      expect(list.controller.offset, closeTo(0.05, 1e-6));
    });
  });

  group('the other recognizers', () {
    test('a pan starts where the press was, in logical pixels', () async {
      // What is checked here is the arm and the start. `onPanUpdate` and
      // `onPanEnd` are wired up and are not checked, because
      // `DragGestureRecognizer` does not deliver them in this Flutter build
      // even when driven by hand with no 3D in the picture — the same
      // breakage `LongPressGestureRecognizer` shows below.
      DragStartDetails? start;
      final surface = laidOut(
        GestureDetector3d(
          onPanStart: (details) => start = details,
          onPanUpdate: (_) {},
          onPanEnd: (_) {},
          child: TestBox(const Size3d(2, 2, 0)),
        ),
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(1.5, 1, 0)));
      // A recognizer alone in the arena wins by default rather than by
      // resolution, and Flutter schedules that on a microtask: a real
      // application is between events here, a test has to say so.
      await Future<void>.delayed(Duration.zero);

      expect(start, isNotNull);
      expect(start!.localPosition.dx, closeTo(150.0, 1e-3));

      pointer.up();
    });

    test('a long press arms the recognizer Flutter would arm', () {
      // There is no test here that a long press *fires*, and deliberately:
      // `LongPressGestureRecognizer` does not fire in this Flutter build at
      // all, in a plain widget tree, under `tester.longPress`, with no 3D
      // anywhere near it. What this package owes the recognizer is the down
      // event, which it gets — the same one a `RenderPointerListener` would
      // hand it.
      final detector = GestureDetector3d(
        onLongPress: () {},
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        detector,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );

      Layout3dPointer(surface).down(rayAt(surface, const Offset3d(.5, .5, 0)));

      expect(detector.recognizers, hasLength(1));
      expect(
        detector.recognizers.single.toString(),
        contains('state: possible'),
      );
    });
  });

  group('driving a state layer', () {
    ({Layout3dSurface surface, DecoratedBox3d panel, Layout3dPointer pointer})
    button() {
      final panel = DecoratedBox3d(
        decoration: const BoxDecoration3d(color: Color(0xFF202124)),
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final detector = GestureDetector3d(child: panel);
      const pressed = StateLayer3d(color: Color(0xFFFFFFFF), opacity: 0.12);
      detector.onTapDown = (_) {
        panel.stateLayer = pressed;
      };
      detector.onTapCancel = () {
        panel.stateLayer = StateLayer3d.none;
      };
      detector.onTap = () {
        panel.stateLayer = StateLayer3d.none;
      };
      final surface = laidOut(
        detector,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      return (
        surface: surface,
        panel: panel,
        pointer: Layout3dPointer(surface),
      );
    }

    test(
      'a press wears the layer and a tap takes it off, without a relayout',
      () async {
        final control = button();

        control.pointer.down(rayAt(control.surface, const Offset3d(.5, .5, 0)));
        // The tap down is on a deadline, so that a scroll that starts a moment
        // later does not flash the button: Flutter's kPressTimeout.
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(control.panel.stateLayer.opacity, closeTo(0.12, 1e-9));
        expect(
          control.surface.needsFlush,
          isFalse,
          reason: 'a state layer never dirties layout',
        );

        control.pointer.up();

        expect(control.panel.stateLayer, StateLayer3d.none);
        expect(control.surface.needsFlush, isFalse);
      },
    );

    test('a hover lights the panel and leaving it puts it out', () {
      final panel = DecoratedBox3d(
        decoration: const BoxDecoration3d(color: Color(0xFF202124)),
        child: TestBox(const Size3d(1, 1, 0)),
      );
      const hovered = StateLayer3d(color: Color(0xFFFFFFFF), opacity: 0.08);
      final surface = laidOut(
        Center3d(
          child: Listener3d(
            behavior: HitTestBehavior3d.opaque,
            onPointerEnter: (_) {
              panel.stateLayer = hovered;
            },
            onPointerExit: (_) {
              panel.stateLayer = StateLayer3d.none;
            },
            child: panel,
          ),
        ),
        constraints: Constraints3d.tight(const Size3d(3, 3, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.hover(rayAt(surface, const Offset3d(1.5, 1.5, 0)));

      expect(panel.stateLayer, hovered);
      expect(surface.needsFlush, isFalse);

      pointer.hover(rayAt(surface, const Offset3d(0.1, 0.1, 0)));

      expect(panel.stateLayer, StateLayer3d.none);
      expect(surface.needsFlush, isFalse);
    });
  });
}
