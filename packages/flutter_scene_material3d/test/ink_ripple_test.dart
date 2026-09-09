// The press ripple: the arithmetic, the frame the origin arrives in, the
// timeline under a ticker, and the claim the whole phase rests on — a ripple
// is the first thing in this catalogue that writes a uniform every frame, and
// it must not leave the repaint-only tier while doing it.
//
// The last group is the important one. `test/ink_well_test.dart` counts builds
// and layouts across *one* state change; this counts them across a whole run
// of an animation, which is the shape `test/animation_test.dart` in the layout
// package uses for text.

import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/widgets.dart'
    show Builder, BuildContext, FocusManager, SizedBox;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show DecoratedBox3d, Offset3d, Ripple3d, Size3d;
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A control that does not fill its surface, so the panel's own frame is not
/// the surface's and a press has a change of frame to survive.
///
/// The surface is 4 by 4; the control is centred, padded, and its content is a
/// 1-unit square, so the panel is a square of `1 + 2 * dp(padding)` centred at
/// (2, 2). The `Builder` counts the rebuilds of everything under it.
class Inset {
  Inset(this.controller, this.child, this.builds);

  final Layout3dController controller;
  final TestBox child;
  final List<int> builds;

  Layout3dSurface get surface => controller.surface!;
  DecoratedBox3d get panel => decoratedBoxIn(surface);
  Ripple3d? get ripple => panel.stateLayer.ripple;

  /// One pointer for the whole control, not one per access: a
  /// `Layout3dPointer` carries the live sequences, so an `up()` sent through a
  /// second instance lands nowhere and the press never ends.
  late final Layout3dPointer pointer = Layout3dPointer(surface);

  /// The panel's centre in its own frame, which is what a press aimed at the
  /// surface's centre has to come out as.
  Offset3d get panelCentre =>
      Offset3d(panel.size.width / 2.0, panel.size.height / 2.0, 0.0);
}

Future<Inset> pumpInset(WidgetTester tester) async {
  final controller = Layout3dController();
  late TestBox child;
  final builds = <int>[0];

  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      size: const Size3d(4, 4, 0.5),
      controller: controller,
      child: SceneTheme3d(
        data: Theme3dData.light,
        child: SceneCenter3d(
          child: Material3d(
            alignment: null,
            padding: const EdgeInsets3d.symmetric(horizontal: 40, vertical: 40),
            child: Builder(
              builder: (BuildContext context) {
                builds[0]++;
                return InkWell3d(
                  focusOnPointerDown: false,
                  onTap: () {},
                  child: SceneTestBox(const Size3d(1, 1, 0), (b) => child = b),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  return Inset(controller, child, builds);
}

/// Presses at [point] on the surface and pumps past the arena's deadline, so
/// that the press is reported and the ripple has started.
Future<void> pressAt(WidgetTester tester, Inset it, Offset3d point) async {
  it.pointer.down(rayAt(it.surface, point));
  await tester.pump(kPressTimeout);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  });

  const theme = Theme3dData.light;
  const style = InkRipple3dStyle.material;

  group('the run, as arithmetic', () {
    InkRipple3dRun run() => InkRipple3dRun(
      origin: const Offset3d(1, 1, 0),
      targetRadius: 2.0,
      opacity: 0.1,
    );

    test('it starts at nothing and ends covering the control', () {
      final it = run();
      expect(it.radiusAt(Duration.zero), 0.0);
      expect(it.opacityAt(Duration.zero), 0.0);
      expect(it.radiusAt(style.expand), closeTo(2.0, 1e-12));
      expect(it.radiusAt(style.expand * 4), closeTo(2.0, 1e-12));
      expect(it.opacityAt(style.fadeIn), closeTo(0.1, 1e-12));
    });

    test('the radius only ever grows', () {
      final it = run();
      var last = -1.0;
      for (var ms = 0; ms <= 400; ms += 5) {
        final r = it.radiusAt(Duration(milliseconds: ms));
        expect(r, greaterThanOrEqualTo(last));
        last = r;
      }
      expect(last, closeTo(2.0, 1e-12));
    });

    test('a held press settles, and a released one never does again', () {
      final it = run();
      expect(it.isSettledAt(const Duration(milliseconds: 100)), isFalse);
      expect(it.isSettledAt(style.expand), isTrue);
      expect(it.isDoneAt(style.expand * 10), isFalse);

      it.release(style.expand);
      expect(it.isSettledAt(style.expand), isFalse);
      expect(it.isDoneAt(style.expand), isFalse);
      expect(it.isDoneAt(style.expand + style.fadeOut), isTrue);
    });

    test('releasing twice keeps the first release', () {
      // A cancel arriving after an up is a real sequence the arena produces,
      // and a fade that restarted on it would flicker.
      final it = run();
      it.release(const Duration(milliseconds: 100));
      it.release(const Duration(milliseconds: 300));
      expect(it.releasedAt, const Duration(milliseconds: 100));
    });

    test('the fade takes the opacity down while the radius carries on', () {
      final it = run();
      it.release(const Duration(milliseconds: 50));
      final atRelease = it.opacityAt(const Duration(milliseconds: 50));
      final later = const Duration(milliseconds: 200);
      expect(it.opacityAt(later), lessThan(atRelease));
      expect(
        it.radiusAt(later),
        greaterThan(it.radiusAt(const Duration(milliseconds: 50))),
        reason: 'a ripple snatched away mid-growth reads as a glitch',
      );
      expect(it.opacityAt(const Duration(milliseconds: 50) + style.fadeOut), 0);
    });

    test('covering measures from where the press landed', () {
      final middle = InkRipple3dRun.covering(
        size: const Size3d(6, 8, 0),
        origin: const Offset3d(3, 4, 0),
        opacity: 0.1,
      );
      final corner = InkRipple3dRun.covering(
        size: const Size3d(6, 8, 0),
        origin: Offset3d.zero,
        opacity: 0.1,
      );
      expect(middle.targetRadius, closeTo(5.0, 1e-12));
      expect(corner.targetRadius, closeTo(10.0, 1e-12));
    });

    test('a zero-length style is instantaneous rather than infinite', () {
      final it = InkRipple3dRun(
        origin: Offset3d.zero,
        targetRadius: 1.0,
        opacity: 0.1,
        style: const InkRipple3dStyle(
          fadeIn: Duration.zero,
          expand: Duration.zero,
          fadeOut: Duration.zero,
        ),
      );
      expect(it.radiusAt(Duration.zero), 1.0);
      expect(it.opacityAt(Duration.zero), 0.1);
      it.release(Duration.zero);
      expect(it.isDoneAt(Duration.zero), isTrue);
    });
  });

  group('the origin arrives in the panel\'s frame', () {
    testWidgets('a press at the middle ripples from the middle', (
      tester,
    ) async {
      // The press lands on the ink well's gesture detector, which sits inside
      // the panel's padding; the wash belongs to the panel. Those are not the
      // same box, and this is the assertion that says the change of frame
      // happened.
      final it = await pumpInset(tester);
      await pressAt(tester, it, const Offset3d(2, 2, 0));
      await tester.pump(const Duration(milliseconds: 30));

      final origin = it.ripple!.origin;
      expect(origin.x, closeTo(it.panelCentre.x, 1e-6));
      expect(origin.y, closeTo(it.panelCentre.y, 1e-6));
      expect(
        it.panel.size.width,
        greaterThan(1.0),
        reason: 'the padding really did make the panel bigger than the child',
      );
    });

    testWidgets('and an off-centre press ripples off centre, by as much', (
      tester,
    ) async {
      final it = await pumpInset(tester);
      await pressAt(tester, it, const Offset3d(2.3, 1.8, 0));
      await tester.pump(const Duration(milliseconds: 30));

      final origin = it.ripple!.origin;
      expect(origin.x, closeTo(it.panelCentre.x + 0.3, 1e-6));
      expect(origin.y, closeTo(it.panelCentre.y - 0.2, 1e-6));
    });

    testWidgets('a corner press has further to travel than a middle one', (
      tester,
    ) async {
      // Material's ripple ends having covered the control, so where it starts
      // decides how big it gets.
      final it = await pumpInset(tester);
      await pressAt(tester, it, const Offset3d(2, 2, 0));
      await tester.pump(style.expand * 2);
      final fromMiddle = it.ripple!.radius;

      it.pointer.up();
      await tester.pumpAndSettle();

      await pressAt(tester, it, const Offset3d(1.6, 1.6, 0));
      await tester.pump(style.expand * 2);
      expect(it.ripple!.radius, greaterThan(fromMiddle));
      it.pointer.up();
      await tester.pumpAndSettle();
    });
  });

  group('the timeline', () {
    testWidgets('the lit circle grows, frame after frame', (tester) async {
      final it = await pumpInset(tester);
      await pressAt(tester, it, const Offset3d(2, 2, 0));

      var last = -1.0;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        final radius = it.ripple!.radius;
        expect(radius, greaterThan(last), reason: 'frame $i');
        last = radius;
      }

      it.pointer.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a held press stops asking for frames once it has grown', (
      tester,
    ) async {
      // The property that keeps a long press off the per-frame path. Nothing
      // about the picture changes after the circle has covered the control,
      // so the controller stops its ticker and the surface schedules nothing.
      final it = await pumpInset(tester);
      await pressAt(tester, it, const Offset3d(2, 2, 0));
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'still growing');

      await tester.pumpAndSettle();
      expect(
        it.ripple!.opacity,
        closeTo(theme.stateLayer.press, 1e-9),
        reason: 'held at the press figure, which is the old uniform wash',
      );
      expect(tester.binding.hasScheduledFrame, isFalse);

      it.pointer.up();
      await tester.pumpAndSettle();
      expect(it.ripple, isNull);
    });

    testWidgets('a press that never becomes a press ripples not at all', (
      tester,
    ) async {
      // The arena's half of the design, and the reason there is no
      // unconfirmed phase to animate: the ripple starts on the *reported*
      // press, which the tap recognizer withholds until it has won or its
      // deadline has passed. A pointer that is taken away first — the
      // scrolling view under the control claiming it, here spelled as a
      // cancel — lights nothing up at all.
      final it = await pumpInset(tester);
      it.pointer.down(rayAt(it.surface, const Offset3d(2, 2, 0)));
      it.pointer.cancel();
      await tester.pump(kPressTimeout * 2);
      expect(it.ripple, isNull);
      expect(it.panel.stateLayer, StateLayer3d.none);
    });

    testWidgets('a tap that resolves at once still ripples, and it is a fade', (
      tester,
    ) async {
      // The other end of the same rule. A press and a release in the same
      // instant do reach the control — Flutter reports both — so the run is
      // born already released and the whole of it is the fade-out. Material
      // does the same thing, and a tap that flashed nothing would read as a
      // dead control.
      final it = await pumpInset(tester);
      it.pointer.down(rayAt(it.surface, const Offset3d(2, 2, 0)));
      it.pointer.up();
      // Two frames, because a `Ticker`'s first tick is its own zero: one to
      // start the clock and one to move it.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final run = it.ripple;
      expect(run, isNotNull);
      expect(run!.radius, greaterThan(0.0));
      expect(run.opacity, greaterThan(0.0));
      await tester.pumpAndSettle();
      expect(it.ripple, isNull);
    });

    testWidgets('a second press replaces the first, origin and all', (
      tester,
    ) async {
      // One box carries one pair of uniforms, so it carries one ripple. The
      // finger that is down now is the one the reader is looking at, so it
      // wins — rather than the new press being dropped, or two ripples being
      // averaged into a smear.
      final it = await pumpInset(tester);
      await pressAt(tester, it, const Offset3d(1.7, 1.7, 0));
      await tester.pump(const Duration(milliseconds: 120));
      final first = it.ripple!;
      expect(first.radius, greaterThan(0.0));

      it.pointer.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(it.ripple, isNotNull, reason: 'still fading');

      await pressAt(tester, it, const Offset3d(2.3, 2.3, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final second = it.ripple!;
      expect(second.origin.x, greaterThan(first.origin.x));
      expect(
        second.radius,
        lessThan(first.radius),
        reason: 'the clock restarted with it',
      );

      it.pointer.up();
      await tester.pumpAndSettle();
    });
  });

  group('the tier it must not leave', () {
    testWidgets('a whole ripple costs no build and no layout', (tester) async {
      // The claim of phase 8, stated the way this repository states them:
      // by counting the work across the whole animation rather than by
      // trusting the code path. A press, twenty frames of expansion, a
      // release and the fade, and neither counter moves.
      final it = await pumpInset(tester);
      final laidOut = it.child.layoutCount;
      final built = it.builds[0];

      await pressAt(tester, it, const Offset3d(2.1, 1.9, 0));

      var frames = 0;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        frames++;
        expect(it.surface.needsFlush, isFalse, reason: 'frame $frames');
      }

      it.pointer.up();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 12));
        frames++;
        expect(it.surface.needsFlush, isFalse, reason: 'frame $frames');
      }

      expect(it.ripple, isNull, reason: 'the run finished inside the window');
      expect(it.child.layoutCount, laidOut, reason: 'nothing laid out');
      expect(it.builds[0], built, reason: 'nothing rebuilt');
      expect(frames, 60);
    });

    testWidgets('a control taken out of the tree mid-press leaves no ticker', (
      tester,
    ) async {
      // A ticker outliving its widget is a Flutter error rather than a slow
      // frame, so this one fails loudly if the controller ever forgets to
      // stop it.
      final it = await pumpInset(tester);
      await pressAt(tester, it, const Offset3d(2, 2, 0));
      await tester.pump(const Duration(milliseconds: 30));
      expect(it.ripple, isNotNull);

      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });

  group('without a ticker', () {
    test('the controller falls back to the uniform press wash', () {
      // The behaviour this package shipped before phase 8, kept reachable:
      // no vsync, no ripple, and a press is Material's 10% arriving at once.
      // It is what an imperative scene assembled without a widget tree gets.
      final controller = MutableInkController3d(
        color: theme.colorScheme.onSurface,
        opacities: theme.stateLayer,
      );
      controller.setInkState(Material3dState.pressed, active: true);
      expect(controller.ripple, isNull);
      expect(controller.isAnimating, isFalse);
      expect(controller.layer.opacity, theme.stateLayer.press);
      expect(controller.layer.ripple, isNull);
      controller.dispose();
    });
  });
}
