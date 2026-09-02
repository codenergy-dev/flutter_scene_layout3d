import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Constraints3d,
        Layout3d,
        Layout3dMetrics,
        Layout3dSlot,
        VisualDensity3d;

import '../tokens/color_scheme.dart';
import '../tokens/depth.dart';
import '../tokens/shape.dart';
import '../tokens/state_layer.dart';
import '../tokens/typography.dart';

/// Every token a component reads, in one value.
///
/// Six families and a density. A component asks the theme for a token and
/// the metrics for a conversion, in that order and never the other way round:
///
/// ```dart
/// // Inside performLayout, with no BuildContext anywhere.
/// final theme = theme3d;                       // tokens, in logical pixels
/// final height = metrics.dp(40);               // logical pixels to units
/// ```
///
/// **That one-way arrow is the discipline this class exists to enforce.** The
/// theme turns a *name* into a dp figure — `shape.medium`, `elevation.level1`,
/// `thickness.raised` — and `Layout3dMetrics` turns a dp figure into world
/// units. A component that reads a Material number off the metrics, or that
/// stores world units in a token, has mixed the two frames, and the failure
/// is silent: everything looks right at the default scale of 0.01 units per
/// logical pixel and comes apart on a surface bound to a camera.
///
/// ## Both halves of the channel
///
/// A theme has to reach two layers that do not share a mechanism:
///
///  * **The widget layer** reads it as `Theme3d.of(context)`, an ordinary
///    inherited widget.
///  * **The imperative layer** has no `BuildContext` — a `Layout3d` is not a
///    widget and `performLayout` is not a build — so it reads it out of the
///    owner's slot, as [slot], which is what `Layout3dSlot` was added to
///    `flutter_scene_layout3d` for. `SceneTheme3d` writes both at once.
///
/// **Writing the slot relayouts the subtree**, by design and correctly: the
/// tokens decide paddings, type sizes and thicknesses, so a theme change
/// changes sizes, and nothing else would tell the tree. It follows that
/// nothing on a per-frame path may write a theme. A hover, a press and a
/// raised elevation are `DecoratedBox3d.decoration` and `.stateLayer` — the
/// repaint-only tier — not a new theme.
///
/// ## Density lives in two places, and the theme wins
///
/// `Layout3dMetrics` already carries a `VisualDensity3d`, and applies it in
/// `Layout3dMetrics.effectiveConstraints`. This class carries one too,
/// because density is a *theme* decision in Material and an application
/// setting a theme expects it to be respected. They can therefore disagree,
/// and the rule is: **[density] is what a component obeys.**
/// [effectiveConstraints] applies it through the metrics' own arithmetic —
/// one implementation, two dials, an explicit winner. `SceneTheme3d`
/// deliberately does not write the surface's metrics to close the gap: the
/// metrics is the surface's unit contract, and a widget inside the tree
/// rewriting it would be a theme reaching outside its own vocabulary.
class Theme3dData {
  /// Creates a theme. Every family defaults to its Material 3 baseline.
  const Theme3dData({
    this.colorScheme = ColorScheme3d.light,
    this.typography = Typography3d.baseline,
    this.shape = ShapeScale3d.baseline,
    this.elevation = Elevation3d.baseline,
    this.thickness = Thickness3d.baseline,
    this.stateLayer = StateLayerOpacity3d.baseline,
    this.density = VisualDensity3d.standard,
  });

  /// The baseline light theme.
  static const Theme3dData light = Theme3dData();

  /// The baseline dark theme: the light one with [ColorScheme3d.dark].
  ///
  /// Only the colours change. Material's type, shape and elevation scales are
  /// the same in both brightnesses, and so is the thickness scale invented
  /// here — a card is not deeper at night.
  static const Theme3dData dark = Theme3dData(colorScheme: ColorScheme3d.dark);

  /// The owner slot a theme is published in.
  ///
  /// A `Layout3dSlot` is identified by its type **and its name**, never by
  /// identity — Dart canonicalizes `const` instances, so identity keying
  /// would behave one way for a `const` slot and another for a `final` one.
  /// The consequence is that two libraries choosing the same name for the
  /// same type would collide, which is why this one is namespaced to the
  /// package that owns it.
  ///
  /// Read it from inside `performLayout` through [Layout3dTheme3d.theme3d]
  /// rather than by hand, so the fallback is stated in one place.
  static const Layout3dSlot<Theme3dData> slot = Layout3dSlot<Theme3dData>(
    'material3d.theme',
  );

  /// The colour roles.
  final ColorScheme3d colorScheme;

  /// The type scale.
  final Typography3d typography;

  /// The corner radii, and the bevel rule that goes with a thickness.
  final ShapeScale3d shape;

  /// The six elevation levels, in logical pixels.
  final Elevation3d elevation;

  /// How deep a component is, in logical pixels.
  final Thickness3d thickness;

  /// How strong the wash is for a hover, a focus, a press or a drag.
  ///
  /// The family Material publishes and this package needed a name for, since
  /// every interactive component resolves it the same way: the opacity comes
  /// from here and the colour comes from whatever the component is drawn on.
  final StateLayerOpacity3d stateLayer;

  /// How tightly components pack themselves.
  ///
  /// See the class doc: this is the authority, not `metrics.density`.
  final VisualDensity3d density;

  /// [constraints] adjusted by this theme's [density], in world units.
  ///
  /// The arithmetic is `Layout3dMetrics.effectiveConstraints`' — the theme
  /// only decides *which* density is applied. A component sizing itself
  /// against a Material minimum calls this instead of the metrics' own
  /// method, and gets the theme's density rather than the surface's.
  Constraints3d effectiveConstraints(
    Constraints3d constraints,
    Layout3dMetrics metrics,
  ) => metrics.copyWith(density: density).effectiveConstraints(constraints);

  /// The [token] style, in [color].
  ///
  /// The one call a component makes to turn a type role into something
  /// `Text3d` can measure. The scale carries no colour of its own — a colour
  /// is a `ColorScheme3d` role and depends on what the label is drawn on, not
  /// on how big it is — so this is where the two families meet.
  ///
  /// ```dart
  /// theme.textStyle(
  ///   Typography3dToken.labelLarge,
  ///   color: theme.colorScheme.onPrimary,
  /// )
  /// ```
  TextStyle textStyle(Typography3dToken token, {Color? color}) {
    final style = typography.resolve(token);
    return color == null ? style : style.copyWith(color: color);
  }

  /// A copy with the given families replaced.
  Theme3dData copyWith({
    ColorScheme3d? colorScheme,
    Typography3d? typography,
    ShapeScale3d? shape,
    Elevation3d? elevation,
    Thickness3d? thickness,
    StateLayerOpacity3d? stateLayer,
    VisualDensity3d? density,
  }) => Theme3dData(
    colorScheme: colorScheme ?? this.colorScheme,
    typography: typography ?? this.typography,
    shape: shape ?? this.shape,
    elevation: elevation ?? this.elevation,
    thickness: thickness ?? this.thickness,
    stateLayer: stateLayer ?? this.stateLayer,
    density: density ?? this.density,
  );

  /// Linearly interpolates between two themes, family by family.
  ///
  /// This is what makes a theme change animatable — a light-to-dark fade is
  /// `Theme3dDataTween(begin: Theme3dData.light, end: Theme3dData.dark)` — and
  /// it is deliberately *not* cheap: writing the interpolated value into the
  /// slot relayouts the subtree on every frame of the animation. Animating a
  /// whole theme is a screen-sized transition, not an interaction. A button
  /// lighting up under a pointer animates its own decoration instead, and
  /// touches no layout at all.
  static Theme3dData lerp(Theme3dData a, Theme3dData b, double t) =>
      Theme3dData(
        colorScheme: ColorScheme3d.lerp(a.colorScheme, b.colorScheme, t),
        typography: Typography3d.lerp(a.typography, b.typography, t),
        shape: ShapeScale3d.lerp(a.shape, b.shape, t),
        elevation: Elevation3d.lerp(a.elevation, b.elevation, t),
        thickness: Thickness3d.lerp(a.thickness, b.thickness, t),
        stateLayer: StateLayerOpacity3d.lerp(a.stateLayer, b.stateLayer, t),
        density: VisualDensity3d.lerp(a.density, b.density, t),
      );

  @override
  bool operator ==(Object other) =>
      other is Theme3dData &&
      other.colorScheme == colorScheme &&
      other.typography == typography &&
      other.shape == shape &&
      other.elevation == elevation &&
      other.thickness == thickness &&
      other.stateLayer == stateLayer &&
      other.density == density;

  @override
  int get hashCode => Object.hash(
    colorScheme,
    typography,
    shape,
    elevation,
    thickness,
    stateLayer,
    density,
  );

  @override
  String toString() =>
      'Theme3dData(${colorScheme.brightness.name}, density: $density)';
}

/// Reading the theme from inside a `Layout3d`.
///
/// The imperative half of the theme channel. It reads the same owner slot
/// `SceneTheme3d` writes, so a box laid out under a themed widget tree sees
/// the theme without anything being threaded through its constructor — which
/// is the whole reason `Layout3dSlot` exists.
extension Layout3dTheme3d on Layout3d {
  /// The theme in force, or [Theme3dData.light] when none was published.
  ///
  /// Falling back rather than throwing, for the same reason
  /// `Layout3d.metrics` falls back to `Layout3dMetrics.standard`: a box reads
  /// this inside `performLayout`, where throwing would take down a whole
  /// layout pass over a missing default, and where "detached" is a normal
  /// state rather than an error. A component drawn in the baseline light
  /// theme is visibly wrong and diagnosable; a layout that threw is neither.
  Theme3dData get theme3d => slot(Theme3dData.slot) ?? Theme3dData.light;

  /// Whether a theme was actually published, for a caller that wants to know
  /// rather than to be defaulted.
  bool get hasTheme3d => slot(Theme3dData.slot) != null;
}
