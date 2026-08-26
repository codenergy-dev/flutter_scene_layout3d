import 'dart:ui' show lerpDouble;

import 'geometry/constraints3d.dart';
import 'geometry/offset3d.dart';
import 'geometry/size3d.dart';

/// How tightly a component packs itself, the 3D analogue of [VisualDensity].
///
/// Flutter's rule, one axis richer: each unit of density is worth four
/// logical pixels of size adjustment, negative values pull a control in and
/// positive ones push it out, and the range is clamped to `[-4, 4]` so a
/// theme cannot make a control collapse or explode.
///
/// The adjustment is stated in *logical pixels*, not world units, because
/// that is the frame the whole contract is specified in; a component turns it
/// into units through [Layout3dMetrics.dp], or lets
/// [Layout3dMetrics.effectiveConstraints] do it.
///
/// [depth] is the axis Flutter does not have. A denser panel is not only
/// narrower and shorter, it is *thinner*: the slab behind a button, the
/// travel of a press, and the gap that keeps two coplanar faces out of each
/// other's depth buffer all scale with it.
class VisualDensity3d {
  /// Creates a density from its three per-axis dials.
  const VisualDensity3d({
    this.horizontal = 0.0,
    this.vertical = 0.0,
    this.depth = 0.0,
  }) : assert(horizontal >= minimumDensity && horizontal <= maximumDensity),
       assert(vertical >= minimumDensity && vertical <= maximumDensity),
       assert(depth >= minimumDensity && depth <= maximumDensity);

  /// The most negative a density dial may be.
  static const double minimumDensity = -4.0;

  /// The most positive a density dial may be.
  static const double maximumDensity = 4.0;

  /// Logical pixels of size adjustment per unit of density.
  ///
  /// Four, the same as Flutter's, so a Material spec written against
  /// `VisualDensity` transfers unchanged.
  static const double logicalPixelsPerUnit = 4.0;

  /// The unadjusted density, and the default.
  static const VisualDensity3d standard = VisualDensity3d();

  /// One step tighter on the two in-plane axes.
  static const VisualDensity3d comfortable = VisualDensity3d(
    horizontal: -1.0,
    vertical: -1.0,
  );

  /// Two steps tighter on the two in-plane axes.
  static const VisualDensity3d compact = VisualDensity3d(
    horizontal: -2.0,
    vertical: -2.0,
  );

  /// The dial along `x`.
  final double horizontal;

  /// The dial along `y`.
  final double vertical;

  /// The dial along `z`.
  final double depth;

  /// The size adjustment this density asks for, in logical pixels.
  Offset3d get baseSizeAdjustment => Offset3d(
    horizontal * logicalPixelsPerUnit,
    vertical * logicalPixelsPerUnit,
    depth * logicalPixelsPerUnit,
  );

  /// A copy with the given dials replaced.
  VisualDensity3d copyWith({
    double? horizontal,
    double? vertical,
    double? depth,
  }) => VisualDensity3d(
    horizontal: horizontal ?? this.horizontal,
    vertical: vertical ?? this.vertical,
    depth: depth ?? this.depth,
  );

  /// Linearly interpolates between two densities.
  static VisualDensity3d lerp(VisualDensity3d a, VisualDensity3d b, double t) =>
      VisualDensity3d(
        horizontal: lerpDouble(a.horizontal, b.horizontal, t)!,
        vertical: lerpDouble(a.vertical, b.vertical, t)!,
        depth: lerpDouble(a.depth, b.depth, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is VisualDensity3d &&
      other.horizontal == horizontal &&
      other.vertical == vertical &&
      other.depth == depth;

  @override
  int get hashCode => Object.hash(horizontal, vertical, depth);

  @override
  String toString() =>
      'VisualDensity3d(h: ${horizontal.toStringAsFixed(1)}, '
      'v: ${vertical.toStringAsFixed(1)}, d: ${depth.toStringAsFixed(1)})';
}

/// The unit contract of a layout tree: what a logical pixel is worth in world
/// units, and the two dials a component library reads beside it.
///
/// Everything in this package measures in world units, because that is what a
/// scene is made of. Everything a *component* library is specified in is
/// measured in logical pixels: a Material touch target is 48dp, a card corner
/// is 12dp, a body label is 14sp. [unitsPerLogicalPixel] is the one number
/// that joins the two, and it is carried on [Layout3dOwner] beside the basis
/// so both the imperative and the declarative layer see it — a `Layout3d`
/// reads it as [Layout3d.metrics], with no `BuildContext` in the way.
///
/// ```dart
/// // A Material touch target, on the plane, at whatever density is in force.
/// SizedBox3d(
///   width: metrics.dp(48),
///   height: metrics.dp(48),
///   child: content,
/// )
/// ```
///
/// There are three honest ways to fix the number, and a component library
/// needs all three:
///
///  * **Derived.** A [Layout3dCameraBinding.screenFilling] surface covers the
///    view exactly, so its world height spans exactly `viewSize.height`
///    logical pixels and the conversion is forced rather than chosen. This is
///    the case the binding exists for.
///  * **Authored.** A panel on a wall at some angle is not a screen. The
///    author states the scale outright —
///    [Layout3dCameraBinding.fixedDensity], or a metrics value assigned to
///    the surface — and every component below inherits it.
///  * **Inherited.** Everything under a surface reads the surface's metrics
///    through its owner, so a component never has to be told.
///
/// Changing the metrics relayouts, for the same reason changing the basis
/// does: content measured at one density reports a different size at another.
///
/// The number is *not* a promise about pixels on screen for a surface that is
/// not camera-bound. A panel standing at an angle, or one the viewer can walk
/// toward, covers a different number of real pixels every frame; the metrics
/// say how the layout is *specified*, and anything that rasterizes (text, in
/// particular) needs its own level-of-detail story on top.
class Layout3dMetrics {
  /// Creates a unit contract.
  const Layout3dMetrics({
    this.unitsPerLogicalPixel = defaultUnitsPerLogicalPixel,
    this.textScaleFactor = 1.0,
    this.density = VisualDensity3d.standard,
  }) : assert(unitsPerLogicalPixel > 0.0),
       assert(textScaleFactor > 0.0);

  /// The default scale: one world unit is one hundred logical pixels.
  ///
  /// Chosen so the panel sizes this package's own examples use read as
  /// plausible screens — the `Size3d(4, 3, 0.5)` surface of the README is
  /// 400 by 300 dp — and so a Material 48dp touch target is a comfortable
  /// 0.48 units, neither a speck nor a wall. It is an *authored* default,
  /// unlike a derived one, so a layout that cares should say what it wants
  /// rather than lean on it.
  static const double defaultUnitsPerLogicalPixel = 0.01;

  /// The default contract: [defaultUnitsPerLogicalPixel], no text scaling,
  /// standard density.
  static const Layout3dMetrics standard = Layout3dMetrics();

  /// World units per logical pixel.
  ///
  /// The whole contract in one number. Multiply a dp figure by it to get
  /// units ([dp]); divide units by it to get dp ([toLogicalPixels]).
  final double unitsPerLogicalPixel;

  /// The accessibility text scale, the analogue of `MediaQuery.textScaler`.
  ///
  /// Applied by [sp] and by nothing else: it scales type, not the boxes
  /// around it, which is why it is a separate dial from [density].
  final double textScaleFactor;

  /// How tightly components pack themselves.
  final VisualDensity3d density;

  /// Logical pixels per world unit, the inverse of [unitsPerLogicalPixel].
  ///
  /// What a rasterizer wants: the number of pixels a unit of the plane is
  /// worth, and so the resolution a glyph atlas or a texture has to be
  /// generated at to come out sharp.
  double get logicalPixelsPerUnit => 1.0 / unitsPerLogicalPixel;

  /// [logicalPixels] as world units.
  ///
  /// The conversion a component author reaches for: `metrics.dp(48)` is a
  /// Material touch target, whatever scale the surface is drawn at.
  double dp(double logicalPixels) => logicalPixels * unitsPerLogicalPixel;

  /// [logicalPixels] as world units, scaled by [textScaleFactor].
  ///
  /// The type counterpart of [dp]. A 14sp label is `metrics.sp(14)` units
  /// tall and grows when the platform's text scale does.
  double sp(double logicalPixels) =>
      logicalPixels * textScaleFactor * unitsPerLogicalPixel;

  /// [units] as logical pixels, the inverse of [dp].
  double toLogicalPixels(double units) => units / unitsPerLogicalPixel;

  /// A size stated in logical pixels, as world units.
  ///
  /// [depth] defaults to zero, because a component's thickness is almost
  /// never part of a Material spec and is better stated deliberately.
  Size3d dpSize(double width, double height, [double depth = 0.0]) =>
      Size3d(dp(width), dp(height), dp(depth));

  /// [constraints] with each minimum grown (or shrunk) by [density].
  ///
  /// The 3D form of `VisualDensity.effectiveConstraints`, and the reason the
  /// density lives on the metrics rather than beside them: the adjustment is
  /// authored in logical pixels and has to be converted before it can touch a
  /// constraint. A minimum never goes below zero or above its own maximum.
  Constraints3d effectiveConstraints(Constraints3d constraints) {
    final adjustment = density.baseSizeAdjustment;
    if (adjustment == Offset3d.zero) return constraints;
    return constraints.copyWith(
      minWidth: (constraints.minWidth + dp(adjustment.x)).clamp(
        0.0,
        constraints.maxWidth,
      ),
      minHeight: (constraints.minHeight + dp(adjustment.y)).clamp(
        0.0,
        constraints.maxHeight,
      ),
      minDepth: (constraints.minDepth + dp(adjustment.z)).clamp(
        0.0,
        constraints.maxDepth,
      ),
    );
  }

  /// A copy with the given fields replaced.
  Layout3dMetrics copyWith({
    double? unitsPerLogicalPixel,
    double? textScaleFactor,
    VisualDensity3d? density,
  }) => Layout3dMetrics(
    unitsPerLogicalPixel: unitsPerLogicalPixel ?? this.unitsPerLogicalPixel,
    textScaleFactor: textScaleFactor ?? this.textScaleFactor,
    density: density ?? this.density,
  );

  @override
  bool operator ==(Object other) =>
      other is Layout3dMetrics &&
      other.unitsPerLogicalPixel == unitsPerLogicalPixel &&
      other.textScaleFactor == textScaleFactor &&
      other.density == density;

  @override
  int get hashCode =>
      Object.hash(unitsPerLogicalPixel, textScaleFactor, density);

  @override
  String toString() =>
      'Layout3dMetrics(1 unit = ${logicalPixelsPerUnit.toStringAsFixed(1)} dp, '
      'textScaleFactor: $textScaleFactor, density: $density)';
}
