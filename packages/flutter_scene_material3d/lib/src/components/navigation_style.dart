import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d, EdgeInsets3d, Size3d;

import '../theme/theme_data.dart';
import '../tokens/typography.dart';

/// Which of Material 3's two navigation surfaces a [NavigationStyle3d] is
/// for.
///
/// They are the same component with the destinations turned ninety degrees,
/// and Material gives them different tokens anyway — a bar is a raised
/// `surfaceContainer` and a rail is a flat `surface` — so both are named
/// here rather than one being derived from the other.
enum NavigationVariant3d {
  /// The bar across the bottom of a compact screen: 80dp tall, at elevation
  /// level 2, on `surfaceContainer`.
  bar,

  /// The rail down the leading edge of a wide one: 80dp wide, flat, on
  /// `surface`.
  rail,
}

/// Everything a navigation surface is made of, including the pill.
///
/// Every figure is in **logical pixels**, and the components convert.
///
/// ## The selection indicator is a component, not a decoration
///
/// Material 3's selected destination is marked by a pill behind its icon —
/// `secondaryContainer`, stadium-shaped, 64 by 32 in a bar and 56 by 32 in a
/// rail. Here that is a `Material3d` with a `shape.full` and nothing else,
/// which is why this package needed no new machinery for it: a stadium *is*
/// a rounded rectangle whose radius exceeds half its shorter side, and
/// `ShapeScale3d.full` is exactly that.
///
/// The one thing it does need is a **depth step**, because the pill and the
/// icon share a plane and the icon is drawn on top of it. See
/// [indicatorDepthStep].
@immutable
class NavigationStyle3d {
  /// Creates a navigation style. Every field is required, for the reason
  /// `CardStyle3d`'s are.
  const NavigationStyle3d({
    required this.container,
    required this.contentColor,
    required this.selectedContentColor,
    required this.indicatorColor,
    required this.indicatorSize,
    required this.indicatorShape,
    required this.labelStyle,
    required this.extent,
    required this.elevation,
    required this.thickness,
    required this.destinationThickness,
    required this.indicatorDepthStep,
    required this.padding,
    required this.labelGap,
  }) : assert(extent >= 0.0),
       assert(elevation >= 0.0),
       assert(thickness >= 0.0),
       assert(indicatorDepthStep > 0.0);

  /// Material's navigation bar height, in logical pixels: 80.
  ///
  /// `_NavigationBarDefaultsM3.height`, and `test/navigation_defaults_test
  /// .dart` reads it off a real `NavigationBar` rather than transcribing it.
  static const double barExtent = 80.0;

  /// Material's navigation rail width, in logical pixels: 80.
  ///
  /// `_NavigationRailDefaultsM3.minWidth`, read the same way.
  static const double railExtent = 80.0;

  /// The size of a bar's selection indicator, in logical pixels.
  ///
  /// `NavigationIndicator`'s own defaults, which are **public**: 64 by 32,
  /// with a 16dp radius, which for a 32dp-tall pill is a stadium.
  static const Size3d barIndicatorSize = Size3d(64.0, 32.0, 0.0);

  /// The size of a rail's selection indicator, in logical pixels: Flutter's
  /// `_kCircularIndicatorDiameter` by `_kIndicatorHeight`, 56 by 32.
  static const Size3d railIndicatorSize = Size3d(56.0, 32.0, 0.0);

  /// The style Material publishes for [variant], out of [theme]'s tokens.
  factory NavigationStyle3d.of(Theme3dData theme, NavigationVariant3d variant) {
    final scheme = theme.colorScheme;
    NavigationStyle3d common({
      required Color container,
      required double extent,
      required double elevation,
      required Size3d indicatorSize,
    }) => NavigationStyle3d(
      container: container,
      contentColor: scheme.onSurfaceVariant,
      selectedContentColor: scheme.onSecondaryContainer,
      indicatorColor: scheme.secondaryContainer,
      indicatorSize: indicatorSize,
      indicatorShape: theme.shape.full,
      labelStyle: Typography3dToken.labelMedium,
      extent: extent,
      elevation: elevation,
      thickness: theme.thickness.structural,
      destinationThickness: theme.thickness.thin,
      // Small on purpose: the pill has no thickness worth speaking of and
      // the glyph in front of it has none at all, so the mean the step has
      // to clear is half the pill. `thin` clears it twice over and keeps the
      // icon visibly on the pill rather than hovering above it.
      indicatorDepthStep: theme.thickness.thin,
      padding: const EdgeInsets3d.symmetric(horizontal: 8.0, vertical: 12.0),
      labelGap: 4.0,
    );

    return switch (variant) {
      NavigationVariant3d.bar => common(
        container: scheme.surfaceContainer,
        extent: barExtent,
        elevation: theme.elevation.level2,
        indicatorSize: barIndicatorSize,
      ),
      NavigationVariant3d.rail => common(
        container: scheme.surface,
        extent: railExtent,
        elevation: theme.elevation.level0,
        indicatorSize: railIndicatorSize,
      ),
    };
  }

  /// The surface's colour.
  final Color container;

  /// The colour of an unselected destination's icon and label:
  /// `onSurfaceVariant`.
  final Color contentColor;

  /// The colour of the selected destination's icon and label:
  /// `onSecondaryContainer`.
  final Color selectedContentColor;

  /// The pill's colour: `secondaryContainer`.
  final Color indicatorColor;

  /// The pill's size in the plane, in logical pixels. Its depth comes from
  /// [destinationThickness].
  final Size3d indicatorSize;

  /// The pill's corner radii: `shape.full`, a stadium.
  final BorderRadius3d indicatorShape;

  /// The type role a destination's label takes: `labelMedium`.
  final Typography3dToken labelStyle;

  /// How tall a bar is, or how wide a rail is, in logical pixels.
  final double extent;

  /// How far the surface stands off the screen, in logical pixels: level 2
  /// for a bar, zero for a rail.
  final double elevation;

  /// How deep the surface's slab is: `thickness.structural`, 8dp.
  final double thickness;

  /// How deep one destination's own slab is: `thickness.thin`, 1dp.
  ///
  /// A destination has a slab of its own rather than sharing the surface's,
  /// because it needs a state layer of its own: an `InkWell3d` finds the
  /// **enclosing** `Material3d`, so a well placed directly inside the bar
  /// would wash the whole bar under one finger.
  final double destinationThickness;

  /// How far in front of the pill the icon and label sit, in logical pixels.
  ///
  /// A pill and the glyph drawn on it are coplanar without this, and two
  /// coplanar surfaces z-fight — the icon appears in patches, differently on
  /// every frame and every driver. `Thickness3d.separates` is the predicate:
  /// the step has to exceed the mean of the two thicknesses, and a glyph has
  /// none, so half the pill's depth is the bar to clear.
  final double indicatorDepthStep;

  /// Space between the surface's faces and its destinations, in logical
  /// pixels. **In-plane only.**
  final EdgeInsets3d padding;

  /// The gap between a destination's pill and its label, in logical pixels.
  final double labelGap;

  /// This style with the given fields replaced.
  NavigationStyle3d copyWith({
    Color? container,
    Color? contentColor,
    Color? selectedContentColor,
    Color? indicatorColor,
    Size3d? indicatorSize,
    BorderRadius3d? indicatorShape,
    Typography3dToken? labelStyle,
    double? extent,
    double? elevation,
    double? thickness,
    double? destinationThickness,
    double? indicatorDepthStep,
    EdgeInsets3d? padding,
    double? labelGap,
  }) => NavigationStyle3d(
    container: container ?? this.container,
    contentColor: contentColor ?? this.contentColor,
    selectedContentColor: selectedContentColor ?? this.selectedContentColor,
    indicatorColor: indicatorColor ?? this.indicatorColor,
    indicatorSize: indicatorSize ?? this.indicatorSize,
    indicatorShape: indicatorShape ?? this.indicatorShape,
    labelStyle: labelStyle ?? this.labelStyle,
    extent: extent ?? this.extent,
    elevation: elevation ?? this.elevation,
    thickness: thickness ?? this.thickness,
    destinationThickness: destinationThickness ?? this.destinationThickness,
    indicatorDepthStep: indicatorDepthStep ?? this.indicatorDepthStep,
    padding: padding ?? this.padding,
    labelGap: labelGap ?? this.labelGap,
  );

  @override
  bool operator ==(Object other) =>
      other is NavigationStyle3d &&
      other.container == container &&
      other.contentColor == contentColor &&
      other.selectedContentColor == selectedContentColor &&
      other.indicatorColor == indicatorColor &&
      other.indicatorSize == indicatorSize &&
      other.indicatorShape == indicatorShape &&
      other.labelStyle == labelStyle &&
      other.extent == extent &&
      other.elevation == elevation &&
      other.thickness == thickness &&
      other.destinationThickness == destinationThickness &&
      other.indicatorDepthStep == indicatorDepthStep &&
      other.padding == padding &&
      other.labelGap == labelGap;

  @override
  int get hashCode => Object.hash(
    container,
    contentColor,
    selectedContentColor,
    indicatorColor,
    indicatorSize,
    indicatorShape,
    labelStyle,
    extent,
    elevation,
    thickness,
    destinationThickness,
    indicatorDepthStep,
    padding,
    labelGap,
  );

  @override
  String toString() =>
      'NavigationStyle3d(${extent}dp, ${elevation}dp up, ${thickness}dp '
      'thick)';
}
