import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show EdgeInsetsDirectional3d;

import '../theme/theme_data.dart';
import '../tokens/typography.dart';

/// Everything a [MaterialBanner3d] is made of.
///
/// Flutter's `MaterialBannerThemeData` resolved, plus the figures its
/// `MaterialBanner` writes inline: the two paddings, the leading gap, the
/// 52dp actions bar and its 8dp spacing, the 10dp margin and the 1.5 ceiling
/// on type. The colours are `_BannerDefaultsM3`'s and the elevation is what a
/// real banner actually lays out at, both read off the `Material` one builds
/// in `test/phase_4_defaults_test.dart`;
/// the paddings are read off where a real banner puts its content. The rest
/// are transcribed, and the test says which.
///
/// Every figure is in **logical pixels**.
@immutable
class MaterialBannerStyle3d {
  /// Creates a banner style. Every field is required, for the reason
  /// `CardStyle3d`'s are.
  const MaterialBannerStyle3d({
    required this.container,
    required this.contentColor,
    required this.dividerColor,
    required this.textStyle,
    required this.elevation,
    required this.thickness,
    required this.singleRowPadding,
    required this.padding,
    required this.leadingPadding,
    required this.actionsBarMinHeight,
    required this.actionsBarPadding,
    required this.actionsSpacing,
    required this.elevatedMargin,
    required this.maxTextScaleFactor,
  }) : assert(elevation >= 0.0),
       assert(thickness >= 0.0),
       assert(actionsBarMinHeight >= 0.0),
       assert(actionsSpacing >= 0.0),
       assert(elevatedMargin >= 0.0),
       assert(maxTextScaleFactor >= 1.0);

  /// The style Material publishes, out of [theme]'s tokens.
  factory MaterialBannerStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return MaterialBannerStyle3d(
      container: scheme.surfaceContainerLow,
      contentColor: scheme.onSurface,
      dividerColor: scheme.outlineVariant,
      textStyle: Typography3dToken.bodyMedium,
      // **Zero, though `_BannerDefaultsM3` says 1.** `MaterialBanner.build`
      // reads `widget.elevation ?? bannerTheme.elevation ?? 0.0` and never the
      // defaults' figure, so a Material 3 banner in Flutter is flat, with the
      // rule under it and no margin. The drift test found it; a port draws
      // what Flutter draws, not what its token table says.
      elevation: theme.elevation.level0,
      // A strip in the body, like a card, and no deeper than the deepest
      // thing a body holds — a `Scaffold3d` keeps its bars in front of
      // `raised` and asserts as much.
      thickness: theme.thickness.raised,
      singleRowPadding: const EdgeInsetsDirectional3d.only(start: 16, top: 2),
      padding: const EdgeInsetsDirectional3d.only(
        start: 16,
        top: 24,
        end: 16,
        bottom: 4,
      ),
      leadingPadding: const EdgeInsetsDirectional3d.only(end: 16),
      actionsBarMinHeight: 52,
      actionsBarPadding: const EdgeInsetsDirectional3d.only(start: 8, end: 8),
      actionsSpacing: 8,
      elevatedMargin: 10,
      maxTextScaleFactor: 1.5,
    );
  }

  /// The strip's colour: `surfaceContainerLow`.
  final Color container;

  /// The content's colour: `onSurface`, which is where Flutter's text theme
  /// leaves `bodyMedium`.
  final Color contentColor;

  /// The rule under a flat banner: `outlineVariant`.
  final Color dividerColor;

  /// The content's type: `bodyMedium`.
  final Typography3dToken textStyle;

  /// How far the banner stands off the screen: none, which is what Flutter's
  /// banner lays out at whatever its token table says.
  final double elevation;

  /// How deep the slab is: `thickness.raised`, 4dp.
  final double thickness;

  /// Space round the content when the one action sits beside it: 16dp at the
  /// start and 2dp at the top.
  final EdgeInsetsDirectional3d singleRowPadding;

  /// Space round the content when the actions sit under it.
  final EdgeInsetsDirectional3d padding;

  /// Space after the leading widget: 16dp at its end.
  final EdgeInsetsDirectional3d leadingPadding;

  /// The shortest the actions bar may be: 52dp.
  final double actionsBarMinHeight;

  /// Space either side of the actions: 8dp.
  final EdgeInsetsDirectional3d actionsBarPadding;

  /// Between one action and the next: 8dp, Flutter's `OverflowBar` spacing.
  final double actionsSpacing;

  /// The margin under a banner that is raised at all: 10dp.
  ///
  /// In Flutter it is room for the shadow a raised banner casts. Nothing
  /// here casts a shadow, and the margin is kept anyway, because it is space
  /// a ported screen already lays the rest of itself out around.
  final double elevatedMargin;

  /// How far the content and the actions grow with the reader's type: 1.5,
  /// Flutter's `_kMaxContentTextScaleFactor`.
  final double maxTextScaleFactor;
}
