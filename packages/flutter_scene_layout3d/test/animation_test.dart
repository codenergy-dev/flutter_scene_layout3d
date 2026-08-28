// Animation: the tweens, the implicit layer that pays for a relayout, the
// node-only layer that does not, and the scroll half — animateTo,
// ensureVisible, and a release that flings.

import 'dart:async' show unawaited;

import 'package:flutter/animation.dart' show AnimationController, Curves, Tween;
import 'package:flutter/widgets.dart'
    show Directionality, TextDirection, TextStyle, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const TextStyle style = TextStyle(fontSize: 10);

Layout3d rootOf(Layout3dController controller) => controller.surface!.child!;

/// The box under a `SceneCenter3d` at the root, which is how a widget test
/// gives an animated box room to be a size of its own: the surface hands its
/// root child tight constraints.
Layout3d centredOf(Layout3dController controller) =>
    (rootOf(controller) as Align3d).child!;

/// A viewport over five stacked boxes: content 10 long, window 4, so six
/// units of scroll.
({Layout3dSurface surface, Viewport3d viewport, List<TestBox> items}) column({
  Scroll3dController? controller,
}) {
  final items = List.generate(5, (_) => TestBox(const Size3d(2, 2, 2)));
  final viewport = Viewport3d(
    controller: controller,
    child: Column3d(mainAxisSize: MainAxisSize3d.min, children: items),
  );
  final surface = laidOut(
    viewport,
    constraints: Constraints3d.tight(const Size3d(10, 4, 10)),
  );
  return (surface: surface, viewport: viewport, items: items);
}

void main() {
  group('tweens', () {
    test('endpoints and midpoint agree with the value type\'s own lerp', () {
      void check<T extends Object>(Tween<T> tween, T Function(double) lerp) {
        for (final t in const <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
          expect(tween.transform(t), lerp(t), reason: '$tween at $t');
        }
      }

      check(
        Size3dTween(begin: Size3d.zero, end: const Size3d(2, 4, 6)),
        (t) => Size3d.lerp(Size3d.zero, const Size3d(2, 4, 6), t),
      );
      check(
        Offset3dTween(begin: Offset3d.zero, end: const Offset3d(1, -2, 3)),
        (t) => Offset3d.lerp(Offset3d.zero, const Offset3d(1, -2, 3), t),
      );
      check(
        EdgeInsets3dTween(
          begin: EdgeInsets3d.zero,
          end: const EdgeInsets3d.all(2),
        ),
        (t) =>
            EdgeInsets3d.lerp(EdgeInsets3d.zero, const EdgeInsets3d.all(2), t),
      );
      check(
        Alignment3dTween(
          begin: Alignment3d.topLeft,
          end: Alignment3d.bottomRight,
        ),
        (t) =>
            Alignment3d.lerp(Alignment3d.topLeft, Alignment3d.bottomRight, t),
      );
      check(
        Constraints3dTween(
          begin: Constraints3d.loose(const Size3d(4, 4, 4)),
          end: Constraints3d.tight(const Size3d(1, 2, 3)),
        ),
        (t) => Constraints3d.lerp(
          Constraints3d.loose(const Size3d(4, 4, 4)),
          Constraints3d.tight(const Size3d(1, 2, 3)),
          t,
        ),
      );
    });
  });

  group('the node-only path', () {
    testWidgets('moves the geometry and marks nothing dirty', (tester) async {
      final content = TestBox(const Size3d(2, 2, 2));
      final ticker = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 100),
      );
      final lift = Offset3dTween(
        begin: Offset3d.zero,
        end: const Offset3d(0, 0, -1),
      ).animate(ticker);
      final slide = NodeTransform3d(offsetAnimation: lift, child: content);
      final surface = laidOut(
        slide,
        constraints: Constraints3d.tight(const Size3d(4, 4, 4)),
      );
      final laidOutOnce = content.layoutCount;
      final where = content.offset;

      ticker.forward();
      // The load-bearing assertion: across the whole run, not one box is ever
      // waiting to be laid out again.
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 10));
        expect(surface.needsFlush, isFalse, reason: 'frame $frame');
      }

      expect(content.layoutCount, laidOutOnce);
      expect(content.offset, where);
      expect(slide.nodeOffset.z, closeTo(-1.0, 1e-9));
      expect(translationOf(slide).z, closeTo(-1.0, 1e-9));
      ticker.dispose();
    });

    testWidgets('the layout frame is what a ray still finds', (tester) async {
      final content = TestBox(const Size3d(2, 2, 2), pointable: true);
      final slide = NodeTransform3d(child: content);
      final surface = laidOut(
        Center3d(child: slide),
        constraints: Constraints3d.tight(const Size3d(4, 4, 4)),
      );
      final before = surface.hitTestAt(const Offset3d(2, 2, 0));
      expect(before.path.map((entry) => entry.layout), contains(content));

      // A metre toward the viewer, and the box is still aimed at where the
      // layout put it: `worldTransform` undoes the node-only nudge.
      slide.nodeOffset = const Offset3d(0, 0, -1);
      expect(surface.needsFlush, isFalse);
      final after = surface.hitTestAt(const Offset3d(2, 2, 0));
      expect(after.path.map((entry) => entry.layout), contains(content));
    });

    testWidgets('SceneAnimatedSlide3d rebuilds nothing while it runs', (
      tester,
    ) async {
      final parent = Node();
      final controller = Layout3dController();

      Widget frame(Offset3d offset) => SceneLayout3d(
        parent: parent,
        size: const Size3d(10, 10, 10),
        controller: controller,
        child: SceneAnimatedSlide3d(
          duration: const Duration(milliseconds: 100),
          offset: offset,
          child: const SceneSizedBox3d.cube(2),
        ),
      );

      await tester.pumpWidget(frame(Offset3d.zero));
      final slide = rootOf(controller) as NodeTransform3d;
      final box = slide.child!;

      await tester.pumpWidget(frame(const Offset3d(0, 0, -1)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(slide.nodeOffset.z, lessThan(0.0));
      expect(slide.nodeOffset.z, greaterThan(-1.0));
      // The box under it has not moved, and is not waiting to.
      expect(box.offset, Offset3d.zero);
      expect(controller.surface!.needsFlush, isFalse);

      await tester.pumpAndSettle();
      expect(slide.nodeOffset.z, closeTo(-1.0, 1e-9));
    });
  });

  group('implicit animation', () {
    testWidgets('reaches its target and rests there', (tester) async {
      final parent = Node();
      final controller = Layout3dController();
      var ended = 0;

      Widget frame(double width) => SceneLayout3d(
        parent: parent,
        size: const Size3d(10, 10, 10),
        controller: controller,
        child: SceneCenter3d(
          child: SceneAnimatedContainer3d(
            duration: const Duration(milliseconds: 100),
            curve: Curves.linear,
            onEnd: () => ended++,
            width: width,
            height: 1,
          ),
        ),
      );

      await tester.pumpWidget(frame(1));
      expect(centredOf(controller).size.width, 1);

      await tester.pumpWidget(frame(3));
      await tester.pump(const Duration(milliseconds: 50));
      final midway = centredOf(controller).size.width;
      expect(midway, greaterThan(1.0));
      expect(midway, lessThan(3.0));

      await tester.pumpAndSettle();
      expect(centredOf(controller).size.width, 3);
      expect(ended, 1);
      // Rested: nothing is dirty and nothing has asked for another frame.
      expect(controller.surface!.needsFlush, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a retarget carries on from where it had got to', (
      tester,
    ) async {
      final parent = Node();
      final controller = Layout3dController();

      Widget frame(double width) => SceneLayout3d(
        parent: parent,
        size: const Size3d(10, 10, 10),
        controller: controller,
        child: SceneCenter3d(
          child: SceneAnimatedContainer3d(
            duration: const Duration(milliseconds: 100),
            curve: Curves.linear,
            width: width,
            height: 1,
          ),
        ),
      );

      await tester.pumpWidget(frame(1));
      await tester.pumpWidget(frame(3));
      await tester.pump(const Duration(milliseconds: 50));
      final midway = centredOf(controller).size.width;

      await tester.pumpWidget(frame(0.5));
      await tester.pump();
      // No snap back to where the first animation started.
      expect(centredOf(controller).size.width, closeTo(midway, 1e-6));
      await tester.pumpAndSettle();
      expect(centredOf(controller).size.width, closeTo(0.5, 1e-9));
    });

    testWidgets('animating a box around a label never consults the font', (
      tester,
    ) async {
      final parent = Node();
      final controller = Layout3dController();

      Widget frame(double width) => Directionality(
        textDirection: TextDirection.ltr,
        child: SceneLayout3d(
          parent: parent,
          size: const Size3d(10, 10, 10),
          controller: controller,
          child: SceneCenter3d(
            child: SceneAnimatedContainer3d(
              duration: const Duration(milliseconds: 100),
              curve: Curves.linear,
              width: width,
              child: const SceneText3d('hello world', style: style),
            ),
          ),
        ),
      );

      await tester.pumpWidget(frame(2));
      await tester.pumpWidget(frame(0.8));
      // Everything the font can tell us has been asked by now; the run below
      // refits the same prepared text at fifty widths and must ask nothing
      // more. This is the assertion the text plan was built to make possible,
      // and the one that fails first if measurement ever gets back onto the
      // layout path.
      final before = debugTextParagraphCount;
      await tester.pumpAndSettle();
      expect(debugTextParagraphCount, before);
    });
  });

  group('animateTo', () {
    testWidgets('clamps to the range and completes', (tester) async {
      final scroll = Scroll3dController(vsync: const TestVSync());
      final view = column(controller: scroll);
      expect(scroll.maxScrollExtent, 6);

      var done = false;
      unawaited(
        scroll
            .animateTo(100, duration: const Duration(milliseconds: 100))
            .then((_) => done = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(scroll.offset, greaterThan(0.0));
      expect(scroll.offset, lessThan(6.0));

      await tester.pump(const Duration(milliseconds: 60));
      await tester.idle();
      expect(scroll.offset, 6);
      expect(scroll.isAnimating, isFalse);
      expect(done, isTrue);

      view.surface.flush();
      expect(view.viewport.child!.offset.y, -6);
      scroll.dispose();
    });

    testWidgets('a second call interrupts the first cleanly', (tester) async {
      final scroll = Scroll3dController(vsync: const TestVSync());
      column(controller: scroll);

      var firstDone = false;
      unawaited(
        scroll
            .animateTo(6, duration: const Duration(milliseconds: 100))
            .then((_) => firstDone = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final midway = scroll.offset;

      var secondDone = false;
      unawaited(
        scroll
            .animateTo(0, duration: const Duration(milliseconds: 100))
            .then((_) => secondDone = true),
      );
      await tester.idle();
      // The interrupted call answers rather than hanging, and the new one
      // starts from where the old one had got to.
      expect(firstDone, isTrue);
      expect(scroll.offset, midway);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.idle();
      expect(scroll.offset, 0);
      expect(secondDone, isTrue);
      scroll.dispose();
    });

    test('a zero duration is a jump', () {
      final scroll = Scroll3dController();
      column(controller: scroll);
      scroll.animateTo(3, duration: Duration.zero);
      expect(scroll.offset, 3);
      expect(scroll.isAnimating, isFalse);
      scroll.dispose();
    });
  });

  group('ensureVisible', () {
    test('brings a target below the window into it', () {
      final view = column();
      expect(offsetToReveal3d(view.viewport, view.items[4]), 6);
      ensureVisible3d(view.items[4]);
      expect(view.viewport.controller.offset, 6);
    });

    test('brings a target above the window back into it', () {
      final view = column();
      view.viewport.controller.jumpTo(6);
      view.surface.flush();
      ensureVisible3d(view.items.first);
      expect(view.viewport.controller.offset, 0);
    });

    test('leaves a target that is already visible alone', () {
      final view = column();
      view.viewport.controller.jumpTo(2);
      view.surface.flush();
      // Items 1 and 2 span 2..6, exactly the window.
      ensureVisible3d(view.items[1]);
      expect(view.viewport.controller.offset, 2);
    });

    test('an alignment says where in the window it lands', () {
      final view = column();
      // Item 2 sits at 4..6 in the content.
      expect(offsetToReveal3d(view.viewport, view.items[2], alignment: 0.0), 4);
      expect(offsetToReveal3d(view.viewport, view.items[2], alignment: 1.0), 2);
      expect(offsetToReveal3d(view.viewport, view.items[2], alignment: 0.5), 3);
    });

    test('a box outside any scrolling view is left alone', () {
      final loose = TestBox(const Size3d(1, 1, 1));
      laidOut(loose);
      expect(Scrollable3d.of(loose), isNull);
      expect(ensureVisible3d(loose), completes);
    });
  });

  group('physics', () {
    testWidgets('a fling decelerates to rest and stays clamped', (
      tester,
    ) async {
      final scroll = Scroll3dController(vsync: const TestVSync());
      column(controller: scroll);

      unawaited(scroll.fling(4.0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final early = scroll.offset;
      expect(early, greaterThan(0.0));

      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(scroll.isAnimating, isFalse);
      expect(scroll.offset, greaterThan(early));
      expect(scroll.offset, lessThanOrEqualTo(6.0));
      scroll.dispose();
    });

    testWidgets('a clamping fling stops at the end rather than through it', (
      tester,
    ) async {
      final scroll = Scroll3dController(vsync: const TestVSync());
      column(controller: scroll);

      unawaited(scroll.fling(60.0));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(scroll.offset, 6);
      expect(scroll.isAnimating, isFalse);
      scroll.dispose();
    });

    testWidgets('a bouncing physics comes back from beyond the end', (
      tester,
    ) async {
      final scroll = Scroll3dController(
        physics: BouncingScroll3dPhysics(),
        vsync: const TestVSync(),
      );
      final view = column(controller: scroll);

      // Past the end, which the default physics would not have allowed.
      scroll.jumpTo(7);
      expect(scroll.offset, 7);
      expect(scroll.overscroll, 1);

      // A release at rest is still a release: the spring is what brings it
      // back.
      scroll.endUserScroll();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(scroll.offset, closeTo(6, 1e-3));
      expect(scroll.isAnimating, isFalse);

      view.surface.flush();
      expect(scroll.outOfRange, isFalse);
      scroll.dispose();
    });

    test('a bouncing drag past the end moves less than the finger', () {
      final scroll = Scroll3dController(physics: BouncingScroll3dPhysics());
      column(controller: scroll);
      scroll.beginUserScroll();
      scroll.applyUserOffset(6);
      expect(scroll.offset, 6);
      // The first step past the edge is undamped, as it is in Flutter: the
      // position was still in range when it was asked for.
      scroll.applyUserOffset(1);
      expect(scroll.offset, 7);
      // From here the friction bites, and a unit of finger is less than a
      // unit of content.
      scroll.applyUserOffset(1);
      expect(scroll.offset, greaterThan(7.0));
      expect(scroll.offset, lessThan(8.0));
      scroll.dispose();
    });

    test('a clamping drag past the end moves nothing', () {
      final scroll = Scroll3dController();
      column(controller: scroll);
      scroll.beginUserScroll();
      scroll.applyUserOffset(10);
      expect(scroll.offset, 6);
      scroll.applyUserOffset(1);
      expect(scroll.offset, 6);
      scroll.dispose();
    });

    test('a shorter content snaps a clamping position back into range', () {
      final scroll = Scroll3dController();
      final view = column(controller: scroll);
      scroll.jumpTo(6);
      view.viewport.child = TestBox(const Size3d(2, 6, 2));
      view.surface.flush();
      expect(scroll.offset, 2);
    });
  });

  group('userScrollDirection', () {
    test('follows a drag, and is idle between gestures', () {
      final scroll = Scroll3dController();
      column(controller: scroll);
      expect(scroll.userScrollDirection, ScrollDirection3d.idle);

      scroll.beginUserScroll();
      scroll.applyUserOffset(2);
      expect(scroll.userScrollDirection, ScrollDirection3d.reverse);
      scroll.applyUserOffset(-1);
      expect(scroll.userScrollDirection, ScrollDirection3d.forward);

      scroll.endUserScroll();
      expect(scroll.userScrollDirection, ScrollDirection3d.idle);
      scroll.dispose();
    });

    test('a programmatic jump is nobody scrolling', () {
      final scroll = Scroll3dController();
      column(controller: scroll);
      scroll.jumpTo(3);
      expect(scroll.userScrollDirection, ScrollDirection3d.idle);
      scroll.dispose();
    });
  });

  group('a release that flings', () {
    testWidgets('a drag with real timestamps throws the list', (tester) async {
      final view = column();
      final pointer = Layout3dPointer(view.surface);
      var time = Duration.zero;
      Duration next() => time += const Duration(milliseconds: 16);

      pointer.down(
        rayAt(view.surface, const Offset3d(5, 3.5, 0)),
        timeStamp: time,
      );
      for (var step = 1; step <= 5; step++) {
        pointer.move(
          rayAt(view.surface, Offset3d(5, 3.5 - step * 0.3, 0)),
          timeStamp: next(),
        );
      }
      final released = view.viewport.controller.offset;
      pointer.up(timeStamp: next());

      expect(view.viewport.controller.isAnimating, isTrue);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(view.viewport.controller.offset, greaterThan(released));
      expect(view.viewport.controller.isAnimating, isFalse);
    });

    testWidgets('a drag inside a single millisecond does not', (tester) async {
      final view = column();
      final pointer = Layout3dPointer(view.surface);
      pointer.down(
        rayAt(view.surface, const Offset3d(5, 3.5, 0)),
        timeStamp: Duration.zero,
      );
      for (var step = 1; step <= 5; step++) {
        pointer.move(
          rayAt(view.surface, Offset3d(5, 3.5 - step * 0.3, 0)),
          timeStamp: Duration(microseconds: step * 50),
        );
      }
      pointer.up(timeStamp: const Duration(microseconds: 300));
      expect(view.viewport.controller.isAnimating, isFalse);
    });
  });
}
