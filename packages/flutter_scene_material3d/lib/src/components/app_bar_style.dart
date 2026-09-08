import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d, EdgeInsets3d;

import '../theme/theme_data.dart';
import '../tokens/typography.dart';

/// Which of Material 3's four top app bars an [AppBarStyle3d] is for.
///
/// The same shape of enum as `CardVariant3d` and `ButtonVariant3d`, and for
/// the same reason: one factory names every kind, a test can walk them, and
/// the four are not four implementations.
///
/// The three sizes differ only in how tall they are *expanded* and in what
/// type role the title takes there. All four collapse to the same 64dp
/// toolbar, which is why a `SliverAppBar3d` can pin any of them.
enum AppBarVariant3d {
  /// A 64dp bar with the title at the leading edge. Material's default.
  small,

  /// A 64dp bar with the title centred, which is iOS's convention and
  /// Material's `AppBar.centerTitle`.
  centerAligned,

  /// A 112dp bar collapsing to 64, with the expanded title in
  /// `headlineSmall`.
  medium,

  /// A 152dp bar collapsing to 64, with the expanded title in
  /// `headlineMedium`.
  large,
}

/// Everything an app bar variant is made of.
///
/// Every figure is in **logical pixels**, like every other Material token, and
/// [AppBar3d] converts them through the surface's metrics.
///
/// ## Nothing here varies with a pointer, and one thing varies with a scroll
///
/// A bar is not an interactive surface — its buttons are — so there is no
/// hovered container, no focused outline and no disabled substitution, the
/// same property `CardStyle3d` has. What a bar *does* have is a state
/// Material calls "scrolled under": [scrolledUnderElevation], which the bar
/// takes on once content has gone beneath it.
///
/// That is one number, and here it does two jobs it does not do in Flutter.
/// It is a real distance toward the viewer, so it is also the thing keeping a
/// row's slab out of the bar's slab; and because it is a rebuild rather than
/// a uniform write, a bar that changed it every frame would be relaying out a
/// screen. `SliverAppBar3d` therefore does not animate it — see that class.
@immutable
class AppBarStyle3d {
  /// Creates an app bar style. Every field is required, for the reason
  /// `CardStyle3d`'s are: a half-stated style is a surface drawing in a
  /// colour nobody chose.
  const AppBarStyle3d({
    required this.container,
    required this.contentColor,
    required this.titleStyle,
    required this.expandedTitleStyle,
    required this.shape,
    required this.toolbarHeight,
    required this.expandedHeight,
    required this.elevation,
    required this.scrolledUnderElevation,
    required this.thickness,
    required this.centerTitle,
    required this.titleSpacing,
    required this.padding,
  }) : assert(toolbarHeight >= 0.0),
       assert(expandedHeight >= toolbarHeight),
       assert(elevation >= 0.0),
       assert(scrolledUnderElevation >= 0.0),
       assert(thickness >= 0.0);

  /// Material's collapsed toolbar height, in logical pixels.
  ///
  /// 64, which is `_AppBarDefaultsM3.toolbarHeight` and the figure
  /// `AppBar.medium` and `AppBar.large` collapse to.
  ///
  /// **Flutter's own plain `AppBar` lays out at 56 instead**, because its
  /// build method resolves `widget.toolbarHeight ?? appBarTheme.toolbarHeight
  /// ?? kToolbarHeight` and never reaches its M3 defaults object. That is a
  /// discrepancy inside Flutter rather than a choice this package is making,
  /// and `test/app_bar_defaults_test.dart` pins **both** numbers so that a
  /// reader meets it here rather than discovering it against a ruler.
  static const double defaultToolbarHeight = 64.0;

  /// The expanded height of a [AppBarVariant3d.medium] bar, in logical
  /// pixels: Flutter's `_MediumScrollUnderFlexibleConfig.expandedHeight`.
  static const double mediumExpandedHeight = 112.0;

  /// The expanded height of a [AppBarVariant3d.large] bar, in logical pixels:
  /// Flutter's `_LargeScrollUnderFlexibleConfig.expandedHeight`.
  static const double largeExpandedHeight = 152.0;

  /// Material's gap between the leading widget and the title, in logical
  /// pixels: Flutter's `NavigationToolbar.kMiddleSpacing`.
  static const double defaultTitleSpacing = 16.0;

  /// The elevation a bar takes on once content has scrolled under it, in
  /// logical pixels: Flutter's `_AppBarDefaultsM3.scrolledUnderElevation`.
  static const double defaultScrolledUnderElevation = 3.0;

  /// The style Material publishes for [variant], out of [theme]'s tokens.
  ///
  /// Checked in `test/app_bar_defaults_test.dart` against the figures
  /// Flutter's own generated defaults carry.
  factory AppBarStyle3d.of(Theme3dData theme, AppBarVariant3d variant) {
    final scheme = theme.colorScheme;
    AppBarStyle3d common({
      required double expandedHeight,
      required Typography3dToken expandedTitleStyle,
      bool centerTitle = false,
    }) => AppBarStyle3d(
      container: scheme.surface,
      contentColor: scheme.onSurface,
      titleStyle: Typography3dToken.titleLarge,
      expandedTitleStyle: expandedTitleStyle,
      shape: theme.shape.none,
      toolbarHeight: defaultToolbarHeight,
      expandedHeight: expandedHeight,
      elevation: theme.elevation.level0,
      scrolledUnderElevation: defaultScrolledUnderElevation,
      thickness: theme.thickness.structural,
      centerTitle: centerTitle,
      titleSpacing: defaultTitleSpacing,
      padding: const EdgeInsets3d.symmetric(horizontal: 4.0),
    );

    return switch (variant) {
      AppBarVariant3d.small => common(
        expandedHeight: defaultToolbarHeight,
        expandedTitleStyle: Typography3dToken.titleLarge,
      ),
      AppBarVariant3d.centerAligned => common(
        expandedHeight: defaultToolbarHeight,
        expandedTitleStyle: Typography3dToken.titleLarge,
        centerTitle: true,
      ),
      AppBarVariant3d.medium => common(
        expandedHeight: mediumExpandedHeight,
        expandedTitleStyle: Typography3dToken.headlineSmall,
      ),
      AppBarVariant3d.large => common(
        expandedHeight: largeExpandedHeight,
        expandedTitleStyle: Typography3dToken.headlineMedium,
      ),
    };
  }

  /// The slab's colour: `colorScheme.surface`.
  final Color container;

  /// The colour of the title, the leading widget and the actions:
  /// `colorScheme.onSurface`.
  final Color contentColor;

  /// The type role the title takes in a collapsed bar: `titleLarge`.
  final Typography3dToken titleStyle;

  /// The type role the title takes at the bar's full height.
  ///
  /// The same as [titleStyle] for the two 64dp bars, and larger for the two
  /// that expand. **`AppBar3d` uses it only when the bar is at rest** — the
  /// title's role cannot change mid-collapse, because that is a rebuild and a
  /// collapse happens inside a layout pass. See `SliverAppBar3d`.
  final Typography3dToken expandedTitleStyle;

  /// The corner radii, in logical pixels: square, for all four variants.
  final BorderRadius3d shape;

  /// How tall the bar is when it has collapsed as far as it will go, in
  /// logical pixels.
  final double toolbarHeight;

  /// How tall the bar is at rest, in logical pixels.
  ///
  /// Equal to [toolbarHeight] for a bar that does not expand.
  final double expandedHeight;

  /// How far the bar stands off the screen at rest, in logical pixels: zero.
  final double elevation;

  /// How far the bar stands off the screen once content is beneath it.
  final double scrolledUnderElevation;

  /// How deep the slab is, in logical pixels: `thickness.structural`, 8dp.
  ///
  /// The token named for exactly this. A bar is the deepest thing on a
  /// screen because it is the thing everything else passes behind, and its
  /// depth is what makes that read as passing behind rather than through.
  final double thickness;

  /// Whether the title is centred rather than at the leading edge.
  final bool centerTitle;

  /// The gap between the leading widget and the title, in logical pixels.
  final double titleSpacing;

  /// Space between the bar's faces and its content, in logical pixels.
  ///
  /// **In-plane only.** A front inset pushes the toolbar into the slab, where
  /// the surface it is drawn on wins the depth test and the title vanishes.
  final EdgeInsets3d padding;

  /// This style with the given fields replaced.
  AppBarStyle3d copyWith({
    Color? container,
    Color? contentColor,
    Typography3dToken? titleStyle,
    Typography3dToken? expandedTitleStyle,
    BorderRadius3d? shape,
    double? toolbarHeight,
    double? expandedHeight,
    double? elevation,
    double? scrolledUnderElevation,
    double? thickness,
    bool? centerTitle,
    double? titleSpacing,
    EdgeInsets3d? padding,
  }) => AppBarStyle3d(
    container: container ?? this.container,
    contentColor: contentColor ?? this.contentColor,
    titleStyle: titleStyle ?? this.titleStyle,
    expandedTitleStyle: expandedTitleStyle ?? this.expandedTitleStyle,
    shape: shape ?? this.shape,
    toolbarHeight: toolbarHeight ?? this.toolbarHeight,
    expandedHeight: expandedHeight ?? this.expandedHeight,
    elevation: elevation ?? this.elevation,
    scrolledUnderElevation:
        scrolledUnderElevation ?? this.scrolledUnderElevation,
    thickness: thickness ?? this.thickness,
    centerTitle: centerTitle ?? this.centerTitle,
    titleSpacing: titleSpacing ?? this.titleSpacing,
    padding: padding ?? this.padding,
  );

  @override
  bool operator ==(Object other) =>
      other is AppBarStyle3d &&
      other.container == container &&
      other.contentColor == contentColor &&
      other.titleStyle == titleStyle &&
      other.expandedTitleStyle == expandedTitleStyle &&
      other.shape == shape &&
      other.toolbarHeight == toolbarHeight &&
      other.expandedHeight == expandedHeight &&
      other.elevation == elevation &&
      other.scrolledUnderElevation == scrolledUnderElevation &&
      other.thickness == thickness &&
      other.centerTitle == centerTitle &&
      other.titleSpacing == titleSpacing &&
      other.padding == padding;

  @override
  int get hashCode => Object.hash(
    container,
    contentColor,
    titleStyle,
    expandedTitleStyle,
    shape,
    toolbarHeight,
    expandedHeight,
    elevation,
    scrolledUnderElevation,
    thickness,
    centerTitle,
    titleSpacing,
    padding,
  );

  @override
  String toString() =>
      'AppBarStyle3d(${toolbarHeight}dp toolbar, ${expandedHeight}dp '
      'expanded, ${thickness}dp thick)';
}
