// A wheel and a trackpad: the scrolling a desktop reaches for first, which
// nothing routed until the host grew a pointer signal and a pan-zoom.
//
// Three layers, bottom up. The controller's `pointerScroll` is arithmetic.
// `PointerScroll3d` and the pan-zoom sequence are the rules — which view takes
// a wheel, and what a pan presses (nothing) — driven with hand-made rays. And
// `SceneInput3d` is the platform's events arriving, including the one thing
// only a widget test can check: that the scene claims a wheel through
// Flutter's resolver, and leaves it for the widget tree around it when it has
// nothing to move.

import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show GestureBinding, PointerDeviceKind, PointerSignalEvent;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show Alignment, HitTestBehavior, Listener, SizedBox, Stack, Widget;
import 'package:flutter_scene/scene.dart' show Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support.dart';

/// A leaf that answers hit tests, which is what real content does.
TestBox solid(Size3d size) => TestBox(size, pointable: true);

/// A vertical list two units tall over eight one-unit rows, so there are six
/// units to scroll. Fifty logical pixels is half a unit, through the standard
/// hundred to the unit.
({
  Layout3dSurface surface,
  ListView3d list,
  Layout3dPointer pointer,
  List<String> log,
})
tallList({Scroll3dPhysics? physics}) {
  final log = <String>[];
  final list = ListView3d(
    controller: physics == null ? null : Scroll3dController(physics: physics),
    children: List.generate(
      8,
      (index) => GestureDetector3d(
        onTap: () => log.add('tap $index'),
        child: TestBox(const Size3d(1, 1, 0)),
      ),
    ),
  );
  final surface = laidOut(
    list,
    constraints: Constraints3d.tight(const Size3d(1, 2, 0)),
  );
  addTearDown(surface.dispose);
  return (
    surface: surface,
    list: list,
    pointer: Layout3dPointer(surface),
    log: log,
  );
}

/// The middle of the list's window.
const Offset3d middle = Offset3d(0.5, 1.0, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the controller', () {
    Scroll3dController measured() =>
        Scroll3dController()
          ..applyViewportMetrics(maxScrollExtent: 6, viewportExtent: 2);

    test('a wheel jumps, and reports that it moved', () {
      final controller = measured();

      expect(controller.pointerScroll(0.5), isTrue);

      expect(controller.offset, 0.5);
      expect(controller.isAnimating, isFalse, reason: 'a jump, not a tween');
    });

    test('a wheel stops at the end whatever the physics allows', () {
      // A bouncing list would let a drag pull past the end. A wheel has no
      // finger to let go of, so nothing would ever spring it back.
      final controller = Scroll3dController(physics: BouncingScroll3dPhysics())
        ..applyViewportMetrics(maxScrollExtent: 6, viewportExtent: 2);

      controller.pointerScroll(10);
      expect(controller.offset, 6);

      expect(controller.pointerScroll(1), isFalse);
      expect(controller.offset, 6);
      expect(controller.pointerScrollTarget(1), 6);
    });

    test('the direction reads as the viewer scrolling, then goes idle', () {
      final controller = measured();
      final seen = <ScrollDirection3d>[];
      controller.addListener(() => seen.add(controller.userScrollDirection));

      controller.pointerScroll(1);
      controller.pointerScroll(-0.5);

      expect(seen, <ScrollDirection3d>[
        ScrollDirection3d.reverse,
        ScrollDirection3d.forward,
      ]);
      expect(controller.userScrollDirection, ScrollDirection3d.idle);
    });

    testWidgets('a zero wheel stops what was coasting', (tester) async {
      final controller = measured();
      addTearDown(controller.dispose);
      controller.fling(20);
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.isAnimating, isTrue);

      expect(controller.pointerScroll(0), isFalse);

      expect(controller.isAnimating, isFalse);
    });

    testWidgets('a page view settles on a page after a notch', (tester) async {
      final controller = Scroll3dController(physics: PageScroll3dPhysics())
        ..applyViewportMetrics(maxScrollExtent: 3, viewportExtent: 1);
      addTearDown(controller.dispose);

      controller.pointerScroll(0.3);
      expect(controller.offset, closeTo(0.3, 1e-9));
      expect(controller.isAnimating, isTrue, reason: 'the settle, at rest');

      await tester.pumpAndSettle();

      expect(controller.offset, closeTo(0.0, 1e-6));
    });
  });

  group('which view takes a wheel', () {
    test('the list under the ray, by the vertical half of the delta', () {
      final panel = tallList();

      final scroll = panel.pointer.resolveScroll(
        rayAt(panel.surface, middle),
        const Offset(0, 50),
      );

      expect(scroll, isNotNull);
      expect(scroll!.scrollable, same(panel.list));
      expect(scroll.delta, closeTo(0.5, 1e-9));
      expect(panel.list.controller.offset, 0.0, reason: 'resolved, not moved');

      expect(scroll.apply(), isTrue);
      expect(panel.list.controller.offset, closeTo(0.5, 1e-9));
    });

    test('a sideways wheel does not move a vertical list', () {
      final panel = tallList();

      expect(
        panel.pointer.resolveScroll(
          rayAt(panel.surface, middle),
          const Offset(50, 0),
        ),
        isNull,
      );
    });

    test('a list already at its end declines', () {
      final panel = tallList();
      final ray = rayAt(panel.surface, middle);

      expect(panel.pointer.resolveScroll(ray, const Offset(0, -50)), isNull);

      panel.list.controller.jumpTo(6);
      panel.surface.flush();
      expect(panel.pointer.resolveScroll(ray, const Offset(0, 50)), isNull);
    });

    test('a wheel scrolls through a sideways view to the list around it', () {
      final carousel = ListView3d(
        scrollDirection: Axis3d.horizontal,
        children: List.generate(6, (_) => solid(const Size3d(1, 1, 0))),
      );
      final outer = ListView3d(
        children: <Layout3d>[
          SizedBox3d(width: 2, height: 1, child: carousel),
          ...List.generate(6, (_) => solid(const Size3d(2, 1, 0))),
        ],
      );
      final surface = laidOut(
        outer,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      addTearDown(surface.dispose);
      final pointer = Layout3dPointer(surface);
      final overCarousel = rayAt(surface, const Offset3d(1, 0.5, 0));

      expect(
        pointer.resolveScroll(overCarousel, const Offset(0, 50))!.scrollable,
        same(outer),
      );
      expect(
        pointer.resolveScroll(overCarousel, const Offset(50, 0))!.scrollable,
        same(carousel),
      );

      // At the carousel's end a sideways wheel has nowhere to go, and the
      // list around it does not scroll sideways either.
      carousel.controller.jumpTo(carousel.controller.maxScrollExtent);
      surface.flush();
      expect(pointer.resolveScroll(overCarousel, const Offset(50, 0)), isNull);
    });

    test('a wheel at the end of an inner list goes on to the outer one', () {
      final inner = ListView3d(
        children: List.generate(4, (_) => solid(const Size3d(2, 1, 0))),
      );
      final outer = ListView3d(
        children: <Layout3d>[
          SizedBox3d(width: 2, height: 1, child: inner),
          ...List.generate(6, (_) => solid(const Size3d(2, 1, 0))),
        ],
      );
      final surface = laidOut(
        outer,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      addTearDown(surface.dispose);
      final pointer = Layout3dPointer(surface);
      final overInner = rayAt(surface, const Offset3d(1, 0.5, 0));

      expect(
        pointer.resolveScroll(overInner, const Offset(0, 50))!.scrollable,
        same(inner),
      );

      inner.controller.jumpTo(inner.controller.maxScrollExtent);
      surface.flush();

      expect(
        pointer.resolveScroll(overInner, const Offset(0, 50))!.scrollable,
        same(outer),
      );
    });

    test('the delta is taken through the surface\'s metrics', () {
      final list = ListView3d(
        children: List.generate(8, (_) => solid(const Size3d(1, 1, 0))),
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(1, 2, 0)),
        metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.001),
      );
      addTearDown(surface.dispose);

      final scroll = Layout3dPointer(
        surface,
      ).resolveScroll(rayAt(surface, middle), const Offset(0, 100));

      expect(scroll!.delta, closeTo(0.1, 1e-9));
    });
  });

  group('across surfaces', () {
    test('a dialog in front takes the wheel even with nothing to scroll', () {
      final panel = tallList();
      final dialog = laidOut(
        solid(const Size3d(1, 2, 0)),
        constraints: Constraints3d.tight(const Size3d(1, 2, 0)),
      );
      addTearDown(dialog.dispose);
      final group = Layout3dPointerGroup()
        ..addSurface(panel.surface)
        ..addSurface(dialog, zOrder: 1);
      final ray = rayAt(panel.surface, middle);

      expect(group.resolveScroll(ray, const Offset(0, 50)), isNull);
      expect(group.lastHit.firstOf<TestBox>(), isNotNull);

      group.addSurface(dialog, zOrder: 1, absorbs: false);
      expect(
        group.resolveScroll(ray, const Offset(0, 50))?.scrollable,
        same(panel.list),
      );
    });
  });

  group('a trackpad pan', () {
    test('moves the list with the fingers and presses nothing', () {
      final panel = tallList();

      expect(
        panel.pointer.panZoomStart(
          rayAt(panel.surface, const Offset3d(0.5, 1.5, 0)),
          timeStamp: Duration.zero,
        ),
        isTrue,
      );
      panel.pointer.panZoomUpdate(
        rayAt(panel.surface, const Offset3d(0.5, 1.0, 0)),
        timeStamp: const Duration(milliseconds: 100),
      );
      panel.pointer.panZoomEnd(timeStamp: const Duration(milliseconds: 1000));
      panel.surface.flush();

      // From the first move, with no slop: nothing competed for a pan, so
      // there was nothing to wait for.
      expect(panel.list.controller.offset, closeTo(0.5, 1e-9));
      expect(panel.log, isEmpty, reason: 'a pan is not a tap');
    });

    testWidgets('lets the list go at the speed the fingers were moving', (
      tester,
    ) async {
      final panel = tallList();
      final pointer = panel.pointer;

      pointer.panZoomStart(
        rayAt(panel.surface, const Offset3d(0.5, 1.9, 0)),
        timeStamp: Duration.zero,
      );
      for (var step = 1; step <= 6; step++) {
        pointer.panZoomUpdate(
          rayAt(panel.surface, Offset3d(0.5, 1.9 - step * 0.2, 0)),
          timeStamp: Duration(milliseconds: step * 16),
        );
      }
      final released = panel.list.controller.offset;
      pointer.panZoomEnd(timeStamp: const Duration(milliseconds: 100));

      expect(panel.list.controller.isAnimating, isTrue);
      await tester.pumpAndSettle();
      expect(panel.list.controller.offset, greaterThan(released));
    });

    test('grabs nothing where there is nothing to scroll', () {
      final surface = laidOut(
        solid(const Size3d(1, 1, 0)),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      addTearDown(surface.dispose);
      final pointer = Layout3dPointer(surface);

      expect(
        pointer.panZoomStart(rayAt(surface, const Offset3d(0.5, 0.5, 0))),
        isFalse,
      );
      expect(pointer.isDown(0), isFalse);
    });

    testWidgets('fingers landing on a coasting list stop it', (tester) async {
      final panel = tallList();
      panel.list.controller.fling(20);
      await tester.pump(const Duration(milliseconds: 16));
      expect(panel.list.controller.isAnimating, isTrue);

      panel.pointer.cancelScrollInertia(rayAt(panel.surface, middle));

      expect(panel.list.controller.isAnimating, isFalse);
    });

    test('a group keeps the pan on the surface that grabbed it', () {
      final panel = tallList();
      final other = laidOut(
        solid(const Size3d(1, 2, 0)),
        constraints: Constraints3d.tight(const Size3d(1, 2, 0)),
      );
      addTearDown(other.dispose);
      final group = Layout3dPointerGroup()
        ..addSurface(panel.surface)
        ..addSurface(other, zOrder: -1);

      expect(
        group.panZoomStart(rayAt(panel.surface, const Offset3d(0.5, 1.5, 0))),
        isTrue,
      );
      // Taking the list's surface out mid-pan leaves nothing holding it.
      group.panZoomUpdate(rayAt(panel.surface, const Offset3d(0.5, 1.0, 0)));
      panel.surface.flush();
      expect(panel.list.controller.offset, closeTo(0.5, 1e-9));

      group.removeSurface(panel.surface);
      expect(
        group.panZoomUpdate(rayAt(panel.surface, const Offset3d(0.5, 0.5, 0))),
        isFalse,
      );
    });
  });

  group('through SceneInput3d', () {
    PerspectiveCamera camera() => PerspectiveCamera(
      fovRadiansY: math.pi / 4,
      position: Vector3(0, 0, 5),
      target: Vector3(0, 0, 0),
    );
    const center = Offset(400, 300);

    /// A four-unit panel filling the view, holding a list of one-unit rows.
    Widget scene({
      required Scroll3dController controller,
      Axis3d axis = Axis3d.vertical,
      List<String>? log,
      Input3dHitCallback? onHit,
    }) => SceneInput3d(
      camera: camera(),
      onHit: onHit,
      child: SizedBox.expand(
        child: Stack(
          alignment: Alignment.topLeft,
          children: <Widget>[
            SceneLayout3d(
              parent: Node(),
              size: const Size3d(4, 4, 0.2),
              child: SceneListView3d(
                controller: controller,
                scrollDirection: axis,
                children: List.generate(
                  12,
                  (index) => SceneGestureDetector3d(
                    onTap: () => log?.add('tap $index'),
                    child: const SceneSizedBox3d.cube(1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    testWidgets('a wheel over the list scrolls it, and says so', (
      tester,
    ) async {
      final controller = Scroll3dController();
      addTearDown(controller.dispose);
      final hits = <Input3dHit>[];
      await tester.pumpWidget(scene(controller: controller, onHit: hits.add));

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 50)));

      expect(controller.offset, closeTo(0.5, 1e-9));
      final scroll = hits.lastWhere((h) => h.phase == Input3dHitPhase.scroll);
      expect(scroll.grabbedScrollable, isTrue);
      expect(scroll.result.isEmpty, isFalse);
    });

    testWidgets('Shift turns a mouse wheel sideways', (tester) async {
      final controller = Scroll3dController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        scene(controller: controller, axis: Axis3d.horizontal),
      );

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 50)));
      expect(controller.offset, 0.0, reason: 'a vertical wheel, unshifted');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 50)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(controller.offset, closeTo(0.5, 1e-9));
    });

    testWidgets(
      'the scene leaves a wheel it cannot use to the tree around it',
      (tester) async {
        final controller = Scroll3dController();
        addTearDown(controller.dispose);
        final outside = <String>[];
        // A widget-tree scroll view around the scene, standing in for a page
        // the scene is one part of. It registers after the scene does, because
        // it is further from the pointer in the hit test. Opaque, as a
        // `Scrollable` is by default: the scene's own listener is translucent,
        // so a parent that deferred to it would not be in the path at all.
        await tester.pumpWidget(
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (PointerSignalEvent event) {
              GestureBinding.instance.pointerSignalResolver.register(
                event,
                (_) => outside.add('page scrolled'),
              );
            },
            child: scene(controller: controller),
          ),
        );
        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(mouse.hover(center));

        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 50)));
        expect(outside, isEmpty);
        expect(controller.offset, closeTo(0.5, 1e-9));

        // Upward past the start: the list has nowhere to go, so it does not
        // claim the wheel, and the page gets it.
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, -500)));
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, -50)));
        expect(controller.offset, 0.0);
        expect(outside, <String>['page scrolled']);
      },
    );

    testWidgets('two fingers scroll the list and tap nothing', (tester) async {
      final controller = Scroll3dController();
      addTearDown(controller.dispose);
      final log = <String>[];
      final hits = <Input3dHit>[];
      await tester.pumpWidget(
        scene(controller: controller, log: log, onHit: hits.add),
      );

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(center);
      await gesture.panZoomUpdate(
        center,
        pan: const Offset(0, -100),
        timeStamp: const Duration(milliseconds: 500),
      );
      await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      // Fingers up the pad move the content up, which is further into the
      // list. A hundred pixels of screen is most of a unit on a panel that
      // fills six hundred of them with a little over four.
      expect(controller.offset, greaterThan(0.5));
      expect(controller.offset, lessThan(1.0));
      expect(log, isEmpty);
      expect(
        hits
            .where((h) => h.phase == Input3dHitPhase.scroll)
            .single
            .grabbedScrollable,
        isTrue,
      );
    });

    testWidgets('a wheel event that is not a scroll changes nothing', (
      tester,
    ) async {
      final controller = Scroll3dController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(scene(controller: controller));

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.sendEventToBinding(mouse.scale(2.0));

      expect(controller.offset, 0.0);
    });
  });
}
