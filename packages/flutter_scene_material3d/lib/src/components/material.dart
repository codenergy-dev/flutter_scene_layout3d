import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter/widgets.dart'
    show BuildContext, DefaultTextStyle, State, StatefulWidget, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        Border3d,
        BorderRadius3d,
        BoxDecoration3d,
        DecoratedBox3d,
        EdgeInsets3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show Layout3dMetricsScope, SceneContainer3d, SingleChildLayout3dWidget;

import '../theme/theme.dart';
import '../theme/theme_data.dart';
import '../tokens/typography.dart';
import 'ink.dart';

/// A Material surface: the one primitive every other component here is built
/// out of.
///
/// It is a `SceneDecoratedBox3d` with the theme resolved into it, and it owns
/// the five things Material says a surface has — the colour, the shape, the
/// elevation, the state layer, and the thing Material has no word for because
/// a screen has none of it, the **thickness**. Every button in the catalogue
/// is one of these with different tokens in it, which is the point: there is
/// exactly one class that knows how a token becomes a `BoxDecoration3d`.
///
/// ```dart
/// Material3d(
///   color: theme.colorScheme.surfaceContainer,
///   shape: theme.shape.medium,
///   elevation: theme.elevation.level1,
///   thickness: theme.thickness.raised,
///   padding: const EdgeInsets3d.symmetric(horizontal: 24, vertical: 10),
///   child: const SceneText3d('Continue'),
/// )
/// ```
///
/// Everything it takes is in **logical pixels** — a 12dp radius, a 3dp
/// elevation, a 16dp padding — and it converts, so a component's numbers are
/// the ones its specification is written with at any surface scale. The
/// decoration figures are converted by the painter; the padding and the
/// thickness are converted here, through `Layout3dMetricsScope.of(context)`,
/// which is why **a `Material3d` has to be built inside a `SceneLayout3d`**
/// and asserts when it is not.
///
/// ## What each token defaults to
///
/// Every property is nullable and falls back to the theme, so a bare
/// `Material3d(child: …)` is a flat surface at the theme's own colours:
///
///  * [color] — `colorScheme.surface`
///  * [shape] — `shape.none`, square corners
///  * [elevation] — `elevation.level0`, flat
///  * [thickness] — `thickness.standard`, 2dp
///  * [bevel] — `shape.bevelFor(thickness)`, a quarter of the thickness
///  * [surfaceTint] — `colorScheme.surfaceTint`
///  * [contentColor] — `colorScheme.onSurface`
///
/// ## Elevation is a height and a tint, and never a shadow
///
/// [elevation] lifts the geometry toward the viewer by `metrics.dp(elevation)`
/// and nothing else: no shadow is drawn, and none can be, because the panel
/// shader blends its own anti-aliased outline and `flutter_scene` keeps
/// non-opaque materials out of the shadow pass. What is left of Material's
/// elevation model is parallax, occlusion, and the **surface tint** — which
/// therefore carries more weight here than it does on a screen, and is what
/// distinguishes a raised card from a flat one when the camera is head-on.
/// [surfaceTint] is applied automatically at any elevation above zero, and
/// passing a fully transparent colour is how a component opts out.
///
/// ## The thickness, and the one rule that comes with it
///
/// [thickness] is a tight depth constraint on the surface, so a `Material3d`
/// is a slab rather than a decal, and [bevel] rounds its rim in proportion —
/// a knife-edged 4dp card reads as a cut-out under a grazing light.
///
/// The rule to know before stacking two of them: `Stack3d.depthStep`
/// separates two slabs only when the step exceeds the **mean** of their
/// thicknesses, because each is centred on its own plane. Under that, the
/// back one pokes through the front one and wins the depth test where they
/// overlap — and a drop target inherits the same failure, taking a drop that
/// visibly belonged to the card in front of it. `Thickness3d.separates` is
/// that sentence as a predicate, and the theme's own scale clears its own
/// `depthStep` with half again to spare.
///
/// ## Nothing draws until an application installs a painter
///
/// A `Material3d` with no painter measures, lays out and draws nothing at
/// all, with no error anywhere. `initializeMaterial3d()` is the one call that
/// fixes it.
class Material3d extends StatefulWidget {
  /// Creates a Material surface. Every token defaults to the theme's.
  const Material3d({
    super.key,
    this.color,
    this.shape,
    this.elevation,
    this.thickness,
    this.bevel,
    this.border = Border3d.none,
    this.surfaceTint,
    this.contentColor,
    this.textStyle,
    this.padding = EdgeInsets3d.zero,
    this.alignment = Alignment3d.frontCenter,
    this.child,
  });

  /// The slab's colour, or null for `colorScheme.surface`.
  final Color? color;

  /// The corner radii, in logical pixels, or null for `shape.none`.
  final BorderRadius3d? shape;

  /// How far the surface stands off its parent, in logical pixels, or null
  /// for `elevation.level0`.
  final double? elevation;

  /// How deep the slab is, in logical pixels, or null for
  /// `thickness.standard`.
  final double? thickness;

  /// How far the slab's rim is rounded along the depth axis, in logical
  /// pixels, or null for `shape.bevelFor(thickness)`.
  final double? bevel;

  /// The line drawn inside the outline. `Border3d.none` by default.
  final Border3d border;

  /// The colour a raised surface is tinted with, or null for
  /// `colorScheme.surfaceTint`.
  ///
  /// The amount comes from [elevation] through Material's published table, so
  /// a flat surface is untinted whatever this says. Pass a fully transparent
  /// colour to opt out of the tint at a real elevation.
  final Color? surfaceTint;

  /// The colour of whatever is drawn on this surface, or null for
  /// `colorScheme.onSurface`.
  ///
  /// It does two jobs, which is why it is one property: it is the colour of
  /// the state-layer wash — Material's own rule, that a wash is the surface's
  /// "on" colour at a low opacity — and it is the colour of the labels below,
  /// through the [DefaultTextStyle] this widget installs.
  final Color? contentColor;

  /// The style labels below this surface inherit, or null for the theme's
  /// `bodyMedium` in [contentColor].
  ///
  /// Merged onto whatever style is already in force, exactly as Flutter's
  /// `Material` does it, so a `SceneText3d` inside a component only has to
  /// say what differs.
  final TextStyle? textStyle;

  /// Space between the surface's faces and its child, in logical pixels.
  ///
  /// **A front or back inset pushes the child into the slab**, where the
  /// surface it is drawn on will win the depth test and hide it. That is
  /// correct — the padding is a real inset on a real box — and it means
  /// `EdgeInsets3d.all(16)` is rarely what a component wants. State the two
  /// in-plane axes: `EdgeInsets3d.symmetric(horizontal: 24, vertical: 10)`.
  final EdgeInsets3d padding;

  /// Where the child sits inside the padded surface.
  ///
  /// [Alignment3d.frontCenter] by default, and the depth half of that is not
  /// cosmetic: a label centred *in depth* sits in the middle of the slab and
  /// is hidden by the front half of it. Aligned to the front face it sits on
  /// the surface, which is where a label on a card belongs.
  ///
  /// Null gives the child the surface's own constraints instead of aligning
  /// it in them, the way a `Container3d` with no alignment does.
  final Alignment3d? alignment;

  /// What is drawn on the surface.
  final Widget? child;

  /// The decoration the given tokens resolve to.
  ///
  /// The single place a token becomes a `BoxDecoration3d`, exposed as a
  /// static because two callers need it and they must not drift apart: this
  /// widget, and anything building a Material surface in the **imperative**
  /// layer — a `DecoratedBox3d` in a scene assembled without widgets, which
  /// is what `examples/render_probe` is and what a game with its own scene
  /// graph will be. A probe that reimplemented the resolution would be
  /// checking its own arithmetic rather than this package's.
  ///
  /// Every argument is in logical pixels and every null falls back to
  /// [theme], exactly as the constructor's do.
  static BoxDecoration3d decorationFor(
    Theme3dData theme, {
    Color? color,
    BorderRadius3d? shape,
    double? elevation,
    double? thickness,
    double? bevel,
    Border3d border = Border3d.none,
    Color? surfaceTint,
  }) {
    final depth = thickness ?? theme.thickness.standard;
    return BoxDecoration3d(
      color: color ?? theme.colorScheme.surface,
      borderRadius: shape ?? theme.shape.none,
      bevel: bevel ?? theme.shape.bevelFor(depth),
      border: border,
      elevation: elevation ?? theme.elevation.level0,
      surfaceTint: surfaceTint ?? theme.colorScheme.surfaceTint,
    );
  }

  @override
  State<Material3d> createState() => _Material3dState();
}

class _Material3dState extends State<Material3d> {
  MutableInkController3d? _ink;

  @override
  void dispose() {
    _ink?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final scheme = theme.colorScheme;

    final thickness = widget.thickness ?? theme.thickness.standard;
    final elevation = widget.elevation ?? theme.elevation.level0;
    final contentColor = widget.contentColor ?? scheme.onSurface;

    final ink = _ink ??= MutableInkController3d(
      color: contentColor,
      opacities: theme.stateLayer,
    );
    ink.restyle(color: contentColor, opacities: theme.stateLayer);

    final decoration = Material3d.decorationFor(
      theme,
      color: widget.color,
      shape: widget.shape,
      elevation: elevation,
      thickness: thickness,
      bevel: widget.bevel,
      border: widget.border,
      surfaceTint: widget.surfaceTint,
    );

    final textStyle =
        widget.textStyle ??
        theme.textStyle(Typography3dToken.bodyMedium, color: contentColor);

    return InkController3dScope(
      controller: ink,
      child: DefaultTextStyle.merge(
        style: textStyle,
        child: _Material3dSurface(
          ink: ink,
          decoration: decoration,
          child: SceneContainer3d(
            alignment: widget.alignment,
            padding: metrics.dpInsets(widget.padding),
            depth: metrics.dp(thickness),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The decorated box a [Material3d] draws, and the place the ink controller
/// is handed its box.
///
/// It exists rather than a plain `SceneDecoratedBox3d` for one reason: the
/// state layer must not be a widget property. If it were, every hover would
/// have to rebuild this widget to reach the box, which is exactly the tier
/// the decoration layer was designed to avoid. So the decoration comes down
/// the tree and the wash comes sideways, from the controller, and a rebuild
/// re-applies whatever the controller currently holds rather than clobbering
/// it with a stale value.
class _Material3dSurface extends SingleChildLayout3dWidget {
  const _Material3dSurface({
    required this.ink,
    required this.decoration,
    super.child,
  });

  final MutableInkController3d ink;
  final BoxDecoration3d decoration;

  @override
  DecoratedBox3d createLayout(BuildContext context) {
    final box = DecoratedBox3d(decoration: decoration);
    ink.attach(box);
    return box;
  }

  @override
  void updateLayout(BuildContext context, DecoratedBox3d layout) {
    layout.decoration = decoration;
    ink.attach(layout);
  }
}
