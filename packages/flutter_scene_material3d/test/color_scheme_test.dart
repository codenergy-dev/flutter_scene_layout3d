// ColorScheme3d: Material 3's colour roles, transcribed.
//
// Transcription is where errors hide, so the table is not checked against a
// second hand-written table — it is checked against Flutter's own Material 3
// baseline schemes, which are generated from the same Material token
// database. That makes this a drift alarm as well as a transcription check:
// if Flutter regenerates its tokens and a role moves, this fails and says
// which one.

import 'dart:ui' show Brightness, Color;

import 'package:flutter/material.dart' show ColorScheme, ThemeData;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every role of [scheme], by name, so two schemes can be compared field by
/// field with a failure that says which field.
Map<String, Color> rolesOf(ColorScheme3d scheme) => <String, Color>{
  'primary': scheme.primary,
  'onPrimary': scheme.onPrimary,
  'primaryContainer': scheme.primaryContainer,
  'onPrimaryContainer': scheme.onPrimaryContainer,
  'primaryFixed': scheme.primaryFixed,
  'primaryFixedDim': scheme.primaryFixedDim,
  'onPrimaryFixed': scheme.onPrimaryFixed,
  'onPrimaryFixedVariant': scheme.onPrimaryFixedVariant,
  'secondary': scheme.secondary,
  'onSecondary': scheme.onSecondary,
  'secondaryContainer': scheme.secondaryContainer,
  'onSecondaryContainer': scheme.onSecondaryContainer,
  'secondaryFixed': scheme.secondaryFixed,
  'secondaryFixedDim': scheme.secondaryFixedDim,
  'onSecondaryFixed': scheme.onSecondaryFixed,
  'onSecondaryFixedVariant': scheme.onSecondaryFixedVariant,
  'tertiary': scheme.tertiary,
  'onTertiary': scheme.onTertiary,
  'tertiaryContainer': scheme.tertiaryContainer,
  'onTertiaryContainer': scheme.onTertiaryContainer,
  'tertiaryFixed': scheme.tertiaryFixed,
  'tertiaryFixedDim': scheme.tertiaryFixedDim,
  'onTertiaryFixed': scheme.onTertiaryFixed,
  'onTertiaryFixedVariant': scheme.onTertiaryFixedVariant,
  'error': scheme.error,
  'onError': scheme.onError,
  'errorContainer': scheme.errorContainer,
  'onErrorContainer': scheme.onErrorContainer,
  'surface': scheme.surface,
  'onSurface': scheme.onSurface,
  'onSurfaceVariant': scheme.onSurfaceVariant,
  'surfaceDim': scheme.surfaceDim,
  'surfaceBright': scheme.surfaceBright,
  'surfaceContainerLowest': scheme.surfaceContainerLowest,
  'surfaceContainerLow': scheme.surfaceContainerLow,
  'surfaceContainer': scheme.surfaceContainer,
  'surfaceContainerHigh': scheme.surfaceContainerHigh,
  'surfaceContainerHighest': scheme.surfaceContainerHighest,
  'outline': scheme.outline,
  'outlineVariant': scheme.outlineVariant,
  'shadow': scheme.shadow,
  'scrim': scheme.scrim,
  'inverseSurface': scheme.inverseSurface,
  'onInverseSurface': scheme.onInverseSurface,
  'inversePrimary': scheme.inversePrimary,
  'surfaceTint': scheme.surfaceTint,
};

/// The same roles off Flutter's own scheme.
Map<String, Color> flutterRolesOf(ColorScheme scheme) => <String, Color>{
  'primary': scheme.primary,
  'onPrimary': scheme.onPrimary,
  'primaryContainer': scheme.primaryContainer,
  'onPrimaryContainer': scheme.onPrimaryContainer,
  'primaryFixed': scheme.primaryFixed,
  'primaryFixedDim': scheme.primaryFixedDim,
  'onPrimaryFixed': scheme.onPrimaryFixed,
  'onPrimaryFixedVariant': scheme.onPrimaryFixedVariant,
  'secondary': scheme.secondary,
  'onSecondary': scheme.onSecondary,
  'secondaryContainer': scheme.secondaryContainer,
  'onSecondaryContainer': scheme.onSecondaryContainer,
  'secondaryFixed': scheme.secondaryFixed,
  'secondaryFixedDim': scheme.secondaryFixedDim,
  'onSecondaryFixed': scheme.onSecondaryFixed,
  'onSecondaryFixedVariant': scheme.onSecondaryFixedVariant,
  'tertiary': scheme.tertiary,
  'onTertiary': scheme.onTertiary,
  'tertiaryContainer': scheme.tertiaryContainer,
  'onTertiaryContainer': scheme.onTertiaryContainer,
  'tertiaryFixed': scheme.tertiaryFixed,
  'tertiaryFixedDim': scheme.tertiaryFixedDim,
  'onTertiaryFixed': scheme.onTertiaryFixed,
  'onTertiaryFixedVariant': scheme.onTertiaryFixedVariant,
  'error': scheme.error,
  'onError': scheme.onError,
  'errorContainer': scheme.errorContainer,
  'onErrorContainer': scheme.onErrorContainer,
  'surface': scheme.surface,
  'onSurface': scheme.onSurface,
  'onSurfaceVariant': scheme.onSurfaceVariant,
  'surfaceDim': scheme.surfaceDim,
  'surfaceBright': scheme.surfaceBright,
  'surfaceContainerLowest': scheme.surfaceContainerLowest,
  'surfaceContainerLow': scheme.surfaceContainerLow,
  'surfaceContainer': scheme.surfaceContainer,
  'surfaceContainerHigh': scheme.surfaceContainerHigh,
  'surfaceContainerHighest': scheme.surfaceContainerHighest,
  'outline': scheme.outline,
  'outlineVariant': scheme.outlineVariant,
  'shadow': scheme.shadow,
  'scrim': scheme.scrim,
  'inverseSurface': scheme.inverseSurface,
  'onInverseSurface': scheme.onInverseSurface,
  'inversePrimary': scheme.inversePrimary,
  'surfaceTint': scheme.surfaceTint,
};

void main() {
  group('the baseline tables', () {
    test('light matches Material 3, role by role', () {
      final theirs = flutterRolesOf(
        ThemeData(brightness: Brightness.light).colorScheme,
      );
      final ours = rolesOf(ColorScheme3d.light);
      expect(ours.keys, theirs.keys);
      for (final role in ours.keys) {
        expect(ours[role], theirs[role], reason: 'light $role');
      }
      expect(ColorScheme3d.light.brightness, Brightness.light);
    });

    test('dark matches Material 3, role by role', () {
      final theirs = flutterRolesOf(
        ThemeData(brightness: Brightness.dark).colorScheme,
      );
      final ours = rolesOf(ColorScheme3d.dark);
      for (final role in ours.keys) {
        expect(ours[role], theirs[role], reason: 'dark $role');
      }
      expect(ColorScheme3d.dark.brightness, Brightness.dark);
    });

    test('the table is all forty-six roles', () {
      // A guard against a role being dropped from rolesOf and the two
      // comparisons above then agreeing about nothing.
      expect(rolesOf(ColorScheme3d.light), hasLength(46));
    });

    test('the fixed roles do not change with the brightness', () {
      // That is what "fixed" means: a container whose colour survives a
      // change of brightness, so a badge keeps its identity between the two.
      const light = ColorScheme3d.light;
      const dark = ColorScheme3d.dark;
      expect(light.primaryFixed, dark.primaryFixed);
      expect(light.primaryFixedDim, dark.primaryFixedDim);
      expect(light.onPrimaryFixed, dark.onPrimaryFixed);
      expect(light.onPrimaryFixedVariant, dark.onPrimaryFixedVariant);
      expect(light.secondaryFixed, dark.secondaryFixed);
      expect(light.onSecondaryFixedVariant, dark.onSecondaryFixedVariant);
      expect(light.tertiaryFixed, dark.tertiaryFixed);
      expect(light.onTertiaryFixedVariant, dark.onTertiaryFixedVariant);
    });

    test('surfaceTint is primary in both schemes', () {
      expect(ColorScheme3d.light.surfaceTint, ColorScheme3d.light.primary);
      expect(ColorScheme3d.dark.surfaceTint, ColorScheme3d.dark.primary);
    });

    test('a handful of roles, spelled out', () {
      // Literal spot checks, so the suite still states figures of its own if
      // the comparison above ever has to be dropped.
      expect(ColorScheme3d.light.primary, const Color(0xFF6750A4));
      expect(ColorScheme3d.light.surface, const Color(0xFFFEF7FF));
      expect(ColorScheme3d.light.onSurface, const Color(0xFF1D1B20));
      expect(ColorScheme3d.light.outline, const Color(0xFF79747E));
      expect(ColorScheme3d.light.error, const Color(0xFFB3261E));
      expect(ColorScheme3d.dark.primary, const Color(0xFFD0BCFF));
      expect(ColorScheme3d.dark.surface, const Color(0xFF141218));
      expect(
        ColorScheme3d.dark.surfaceContainerHighest,
        const Color(0xFF36343B),
      );
    });
  });

  group('disabled by substitution', () {
    test('is onSurface at the opacities Material states', () {
      expect(ColorScheme3d.disabledContentOpacity, 0.38);
      expect(ColorScheme3d.disabledContainerOpacity, 0.12);
      const scheme = ColorScheme3d.light;
      expect(scheme.disabledContent.a, closeTo(0.38, 1e-6));
      expect(scheme.disabledContainer.a, closeTo(0.12, 1e-6));
      // The hue is onSurface's; only the alpha differs.
      expect(scheme.disabledContent.r, scheme.onSurface.r);
      expect(scheme.disabledContent.g, scheme.onSurface.g);
      expect(scheme.disabledContent.b, scheme.onSurface.b);
    });
  });

  group('lerp', () {
    test('is the ends at t = 0 and t = 1', () {
      expect(
        ColorScheme3d.lerp(ColorScheme3d.light, ColorScheme3d.dark, 0.0),
        ColorScheme3d.light,
      );
      expect(
        ColorScheme3d.lerp(ColorScheme3d.light, ColorScheme3d.dark, 1.0),
        ColorScheme3d.dark,
      );
    });

    test('is between them in the middle, role by role', () {
      final middle = ColorScheme3d.lerp(
        ColorScheme3d.light,
        ColorScheme3d.dark,
        0.5,
      );
      final a = rolesOf(ColorScheme3d.light);
      final b = rolesOf(ColorScheme3d.dark);
      final m = rolesOf(middle);
      for (final role in m.keys) {
        expect(m[role], Color.lerp(a[role], b[role], 0.5), reason: role);
      }
      // Not simply one of the ends: the two schemes genuinely differ.
      expect(middle, isNot(ColorScheme3d.light));
      expect(middle, isNot(ColorScheme3d.dark));
    });

    test('snaps the brightness at the halfway point', () {
      // There is no colour between two brightnesses, and inventing a third
      // enum value would be worse than choosing one.
      Brightness at(double t) => ColorScheme3d.lerp(
        ColorScheme3d.light,
        ColorScheme3d.dark,
        t,
      ).brightness;
      expect(at(0.0), Brightness.light);
      expect(at(0.49), Brightness.light);
      expect(at(0.5), Brightness.dark);
      expect(at(1.0), Brightness.dark);
    });
  });

  group('value semantics', () {
    test('two identical schemes are equal and hash alike', () {
      final copy = ColorScheme3d.light.copyWith();
      expect(copy, ColorScheme3d.light);
      expect(copy.hashCode, ColorScheme3d.light.hashCode);
      expect(ColorScheme3d.light, isNot(ColorScheme3d.dark));
    });

    test('one changed role breaks equality', () {
      // Every field has to reach == and hashCode, and a 46-field comparison
      // is exactly where one gets forgotten.
      final ours = rolesOf(ColorScheme3d.light);
      for (final role in ours.keys) {
        final changed = _withRoleChanged(ColorScheme3d.light, role);
        expect(changed, isNot(ColorScheme3d.light), reason: role);
        expect(
          changed.hashCode,
          isNot(ColorScheme3d.light.hashCode),
          reason: role,
        );
      }
    });

    test('brightness alone breaks equality', () {
      expect(
        ColorScheme3d.light.copyWith(brightness: Brightness.dark),
        isNot(ColorScheme3d.light),
      );
    });
  });
}

/// [scheme] with exactly one role replaced by a colour nothing else uses.
ColorScheme3d _withRoleChanged(ColorScheme3d scheme, String role) {
  const odd = Color(0xFF010203);
  return switch (role) {
    'primary' => scheme.copyWith(primary: odd),
    'onPrimary' => scheme.copyWith(onPrimary: odd),
    'primaryContainer' => scheme.copyWith(primaryContainer: odd),
    'onPrimaryContainer' => scheme.copyWith(onPrimaryContainer: odd),
    'primaryFixed' => scheme.copyWith(primaryFixed: odd),
    'primaryFixedDim' => scheme.copyWith(primaryFixedDim: odd),
    'onPrimaryFixed' => scheme.copyWith(onPrimaryFixed: odd),
    'onPrimaryFixedVariant' => scheme.copyWith(onPrimaryFixedVariant: odd),
    'secondary' => scheme.copyWith(secondary: odd),
    'onSecondary' => scheme.copyWith(onSecondary: odd),
    'secondaryContainer' => scheme.copyWith(secondaryContainer: odd),
    'onSecondaryContainer' => scheme.copyWith(onSecondaryContainer: odd),
    'secondaryFixed' => scheme.copyWith(secondaryFixed: odd),
    'secondaryFixedDim' => scheme.copyWith(secondaryFixedDim: odd),
    'onSecondaryFixed' => scheme.copyWith(onSecondaryFixed: odd),
    'onSecondaryFixedVariant' => scheme.copyWith(onSecondaryFixedVariant: odd),
    'tertiary' => scheme.copyWith(tertiary: odd),
    'onTertiary' => scheme.copyWith(onTertiary: odd),
    'tertiaryContainer' => scheme.copyWith(tertiaryContainer: odd),
    'onTertiaryContainer' => scheme.copyWith(onTertiaryContainer: odd),
    'tertiaryFixed' => scheme.copyWith(tertiaryFixed: odd),
    'tertiaryFixedDim' => scheme.copyWith(tertiaryFixedDim: odd),
    'onTertiaryFixed' => scheme.copyWith(onTertiaryFixed: odd),
    'onTertiaryFixedVariant' => scheme.copyWith(onTertiaryFixedVariant: odd),
    'error' => scheme.copyWith(error: odd),
    'onError' => scheme.copyWith(onError: odd),
    'errorContainer' => scheme.copyWith(errorContainer: odd),
    'onErrorContainer' => scheme.copyWith(onErrorContainer: odd),
    'surface' => scheme.copyWith(surface: odd),
    'onSurface' => scheme.copyWith(onSurface: odd),
    'onSurfaceVariant' => scheme.copyWith(onSurfaceVariant: odd),
    'surfaceDim' => scheme.copyWith(surfaceDim: odd),
    'surfaceBright' => scheme.copyWith(surfaceBright: odd),
    'surfaceContainerLowest' => scheme.copyWith(surfaceContainerLowest: odd),
    'surfaceContainerLow' => scheme.copyWith(surfaceContainerLow: odd),
    'surfaceContainer' => scheme.copyWith(surfaceContainer: odd),
    'surfaceContainerHigh' => scheme.copyWith(surfaceContainerHigh: odd),
    'surfaceContainerHighest' => scheme.copyWith(surfaceContainerHighest: odd),
    'outline' => scheme.copyWith(outline: odd),
    'outlineVariant' => scheme.copyWith(outlineVariant: odd),
    'shadow' => scheme.copyWith(shadow: odd),
    'scrim' => scheme.copyWith(scrim: odd),
    'inverseSurface' => scheme.copyWith(inverseSurface: odd),
    'onInverseSurface' => scheme.copyWith(onInverseSurface: odd),
    'inversePrimary' => scheme.copyWith(inversePrimary: odd),
    'surfaceTint' => scheme.copyWith(surfaceTint: odd),
    _ => throw ArgumentError('unhandled role $role'),
  };
}
