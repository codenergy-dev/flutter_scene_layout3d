import 'package:flutter/gestures.dart'
    show
        PointerDownEvent,
        PointerEnterEvent,
        PointerEvent,
        PointerExitEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerUpEvent;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A listener that writes down what reached it, in the order it arrived.
Listener3d recorder(
  String label,
  List<String> log, {
  HitTestBehavior3d behavior = HitTestBehavior3d.deferToChild,
  Layout3d? child,
}) => Listener3d(
  behavior: behavior,
  onPointerDown: (_) => log.add('$label down'),
  onPointerMove: (_) => log.add('$label move'),
  onPointerUp: (_) => log.add('$label up'),
  onPointerCancel: (_) => log.add('$label cancel'),
  onPointerEnter: (_) => log.add('$label enter'),
  onPointerExit: (_) => log.add('$label exit'),
  onPointerHover: (_) => log.add('$label hover'),
  child: child,
);

void main() {
  group('dispatch', () {
    test('a press reaches every listener on the path, deepest first', () {
      final log = <String>[];
      final leaf = recorder(
        'leaf',
        log,
        behavior: HitTestBehavior3d.opaque,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final middle = recorder('middle', log, child: leaf);
      final outer = recorder('outer', log, child: Center3d(child: middle));
      final surface = laidOut(
        outer,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(1, 1, 0)));

      expect(log, ['leaf down', 'middle down', 'outer down']);
    });

    test('the box under the ray is three levels down and still hears it', () {
      final log = <String>[];
      final target = recorder(
        'target',
        log,
        behavior: HitTestBehavior3d.opaque,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        Column3d(
          children: [
            Row3d(children: [Center3d(child: target)]),
          ],
        ),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));

      expect(log, ['target down']);
    });

    test('an AbsorbPointer3d in between takes the press instead', () {
      final log = <String>[];
      final target = recorder(
        'target',
        log,
        behavior: HitTestBehavior3d.opaque,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final outer = recorder(
        'outer',
        log,
        child: AbsorbPointer3d(child: target),
      );
      final surface = laidOut(
        outer,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));

      expect(log, ['outer down'], reason: 'the absorber swallowed it');
    });

    test('the path is captured, so a move that leaves the box still lands', () {
      final positions = <Offset3d>[];
      final listener = Listener3d(
        behavior: HitTestBehavior3d.opaque,
        onPointerMove: (event) => positions.add(event.localPosition),
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        Center3d(child: listener),
        constraints: Constraints3d.tight(const Size3d(4, 4, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(2, 2, 0)));
      // Well outside the box: a fresh hit test would find nothing there.
      pointer.move(rayAt(surface, const Offset3d(3.5, 2, 0)));

      expect(surface.hitTestAt(const Offset3d(3.5, 2, 0)).isEmpty, isTrue);
      expect(positions, hasLength(1));
      expect(rounded(positions.single).x, closeTo(2.0, 1e-6));
    });

    test('a cancel is dispatched and ends the sequence', () {
      final log = <String>[];
      final surface = laidOut(
        recorder(
          'box',
          log,
          behavior: HitTestBehavior3d.opaque,
          child: TestBox(const Size3d(1, 1, 0)),
        ),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
      pointer.cancel();

      expect(log, ['box down', 'box cancel']);
      expect(pointer.isDown(0), isFalse);
      expect(
        pointer.move(rayAt(surface, const Offset3d(0.5, 0.5, 0))),
        isFalse,
      );
    });

    test('a hidden subtree receives nothing', () {
      final log = <String>[];
      final surface = laidOut(
        Stack3d(
          children: [
            TestBox(const Size3d(1, 1, 0), pointable: true),
            Offstage3d(
              child: recorder(
                'hidden',
                log,
                behavior: HitTestBehavior3d.opaque,
                child: TestBox(const Size3d(1, 1, 0)),
              ),
            ),
          ],
        ),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));

      expect(log, isEmpty);
    });

    test('the event carries the position in the box own frame, and in dp', () {
      PointerEvent3d? seen;
      final listener = Listener3d(
        behavior: HitTestBehavior3d.opaque,
        onPointerDown: (event) => seen = event,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        Center3d(child: listener),
        constraints: Constraints3d.tight(const Size3d(3, 3, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(1.25, 1.25, 0)));

      expect(seen, isNotNull);
      // A quarter of the way into a one-unit box that sits at (1, 1).
      expect(rounded(seen!.localPosition).x, closeTo(0.25, 1e-6));
      expect(rounded(seen!.localPosition).y, closeTo(0.25, 1e-6));
      // The same point in logical pixels, at the standard hundred per unit.
      expect(seen!.localOffset.dx, closeTo(25.0, 1e-4));
      // And the Flutter event says where it is on the surface, in dp.
      expect(seen!.event.position.dx, closeTo(125.0, 1e-4));
      expect(seen!.event.localPosition.dx, closeTo(25.0, 1e-4));
      expect(seen!.event, isA<PointerDownEvent>());
    });
  });

  group('hit test behaviour', () {
    ({Layout3dSurface surface, List<String> log}) paddedButton(
      HitTestBehavior3d behavior,
    ) {
      final log = <String>[];
      final button = recorder(
        'button',
        log,
        behavior: behavior,
        child: Padding3d(
          padding: const EdgeInsets3d.all(0.5),
          child: IgnorePointer3d(child: TestBox(const Size3d(1, 1, 0))),
        ),
      );
      return (
        surface: laidOut(
          Center3d(child: button),
          constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
        ),
        log: log,
      );
    }

    test('opaque makes a padded button padding pressable', () {
      final panel = paddedButton(HitTestBehavior3d.opaque);
      final pointer = Layout3dPointer(panel.surface);

      // A quarter of a unit in from the corner: inside the padding, outside
      // the label.
      pointer.down(rayAt(panel.surface, const Offset3d(0.25, 0.25, 0)));

      expect(panel.log, ['button down']);
    });

    test('deferToChild does not', () {
      final panel = paddedButton(HitTestBehavior3d.deferToChild);
      final pointer = Layout3dPointer(panel.surface);

      pointer.down(rayAt(panel.surface, const Offset3d(0.25, 0.25, 0)));

      expect(panel.log, isEmpty);
    });

    test('translucent hears the pointer and lets the ray through', () {
      final log = <String>[];
      final behind = TestBox(const Size3d(1, 1, 0), pointable: true);
      final front = recorder(
        'veil',
        log,
        behavior: HitTestBehavior3d.translucent,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        Stack3d(children: [behind, front]),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));

      // The veil is on the path, ahead of the box it did not stop the ray
      // reaching: both are in, and both would be told about the pointer.
      expect(pointer.lastHit.path.map((entry) => entry.layout).toList(), [
        front,
        behind,
        isA<Stack3d>(),
        surface,
      ]);
      expect(log, ['veil down'], reason: 'and the veil heard it anyway');
    });
  });

  group('hover', () {
    ({Layout3dSurface surface, List<String> log, Layout3dPointer pointer})
    twoPanels() {
      final log = <String>[];
      final left = recorder(
        'left',
        log,
        behavior: HitTestBehavior3d.opaque,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final right = recorder(
        'right',
        log,
        behavior: HitTestBehavior3d.opaque,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        Row3d(children: [left, right]),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      return (surface: surface, log: log, pointer: Layout3dPointer(surface));
    }

    test('crossing a boundary exits one panel and enters the other', () {
      final panels = twoPanels();

      panels.pointer.hover(rayAt(panels.surface, const Offset3d(0.5, 0.5, 0)));
      expect(panels.log, ['left enter', 'left hover']);

      panels.log.clear();
      panels.pointer.hover(rayAt(panels.surface, const Offset3d(1.5, 0.5, 0)));

      expect(panels.log, ['left exit', 'right enter', 'right hover']);
    });

    test('moving inside the same panel is a hover and nothing more', () {
      final panels = twoPanels();

      panels.pointer.hover(rayAt(panels.surface, const Offset3d(0.2, 0.2, 0)));
      panels.log.clear();
      panels.pointer.hover(rayAt(panels.surface, const Offset3d(0.8, 0.8, 0)));

      expect(panels.log, ['left hover']);
    });

    test('leaving the surface entirely exits everything', () {
      final panels = twoPanels();

      panels.pointer.hover(rayAt(panels.surface, const Offset3d(0.5, 0.5, 0)));
      panels.log.clear();
      // Off the plane: the hit test finds nothing at all.
      panels.pointer.hover(rayAt(panels.surface, const Offset3d(9, 9, 0)));

      expect(panels.log, ['left exit']);
      expect(panels.pointer.hoveredFor(0), isEmpty);
    });

    test('exit takes the pointer off without a ray', () {
      final panels = twoPanels();

      panels.pointer.hover(rayAt(panels.surface, const Offset3d(0.5, 0.5, 0)));
      panels.log.clear();
      panels.pointer.exit();

      expect(panels.log, ['left exit']);
    });

    test('enter runs outermost first, so a card knows before its label', () {
      final log = <String>[];
      final inner = recorder(
        'inner',
        log,
        behavior: HitTestBehavior3d.opaque,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final outer = recorder(
        'outer',
        log,
        behavior: HitTestBehavior3d.opaque,
        child: inner,
      );
      final surface = laidOut(
        outer,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );

      Layout3dPointer(
        surface,
      ).hover(rayAt(surface, const Offset3d(0.5, .5, 0)));

      expect(log, ['outer enter', 'inner enter', 'inner hover', 'outer hover']);
    });

    test('the hover events are the Flutter ones', () {
      final events = <PointerEvent>[];
      final surface = laidOut(
        Listener3d(
          behavior: HitTestBehavior3d.opaque,
          onPointerEnter: (event) => events.add(event.event),
          onPointerHover: (event) => events.add(event.event),
          onPointerExit: (event) => events.add(event.event),
          child: TestBox(const Size3d(1, 1, 0)),
        ),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.hover(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
      pointer.exit();

      expect(events, [
        isA<PointerEnterEvent>(),
        isA<PointerHoverEvent>(),
        isA<PointerExitEvent>(),
      ]);
    });
  });

  group('several pointers', () {
    test('two fingers drive two lists independently', () {
      final left = ListView3d(
        children: List.generate(
          8,
          (index) => TestBox(const Size3d(1, 1, 0), pointable: true),
        ),
      );
      final right = ListView3d(
        children: List.generate(
          8,
          (index) => TestBox(const Size3d(1, 1, 0), pointable: true),
        ),
      );
      final surface = laidOut(
        Row3d(
          children: [
            SizedBox3d(width: 1, child: left),
            SizedBox3d(width: 1, child: right),
          ],
        ),
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      final pointer = Layout3dPointer(surface);

      expect(
        pointer.down(rayAt(surface, const Offset3d(0.5, 1.5, 0)), pointer: 1),
        isTrue,
      );
      expect(
        pointer.down(rayAt(surface, const Offset3d(1.5, 1.5, 0)), pointer: 2),
        isTrue,
      );
      expect(pointer.draggedScrollableFor(1), same(left));
      expect(pointer.draggedScrollableFor(2), same(right));

      pointer.move(rayAt(surface, const Offset3d(0.5, 1.0, 0)), pointer: 1);
      surface.flush();

      expect(left.controller.offset, closeTo(0.5, 1e-6));
      expect(right.controller.offset, 0.0, reason: 'the other finger held');

      pointer.up(pointer: 1);

      expect(pointer.draggedScrollableFor(1), isNull);
      expect(pointer.draggedScrollableFor(2), same(right));
    });

    test('each pointer hovers on its own account', () {
      final log = <String>[];
      final left = recorder(
        'left',
        log,
        behavior: HitTestBehavior3d.opaque,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final right = recorder(
        'right',
        log,
        behavior: HitTestBehavior3d.opaque,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        Row3d(children: [left, right]),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.hover(rayAt(surface, const Offset3d(0.5, 0.5, 0)), pointer: 1);
      pointer.hover(rayAt(surface, const Offset3d(1.5, 0.5, 0)), pointer: 2);

      expect(pointer.hoveredFor(1), contains(left));
      expect(pointer.hoveredFor(2), contains(right));

      log.clear();
      pointer.exit(pointer: 1);

      expect(log, ['left exit'], reason: 'the second pointer is still there');
      expect(pointer.hoveredFor(2), contains(right));
    });
  });

  group('TapTarget3d', () {
    ({Layout3dSurface surface, TapTarget3d target, TestBox icon}) toolbar() {
      // 24dp of icon in a 100dp-wide surface, at the standard hundred logical
      // pixels to the unit.
      final icon = TestBox(const Size3d(0.24, 0.24, 0), pointable: true);
      final target = TapTarget3d(child: icon);
      final surface = laidOut(
        Center3d(child: target),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      return (surface: surface, target: target, icon: icon);
    }

    test('answers a ray 48dp across, though it is 24dp of content', () {
      final panel = toolbar();

      // The icon spans 0.38 to 0.62; the target reaches 0.26 to 0.74.
      expect(
        panel.surface.hitTestAt(const Offset3d(0.3, 0.5, 0)).target,
        same(panel.target),
      );
      expect(
        panel.surface.hitTestAt(const Offset3d(0.5, 0.5, 0)).target,
        same(panel.icon),
        reason: 'the content still answers where it is',
      );
      expect(
        panel.surface.hitTestAt(const Offset3d(0.2, 0.5, 0)).isEmpty,
        isTrue,
        reason: 'and the reach stops at 48dp',
      );
    });

    test('takes no room: the box is its child size and nothing moved', () {
      final panel = toolbar();

      expect(panel.target.size, const Size3d(0.24, 0.24, 0));
      expect(panel.icon.size, const Size3d(0.24, 0.24, 0));
      expect(translationOf(panel.target).x, closeTo(0.38, 1e-6));
    });

    test('a target already big enough is left alone', () {
      final big = TestBox(const Size3d(0.8, 0.8, 0), pointable: true);
      final target = TapTarget3d(child: big);
      final surface = laidOut(
        Center3d(child: target),
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );

      expect(target.slop, Offset3d.zero);
      expect(surface.hitTestAt(const Offset3d(0.5, 1, 0)).isEmpty, isTrue);
    });

    test('the minimum is read through the metrics, so density carries', () {
      final icon = TestBox(const Size3d(0.24, 0.24, 0), pointable: true);
      final target = TapTarget3d(child: icon);
      final surface = laidOut(
        Center3d(child: target),
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
        metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.02),
      );

      // Twice the scale, so 48dp is 0.96 units and the reach is wider.
      expect(target.effectiveMinimumSize.width, closeTo(0.96, 1e-9));
      expect(surface.hitTestAt(const Offset3d(0.6, 1, 0)).target, same(target));
    });
  });

  group('the sequence itself', () {
    test('a press that hits nothing starts no sequence', () {
      final surface = laidOut(
        TestBox(const Size3d(1, 1, 0), pointable: true),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      expect(pointer.down(rayAt(surface, const Offset3d(5, 5, 0))), isFalse);
      expect(pointer.isDown(0), isFalse);
      expect(pointer.pathFor(0), isNull);
    });

    test('a second press on the same id cancels the first', () {
      final log = <String>[];
      final surface = laidOut(
        recorder(
          'box',
          log,
          behavior: HitTestBehavior3d.opaque,
          child: TestBox(const Size3d(1, 1, 0)),
        ),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));

      expect(log, ['box down', 'box cancel', 'box down']);
    });

    test('dispose cancels what is down and exits what is hovered', () {
      final log = <String>[];
      final surface = laidOut(
        recorder(
          'box',
          log,
          behavior: HitTestBehavior3d.opaque,
          child: TestBox(const Size3d(1, 1, 0)),
        ),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)), pointer: 1);
      pointer.hover(rayAt(surface, const Offset3d(0.5, 0.5, 0)), pointer: 2);
      log.clear();
      pointer.dispose();

      expect(log, ['box cancel', 'box exit']);
    });

    test('the Flutter events are the Flutter ones, in order', () {
      final events = <PointerEvent>[];
      final positions = <double>[];
      final surface = laidOut(
        Center3d(
          child: Listener3d(
            behavior: HitTestBehavior3d.opaque,
            onPointerDown: (event) => events.add(event.event),
            onPointerMove: (event) => events.add(event.event),
            onPointerUp: (event) {
              events.add(event.event);
              positions.add(event.localPosition.x);
            },
            child: TestBox(const Size3d(1, 1, 0)),
          ),
        ),
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(1, 1, 0)));
      pointer.move(rayAt(surface, const Offset3d(1.2, 1, 0)));
      pointer.up();

      expect(events, [
        isA<PointerDownEvent>(),
        isA<PointerMoveEvent>(),
        isA<PointerUpEvent>(),
      ]);
      // An up with no ray of its own reports where the pointer got to, not
      // where it started.
      expect(positions.single, closeTo(0.7, 1e-6));
    });
  });
}
