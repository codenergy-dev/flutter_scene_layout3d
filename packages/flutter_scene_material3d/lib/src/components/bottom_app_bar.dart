import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show EdgeInsets3d, EdgeInsetsGeometry3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        MediaQuery3d,
        ScenePadding3d,
        SceneSafeArea3d,
        SceneSizedBox3d;

import '../theme/theme.dart';
import '../theme/theme_data.dart';
import 'material.dart';

/// Everything a [BottomAppBar3d] is made of.
///
/// `_BottomAppBarDefaultsM3`'s figures and the 12 by 16 padding Flutter's
/// `BottomAppBar` writes inline for Material 3. The height and the padding
/// are read off a real bar in `test/phase_4_defaults_test.dart`, and the
/// colour off its `PhysicalShape`.
///
/// Every figure is in **logical pixels**.
@immutable
class BottomAppBarStyle3d {
  /// Creates a bottom app bar style. Every field is required, for the reason
  /// `CardStyle3d`'s are.
  const BottomAppBarStyle3d({
    required this.container,
    required this.contentColor,
    required this.height,
    required this.elevation,
    required this.thickness,
    required this.padding,
  }) : assert(height >= 0.0),
       assert(elevation >= 0.0),
       assert(thickness >= 0.0);

  /// The style Material publishes, out of [theme]'s tokens.
  factory BottomAppBarStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return BottomAppBarStyle3d(
      container: scheme.surfaceContainer,
      contentColor: scheme.onSurfaceVariant,
      height: 80.0,
      elevation: theme.elevation.level2,
      thickness: theme.thickness.structural,
      padding: const EdgeInsets3d.symmetric(vertical: 12.0, horizontal: 16.0),
    );
  }

  /// The bar's colour: `surfaceContainer`.
  final Color container;

  /// The colour of what is drawn on it: `onSurfaceVariant`, which is what
  /// Material's bottom app bar gives its icons.
  final Color contentColor;

  /// How tall the bar is, before the safe area: 80dp.
  final double height;

  /// How far the bar stands off the screen: level 2, Flutter's 3dp.
  final double elevation;

  /// How deep the slab is: `thickness.structural`, 8dp, as every bar's is.
  final double thickness;

  /// Space between the bar's edges and what it holds: 12dp top and bottom,
  /// 16dp either side. **In-plane only.**
  final EdgeInsets3d padding;
}

/// The bar across the bottom of a screen that holds actions rather than
/// destinations.
///
/// ```dart
/// Scaffold3d(
///   body: body,
///   bottomNavigationBar: BottomAppBar3d(
///     child: SceneRow3d(
///       children: <Widget>[
///         IconButton3d(icon: Icons.search, semanticLabel: 'Search', onPressed: search),
///         IconButton3d(icon: Icons.share, semanticLabel: 'Share', onPressed: share),
///       ],
///     ),
///   ),
/// )
/// ```
///
/// Flutter's `BottomAppBar`: an 80dp `surfaceContainer` bar at elevation
/// level 2, holding whatever it is given 12dp from its top and bottom and
/// 16dp from its sides. It goes where Flutter puts it, in
/// `Scaffold3d.bottomNavigationBar`, and it is `thickness.structural` for the
/// reason every bar is: the body's content passes behind it.
///
/// ## The safe area
///
/// It grows by the part of the surface the platform has spent at the
/// bottom, and keeps its content clear of it — Flutter's `SafeArea` inside
/// the bar, which is what `NavigationBar3d` does too. On a surface that does
/// not stand in for the view the inset is zero and none of this does
/// anything.
///
/// ## No notch, and why that is Material 3's default too
///
/// Flutter's Material 3 bar is shaped by an `AutomaticNotchedShape` around a
/// plain rectangle with no guest shape, which cuts no notch at all; the
/// notch around a docked floating action button is a Material 2 picture. It
/// is also one this package could not draw: a notch is a hole cut out of a
/// panel, and a panel here can be rounded at its corners and cut by convex
/// planes, neither of which is a hole. So there is no `shape`.
///
/// Nor is there Flutter's `FloatingActionButtonLocation.endContained`, which
/// sits a button inside the bar: `Scaffold3d` puts its button at Flutter's
/// default `endFloat`, above whatever bar is at the bottom.
///
/// ## What it announces
///
/// Nothing, as Flutter's announces nothing: a bar of actions is the actions,
/// and each of them names itself.
class BottomAppBar3d extends StatelessWidget {
  /// Creates a bottom app bar.
  const BottomAppBar3d({
    super.key,
    this.color,
    this.elevation,
    this.height,
    this.padding,
    this.style,
    this.child,
  });

  /// The bar's colour, or null for the style's `surfaceContainer`.
  final Color? color;

  /// How far the bar stands off the screen, in logical pixels, or null for
  /// the style's level 2.
  final double? elevation;

  /// How tall the bar is before the safe area, in logical pixels, or null
  /// for the style's 80.
  final double? height;

  /// Space between the bar's edges and [child], or null for the style's.
  final EdgeInsetsGeometry3d? padding;

  /// The whole token set, or null for `BottomAppBarStyle3d.of(theme)`.
  final BottomAppBarStyle3d? style;

  /// What the bar holds: usually a row of `IconButton3d`s.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? BottomAppBarStyle3d.of(theme);
    final inset = MediaQuery3d.of(context).padding;

    return SceneSizedBox3d(
      height: metrics.dp(
        (height ?? resolved.height) + inset.top + inset.bottom,
      ),
      child: Material3d(
        color: color ?? resolved.container,
        contentColor: resolved.contentColor,
        shape: theme.shape.none,
        elevation: elevation ?? resolved.elevation,
        thickness: resolved.thickness,
        // `_BottomAppBarDefaultsM3` tints with transparent: the container
        // token already says how raised the bar is.
        surfaceTint: const Color(0x00000000),
        alignment: null,
        child: SceneSafeArea3d(
          child: ScenePadding3d(
            padding: metrics.dpInsets(padding ?? resolved.padding),
            child: child,
          ),
        ),
      ),
    );
  }
}
