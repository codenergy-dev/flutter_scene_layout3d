import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d, EdgeInsetsDirectional3d, Motion3d, Offset3d;

import '../theme/theme_data.dart';
import '../tokens/typography.dart';
import 'overlay_style.dart';

/// Everything a [Drawer3d] is made of: the surface, and the scrim and the
/// clock it arrives on when [showDrawer3d] opens it.
///
/// `_DrawerDefaultsM3`'s figures, Flutter's `_kWidth` and the scrim its
/// `DrawerController` draws. The width, the colour and the elevation are
/// read off a real `Drawer` in `test/phase_4_defaults_test.dart`; the 16dp
/// corner is hard-coded in Flutter with a note that there is no token for
/// it, and is transcribed.
///
/// Every figure is in **logical pixels**.
@immutable
class DrawerStyle3d {
  /// Creates a drawer style. Every field is required, for the reason
  /// `CardStyle3d`'s are.
  const DrawerStyle3d({
    required this.container,
    required this.contentColor,
    required this.width,
    required this.cornerRadius,
    required this.elevation,
    required this.thickness,
    required this.scrimColor,
    required this.scrimThickness,
    required this.arrival,
  }) : assert(width >= 0.0),
       assert(cornerRadius >= 0.0),
       assert(elevation >= 0.0),
       assert(thickness >= 0.0),
       assert(scrimThickness >= 0.0);

  /// The style Material publishes, out of [theme]'s tokens.
  factory DrawerStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return DrawerStyle3d(
      container: scheme.surfaceContainerLow,
      contentColor: scheme.onSurface,
      width: 304.0,
      cornerRadius: theme.shape.large.topLeft,
      elevation: theme.elevation.level1,
      thickness: theme.thickness.structural,
      // Flutter's drawer dims with `Colors.black54`, not with Material's 32%
      // scrim: a drawer darkens the screen more than a dialog does, and a
      // port should not see the difference. The alpha is coverage here, as
      // every scrim's is — see `scrimCoverage3d`.
      scrimColor: scheme.scrim.withValues(alpha: 0x8A / 0xFF),
      scrimThickness: theme.thickness.thin,
      // Flutter's `_kBaseSettleDuration` is 246ms, and it opens with a
      // critically damped spring rather than a curve. `medium1` is the token
      // nearest the figure and the emphasized pair the catalogue's word for
      // the motion; the direction is the edge's, set by `showDrawer3d`.
      arrival: Arrival3d.symmetric(
        motion: const Motion3d(fraction: Offset3d(-1, 0, 0)),
        duration: theme.motion.medium1,
        curve: theme.motion.emphasizedDecelerate,
        reverseCurve: theme.motion.emphasizedAccelerate,
      ),
    );
  }

  /// The surface's colour: `surfaceContainerLow`.
  final Color container;

  /// The colour of what is drawn on it: `onSurface`.
  final Color contentColor;

  /// How wide a drawer is: Flutter's 304dp.
  ///
  /// Material's own specification says 360dp. A ported screen was laid out
  /// against Flutter's figure, so that is the one here.
  final double width;

  /// The radius of the two corners away from the edge the drawer is against:
  /// 16dp, which is `shape.large`.
  final double cornerRadius;

  /// How far the drawer stands off whatever it is in front of: level 1, 1dp.
  final double elevation;

  /// How deep the slab is: `thickness.structural`, 8dp. A drawer is structure
  /// that has slid into view, as a sheet is.
  final double thickness;

  /// The scrim's colour: `scrim` at Flutter's `Colors.black54` alpha,
  /// `0x8A`, which is a hair over 54%.
  ///
  /// **The alpha is how much of the screen the scrim covers**, not how much
  /// it blends; see `scrimCoverage3d`.
  final Color scrimColor;

  /// How deep the scrim's slab is: `thickness.thin`, 1dp.
  final double scrimThickness;

  /// How the drawer arrives and leaves: 250ms each way. The [Arrival3d.motion]
  /// here is the left-to-right start edge's; `showDrawer3d` turns it to the
  /// edge the drawer is actually on.
  final Arrival3d arrival;

  /// The corners a drawer against its [leftEdge] or right edge is rounded
  /// at: the two away from that edge.
  BorderRadius3d shapeFor({required bool leftEdge}) => leftEdge
      ? BorderRadius3d.horizontal(right: cornerRadius)
      : BorderRadius3d.horizontal(left: cornerRadius);
}

/// Everything a [NavigationDrawer3d]'s destinations are made of.
///
/// `_NavigationDrawerDefaultsM3`'s figures and the gaps Flutter's
/// destination writes inline: 16dp before the icon and 12dp after it, a
/// 56dp tile with 12dp either side of it. Read off a real
/// `NavigationDrawer` in `test/phase_4_defaults_test.dart` where the laid-out
/// widget says them, and transcribed where only the source does.
///
/// Every figure is in **logical pixels**.
@immutable
class NavigationDrawerStyle3d {
  /// Creates a navigation drawer style. Every field is required.
  const NavigationDrawerStyle3d({
    required this.indicatorColor,
    required this.indicatorShape,
    required this.contentColor,
    required this.selectedContentColor,
    required this.labelStyle,
    required this.tileHeight,
    required this.tilePadding,
    required this.iconInset,
    required this.labelGap,
    required this.destinationThickness,
  }) : assert(tileHeight >= 0.0),
       assert(iconInset >= 0.0),
       assert(labelGap >= 0.0),
       assert(destinationThickness >= 0.0);

  /// The style Material publishes, out of [theme]'s tokens.
  factory NavigationDrawerStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return NavigationDrawerStyle3d(
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: theme.shape.full,
      contentColor: scheme.onSurfaceVariant,
      selectedContentColor: scheme.onSecondaryContainer,
      labelStyle: Typography3dToken.labelLarge,
      tileHeight: 56.0,
      tilePadding: const EdgeInsetsDirectional3d.only(start: 12, end: 12),
      iconInset: 16.0,
      labelGap: 12.0,
      destinationThickness: theme.thickness.thin,
    );
  }

  /// The selected destination's colour: `secondaryContainer`.
  ///
  /// **It is the destination's own colour, not a second slab.** Flutter's
  /// indicator is a 336 by 56 pill in a tile 280 wide, so it fills the tile;
  /// here the tile's own surface takes this colour when it is selected, and
  /// there is no pill to step the icon in front of.
  final Color indicatorColor;

  /// The tile's corners: `shape.full`, a stadium, which is the indicator's
  /// shape and the ink's.
  final BorderRadius3d indicatorShape;

  /// An unselected destination's icon and label: `onSurfaceVariant`.
  final Color contentColor;

  /// The selected destination's icon and label: `onSecondaryContainer`.
  final Color selectedContentColor;

  /// The label's type: `labelLarge`.
  final Typography3dToken labelStyle;

  /// How tall a destination is: 56dp, which is past Material's 48dp minimum
  /// target on its own.
  final double tileHeight;

  /// Space either side of a destination, inside the drawer: 12dp.
  final EdgeInsetsDirectional3d tilePadding;

  /// Space before the icon, inside the tile: 16dp.
  final double iconInset;

  /// Space between the icon and the label: 12dp.
  final double labelGap;

  /// How deep a destination's own slab is: `thickness.thin`, 1dp.
  ///
  /// A destination is a surface of its own for the reason a navigation bar's
  /// is: an `InkWell3d` washes the **enclosing** `Material3d`, and one placed
  /// straight on the drawer would light the whole drawer up.
  final double destinationThickness;
}
