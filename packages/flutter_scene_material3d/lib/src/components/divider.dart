import 'dart:ui' show Color;

import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Alignment3d, EdgeInsets3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        ScenePadding3d;

import '../theme/theme.dart';
import 'material.dart';

/// A one-pixel rule between two pieces of content.
///
/// ```dart
/// SceneColumn3d(
///   children: <Widget>[
///     ListTile3d.text(title: 'Inbox'),
///     const Divider3d(),
///     ListTile3d.text(title: 'Archive'),
///   ],
/// )
/// ```
///
/// The smallest component in the catalogue and the one that asks the sharpest
/// question, because "one pixel" is three different numbers here.
///
/// ## Three figures, and they are not the same figure
///
///  * [space] — how much room the divider takes in the column: **16dp**, of
///    which the rule is a sliver in the middle. Material's own figure.
///  * [thickness] — how tall the rule itself is, **in the plane**: 1dp. This
///    is Flutter's `Divider.thickness`, and it is the one a reader means by
///    "a one-pixel line".
///  * [depth] — how deep the slab is, along the axis Flutter does not have:
///    `Thickness3d.thin`, also 1dp, and a *different* dial that happens to
///    carry the same number.
///
/// The collision of names is real and worth stating once: `Material3d`'s
/// `thickness` is a depth, and a divider's `thickness` is a height. This
/// class keeps Flutter's spelling for the in-plane figure — a caller
/// migrating a `Divider` writes what they already know — and names the depth
/// [depth].
///
/// ## Why a divider has a depth at all
///
/// The tempting answer is that a rule is flat, so it should be a zero-depth
/// slab. It cannot be, and the reason is the depth buffer. A `Material3d`
/// aligns its child to its **front face**, so a divider inside a card sits
/// exactly on the card's front plane; a slab with no depth there is coplanar
/// with the surface behind it and z-fights — the rule appears in patches,
/// differently on every frame and every driver, with nothing to say why.
///
/// So a divider is a real slab, [Thickness3d.thin] deep, and it stands its
/// own half-thickness proud of whatever it is drawn on. That is also what the
/// thickness scale's own documentation always said the `thin` step was for.
/// The cost is the ordinary one: `Thickness3d.separates` still has to hold
/// against whatever the divider is stacked with, and at 1dp against anything
/// on the scale it does, comfortably.
///
/// ## And it cannot be probed at the default unit rate
///
/// A 1dp rule is 0.01 world units at the default hundred logical pixels to
/// the unit — a pixel or two on screen, thinner than any probe disc fits
/// inside. Phase 3 met the same wall with a button's 1dp outline and answered
/// it the right way round: turn the *surface's* `unitsPerLogicalPixel` up so
/// the token keeps its published figure, rather than fattening the token so a
/// test can see it. `examples/render_probe`'s `divider_rule` scene does the
/// same, and a camera-bound surface turns that dial anyway.
///
/// ## What it announces
///
/// Nothing, by default, and that is the right answer rather than an omission.
/// A divider is a visual separator with no content; Flutter's own `Divider`
/// publishes no semantics either, and a reader that announced "divider"
/// between every pair of rows would be worse than one that skipped it. Pass a
/// [semanticLabel] for the case where the rule really does name a section
/// break, and it announces that instead.
class Divider3d extends StatelessWidget {
  /// Creates a horizontal rule.
  const Divider3d({
    super.key,
    this.space,
    this.thickness,
    this.depth,
    this.indent = 0.0,
    this.endIndent = 0.0,
    this.color,
    this.semanticLabel,
    this.textDirection,
  }) : assert(space == null || space >= 0.0),
       assert(thickness == null || thickness >= 0.0),
       assert(depth == null || depth >= 0.0),
       assert(indent >= 0.0),
       assert(endIndent >= 0.0);

  /// Material's default vertical space for a divider, in logical pixels.
  static const double defaultSpace = 16.0;

  /// Material's default rule height, in logical pixels.
  ///
  /// Checked against `Divider.createBorderSide(context).width` in
  /// `test/divider_test.dart` — Flutter's own accessor, which is public, so
  /// the suite is a drift alarm rather than a second transcription.
  static const double defaultThickness = 1.0;

  /// How much room the divider takes along the column, in logical pixels, or
  /// null for [defaultSpace].
  final double? space;

  /// How tall the rule is, in the plane, in logical pixels, or null for
  /// [defaultThickness].
  final double? thickness;

  /// How deep the slab is, in logical pixels, or null for
  /// `theme.thickness.thin`.
  ///
  /// See the class doc: zero is expressible and is almost always wrong,
  /// because a zero-depth rule on a surface's front face z-fights it.
  final double? depth;

  /// How far the rule is inset from the leading edge, in logical pixels.
  final double indent;

  /// How far the rule is inset from the trailing edge, in logical pixels.
  final double endIndent;

  /// The rule's colour, or null for `colorScheme.outlineVariant`.
  final Color? color;

  /// What a screen reader announces, or null to announce nothing at all.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final rule = thickness ?? defaultThickness;
    final slab = depth ?? theme.thickness.thin;

    // The rule itself: a `Material3d` with no shape, at the divider colour,
    // sized in the plane by the caller and in depth by the thickness scale.
    // It is a `Material3d` rather than a bare `SceneDecoratedBox3d` for the
    // reason every component here is one — there is exactly one class that
    // knows how a token becomes a `BoxDecoration3d`, and a divider that
    // resolved its own bevel would be a second copy of that rule.
    Widget line = SceneSizedBox3d(
      height: metrics.dp(rule),
      child: Material3d(
        color: color ?? theme.colorScheme.outlineVariant,
        shape: theme.shape.none,
        elevation: theme.elevation.level0,
        thickness: slab,
        // A rule this thin wants no rounded rim: at 1dp a quarter-thickness
        // bevel is a quarter of a logical pixel, which costs a shader term
        // and shows nothing.
        bevel: 0.0,
        surfaceTint: const Color(0x00000000),
      ),
    );

    if (indent != 0.0 || endIndent != 0.0) {
      line = ScenePadding3d(
        padding: metrics.dpInsets(
          EdgeInsets3d.only(left: indent, right: endIndent),
        ),
        child: line,
      );
    }

    // The rule sits in the middle of its space, on the front face, so a
    // divider drawn on a card is on the card rather than inside it.
    Widget divider = SceneSizedBox3d(
      height: metrics.dp(space ?? defaultSpace),
      child: SceneAlign3d(alignment: Alignment3d.frontCenter, child: line),
    );

    final label = semanticLabel;
    if (label == null) return divider;
    return SceneSemantics3d(
      properties: SemanticsProperties(
        label: label,
        textDirection: textDirection,
      ),
      child: divider,
    );
  }
}
