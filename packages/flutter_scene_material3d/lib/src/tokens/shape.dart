import 'dart:ui' show lerpDouble;

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d;

/// Material 3's shape scale, in logical pixels, plus the rule a slab needs
/// that a flat specification does not.
///
/// Seven steps from square to stadium. A component names a step —
/// `theme.shape.medium` for a card, `theme.shape.full` for a button — and the
/// step is a [BorderRadius3d], which `BoxDecoration3d.borderRadius` takes
/// directly.
///
/// **The figures are logical pixels**, like every other Material token, and
/// the metrics turn them into world units at paint time. At the default rate
/// of `0.01` units per logical pixel a 12dp radius is 0.12 units;
/// `BorderRadius3d.circular(0.12)` written by hand instead is a corner about
/// a thousandth of a unit across and renders as square. That mistake has been
/// made in this repository and cost an hour of debugging a shader that was
/// working perfectly.
///
/// ## A thickness needs a bevel, and Material has no token for either
///
/// [BorderRadius3d] rounds the four corners you see face-on. A component here
/// is a *slab*, and its rim — the eight edges along the depth axis — is a
/// separate dial, `BoxDecoration3d.bevel`. A 4dp-thick card with a 12dp
/// corner radius and no bevel has a knife edge where a real object would have
/// a softened one, and under a grazing light it reads as a cut-out rather
/// than as a thing.
///
/// So the bevel belongs to the shape scale, and it is stated as a *fraction
/// of the thickness* rather than as a figure of its own: a 1dp divider and an
/// 8dp app bar want visibly different rims, and one number that suits both
/// does not exist. [bevelFor] is the call:
///
/// ```dart
/// BoxDecoration3d(
///   color: theme.colorScheme.surfaceContainer,
///   borderRadius: theme.shape.medium,
///   bevel: theme.shape.bevelFor(theme.thickness.raised),
///   elevation: theme.elevation.level1,
/// )
/// ```
///
/// The painter clamps a bevel to half the slab's depth, so an over-large
/// fraction degrades into a fully rounded rim rather than into nonsense — but
/// it is a fraction of a *quarter* by default, which is a rim you notice only
/// when it is missing.
class ShapeScale3d {
  /// Creates a shape scale.
  const ShapeScale3d({
    this.none = BorderRadius3d.zero,
    this.extraSmall = const BorderRadius3d.circular(4.0),
    this.small = const BorderRadius3d.circular(8.0),
    this.medium = const BorderRadius3d.circular(12.0),
    this.large = const BorderRadius3d.circular(16.0),
    this.extraLarge = const BorderRadius3d.circular(28.0),
    this.full = const BorderRadius3d.circular(fullRadius),
    this.bevelFraction = 0.25,
  }) : assert(bevelFraction >= 0.0);

  /// Material 3's published shape scale, with a quarter-thickness bevel.
  static const ShapeScale3d baseline = ShapeScale3d();

  /// The radius [full] is written with: large enough that any real box
  /// resolves it down to a stadium.
  ///
  /// Material's `full` is not a number, it is "half the shorter side", and
  /// `BorderRadius3d` holds no such rule — but [BorderRadius3d.resolve]
  /// already scales radii down to what a box can fit, so an absurdly large
  /// radius *is* a stadium once resolved, on any box, at any size.
  ///
  /// It is a finite absurdity on purpose. `double.infinity` would satisfy the
  /// constructor's assert and then produce `infinity * 0` — a `NaN` radius —
  /// the first time `resolve` scaled it, and a `NaN` in a shader uniform
  /// draws nothing with no error anywhere. A thousand logical pixels is ten
  /// world units at the default rate, which is larger than any panel this
  /// package is meant for and small enough to survive arithmetic.
  static const double fullRadius = 1000.0;

  /// Square corners.
  final BorderRadius3d none;

  /// 4dp. A chip, a small badge.
  final BorderRadius3d extraSmall;

  /// 8dp. A text field, a small card.
  final BorderRadius3d small;

  /// 12dp. The default card and menu radius.
  final BorderRadius3d medium;

  /// 16dp. A large card, a dialog.
  final BorderRadius3d large;

  /// 28dp. A bottom sheet, a large floating action button.
  final BorderRadius3d extraLarge;

  /// A stadium: fully rounded on the shorter axis, whatever the box's size.
  ///
  /// See [fullRadius] for why this is a large number rather than a flag.
  final BorderRadius3d full;

  /// How much of a component's thickness its rim is rounded off by.
  ///
  /// A quarter by default. See the class doc for why this lives on the shape
  /// scale rather than being a figure each component picks.
  final double bevelFraction;

  /// The bevel a slab [thickness] logical pixels deep should be given, in
  /// logical pixels.
  double bevelFor(double thickness) => thickness * bevelFraction;

  /// A copy with the given steps replaced.
  ShapeScale3d copyWith({
    BorderRadius3d? none,
    BorderRadius3d? extraSmall,
    BorderRadius3d? small,
    BorderRadius3d? medium,
    BorderRadius3d? large,
    BorderRadius3d? extraLarge,
    BorderRadius3d? full,
    double? bevelFraction,
  }) => ShapeScale3d(
    none: none ?? this.none,
    extraSmall: extraSmall ?? this.extraSmall,
    small: small ?? this.small,
    medium: medium ?? this.medium,
    large: large ?? this.large,
    extraLarge: extraLarge ?? this.extraLarge,
    full: full ?? this.full,
    bevelFraction: bevelFraction ?? this.bevelFraction,
  );

  /// Linearly interpolates between two shape scales.
  ///
  /// **Every corner is held at or above zero**, and that is not decoration.
  /// `BorderRadius3d` asserts on a negative radius, and an overshooting curve
  /// — `Curves.easeInBack`, a spring — evaluates its tween outside `[0, 1]`
  /// by construction. Without the clamp, animating from a rounded scale to a
  /// square one crashes on the frames where the curve dips below zero, which
  /// is a bug that only appears for some curves.
  static ShapeScale3d lerp(ShapeScale3d a, ShapeScale3d b, double t) =>
      ShapeScale3d(
        none: _lerpRadius(a.none, b.none, t),
        extraSmall: _lerpRadius(a.extraSmall, b.extraSmall, t),
        small: _lerpRadius(a.small, b.small, t),
        medium: _lerpRadius(a.medium, b.medium, t),
        large: _lerpRadius(a.large, b.large, t),
        extraLarge: _lerpRadius(a.extraLarge, b.extraLarge, t),
        full: _lerpRadius(a.full, b.full, t),
        bevelFraction: lerpDouble(
          a.bevelFraction,
          b.bevelFraction,
          t,
        )!.clamp(0.0, double.infinity),
      );

  /// Interpolates two radii, corner by corner, and holds each at or above
  /// zero.
  static BorderRadius3d _lerpRadius(
    BorderRadius3d a,
    BorderRadius3d b,
    double t,
  ) => BorderRadius3d(
    topLeft: _lerpCorner(a.topLeft, b.topLeft, t),
    topRight: _lerpCorner(a.topRight, b.topRight, t),
    bottomLeft: _lerpCorner(a.bottomLeft, b.bottomLeft, t),
    bottomRight: _lerpCorner(a.bottomRight, b.bottomRight, t),
  );

  static double _lerpCorner(double a, double b, double t) =>
      lerpDouble(a, b, t)!.clamp(0.0, double.infinity);

  @override
  bool operator ==(Object other) =>
      other is ShapeScale3d &&
      other.none == none &&
      other.extraSmall == extraSmall &&
      other.small == small &&
      other.medium == medium &&
      other.large == large &&
      other.extraLarge == extraLarge &&
      other.full == full &&
      other.bevelFraction == bevelFraction;

  @override
  int get hashCode => Object.hash(
    none,
    extraSmall,
    small,
    medium,
    large,
    extraLarge,
    full,
    bevelFraction,
  );

  @override
  String toString() => 'ShapeScale3d(medium: $medium, bevel: $bevelFraction×)';
}
