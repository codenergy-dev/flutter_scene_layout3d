import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show AlignmentDirectional3d, AlignmentGeometry3d, EdgeInsets3d, Offset3d;

import '../theme/theme_data.dart';
import '../tokens/depth.dart';
import '../tokens/typography.dart';
import 'icon.dart';
import 'material.dart';

/// Everything a [Badge3d] is made of.
///
/// Flutter's `BadgeThemeData`, resolved. The sizes, the padding and the
/// alignment are `_BadgeDefaultsM3`'s constructor figures and the colours its
/// getters; `test/phase_4_defaults_test.dart` reads them off a real `Badge`
/// — the colours and sizes from the laid-out widget, the offset from its
/// public documentation — rather than trusting this transcription.
///
/// Every figure is in **logical pixels**.
@immutable
class BadgeStyle3d {
  /// Creates a badge style. Every field is required, for the reason
  /// `CardStyle3d`'s are: a half-stated style is a badge drawing in a colour
  /// nobody chose.
  const BadgeStyle3d({
    required this.backgroundColor,
    required this.textColor,
    required this.smallSize,
    required this.largeSize,
    required this.padding,
    required this.alignment,
    required this.offset,
    required this.textStyle,
    required this.thickness,
    required this.depthStep,
  }) : assert(smallSize >= 0.0),
       assert(largeSize >= 0.0),
       assert(thickness >= 0.0),
       assert(
         depthStep > thickness,
         'A badge lifted by no more than its own thickness has a face on the '
         'plane of whatever it decorates, and two coplanar surfaces z-fight.',
       );

  /// The style Material publishes, out of [theme]'s tokens.
  factory BadgeStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return BadgeStyle3d(
      backgroundColor: scheme.error,
      textColor: scheme.onError,
      smallSize: 6.0,
      largeSize: 16.0,
      padding: const EdgeInsets3d.symmetric(horizontal: 4.0),
      alignment: AlignmentDirectional3d.topEnd,
      offset: const Offset3d(4.0, -4.0, 0.0),
      textStyle: Typography3dToken.labelSmall,
      thickness: theme.thickness.thin,
      depthStep: depthStepOver(theme),
    );
  }

  /// How far in front of what it decorates a badge stands, by default: clear
  /// of a 24dp icon's glyph wall, of the lift that icon has off the surface
  /// it is on, and then by the catalogue's usual step.
  ///
  /// **An icon is not flat here.** A glyph is a slab whose wall grows toward
  /// the viewer by a tenth of its font size — `AtlasText3dRenderer.depthFactor`
  /// — so a 24dp icon's corner reaches 2.4dp in front of its own plane, and a
  /// badge resting on that plane would have the icon standing through it.
  /// Flutter paints a badge after its child and needs none of this.
  static double depthStepOver(Theme3dData theme) =>
      Icon3d.defaultSize * iconWallFactor +
      Material3d.contentLift +
      Thickness3d.stepOver(theme.thickness.thin, theme.thickness.thin);

  /// The share of an icon's size its glyph wall reaches toward the viewer:
  /// `AtlasText3dRenderer`'s default `depthFactor`, which a test checks is
  /// still what the renderer uses.
  static const double iconWallFactor = 0.10;

  /// The stadium's colour: `error`.
  final Color backgroundColor;

  /// The label's colour: `onError`.
  final Color textColor;

  /// The diameter of a badge with no label: 6dp.
  final double smallSize;

  /// The height of a badge with a label, and its narrowest width: 16dp.
  final double largeSize;

  /// Space either side of the label, in the plane: 4dp.
  final EdgeInsets3d padding;

  /// Which corner of its child a badge sits at: the top end, which is the
  /// top left in right to left.
  final AlignmentGeometry3d alignment;

  /// How far a labelled badge is moved from that corner, in the plane, with
  /// x toward the **end**: Flutter's public default of 4 across and 4 up.
  ///
  /// Mirrored in right to left, as Flutter's is. Flutter also moves a
  /// labelled badge down by 8dp on top of whatever this says, to keep the
  /// placement its users had before it changed the arithmetic, and then up
  /// by half the badge's own height; [Badge3d] does both, so a 16dp badge
  /// overhangs its child's top-end corner by 4dp each way. A badge with no
  /// label ignores this and sits inside the corner.
  final Offset3d offset;

  /// The type the label is drawn in: `labelSmall`.
  final Typography3dToken textStyle;

  /// How deep the stadium's slab is: `thickness.thin`, 1dp.
  final double thickness;

  /// How far in front of its child the badge stands; see [depthStepOver].
  final double depthStep;

  /// This style with the given fields replaced.
  BadgeStyle3d copyWith({
    Color? backgroundColor,
    Color? textColor,
    double? smallSize,
    double? largeSize,
    EdgeInsets3d? padding,
    AlignmentGeometry3d? alignment,
    Offset3d? offset,
    Typography3dToken? textStyle,
    double? thickness,
    double? depthStep,
  }) => BadgeStyle3d(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    textColor: textColor ?? this.textColor,
    smallSize: smallSize ?? this.smallSize,
    largeSize: largeSize ?? this.largeSize,
    padding: padding ?? this.padding,
    alignment: alignment ?? this.alignment,
    offset: offset ?? this.offset,
    textStyle: textStyle ?? this.textStyle,
    thickness: thickness ?? this.thickness,
    depthStep: depthStep ?? this.depthStep,
  );
}
