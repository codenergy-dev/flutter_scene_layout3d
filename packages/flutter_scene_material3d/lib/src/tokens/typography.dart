import 'dart:ui' show Color, FontWeight, TextLeadingDistribution;

import 'package:flutter/painting.dart' show TextStyle;

/// Material 3's type scale, as Flutter [TextStyle]s.
///
/// Fifteen styles in five groups of three. The group says what the text is
/// *for* — a display line, a headline, a title, running body copy, the label
/// inside a control — and the size within the group is the emphasis. A
/// component names a style rather than a number, which is what lets a theme
/// change the whole catalogue's voice at once.
///
/// **Every figure is in logical pixels, and stays that way.** `Text3d` takes
/// a `TextStyle` directly, measures in logical pixels, and multiplies by
/// `metrics.unitsPerLogicalPixel * metrics.textScaleFactor` to reach world
/// units — so a `labelLarge` is 14sp on a camera-bound surface and still 14sp
/// on a panel hanging on a wall. Nothing here should ever be pre-multiplied
/// by the metrics; that is the layer below's job, and doing it twice is a
/// label the size of a door.
///
/// ## Where these numbers come from, and where they differ from Flutter's
///
/// The sizes, weights and tracking are Material 3's published figures, the
/// same ones Flutter's `Typography.material2021` carries. The **line heights
/// are not spelled the same way**: Material publishes a line height in
/// logical pixels (a 57dp `displayLarge` on a 64dp line), while Flutter's
/// `TextStyle.height` is a *multiple* of the font size, so its generated
/// tables round — `1.12` where `64 / 57` is `1.1228…`. These styles carry the
/// exact ratio instead, written as the division so that the published pair is
/// readable in the source. The difference is under half a percent of a line,
/// and it is in the direction of the spec.
///
/// [TextLeadingDistribution.even] is set for the same reason: Material's line
/// height is the whole line box with the extra leading split above and below,
/// which is what `even` means and what `proportional` — Flutter's default —
/// does not do.
///
/// **These styles carry no colour.** A colour comes from the
/// [ColorScheme3d] role the *component* is drawing in — `onSurface` for body
/// copy, `onPrimary` inside a filled button — and a style that carried one
/// would have to be re-derived every time the scheme changed. Use [apply], or
/// `copyWith(color: …)` at the point of use.
class Typography3d {
  /// Creates a type scale. Every style is required, so a scale cannot be
  /// half-defined.
  const Typography3d({
    required this.displayLarge,
    required this.displayMedium,
    required this.displaySmall,
    required this.headlineLarge,
    required this.headlineMedium,
    required this.headlineSmall,
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
  });

  /// Material 3's baseline type scale, for English-like scripts.
  ///
  /// Material publishes separate geometry for dense (Chinese, Japanese,
  /// Korean) and tall (Farsi, Hindi, Thai) scripts. Those are not here: they
  /// differ only in the baseline they hang from, and choosing between them
  /// needs a locale, which nothing in this stack has yet. State a scale of
  /// your own if you need one.
  static const Typography3d baseline = Typography3d(
    displayLarge: TextStyle(
      fontSize: 57.0,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
      height: 64.0 / 57.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    displayMedium: TextStyle(
      fontSize: 45.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 52.0 / 45.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    displaySmall: TextStyle(
      fontSize: 36.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 44.0 / 36.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    headlineLarge: TextStyle(
      fontSize: 32.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 40.0 / 32.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    headlineMedium: TextStyle(
      fontSize: 28.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 36.0 / 28.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    headlineSmall: TextStyle(
      fontSize: 24.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 32.0 / 24.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    titleLarge: TextStyle(
      fontSize: 22.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 28.0 / 22.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    titleMedium: TextStyle(
      fontSize: 16.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      height: 24.0 / 16.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    titleSmall: TextStyle(
      fontSize: 14.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 20.0 / 14.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    bodyLarge: TextStyle(
      fontSize: 16.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.5,
      height: 24.0 / 16.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    bodyMedium: TextStyle(
      fontSize: 14.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      height: 20.0 / 14.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    bodySmall: TextStyle(
      fontSize: 12.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      height: 16.0 / 12.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    labelLarge: TextStyle(
      fontSize: 14.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 20.0 / 14.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    labelMedium: TextStyle(
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 16.0 / 12.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    labelSmall: TextStyle(
      fontSize: 11.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 16.0 / 11.0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
  );

  /// 57dp on a 64dp line. The largest thing on a screen, used once.
  final TextStyle displayLarge;

  /// 45dp on a 52dp line.
  final TextStyle displayMedium;

  /// 36dp on a 44dp line.
  final TextStyle displaySmall;

  /// 32dp on a 40dp line. The heading of a screen or a large section.
  final TextStyle headlineLarge;

  /// 28dp on a 36dp line.
  final TextStyle headlineMedium;

  /// 24dp on a 32dp line.
  final TextStyle headlineSmall;

  /// 22dp on a 28dp line. The title of a bar, a dialog, a card.
  final TextStyle titleLarge;

  /// 16dp on a 24dp line, medium weight. A list tile's headline.
  final TextStyle titleMedium;

  /// 14dp on a 20dp line, medium weight.
  final TextStyle titleSmall;

  /// 16dp on a 24dp line. Running copy at the comfortable size.
  final TextStyle bodyLarge;

  /// 14dp on a 20dp line. The default body style, and the most used of all.
  final TextStyle bodyMedium;

  /// 12dp on a 16dp line. Supporting copy, a caption.
  final TextStyle bodySmall;

  /// 14dp on a 20dp line, medium weight. The text inside a button.
  final TextStyle labelLarge;

  /// 12dp on a 16dp line, medium weight. A navigation label, a chip.
  final TextStyle labelMedium;

  /// 11dp on a 16dp line, medium weight. The smallest label Material states.
  final TextStyle labelSmall;

  /// Every style with [color] (and optionally a font) applied.
  ///
  /// The one-call form of what a component does at the point of use, for an
  /// application that wants a whole scale in one role's colour — a card of
  /// `onSurface` copy, say — without writing `copyWith` fifteen times.
  Typography3d apply({
    Color? color,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    String? package,
  }) {
    TextStyle one(TextStyle style) => style.copyWith(
      color: color ?? style.color,
      fontFamily: fontFamily ?? style.fontFamily,
      fontFamilyFallback: fontFamilyFallback ?? style.fontFamilyFallback,
      package: package,
    );
    return Typography3d(
      displayLarge: one(displayLarge),
      displayMedium: one(displayMedium),
      displaySmall: one(displaySmall),
      headlineLarge: one(headlineLarge),
      headlineMedium: one(headlineMedium),
      headlineSmall: one(headlineSmall),
      titleLarge: one(titleLarge),
      titleMedium: one(titleMedium),
      titleSmall: one(titleSmall),
      bodyLarge: one(bodyLarge),
      bodyMedium: one(bodyMedium),
      bodySmall: one(bodySmall),
      labelLarge: one(labelLarge),
      labelMedium: one(labelMedium),
      labelSmall: one(labelSmall),
    );
  }

  /// A copy with the given styles replaced.
  Typography3d copyWith({
    TextStyle? displayLarge,
    TextStyle? displayMedium,
    TextStyle? displaySmall,
    TextStyle? headlineLarge,
    TextStyle? headlineMedium,
    TextStyle? headlineSmall,
    TextStyle? titleLarge,
    TextStyle? titleMedium,
    TextStyle? titleSmall,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? labelLarge,
    TextStyle? labelMedium,
    TextStyle? labelSmall,
  }) => Typography3d(
    displayLarge: displayLarge ?? this.displayLarge,
    displayMedium: displayMedium ?? this.displayMedium,
    displaySmall: displaySmall ?? this.displaySmall,
    headlineLarge: headlineLarge ?? this.headlineLarge,
    headlineMedium: headlineMedium ?? this.headlineMedium,
    headlineSmall: headlineSmall ?? this.headlineSmall,
    titleLarge: titleLarge ?? this.titleLarge,
    titleMedium: titleMedium ?? this.titleMedium,
    titleSmall: titleSmall ?? this.titleSmall,
    bodyLarge: bodyLarge ?? this.bodyLarge,
    bodyMedium: bodyMedium ?? this.bodyMedium,
    bodySmall: bodySmall ?? this.bodySmall,
    labelLarge: labelLarge ?? this.labelLarge,
    labelMedium: labelMedium ?? this.labelMedium,
    labelSmall: labelSmall ?? this.labelSmall,
  );

  /// Linearly interpolates between two type scales.
  ///
  /// Each style through [TextStyle.lerp], so a size, a weight, a tracking and
  /// a colour all move together. **This is a relayout**, unlike interpolating
  /// a colour scheme: a label's size decides its box, so animating a
  /// typography change re-measures every label on the surface every frame.
  /// It exists so a theme change can be animated at all, not so that one can
  /// be animated cheaply.
  ///
  /// **It is not the identity at its own ends.** [TextStyle.lerp] is a merge
  /// as well as an interpolation: where one end states a property and the
  /// other leaves it null, the stated value is carried across rather than
  /// dropped. So a scale built from bare `TextStyle(fontSize: 10)` values
  /// comes back at `t == 1` with the other end's weights and tracking filled
  /// in. That is Flutter's behaviour and usually what you want; state a
  /// complete style — `baseline.bodyMedium.copyWith(fontSize: 10)` — when you
  /// want the ends to be exactly what you wrote.
  ///
  /// **And it does not clamp.** The shape and depth scales hold their values
  /// at or above zero because the layer below them asserts on a negative
  /// radius or elevation; nothing asserts on a negative font size, so an
  /// overshooting curve run past `t == 1` between two very different scales
  /// can produce one, and it will surface later as a measurement failure
  /// rather than here. Curves that overshoot want a size floor of their own.
  static Typography3d lerp(Typography3d a, Typography3d b, double t) =>
      Typography3d(
        displayLarge: TextStyle.lerp(a.displayLarge, b.displayLarge, t)!,
        displayMedium: TextStyle.lerp(a.displayMedium, b.displayMedium, t)!,
        displaySmall: TextStyle.lerp(a.displaySmall, b.displaySmall, t)!,
        headlineLarge: TextStyle.lerp(a.headlineLarge, b.headlineLarge, t)!,
        headlineMedium: TextStyle.lerp(a.headlineMedium, b.headlineMedium, t)!,
        headlineSmall: TextStyle.lerp(a.headlineSmall, b.headlineSmall, t)!,
        titleLarge: TextStyle.lerp(a.titleLarge, b.titleLarge, t)!,
        titleMedium: TextStyle.lerp(a.titleMedium, b.titleMedium, t)!,
        titleSmall: TextStyle.lerp(a.titleSmall, b.titleSmall, t)!,
        bodyLarge: TextStyle.lerp(a.bodyLarge, b.bodyLarge, t)!,
        bodyMedium: TextStyle.lerp(a.bodyMedium, b.bodyMedium, t)!,
        bodySmall: TextStyle.lerp(a.bodySmall, b.bodySmall, t)!,
        labelLarge: TextStyle.lerp(a.labelLarge, b.labelLarge, t)!,
        labelMedium: TextStyle.lerp(a.labelMedium, b.labelMedium, t)!,
        labelSmall: TextStyle.lerp(a.labelSmall, b.labelSmall, t)!,
      );

  List<Object?> get _fields => <Object?>[
    displayLarge,
    displayMedium,
    displaySmall,
    headlineLarge,
    headlineMedium,
    headlineSmall,
    titleLarge,
    titleMedium,
    titleSmall,
    bodyLarge,
    bodyMedium,
    bodySmall,
    labelLarge,
    labelMedium,
    labelSmall,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Typography3d) return false;
    final mine = _fields;
    final theirs = other._fields;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);

  @override
  String toString() => 'Typography3d(bodyMedium: $bodyMedium)';
}
