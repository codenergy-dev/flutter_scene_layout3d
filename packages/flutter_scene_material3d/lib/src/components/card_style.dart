import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Border3d, BorderRadius3d, EdgeInsets3d;

import '../theme/theme_data.dart';

/// Which of Material 3's three cards a [CardStyle3d] is for.
///
/// The same shape of enum as `ButtonVariant3d`, and for the same reason: one
/// factory names every kind, a test can walk them, and the three are not
/// three implementations. A `Card3d` is a `Material3d` with a token set, and
/// the only thing that separates an elevated card from an outlined one is
/// which set.
enum CardVariant3d {
  /// A `surfaceContainerLow` container resting at elevation level 1.
  elevated,

  /// A `surfaceContainerHighest` container, flat.
  filled,

  /// A `surface` container inside a 1dp `outlineVariant`, flat.
  outlined,
}

/// Everything a card variant is made of.
///
/// Smaller than `ButtonStyle3d`, and the difference is the interesting part:
/// **nothing here varies with a state.** Material 3 gives a card no disabled
/// appearance, no hovered container and no focused outline — an interactive
/// card is washed by its state layer and is otherwise the same card. That is
/// why a `Card3d` never rebuilds for a hover, a focus or a press, where a
/// filled button has to; the whole interaction is one uniform write on the
/// repaint-only tier.
///
/// Every figure is in **logical pixels**, like every other Material token,
/// and `Card3d` converts them through the surface's metrics.
@immutable
class CardStyle3d {
  /// Creates a card style. Every field is required, for the reason
  /// `ButtonStyle3d`'s are: a half-stated style is a surface drawing in a
  /// colour nobody chose.
  const CardStyle3d({
    required this.container,
    required this.contentColor,
    required this.shape,
    required this.elevation,
    required this.thickness,
    required this.outline,
    required this.outlineWidth,
    required this.margin,
    required this.padding,
  }) : assert(elevation >= 0.0),
       assert(thickness >= 0.0),
       assert(outlineWidth >= 0.0);

  /// The style Material publishes for [variant], out of [theme]'s tokens.
  ///
  /// Checked against Flutter's own card defaults in
  /// `test/card_defaults_test.dart` — by reading the `Material` a real `Card`
  /// renders, since `_CardDefaultsM3` is private and `CardTheme.of` returns
  /// an application's overrides rather than the resolved defaults.
  factory CardStyle3d.of(Theme3dData theme, CardVariant3d variant) {
    final scheme = theme.colorScheme;
    CardStyle3d common({
      required Color container,
      double elevation = 0.0,
      Color? outline,
    }) => CardStyle3d(
      container: container,
      contentColor: scheme.onSurface,
      shape: theme.shape.medium,
      elevation: elevation,
      thickness: theme.thickness.raised,
      outline: outline,
      outlineWidth: outline == null ? 0.0 : 1.0,
      margin: const EdgeInsets3d.symmetric(horizontal: 4.0, vertical: 4.0),
      padding: EdgeInsets3d.zero,
    );

    return switch (variant) {
      CardVariant3d.elevated => common(
        container: scheme.surfaceContainerLow,
        elevation: theme.elevation.level1,
      ),
      CardVariant3d.filled => common(container: scheme.surfaceContainerHighest),
      CardVariant3d.outlined => common(
        container: scheme.surface,
        outline: scheme.outlineVariant,
      ),
    };
  }

  /// The slab's colour.
  final Color container;

  /// The colour of the labels and icons drawn on it, and of the state-layer
  /// wash when the card is interactive.
  final Color contentColor;

  /// The corner radii, in logical pixels. `shape.medium` — 12dp — for all
  /// three variants.
  final BorderRadius3d shape;

  /// How far the card stands off its parent, in logical pixels.
  ///
  /// Level 1 for an elevated card and zero for the other two. There is no
  /// hovered figure because Material 3 does not raise a card under a pointer,
  /// which is what keeps a card's whole interaction off the rebuild path.
  final double elevation;

  /// How deep the slab is, in logical pixels: `thickness.raised`, 4dp.
  ///
  /// The token Material has no word for. A card is the component the scale
  /// was named around — deep enough that its rim catches a grazing light and
  /// that it visibly occludes what is behind it, shallow enough that a 12dp
  /// depth step still separates two of them.
  final double thickness;

  /// The outline's colour, or null for a variant that draws none.
  final Color? outline;

  /// How thick the outline is, in logical pixels. Zero when there is none.
  final double outlineWidth;

  /// Space *outside* the card, in logical pixels: Material's 4dp all round.
  ///
  /// **In-plane only.** A front or back margin would push the card off the
  /// plane its parent put it on, which is what [elevation] is for and is not
  /// what a margin means.
  final EdgeInsets3d margin;

  /// Space between the card's faces and its child, in logical pixels.
  ///
  /// Zero, exactly as Flutter's `Card` has none: a card is a surface, and
  /// what goes inside it decides its own insets. State the two in-plane axes
  /// if you set one — a front inset pushes the child into the slab, where the
  /// surface it is drawn on wins the depth test and hides it.
  final EdgeInsets3d padding;

  /// The outline as a [Border3d], which is what a `Material3d` takes.
  Border3d get border => outline == null
      ? Border3d.none
      : Border3d(width: outlineWidth, color: outline!);

  /// This style with the given fields replaced.
  CardStyle3d copyWith({
    Color? container,
    Color? contentColor,
    BorderRadius3d? shape,
    double? elevation,
    double? thickness,
    Color? outline,
    double? outlineWidth,
    EdgeInsets3d? margin,
    EdgeInsets3d? padding,
  }) => CardStyle3d(
    container: container ?? this.container,
    contentColor: contentColor ?? this.contentColor,
    shape: shape ?? this.shape,
    elevation: elevation ?? this.elevation,
    thickness: thickness ?? this.thickness,
    outline: outline ?? this.outline,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    margin: margin ?? this.margin,
    padding: padding ?? this.padding,
  );

  @override
  bool operator ==(Object other) =>
      other is CardStyle3d &&
      other.container == container &&
      other.contentColor == contentColor &&
      other.shape == shape &&
      other.elevation == elevation &&
      other.thickness == thickness &&
      other.outline == outline &&
      other.outlineWidth == outlineWidth &&
      other.margin == margin &&
      other.padding == padding;

  @override
  int get hashCode => Object.hash(
    container,
    contentColor,
    shape,
    elevation,
    thickness,
    outline,
    outlineWidth,
    margin,
    padding,
  );

  @override
  String toString() =>
      'CardStyle3d($container, ${elevation}dp, ${thickness}dp thick)';
}
