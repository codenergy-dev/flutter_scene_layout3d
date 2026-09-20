import 'dart:ui' show Brightness, Color;

import 'package:material_color_utilities/material_color_utilities.dart';

/// How `ColorScheme3d.fromSeed` turns one colour into forty-six.
///
/// A seed is not a role. It is the input to a set of *tonal palettes* — a
/// primary, a secondary, a tertiary, two neutrals and an error — and a
/// variant is the rule that derives those palettes from it. The rule decides
/// how much of the seed's own chroma survives, whether the secondary and
/// tertiary hues are relatives of the seed or deliberate strangers, and
/// whether the seed's hue appears in the result at all. Once the palettes
/// exist, every role is a tone lookup and the variant no longer matters.
///
/// The names are Flutter's `DynamicSchemeVariant`, one for one, for the same
/// reason the role names are Material's: a figure written against Flutter's
/// Material transfers here unchanged. It is re-declared rather than imported
/// because `DynamicSchemeVariant` lives in `package:flutter/material.dart`,
/// which this package's `lib/` does not import.
///
/// The parameter that takes one is spelled `variant`, as
/// `ButtonVariant3d` and `CardVariant3d` and the rest of the catalogue spell
/// it, rather than `dynamicSchemeVariant`.
enum ColorSchemeVariant3d {
  /// Material's default, and the one every baseline figure assumes.
  ///
  /// Pastel palettes at a low chroma: the primary palette is clamped to a
  /// chroma of 36 whatever the seed's own is, so a vivid seed produces a
  /// quieter scheme. That clamp is why a scheme seeded with Material's own
  /// `#6750A4` does not come back with `#6750A4` as its primary.
  tonalSpot,

  /// The palettes match the seed, even when the seed is very bright.
  ///
  /// The counterpart to [tonalSpot]'s clamp: use it when a brand colour has
  /// to survive intact rather than be made polite.
  fidelity,

  /// Greyscale. No chroma anywhere, including the seed's.
  monochrome,

  /// Close to greyscale: a hint of the seed's chroma and no more.
  neutral,

  /// High chroma. The primary palette is as vivid as the seed allows.
  ///
  /// Unlike [fidelity], the roles keep their usual tones rather than moving
  /// to match the palette, so contrast is preserved and the vividness is
  /// spent on the palette alone.
  vibrant,

  /// Medium chroma, and the primary hue is deliberately *not* the seed's.
  expressive,

  /// Almost [fidelity]: the tones follow the seed too, and
  /// `ColorScheme3d.primaryContainer` is the seed itself, adjusted only as
  /// far as contrast with the surfaces requires.
  content,

  /// A playful scheme in which the seed's hue does not appear.
  rainbow,

  /// A playful scheme in which the seed's hue does not appear, with a
  /// stronger neutral.
  fruitSalad,
}

/// The `material_color_utilities` scheme [variant] names, seeded with
/// [seedColor] and resolved for [brightness] at [contrastLevel].
///
/// This is the whole of the colour library's surface that this package
/// touches for generation; the mapping from the result onto
/// `ColorScheme3d`'s forty-six roles is in `color_scheme.dart`. Keeping the
/// import in one file is also what keeps that file free of a cycle: nothing
/// here knows `ColorScheme3d` exists.
DynamicScheme dynamicSchemeFrom3d({
  required Color seedColor,
  required Brightness brightness,
  required ColorSchemeVariant3d variant,
  required double contrastLevel,
}) {
  final source = Hct.fromInt(seedColor.toARGB32());
  final isDark = brightness == Brightness.dark;
  return switch (variant) {
    ColorSchemeVariant3d.tonalSpot => SchemeTonalSpot(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    ColorSchemeVariant3d.fidelity => SchemeFidelity(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    ColorSchemeVariant3d.monochrome => SchemeMonochrome(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    ColorSchemeVariant3d.neutral => SchemeNeutral(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    ColorSchemeVariant3d.vibrant => SchemeVibrant(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    ColorSchemeVariant3d.expressive => SchemeExpressive(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    ColorSchemeVariant3d.content => SchemeContent(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    ColorSchemeVariant3d.rainbow => SchemeRainbow(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
    ColorSchemeVariant3d.fruitSalad => SchemeFruitSalad(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: contrastLevel,
    ),
  };
}
