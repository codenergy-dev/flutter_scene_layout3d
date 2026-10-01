import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;

import '../theme/theme_data.dart';
import '../tokens/depth.dart';

/// Everything a [LinearProgressIndicator3d] and a
/// [CircularProgressIndicator3d] are made of.
///
/// Flutter's `ProgressIndicatorThemeData`, resolved: one table for both
/// indicators, because Flutter keeps one for both and because they share
/// their colour and differ only in their shape.
///
/// ## Which Material 3
///
/// Flutter ships two, and picks the older by default — its `year2023` flag is
/// true unless an application says otherwise. That one is a 4dp bar with
/// square ends and a 4dp stroke on a 36dp circle with no track. The 2024 one
/// adds a gap between the bar and its track, a dot at the track's end, round
/// caps and a track behind the circle. **This table is the 2023 one**,
/// because it is what a ported screen already draws; nothing about the 2024
/// one is out of reach, and [circularTrackColor] is already the first half of
/// it.
///
/// Every figure is in logical pixels.
@immutable
class ProgressIndicatorStyle3d {
  /// Creates a progress indicator style. Every field is required, for the
  /// reason `ButtonStyle3d`'s are.
  const ProgressIndicatorStyle3d({
    required this.color,
    required this.linearTrackColor,
    required this.circularTrackColor,
    required this.linearMinHeight,
    required this.circularSize,
    required this.strokeWidth,
    required this.thickness,
    required this.depthStep,
  }) : assert(linearMinHeight > 0.0),
       assert(circularSize > 0.0),
       assert(strokeWidth > 0.0),
       assert(thickness >= 0.0),
       // The indicator stands in front of its track, and a slab lifted by
       // no more than half their thicknesses is coplanar with it.
       assert(depthStep > thickness);

  /// The style Material publishes, out of [theme]'s tokens.
  ///
  /// Checked in `test/progress_indicator_test.dart` against a real
  /// `LinearProgressIndicator` and `CircularProgressIndicator`: their sizes
  /// are measured off the laid-out widgets and their colours read off what
  /// they paint, because `_LinearProgressIndicatorDefaultsM3Year2023` and its
  /// sibling are private.
  factory ProgressIndicatorStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return ProgressIndicatorStyle3d(
      color: scheme.primary,
      linearTrackColor: scheme.secondaryContainer,
      circularTrackColor: null,
      linearMinHeight: defaultLinearMinHeight,
      circularSize: defaultCircularSize,
      strokeWidth: defaultStrokeWidth,
      thickness: theme.thickness.thin,
      depthStep: Thickness3d.stepOver(
        theme.thickness.thin,
        theme.thickness.thin,
      ),
    );
  }

  /// Material's bar height, in logical pixels: 4dp.
  static const double defaultLinearMinHeight = 4.0;

  /// The circle's extent, in logical pixels: Flutter's 36dp minimum.
  static const double defaultCircularSize = 36.0;

  /// The circle's stroke, in logical pixels: 4dp.
  static const double defaultStrokeWidth = 4.0;

  /// The colour of the part that shows progress: `primary`.
  final Color color;

  /// The bar's track: `secondaryContainer`.
  final Color linearTrackColor;

  /// The circle's track, or null for none — which is Flutter's 2023 default.
  ///
  /// When there is one it is the rest of the same ring as the arc, not a
  /// second slab behind it: the arc is where the ring's gradient is [color]
  /// and the track is where it is this, so the two cannot z-fight.
  final Color? circularTrackColor;

  /// How tall the bar is, in logical pixels.
  final double linearMinHeight;

  /// How wide and tall the circle's box is, in logical pixels.
  ///
  /// The stroke is **centred** on the box's circle, as Flutter's is, so the
  /// ring overhangs the box by half a stroke on every side: a 36dp indicator
  /// draws a 40dp ring. A ported screen lays out against the 36.
  final double circularSize;

  /// How thick the circle's stroke is, in logical pixels.
  final double strokeWidth;

  /// How deep the bar's and the ring's slabs are, in logical pixels:
  /// `thickness.thin`.
  final double thickness;

  /// How far the bar stands in front of its track, in logical pixels.
  ///
  /// [Thickness3d.stepOver] of the two, for the reason every stacked slab in
  /// this catalogue takes it.
  final double depthStep;

  /// This style with the given fields replaced.
  ///
  /// [circularTrackColor] cannot be cleared this way; construct a new style
  /// for that, the way `copyWith` on a nullable field always has to be used.
  ProgressIndicatorStyle3d copyWith({
    Color? color,
    Color? linearTrackColor,
    Color? circularTrackColor,
    double? linearMinHeight,
    double? circularSize,
    double? strokeWidth,
    double? thickness,
    double? depthStep,
  }) => ProgressIndicatorStyle3d(
    color: color ?? this.color,
    linearTrackColor: linearTrackColor ?? this.linearTrackColor,
    circularTrackColor: circularTrackColor ?? this.circularTrackColor,
    linearMinHeight: linearMinHeight ?? this.linearMinHeight,
    circularSize: circularSize ?? this.circularSize,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    thickness: thickness ?? this.thickness,
    depthStep: depthStep ?? this.depthStep,
  );

  @override
  bool operator ==(Object other) =>
      other is ProgressIndicatorStyle3d &&
      other.color == color &&
      other.linearTrackColor == linearTrackColor &&
      other.circularTrackColor == circularTrackColor &&
      other.linearMinHeight == linearMinHeight &&
      other.circularSize == circularSize &&
      other.strokeWidth == strokeWidth &&
      other.thickness == thickness &&
      other.depthStep == depthStep;

  @override
  int get hashCode => Object.hash(
    color,
    linearTrackColor,
    circularTrackColor,
    linearMinHeight,
    circularSize,
    strokeWidth,
    thickness,
    depthStep,
  );

  @override
  String toString() =>
      'ProgressIndicatorStyle3d($color on $linearTrackColor, '
      '${linearMinHeight}dp bar, ${circularSize}dp circle)';
}
