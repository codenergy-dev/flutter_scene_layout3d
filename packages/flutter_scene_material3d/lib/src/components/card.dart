import 'dart:ui' show Color;

import 'package:flutter/gestures.dart'
    show GestureLongPressCallback, GestureTapCallback;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show EdgeInsets3d, Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        ScenePadding3d,
        SceneSemantics3d,
        SceneTapTarget3d;

import '../theme/theme.dart';
import 'card_style.dart';
import 'ink_well.dart';
import 'material.dart';

/// A Material card: a surface that holds a piece of content, of whichever of
/// the three kinds its [style] describes.
///
/// ```dart
/// Card3d(
///   variant: CardVariant3d.elevated,
///   child: ScenePadding3d(
///     padding: metrics.dpInsets(
///       const EdgeInsets3d.symmetric(horizontal: 16, vertical: 12),
///     ),
///     child: const SceneText3d('Yesterday'),
///   ),
/// )
/// ```
///
/// `ElevatedCard3d`, `FilledCard3d` and `OutlinedCard3d` are this widget with
/// a different [CardStyle3d] in it, which is the claim the catalogue keeps
/// making: a component is a `Material3d` plus a token set.
///
/// ## A card is where the depth stops being decoration
///
/// A card is `thickness.raised`, 4dp, and an elevated one rests 1dp toward
/// the viewer on top of that. On a screen those two numbers are a shadow
/// recipe; here they are geometry that occludes, catches a grazing light on
/// its bevelled rim, and moves under the camera. Nothing casts a shadow — the
/// panel shader blends, and `flutter_scene` keeps non-opaque materials out of
/// the shadow pass — so parallax and occlusion are the whole of the signal.
///
/// **And a clip leaves it alone.** `Clip3dRegion.rect` is four planes: a
/// scrolling list cuts its rows at the window's edges and says nothing about
/// depth, precisely so a raised card inside one still stands proud of it
/// rather than being sliced off flush with the surface. That is a deliberate
/// decision in `flutter_scene_layout3d`'s clip contract and this is the first
/// component that depends on it; `examples/render_probe`'s
/// `card_in_clipped_list` scene is the picture of it.
///
/// ## What a state costs: nothing
///
/// Material 3 gives a card no disabled appearance, no hovered container and
/// no focused outline, so an interactive card is *washed* and is otherwise
/// unchanged. Every state therefore goes through the ink controller, which
/// writes one shader uniform and rebuilds nothing at all — where a filled
/// button has to rebuild for its hovered elevation. See [CardStyle3d].
///
/// ## Announcing itself
///
/// A card is a container, and a container with a tap is a button. Pass a
/// [semanticLabel]: `Semantics3d` publishes what it is given and gathers no
/// label out of the labels inside the card, so a tappable card without one
/// announces itself as a button with no name.
class Card3d extends StatelessWidget {
  /// Creates a card of [variant], or drawn with an explicit [style].
  const Card3d({
    super.key,
    this.variant = CardVariant3d.elevated,
    this.style,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.textDirection,
    this.child,
  });

  /// Which of the three kinds this card is, when [style] is null.
  final CardVariant3d variant;

  /// The tokens to draw with, or null for the theme's style for [variant].
  final CardStyle3d? style;

  /// Called when the card is tapped, or null for a card that is not
  /// interactive at all.
  ///
  /// A card with neither this nor [onLongPress] installs no ink well, takes
  /// no focus and announces itself as a plain container rather than as a
  /// button.
  final GestureTapCallback? onTap;

  /// Called when the card is long-pressed.
  final GestureLongPressCallback? onLongPress;

  /// What a screen reader announces this card as.
  ///
  /// **State it.** There is no semantics merge in this stack: the labels
  /// inside the card are not gathered into the card's own announcement.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// What the card holds.
  final Widget? child;

  /// Whether the card responds to a pointer.
  bool get interactive => onTap != null || onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? CardStyle3d.of(theme, variant);

    final surface = Material3d(
      color: resolved.container,
      contentColor: resolved.contentColor,
      shape: resolved.shape,
      elevation: resolved.elevation,
      thickness: resolved.thickness,
      border: resolved.border,
      padding: resolved.padding,
      // Material 3 turns the surface tint off on a card, and the reason is
      // the one phase 3 found for buttons: an elevated card's container token
      // is `surfaceContainerLow`, which already *is* the level-1 tint baked
      // into a colour. Applying the tint again double-counts it. Flutter's
      // own `_CardDefaultsM3` resolves `surfaceTintColor` to transparent for
      // all three variants, and `test/card_defaults_test.dart` reads that
      // figure rather than asserting ours.
      surfaceTint: const Color(0x00000000),
      // The child gets the surface's own constraints and fills it, which is
      // what a card is for. A button aligns instead, because it shrink-wraps
      // a label.
      alignment: null,
      child: interactive
          ? InkWell3d(
              // One target, and it is the one outside this panel.
              minimumSize: Size3d.zero,
              onTap: onTap,
              onLongPress: onLongPress,
              child: child,
            )
          : child,
    );

    // The margin is outside the panel and outside the ink, exactly as
    // Flutter's `Card` puts its `Padding` outside its `Material`: a wash that
    // covered the margin would be a card that lights up 4dp beyond its own
    // edge.
    final withMargin = resolved.margin == EdgeInsets3d.zero
        ? surface
        : ScenePadding3d(
            padding: metrics.dpInsets(resolved.margin),
            child: surface,
          );

    final announced = SceneSemantics3d(
      properties: SemanticsProperties(
        button: interactive ? true : null,
        enabled: interactive ? true : null,
        label: semanticLabel,
        textDirection: textDirection,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
      child: withMargin,
    );

    if (!interactive) return announced;
    // The target is outermost for the reason `Button3d`'s is: it reaches past
    // its own extent and every ancestor gates a ray on its own extent, so
    // anything wrapped around it at the card's size — the semantics box
    // included — rejects a press in the margin before the target sees it.
    // A card is almost always larger than 48dp, so the reach usually buys
    // nothing; putting it in the wrong place would still cost something.
    return SceneTapTarget3d(child: announced);
  }
}

/// A `surfaceContainerLow` card resting at elevation level 1.
///
/// The default card, and the one that shows what this package does
/// differently: the lift is a real 1dp of geometry rather than a shadow
/// recipe, so the card occludes what is behind it and moves under the camera.
class ElevatedCard3d extends _VariantCard3d {
  /// Creates an elevated card.
  const ElevatedCard3d({
    super.key,
    super.style,
    super.onTap,
    super.onLongPress,
    super.semanticLabel,
    super.textDirection,
    super.child,
  });

  @override
  CardVariant3d get variant => CardVariant3d.elevated;
}

/// A flat `surfaceContainerHighest` card.
///
/// The lowest-emphasis card: it separates itself from the screen by tone
/// rather than by height, which is the variant to reach for when a list of
/// cards would otherwise be a thicket of edges.
class FilledCard3d extends _VariantCard3d {
  /// Creates a filled card.
  const FilledCard3d({
    super.key,
    super.style,
    super.onTap,
    super.onLongPress,
    super.semanticLabel,
    super.textDirection,
    super.child,
  });

  @override
  CardVariant3d get variant => CardVariant3d.filled;
}

/// A flat `surface` card inside a 1dp `outlineVariant`.
///
/// The one whose whole appearance is a border, which makes it the variant
/// most exposed to the unit contract: a 1dp outline is 0.01 world units at
/// the default rate and a couple of pixels on screen. See *A 1dp line* in the
/// package README for what that means for a probe and for a camera-bound
/// surface.
class OutlinedCard3d extends _VariantCard3d {
  /// Creates an outlined card.
  const OutlinedCard3d({
    super.key,
    super.style,
    super.onTap,
    super.onLongPress,
    super.semanticLabel,
    super.textDirection,
    super.child,
  });

  @override
  CardVariant3d get variant => CardVariant3d.outlined;
}

/// The shared body of the three named cards.
///
/// Not exported: a caller who wants a fourth kind writes a [Card3d] with a
/// [CardStyle3d] of their own.
abstract class _VariantCard3d extends StatelessWidget {
  const _VariantCard3d({
    super.key,
    this.style,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.textDirection,
    this.child,
  });

  /// Which variant's tokens this card resolves.
  CardVariant3d get variant;

  /// The tokens to draw with, or null for the theme's style for [variant].
  final CardStyle3d? style;

  /// Called when the card is tapped.
  final GestureTapCallback? onTap;

  /// Called when the card is long-pressed.
  final GestureLongPressCallback? onLongPress;

  /// What a screen reader announces this card as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// What the card holds.
  final Widget? child;

  @override
  Widget build(BuildContext context) => Card3d(
    variant: variant,
    style: style,
    onTap: onTap,
    onLongPress: onLongPress,
    semanticLabel: semanticLabel,
    textDirection: textDirection,
    child: child,
  );
}
