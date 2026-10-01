import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d, EdgeInsets3d;

import '../theme/theme_data.dart';
import '../tokens/depth.dart';
import '../tokens/typography.dart';

/// Which of Material 3's two tab bars a [TabBarStyle3d] is for.
///
/// Flutter spells the second one `TabBar.secondary`; both are the same
/// widget with different tokens, which is exactly what a variant is here.
enum TabBarVariant3d {
  /// The bar under a top app bar, for a screen's main sections: the chosen
  /// label in `primary`, under a 3dp indicator as wide as the label with its
  /// top corners rounded.
  primary,

  /// The bar inside a section, for its subsections: the chosen label in
  /// `onSurface`, under a square 2dp indicator as wide as the whole tab.
  secondary,
}

/// How wide a tab bar's indicator is.
///
/// Flutter's `TabBarIndicatorSize`, spelled again for the reason
/// `ListTileControlAffinity3d` gives.
enum TabBarIndicatorSize3d {
  /// As wide as the tab's label, which is the primary bar's.
  label,

  /// As wide as the whole tab, which is the secondary bar's.
  tab,
}

/// How a tab bar's indicator travels from one tab to another.
///
/// Flutter's `TabIndicatorAnimation`.
enum TabIndicatorAnimation3d {
  /// Straight across, at one width interpolated into the other: the
  /// secondary bar's.
  linear,

  /// Stretched toward where it is going and then drawn in behind, one edge
  /// leading on an accelerating curve and the other trailing on a
  /// decelerating one: the primary bar's.
  elastic,
}

/// Everything a [TabBar3d] is made of.
///
/// Flutter's `_TabsPrimaryDefaultsM3` and `_TabsSecondaryDefaultsM3`,
/// resolved, with the figures `TabBar` and `Tab` keep as private constants
/// beside them — the 46dp tab, the 72dp tab with an icon, the 2dp Flutter
/// reserves under every tab, and the 16dp either side of a label. The
/// colours are the defaults' getters; the heights, the label's place and the
/// indicator at rest are read off a laid-out `TabBar` in
/// `test/phase_5_defaults_test.dart`.
///
/// Every figure is in **logical pixels**.
@immutable
class TabBarStyle3d {
  /// Creates a tab bar style. Every field is required, for the reason
  /// `CardStyle3d`'s are.
  const TabBarStyle3d({
    required this.labelColor,
    required this.unselectedLabelColor,
    required this.labelStyle,
    required this.indicatorColor,
    required this.indicatorWeight,
    required this.indicatorSize,
    required this.indicatorShape,
    required this.indicatorAnimation,
    required this.dividerColor,
    required this.dividerHeight,
    required this.tabHeight,
    required this.textAndIconTabHeight,
    required this.reservedHeight,
    required this.labelPadding,
    required this.iconMargin,
    required this.thickness,
    required this.depthStep,
  }) : assert(indicatorWeight > 0.0),
       assert(dividerHeight >= 0.0),
       assert(tabHeight > 0.0),
       assert(textAndIconTabHeight >= tabHeight),
       assert(reservedHeight >= 0.0),
       assert(thickness >= 0.0),
       assert(
         depthStep > thickness,
         'The rule and the indicator stand in front of the tabs, and a step '
         'no larger than a tab\'s own thickness leaves them fighting it.',
       );

  /// The style Material publishes for [variant], out of [theme]'s tokens.
  factory TabBarStyle3d.of(Theme3dData theme, TabBarVariant3d variant) {
    final scheme = theme.colorScheme;
    final primary = variant == TabBarVariant3d.primary;
    final weight = primary ? 3.0 : 2.0;
    return TabBarStyle3d(
      labelColor: primary ? scheme.primary : scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: Typography3dToken.titleSmall,
      indicatorColor: scheme.primary,
      indicatorWeight: weight,
      indicatorSize: primary
          ? TabBarIndicatorSize3d.label
          : TabBarIndicatorSize3d.tab,
      // Only the primary bar's indicator is rounded, and by its own weight:
      // `_TabBarState._getIndicator`.
      indicatorShape: primary
          ? BorderRadius3d.vertical(top: weight)
          : BorderRadius3d.zero,
      indicatorAnimation: primary
          ? TabIndicatorAnimation3d.elastic
          : TabIndicatorAnimation3d.linear,
      dividerColor: scheme.outlineVariant,
      dividerHeight: 1.0,
      tabHeight: 46.0,
      textAndIconTabHeight: 72.0,
      reservedHeight: 2.0,
      labelPadding: const EdgeInsets3d.symmetric(horizontal: 16.0),
      iconMargin: const EdgeInsets3d.only(bottom: 2.0),
      thickness: theme.thickness.thin,
      depthStep: Thickness3d.stepOver(
        theme.thickness.thin,
        theme.thickness.thin,
      ),
    );
  }

  /// The chosen tab's label: `primary` on a primary bar, `onSurface` on a
  /// secondary one. Also its wash.
  final Color labelColor;

  /// Every other tab's label: `onSurfaceVariant`.
  final Color unselectedLabelColor;

  /// The type role a label takes: `titleSmall`.
  final Typography3dToken labelStyle;

  /// The indicator's colour: `primary`.
  final Color indicatorColor;

  /// How tall the indicator is: 3dp on a primary bar, 2dp on a secondary
  /// one.
  final double indicatorWeight;

  /// Whether the indicator is as wide as the label or as the tab.
  final TabBarIndicatorSize3d indicatorSize;

  /// The indicator's corners: its top two rounded by its weight on a primary
  /// bar, square on a secondary one.
  final BorderRadius3d indicatorShape;

  /// How the indicator travels between tabs.
  final TabIndicatorAnimation3d indicatorAnimation;

  /// The rule across the foot of the bar: `outlineVariant`.
  final Color dividerColor;

  /// How tall the rule is: 1dp. Zero draws none.
  final double dividerHeight;

  /// How tall a tab with a label or an icon is: 46dp, Flutter's `_kTabHeight`.
  final double tabHeight;

  /// How tall a tab with both is: 72dp, `_kTextAndIconTabHeight`. Every other
  /// tab in the same bar is padded to match.
  final double textAndIconTabHeight;

  /// The space under every tab that the indicator is drawn across: 2dp.
  ///
  /// Flutter pads each tab by `TabBar.indicatorWeight`, whose default is 2,
  /// and draws Material 3's 3dp indicator over it regardless — so a primary
  /// bar is 48dp tall and its indicator reaches 1dp into the tab.
  final double reservedHeight;

  /// The space either side of a label: 16dp, `kTabLabelPadding`.
  final EdgeInsets3d labelPadding;

  /// The space under a tab's icon when it has a label too: 2dp.
  final EdgeInsets3d iconMargin;

  /// How deep each tab's slab, the rule and the indicator are:
  /// `thickness.thin`.
  ///
  /// A tab is a slab of its own for the reason a navigation destination is:
  /// an `InkWell3d` washes the enclosing `Material3d`, and one shared surface
  /// would light every tab up under one finger.
  final double thickness;

  /// How far in front of the tabs the rule stands, and the indicator in
  /// front of the rule: `Thickness3d.stepOver` of two thin slabs.
  final double depthStep;

  /// This style with the given fields replaced.
  TabBarStyle3d copyWith({
    Color? labelColor,
    Color? unselectedLabelColor,
    Typography3dToken? labelStyle,
    Color? indicatorColor,
    double? indicatorWeight,
    TabBarIndicatorSize3d? indicatorSize,
    BorderRadius3d? indicatorShape,
    TabIndicatorAnimation3d? indicatorAnimation,
    Color? dividerColor,
    double? dividerHeight,
    double? tabHeight,
    double? textAndIconTabHeight,
    double? reservedHeight,
    EdgeInsets3d? labelPadding,
    EdgeInsets3d? iconMargin,
    double? thickness,
    double? depthStep,
  }) => TabBarStyle3d(
    labelColor: labelColor ?? this.labelColor,
    unselectedLabelColor: unselectedLabelColor ?? this.unselectedLabelColor,
    labelStyle: labelStyle ?? this.labelStyle,
    indicatorColor: indicatorColor ?? this.indicatorColor,
    indicatorWeight: indicatorWeight ?? this.indicatorWeight,
    indicatorSize: indicatorSize ?? this.indicatorSize,
    indicatorShape: indicatorShape ?? this.indicatorShape,
    indicatorAnimation: indicatorAnimation ?? this.indicatorAnimation,
    dividerColor: dividerColor ?? this.dividerColor,
    dividerHeight: dividerHeight ?? this.dividerHeight,
    tabHeight: tabHeight ?? this.tabHeight,
    textAndIconTabHeight: textAndIconTabHeight ?? this.textAndIconTabHeight,
    reservedHeight: reservedHeight ?? this.reservedHeight,
    labelPadding: labelPadding ?? this.labelPadding,
    iconMargin: iconMargin ?? this.iconMargin,
    thickness: thickness ?? this.thickness,
    depthStep: depthStep ?? this.depthStep,
  );

  @override
  bool operator ==(Object other) =>
      other is TabBarStyle3d &&
      other.labelColor == labelColor &&
      other.unselectedLabelColor == unselectedLabelColor &&
      other.labelStyle == labelStyle &&
      other.indicatorColor == indicatorColor &&
      other.indicatorWeight == indicatorWeight &&
      other.indicatorSize == indicatorSize &&
      other.indicatorShape == indicatorShape &&
      other.indicatorAnimation == indicatorAnimation &&
      other.dividerColor == dividerColor &&
      other.dividerHeight == dividerHeight &&
      other.tabHeight == tabHeight &&
      other.textAndIconTabHeight == textAndIconTabHeight &&
      other.reservedHeight == reservedHeight &&
      other.labelPadding == labelPadding &&
      other.iconMargin == iconMargin &&
      other.thickness == thickness &&
      other.depthStep == depthStep;

  @override
  int get hashCode => Object.hash(
    labelColor,
    unselectedLabelColor,
    labelStyle,
    indicatorColor,
    indicatorWeight,
    indicatorSize,
    indicatorShape,
    indicatorAnimation,
    dividerColor,
    dividerHeight,
    tabHeight,
    textAndIconTabHeight,
    reservedHeight,
    labelPadding,
    iconMargin,
    thickness,
    depthStep,
  );

  @override
  String toString() =>
      'TabBarStyle3d(${tabHeight + reservedHeight}dp, '
      '${indicatorWeight}dp ${indicatorSize.name} indicator)';
}
