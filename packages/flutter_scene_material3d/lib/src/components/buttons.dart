import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter/gestures.dart'
    show GestureLongPressCallback, GestureTapCallback;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        FocusNode,
        IconData,
        State,
        StatefulWidget,
        StatelessWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Alignment3d, Constraints3d, Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneConstrainedBox3d,
        SceneSemantics3d,
        SceneTapTarget3d;

import '../theme/theme.dart';
import '../tokens/state_layer.dart';
import 'button_style.dart';
import 'icon.dart';
import 'ink_well.dart';
import 'material.dart';

/// A Material button, of whichever variant its [style] describes.
///
/// The seven named buttons below — [FilledButton3d], [FilledTonalButton3d],
/// [OutlinedButton3d], [TextButton3d], [ElevatedButton3d], [IconButton3d] and
/// [FloatingActionButton3d] — are all *this widget* with a different
/// [ButtonStyle3d] in it. That is the claim the whole catalogue rests on: a
/// component is a `Material3d` with a set of tokens, and if a variant ever
/// needs more than that, the design has not held.
///
/// ```dart
/// Button3d(
///   style: ButtonStyle3d.of(Theme3d.of(context), ButtonVariant3d.filled),
///   onPressed: _save,
///   semanticLabel: 'Save',
///   child: const SceneText3d('Save'),
/// )
/// ```
///
/// ## The tree it builds, and why in that order
///
/// ```
/// SceneTapTarget3d      48dp of reach — outermost, deliberately
///   SceneSemantics3d    button: true, the label, enabled
///     SceneConstrainedBox3d   64 x 40dp minimum
///       Material3d      the slab: colour, shape, elevation, thickness, border
///         InkWell3d     the pointer and the focus, with no target of its own
///           SceneAlign3d  shrink-wrapped and centred on the front face
/// ```
///
/// **The tap target is the outermost box and that is load-bearing.** A
/// `TapTarget3d` reaches past its own extent and *every ancestor* gates a ray
/// on its own extent — so anything wrapped around it at the button's own size
/// rejects a press in the margin before the target ever sees it. That is the
/// panel, obviously; it is also the semantics box, which is why the semantics
/// sits inside rather than outside as Flutter's does (Flutter can afford the
/// other order because its `_InputPadding` grows the *layout* box, and this
/// one deliberately does not). The `InkWell3d` inside is therefore asked for
/// `minimumSize: Size3d.zero`: one target, not two nested ones disagreeing
/// about where the control is.
///
/// **The minimum size is 40dp and the target is 48dp**, which is not a
/// contradiction. A row of buttons is 40dp tall — that is the figure the
/// specification lays out with — and answers a finger 4dp above and below it,
/// because the reach is in the hit test rather than in the extent. Nothing
/// moves apart to make room for it.
///
/// ## What a state costs
///
/// A hover, a focus and a press write the *wash* through the ink controller,
/// which never rebuilds anything and never lays anything out. Two states also
/// move a **token**: a hover raises a filled or elevated button's elevation,
/// and the focus moves an outlined button's border to `primary`. Those cannot
/// go through the wash channel, so this widget rebuilds — but only when the
/// resolved style actually changed, which it checks by comparing the resolved
/// value. A text button's hover rebuilds nothing at all; a filled button's
/// rebuilds and still lays nothing out, because an elevation is a shader
/// uniform on a box that is already the right size.
///
/// ## Disabled is a substitution
///
/// `onPressed: null` disables the button, Flutter's own spelling. There is no
/// subtree opacity in this stack, so a disabled button is *drawn in different
/// colours*: `onSurface` at 12% for the container, at 38% for the label, the
/// icon and the outline, and elevation zero. See [ButtonStyle3d.resolve].
class Button3d extends StatefulWidget {
  /// Creates a button drawn with [style].
  const Button3d({
    super.key,
    required this.style,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.textDirection,
    this.child,
  });

  /// The tokens this button draws with, before a state has its say.
  final ButtonStyle3d style;

  /// Called when the button is tapped, or null to disable it.
  ///
  /// Null is Flutter's spelling of "disabled", and it is the only one here:
  /// there is no separate `enabled` flag to disagree with it.
  final GestureTapCallback? onPressed;

  /// Called when the button is long-pressed.
  final GestureLongPressCallback? onLongPress;

  /// Called when the pointer arrives over the button or leaves it.
  final ValueChanged<bool>? onHover;

  /// Called when the button gains or loses the focus.
  final ValueChanged<bool>? onFocusChange;

  /// The node holding this button's place in the focus tree.
  final FocusNode? focusNode;

  /// Whether the button takes the focus as soon as it is laid out.
  final bool autofocus;

  /// What a screen reader announces this button as.
  ///
  /// **State it.** `Semantics3d` publishes the properties it is given and does
  /// not gather a label out of the labels below it, the way Flutter's
  /// `Semantics(container: true)` merge does — there is no semantics tree
  /// under a scene node to merge. So a button with no [semanticLabel]
  /// announces itself as a button, enabled or not, with no name.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// What is drawn on the button: a label, an icon, or a row of both.
  final Widget? child;

  /// Whether the button responds at all.
  bool get enabled => onPressed != null || onLongPress != null;

  @override
  State<Button3d> createState() => _Button3dState();
}

class _Button3dState extends State<Button3d> {
  final Set<Material3dState> _states = <Material3dState>{};
  ResolvedButtonStyle3d? _resolved;

  /// Records a state and rebuilds **only if a token moved**.
  ///
  /// The wash is already on its way to the panel by the time this runs — the
  /// `InkWell3d` wrote it through the ink controller, touching no widget at
  /// all — so this method exists purely to notice the two transitions that
  /// change a colour or a height: a hover raising the elevation, and the
  /// focus moving an outline. Comparing the *resolved* style rather than the
  /// state set is what keeps a text button's hover free.
  void _note(Material3dState state, bool active) {
    // A gesture can arrive after the button has left the tree: the pointer
    // sequence holds the captured path, and a tap cancelled by the widget
    // being replaced is delivered to boxes whose widgets are already
    // defunct. `InkWell3d` survives that because its own teardown only
    // touches a controller; this one would call `setState` on a dead State.
    if (!mounted) return;
    if (active ? !_states.add(state) : !_states.remove(state)) return;
    final resolved = widget.style.resolve(_states, enabled: widget.enabled);
    if (resolved == _resolved) return;
    setState(() => _resolved = resolved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final enabled = widget.enabled;
    final style = widget.style;
    // Recomputed rather than read from the field: the theme, the style or the
    // enabled flag may have changed without any state moving.
    final resolved = _resolved = style.resolve(_states, enabled: enabled);

    return SceneTapTarget3d(
      // The outermost box of the whole button, and it has to be: a target
      // reaches past its own extent, every *ancestor* gates a ray on its own
      // extent, and the semantics box below is exactly the button's size. Put
      // the semantics outside and a press 4dp above the button is rejected by
      // the semantics box before the target ever sees it.
      //
      // A null minimum is Material's 48dp, resolved through the surface's
      // metrics at hit-test time so a camera-bound surface keeps it 48dp.
      child: SceneSemantics3d(
        properties: SemanticsProperties(
          button: true,
          enabled: enabled,
          label: widget.semanticLabel,
          textDirection: widget.textDirection,
          onTap: enabled ? widget.onPressed : null,
          onLongPress: enabled ? widget.onLongPress : null,
        ),
        child: SceneConstrainedBox3d(
          constraints: Constraints3d(
            minWidth: metrics.dp(style.minimumWidth),
            minHeight: metrics.dp(style.minimumHeight),
          ),
          child: Material3d(
            color: resolved.container,
            contentColor: resolved.content,
            shape: style.shape,
            elevation: resolved.elevation,
            thickness: style.thickness,
            border: resolved.border,
            padding: style.padding,
            textStyle: theme.textStyle(
              style.labelStyle,
              color: resolved.content,
            ),
            // The container hands its child the surface's own constraints
            // and the alignment happens below, so the button shrink-wraps its
            // label the way Flutter's `Align(widthFactor: 1.0)` makes it.
            alignment: null,
            // Material 3 turns the surface tint off on every button, and the
            // reason is not laziness: an elevated button's container token is
            // already `surfaceContainerLow`, which *is* the level-1 tint
            // baked into a colour. Applying it again double-counts.
            surfaceTint: const Color(0x00000000),
            child: InkWell3d(
              // One target, and it is the one outside this panel.
              minimumSize: Size3d.zero,
              enabled: enabled,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              onTap: widget.onPressed,
              onLongPress: widget.onLongPress,
              onHover: (hovered) {
                _note(Material3dState.hovered, hovered);
                widget.onHover?.call(hovered);
              },
              onHighlightChanged: (pressed) =>
                  _note(Material3dState.pressed, pressed),
              onFocusChange: (focused) {
                _note(Material3dState.focused, focused);
                widget.onFocusChange?.call(focused);
              },
              child: SceneAlign3d(
                alignment: Alignment3d.frontCenter,
                widthFactor: 1.0,
                heightFactor: 1.0,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The most emphatic button on a screen: a filled `primary` container.
///
/// ```dart
/// FilledButton3d(
///   onPressed: _submit,
///   semanticLabel: 'Continue',
///   child: const SceneText3d('Continue'),
/// )
/// ```
///
/// One action per screen, and the one the user is most likely to want. A
/// [Button3d] with `ButtonVariant3d.filled`, which is the whole of what a
/// variant is here.
class FilledButton3d extends _VariantButton3d {
  /// Creates a filled button. `onPressed: null` disables it.
  const FilledButton3d({
    super.key,
    super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
    super.style,
    super.child,
  });

  @override
  ButtonVariant3d get variant => ButtonVariant3d.filled;
}

/// A filled button at lower emphasis, on `secondaryContainer`.
///
/// For the action that is important but not the screen's one answer: "Add to
/// cart" beside "Buy now".
class FilledTonalButton3d extends _VariantButton3d {
  /// Creates a tonal button. `onPressed: null` disables it.
  const FilledTonalButton3d({
    super.key,
    super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
    super.style,
    super.child,
  });

  @override
  ButtonVariant3d get variant => ButtonVariant3d.filledTonal;
}

/// A transparent container inside a 1dp `outline`, for a secondary action.
///
/// The one variant whose *focus* changes a token rather than only the wash:
/// the border moves from `outline` to `primary`, which is the thing a
/// low-vision reader can see from further away than a 10% wash.
class OutlinedButton3d extends _VariantButton3d {
  /// Creates an outlined button. `onPressed: null` disables it.
  const OutlinedButton3d({
    super.key,
    super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
    super.style,
    super.child,
  });

  @override
  ButtonVariant3d get variant => ButtonVariant3d.outlined;
}

/// A label and nothing else: the lowest-emphasis button Material has.
///
/// Its padding is tighter than every other variant's — 12dp rather than 24 —
/// because there is no container for the label to sit inside.
class TextButton3d extends _VariantButton3d {
  /// Creates a text button. `onPressed: null` disables it.
  const TextButton3d({
    super.key,
    super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
    super.style,
    super.child,
  });

  @override
  ButtonVariant3d get variant => ButtonVariant3d.text;
}

/// A `surfaceContainerLow` container that rests at elevation level 1 and
/// rises to level 2 under a pointer.
///
/// The variant that shows off what this package does differently: in Flutter
/// the lift is a shadow recipe, and here it is a real 1dp of geometry that
/// occludes what is behind it and moves under the camera. What it is *not* is
/// a shadow — the panel shader blends, and `flutter_scene` keeps non-opaque
/// materials out of the shadow pass — so an elevated button reads as raised
/// through parallax rather than through a dark edge.
class ElevatedButton3d extends _VariantButton3d {
  /// Creates an elevated button. `onPressed: null` disables it.
  const ElevatedButton3d({
    super.key,
    super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
    super.style,
    super.child,
  });

  @override
  ButtonVariant3d get variant => ButtonVariant3d.elevated;
}

/// A round 40dp target around one 24dp icon, with no container at rest.
///
/// ```dart
/// IconButton3d(icon: Icons.close, onPressed: _dismiss, semanticLabel: 'Close')
/// ```
///
/// It takes an [IconData] rather than a child because the icon size is a
/// token: 24dp when the icon *is* the button, against 18dp for an icon beside
/// a label. There is no `IconTheme` in this stack to carry that down a
/// subtree, so the component states it.
///
/// **Give it a [semanticLabel].** An icon button has no text to fall back on,
/// and nothing here infers a name from a glyph.
class IconButton3d extends StatelessWidget {
  /// Creates an icon button. `onPressed: null` disables it.
  const IconButton3d({
    super.key,
    required this.icon,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.textDirection,
    this.style,
  });

  /// The glyph to draw.
  final IconData icon;

  /// Called when the button is tapped, or null to disable it.
  final GestureTapCallback? onPressed;

  /// Called when the button is long-pressed.
  final GestureLongPressCallback? onLongPress;

  /// Called when the pointer arrives over the button or leaves it.
  final ValueChanged<bool>? onHover;

  /// Called when the button gains or loses the focus.
  final ValueChanged<bool>? onFocusChange;

  /// The node holding this button's place in the focus tree.
  final FocusNode? focusNode;

  /// Whether the button takes the focus as soon as it is laid out.
  final bool autofocus;

  /// What a screen reader announces this button as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// The tokens to draw with, or null for the theme's icon-button style.
  final ButtonStyle3d? style;

  @override
  Widget build(BuildContext context) {
    final resolved =
        style ?? ButtonStyle3d.of(Theme3d.of(context), ButtonVariant3d.icon);
    return Button3d(
      style: resolved,
      onPressed: onPressed,
      onLongPress: onLongPress,
      onHover: onHover,
      onFocusChange: onFocusChange,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
      // No colour: the enclosing Material3d publishes the content colour as a
      // DefaultTextStyle, so the icon is disabled-grey without being told.
      child: Icon3d(icon, size: resolved.iconSize),
    );
  }
}

/// The screen's one prominent action: a 56dp `primaryContainer` square with a
/// 16dp radius, resting at elevation level 3.
///
/// ```dart
/// FloatingActionButton3d(
///   onPressed: _compose,
///   semanticLabel: 'Compose',
///   child: const Icon3d(Icons.edit),
/// )
/// ```
///
/// It is the variant that exercises the depth tokens hardest, and the numbers
/// are worth reading together. It is `thickness.raised` — 4dp — and it rests
/// 6dp toward the viewer, so it reaches `6 + 4/2 = 8dp` in front of the plane
/// it sits on. The theme's `thickness.depthStep` is 12dp, so it clears
/// anything stacked behind it with room to spare; a theme that raises the
/// elevation scale without raising the step would put a floating action
/// button *through* the layer above it, and `Thickness3d.separates` is the
/// predicate that says so out loud.
class FloatingActionButton3d extends _VariantButton3d {
  /// Creates a floating action button. `onPressed: null` disables it.
  const FloatingActionButton3d({
    super.key,
    super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
    super.style,
    super.child,
  });

  @override
  ButtonVariant3d get variant => ButtonVariant3d.floatingAction;
}

/// The shared body of the six variants that take a child.
///
/// Not exported: a caller who wants an eighth variant writes a [Button3d]
/// with a [ButtonStyle3d] of their own, which is the seam this class exists
/// to avoid duplicating rather than to hide.
abstract class _VariantButton3d extends StatelessWidget {
  const _VariantButton3d({
    super.key,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.textDirection,
    this.style,
    this.child,
  });

  /// Which variant's tokens this button resolves.
  ButtonVariant3d get variant;

  /// Called when the button is tapped, or null to disable it.
  final GestureTapCallback? onPressed;

  /// Called when the button is long-pressed.
  final GestureLongPressCallback? onLongPress;

  /// Called when the pointer arrives over the button or leaves it.
  final ValueChanged<bool>? onHover;

  /// Called when the button gains or loses the focus.
  final ValueChanged<bool>? onFocusChange;

  /// The node holding this button's place in the focus tree.
  final FocusNode? focusNode;

  /// Whether the button takes the focus as soon as it is laid out.
  final bool autofocus;

  /// What a screen reader announces this button as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// The tokens to draw with, or null for the theme's style for [variant].
  final ButtonStyle3d? style;

  /// What is drawn on the button.
  final Widget? child;

  @override
  Widget build(BuildContext context) => Button3d(
    style: style ?? ButtonStyle3d.of(Theme3d.of(context), variant),
    onPressed: onPressed,
    onLongPress: onLongPress,
    onHover: onHover,
    onFocusChange: onFocusChange,
    focusNode: focusNode,
    autofocus: autofocus,
    semanticLabel: semanticLabel,
    textDirection: textDirection,
    child: child,
  );
}
