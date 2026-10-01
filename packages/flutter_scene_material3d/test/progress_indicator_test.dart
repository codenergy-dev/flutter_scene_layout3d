// The two progress indicators: the bar's span and the ring's arc at a value
// and on Flutter's timeline, the overhang, what each announces — and the tier
// both are held to, which is that a whole indeterminate run lays nothing out
// and builds nothing.
//
// The last group is the drift alarm. Flutter's defaults for both indicators
// are private, so they are measured off real ones and read off what those
// paint; its indeterminate curves are private too, so the bar's lines and the
// ring's arc are checked against where a real indicator draws them.

import 'dart:math' as math;
import 'dart:ui' show Color, Rect;

import 'package:flutter/material.dart' as material;
import 'package:flutter/painting.dart' show SweepGradient;
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/animation.dart' show Animation, AnimationController;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        SingleTickerProviderStateMixin,
        State,
        StatefulWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'surfaces_support.dart';

/// One world unit is a hundred logical pixels at the standard metrics.
double dp(double logical) => logical / 100.0;

/// Where [box]'s node transform draws its span, as fractions of its width:
/// the left end and the length.
(double, double) spanOf(Layout3d box) {
  final transform = box.nodeTransform;
  if (transform == null) return (0.0, 1.0);
  return (transform.entry(0, 3) / box.size.width, transform.entry(0, 0));
}

/// The angle [box]'s node transform turns it by, in `[0, 2π)`.
double turnOf(Layout3d box) {
  final transform = box.nodeTransform!;
  final angle = math.atan2(transform.entry(1, 0), transform.entry(0, 0));
  return angle < 0 ? angle + 2 * math.pi : angle;
}

/// [angle] brought into `[0, 2π)`.
double wrapped(double angle) {
  final a = angle % (2 * math.pi);
  return a < 0 ? a + 2 * math.pi : a;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;
  final style = ProgressIndicatorStyle3d.of(theme);
  final scheme = theme.colorScheme;

  group('the bar', () {
    testWidgets('is 4dp of primary on secondaryContainer, as wide as allowed', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const LinearProgressIndicator3d(value: 0.5),
      );
      final track = it.panels[0];
      final bar = it.panels[1];
      expect(track.size.width, closeTo(4.0, 1e-9), reason: 'the surface');
      expect(track.size.height, closeTo(dp(4), 1e-9));
      expect(track.size.depth, closeTo(dp(theme.thickness.thin), 1e-9));
      expect(
        (track.decoration as BoxDecoration3d).color,
        scheme.secondaryContainer,
      );
      expect((bar.decoration as BoxDecoration3d).color, scheme.primary);
      expect(
        bar.size.width,
        closeTo(track.size.width, 1e-9),
        reason: 'the bar is laid out as long as the track, at every value',
      );
    });

    testWidgets('stands in front of its track', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const LinearProgressIndicator3d(value: 0.5),
      );
      final steps = oneOf<Stack3d>(
        it.surface,
      ).children.map((child) => child.sceneOffset.z).toList();
      expect(steps, hasLength(2));
      expect(steps[0], 0.0);
      expect(steps[1], closeTo(-dp(style.depthStep), 1e-9));
      expect(
        theme.thickness.separates(
          style.thickness,
          style.thickness,
          step: style.depthStep,
        ),
        isTrue,
      );
    });

    testWidgets('fills to its value by a scale, not a width', (tester) async {
      for (final value in <double>[0.0, 0.3, 1.0]) {
        final it = await pumpComponent(
          tester,
          () => LinearProgressIndicator3d(value: value),
        );
        final span = namedBox(it.surface, 'LinearProgressIndicator3d value');
        final (left, length) = spanOf(span);
        expect(left, closeTo(0.0, 1e-6));
        expect(length, closeTo(value, 1e-6), reason: 'at $value');
      }
    });

    testWidgets('holds its value to [0, 1], as Flutter does', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const LinearProgressIndicator3d(value: 1.7),
      );
      expect(
        namedBox(it.surface, 'LinearProgressIndicator3d value').nodeTransform,
        isNull,
        reason: 'a full bar needs no transform at all',
      );
    });

    testWidgets('fills from the right in right to left', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const LinearProgressIndicator3d(value: 0.3),
        textDirection: TextDirection.rtl,
      );
      final (left, length) = spanOf(
        namedBox(it.surface, 'LinearProgressIndicator3d value'),
      );
      expect(left, closeTo(0.7, 1e-6));
      expect(length, closeTo(0.3, 1e-6));
    });

    testWidgets('takes its colours and height from its arguments', (
      tester,
    ) async {
      const red = Color(0xFFFF0000);
      const grey = Color(0xFF808080);
      final it = await pumpComponent(
        tester,
        () => const LinearProgressIndicator3d(
          value: 0.5,
          color: red,
          backgroundColor: grey,
          minHeight: 8,
        ),
      );
      expect((it.panels[0].decoration as BoxDecoration3d).color, grey);
      expect((it.panels[1].decoration as BoxDecoration3d).color, red);
      expect(it.panels[0].size.height, closeTo(dp(8), 1e-9));
    });

    testWidgets('announces a progress bar from 0 to 100', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const LinearProgressIndicator3d(
          value: 0.25,
          semanticsLabel: 'Downloading',
        ),
      );
      final properties = it.semantics.properties;
      expect(properties.label, 'Downloading');
      expect(properties.role, SemanticsRole.progressBar);
      expect(properties.value, '25');
      expect(properties.minValue, '0');
      expect(properties.maxValue, '100');
    });
  });

  group('the bar, indeterminate', () {
    testWidgets('runs Flutter\'s two lines on Flutter\'s clock', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const LinearProgressIndicator3d(),
      );
      // A ticker's first tick is its own zero; see `docs/traps.md`.
      await tester.pump();
      var elapsed = 0;
      for (final ms in <int>[300, 500, 1100, 1500]) {
        await tester.pump(Duration(milliseconds: ms - elapsed));
        elapsed = ms;
        final t = ms / 1800;
        for (final (name, at) in <(String, (double, double) Function(double))>[
          ('first line', LinearProgressIndicator3d.firstLineAt),
          ('second line', LinearProgressIndicator3d.secondLineAt),
        ]) {
          final (tail, head) = at(t);
          final (left, length) = spanOf(
            namedBox(it.surface, 'LinearProgressIndicator3d $name'),
          );
          final expected = (head - tail).clamp(0.0, 1.0);
          expect(length, closeTo(expected, 1e-5), reason: '$name at ${ms}ms');
          if (expected > 0) {
            expect(left, closeTo(tail, 1e-5), reason: '$name at ${ms}ms');
          }
        }
      }
    });

    testWidgets('announces a loading spinner, with no value', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const LinearProgressIndicator3d(semanticsLabel: 'Loading'),
      );
      final properties = it.semantics.properties;
      expect(properties.role, SemanticsRole.loadingSpinner);
      expect(properties.value, isNull);
      expect(properties.minValue, isNull);
    });

    testWidgets('lays nothing out and builds nothing, for a second', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const LinearProgressIndicator3d(),
      );
      await tester.pump();
      await expectNothingLaidOut(tester, it.surface);
    });

    testWidgets('stops asking for frames once it has a value', (tester) async {
      double? value;
      late void Function(void Function()) rebuild;
      await pumpComponent(
        tester,
        () => _Host(
          builder: (context, setState) {
            rebuild = setState;
            return LinearProgressIndicator3d(value: value);
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'running');
      rebuild(() => value = 0.4);
      // Settling at all is the assertion: a clock still running would spin.
      await tester.pumpAndSettle();
    });
  });

  group('the ring', () {
    testWidgets('is a 36dp box with a 40dp ring over it', (tester) async {
      // Flutter centres its stroke on the circle the box inscribes, so the
      // ring overhangs the box by half a stroke all round.
      final it = await pumpComponent(
        tester,
        () => const CircularProgressIndicator3d(value: 0.25),
      );
      final ring = namedBox(it.surface, 'CircularProgressIndicator3d ring');
      final box = namedBox(it.surface, 'CircularProgressIndicator3d');
      expect(box.size.width, closeTo(dp(36), 1e-9));
      expect(ring.size.width, closeTo(dp(40), 1e-9));
      expect(ring.size.height, closeTo(dp(40), 1e-9));
      expect(ring.offset.x, closeTo(-dp(2), 1e-9));
      expect(ring.offset.y, closeTo(-dp(2), 1e-9));
      final decoration = (ring as DecoratedBox3d).decoration as BoxDecoration3d;
      expect(decoration.color.a, 0.0, reason: 'nothing in the middle');
      expect(decoration.border.width, 4.0);
      expect(decoration.borderRadius, theme.shape.full);
    });

    testWidgets('draws its value as a sweep on its border', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const CircularProgressIndicator3d(value: 0.25),
      );
      final ring =
          namedBox(it.surface, 'CircularProgressIndicator3d ring')
              as DecoratedBox3d;
      final border = (ring.decoration as BoxDecoration3d).border;
      final sweep = border.gradient! as SweepGradient;
      expect(sweep.stops, <double>[0.0, 0.25, 0.25, 1.0]);
      expect(sweep.colors[0], scheme.primary);
      expect(sweep.colors[1], scheme.primary);
      expect(sweep.colors[2].a, 0.0, reason: 'no track by default');

      // And the shader is told the ramp is the border's, not the fill's.
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: ring.decoration as BoxDecoration3d,
        size: ring.size,
        metrics: Layout3dMetrics.standard,
      );
      expect(uniforms.gradientPaintsBorder, isTrue);
    });

    testWidgets('starts at twelve o\'clock, turned about its centre', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const CircularProgressIndicator3d(value: 0.25),
      );
      final ring = namedBox(it.surface, 'CircularProgressIndicator3d ring');
      // A quarter turn back from three o'clock, the sweep's own zero.
      expect(turnOf(ring), closeTo(1.5 * math.pi, 1e-6));
      final c = ring.size.center;
      final moved = ring.nodeTransform!.transform3(Vector3(c.x, c.y, c.z));
      expect(moved.x, closeTo(c.x, 1e-6));
      expect(moved.y, closeTo(c.y, 1e-6));
    });

    testWidgets('its track is the rest of the same ramp', (tester) async {
      const grey = Color(0xFF808080);
      final it = await pumpComponent(
        tester,
        () => const CircularProgressIndicator3d(
          value: 0.6,
          backgroundColor: grey,
        ),
      );
      final ring =
          namedBox(it.surface, 'CircularProgressIndicator3d ring')
              as DecoratedBox3d;
      final sweep =
          (ring.decoration as BoxDecoration3d).border.gradient!
              as SweepGradient;
      expect(sweep.colors, <Color>[scheme.primary, scheme.primary, grey, grey]);
      expect(
        boxesOf<DecoratedBox3d>(it.surface),
        hasLength(1),
        reason: 'one slab, so the track cannot z-fight the arc',
      );
    });

    testWidgets('an empty ring draws no arc at all', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const CircularProgressIndicator3d(value: 0.0),
      );
      final ring =
          namedBox(it.surface, 'CircularProgressIndicator3d ring')
              as DecoratedBox3d;
      final sweep =
          (ring.decoration as BoxDecoration3d).border.gradient!
              as SweepGradient;
      expect(sweep.colors.every((c) => c.a == 0.0), isTrue);
    });

    testWidgets('fits a smaller box, and its stroke follows', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const SceneSizedBox3d(
          width: 0.2,
          height: 0.2,
          child: CircularProgressIndicator3d(strokeWidth: 2),
        ),
      );
      final ring =
          namedBox(it.surface, 'CircularProgressIndicator3d ring')
              as DecoratedBox3d;
      expect(ring.size.width, closeTo(dp(22), 1e-9));
      expect((ring.decoration as BoxDecoration3d).border.width, 2.0);
    });

    testWidgets('announces a progress bar with a value', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const CircularProgressIndicator3d(
          value: 0.5,
          semanticsLabel: 'Uploading',
          semanticsValue: '1 of 2',
        ),
      );
      final properties = it.semantics.properties;
      expect(properties.role, SemanticsRole.progressBar);
      expect(properties.value, '1 of 2');
    });
  });

  group('the ring, indeterminate', () {
    testWidgets('follows Flutter\'s head, tail and turn', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const CircularProgressIndicator3d(),
      );
      await tester.pump();
      var elapsed = 0;
      for (final ms in <int>[200, 700, 1300, 2500]) {
        await tester.pump(Duration(milliseconds: ms - elapsed));
        elapsed = ms;
        final t = ms / (1333 * 2222);
        final (start, sweep) = CircularProgressIndicator3d.indeterminateArcAt(
          t,
        );
        final ring =
            namedBox(it.surface, 'CircularProgressIndicator3d ring')
                as DecoratedBox3d;
        // The caps: half a 4dp stroke, along an 18dp radius.
        const cap = 2.0 / 18.0;
        final fraction =
            ((ring.decoration as BoxDecoration3d).border.gradient!
                    as SweepGradient)
                .stops![1];
        expect(
          fraction,
          closeTo((sweep + 2 * cap) / (2 * math.pi), 1e-6),
          reason: 'the arc at ${ms}ms',
        );
        expect(
          turnOf(ring),
          closeTo(wrapped(start - cap), 1e-4),
          reason: 'its start at ${ms}ms',
        );
      }
    });

    testWidgets('lays nothing out and builds nothing, for a second', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const CircularProgressIndicator3d(),
      );
      await tester.pump();
      await expectNothingLaidOut(tester, it.surface);
    });

    testWidgets('announces a loading spinner', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const CircularProgressIndicator3d(),
      );
      expect(it.semantics.properties.role, SemanticsRole.loadingSpinner);
    });
  });

  group('the watcher these tests trust', () {
    // If the watcher missed either of these, every "nothing laid out" above
    // would be proving nothing. Dirt reaches a surface two ways — a tick that
    // resizes a box, and a rebuild that does — and it has to see both.
    testWidgets('sees a box a tick resizes', (tester) async {
      final it = await pumpComponent(tester, () => const _TickingWidth());
      await tester.pump();
      final watched = await watchFrames(tester, it.surface, frames: 6);
      expect(watched.laidOut, isNotEmpty);
    });

    testWidgets('and an animation that rebuilds to resize', (tester) async {
      var wide = false;
      late void Function(void Function()) rebuild;
      final it = await pumpComponent(
        tester,
        () => _Host(
          builder: (context, setState) {
            rebuild = setState;
            return SceneAnimatedContainer3d(
              duration: const Duration(milliseconds: 200),
              width: wide ? 2.0 : 1.0,
              height: 1.0,
            );
          },
        ),
      );
      rebuild(() => wide = true);
      await tester.pump();
      final watched = await watchFrames(tester, it.surface, frames: 6);
      expect(watched.laidOut, isNotEmpty);
      expect(watched.rebuilt, isNotEmpty);
      await tester.pumpAndSettle();
    });
  });

  group('the defaults, against Flutter\'s own indicators', () {
    Future<void> pumpMaterial(WidgetTester tester, Widget child) =>
        tester.pumpWidget(
          material.MaterialApp(
            theme: material.ThemeData(
              useMaterial3: true,
              colorScheme: material.ColorScheme.fromSeed(
                seedColor: const Color(0xFF6750A4),
              ),
            ),
            home: material.Scaffold(
              body: material.Center(
                child: material.SizedBox(width: 200, child: child),
              ),
            ),
          ),
        );

    material.ColorScheme schemeOf(WidgetTester tester) => material.Theme.of(
      tester.element(find.byType(material.Scaffold)),
    ).colorScheme;

    test('the lines run on Flutter\'s published duration', () {
      expect(
        LinearProgressIndicator3d.indeterminateDuration,
        material.LinearProgressIndicator.defaultAnimationDuration,
      );
    });

    testWidgets('a bar is as tall as Flutter\'s, in the same two roles', (
      tester,
    ) async {
      final bar = material.LinearProgressIndicator(value: 0.5);
      await pumpMaterial(tester, bar);
      expect(tester.getSize(find.byWidget(bar)).height, style.linearMinHeight);
      final roles = schemeOf(tester);
      // The track, then the value: the roles this table takes are
      // `secondaryContainer` and `primary`.
      expect(
        find.byType(material.LinearProgressIndicator),
        paints
          ..rect(color: roles.secondaryContainer)
          ..rect(color: roles.primary),
      );
    });

    testWidgets('a circle is as big as Flutter\'s, stroked the same', (
      tester,
    ) async {
      final ring = material.CircularProgressIndicator(value: 0.5);
      await pumpMaterial(tester, material.Center(child: ring));
      expect(tester.getSize(find.byWidget(ring)).width, style.circularSize);
      expect(
        find.byType(material.CircularProgressIndicator),
        paints..arc(
          color: schemeOf(tester).primary,
          strokeWidth: style.strokeWidth,
        ),
      );
    });

    testWidgets('the lines are where Flutter draws them', (tester) async {
      // The four curves are private in Flutter, so the transcription is
      // checked against a real bar: its first line's rectangle at a known
      // point of the pass.
      const bar = material.LinearProgressIndicator();
      await pumpMaterial(tester, bar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final (tail, head) = LinearProgressIndicator3d.firstLineAt(500 / 1800);
      final primary = schemeOf(tester).primary;
      final drawn = <Rect>[];
      expect(
        find.byType(material.LinearProgressIndicator),
        paints..everything((method, arguments) {
          // A `Paint` hands its colour back at single precision, so the
          // comparison is by the 32-bit value both round to.
          if (method == #drawRect &&
              (arguments[1] as material.Paint).color.toARGB32() ==
                  primary.toARGB32()) {
            drawn.add(arguments[0] as Rect);
          }
          return true;
        }),
      );
      expect(
        drawn.any(
          (rect) =>
              (rect.left - tail * 200).abs() < 1e-6 &&
              (rect.right - head * 200).abs() < 1e-6,
        ),
        isTrue,
        reason: 'Flutter drew its lines at $drawn',
      );
    });

    testWidgets('and so is the arc', (tester) async {
      const ring = material.CircularProgressIndicator();
      await pumpMaterial(tester, material.Center(child: ring));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final (start, sweep) = CircularProgressIndicator3d.indeterminateArcAt(
        700 / (1333 * 2222),
      );
      late double drawnStart;
      late double drawnSweep;
      expect(
        find.byType(material.CircularProgressIndicator),
        paints..something((method, arguments) {
          if (method != #drawArc) return false;
          drawnStart = arguments[1] as double;
          drawnSweep = arguments[2] as double;
          return true;
        }),
      );
      expect(drawnStart, closeTo(start, 1e-9));
      expect(drawnSweep, closeTo(sweep, 1e-9));
    });
  });
}

/// A minimal stateful host, so a test can change an indicator the way an
/// application does.
class _Host extends StatefulWidget {
  const _Host({required this.builder});

  final Widget Function(BuildContext, void Function(void Function())) builder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
}

/// A box whose width a ticker changes on every frame, the way a component
/// on the wrong tier would: the watcher's first control case.
class _TickingWidth extends StatefulWidget {
  const _TickingWidth();

  @override
  State<_TickingWidth> createState() => _TickingWidthState();
}

class _TickingWidthState extends State<_TickingWidth>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    duration: const Duration(seconds: 1),
    vsync: this,
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SceneTickingWidth(_clock);
}

class _SceneTickingWidth extends Layout3dWidget {
  const _SceneTickingWidth(this.clock);

  final Animation<double> clock;

  @override
  SizedBox3d createLayout(BuildContext context) {
    final box = SizedBox3d(width: 1.0, height: 1.0);
    clock.addListener(() => box.width = 1.0 + clock.value);
    return box;
  }

  @override
  void updateLayout(BuildContext context, SizedBox3d layout) {}
}
