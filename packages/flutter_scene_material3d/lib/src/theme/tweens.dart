import 'package:flutter/animation.dart' show Tween;

import '../tokens/color_scheme.dart';
import '../tokens/depth.dart';
import '../tokens/shape.dart';
import '../tokens/typography.dart';
import 'theme_data.dart';

/// Interpolates between two colour schemes.
///
/// Every token family here carries a static `lerp`, so a tween is a two-line
/// adapter onto Flutter's [Tween] — the same shape `flutter_scene_layout3d`'s
/// `BoxDecoration3dTween` and friends have, and for the same reason: an
/// application driving an `AnimationController` writes
/// `tween.animate(controller)` rather than reaching for the `lerp` by hand,
/// and the implicit animation machinery already knows what to do with a
/// [Tween].
class ColorScheme3dTween extends Tween<ColorScheme3d> {
  /// Creates a tween between two schemes.
  ColorScheme3dTween({super.begin, super.end});

  @override
  ColorScheme3d lerp(double t) => ColorScheme3d.lerp(begin!, end!, t);
}

/// Interpolates between two type scales.
///
/// **This one relayouts.** A font size decides a label's box, so every frame
/// of a typography animation re-measures every label under the theme. See
/// [Typography3d.lerp].
class Typography3dTween extends Tween<Typography3d> {
  /// Creates a tween between two type scales.
  Typography3dTween({super.begin, super.end});

  @override
  Typography3d lerp(double t) => Typography3d.lerp(begin!, end!, t);
}

/// Interpolates between two shape scales.
class ShapeScale3dTween extends Tween<ShapeScale3d> {
  /// Creates a tween between two shape scales.
  ShapeScale3dTween({super.begin, super.end});

  @override
  ShapeScale3d lerp(double t) => ShapeScale3d.lerp(begin!, end!, t);
}

/// Interpolates between two elevation scales.
class Elevation3dTween extends Tween<Elevation3d> {
  /// Creates a tween between two elevation scales.
  Elevation3dTween({super.begin, super.end});

  @override
  Elevation3d lerp(double t) => Elevation3d.lerp(begin!, end!, t);
}

/// Interpolates between two thickness scales.
class Thickness3dTween extends Tween<Thickness3d> {
  /// Creates a tween between two thickness scales.
  Thickness3dTween({super.begin, super.end});

  @override
  Thickness3d lerp(double t) => Thickness3d.lerp(begin!, end!, t);
}

/// Interpolates between two whole themes.
///
/// The tween a light-to-dark transition is written with:
///
/// ```dart
/// final theme = Theme3dDataTween(
///   begin: Theme3dData.light,
///   end: Theme3dData.dark,
/// ).animate(controller);
///
/// // Rebuilding the SceneTheme3d with theme.value writes the owner slot,
/// // which relayouts the subtree. That is a screen transition, not an
/// // interaction: a control lighting up under a pointer animates its own
/// // decoration instead and touches no layout at all.
/// ```
class Theme3dDataTween extends Tween<Theme3dData> {
  /// Creates a tween between two themes.
  Theme3dDataTween({super.begin, super.end});

  @override
  Theme3dData lerp(double t) => Theme3dData.lerp(begin!, end!, t);
}
