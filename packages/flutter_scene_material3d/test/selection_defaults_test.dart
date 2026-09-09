// The drift alarm for the selection controls.
//
// The standard phases 3 to 6 set has three grades, and this phase hits all
// three again:
//
//  * **Read from Flutter.** `Checkbox.width`, `kRadialReactionRadius`,
//    `kMinInteractiveDimension`, `RoundSliderThumbShape.enabledThumbRadius`
//    and `RoundSliderOverlayShape.overlayRadius` are all public constants, so
//    five of this phase's figures are read rather than copied and this file
//    fails the day Flutter changes one.
//  * **Read from a laid-out widget.** `_SwitchConfigM3` and `_SliderDefaults`
//    are private as data and public as a fact about a rendered control, so
//    the switch's track width and the slider's height are measured off real
//    ones with `tester.getSize`, exactly as phase 4 measured a `ListTile`.
//  * **Transcribed, and said out loud.** Everything else — a radio's two
//    diameters, a 2dp outline, a 2dp corner, a slider's 4dp track — has no
//    accessor at all. Those tests state the figure *and* say it is a
//    transcription, so the next reader meets the fact here rather than
//    against a ruler.
//
// The colours are a fourth case and are checked elsewhere: every token below
// is a `ColorScheme3d` *role*, and `test/color_scheme_test.dart` already
// checks the roles' values against Flutter's own generated table. What this
// file pins is which role each token takes, which is what
// `_CheckboxDefaultsM3` and its siblings actually say.

import 'package:flutter/material.dart' as material;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show TapTarget3d;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;
  final scheme = theme.colorScheme;
  final checkbox = CheckboxStyle3d.of(theme);
  final radio = RadioStyle3d.of(theme);
  final toggle = SwitchStyle3d.of(theme);
  final slider = SliderStyle3d.of(theme);

  group('figures read straight from Flutter', () {
    test('a checkbox is Checkbox.width across', () {
      expect(checkbox.size, material.Checkbox.width);
      expect(CheckboxStyle3d.defaultSize, material.Checkbox.width);
    });

    test('and its wash is the radial reaction, which is 40dp', () {
      expect(
        checkbox.stateLayerSize,
        material.kRadialReactionRadius * 2.0,
        reason: "Material's state layer for a checkbox, a radio and a switch",
      );
      expect(radio.stateLayerSize, material.kRadialReactionRadius * 2.0);
    });

    test('the target is the minimum interactive dimension', () {
      expect(TapTarget3d.materialMinimum, material.kMinInteractiveDimension);
      expect(
        checkbox.stateLayerSize,
        lessThan(TapTarget3d.materialMinimum),
        reason: 'which is why the reach is load-bearing on a checkbox',
      );
    });

    test("a slider's thumb is the round thumb shape's diameter", () {
      expect(
        slider.thumbSize,
        const material.RoundSliderThumbShape().enabledThumbRadius * 2.0,
      );
    });

    test('and its wash is the round overlay shape, which is also 48dp', () {
      expect(
        slider.stateLayerSize,
        const material.RoundSliderOverlayShape().overlayRadius * 2.0,
      );
      expect(
        slider.stateLayerSize,
        TapTarget3d.materialMinimum,
        reason:
            'a coincidence rather than a construction: the only control here '
            'whose wash and whose reach are the same figure',
      );
    });
  });

  group('figures measured off a real Flutter control', () {
    testWidgets('a switch is 52dp of track inside 4dp of padding', (
      tester,
    ) async {
      // `_SwitchConfigM3.switchWidth` is private as data. What is not private
      // is what a real switch lays out at, and `_SwitchDefaultsM3.padding` is
      // 4dp on each side — the one transcription inside this measurement, and
      // the reason it is a subtraction rather than a reading.
      await tester.pumpWidget(
        material.MaterialApp(
          home: material.Scaffold(
            body: material.Switch(value: true, onChanged: (_) {}),
          ),
        ),
      );
      final size = tester.getSize(find.byType(material.Switch));
      expect(size.width - 8.0, toggle.trackWidth);
      expect(
        size.height,
        TapTarget3d.materialMinimum,
        reason: "a real switch lays out at its target, not at its track's 32dp",
      );
    });

    testWidgets('a slider is 48dp tall', (tester) async {
      await tester.pumpWidget(
        const material.MaterialApp(
          home: material.Scaffold(
            body: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              children: <material.Widget>[
                material.SizedBox(
                  width: 300,
                  child: material.Slider(value: 0.5, onChanged: null),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(material.Slider)).height,
        slider.stateLayerSize,
      );
    });

    testWidgets('and a checkbox and a radio both lay out at 48dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        material.MaterialApp(
          home: material.Scaffold(
            body: material.Column(
              children: <material.Widget>[
                material.Checkbox(value: true, onChanged: (_) {}),
                // `Radio.groupValue` and `Radio.onChanged` were deprecated
                // after 3.32 in favour of a `RadioGroup` ancestor, which is
                // why this reads oddly for a size measurement. The
                // divergence is recorded in the plan: `Radio3d` keeps the
                // older spelling, because a `RadioGroup3d` is an inherited
                // widget plus a registry and this catalogue's radio is a
                // leaf that states its own semantics.
                material.RadioGroup<int>(
                  groupValue: 1,
                  onChanged: (_) {},
                  child: const material.Radio<int>(value: 1),
                ),
              ],
            ),
          ),
        ),
      );
      // Flutter's control *is* its target, because a 2D framework can grow a
      // box without moving its neighbours apart in three dimensions. Here the
      // reach is invisible to layout instead, which is `TapTarget3d`'s whole
      // design — so the extent is 40dp and the target is 48.
      expect(
        tester.getSize(find.byType(material.Checkbox)).width,
        TapTarget3d.materialMinimum,
      );
      expect(
        tester.getSize(find.byType(material.Radio<int>)).width,
        TapTarget3d.materialMinimum,
      );
    });
  });

  group('figures transcribed, and this test says so', () {
    test("a radio's two diameters", () {
      // Flutter's `_kOuterRadius` (8.0) and `_kInnerRadius` (4.5), both
      // private constants in `radio.dart` with no accessor of any kind.
      expect(radio.outerSize, 16.0);
      expect(radio.innerSize, 9.0);
    });

    test('the 2dp outlines and the 2dp checkbox corner', () {
      // `_CheckboxDefaultsM3.side` is a 2dp `BorderSide`, its `shape` a 2dp
      // `RoundedRectangleBorder`, and `_SwitchDefaultsM3.trackOutlineWidth`
      // is 2dp. All three are private.
      expect(checkbox.outlineWidth, 2.0);
      expect(radio.outlineWidth, 2.0);
      expect(toggle.trackOutlineWidth, 2.0);
      expect(checkbox.shape.topLeft, 2.0);
    });

    test("a switch's track height and thumb", () {
      // `_SwitchConfigM3.trackHeight` (32), `.activeThumbRadius` (12).
      expect(toggle.trackHeight, 32.0);
      expect(
        toggle.thumbSize,
        24.0,
        reason:
            "Material's *selected* thumb. The unselected one is 16dp and the "
            'difference between them is an animation, which this package has '
            'no motion tokens for — so the thumb is one size and what moves '
            'is where it is',
      );
      expect(toggle.thumbMargin, 4.0);
      expect(toggle.travel, 20.0);
    });

    test("a slider's track height and narrowest width", () {
      // `_SliderDefaultsM3Year2023(context) : super(trackHeight: 4.0)` and
      // `_RenderSlider._minPreferredTrackWidth`, both private.
      //
      // Flutter also ships a 2024 M3 slider with a 16dp track and a 4 by 44
      // bar handle. This package takes the round-thumb one deliberately: a
      // thumb standing proud of a track is what this catalogue's third
      // dimension is for, and a handle inset into a track of its own height
      // is a picture a 3D scene has nothing to add to.
      expect(slider.trackHeight, 4.0);
      expect(slider.minimumTrackWidth, 144.0);
    });
  });

  group('which colour role each token takes', () {
    test('a checkbox, out of _CheckboxDefaultsM3', () {
      expect(checkbox.container.a, 0.0);
      expect(checkbox.selectedContainer, scheme.primary);
      expect(checkbox.mark, scheme.onPrimary);
      expect(checkbox.outline, scheme.onSurfaceVariant);
      expect(checkbox.disabledOutline, scheme.disabledContent);
      expect(
        checkbox.disabledSelectedContainer,
        scheme.disabledContent,
        reason: "Flutter's `onSurface` at 38%, which is `disabledContent`",
      );
      expect(
        checkbox.disabledMark,
        scheme.surface,
        reason: 'a hole in the fill rather than a mark on it',
      );
    });

    test('a radio, out of _RadioDefaultsM3', () {
      expect(radio.outline, scheme.onSurfaceVariant);
      expect(radio.selectedOutline, scheme.primary);
      expect(radio.dot, scheme.primary);
      expect(radio.disabledOutline, scheme.disabledContent);
      expect(radio.disabledDot, scheme.disabledContent);
    });

    test('a switch, out of _SwitchDefaultsM3', () {
      expect(toggle.track, scheme.surfaceContainerHighest);
      expect(toggle.selectedTrack, scheme.primary);
      expect(toggle.trackOutline, scheme.outline);
      expect(
        toggle.selectedTrackOutline,
        isNull,
        reason: 'transparent in Flutter, and no border at all here',
      );
      expect(toggle.thumb, scheme.outline);
      expect(toggle.selectedThumb, scheme.onPrimary);
      expect(toggle.disabledSelectedThumb, scheme.surface);
      expect(toggle.disabledSelectedTrack, scheme.disabledContainer);
      expect(
        toggle.disabledTrack.a,
        ColorScheme3d.disabledContainerOpacity,
        reason: "Flutter's `surfaceContainerHighest` at 12%",
      );
    });

    test('a slider, out of _SliderDefaultsM3Year2023', () {
      expect(slider.activeTrack, scheme.primary);
      expect(slider.inactiveTrack, scheme.surfaceContainerHighest);
      expect(slider.thumb, scheme.primary);
      expect(slider.disabledActiveTrack, scheme.disabledContent);
      expect(slider.disabledInactiveTrack, scheme.disabledContainer);
      expect(
        slider.wash,
        scheme.primary,
        reason: "Flutter's overlay for a slider is primary in every state",
      );
    });

    test('and every wash is the role Material names for it', () {
      // The one rule that runs across all four: a control's state layer takes
      // `primary` when it is on and `onSurface` when it is off, which is what
      // makes a hover over a ticked box read as part of the tick.
      for (final pair in <(dynamic, dynamic)>[
        (checkbox.wash, checkbox.selectedWash),
        (radio.wash, radio.selectedWash),
        (toggle.wash, toggle.selectedWash),
      ]) {
        expect(pair.$1, scheme.onSurface);
        expect(pair.$2, scheme.primary);
      }
    });
  });

  group('the depth steps, which Material has nothing to say about', () {
    test('every one of them comes from the thickness scale', () {
      // The figure no specification publishes, derived in one place rather
      // than typed into four components. `Thickness3d.stepOver` is twice the
      // mean of the two thicknesses, which is what `MenuStyle3d.itemDepthStep`
      // had already chosen by hand for two equal slabs.
      expect(
        checkbox.depthStep,
        Thickness3d.stepOver(theme.thickness.thin, theme.thickness.thin),
      );
      expect(
        radio.depthStep,
        Thickness3d.stepOver(theme.thickness.thin, theme.thickness.thin),
      );
      expect(
        toggle.depthStep,
        Thickness3d.stepOver(theme.thickness.thin, theme.thickness.standard),
      );
      expect(
        slider.depthStep,
        Thickness3d.stepOver(theme.thickness.thin, theme.thickness.standard),
      );
    });

    test('and every one of them genuinely separates its pair', () {
      expect(
        theme.thickness.separates(
          checkbox.thickness,
          checkbox.thickness,
          step: checkbox.depthStep,
        ),
        isTrue,
      );
      expect(
        theme.thickness.separates(
          toggle.trackThickness,
          toggle.thumbThickness,
          step: toggle.depthStep,
        ),
        isTrue,
      );
      expect(
        theme.thickness.separates(
          slider.trackThickness,
          slider.thumbThickness,
          step: slider.depthStep,
        ),
        isTrue,
      );
    });

    test(
      'a step at exactly the mean is not enough, and the scale is strict',
      () {
        // The failure this arithmetic exists to prevent: two slabs whose
        // touching faces are coplanar z-fight, and equal is coplanar.
        expect(
          theme.thickness.separates(
            theme.thickness.thin,
            theme.thickness.standard,
            step: Thickness3d.minimumStepFor(
              theme.thickness.thin,
              theme.thickness.standard,
            ),
          ),
          isFalse,
        );
      },
    );
  });
}
