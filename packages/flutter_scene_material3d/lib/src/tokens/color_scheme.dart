import 'dart:ui' show Brightness, Color;

/// Material 3's colour roles, transcribed.
///
/// A role is a *job*, not a colour: `primary` is "the most prominent thing on
/// this screen", `onPrimary` is "what reads on top of that", and a component
/// names the job so that swapping the scheme reskins the catalogue without
/// touching a component. The names, and the two baseline schemes below, are
/// Material 3's own, taken from the same token database Flutter's
/// `ColorScheme` is generated from, so a figure written against Flutter's
/// Material transfers here unchanged.
///
/// **Generating a scheme from a seed colour is out of scope.** Material's
/// tonal-palette algorithm is a package's worth of work; [light] and [dark]
/// are enough to build every component against, and a generator can be added
/// later without changing a single component.
///
/// **Every field is a plain [Color] and the class is `const`.** That matters
/// more here than in Flutter: `Decoration3dPainterCache` keys panels on
/// `Decoration3d.cacheKey`, so a component that computes a fresh colour every
/// frame quietly defeats the cache and the frame rate falls with nothing to
/// say why. Tokens are constants; keep them that way.
///
/// ## Disabled is a colour here, not an opacity
///
/// Flutter draws a disabled control by compositing it at 38% opacity. There
/// is no subtree opacity in this stack — `Node` has no opacity or tint of any
/// kind — so a disabled control is expressed by *substituting tokens*:
/// [disabledContent] for the label and the icon, [disabledContainer] for the
/// slab behind them. Those are the figures Material's own spec states as the
/// result, so this is the more faithful spelling as well as the only
/// available one. What it cannot do is fade an arbitrary child subtree; a
/// component does not need that, and an application that does has to build it
/// out of colours too.
class ColorScheme3d {
  /// Creates a scheme. Every role is required: a half-filled scheme is a
  /// component drawing in a colour nobody chose.
  const ColorScheme3d({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.primaryFixed,
    required this.primaryFixedDim,
    required this.onPrimaryFixed,
    required this.onPrimaryFixedVariant,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.secondaryFixed,
    required this.secondaryFixedDim,
    required this.onSecondaryFixed,
    required this.onSecondaryFixedVariant,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.tertiaryFixed,
    required this.tertiaryFixedDim,
    required this.onTertiaryFixed,
    required this.onTertiaryFixedVariant,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outline,
    required this.outlineVariant,
    required this.shadow,
    required this.scrim,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.surfaceTint,
  });

  /// Material 3's baseline light scheme, built around the specification's
  /// own `#6750A4` primary.
  static const ColorScheme3d light = ColorScheme3d(
    brightness: Brightness.light,
    primary: Color(0xFF6750A4),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEADDFF),
    onPrimaryContainer: Color(0xFF4F378B),
    primaryFixed: Color(0xFFEADDFF),
    primaryFixedDim: Color(0xFFD0BCFF),
    onPrimaryFixed: Color(0xFF21005D),
    onPrimaryFixedVariant: Color(0xFF4F378B),
    secondary: Color(0xFF625B71),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE8DEF8),
    onSecondaryContainer: Color(0xFF4A4458),
    secondaryFixed: Color(0xFFE8DEF8),
    secondaryFixedDim: Color(0xFFCCC2DC),
    onSecondaryFixed: Color(0xFF1D192B),
    onSecondaryFixedVariant: Color(0xFF4A4458),
    tertiary: Color(0xFF7D5260),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFD8E4),
    onTertiaryContainer: Color(0xFF633B48),
    tertiaryFixed: Color(0xFFFFD8E4),
    tertiaryFixedDim: Color(0xFFEFB8C8),
    onTertiaryFixed: Color(0xFF31111D),
    onTertiaryFixedVariant: Color(0xFF633B48),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF8C1D18),
    surface: Color(0xFFFEF7FF),
    onSurface: Color(0xFF1D1B20),
    onSurfaceVariant: Color(0xFF49454F),
    surfaceDim: Color(0xFFDED8E1),
    surfaceBright: Color(0xFFFEF7FF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F2FA),
    surfaceContainer: Color(0xFFF3EDF7),
    surfaceContainerHigh: Color(0xFFECE6F0),
    surfaceContainerHighest: Color(0xFFE6E0E9),
    outline: Color(0xFF79747E),
    outlineVariant: Color(0xFFCAC4D0),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF322F35),
    onInverseSurface: Color(0xFFF5EFF7),
    inversePrimary: Color(0xFFD0BCFF),
    surfaceTint: Color(0xFF6750A4),
  );

  /// Material 3's baseline dark scheme, the tonal counterpart of [light].
  ///
  /// The eight `fixed` roles are deliberately identical in both schemes —
  /// that is what "fixed" means: a container whose colour survives a change
  /// of brightness, so a badge keeps its identity between the two.
  static const ColorScheme3d dark = ColorScheme3d(
    brightness: Brightness.dark,
    primary: Color(0xFFD0BCFF),
    onPrimary: Color(0xFF381E72),
    primaryContainer: Color(0xFF4F378B),
    onPrimaryContainer: Color(0xFFEADDFF),
    primaryFixed: Color(0xFFEADDFF),
    primaryFixedDim: Color(0xFFD0BCFF),
    onPrimaryFixed: Color(0xFF21005D),
    onPrimaryFixedVariant: Color(0xFF4F378B),
    secondary: Color(0xFFCCC2DC),
    onSecondary: Color(0xFF332D41),
    secondaryContainer: Color(0xFF4A4458),
    onSecondaryContainer: Color(0xFFE8DEF8),
    secondaryFixed: Color(0xFFE8DEF8),
    secondaryFixedDim: Color(0xFFCCC2DC),
    onSecondaryFixed: Color(0xFF1D192B),
    onSecondaryFixedVariant: Color(0xFF4A4458),
    tertiary: Color(0xFFEFB8C8),
    onTertiary: Color(0xFF492532),
    tertiaryContainer: Color(0xFF633B48),
    onTertiaryContainer: Color(0xFFFFD8E4),
    tertiaryFixed: Color(0xFFFFD8E4),
    tertiaryFixedDim: Color(0xFFEFB8C8),
    onTertiaryFixed: Color(0xFF31111D),
    onTertiaryFixedVariant: Color(0xFF633B48),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF141218),
    onSurface: Color(0xFFE6E0E9),
    onSurfaceVariant: Color(0xFFCAC4D0),
    surfaceDim: Color(0xFF141218),
    surfaceBright: Color(0xFF3B383E),
    surfaceContainerLowest: Color(0xFF0F0D13),
    surfaceContainerLow: Color(0xFF1D1B20),
    surfaceContainer: Color(0xFF211F26),
    surfaceContainerHigh: Color(0xFF2B2930),
    surfaceContainerHighest: Color(0xFF36343B),
    outline: Color(0xFF938F99),
    outlineVariant: Color(0xFF49454F),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE6E0E9),
    onInverseSurface: Color(0xFF322F35),
    inversePrimary: Color(0xFF6750A4),
    surfaceTint: Color(0xFFD0BCFF),
  );

  /// The opacity Material states for disabled content.
  ///
  /// Applied to [onSurface] by [disabledContent].
  static const double disabledContentOpacity = 0.38;

  /// The opacity Material states for a disabled container.
  ///
  /// Applied to [onSurface] by [disabledContainer].
  static const double disabledContainerOpacity = 0.12;

  /// Whether this is a light or a dark scheme.
  ///
  /// Nothing in this package branches on it; it is here so an application can
  /// ask, and so that interpolating between the two schemes has an answer for
  /// the field ([lerp] snaps it at the halfway point rather than inventing a
  /// third brightness).
  final Brightness brightness;

  /// The most prominent colour of the scheme: a filled button, an active state.
  final Color primary;

  /// Content drawn on [primary].
  final Color onPrimary;

  /// A quieter primary surface: a tonal button, a selected chip.
  final Color primaryContainer;

  /// Content drawn on [primaryContainer].
  final Color onPrimaryContainer;

  /// A primary container that does not change with the brightness.
  final Color primaryFixed;

  /// The dimmer of the two fixed primary containers.
  final Color primaryFixedDim;

  /// Content drawn on [primaryFixed] or [primaryFixedDim].
  final Color onPrimaryFixed;

  /// Lower-emphasis content on a fixed primary container.
  final Color onPrimaryFixedVariant;

  /// The scheme's supporting accent.
  final Color secondary;

  /// Content drawn on [secondary].
  final Color onSecondary;

  /// A quieter secondary surface.
  final Color secondaryContainer;

  /// Content drawn on [secondaryContainer].
  final Color onSecondaryContainer;

  /// A secondary container that does not change with the brightness.
  final Color secondaryFixed;

  /// The dimmer of the two fixed secondary containers.
  final Color secondaryFixedDim;

  /// Content drawn on [secondaryFixed] or [secondaryFixedDim].
  final Color onSecondaryFixed;

  /// Lower-emphasis content on a fixed secondary container.
  final Color onSecondaryFixedVariant;

  /// The scheme's contrasting accent, for balance rather than emphasis.
  final Color tertiary;

  /// Content drawn on [tertiary].
  final Color onTertiary;

  /// A quieter tertiary surface.
  final Color tertiaryContainer;

  /// Content drawn on [tertiaryContainer].
  final Color onTertiaryContainer;

  /// A tertiary container that does not change with the brightness.
  final Color tertiaryFixed;

  /// The dimmer of the two fixed tertiary containers.
  final Color tertiaryFixedDim;

  /// Content drawn on [tertiaryFixed] or [tertiaryFixedDim].
  final Color onTertiaryFixed;

  /// Lower-emphasis content on a fixed tertiary container.
  final Color onTertiaryFixedVariant;

  /// The colour of a failure: an invalid field, a destructive action.
  final Color error;

  /// Content drawn on [error].
  final Color onError;

  /// A quieter error surface.
  final Color errorContainer;

  /// Content drawn on [errorContainer].
  final Color onErrorContainer;

  /// The ground everything else stands on.
  final Color surface;

  /// Content drawn on [surface]: body text, an icon at full emphasis.
  final Color onSurface;

  /// Lower-emphasis content on a surface: a caption, a supporting icon.
  final Color onSurfaceVariant;

  /// The dimmest surface of the group.
  final Color surfaceDim;

  /// The brightest surface of the group.
  final Color surfaceBright;

  /// The surface container furthest from the viewer's attention.
  final Color surfaceContainerLowest;

  /// A surface container one step up from [surfaceContainerLowest].
  final Color surfaceContainerLow;

  /// The default container surface: a card, a sheet, a menu.
  final Color surfaceContainer;

  /// A surface container one step up from [surfaceContainer].
  final Color surfaceContainerHigh;

  /// The most prominent container surface.
  final Color surfaceContainerHighest;

  /// A drawn boundary: the rim of an outlined button, a text field.
  final Color outline;

  /// A quieter boundary: a divider, a decorative rule.
  final Color outlineVariant;

  /// The colour Material casts a shadow in.
  final Color shadow;

  /// The colour a modal barrier dims the scene with.
  final Color scrim;

  /// A surface of the opposite brightness, for a snack bar or a tooltip.
  final Color inverseSurface;

  /// Content drawn on [inverseSurface].
  final Color onInverseSurface;

  /// The accent that reads on [inverseSurface].
  final Color inversePrimary;

  /// The hue a raised surface is tinted with. Material 3 makes it [primary].
  final Color surfaceTint;

  /// [onSurface] at [disabledContentOpacity], the label of a disabled control.
  Color get disabledContent =>
      onSurface.withValues(alpha: disabledContentOpacity);

  /// [onSurface] at [disabledContainerOpacity], the slab of a disabled
  /// control.
  Color get disabledContainer =>
      onSurface.withValues(alpha: disabledContainerOpacity);

  /// A copy with the given roles replaced.
  ColorScheme3d copyWith({
    Brightness? brightness,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? surface,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
  }) => ColorScheme3d(
    brightness: brightness ?? this.brightness,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    primaryContainer: primaryContainer ?? this.primaryContainer,
    onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
    primaryFixed: primaryFixed ?? this.primaryFixed,
    primaryFixedDim: primaryFixedDim ?? this.primaryFixedDim,
    onPrimaryFixed: onPrimaryFixed ?? this.onPrimaryFixed,
    onPrimaryFixedVariant: onPrimaryFixedVariant ?? this.onPrimaryFixedVariant,
    secondary: secondary ?? this.secondary,
    onSecondary: onSecondary ?? this.onSecondary,
    secondaryContainer: secondaryContainer ?? this.secondaryContainer,
    onSecondaryContainer: onSecondaryContainer ?? this.onSecondaryContainer,
    secondaryFixed: secondaryFixed ?? this.secondaryFixed,
    secondaryFixedDim: secondaryFixedDim ?? this.secondaryFixedDim,
    onSecondaryFixed: onSecondaryFixed ?? this.onSecondaryFixed,
    onSecondaryFixedVariant:
        onSecondaryFixedVariant ?? this.onSecondaryFixedVariant,
    tertiary: tertiary ?? this.tertiary,
    onTertiary: onTertiary ?? this.onTertiary,
    tertiaryContainer: tertiaryContainer ?? this.tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer ?? this.onTertiaryContainer,
    tertiaryFixed: tertiaryFixed ?? this.tertiaryFixed,
    tertiaryFixedDim: tertiaryFixedDim ?? this.tertiaryFixedDim,
    onTertiaryFixed: onTertiaryFixed ?? this.onTertiaryFixed,
    onTertiaryFixedVariant:
        onTertiaryFixedVariant ?? this.onTertiaryFixedVariant,
    error: error ?? this.error,
    onError: onError ?? this.onError,
    errorContainer: errorContainer ?? this.errorContainer,
    onErrorContainer: onErrorContainer ?? this.onErrorContainer,
    surface: surface ?? this.surface,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
    surfaceDim: surfaceDim ?? this.surfaceDim,
    surfaceBright: surfaceBright ?? this.surfaceBright,
    surfaceContainerLowest:
        surfaceContainerLowest ?? this.surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
    surfaceContainer: surfaceContainer ?? this.surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
    surfaceContainerHighest:
        surfaceContainerHighest ?? this.surfaceContainerHighest,
    outline: outline ?? this.outline,
    outlineVariant: outlineVariant ?? this.outlineVariant,
    shadow: shadow ?? this.shadow,
    scrim: scrim ?? this.scrim,
    inverseSurface: inverseSurface ?? this.inverseSurface,
    onInverseSurface: onInverseSurface ?? this.onInverseSurface,
    inversePrimary: inversePrimary ?? this.inversePrimary,
    surfaceTint: surfaceTint ?? this.surfaceTint,
  );

  /// Linearly interpolates between two schemes.
  ///
  /// Every role is interpolated in isolation, which is what makes a theme
  /// change animatable: a scheme halfway between [light] and [dark] is a
  /// perfectly usable scheme, because a role's job does not change when its
  /// colour does. [brightness] has no midpoint and snaps at `t == 0.5`.
  static ColorScheme3d lerp(
    ColorScheme3d a,
    ColorScheme3d b,
    double t,
  ) => ColorScheme3d(
    brightness: t < 0.5 ? a.brightness : b.brightness,
    primary: Color.lerp(a.primary, b.primary, t)!,
    onPrimary: Color.lerp(a.onPrimary, b.onPrimary, t)!,
    primaryContainer: Color.lerp(a.primaryContainer, b.primaryContainer, t)!,
    onPrimaryContainer: Color.lerp(
      a.onPrimaryContainer,
      b.onPrimaryContainer,
      t,
    )!,
    primaryFixed: Color.lerp(a.primaryFixed, b.primaryFixed, t)!,
    primaryFixedDim: Color.lerp(a.primaryFixedDim, b.primaryFixedDim, t)!,
    onPrimaryFixed: Color.lerp(a.onPrimaryFixed, b.onPrimaryFixed, t)!,
    onPrimaryFixedVariant: Color.lerp(
      a.onPrimaryFixedVariant,
      b.onPrimaryFixedVariant,
      t,
    )!,
    secondary: Color.lerp(a.secondary, b.secondary, t)!,
    onSecondary: Color.lerp(a.onSecondary, b.onSecondary, t)!,
    secondaryContainer: Color.lerp(
      a.secondaryContainer,
      b.secondaryContainer,
      t,
    )!,
    onSecondaryContainer: Color.lerp(
      a.onSecondaryContainer,
      b.onSecondaryContainer,
      t,
    )!,
    secondaryFixed: Color.lerp(a.secondaryFixed, b.secondaryFixed, t)!,
    secondaryFixedDim: Color.lerp(a.secondaryFixedDim, b.secondaryFixedDim, t)!,
    onSecondaryFixed: Color.lerp(a.onSecondaryFixed, b.onSecondaryFixed, t)!,
    onSecondaryFixedVariant: Color.lerp(
      a.onSecondaryFixedVariant,
      b.onSecondaryFixedVariant,
      t,
    )!,
    tertiary: Color.lerp(a.tertiary, b.tertiary, t)!,
    onTertiary: Color.lerp(a.onTertiary, b.onTertiary, t)!,
    tertiaryContainer: Color.lerp(a.tertiaryContainer, b.tertiaryContainer, t)!,
    onTertiaryContainer: Color.lerp(
      a.onTertiaryContainer,
      b.onTertiaryContainer,
      t,
    )!,
    tertiaryFixed: Color.lerp(a.tertiaryFixed, b.tertiaryFixed, t)!,
    tertiaryFixedDim: Color.lerp(a.tertiaryFixedDim, b.tertiaryFixedDim, t)!,
    onTertiaryFixed: Color.lerp(a.onTertiaryFixed, b.onTertiaryFixed, t)!,
    onTertiaryFixedVariant: Color.lerp(
      a.onTertiaryFixedVariant,
      b.onTertiaryFixedVariant,
      t,
    )!,
    error: Color.lerp(a.error, b.error, t)!,
    onError: Color.lerp(a.onError, b.onError, t)!,
    errorContainer: Color.lerp(a.errorContainer, b.errorContainer, t)!,
    onErrorContainer: Color.lerp(a.onErrorContainer, b.onErrorContainer, t)!,
    surface: Color.lerp(a.surface, b.surface, t)!,
    onSurface: Color.lerp(a.onSurface, b.onSurface, t)!,
    onSurfaceVariant: Color.lerp(a.onSurfaceVariant, b.onSurfaceVariant, t)!,
    surfaceDim: Color.lerp(a.surfaceDim, b.surfaceDim, t)!,
    surfaceBright: Color.lerp(a.surfaceBright, b.surfaceBright, t)!,
    surfaceContainerLowest: Color.lerp(
      a.surfaceContainerLowest,
      b.surfaceContainerLowest,
      t,
    )!,
    surfaceContainerLow: Color.lerp(
      a.surfaceContainerLow,
      b.surfaceContainerLow,
      t,
    )!,
    surfaceContainer: Color.lerp(a.surfaceContainer, b.surfaceContainer, t)!,
    surfaceContainerHigh: Color.lerp(
      a.surfaceContainerHigh,
      b.surfaceContainerHigh,
      t,
    )!,
    surfaceContainerHighest: Color.lerp(
      a.surfaceContainerHighest,
      b.surfaceContainerHighest,
      t,
    )!,
    outline: Color.lerp(a.outline, b.outline, t)!,
    outlineVariant: Color.lerp(a.outlineVariant, b.outlineVariant, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
    scrim: Color.lerp(a.scrim, b.scrim, t)!,
    inverseSurface: Color.lerp(a.inverseSurface, b.inverseSurface, t)!,
    onInverseSurface: Color.lerp(a.onInverseSurface, b.onInverseSurface, t)!,
    inversePrimary: Color.lerp(a.inversePrimary, b.inversePrimary, t)!,
    surfaceTint: Color.lerp(a.surfaceTint, b.surfaceTint, t)!,
  );

  List<Object?> get _fields => <Object?>[
    brightness,
    primary,
    onPrimary,
    primaryContainer,
    onPrimaryContainer,
    primaryFixed,
    primaryFixedDim,
    onPrimaryFixed,
    onPrimaryFixedVariant,
    secondary,
    onSecondary,
    secondaryContainer,
    onSecondaryContainer,
    secondaryFixed,
    secondaryFixedDim,
    onSecondaryFixed,
    onSecondaryFixedVariant,
    tertiary,
    onTertiary,
    tertiaryContainer,
    onTertiaryContainer,
    tertiaryFixed,
    tertiaryFixedDim,
    onTertiaryFixed,
    onTertiaryFixedVariant,
    error,
    onError,
    errorContainer,
    onErrorContainer,
    surface,
    onSurface,
    onSurfaceVariant,
    surfaceDim,
    surfaceBright,
    surfaceContainerLowest,
    surfaceContainerLow,
    surfaceContainer,
    surfaceContainerHigh,
    surfaceContainerHighest,
    outline,
    outlineVariant,
    shadow,
    scrim,
    inverseSurface,
    onInverseSurface,
    inversePrimary,
    surfaceTint,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ColorScheme3d) return false;
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
  String toString() => 'ColorScheme3d(${brightness.name}, primary: $primary)';
}
