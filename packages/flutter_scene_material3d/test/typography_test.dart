// Typography3d: Material 3's type scale.
//
// The published figures are a size, a weight, a tracking and a line height in
// logical pixels. The first three are checked against Flutter's own generated
// M3 table; the line height is checked against the published dp figure, which
// is the one place these styles deliberately differ from Flutter's (see the
// class doc: Flutter's `height` multiples are rounded, these are exact).

import 'dart:ui' show Color, FontWeight, TextLeadingDistribution;

import 'package:flutter/material.dart' show TextTheme, Typography;
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fifteen styles by name.
Map<String, TextStyle> stylesOf(Typography3d type) => <String, TextStyle>{
  'displayLarge': type.displayLarge,
  'displayMedium': type.displayMedium,
  'displaySmall': type.displaySmall,
  'headlineLarge': type.headlineLarge,
  'headlineMedium': type.headlineMedium,
  'headlineSmall': type.headlineSmall,
  'titleLarge': type.titleLarge,
  'titleMedium': type.titleMedium,
  'titleSmall': type.titleSmall,
  'bodyLarge': type.bodyLarge,
  'bodyMedium': type.bodyMedium,
  'bodySmall': type.bodySmall,
  'labelLarge': type.labelLarge,
  'labelMedium': type.labelMedium,
  'labelSmall': type.labelSmall,
};

/// The same styles off Flutter's own M3 geometry.
Map<String, TextStyle> flutterStylesOf(TextTheme theme) => <String, TextStyle>{
  'displayLarge': theme.displayLarge!,
  'displayMedium': theme.displayMedium!,
  'displaySmall': theme.displaySmall!,
  'headlineLarge': theme.headlineLarge!,
  'headlineMedium': theme.headlineMedium!,
  'headlineSmall': theme.headlineSmall!,
  'titleLarge': theme.titleLarge!,
  'titleMedium': theme.titleMedium!,
  'titleSmall': theme.titleSmall!,
  'bodyLarge': theme.bodyLarge!,
  'bodyMedium': theme.bodyMedium!,
  'bodySmall': theme.bodySmall!,
  'labelLarge': theme.labelLarge!,
  'labelMedium': theme.labelMedium!,
  'labelSmall': theme.labelSmall!,
};

/// Material 3's published line heights, in logical pixels.
const Map<String, double> lineHeights = <String, double>{
  'displayLarge': 64.0,
  'displayMedium': 52.0,
  'displaySmall': 44.0,
  'headlineLarge': 40.0,
  'headlineMedium': 36.0,
  'headlineSmall': 32.0,
  'titleLarge': 28.0,
  'titleMedium': 24.0,
  'titleSmall': 20.0,
  'bodyLarge': 24.0,
  'bodyMedium': 20.0,
  'bodySmall': 16.0,
  'labelLarge': 20.0,
  'labelMedium': 16.0,
  'labelSmall': 16.0,
};

void main() {
  const baseline = Typography3d.baseline;
  final flutterScale = flutterStylesOf(Typography.englishLike2021);

  group('the baseline scale', () {
    test('is fifteen styles', () {
      expect(stylesOf(baseline), hasLength(15));
    });

    test('sizes, weights and tracking match Material 3', () {
      final ours = stylesOf(baseline);
      for (final name in ours.keys) {
        final mine = ours[name]!;
        final theirs = flutterScale[name]!;
        expect(mine.fontSize, theirs.fontSize, reason: '$name fontSize');
        expect(mine.fontWeight, theirs.fontWeight, reason: '$name fontWeight');
        expect(
          mine.letterSpacing,
          theirs.letterSpacing,
          reason: '$name letterSpacing',
        );
      }
    });

    test('line heights are the published dp figures, exactly', () {
      // Material publishes a line height in logical pixels; TextStyle.height
      // is a multiple of the font size. These carry the exact ratio, so
      // height × fontSize is the published figure with no rounding.
      final ours = stylesOf(baseline);
      for (final name in ours.keys) {
        final style = ours[name]!;
        expect(
          style.height! * style.fontSize!,
          closeTo(lineHeights[name]!, 1e-9),
          reason: '$name line height',
        );
      }
    });

    test('and are within half a percent of Flutter\'s rounded multiples', () {
      // The deliberate divergence, pinned so that it stays small and stays
      // deliberate. Flutter's generated table rounds 64 / 57 to 1.12.
      final ours = stylesOf(baseline);
      for (final name in ours.keys) {
        expect(
          ours[name]!.height!,
          closeTo(flutterScale[name]!.height!, 0.005),
          reason: '$name height',
        );
      }
      // Not identical, though: displayLarge is where the rounding shows.
      expect(
        baseline.displayLarge.height,
        isNot(flutterScale['displayLarge']!.height),
      );
    });

    test('the five label and title styles are medium weight', () {
      // The one place the scale is not w400, and the reason a button's label
      // reads as a control rather than as copy.
      expect(baseline.titleMedium.fontWeight, FontWeight.w500);
      expect(baseline.titleSmall.fontWeight, FontWeight.w500);
      expect(baseline.labelLarge.fontWeight, FontWeight.w500);
      expect(baseline.labelMedium.fontWeight, FontWeight.w500);
      expect(baseline.labelSmall.fontWeight, FontWeight.w500);
      expect(baseline.titleLarge.fontWeight, FontWeight.w400);
      expect(baseline.bodyLarge.fontWeight, FontWeight.w400);
    });

    test('leading is distributed evenly', () {
      // Material's line height is the whole line box with the extra leading
      // split above and below, which is what `even` means and what Flutter's
      // default `proportional` does not do.
      for (final style in stylesOf(baseline).values) {
        expect(style.leadingDistribution, TextLeadingDistribution.even);
      }
    });

    test('carries no colour and no font family', () {
      // A colour comes from the role the component is drawing in, not from
      // the type scale, and a style carrying one would have to be re-derived
      // every time the scheme changed.
      for (final style in stylesOf(baseline).values) {
        expect(style.color, isNull);
        expect(style.fontFamily, isNull);
      }
    });
  });

  group('apply', () {
    test('puts one colour on every style and changes nothing else', () {
      const ink = Color(0xFF102030);
      final applied = baseline.apply(color: ink);
      final before = stylesOf(baseline);
      final after = stylesOf(applied);
      for (final name in after.keys) {
        expect(after[name]!.color, ink, reason: name);
        expect(after[name]!.fontSize, before[name]!.fontSize, reason: name);
        expect(after[name]!.height, before[name]!.height, reason: name);
      }
    });

    test('leaves the original alone', () {
      baseline.apply(color: const Color(0xFF102030));
      expect(baseline.bodyMedium.color, isNull);
    });
  });

  group('lerp', () {
    // A scale that states the same properties as the baseline, differing
    // only in one number. See the last test in this group for why that
    // matters.
    final small = baseline.copyWith(
      bodyMedium: baseline.bodyMedium.copyWith(fontSize: 10.0),
    );

    test('is the ends at t = 0 and t = 1', () {
      expect(Typography3d.lerp(baseline, small, 0.0), baseline);
      expect(Typography3d.lerp(baseline, small, 1.0), small);
    });

    test('is halfway in the middle', () {
      final middle = Typography3d.lerp(baseline, small, 0.5);
      expect(middle.bodyMedium.fontSize, closeTo(12.0, 1e-9));
      // Untouched styles interpolate to themselves.
      expect(middle.labelLarge.fontSize, baseline.labelLarge.fontSize);
      expect(middle, isNot(baseline));
      expect(middle, isNot(small));
    });

    test('fills in what the other end leaves unstated', () {
      // TextStyle.lerp is a merge as well as an interpolation: where one end
      // states a property and the other does not, the stated value is
      // carried across rather than dropped. So a scale built from bare
      // TextStyles does not come back unchanged at t = 1 — it comes back
      // with the baseline's weight and tracking filled in. That is Flutter's
      // behaviour, it is usually what you want, and it is a surprise if you
      // expected an interpolation to be the identity at its own end.
      final bare = baseline.copyWith(
        bodyMedium: const TextStyle(fontSize: 10.0),
      );
      final end = Typography3d.lerp(baseline, bare, 1.0);
      expect(end.bodyMedium.fontSize, 10.0);
      expect(end.bodyMedium.fontWeight, baseline.bodyMedium.fontWeight);
      expect(end, isNot(bare));
    });
  });

  group('value semantics', () {
    test('two identical scales are equal and hash alike', () {
      expect(baseline.copyWith(), baseline);
      expect(baseline.copyWith().hashCode, baseline.hashCode);
    });

    test('one changed style breaks equality', () {
      final ours = stylesOf(baseline);
      for (final name in ours.keys) {
        final changed = _withStyleChanged(baseline, name);
        expect(changed, isNot(baseline), reason: name);
        expect(changed.hashCode, isNot(baseline.hashCode), reason: name);
      }
    });
  });
}

/// [type] with exactly one style replaced.
Typography3d _withStyleChanged(Typography3d type, String name) {
  const odd = TextStyle(fontSize: 3.0);
  return switch (name) {
    'displayLarge' => type.copyWith(displayLarge: odd),
    'displayMedium' => type.copyWith(displayMedium: odd),
    'displaySmall' => type.copyWith(displaySmall: odd),
    'headlineLarge' => type.copyWith(headlineLarge: odd),
    'headlineMedium' => type.copyWith(headlineMedium: odd),
    'headlineSmall' => type.copyWith(headlineSmall: odd),
    'titleLarge' => type.copyWith(titleLarge: odd),
    'titleMedium' => type.copyWith(titleMedium: odd),
    'titleSmall' => type.copyWith(titleSmall: odd),
    'bodyLarge' => type.copyWith(bodyLarge: odd),
    'bodyMedium' => type.copyWith(bodyMedium: odd),
    'bodySmall' => type.copyWith(bodySmall: odd),
    'labelLarge' => type.copyWith(labelLarge: odd),
    'labelMedium' => type.copyWith(labelMedium: odd),
    'labelSmall' => type.copyWith(labelSmall: odd),
    _ => throw ArgumentError('unhandled style $name'),
  };
}
