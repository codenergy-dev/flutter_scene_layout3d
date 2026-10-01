import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d, EdgeInsetsDirectional3d, EdgeInsetsGeometry3d;

import '../theme/theme_data.dart';
import '../tokens/depth.dart';
import '../tokens/typography.dart';

/// Everything a [SegmentedButton3d] is made of.
///
/// Flutter's `_SegmentedButtonDefaultsM3`, resolved, with the two figures it
/// borrows from `TextButton` — a segment *is* a text button there — and the
/// three this package adds because a segment is a slab. The colours are the
/// defaults' getters; the 48dp the button lays out at, the equal segments
/// and each segment's padding are read off a laid-out `SegmentedButton` in
/// `test/phase_5_defaults_test.dart`, which is the grade that catches a
/// change upstream as well as one here.
///
/// Every figure is in **logical pixels**.
@immutable
class SegmentedButtonStyle3d {
  /// Creates a segmented button style. Every field is required, for the
  /// reason `CardStyle3d`'s are.
  const SegmentedButtonStyle3d({
    required this.selectedContainer,
    required this.content,
    required this.selectedContent,
    required this.disabledContent,
    required this.outline,
    required this.disabledOutline,
    required this.outlineWidth,
    required this.shape,
    required this.height,
    required this.tapTargetHeight,
    required this.minimumSegmentWidth,
    required this.padding,
    required this.iconPadding,
    required this.iconSize,
    required this.iconGap,
    required this.labelStyle,
    required this.thickness,
    required this.outlineThickness,
    required this.outlineDepthStep,
  }) : assert(outlineWidth >= 0.0),
       assert(height > 0.0),
       assert(tapTargetHeight >= height),
       assert(minimumSegmentWidth >= 0.0),
       assert(iconSize > 0.0),
       assert(thickness >= 0.0),
       assert(outlineThickness >= 0.0),
       assert(
         outlineDepthStep > (thickness + outlineThickness) / 2.0,
         'The outline stands in front of the segments, and a step no larger '
         'than the mean of the two thicknesses leaves them fighting where '
         'they overlap.',
       );

  /// The style Material publishes, out of [theme]'s tokens.
  factory SegmentedButtonStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return SegmentedButtonStyle3d(
      selectedContainer: scheme.secondaryContainer,
      content: scheme.onSurface,
      selectedContent: scheme.onSecondaryContainer,
      disabledContent: scheme.disabledContent,
      outline: scheme.outline,
      disabledOutline: scheme.disabledContainer,
      outlineWidth: 1.0,
      shape: theme.shape.full,
      height: 40.0,
      tapTargetHeight: 48.0,
      minimumSegmentWidth: 64.0,
      padding: const EdgeInsetsDirectional3d.only(
        start: 12.0,
        top: 8.0,
        end: 12.0,
        bottom: 8.0,
      ),
      iconPadding: const EdgeInsetsDirectional3d.only(
        start: 12.0,
        top: 8.0,
        end: 16.0,
        bottom: 8.0,
      ),
      iconSize: 18.0,
      iconGap: 8.0,
      labelStyle: Typography3dToken.labelLarge,
      thickness: theme.thickness.standard,
      outlineThickness: theme.thickness.thin,
      outlineDepthStep: Thickness3d.stepOver(
        theme.thickness.standard,
        theme.thickness.thin,
      ),
    );
  }

  /// A chosen segment's fill: `secondaryContainer`.
  ///
  /// An unchosen one has none, and a disabled one has none whether it is
  /// chosen or not — Flutter's `backgroundColor` resolves disabled to null
  /// before it looks at selected, and the check is what is left to say so.
  final Color selectedContainer;

  /// An unchosen segment's label, icon and wash: `onSurface`.
  final Color content;

  /// A chosen segment's label, icon and wash: `onSecondaryContainer`.
  final Color selectedContent;

  /// A disabled segment's label and icon: `onSurface` at 38%.
  final Color disabledContent;

  /// The outline and the rules between segments: `outline`.
  final Color outline;

  /// The outline of a disabled button: `onSurface` at 12%.
  final Color disabledOutline;

  /// How thick the outline and the rules are: 1dp.
  final double outlineWidth;

  /// The outline's corners: `shape.full`, a stadium. The end segments are
  /// carved with it on their outer corners.
  final BorderRadius3d shape;

  /// How tall the outlined part is: 40dp.
  final double height;

  /// How tall the button lays out: 48dp, the outline centred in it.
  ///
  /// **In the layout, as Flutter's is**, rather than in a `TapTarget3d`'s
  /// reach the way every other control here has it. A press in a reach's
  /// margin arrives at the control's centre, and the centre of a button of
  /// three segments is the middle one — so a press 4dp above the first
  /// would pick the second. Laid out 48dp tall, each segment's own target is
  /// inside a slot of that height and is re-aimed at its own centre.
  final double tapTargetHeight;

  /// The narrowest a segment may be: 64dp, a `TextButton`'s minimum.
  final double minimumSegmentWidth;

  /// Space around a segment's label: `TextButton`'s 12 by 8.
  final EdgeInsetsGeometry3d padding;

  /// Space around a segment with an icon in it: 12 at the start, 16 at the
  /// end and 8 above and below, `TextButton.icon`'s, which Flutter copies
  /// into the segment by hand.
  final EdgeInsetsGeometry3d iconPadding;

  /// How tall an icon in a segment is, the check included: 18dp.
  final double iconSize;

  /// The gap between an icon and the label after it: 8dp.
  final double iconGap;

  /// The type role a segment's label takes: `labelLarge`.
  final Typography3dToken labelStyle;

  /// How deep a segment's slab is: `thickness.standard`, a button's.
  final double thickness;

  /// How deep the outline's slab is: `thickness.thin`.
  final double outlineThickness;

  /// How far in front of the segments the outline stands.
  ///
  /// Flutter paints the border after its children, so a chosen segment's
  /// fill is under the outline's band. Here the outline is a transparent
  /// slab of its own drawn in front, and this is
  /// `Thickness3d.stepOver(thickness, outlineThickness)`.
  final double outlineDepthStep;

  /// This style with the given fields replaced.
  SegmentedButtonStyle3d copyWith({
    Color? selectedContainer,
    Color? content,
    Color? selectedContent,
    Color? disabledContent,
    Color? outline,
    Color? disabledOutline,
    double? outlineWidth,
    BorderRadius3d? shape,
    double? height,
    double? tapTargetHeight,
    double? minimumSegmentWidth,
    EdgeInsetsGeometry3d? padding,
    EdgeInsetsGeometry3d? iconPadding,
    double? iconSize,
    double? iconGap,
    Typography3dToken? labelStyle,
    double? thickness,
    double? outlineThickness,
    double? outlineDepthStep,
  }) => SegmentedButtonStyle3d(
    selectedContainer: selectedContainer ?? this.selectedContainer,
    content: content ?? this.content,
    selectedContent: selectedContent ?? this.selectedContent,
    disabledContent: disabledContent ?? this.disabledContent,
    outline: outline ?? this.outline,
    disabledOutline: disabledOutline ?? this.disabledOutline,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    shape: shape ?? this.shape,
    height: height ?? this.height,
    tapTargetHeight: tapTargetHeight ?? this.tapTargetHeight,
    minimumSegmentWidth: minimumSegmentWidth ?? this.minimumSegmentWidth,
    padding: padding ?? this.padding,
    iconPadding: iconPadding ?? this.iconPadding,
    iconSize: iconSize ?? this.iconSize,
    iconGap: iconGap ?? this.iconGap,
    labelStyle: labelStyle ?? this.labelStyle,
    thickness: thickness ?? this.thickness,
    outlineThickness: outlineThickness ?? this.outlineThickness,
    outlineDepthStep: outlineDepthStep ?? this.outlineDepthStep,
  );

  @override
  bool operator ==(Object other) =>
      other is SegmentedButtonStyle3d &&
      other.selectedContainer == selectedContainer &&
      other.content == content &&
      other.selectedContent == selectedContent &&
      other.disabledContent == disabledContent &&
      other.outline == outline &&
      other.disabledOutline == disabledOutline &&
      other.outlineWidth == outlineWidth &&
      other.shape == shape &&
      other.height == height &&
      other.tapTargetHeight == tapTargetHeight &&
      other.minimumSegmentWidth == minimumSegmentWidth &&
      other.padding == padding &&
      other.iconPadding == iconPadding &&
      other.iconSize == iconSize &&
      other.iconGap == iconGap &&
      other.labelStyle == labelStyle &&
      other.thickness == thickness &&
      other.outlineThickness == outlineThickness &&
      other.outlineDepthStep == outlineDepthStep;

  @override
  int get hashCode => Object.hash(
    selectedContainer,
    content,
    selectedContent,
    disabledContent,
    outline,
    disabledOutline,
    outlineWidth,
    shape,
    height,
    tapTargetHeight,
    minimumSegmentWidth,
    padding,
    iconPadding,
    iconSize,
    iconGap,
    labelStyle,
    thickness,
    outlineThickness,
    outlineDepthStep,
  );

  @override
  String toString() =>
      'SegmentedButtonStyle3d(${height}dp in ${tapTargetHeight}dp, '
      '$selectedContainer)';
}
