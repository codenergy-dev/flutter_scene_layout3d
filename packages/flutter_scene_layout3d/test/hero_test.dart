// A hero that flies between two routes: the match, the geometry it flies on,
// the ends it stands in for, and the endings that have to take it down again.

import 'dart:async' show unawaited;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/scheduler.dart'
    show Ticker, TickerCallback, TickerProvider;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dController,
        SceneHero3d,
        SceneLayout3d,
        SceneOverlay3d,
        SceneSizedBox3d,
        WidgetPageRoute3d;
import 'package:flutter_test/flutter_test.dart';

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

/// The first box of type [T] at or below [root].
T? findIn<T extends Layout3d>(Layout3d root) {
  if (root is T) return root;
  T? found;
  root.visitChildren((child) => found ??= findIn<T>(child));
  return found;
}

/// Every flight currently up in [overlay].
List<Hero3dFlightBox> flightsIn(Overlay3d overlay) => <Hero3dFlightBox>[
  for (final entry in overlay.entries)
    if (entry.content case final content?)
      if (findIn<Hero3dFlightBox>(content) case final flight?) flight,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A page with one hero on it, under an overlay on a laid-out surface.
  ({Layout3dSurface surface, Overlay3d overlay, Hero3d hero}) page({
    Size3d size = const Size3d(1, 1, 0),
    Hero3dFit fit = Hero3dFit.stretch,
    Object tag = 'photo',
  }) {
    final hero = Hero3d(
      tag: tag,
      fit: fit,
      flightBuilder: (_) => TestBox(size),
      child: TestBox(size),
    );
    final overlay = Overlay3d(children: <Layout3d>[hero]);
    final surface = laidOut(
      overlay,
      constraints: Constraints3d.tight(const Size3d(4, 3, 0)),
    );
    addTearDown(surface.dispose);
    return (surface: surface, overlay: overlay, hero: hero);
  }

  Navigator3d timed(Overlay3d overlay, _Vsync vsync, {int ms = 200}) =>
      Navigator3d(
        overlay,
        vsync: vsync,
        transition: TimedRoute3dTransition(
          duration: Duration(milliseconds: ms),
          curve: Curves.linear,
        ),
      );

  /// A route carrying one hero of [size] under [tag].
  ///
  /// The hero is read through a closure because the route's builder has not
  /// run when this returns: a route builds its content when it is pushed.
  ({PageRoute3d<void> route, Hero3d Function() hero}) heroRoute({
    Size3d size = const Size3d(2, 1, 0),
    Object tag = 'photo',
  }) {
    Hero3d? built;
    final route = PageRoute3d<void>(
      builder: (_) => built = Hero3d(
        tag: tag,
        flightBuilder: (_) => TestBox(size),
        child: TestBox(size),
      ),
    );
    return (route: route, hero: () => built!);
  }

  group('a flight needs two ends and a clock', () {
    testWidgets('matching tags put a flight up and hide both ends', (
      tester,
    ) async {
      final host = page();
      final navigator = timed(host.overlay, _Vsync());
      final pushed = heroRoute();
      unawaited(navigator.push(pushed.route));
      host.surface.flush();

      expect(host.overlay.entries, hasLength(2));
      final flights = flightsIn(host.overlay);
      expect(flights, hasLength(1));
      expect(flights.single.hasPlaced, isTrue);
      expect(host.hero.isFlying, isTrue);
      expect(host.hero.node.visible, isFalse);
      expect(pushed.hero().isFlying, isTrue);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(flightsIn(host.overlay), isEmpty);
      expect(host.hero.isFlying, isFalse);
      expect(host.hero.node.visible, isTrue);
      expect(pushed.hero().isFlying, isFalse);
    });

    testWidgets('a tag with no partner does not fly, and says nothing', (
      tester,
    ) async {
      final host = page(tag: 'photo');
      final navigator = timed(host.overlay, _Vsync());
      unawaited(navigator.push(heroRoute(tag: 'something else').route));
      host.surface.flush();

      expect(flightsIn(host.overlay), isEmpty);
      expect(host.hero.isFlying, isFalse);

      // The route still arrives, so its clock still has to be let finish —
      // a test that leaves one running leaks it into the next one.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    test('a route with no transition has no clock, so nothing flies', () {
      final host = page();
      // The default transition, which is `none`.
      final navigator = Navigator3d(host.overlay);
      unawaited(navigator.push(heroRoute().route));
      host.surface.flush();

      expect(flightsIn(host.overlay), isEmpty);
      expect(host.hero.isFlying, isFalse);
    });
  });

  group('the geometry a flight flies on', () {
    testWidgets('it is laid out at the end it starts from and scales toward '
        'the other, per axis', (tester) async {
      final host = page(size: const Size3d(1, 1, 0));
      final navigator = timed(host.overlay, _Vsync());
      unawaited(navigator.push(heroRoute(size: const Size3d(3, 2, 0)).route));
      host.surface.flush();

      final flight = flightsIn(host.overlay).single;
      // The covered side builds it on a push, so the flight is exact there
      // and carries no extra multiply at all.
      expect(flight.size, const Size3d(1, 1, 0));
      expect(flight.nodeTransform, isNull);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Halfway, each axis is halfway on its own: 1 to 3 and 1 to 2.
      final scale = flight.nodeTransform!;
      expect(scale.entry(0, 0), closeTo(2.0, 0.05));
      expect(scale.entry(1, 1), closeTo(1.5, 0.05));

      // And the flight is taken down when the arrival settles, which is the
      // only frame that can read it.
      await tester.pump(const Duration(milliseconds: 200));
      expect(flightsIn(host.overlay), isEmpty);
    });

    testWidgets('a uniform fit takes one factor for all three axes', (
      tester,
    ) async {
      final host = page(size: const Size3d(1, 1, 0), fit: Hero3dFit.uniform);
      final navigator = timed(host.overlay, _Vsync());
      unawaited(navigator.push(heroRoute(size: const Size3d(3, 2, 0)).route));
      host.surface.flush();

      final flight = flightsIn(host.overlay).single;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // `contain`: the smaller of the two plane factors — 1.5 rather than the
      // 2 the width alone would ask for — so the flight fits inside the far
      // end rather than overhanging it, and nothing is distorted.
      final scale = flight.nodeTransform!;
      expect(scale.entry(0, 0), closeTo(1.5, 0.05));
      expect(scale.entry(1, 1), closeTo(1.5, 0.05));
      expect(scale.entry(2, 2), closeTo(1.5, 0.05));

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('it moves between the two ends and leaves the depth axis '
        'alone', (tester) async {
      final host = page();
      final navigator = timed(host.overlay, _Vsync());
      unawaited(navigator.push(heroRoute().route).then((_) {}));
      host.surface.flush();

      final flight = flightsIn(host.overlay).single;
      final start = flight.nodeOffset;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final middle = flight.nodeOffset;
      expect(
        middle,
        isNot(start),
        reason: 'a flight halfway between two places is at neither',
      );
      expect(
        middle.z,
        start.z,
        reason: 'depth belongs to the layer lift, not to the flight',
      );
      expect(
        host.surface.needsFlush,
        isFalse,
        reason: 'a flight lays nothing out',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('a route whose content arrives a frame late', () {
    testWidgets('a widget-built route still flies, on the second attempt', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0),
          controller: controller,
          child: SceneOverlay3d(
            child: SceneHero3d(
              tag: 'photo',
              flightBuilder: (_) => TestBox(const Size3d(1, 1, 0)),
              child: const SceneSizedBox3d(width: 1, height: 1, depth: 0),
            ),
          ),
        ),
      );
      final overlay = controller.surface!.child! as Overlay3d;
      final navigator = timed(overlay, _Vsync());
      unawaited(
        navigator.push(
          WidgetPageRoute3d<void>(
            builder: (context, self) => SceneHero3d(
              tag: 'photo',
              flightBuilder: (_) => TestBox(const Size3d(2, 2, 0)),
              child: const SceneSizedBox3d(width: 2, height: 2, depth: 0),
            ),
          ),
        ),
      );

      // Nothing on the turn that pushed it: the route's subtree reaches the
      // element tree on the rebuild the insertion asked for.
      expect(flightsIn(overlay), isEmpty);

      await tester.pump();
      expect(
        flightsIn(overlay),
        hasLength(1),
        reason: 'the second attempt runs once the slot has been filled',
      );
      // Up, but not yet placed: the flight is itself an entry, and an entry
      // has no size until the frame after the one that inserted it.
      await tester.pump();
      expect(flightsIn(overlay).single.hasPlaced, isTrue);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(overlay.entries, isEmpty);
    });
  });

  group('the endings', () {
    testWidgets('a pop flies the other way and builds from the leaving side', (
      tester,
    ) async {
      final host = page();
      final navigator = timed(host.overlay, _Vsync());
      final pushed = heroRoute(size: const Size3d(2, 1, 0));
      unawaited(navigator.push(pushed.route));
      host.surface.flush();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(flightsIn(host.overlay), isEmpty);

      expect(navigator.pop(), isTrue);
      host.surface.flush();
      final flight = flightsIn(host.overlay).single;
      // The side that is leaving is the one the viewer was just looking at,
      // so it is the one that builds the flight and sets its size.
      expect(flight.size, const Size3d(2, 1, 0));
      expect(host.hero.isFlying, isTrue);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.overlay.entries, isEmpty);
      expect(host.hero.isFlying, isFalse);
    });

    testWidgets('a pop that interrupts an arrival takes its flights down', (
      tester,
    ) async {
      final host = page();
      final navigator = timed(host.overlay, _Vsync(), ms: 400);
      final pushed = heroRoute();
      unawaited(navigator.push(pushed.route));
      host.surface.flush();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(flightsIn(host.overlay), hasLength(1));

      // The push's flight is never told its own future completed — an
      // interrupted ticker's future does not complete at all — so the pop is
      // what has to take it down.
      expect(navigator.pop(), isTrue);
      host.surface.flush();
      expect(
        flightsIn(host.overlay),
        hasLength(1),
        reason: 'the pop puts up its own flight in place of the push\'s',
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(host.overlay.entries, isEmpty);
      expect(host.hero.isFlying, isFalse);
    });

    testWidgets('every ending un-hides both ends', (tester) async {
      final host = page();
      final navigator = timed(host.overlay, _Vsync());
      final pushed = heroRoute();
      unawaited(navigator.push(pushed.route));
      host.surface.flush();
      expect(host.hero.isFlying, isTrue);

      // Taking the flight's entry out directly — which is what a navigator
      // going away does — is the same disposal path as settling.
      host.overlay.entries.last.remove();
      expect(host.hero.isFlying, isFalse);
      expect(host.hero.node.visible, isTrue);
      expect(pushed.hero().isFlying, isFalse);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('a hero on its own', () {
    test('it hides on the flag the culling views write, and keeps it', () {
      final hero = Hero3d(
        tag: 'x',
        flightBuilder: (_) => TestBox(const Size3d(1, 1, 0)),
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(hero);
      addTearDown(surface.dispose);

      expect(hero.isFlying, isFalse);
      expect(hero.node.visible, isTrue);
    });

    testWidgets('two heroes with one tag on one route is a mistake', (
      tester,
    ) async {
      final host = page();
      final navigator = timed(host.overlay, _Vsync());
      Layout3d twice() => Column3d(
        children: <Layout3d>[
          Hero3d(
            tag: 'photo',
            flightBuilder: (_) => TestBox(const Size3d(1, 1, 0)),
            child: TestBox(const Size3d(1, 1, 0)),
          ),
          Hero3d(
            tag: 'photo',
            flightBuilder: (_) => TestBox(const Size3d(1, 1, 0)),
            child: TestBox(const Size3d(1, 1, 0)),
          ),
        ],
      );

      expect(
        () => navigator.push(PageRoute3d<void>(builder: (_) => twice())),
        throwsA(isA<AssertionError>()),
      );

      // The push got as far as winding the clock before it threw.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
