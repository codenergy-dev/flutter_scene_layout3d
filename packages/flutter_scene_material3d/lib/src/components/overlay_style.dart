import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d, EdgeInsets3d;

import '../theme/theme_data.dart';
import '../tokens/typography.dart';

// The token sets of the overlays: a dialog, a menu, a snack bar, a tooltip
// and a sheet.
//
// Material publishes a container colour, a shape, an elevation and a padding
// for each of them. It publishes nothing about **how far in front** any of
// them sits, because on a screen that is paint order. Here it is geometry: an
// overlay is a slab carried over a screen that is itself a stack of slabs, and
// a lift that does not clear all of them loses the depth test in patches.
//
// So no style here carries a lift. There is one answer for all of them and it
// belongs where the screen's own depths are stated —
// `Scaffold3d.overlayLift(theme.thickness.depthStep)` — rather than five
// numbers that happen to agree today.

/// Everything a [Dialog3d] is made of.
///
/// Checked against Flutter's own `Dialog` defaults in
/// `test/overlay_defaults_test.dart`, which reads the `Material` a real
/// `Dialog` renders: `_DialogDefaultsM3` is private and `DialogTheme.of`
/// answers with an application's overrides rather than the resolved defaults.
/// That is the weaker of the drift-alarm lanes this package uses, and the
/// figures it cannot reach — the 560dp maximum width, which is an M3 spec
/// figure Flutter does not enforce — are transcriptions and say so.
///
/// Every figure is in **logical pixels**.
@immutable
class DialogStyle3d {
  /// Creates a dialog style. Every field is required, for the reason
  /// `CardStyle3d`'s are: a half-stated style is a surface drawing in a
  /// colour nobody chose.
  const DialogStyle3d({
    required this.container,
    required this.contentColor,
    required this.shape,
    required this.elevation,
    required this.thickness,
    required this.padding,
    required this.insetPadding,
    required this.minWidth,
    required this.maxWidth,
    required this.scrimColor,
    required this.scrimThickness,
    required this.textStyle,
  }) : assert(elevation >= 0.0),
       assert(thickness >= 0.0),
       assert(minWidth >= 0.0),
       assert(maxWidth >= minWidth),
       assert(scrimThickness >= 0.0);

  /// The style Material publishes, out of [theme]'s tokens.
  factory DialogStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return DialogStyle3d(
      container: scheme.surfaceContainerHigh,
      contentColor: scheme.onSurface,
      shape: theme.shape.extraLarge,
      elevation: theme.elevation.level3,
      thickness: theme.thickness.raised,
      padding: const EdgeInsets3d.symmetric(horizontal: 24, vertical: 24),
      insetPadding: const EdgeInsets3d.symmetric(horizontal: 40, vertical: 24),
      minWidth: 280.0,
      maxWidth: 560.0,
      // Material's scrim is black at 32%, and here that alpha reaches the
      // panel shader, which blends. What it is *not* is a wash over a display
      // list: see the scrim discussion on `Dialog3d`.
      scrimColor: scheme.scrim.withValues(alpha: 0.32),
      scrimThickness: theme.thickness.thin,
      textStyle: Typography3dToken.bodyMedium,
    );
  }

  /// The slab's colour: `surfaceContainerHigh`.
  final Color container;

  /// The colour of the labels drawn on it.
  final Color contentColor;

  /// The corner radii: `shape.extraLarge`, 28dp.
  final BorderRadius3d shape;

  /// How far the dialog stands off the overlay: level 3, 6dp.
  final double elevation;

  /// How deep the slab is: `thickness.raised`, 4dp.
  final double thickness;

  /// Space between the dialog's faces and its child: 24dp all round in the
  /// plane.
  final EdgeInsets3d padding;

  /// The margin between the dialog and the edges of the overlay.
  final EdgeInsets3d insetPadding;

  /// The narrowest a dialog may be: Flutter's own 280dp.
  final double minWidth;

  /// The widest: M3's 560dp, transcribed — Flutter's `Dialog` does not
  /// enforce a maximum of its own.
  final double maxWidth;

  /// The scrim's colour: `scrim` at 32% alpha, Material's own figure.
  final Color scrimColor;

  /// How deep the scrim's slab is: `thickness.thin`, 1dp.
  ///
  /// **A scrim is a slab, not an alpha wash**, which is what `ModalBarrier3d`
  /// says about itself. A zero-depth one would be coplanar with whatever it
  /// is drawn over, which is the same z-fight `Divider3d` exists to avoid.
  final double scrimThickness;

  /// The type the dialog's content inherits.
  final Typography3dToken textStyle;
}

/// Everything a [Menu3d] and its items are made of.
///
/// The figures are Flutter's popup-menu constants — 112dp and 280dp are its
/// `_kMenuMinWidth` and `_kMenuMaxWidth`, 48dp its `_kMenuItemHeight`, 8dp its
/// `_kMenuVerticalPadding` — and the container, elevation and shape are
/// `_PopupMenuDefaultsM3`'s. `test/overlay_defaults_test.dart` reads what it
/// can off a real `PopupMenuButton` and says which of these are
/// transcriptions.
@immutable
class MenuStyle3d {
  /// Creates a menu style.
  const MenuStyle3d({
    required this.container,
    required this.contentColor,
    required this.shape,
    required this.elevation,
    required this.thickness,
    required this.padding,
    required this.minWidth,
    required this.maxWidth,
    required this.itemHeight,
    required this.itemPadding,
    required this.itemThickness,
    required this.itemDepthStep,
    required this.itemTextStyle,
  }) : assert(elevation >= 0.0),
       assert(thickness >= 0.0),
       assert(maxWidth >= minWidth),
       assert(
         itemDepthStep > itemThickness,
         'A menu item lifted by less than its own depth still has a face on '
         'the menu it is drawn on, and two coplanar surfaces z-fight.',
       );

  /// The style Material publishes, out of [theme]'s tokens.
  factory MenuStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return MenuStyle3d(
      container: scheme.surfaceContainer,
      contentColor: scheme.onSurface,
      shape: theme.shape.extraSmall,
      elevation: theme.elevation.level2,
      thickness: theme.thickness.raised,
      padding: const EdgeInsets3d.symmetric(vertical: 8),
      minWidth: 112.0,
      maxWidth: 280.0,
      itemHeight: 48.0,
      itemPadding: const EdgeInsets3d.symmetric(horizontal: 12),
      itemThickness: theme.thickness.thin,
      itemDepthStep: 2 * theme.thickness.thin,
      itemTextStyle: Typography3dToken.labelLarge,
    );
  }

  /// The slab's colour: `surfaceContainer`.
  final Color container;

  /// The colour of the item labels.
  final Color contentColor;

  /// The corner radii: `shape.extraSmall`, 4dp.
  final BorderRadius3d shape;

  /// How far the menu stands off the overlay: level 2, 3dp.
  final double elevation;

  /// How deep the slab is: `thickness.raised`, 4dp.
  final double thickness;

  /// Space above and below the item list: 8dp.
  final EdgeInsets3d padding;

  /// The narrowest a menu may be: 112dp.
  final double minWidth;

  /// The widest: 280dp.
  final double maxWidth;

  /// How tall one item is: 48dp, which is also Material's minimum target, so
  /// a menu item needs no reach beyond its own extent.
  final double itemHeight;

  /// Space between an item's edges and its label: 12dp horizontally.
  final EdgeInsets3d itemPadding;

  /// How deep one item's own slab is: `thickness.thin`, 1dp.
  ///
  /// An item needs a surface of its own, for the reason a navigation
  /// destination does: an `InkWell3d` washes the *enclosing* `Material3d`, so
  /// an item without one would light the whole menu up under one finger.
  final double itemThickness;

  /// How far an item's slab stands off the menu's front face, in logical
  /// pixels: 2dp, twice [itemThickness].
  ///
  /// **Not zero, and not one.** A slab resting exactly on the menu's front
  /// face is coplanar with it and z-fights; a slab lifted by exactly its own
  /// depth has its *back* face there instead, which is the same fight seen
  /// from the other side. Twice the thickness clears both. The lift is an
  /// elevation, so it moves the geometry and never the layout.
  final double itemDepthStep;

  /// The type an item's label is drawn in.
  final Typography3dToken itemTextStyle;
}

/// Everything a [SnackBar3d] is made of.
///
/// Read off Flutter's `_SnackbarDefaultsM3` where it is reachable through a
/// real `SnackBar`'s rendered `Material`; the two durations are Flutter's own
/// private constants, transcribed, and the tests say so.
@immutable
class SnackBarStyle3d {
  /// Creates a snack bar style.
  const SnackBarStyle3d({
    required this.container,
    required this.contentColor,
    required this.actionColor,
    required this.shape,
    required this.elevation,
    required this.thickness,
    required this.padding,
    required this.actionPadding,
    required this.margin,
    required this.minHeight,
    required this.maxWidth,
    required this.displayDuration,
    required this.textStyle,
  }) : assert(elevation >= 0.0),
       assert(thickness >= 0.0);

  /// The style Material publishes, out of [theme]'s tokens.
  factory SnackBarStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return SnackBarStyle3d(
      container: scheme.inverseSurface,
      contentColor: scheme.onInverseSurface,
      actionColor: scheme.inversePrimary,
      shape: theme.shape.extraSmall,
      elevation: theme.elevation.level3,
      thickness: theme.thickness.raised,
      padding: const EdgeInsets3d.symmetric(horizontal: 16, vertical: 14),
      actionPadding: const EdgeInsets3d.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets3d.symmetric(horizontal: 16, vertical: 16),
      minHeight: 48.0,
      maxWidth: 600.0,
      displayDuration: const Duration(milliseconds: 4000),
      textStyle: Typography3dToken.bodyMedium,
    );
  }

  /// The slab's colour: `inverseSurface`, which is what makes a snack bar
  /// read as a message rather than as part of the screen.
  final Color container;

  /// The colour of the message: `onInverseSurface`.
  final Color contentColor;

  /// The colour of the action's label: `inversePrimary`.
  final Color actionColor;

  /// The corner radii: `shape.extraSmall`, 4dp.
  final BorderRadius3d shape;

  /// How far the bar stands off the overlay: level 3, 6dp.
  final double elevation;

  /// How deep the slab is: `thickness.raised`, 4dp.
  final double thickness;

  /// Space between the bar's edges and its content.
  final EdgeInsets3d padding;

  /// Space around the action's label, in the plane.
  ///
  /// A transcription: Flutter draws the action as a `TextButton` and its
  /// padding comes out of the button tables rather than out of a snack-bar
  /// token.
  final EdgeInsets3d actionPadding;

  /// Space between the bar and the edges of the overlay.
  final EdgeInsets3d margin;

  /// The shortest a single-line bar may be: 48dp.
  final double minHeight;

  /// The widest a bar may be: Flutter's floating maximum, 600dp.
  final double maxWidth;

  /// How long one message stays up: four seconds, Flutter's
  /// `_snackBarDisplayDuration`.
  final Duration displayDuration;

  /// The type the message is drawn in.
  final Typography3dToken textStyle;
}

/// Everything a [Tooltip3d] is made of.
///
/// Every figure here is a **transcription** of Material's tooltip spec and of
/// Flutter's private tooltip constants, and there is no accessor for any of
/// them; `test/tooltip_test.dart` states that plainly rather than pretending
/// to be a drift alarm it cannot be.
@immutable
class TooltipStyle3d {
  /// Creates a tooltip style.
  const TooltipStyle3d({
    required this.container,
    required this.contentColor,
    required this.shape,
    required this.elevation,
    required this.thickness,
    required this.padding,
    required this.verticalOffset,
    required this.waitDuration,
    required this.showDuration,
    required this.textStyle,
  }) : assert(elevation >= 0.0),
       assert(thickness >= 0.0);

  /// The style Material publishes, out of [theme]'s tokens.
  factory TooltipStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return TooltipStyle3d(
      container: scheme.inverseSurface,
      contentColor: scheme.onInverseSurface,
      shape: theme.shape.extraSmall,
      elevation: theme.elevation.level0,
      thickness: theme.thickness.thin,
      padding: const EdgeInsets3d.symmetric(horizontal: 8, vertical: 4),
      verticalOffset: 24.0,
      waitDuration: const Duration(milliseconds: 500),
      showDuration: const Duration(milliseconds: 1500),
      textStyle: Typography3dToken.bodySmall,
    );
  }

  /// The slab's colour: `inverseSurface`.
  final Color container;

  /// The colour of the label: `onInverseSurface`.
  final Color contentColor;

  /// The corner radii: `shape.extraSmall`, 4dp.
  final BorderRadius3d shape;

  /// How far the tooltip stands off the overlay: none. Material's plain
  /// tooltip is flat.
  final double elevation;

  /// How deep the slab is: `thickness.thin`, 1dp. A tooltip is the thinnest
  /// thing in the catalogue that is not a rule.
  final double thickness;

  /// Space between the tooltip's edges and its label.
  final EdgeInsets3d padding;

  /// How far below its anchor the tooltip sits: Flutter's
  /// `_defaultVerticalOffset`, 24dp.
  final double verticalOffset;

  /// How long a pointer rests before the tooltip appears.
  final Duration waitDuration;

  /// How long it stays after the pointer has left.
  final Duration showDuration;

  /// The type the label is drawn in.
  final Typography3dToken textStyle;
}

/// Everything a [BottomSheet3d] is made of.
///
/// Read off the `Material` a real `BottomSheet` renders where possible;
/// `_BottomSheetDefaultsM3`'s own figures are private.
@immutable
class BottomSheetStyle3d {
  /// Creates a sheet style.
  const BottomSheetStyle3d({
    required this.container,
    required this.contentColor,
    required this.shape,
    required this.elevation,
    required this.thickness,
    required this.maxWidth,
    required this.scrimColor,
    required this.scrimThickness,
    required this.textStyle,
  }) : assert(elevation >= 0.0),
       assert(thickness >= 0.0);

  /// The style Material publishes, out of [theme]'s tokens.
  factory BottomSheetStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return BottomSheetStyle3d(
      container: scheme.surfaceContainerLow,
      contentColor: scheme.onSurface,
      // Only the two corners away from the edge the sheet is anchored to are
      // rounded, which `BottomSheet3d` works out from its own alignment: a
      // sheet on the bottom rounds its top corners, one on the leading edge
      // rounds its trailing ones.
      shape: theme.shape.extraLarge,
      elevation: theme.elevation.level1,
      thickness: theme.thickness.structural,
      maxWidth: 640.0,
      scrimColor: scheme.scrim.withValues(alpha: 0.32),
      scrimThickness: theme.thickness.thin,
      textStyle: Typography3dToken.bodyMedium,
    );
  }

  /// The slab's colour: `surfaceContainerLow`.
  final Color container;

  /// The colour of the labels drawn on it.
  final Color contentColor;

  /// The corner radii of the two corners away from the anchored edge: 28dp.
  final BorderRadius3d shape;

  /// How far the sheet stands off the overlay: level 1, 1dp.
  final double elevation;

  /// How deep the slab is: `thickness.structural`, 8dp. A sheet is
  /// structure, like a bar, rather than a card.
  final double thickness;

  /// The widest a sheet may be: Flutter's 640dp.
  final double maxWidth;

  /// The scrim's colour, for a modal sheet.
  final Color scrimColor;

  /// How deep the scrim's slab is.
  final double scrimThickness;

  /// The type the sheet's content inherits.
  final Typography3dToken textStyle;
}
