// ColorScheme3d: Material 3's colour roles, transcribed.
//
// Transcription is where errors hide, so the table is not checked against a
// second hand-written table — it is checked against Flutter's own Material 3
// baseline schemes, which are generated from the same Material token
// database. That makes this a drift alarm as well as a transcription check:
// if Flutter regenerates its tokens and a role moves, this fails and says
// which one.

import 'dart:ui' show Brightness, Color;

import 'package:flutter/material.dart'
    show ColorScheme, DynamicSchemeVariant, ThemeData;
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

  group('a scheme from one colour', () {
    test('is Flutter\'s own generator, role by role, everywhere', () {
      // The strongest oracle available: both generators read the same
      // `MaterialDynamicColors` table, so this is an exact comparison rather
      // than a tolerance — and what it actually checks is the *mapping*,
      // which is this package's and is where a transcription error hides.
      // 9 variants x 2 brightnesses x 9 seeds, and nothing is allowed to
      // differ by one unit.
      for (final seed in _seeds) {
        for (final brightness in Brightness.values) {
          for (final variant in ColorSchemeVariant3d.values) {
            final ours = rolesOf(
              ColorScheme3d.fromSeed(
                seedColor: seed,
                brightness: brightness,
                variant: variant,
              ),
            );
            final theirs = flutterRolesOf(
              ColorScheme.fromSeed(
                seedColor: seed,
                brightness: brightness,
                dynamicSchemeVariant: _flutterVariant(variant),
              ),
            );
            final where =
                '${variant.name} ${brightness.name} '
                '#${seed.toARGB32().toRadixString(16)}';
            expect(ours.keys, theirs.keys, reason: where);
            for (final role in ours.keys) {
              expect(ours[role], theirs[role], reason: '$where $role');
            }
          }
        }
      }
    });

    test('follows Flutter through the contrast levels too', () {
      for (final contrast in <double>[-1.0, -0.5, 0.0, 0.5, 1.0]) {
        for (final brightness in Brightness.values) {
          final ours = rolesOf(
            ColorScheme3d.fromSeed(
              seedColor: _brand,
              brightness: brightness,
              contrastLevel: contrast,
            ),
          );
          final theirs = flutterRolesOf(
            ColorScheme.fromSeed(
              seedColor: _brand,
              brightness: brightness,
              contrastLevel: contrast,
            ),
          );
          for (final role in ours.keys) {
            expect(
              ours[role],
              theirs[role],
              reason: 'contrast $contrast ${brightness.name} $role',
            );
          }
        }
      }
    });

    test('raising the contrast actually changes the scheme', () {
      // Otherwise the comparison above would pass against a forwarded
      // argument that went nowhere.
      expect(
        ColorScheme3d.fromSeed(seedColor: _brand, contrastLevel: 1.0),
        isNot(ColorScheme3d.fromSeed(seedColor: _brand)),
      );
    });

    test('a contrast level outside Material\'s range is an assert', () {
      expect(
        () => ColorScheme3d.fromSeed(seedColor: _brand, contrastLevel: 1.5),
        throwsAssertionError,
      );
      expect(
        () => ColorScheme3d.fromSeed(seedColor: _brand, contrastLevel: -1.5),
        throwsAssertionError,
      );
    });

    test('tonalSpot is the default, and light is the default brightness', () {
      expect(
        ColorScheme3d.fromSeed(seedColor: _brand),
        ColorScheme3d.fromSeed(
          seedColor: _brand,
          brightness: Brightness.light,
          variant: ColorSchemeVariant3d.tonalSpot,
        ),
      );
    });

    test('brightness is the argument, not something inferred', () {
      expect(
        ColorScheme3d.fromSeed(
          seedColor: _brand,
          brightness: Brightness.dark,
        ).brightness,
        Brightness.dark,
      );
      expect(
        ColorScheme3d.fromSeed(seedColor: _brand).brightness,
        Brightness.light,
      );
    });

    test('the variants are not all the same scheme', () {
      // A switch that fell through to tonalSpot nine times would pass the
      // comparison above only if Flutter's did too, which it would not — but
      // this says it directly and fails faster.
      final seen = <ColorScheme3d>{};
      for (final variant in ColorSchemeVariant3d.values) {
        seen.add(ColorScheme3d.fromSeed(seedColor: _brand, variant: variant));
      }
      expect(seen, hasLength(ColorSchemeVariant3d.values.length));
    });

    test('monochrome is grey and tonalSpot is not', () {
      // One variant spelled out, so the suite states a property of its own
      // rather than only deferring to Flutter.
      final grey = ColorScheme3d.fromSeed(
        seedColor: _brand,
        variant: ColorSchemeVariant3d.monochrome,
      );
      expect(grey.primary.r, closeTo(grey.primary.g, 1 / 255));
      expect(grey.primary.g, closeTo(grey.primary.b, 1 / 255));
      final colourful = ColorScheme3d.fromSeed(seedColor: _brand);
      expect(colourful.primary.r, isNot(closeTo(colourful.primary.b, 1 / 255)));
    });

    test('a brand colour reaches a component, which is the whole promise', () {
      // What the catalogue plan promised when it put this out of its own
      // scope: "a generator can be added later without changing a single
      // component". This is that promise as a test rather than as a sentence
      // — a filled button's container is `primary`, whoever computed primary.
      final scheme = ColorScheme3d.fromSeed(seedColor: _brand);
      final resolved = ButtonStyle3d.of(
        Theme3dData(colorScheme: scheme),
        ButtonVariant3d.filled,
      ).resolve(const <Material3dState>{}, enabled: true);
      expect(resolved.container, scheme.primary);
      expect(resolved.content, scheme.onPrimary);
      // And it really is the brand's, not the baseline's.
      expect(resolved.container, isNot(ColorScheme3d.light.primary));
    });

    test('a role can be overridden with copyWith, which is why there are '
        'no overrides on the factory', () {
      const brandRed = Color(0xFFB00020);
      final scheme = ColorScheme3d.fromSeed(
        seedColor: _brand,
      ).copyWith(error: brandRed);
      expect(scheme.error, brandRed);
      expect(scheme.primary, ColorScheme3d.fromSeed(seedColor: _brand).primary);
    });
  });

  group('a generated scheme is not the baseline', () {
    // Stated out loud so that the next reader does not file it as a defect.
    // The map that asked for this generator proposed the opposite as its
    // oracle - "a generator seeded with Material's own baseline primary
    // should reproduce them" - and that premise is wrong for two separate
    // reasons, both by design.

    test('the seed is an input to the palettes, not the primary role', () {
      // tonalSpot clamps the primary palette's chroma to 36 and #6750A4's own
      // is 47.9, so the scheme it seeds is quieter than the seed.
      final seeded = ColorScheme3d.fromSeed(
        seedColor: ColorScheme3d.light.primary,
      );
      expect(ColorScheme3d.light.primary, const Color(0xFF6750A4));
      expect(seeded.primary, const Color(0xFF65558F));
      expect(seeded.primary, isNot(ColorScheme3d.light.primary));
    });

    test('and the error palette is the variant\'s, not the baseline\'s', () {
      final seeded = ColorScheme3d.fromSeed(
        seedColor: ColorScheme3d.light.primary,
      );
      expect(ColorScheme3d.light.error, const Color(0xFFB3261E));
      expect(seeded.error, const Color(0xFFBA1A1A));
    });

    test('twenty-seven of the forty-six differ, in both brightnesses', () {
      // The count itself is the alarm: if a Flutter upgrade moves the
      // generator or the baseline, this is what says so and by how much.
      int differences(Brightness brightness) {
        final baseline = rolesOf(
          brightness == Brightness.light
              ? ColorScheme3d.light
              : ColorScheme3d.dark,
        );
        final seeded = rolesOf(
          ColorScheme3d.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: brightness,
          ),
        );
        return seeded.keys.where((r) => seeded[r] != baseline[r]).length;
      }

      expect(differences(Brightness.light), 27);
      expect(differences(Brightness.dark), 27);
    });
  });

  group('the memo', () {
    test('hands back the same instance for the same arguments', () {
      expect(
        identical(
          ColorScheme3d.fromSeed(seedColor: _brand),
          ColorScheme3d.fromSeed(seedColor: _brand),
        ),
        isTrue,
      );
    });

    test('keys on every argument', () {
      final base = ColorScheme3d.fromSeed(seedColor: _brand);
      expect(
        identical(
          base,
          ColorScheme3d.fromSeed(
            seedColor: _brand,
            brightness: Brightness.dark,
          ),
        ),
        isFalse,
      );
      expect(
        identical(
          base,
          ColorScheme3d.fromSeed(
            seedColor: _brand,
            variant: ColorSchemeVariant3d.vibrant,
          ),
        ),
        isFalse,
      );
      expect(
        identical(
          base,
          ColorScheme3d.fromSeed(seedColor: _brand, contrastLevel: 0.5),
        ),
        isFalse,
      );
      expect(
        identical(
          base,
          ColorScheme3d.fromSeed(seedColor: const Color(0xFF123456)),
        ),
        isFalse,
      );
    });

    test('an evicted scheme comes back identical in value', () {
      // The cache holds 32; walking well past that evicts the first one, and
      // regenerating it has to produce the same forty-six roles. A memo that
      // changed an answer would be a defect nothing else here would catch.
      final first = ColorScheme3d.fromSeed(seedColor: const Color(0xFF010101));
      for (var i = 0; i < 64; i++) {
        ColorScheme3d.fromSeed(seedColor: Color(0xFF000000 | (i * 7919)));
      }
      final again = ColorScheme3d.fromSeed(seedColor: const Color(0xFF010101));
      expect(again, first);
      expect(identical(again, first), isFalse, reason: 'it really was evicted');
    });
  });
}

/// A brand colour that is nothing like Material's baseline: a deep teal.
const Color _brand = Color(0xFF00696E);

/// Seeds chosen for where a generator breaks rather than for how they look.
///
/// The three achromatic ones have no defined hue, and the three primaries sit
/// at a chroma no palette can hold, so between them they cover the clamping
/// and the fallbacks. The baseline primary is there because it is the one
/// seed anybody will try first.
const List<Color> _seeds = <Color>[
  Color(0xFF6750A4),
  _brand,
  Color(0xFF000000),
  Color(0xFFFFFFFF),
  Color(0xFF808080),
  Color(0xFFFF0000),
  Color(0xFF00FF00),
  Color(0xFF0000FF),
  Color(0xFFFFC107),
];

/// The Flutter variant this package's [ColorSchemeVariant3d] stands for.
///
/// Written out rather than indexed, so that a value added to either enum in a
/// different order is a compile error instead of a silent remapping.
DynamicSchemeVariant _flutterVariant(ColorSchemeVariant3d variant) =>
    switch (variant) {
      ColorSchemeVariant3d.tonalSpot => DynamicSchemeVariant.tonalSpot,
      ColorSchemeVariant3d.fidelity => DynamicSchemeVariant.fidelity,
      ColorSchemeVariant3d.monochrome => DynamicSchemeVariant.monochrome,
      ColorSchemeVariant3d.neutral => DynamicSchemeVariant.neutral,
      ColorSchemeVariant3d.vibrant => DynamicSchemeVariant.vibrant,
      ColorSchemeVariant3d.expressive => DynamicSchemeVariant.expressive,
      ColorSchemeVariant3d.content => DynamicSchemeVariant.content,
      ColorSchemeVariant3d.rainbow => DynamicSchemeVariant.rainbow,
      ColorSchemeVariant3d.fruitSalad => DynamicSchemeVariant.fruitSalad,
    };

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
