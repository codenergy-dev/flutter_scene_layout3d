// The slider: its geometry, the arithmetic between a value and a position,
// the two tiers a drag is allowed to touch, what it announces — and the one
// claim it exists to make, which is that a slider inside a scrolling list
// wins the pointer against the scroll.

import 'package:flutter/widgets.dart'
    show BuildContext, State, StatefulWidget, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

/// One world unit is a hundred logical pixels at the standard metrics.
double dp(double logical) => logical / 100.0;

/// The centre of [box], in the surface's own frame.
Offset3d centreOf(Layout3d box) => offsetInSurface(box) + box.size.center;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;
  final style = SliderStyle3d.of(theme);

  group('the geometry', () {
    testWidgets('is a 144dp control with a 124dp track and a 20dp thumb', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.5, onChanged: (_) {}),
      );
      // Four panels: the wash, the inactive track, the active track, the
      // thumb.
      expect(it.panels.length, 4);
      expect(it.panels[0].size.width, closeTo(dp(144), 1e-9));
      expect(it.panels[0].size.height, closeTo(dp(48), 1e-9));
      expect(
        it.panels[1].size.width,
        closeTo(dp(144 - 20), 1e-9),
        reason:
            'the track is inset by half a thumb at each end, so the thumb '
            'centre reaches the ends rather than the edges',
      );
      expect(it.panels[1].size.height, closeTo(dp(4), 1e-9));
      expect(it.panels[3].size.width, closeTo(dp(20), 1e-9));
      expect(
        it.panels[3].size.depth,
        closeTo(dp(theme.thickness.standard), 1e-9),
      );
    });

    testWidgets('and the thumb and its fill stand proud of the track', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.5, onChanged: (_) {}),
      );
      final steps = oneOf<Stack3d>(
        it.surface,
      ).children.map((child) => child.sceneOffset.z).toList();
      expect(steps, hasLength(4));
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], closeTo(-i * dp(style.depthStep), 1e-9));
      }
      expect(
        theme.thickness.separates(
          style.trackThickness,
          style.thumbThickness,
          step: style.depthStep,
        ),
        isTrue,
      );
    });

    testWidgets('the active track is a scale, not a width', (tester) async {
      // The finding this component turns on. Filling a track by giving a box
      // a width is a relayout on every frame of a drag; a node transform
      // pivots on the box's origin corner, so a full-length track scaled by
      // the value keeps its left end where layout put it and stops at the
      // thumb.
      for (final value in <double>[0.0, 0.25, 1.0]) {
        final it = await pumpComponent(
          tester,
          () => Slider3d(value: value, onChanged: (_) {}),
        );
        final shifts = componentShifts(it.surface);
        expect(shifts, hasLength(2), reason: 'the fill and the thumb');
        expect(shifts[0].scaleX, closeTo(value, 1e-9));
        expect(
          it.panels[2].size.width,
          closeTo(it.panels[1].size.width, 1e-9),
          reason: 'both tracks are laid out the same length, at every value',
        );
      }
    });

    testWidgets('and the thumb rides the track on the node tier', (
      tester,
    ) async {
      for (final entry in <double, double>{
        0.0: -0.5,
        0.5: 0.0,
        1.0: 0.5,
      }.entries) {
        final it = await pumpComponent(
          tester,
          () => Slider3d(value: entry.key, onChanged: (_) {}),
        );
        final thumb = componentShifts(it.surface)[1];
        expect(
          thumb.shift.x,
          closeTo(entry.value * dp(144 - 20), 1e-9),
          reason: 'the thumb at ${entry.key}',
        );
      }
    });

    testWidgets('a wider slider stretches the track and nothing else', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.5, width: 240.0, onChanged: (_) {}),
      );
      expect(it.panels[0].size.width, closeTo(dp(240), 1e-9));
      expect(it.panels[1].size.width, closeTo(dp(220), 1e-9));
      expect(it.panels[3].size.width, closeTo(dp(20), 1e-9));
    });
  });

  group('the arithmetic between a value and a position', () {
    test('a fraction is clamped into the range', () {
      const slider = Slider3d(value: 5.0, min: 0.0, max: 10.0);
      expect(slider.fraction, 0.5);
      expect(const Slider3d(value: -1.0).fraction, 0.0);
      expect(const Slider3d(value: 2.0).fraction, 1.0);
    });

    test('a degenerate range reads as empty rather than dividing by zero', () {
      const slider = Slider3d(value: 3.0, min: 3.0, max: 3.0);
      expect(slider.fraction, 0.0);
      expect(slider.fraction.isNaN, isFalse);
    });

    test('divisions snap to the nearest step', () {
      const slider = Slider3d(value: 0.0, divisions: 4);
      expect(slider.snap(0.0), 0.0);
      expect(slider.snap(0.1), 0.0);
      expect(slider.snap(0.13), closeTo(0.25, 1e-9));
      expect(slider.snap(0.6), closeTo(0.5, 1e-9));
      expect(slider.snap(1.0), 1.0);
    });

    test('and a value comes back in the range it was asked for', () {
      const slider = Slider3d(value: 0.0, min: 10.0, max: 20.0, divisions: 2);
      expect(slider.valueFor(0.0), 10.0);
      expect(slider.valueFor(0.4), closeTo(15.0, 1e-9));
      expect(slider.valueFor(1.0), 20.0);
    });

    testWidgets('a divided slider draws at the step it snapped to', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.6, divisions: 4, onChanged: (_) {}),
      );
      expect(componentShifts(it.surface)[0].scaleX, closeTo(0.5, 1e-9));
    });
  });

  group('a drag', () {
    testWidgets('reports the value under the finger, once it has committed', (
      tester,
    ) async {
      final reported = <double>[];
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.0, onChanged: reported.add),
      );
      final gesture = oneOf<SliderGesture3d>(it.surface);
      final left =
          offsetInSurface(gesture) +
          Offset3d(gesture.padding, gesture.size.height / 2.0, 0.0);

      it.pointer.down(rayAt(it.surface, left));
      expect(reported, isEmpty, reason: 'a press alone changes nothing');

      // Under the touch slop: still nothing, because the finger may yet turn
      // out to be scrolling something.
      it.pointer.move(rayAt(it.surface, left + const Offset3d(0.05, 0, 0)));
      expect(reported, isEmpty);

      it.pointer.move(rayAt(it.surface, left + const Offset3d(0.62, 0, 0)));
      expect(reported.single, closeTo(0.5, 1e-6), reason: 'half the track');

      it.pointer.move(rayAt(it.surface, left + const Offset3d(1.24, 0, 0)));
      expect(reported.last, closeTo(1.0, 1e-6));

      // Past the end, and it holds rather than running off.
      it.pointer.move(rayAt(it.surface, left + const Offset3d(2.0, 0, 0)));
      expect(reported.last, closeTo(1.0, 1e-6));
      it.pointer.up();
    });

    testWidgets('calls start once and end once', (tester) async {
      var starts = 0;
      var ends = 0;
      final it = await pumpComponent(
        tester,
        () => Slider3d(
          value: 0.0,
          onChanged: (_) {},
          onChangeStart: () => starts++,
          onChangeEnd: () => ends++,
        ),
      );
      final gesture = oneOf<SliderGesture3d>(it.surface);
      final at = centreOf(gesture);
      it.pointer.down(rayAt(it.surface, at));
      it.pointer.move(rayAt(it.surface, at + const Offset3d(0.3, 0, 0)));
      it.pointer.move(rayAt(it.surface, at + const Offset3d(0.4, 0, 0)));
      expect(starts, 1);
      expect(ends, 0);
      it.pointer.up();
      expect(ends, 1);
    });

    testWidgets('lays nothing out, on any frame of it', (tester) async {
      // The claim the node tier exists for, stated the way a drag makes it
      // hard: the caller rebuilds on every reported value, exactly as an
      // application does, and no box under the slider is laid out again.
      var value = 0.0;
      final it = await pumpComponent(
        tester,
        () => _Dragging(
          builder: (context, setState) => Slider3d(
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      );
      final gesture = oneOf<SliderGesture3d>(it.surface);
      final left =
          offsetInSurface(gesture) +
          Offset3d(gesture.padding, gesture.size.height / 2.0, 0.0);
      final track = it.panels[1];

      it.pointer.down(rayAt(it.surface, left));
      for (var step = 1; step <= 20; step++) {
        it.pointer.move(rayAt(it.surface, left + Offset3d(step * 0.06, 0, 0)));
        await tester.pump();
        expect(
          it.surface.needsFlush,
          isFalse,
          reason: 'step $step laid something out',
        );
        expect(identical(it.panels[1], track), isTrue);
      }
      it.pointer.up();
      await tester.pump();

      // Twenty moves of 0.06 from the track's left end, against a 1.24-unit
      // track: the finger stopped just short of the far end, which is the
      // arithmetic rather than a rounding.
      expect(value, closeTo(1.20 / 1.24, 1e-6));
      expect(componentShifts(it.surface)[0].scaleX, closeTo(value, 1e-9));
      expect(
        it.panels[2].size.width,
        closeTo(track.size.width, 1e-9),
        reason: 'the fill is still laid out full length; only its node moved',
      );
    });

    testWidgets('a press that never moves is a tap, and it jumps', (
      tester,
    ) async {
      final reported = <double>[];
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.0, onChanged: reported.add),
      );
      final gesture = oneOf<SliderGesture3d>(it.surface);
      it.pointer.down(rayAt(it.surface, centreOf(gesture)));
      expect(reported, isEmpty);
      it.pointer.up();
      expect(
        reported.single,
        closeTo(0.5, 1e-6),
        reason:
            'the member claims at the up, which is legal because what ends '
            'an arena is the sweep rather than the close',
      );
    });

    testWidgets('a disabled slider answers nothing at all', (tester) async {
      final it = await pumpComponent(tester, () => const Slider3d(value: 0.5));
      final gesture = oneOf<SliderGesture3d>(it.surface);
      expect(gesture.enabled, isFalse);
      it.pointer.down(rayAt(it.surface, centreOf(gesture)));
      it.pointer.move(
        rayAt(it.surface, centreOf(gesture) + const Offset3d(0.5, 0, 0)),
      );
      it.pointer.up();
      expect(gesture.isDragging, isFalse);
      expect(
        (it.panels[2].decoration as BoxDecoration3d).color,
        theme.colorScheme.disabledContent,
      );
      expect(
        (it.panels[1].decoration as BoxDecoration3d).color,
        theme.colorScheme.disabledContainer,
      );
      expect(
        (it.panels[3].decoration as BoxDecoration3d).color,
        theme.colorScheme.disabledContent,
      );
    });
  });

  group('the arena: a slider inside a scrolling list', () {
    testWidgets('a sideways drag moves the slider and not the list', (
      tester,
    ) async {
      // The claim `PointerSequence3d.addArenaMember` exists for. The drag
      // plan in the layout package named "a knob, a slider, a rotation
      // handle" as its customers; this is the first of them, and the case
      // that matters is the one where two things want the same finger.
      final reported = <double>[];
      final it = await _pumpInList(tester, (value) => reported.add(value));

      final gesture = oneOf<SliderGesture3d>(it.surface);
      final at = centreOf(gesture);
      it.pointer.down(rayAt(it.surface, at));
      it.pointer.move(rayAt(it.surface, at + const Offset3d(0.4, 0, 0)));
      it.pointer.move(rayAt(it.surface, at + const Offset3d(0.5, 0, 0)));
      it.pointer.up();

      expect(reported, isNotEmpty, reason: 'the slider took the pointer');
      expect(reported.last, greaterThan(0.5));
      expect(
        it.scroll.offset,
        0.0,
        reason: 'and the list under it never moved',
      );
    });

    testWidgets('a vertical drag scrolls the list and leaves the value', (
      tester,
    ) async {
      final reported = <double>[];
      final it = await _pumpInList(tester, (value) => reported.add(value));

      final gesture = oneOf<SliderGesture3d>(it.surface);
      final at = centreOf(gesture);
      it.pointer.down(rayAt(it.surface, at));
      it.pointer.move(rayAt(it.surface, at + const Offset3d(0, -0.4, 0)));
      it.pointer.move(rayAt(it.surface, at + const Offset3d(0, -0.8, 0)));
      it.pointer.up();

      expect(
        it.scroll.offset,
        greaterThan(0.0),
        reason: 'the list took the pointer',
      );
      expect(
        reported,
        isEmpty,
        reason:
            'and the slider was rejected without changing anything — which '
            'is what being a well-behaved arena member means',
      );
      expect(oneOf<SliderGesture3d>(it.surface).isDragging, isFalse);
    });

    testWidgets('a tap on a slider in a list still lands on the slider', (
      tester,
    ) async {
      // The other half of the arena. Neither member crosses its slop, so the
      // sweep at the up decides — and the slider's entry was taken during
      // the down dispatch, before the view armed its own.
      final reported = <double>[];
      final it = await _pumpInList(tester, (value) => reported.add(value));

      final gesture = oneOf<SliderGesture3d>(it.surface);
      it.pointer.down(rayAt(it.surface, centreOf(gesture)));
      it.pointer.up();

      expect(reported.single, closeTo(0.5, 1e-6));
      expect(it.scroll.offset, 0.0);
    });
  });

  group('what it announces', () {
    testWidgets('is a slider, with a name and a value', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.25, onChanged: (_) {}, semanticLabel: 'Volume'),
      );
      expect(it.semantics.properties.slider, isTrue);
      expect(it.semantics.properties.label, 'Volume');
      expect(it.semantics.properties.value, '25%');
      expect(it.semantics.properties.enabled, isTrue);
    });

    testWidgets('and a formatter says it in the range it was given', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Slider3d(
          value: 12.0,
          min: 0.0,
          max: 24.0,
          onChanged: (_) {},
          semanticLabel: 'Hour',
          semanticFormatter: (value) => '${value.round()} o\'clock',
        ),
      );
      expect(it.semantics.properties.value, "12 o'clock");
    });

    testWidgets('a disabled slider says so', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const Slider3d(value: 0.5, semanticLabel: 'Volume'),
      );
      expect(it.semantics.properties.enabled, isFalse);
    });
  });

  group('the target and the wash', () {
    testWidgets('is 48dp tall, which is the target as well as the wash', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.5, onChanged: (_) {}),
      );
      expect(it.target.size.height, closeTo(dp(48), 1e-9));
      expect(
        it.target.effectiveMinimumSize.height,
        closeTo(dp(TapTarget3d.materialMinimum), 1e-9),
      );
      expect(
        SliderStyle3d.defaultStateLayerSize,
        TapTarget3d.materialMinimum,
        reason:
            'a coincidence rather than a construction, and the one control '
            'here whose wash and whose reach agree',
      );
    });

    testWidgets('and a hover washes it in primary without a rebuild', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.5, onChanged: (_) {}),
      );
      final built = it.builds[0];
      it.pointer.hover(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      expect(it.panel.stateLayer.opacity, theme.stateLayer.hover);
      expect(it.panel.stateLayer.color, theme.colorScheme.primary);
      expect(it.builds[0], built);
      expect(it.surface.needsFlush, isFalse);
    });
  });
}

/// A slider inside a vertical list, and the handles a test needs on both.
class _InList {
  _InList(this.surface, this.scroll);

  final Layout3dSurface surface;
  final Scroll3dController scroll;

  Layout3dPointer? _pointer;

  Layout3dPointer get pointer => _pointer ??= Layout3dPointer(surface);
}

Future<_InList> _pumpInList(
  WidgetTester tester,
  void Function(double value) onChanged,
) async {
  final controller = Layout3dController();
  final scroll = Scroll3dController();
  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      size: const Size3d(4, 3, 0.5),
      controller: controller,
      child: SceneTheme3d(
        data: Theme3dData.light,
        child: SceneListView3d(
          controller: scroll,
          children: <Widget>[
            for (var index = 0; index < 6; index++)
              SceneSizedBox3d(
                height: 0.6,
                child: SceneCenter3d(
                  child: index == 0
                      ? Slider3d(value: 0.5, onChanged: onChanged)
                      : const SceneSizedBox3d(width: 1.0, height: 0.4),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  return _InList(controller.surface!, scroll);
}

/// A minimal stateful host, so a drag can be driven the way an application
/// drives one: `setState` per reported value.
class _Dragging extends StatefulWidget {
  const _Dragging({required this.builder});

  final Widget Function(BuildContext, void Function(void Function())) builder;

  @override
  State<_Dragging> createState() => _DraggingState();
}

class _DraggingState extends State<_Dragging> {
  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
}
