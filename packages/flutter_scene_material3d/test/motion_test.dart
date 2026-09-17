// MotionScheme3d: the seventh token family, checked value for value against
// Flutter's own Durations and Easing — which are generated straight from the
// Material token database, and are therefore the strongest drift alarm in
// this package.

import 'package:flutter/animation.dart' show Curve;
import 'package:flutter/material.dart' show Durations, Easing;
import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, Widget;
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlays_support.dart';

void main() {
  group('the durations are Material 3\'s', () {
    const motion = MotionScheme3d.baseline;

    test('every one of the sixteen matches Flutter', () {
      expect(motion.short1, Durations.short1);
      expect(motion.short2, Durations.short2);
      expect(motion.short3, Durations.short3);
      expect(motion.short4, Durations.short4);
      expect(motion.medium1, Durations.medium1);
      expect(motion.medium2, Durations.medium2);
      expect(motion.medium3, Durations.medium3);
      expect(motion.medium4, Durations.medium4);
      expect(motion.long1, Durations.long1);
      expect(motion.long2, Durations.long2);
      expect(motion.long3, Durations.long3);
      expect(motion.long4, Durations.long4);
      expect(motion.extraLong1, Durations.extralong1);
      expect(motion.extraLong2, Durations.extralong2);
      expect(motion.extraLong3, Durations.extralong3);
      expect(motion.extraLong4, Durations.extralong4);
    });

    test('the scale climbs and never repeats', () {
      const scale = <Duration>[
        Duration(milliseconds: 50),
        Duration(milliseconds: 100),
        Duration(milliseconds: 150),
        Duration(milliseconds: 200),
        Duration(milliseconds: 250),
        Duration(milliseconds: 300),
        Duration(milliseconds: 350),
        Duration(milliseconds: 400),
        Duration(milliseconds: 450),
        Duration(milliseconds: 500),
        Duration(milliseconds: 550),
        Duration(milliseconds: 600),
        Duration(milliseconds: 700),
        Duration(milliseconds: 800),
        Duration(milliseconds: 900),
        Duration(milliseconds: 1000),
      ];
      final mine = <Duration>[
        motion.short1,
        motion.short2,
        motion.short3,
        motion.short4,
        motion.medium1,
        motion.medium2,
        motion.medium3,
        motion.medium4,
        motion.long1,
        motion.long2,
        motion.long3,
        motion.long4,
        motion.extraLong1,
        motion.extraLong2,
        motion.extraLong3,
        motion.extraLong4,
      ];
      expect(mine, scale);
      for (var i = 1; i < mine.length; i++) {
        expect(
          mine[i],
          greaterThan(mine[i - 1]),
          reason: 'the scale is a scale',
        );
      }
    });
  });

  group('the easings are Material 3\'s', () {
    const motion = MotionScheme3d.baseline;

    test('every one of the nine matches Flutter', () {
      // Identity, and that is the assertion: `Cubic` has no value equality,
      // both sides are `const`, and Dart canonicalizes them — so a figure
      // that moves upstream stops being the same object and fails here.
      expect(motion.emphasizedAccelerate, same(Easing.emphasizedAccelerate));
      expect(motion.emphasizedDecelerate, same(Easing.emphasizedDecelerate));
      expect(motion.standard, same(Easing.standard));
      expect(motion.standardAccelerate, same(Easing.standardAccelerate));
      expect(motion.standardDecelerate, same(Easing.standardDecelerate));
      expect(motion.legacy, same(Easing.legacy));
      expect(motion.legacyAccelerate, same(Easing.legacyAccelerate));
      expect(motion.legacyDecelerate, same(Easing.legacyDecelerate));
      expect(motion.linear, same(Easing.linear));
    });

    test('they run from nothing to everything', () {
      final curves = <Curve>[
        motion.emphasizedAccelerate,
        motion.emphasizedDecelerate,
        motion.standard,
        motion.linear,
      ];
      for (final curve in curves) {
        expect(curve.transform(0.0), closeTo(0.0, 1e-6));
        expect(curve.transform(1.0), closeTo(1.0, 1e-6));
      }
    });

    test('an arrival front-loads and a departure back-loads', () {
      // What "emphasized" means, stated as the property a component relies
      // on rather than as four cubic control points.
      expect(
        motion.emphasizedDecelerate.transform(0.5),
        greaterThan(0.5),
        reason: 'most of an arrival is over by half way',
      );
      expect(
        motion.emphasizedAccelerate.transform(0.5),
        lessThan(0.5),
        reason: 'a departure saves its distance for the end',
      );
    });
  });

  group('interpolating a scheme', () {
    test('the durations move and the curves snap at the midpoint', () {
      const slow = MotionScheme3d(
        short3: Duration(milliseconds: 300),
        standard: Easing.legacy,
      );
      const fast = MotionScheme3d.baseline;

      final quarter = MotionScheme3d.lerp(slow, fast, 0.25);
      expect(
        quarter.short3,
        const Duration(milliseconds: 262, microseconds: 500),
      );
      expect(quarter.standard, same(slow.standard));

      final most = MotionScheme3d.lerp(slow, fast, 0.75);
      expect(most.short3, const Duration(milliseconds: 187, microseconds: 500));
      expect(most.standard, same(fast.standard));

      // The switch is at the midpoint itself, not after it.
      expect(
        MotionScheme3d.lerp(slow, fast, 0.5).standard,
        same(fast.standard),
      );
      expect(
        MotionScheme3d.lerp(slow, fast, 0.49).standard,
        same(slow.standard),
      );
    });

    test('the ends are the ends', () {
      const a = MotionScheme3d(short1: Duration(milliseconds: 10));
      const b = MotionScheme3d(short1: Duration(milliseconds: 90));
      expect(MotionScheme3d.lerp(a, b, 0.0), a);
      expect(MotionScheme3d.lerp(a, b, 1.0), b);
    });

    test('an overshooting curve cannot produce a negative duration', () {
      const a = MotionScheme3d(short1: Duration(milliseconds: 100));
      const b = MotionScheme3d(short1: Duration(milliseconds: 200));
      // What a Curves.elasticOut hands a tween below zero.
      expect(MotionScheme3d.lerp(a, b, -3.0).short1, Duration.zero);
    });
  });

  group('the value', () {
    test('copyWith replaces one token and keeps the rest', () {
      final slower = MotionScheme3d.baseline.copyWith(
        short3: const Duration(milliseconds: 500),
      );
      expect(slower.short3, const Duration(milliseconds: 500));
      expect(slower.short4, MotionScheme3d.baseline.short4);
      expect(slower.standard, same(MotionScheme3d.baseline.standard));
      expect(slower, isNot(MotionScheme3d.baseline));
    });

    test('equality is over every one of the twenty-five', () {
      expect(const MotionScheme3d(), MotionScheme3d.baseline);
      expect(const MotionScheme3d().hashCode, MotionScheme3d.baseline.hashCode);
      expect(
        const MotionScheme3d(extraLong4: Duration(milliseconds: 999)),
        isNot(MotionScheme3d.baseline),
      );
      expect(
        const MotionScheme3d(linear: Easing.standard),
        isNot(MotionScheme3d.baseline),
      );
    });
  });

  group('the theme carries it', () {
    test('both baselines get the Material figures', () {
      expect(Theme3dData.light.motion, MotionScheme3d.baseline);
      expect(
        Theme3dData.dark.motion,
        MotionScheme3d.baseline,
        reason: 'a dialog does not open more slowly at night',
      );
    });

    test('copyWith and equality reach the seventh family', () {
      final slow = Theme3dData.light.copyWith(
        motion: MotionScheme3d.baseline.copyWith(
          short3: const Duration(milliseconds: 400),
        ),
      );
      expect(slow.motion.short3, const Duration(milliseconds: 400));
      expect(slow, isNot(Theme3dData.light));
      expect(slow.colorScheme, Theme3dData.light.colorScheme);
    });

    test('a theme tween interpolates it with the rest', () {
      final tween = Theme3dDataTween(
        begin: Theme3dData.light,
        end: Theme3dData.light.copyWith(
          motion: const MotionScheme3d(short1: Duration(milliseconds: 150)),
        ),
      );
      expect(
        tween.transform(0.5).motion.short1,
        const Duration(milliseconds: 100),
      );
    });

    test('a motion tween is the family on its own', () {
      final tween = MotionScheme3dTween(
        begin: const MotionScheme3d(medium1: Duration(milliseconds: 200)),
        end: const MotionScheme3d(medium1: Duration(milliseconds: 400)),
      );
      expect(tween.transform(0.5).medium1, const Duration(milliseconds: 300));
    });
  });

  group('the overlays arrive', () {
    // The claim the whole family exists to make: nothing in the catalogue
    // appears any more. Each of these checks the same three things — that the
    // thing is somewhere else part way through, that it is at rest when the
    // clock finishes, and that the clock finishes at all, which is what
    // `pumpAndSettle` returning is.

    testWidgets('a dialog grows and its scrim fades with it, not into it', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester);
      showDialog3d<void>(
        context: pumped.context,
        builder: (context) => const Dialog3d(child: SceneSizedBox3d.cube(0.4)),
      );
      // One frame to build the entry's subtree, then half the 150ms.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));

      final moving = oneOf<MotionTransition3d>(pumped.surface);
      expect(
        moving.nodeTransform,
        isNotNull,
        reason: 'a dialog part way through its arrival is scaled',
      );
      expect(
        moving.imposedOpacity,
        lessThan(1.0),
        reason: 'and part way through its fade',
      );
      // The scrim dims on a box of its own, which is what keeps it still.
      final scrim = oneOf<FadeTransition3d>(pumped.surface);
      expect(scrim.imposedOpacity, lessThan(1.0));
      expect(scrim.nodeOffset, Offset3d.zero);

      await tester.pumpAndSettle();
      expect(moving.nodeTransform, isNull, reason: 'at rest is no matrix');
      expect(moving.imposedOpacity, 1.0);
      expect(scrim.imposedOpacity, 1.0);

      Navigator3d.of(pumped.overlay)!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        pumped.overlay.entries,
        hasLength(1),
        reason: 'the entry is in the overlay for the whole of its departure',
      );
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('a sheet starts one whole height off the edge it names', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester);
      showModalBottomSheet3d<void>(
        context: pumped.context,
        builder: (context) => const BottomSheet3d(
          child: SceneSizedBox3d(width: 2, height: 0.8, depth: 0.02),
        ),
      );
      await tester.pump();
      await tester.pump();

      final moving = oneOf<MotionTransition3d>(pumped.surface);
      // Its own height, not a figure: the sheet is 0.8 tall plus its padding,
      // and whatever that came to is how far down it starts.
      expect(moving.nodeOffset.y, closeTo(moving.size.height, 1e-6));
      expect(moving.nodeOffset.x, 0.0);

      await tester.pumpAndSettle();
      expect(moving.nodeOffset, Offset3d.zero);
    });

    testWidgets('a side sheet comes in from its own side', (tester) async {
      final pumped = await pumpOverlay(tester);
      showModalBottomSheet3d<void>(
        context: pumped.context,
        edge: Sheet3dEdge.right,
        builder: (context) => const BottomSheet3d(
          edge: Sheet3dEdge.right,
          child: SceneSizedBox3d(width: 1.5, height: 2, depth: 0.02),
        ),
      );
      await tester.pump();
      await tester.pump();

      final moving = oneOf<MotionTransition3d>(pumped.surface);
      expect(
        moving.nodeOffset.x,
        closeTo(moving.size.width, 1e-6),
        reason: 'the style says how long and the edge says which way',
      );
      expect(moving.nodeOffset.y, 0.0);
      await tester.pumpAndSettle();
    });

    testWidgets('a tooltip fades and moves nothing', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: const Tooltip3d(
          message: 'Compose',
          child: SceneSizedBox3d.cube(0.5),
        ),
      );
      final style = TooltipStyle3d.of(Theme3dData.light);
      expect(style.arrival.motion, const Motion3d.fade());

      final pointer = Layout3dPointer(pumped.surface);
      pointer.hover(rayAt(pumped.surface, const Offset3d(4, 3, 0)));
      await tester.pump(style.waitDuration + const Duration(milliseconds: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));

      final moving = oneOf<MotionTransition3d>(pumped.surface);
      expect(moving.imposedOpacity, lessThan(1.0));
      expect(moving.nodeOffset, Offset3d.zero, reason: 'a fade moves nothing');
      expect(moving.nodeTransform, isNull);

      await tester.pumpAndSettle();
      expect(moving.imposedOpacity, 1.0);
    });

    testWidgets('a bar waits for the one before it to finish leaving', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester, child: const _Messenger());
      final messenger = ScaffoldMessenger3d.of(
        tester.element(find.byType(SceneText3d)),
      );
      messenger.show(const SnackBar3d(message: 'Saved'));
      messenger.show(const SnackBar3d(message: 'Deleted'));
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, hasLength(1));

      messenger.removeCurrent();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      expect(
        pumped.overlay.entries,
        hasLength(1),
        reason: 'the first is still sinking and the second has not risen',
      );
      final leaving = oneOf<MotionTransition3d>(pumped.surface);
      expect(leaving.nodeOffset.y, greaterThan(0.0));

      await tester.pumpAndSettle();
      expect(
        pumped.overlay.entries,
        hasLength(1),
        reason: 'and now it is the second one, at rest',
      );
      expect(
        oneOf<MotionTransition3d>(pumped.surface).nodeOffset,
        Offset3d.zero,
      );

      messenger.clear();
      await tester.pumpAndSettle();
      expect(pumped.overlay.entries, isEmpty);
    });
  });
}

/// A messenger with something under it a test can reach a context through.
class _Messenger extends StatelessWidget {
  const _Messenger();

  @override
  Widget build(BuildContext context) =>
      const ScaffoldMessenger3d(child: SceneText3d('screen'));
}
