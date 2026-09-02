// Theme3dData: the five token families and a density, as one value.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        BorderRadius3d,
        Constraints3d,
        Layout3dMetrics,
        Size3d,
        VisualDensity3d;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the baselines', () {
    test('light is every family at its Material 3 default', () {
      const theme = Theme3dData.light;
      expect(theme.colorScheme, ColorScheme3d.light);
      expect(theme.typography, Typography3d.baseline);
      expect(theme.shape, ShapeScale3d.baseline);
      expect(theme.elevation, Elevation3d.baseline);
      expect(theme.thickness, Thickness3d.baseline);
      expect(theme.density, VisualDensity3d.standard);
    });

    test('dark changes the colours and nothing else', () {
      // Material's type, shape and elevation scales are the same in both
      // brightnesses, and so is the thickness scale invented here: a card is
      // not deeper at night.
      const light = Theme3dData.light;
      const dark = Theme3dData.dark;
      expect(dark.colorScheme, ColorScheme3d.dark);
      expect(dark.typography, light.typography);
      expect(dark.shape, light.shape);
      expect(dark.elevation, light.elevation);
      expect(dark.thickness, light.thickness);
      expect(dark.density, light.density);
      expect(dark, isNot(light));
    });

    test('the default constructor is the light theme', () {
      expect(const Theme3dData(), Theme3dData.light);
    });

    test('both are const, so a token survives the painter cache', () {
      // Decoration3dPainterCache keys panels on their cache key; a component
      // that recomputed its colours every frame would defeat it silently.
      expect(identical(const Theme3dData(), const Theme3dData()), isTrue);
    });
  });

  group('the slot', () {
    test('is named for the library that owns it', () {
      // A Layout3dSlot is its type and its name, never its identity, so two
      // libraries choosing the same name for the same type would collide.
      expect(Theme3dData.slot.name, 'material3d.theme');
      expect(Theme3dData.slot.toString(), contains('Theme3dData'));
    });
  });

  group('density', () {
    test('the theme\'s wins over the surface metrics\'', () {
      // Layout3dMetrics carries a density too, and applies it in
      // effectiveConstraints. They can disagree; the theme is the authority,
      // and this is where that is decided rather than left to whoever calls
      // first.
      const metrics = Layout3dMetrics(density: VisualDensity3d.standard);
      const theme = Theme3dData(density: VisualDensity3d.comfortable);
      final constraints = Constraints3d.loose(const Size3d(10, 10, 10));

      // The metrics on its own does nothing: its density is standard.
      expect(metrics.effectiveConstraints(constraints), constraints);

      // The theme's comfortable density pulls the minimums in by one unit of
      // density on each in-plane axis — 4 logical pixels, 0.04 units at the
      // default rate — and a minimum never goes below zero.
      final adjusted = theme.effectiveConstraints(constraints, metrics);
      expect(adjusted.minWidth, 0.0);
      expect(adjusted.minHeight, 0.0);

      // Against a constraint with room to shrink, the adjustment shows.
      const tight = Constraints3d(
        minWidth: 1.0,
        maxWidth: 2.0,
        minHeight: 1.0,
        maxHeight: 2.0,
      );
      final tighter = theme.effectiveConstraints(tight, metrics);
      expect(tighter.minWidth, closeTo(1.0 - 0.04, 1e-9));
      expect(tighter.minHeight, closeTo(1.0 - 0.04, 1e-9));
      expect(tighter.maxWidth, 2.0);
    });

    test('uses the metrics\' own arithmetic, so there is one conversion', () {
      const metrics = Layout3dMetrics(unitsPerLogicalPixel: 0.02);
      const theme = Theme3dData(density: VisualDensity3d.compact);
      const constraints = Constraints3d(
        minWidth: 1.0,
        maxWidth: 2.0,
        minHeight: 1.0,
        maxHeight: 2.0,
      );
      expect(
        theme.effectiveConstraints(constraints, metrics),
        metrics
            .copyWith(density: VisualDensity3d.compact)
            .effectiveConstraints(constraints),
      );
    });
  });

  group('lerp', () {
    test('is the ends at t = 0 and t = 1', () {
      expect(
        Theme3dData.lerp(Theme3dData.light, Theme3dData.dark, 0.0),
        Theme3dData.light,
      );
      expect(
        Theme3dData.lerp(Theme3dData.light, Theme3dData.dark, 1.0),
        Theme3dData.dark,
      );
    });

    test('interpolates every family in the middle', () {
      final middle = Theme3dData.lerp(
        Theme3dData.light,
        const Theme3dData(
          colorScheme: ColorScheme3d.dark,
          shape: ShapeScale3d(medium: BorderRadius3d.zero),
          elevation: Elevation3d(level2: 0.0),
          thickness: Thickness3d(raised: 0.0),
          density: VisualDensity3d.compact,
        ),
        0.5,
      );
      expect(
        middle.colorScheme,
        ColorScheme3d.lerp(ColorScheme3d.light, ColorScheme3d.dark, 0.5),
      );
      expect(middle.shape.medium.topLeft, closeTo(6.0, 1e-9));
      expect(middle.elevation.level2, closeTo(1.5, 1e-9));
      expect(middle.thickness.raised, closeTo(2.0, 1e-9));
      expect(middle.density.horizontal, closeTo(-1.0, 1e-9));
      expect(middle, isNot(Theme3dData.light));
    });

    test('a whole-theme tween animates it', () {
      final tween = Theme3dDataTween(
        begin: Theme3dData.light,
        end: Theme3dData.dark,
      );
      expect(tween.transform(0.0), Theme3dData.light);
      expect(tween.transform(1.0), Theme3dData.dark);
      expect(
        tween.transform(0.5).colorScheme.surface,
        isNot(ColorScheme3d.light.surface),
      );
    });
  });

  group('value semantics', () {
    test('two identical themes are equal and hash alike', () {
      expect(Theme3dData.light.copyWith(), Theme3dData.light);
      expect(Theme3dData.light.copyWith().hashCode, Theme3dData.light.hashCode);
    });

    test('every family reaches equality', () {
      const theme = Theme3dData.light;
      for (final one in <Theme3dData>[
        theme.copyWith(colorScheme: ColorScheme3d.dark),
        theme.copyWith(
          typography: Typography3d.baseline.copyWith(
            bodyMedium: Typography3d.baseline.bodySmall,
          ),
        ),
        theme.copyWith(
          shape: ShapeScale3d.baseline.copyWith(medium: BorderRadius3d.zero),
        ),
        theme.copyWith(elevation: Elevation3d.baseline.copyWith(level1: 2.0)),
        theme.copyWith(thickness: Thickness3d.baseline.copyWith(raised: 5.0)),
        theme.copyWith(density: VisualDensity3d.compact),
      ]) {
        expect(one, isNot(theme));
        expect(one.hashCode, isNot(theme.hashCode));
      }
    });
  });
}
