// A route that arrives: the motion a subtree is given, the box that applies
// it on the node tier, and the clock a navigator winds while a route comes in
// and goes out.

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/animation.dart' show AnimationController, Curves;
import 'package:flutter/scheduler.dart'
    show Ticker, TickerCallback, TickerProvider;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dController,
        SceneLayout3d,
        SceneOverlay3d,
        SceneSizedBox3d,
        WidgetPageRoute3d;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support.dart';

/// A provider of bare tickers, for the objects that ask for one outside a
/// `State`.
class _Vsync implements TickerProvider {
  final List<Ticker> tickers = <Ticker>[];

  @override
  Ticker createTicker(TickerCallback onTick) {
    final ticker = Ticker(onTick);
    tickers.add(ticker);
    return ticker;
  }
}

/// Where [layout]'s geometry ends up, in the frame its parent lays out in.
Offset3d placedAt(Layout3d layout) => translationOf(layout);

/// The first box of type [T] at or below [root].
T? findIn<T extends Layout3d>(Layout3d root) {
  if (root is T) return root;
  T? found;
  root.visitChildren((child) => found ??= findIn<T>(child));
  return found;
}

/// A vector matcher that forgives the last few bits of a rotation.
Matcher vectorCloseTo(Vector3 expected) => predicate<Vector3>(
  (actual) =>
      (actual.x - expected.x).abs() < 1e-6 &&
      (actual.y - expected.y).abs() < 1e-6 &&
      (actual.z - expected.z).abs() < 1e-6,
  'close to $expected',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const metrics = Layout3dMetrics.standard;

  group('a motion is a value', () {
    test('the two ways of saying how far add up', () {
      const motion = Motion3d(
        offset: Offset3d(0, 24, 0),
        fraction: Offset3d(0, 1, 0),
      );
      // 24dp is 0.24 units at the standard contract, and the fraction is a
      // whole height of the box itself.
      expect(
        motion.offsetIn(const Size3d(2, 3, 0), metrics),
        const Offset3d(0, 0.24 + 3, 0),
      );
    });

    test('rest carries no transform at all', () {
      expect(Motion3d.none.isAtRest, isTrue);
      expect(Motion3d.none.transformFor(const Size3d(2, 2, 2)), isNull);
      expect(
        const Motion3d(
          offset: Offset3d(1, 0, 0),
        ).transformFor(const Size3d(2, 2, 2)),
        isNull,
        reason: 'a slide is an offset, not a matrix',
      );
    });

    test('a growth pivots on its origin and leaves that point alone', () {
      const size = Size3d(2, 4, 0);
      final transform = const Motion3d.grow(from: 0.5).transformFor(size)!;
      // The centre is the pivot, so it does not move...
      expect(
        transform.transformed3(Vector3(1, 2, 0)),
        vectorCloseTo(Vector3(1, 2, 0)),
      );
      // ... and the corners come halfway in toward it.
      expect(
        transform.transformed3(Vector3(0, 0, 0)),
        vectorCloseTo(Vector3(0.5, 1, 0)),
      );
    });

    test('a growth about a corner holds that corner', () {
      const size = Size3d(2, 4, 0);
      final transform = const Motion3d.grow(
        from: 0.5,
        origin: Alignment3d.topLeft,
      ).transformFor(size)!;
      expect(
        transform.transformed3(Vector3(0, 0, 0)),
        vectorCloseTo(Vector3(0, 0, 0)),
      );
      expect(
        transform.transformed3(Vector3(2, 4, 0)),
        vectorCloseTo(Vector3(1, 2, 0)),
      );
    });

    test('a turn is a hinge, and the axis need not be normalized', () {
      const size = Size3d(2, 2, 0);
      final quarter = const Motion3d.turn(
        radians: math.pi / 2,
        origin: Alignment3d.center,
      ).transformFor(size)!;
      final longAxis = const Motion3d.turn(
        radians: math.pi / 2,
        axis: Offset3d(0, 7, 0),
      ).transformFor(size)!;
      // A quarter turn about the vertical axis takes x into z.
      expect(
        quarter.transformed3(Vector3(2, 1, 0)),
        vectorCloseTo(Vector3(1, 1, -1)),
      );
      expect(
        longAxis.transformed3(Vector3(2, 1, 0)),
        vectorCloseTo(quarter.transformed3(Vector3(2, 1, 0))),
      );
    });

    test('arrival walks the motion back to none', () {
      const motion = Motion3d(fraction: Offset3d(0, 1, 0), scale: 0.5);
      expect(motion.arrived(0), motion);
      expect(motion.arrived(1), Motion3d.none);
      expect(motion.arrived(0.5), Motion3d.lerp(motion, Motion3d.none, 0.5));
      expect(motion.arrived(0.5).scale, closeTo(0.75, 1e-9));
    });

    test('equality is by value, and toString says what moved', () {
      expect(const Motion3d.grow(), const Motion3d(scale: 0.85));
      expect(Motion3d.none.toString(), 'Motion3d.none');
      expect(Motion3d.fromBelow.toString(), contains('fraction'));
    });
  });

  group('the box that applies it', () {
    ({Layout3dSurface surface, MotionTransition3d box, TestBox child}) sheet({
      AnimationController? controller,
      Motion3d motion = Motion3d.fromBelow,
    }) {
      final child = TestBox(const Size3d(2, 3, 0), pointable: true);
      final box = MotionTransition3d(
        animation: controller,
        motion: motion,
        child: child,
      );
      final surface = laidOut(
        box,
        constraints: Constraints3d.tight(const Size3d(2, 3, 0)),
      );
      addTearDown(surface.dispose);
      return (surface: surface, box: box, child: child);
    }

    test('no animation is arrival', () {
      final host = sheet();
      expect(host.box.progress, 1.0);
      expect(host.box.nodeOffset, Offset3d.zero);
      expect(host.box.nodeTransform, isNull);
    });

    testWidgets('the value is applied on layout, not only on a tick', (
      tester,
    ) async {
      final vsync = _Vsync();
      final controller = AnimationController(vsync: vsync, value: 0.0);
      addTearDown(controller.dispose);

      // The first layout is the first chance the box has to know its size,
      // and it is what a route gets: pushed between frames, laid out before
      // anything has ticked.
      final host = sheet(controller: controller);
      expect(host.box.nodeOffset, const Offset3d(0, 3, 0));
      expect(placedAt(host.box), const Offset3d(0, 3, 0));

      controller.value = 0.5;
      expect(host.box.nodeOffset, const Offset3d(0, 1.5, 0));

      controller.value = 1.0;
      expect(host.box.nodeOffset, Offset3d.zero);
      expect(host.box.nodeTransform, isNull);
      expect(
        host.surface.needsFlush,
        isFalse,
        reason: 'the whole run is the node tier',
      );
    });

    test('a ray still finds the child where layout put it', () {
      final vsync = _Vsync();
      final controller = AnimationController(vsync: vsync, value: 0.0);
      addTearDown(controller.dispose);
      final host = sheet(controller: controller);

      expect(host.box.nodeOffset, const Offset3d(0, 3, 0));
      expect(
        host.surface.hitTestAt(const Offset3d(1, 1.5, 0)).target,
        same(host.child),
      );
    });

    test('changing the motion re-applies at once', () {
      final vsync = _Vsync();
      final controller = AnimationController(vsync: vsync, value: 0.0);
      addTearDown(controller.dispose);
      final host = sheet(controller: controller);

      host.box.motion = const Motion3d(offset: Offset3d(0, 0, 50));
      expect(host.box.nodeOffset, const Offset3d(0, 0, 0.5));

      host.box.animation = null;
      expect(host.box.nodeOffset, Offset3d.zero);
    });
  });

  group('the clock a route carries', () {
    ({Layout3dSurface surface, Overlay3d overlay}) panel() {
      final overlay = Overlay3d(
        children: <Layout3d>[TestBox(const Size3d(4, 3, 0), pointable: true)],
      );
      final surface = laidOut(
        overlay,
        constraints: Constraints3d.tight(const Size3d(4, 3, 0)),
      );
      addTearDown(surface.dispose);
      return (surface: surface, overlay: overlay);
    }

    test('a route with no transition rests at arrival', () {
      final host = panel();
      final navigator = Navigator3d(host.overlay);
      final route = PageRoute3d<void>(
        motion: Motion3d.fromBelow,
        builder: (_) => TestBox(const Size3d(2, 1, 0)),
      );
      unawaited(navigator.push(route));
      host.surface.flush();

      expect(route.animation.value, 1.0);
      final moving = findIn<MotionTransition3d>(route.entry!.content!)!;
      expect(moving.nodeOffset, Offset3d.zero);
      expect(moving.nodeTransform, isNull);
    });

    testWidgets('a push winds the clock and a pop unwinds it', (tester) async {
      final host = panel();
      final vsync = _Vsync();
      final navigator = Navigator3d(
        host.overlay,
        vsync: vsync,
        transition: const TimedRoute3dTransition(
          duration: Duration(milliseconds: 200),
          curve: Curves.linear,
        ),
      );
      final content = TestBox(const Size3d(2, 1, 0));
      final route = PageRoute3d<String>(
        motion: Motion3d.fromBelow,
        builder: (_) => content,
      );
      final popped = navigator.push(route);
      host.surface.flush();

      // At rest is 1; a timed forward puts the route at its start in the same
      // turn as the push, before anything has been laid out.
      expect(route.animation.value, 0.0);
      final moving = content.parent! as MotionTransition3d;
      expect(moving.nodeOffset, const Offset3d(0, 1, 0));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.animation.value, closeTo(0.5, 0.05));
      expect(moving.nodeOffset.y, closeTo(0.5, 0.05));
      expect(
        host.surface.needsFlush,
        isFalse,
        reason: 'an arrival lays nothing out',
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(route.animation.value, 1.0);
      expect(moving.nodeOffset, Offset3d.zero);

      // The entry stays in the overlay for the whole of the reverse.
      expect(navigator.pop('answer'), isTrue);
      expect(host.overlay.entries, hasLength(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(moving.nodeOffset.y, closeTo(0.5, 0.05));
      expect(host.overlay.entries, hasLength(1));

      await tester.pump(const Duration(milliseconds: 200));
      expect(host.overlay.entries, isEmpty);
      expect(await popped, 'answer');
      expect(
        vsync.tickers.every((ticker) => !ticker.isActive),
        isTrue,
        reason: 'an animation that has stopped changing stops asking',
      );
    });

    testWidgets('a pop that interrupts an arrival takes what is left of it', (
      tester,
    ) async {
      final host = panel();
      final vsync = _Vsync();
      final navigator = Navigator3d(
        host.overlay,
        vsync: vsync,
        transition: const TimedRoute3dTransition(
          duration: Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      );
      final route = PageRoute3d<void>(
        builder: (_) => TestBox(const Size3d(2, 1, 0)),
      );
      unawaited(navigator.push(route));
      host.surface.flush();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.animation.value, closeTo(0.25, 0.05));

      navigator.pop();
      // A quarter of the way in is a quarter of the way back: 100ms, not 400.
      // The first pump is the one that starts the clock — a ticker's first
      // frame always reports elapsed zero.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(host.overlay.entries, isEmpty);
    });

    test('a zero duration keeps the synchronous path', () {
      final host = panel();
      final navigator = Navigator3d(
        host.overlay,
        transition: const TimedRoute3dTransition(duration: Duration.zero),
      );
      final route = PageRoute3d<int>(
        builder: (_) => TestBox(const Size3d(2, 1, 0)),
      );
      unawaited(navigator.push(route));
      host.surface.flush();
      expect(
        route.animation.value,
        1.0,
        reason: 'nothing to wind: the route is there at once',
      );

      expect(navigator.pop(3), isTrue);
      expect(
        host.overlay.entries,
        isEmpty,
        reason: 'the entry came out in the same turn',
      );
    });

    testWidgets('the barrier does not move with what it covers', (
      tester,
    ) async {
      final host = panel();
      final vsync = _Vsync();
      final navigator = Navigator3d(
        host.overlay,
        vsync: vsync,
        transition: const TimedRoute3dTransition(
          duration: Duration(milliseconds: 200),
          curve: Curves.linear,
        ),
      );
      final content = TestBox(const Size3d(2, 1, 0));
      final route = PageRoute3d<void>(
        modal: true,
        motion: Motion3d.fromBelow,
        builder: (_) => content,
      );
      unawaited(navigator.push(route));
      host.surface.flush();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final barrier = findIn<ModalBarrier3d>(route.entry!.content!);
      expect(barrier, isNotNull);
      expect(
        barrier!.nodeOffset,
        Offset3d.zero,
        reason: 'a scrim does not slide in with what it dims',
      );
      expect(
        (content.parent! as MotionTransition3d).nodeOffset.y,
        closeTo(0.5, 0.05),
      );

      navigator.pop();
      await tester.pumpAndSettle();
      expect(host.overlay.entries, isEmpty);
    });

    testWidgets('a widget route arrives too, one frame later', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0),
          controller: controller,
          child: SceneOverlay3d(
            child: const SceneSizedBox3d(width: 2, height: 1, depth: 0),
          ),
        ),
      );
      final overlay = controller.surface!.child! as Overlay3d;
      final vsync = _Vsync();
      final navigator = Navigator3d(
        overlay,
        vsync: vsync,
        transition: const TimedRoute3dTransition(
          duration: Duration(milliseconds: 200),
          curve: Curves.linear,
        ),
      );
      final route = WidgetPageRoute3d<void>(
        motion: Motion3d.fromBelow,
        builder: (context, self) =>
            const SceneSizedBox3d(width: 2, height: 1, depth: 0),
      );
      unawaited(navigator.push(route));
      await tester.pump();

      final moving = findIn<MotionTransition3d>(route.entry!.content!);
      expect(moving, isNotNull, reason: 'the slot was filled on the rebuild');
      expect(moving!.nodeOffset.y, closeTo(1.0, 0.1));

      await tester.pump(const Duration(milliseconds: 100));
      expect(moving.nodeOffset.y, closeTo(0.5, 0.1));

      navigator.pop();
      await tester.pumpAndSettle();
      expect(overlay.entries, isEmpty);
    });
  });

  group('a route that carries its own clock', () {
    ({Layout3dSurface surface, Overlay3d overlay}) panel() {
      final overlay = Overlay3d(
        children: <Layout3d>[TestBox(const Size3d(4, 3, 0), pointable: true)],
      );
      final surface = laidOut(
        overlay,
        constraints: Constraints3d.tight(const Size3d(4, 3, 0)),
      );
      addTearDown(surface.dispose);
      return (surface: surface, overlay: overlay);
    }

    testWidgets('a route runs its own transition, not the navigator\'s', (
      tester,
    ) async {
      final host = panel();
      final vsync = _Vsync();
      final navigator = Navigator3d(
        host.overlay,
        vsync: vsync,
        transition: const TimedRoute3dTransition(
          duration: Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      );
      final route = PageRoute3d<void>(
        // A quarter of what the navigator would have given it.
        transition: const TimedRoute3dTransition(
          duration: Duration(milliseconds: 100),
          curve: Curves.linear,
        ),
        builder: (_) => TestBox(const Size3d(2, 1, 0)),
      );
      unawaited(navigator.push(route));
      host.surface.flush();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        route.animation.value,
        1.0,
        reason: 'the route\'s own 100ms, not the navigator\'s 400ms',
      );

      navigator.pop();
      await tester.pumpAndSettle();
      expect(host.overlay.entries, isEmpty);
      expect(
        vsync.tickers.every((ticker) => !ticker.isActive),
        isTrue,
        reason: 'an animation that has stopped changing stops asking',
      );
    });

    testWidgets('two routes on one navigator keep their own clocks', (
      tester,
    ) async {
      // The defect this field exists to close: a sheet already open when a
      // dialog is pushed used to leave on whichever transition the navigator
      // last held, because `removeRoute` reads that field at pop time.
      final host = panel();
      final vsync = _Vsync();
      final navigator = Navigator3d(host.overlay, vsync: vsync);

      final sheet = PageRoute3d<void>(
        transition: const TimedRoute3dTransition(
          duration: Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
        builder: (_) => TestBox(const Size3d(2, 1, 0)),
      );
      final dialog = PageRoute3d<void>(
        transition: const TimedRoute3dTransition(
          duration: Duration(milliseconds: 100),
          curve: Curves.linear,
        ),
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );
      unawaited(navigator.push(sheet));
      unawaited(navigator.push(dialog));
      host.surface.flush();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(dialog.animation.value, 1.0);
      expect(sheet.animation.value, closeTo(0.25, 0.05));

      await tester.pump(const Duration(milliseconds: 300));
      expect(sheet.animation.value, 1.0);

      // Now take the sheet out from under the dialog. It leaves on 400ms,
      // which is the point: the last thing pushed was the 100ms dialog.
      expect(navigator.removeRoute(sheet), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        host.overlay.entries,
        hasLength(2),
        reason: 'a quarter of the way out, both entries are still in',
      );
      expect(sheet.animation.value, closeTo(0.75, 0.05));

      await tester.pump(const Duration(milliseconds: 400));
      expect(host.overlay.entries, hasLength(1));

      navigator.pop();
      await tester.pumpAndSettle();
      expect(host.overlay.entries, isEmpty);
    });

    test('a route with none leaves at once on an animating navigator', () {
      final host = panel();
      final navigator = Navigator3d(
        host.overlay,
        transition: const TimedRoute3dTransition(
          duration: Duration(milliseconds: 400),
        ),
      );
      final route = PageRoute3d<int>(
        transition: Route3dTransition.none,
        builder: (_) => TestBox(const Size3d(2, 1, 0)),
      );
      unawaited(navigator.push(route));
      host.surface.flush();
      expect(route.animation.value, 1.0);

      expect(navigator.pop(7), isTrue);
      expect(
        host.overlay.entries,
        isEmpty,
        reason: 'the synchronous removal path survives a per-route none',
      );
    });

    test('a route with no transition of its own gets the navigator\'s', () {
      final host = panel();
      final navigator = Navigator3d(
        host.overlay,
        transition: const TimedRoute3dTransition(duration: Duration.zero),
      );
      final route = PageRoute3d<void>(
        builder: (_) => TestBox(const Size3d(2, 1, 0)),
      );
      expect(route.transition, isNull);
      unawaited(navigator.push(route));
      host.surface.flush();
      expect(navigator.pop(), isTrue);
      expect(host.overlay.entries, isEmpty);
    });
  });
}
