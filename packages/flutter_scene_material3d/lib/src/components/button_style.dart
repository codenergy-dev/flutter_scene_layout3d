import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Border3d, BorderRadius3d, EdgeInsets3d;

import '../theme/theme_data.dart';
import '../tokens/state_layer.dart';
import '../tokens/typography.dart';

/// Which of Material's seven button shapes a [ButtonStyle3d] is for.
///
/// The enum exists so that one factory — [ButtonStyle3d.of] — can name every
/// variant, and so a test can walk them. The variants are not seven
/// implementations: `FilledButton3d` and `TextButton3d` are the same widget
/// with different tokens in it, and if that ever stops being true, this
/// package has lost the thing it was built to prove.
enum ButtonVariant3d {
  /// The most emphatic button: a filled `primary` container.
  filled,

  /// A filled button at lower emphasis, on `secondaryContainer`.
  filledTonal,

  /// A transparent container inside a one-pixel `outline`.
  outlined,

  /// A label and nothing else.
  text,

  /// A `surfaceContainerLow` container that rests at elevation level 1.
  elevated,

  /// A round target around a single icon, with no container at rest.
  icon,

  /// The screen's one prominent action: a 56dp `primaryContainer` square at
  /// elevation level 3.
  floatingAction,
}

/// Everything a button variant is made of, before a state has had its say.
///
/// This is Flutter's `ButtonStyle`, with the parts that do not survive the
/// move to three dimensions replaced by the ones that do. It is **public for
/// the reason Flutter's is**: a catalogue whose buttons cannot be restyled is
/// a demonstration rather than a library, and the alternative — a private
/// resolver, as this package's plan first proposed — would also have meant
/// that anything building a button in the *imperative* layer (a render probe,
/// a game with its own scene graph) had to reimplement the token table and
/// would then be checking its own arithmetic. That is the same argument that
/// made `Material3d.decorationFor` a static, and it lands the same way.
///
/// ```dart
/// FilledButton3d(
///   style: ButtonStyle3d.of(theme, ButtonVariant3d.filled)
///       .copyWith(shape: theme.shape.small),
///   onPressed: save,
///   child: const SceneText3d('Save'),
/// )
/// ```
///
/// ## What differs from Flutter's `ButtonStyle`
///
/// **There is no `WidgetStateProperty`.** Flutter needs one because any
/// property may vary with any state; here only four actually do — the
/// container colour, the content colour, the elevation and the outline — and
/// each varies in exactly one way. Naming those four out loud
/// ([disabledContainer], [disabledContent], [hoveredElevation],
/// [focusedOutline]) costs a reader nothing to understand and costs the
/// resolver no allocation, and it makes the whole table testable as a table.
///
/// **Disabled is a substitution, not an opacity.** There is no subtree
/// opacity anywhere in this stack, so a disabled button is drawn by swapping
/// colours: `onSurface` at 12% for the container, `onSurface` at 38% for the
/// label, the icon and the outline, and elevation zero. Those are the figures
/// Material's own specification states as the *result* of its 38% rule, so
/// this is the more faithful spelling as well as the only available one — and
/// `ColorScheme3d.disabledContainer` and `.disabledContent` are where they
/// come from.
///
/// **There is a [thickness], and Material has no token for it.** A button
/// here is a slab. The scale is the theme's, not this class's invention; a
/// variant only picks which step of it applies.
///
/// **Every figure is in logical pixels.** The shape, the padding, the
/// minimum size, the outline width, the elevation and the thickness are all
/// dp, and the component converts them through the surface's metrics. That is
/// the whole unit contract: a token is a specification figure, and world
/// units appear only where layout does.
@immutable
class ButtonStyle3d {
  /// Creates a style. Every field is required, because a half-stated style is
  /// a button drawing in a colour nobody chose.
  const ButtonStyle3d({
    required this.container,
    required this.content,
    required this.disabledContainer,
    required this.disabledContent,
    required this.elevation,
    required this.hoveredElevation,
    required this.outline,
    required this.focusedOutline,
    required this.disabledOutline,
    required this.outlineWidth,
    required this.shape,
    required this.thickness,
    required this.padding,
    required this.minimumWidth,
    required this.minimumHeight,
    required this.labelStyle,
    required this.iconSize,
  }) : assert(elevation >= 0.0),
       assert(hoveredElevation >= 0.0),
       assert(thickness >= 0.0),
       assert(outlineWidth >= 0.0),
       assert(minimumWidth >= 0.0),
       assert(minimumHeight >= 0.0),
       assert(iconSize > 0.0);

  /// The style Material publishes for [variant], out of [theme]'s tokens.
  ///
  /// The one place the seven variants differ. Everything downstream of this
  /// — the widget, the resolution by state, the geometry — is shared, which
  /// is the claim the whole phase exists to make good on.
  factory ButtonStyle3d.of(Theme3dData theme, ButtonVariant3d variant) {
    final scheme = theme.colorScheme;
    // Material's own disabled container for a variant that already has none
    // is *still* none: an outlined or text button that goes disabled keeps a
    // transparent slab and dims its outline and its label instead.
    const transparent = Color(0x00000000);

    // Shared by every variant. Material's own figures, checked against
    // `ButtonStyleButton.defaultStyleOf` in `test/button_defaults_test.dart`
    // rather than against a second transcription.
    ButtonStyle3d common({
      required Color container,
      required Color content,
      double elevation = 0.0,
      double? hoveredElevation,
      Color? outline,
      Color? focusedOutline,
      double outlineWidth = 1.0,
      BorderRadius3d? shape,
      double? thickness,
      EdgeInsets3d padding = const EdgeInsets3d.symmetric(horizontal: 24.0),
      double minimumWidth = 64.0,
      double minimumHeight = 40.0,
      Typography3dToken labelStyle = Typography3dToken.labelLarge,
      double iconSize = 18.0,
    }) => ButtonStyle3d(
      container: container,
      content: content,
      disabledContainer: container == transparent
          ? transparent
          : scheme.disabledContainer,
      disabledContent: scheme.disabledContent,
      elevation: elevation,
      hoveredElevation: hoveredElevation ?? elevation,
      outline: outline,
      focusedOutline: focusedOutline ?? outline,
      disabledOutline: outline == null ? null : scheme.disabledContainer,
      outlineWidth: outline == null ? 0.0 : outlineWidth,
      shape: shape ?? theme.shape.full,
      thickness: thickness ?? theme.thickness.standard,
      padding: padding,
      minimumWidth: minimumWidth,
      minimumHeight: minimumHeight,
      labelStyle: labelStyle,
      iconSize: iconSize,
    );

    return switch (variant) {
      ButtonVariant3d.filled => common(
        container: scheme.primary,
        content: scheme.onPrimary,
        hoveredElevation: theme.elevation.level1,
      ),
      ButtonVariant3d.filledTonal => common(
        container: scheme.secondaryContainer,
        content: scheme.onSecondaryContainer,
        hoveredElevation: theme.elevation.level1,
      ),
      ButtonVariant3d.outlined => common(
        container: transparent,
        content: scheme.primary,
        outline: scheme.outline,
        focusedOutline: scheme.primary,
      ),
      ButtonVariant3d.text => common(
        container: transparent,
        content: scheme.primary,
        padding: const EdgeInsets3d.symmetric(horizontal: 12.0, vertical: 8.0),
      ),
      ButtonVariant3d.elevated => common(
        container: scheme.surfaceContainerLow,
        content: scheme.primary,
        elevation: theme.elevation.level1,
        hoveredElevation: theme.elevation.level2,
      ),
      ButtonVariant3d.icon => common(
        container: transparent,
        content: scheme.onSurfaceVariant,
        padding: const EdgeInsets3d.symmetric(horizontal: 8.0, vertical: 8.0),
        minimumWidth: 40.0,
        minimumHeight: 40.0,
        iconSize: 24.0,
      ),
      ButtonVariant3d.floatingAction => common(
        container: scheme.primaryContainer,
        content: scheme.onPrimaryContainer,
        elevation: theme.elevation.level3,
        shape: theme.shape.large,
        thickness: theme.thickness.raised,
        padding: const EdgeInsets3d.symmetric(horizontal: 16.0, vertical: 16.0),
        minimumWidth: 56.0,
        minimumHeight: 56.0,
        iconSize: 24.0,
      ),
    };
  }

  /// The slab's colour at rest.
  final Color container;

  /// The colour of the label, the icon, and the state-layer wash.
  ///
  /// One property doing two jobs, exactly as [Material3d.contentColor] does,
  /// and Material's own rule is why: a wash is the surface's "on" colour at a
  /// low opacity, so a filled button washes in `onPrimary` and an outlined
  /// one in `primary`, without either saying so.
  final Color content;

  /// The slab's colour when the button is disabled: `onSurface` at 12%,
  /// except where the container was already transparent and stays so.
  final Color disabledContainer;

  /// The label and icon colour when disabled: `onSurface` at 38%.
  final Color disabledContent;

  /// How far the button stands off its parent at rest, in logical pixels.
  final double elevation;

  /// How far it stands off while hovered, in logical pixels.
  ///
  /// The one state that changes a button's height in Material 3: a filled
  /// button rises from level 0 to level 1 under a pointer, an elevated one
  /// from level 1 to level 2, and every other variant stays put. A *pressed*
  /// button drops back to [elevation], which is why the resolution is
  /// "hovered and not pressed" rather than simply "hovered".
  final double hoveredElevation;

  /// The outline's colour, or null for a variant that draws none.
  final Color? outline;

  /// The outline's colour while the button holds the focus.
  ///
  /// Material moves an outlined button's border from `outline` to `primary`
  /// when it is focused, which is the one thing distinguishing it from a
  /// wash that a low-vision reader can see at a distance.
  final Color? focusedOutline;

  /// The outline's colour when disabled: `onSurface` at 12%, the same figure
  /// as [disabledContainer].
  final Color? disabledOutline;

  /// How thick the outline is, in logical pixels. Zero when there is none.
  final double outlineWidth;

  /// The corner radii, in logical pixels. `shape.full` for every variant but
  /// the floating action button, which is `shape.large`.
  final BorderRadius3d shape;

  /// How deep the slab is, in logical pixels.
  ///
  /// `thickness.standard` for a button, `thickness.raised` for a floating
  /// action button. Never a number of this class's own invention: the scale
  /// lives in the theme so that a stack's depth step and the components in it
  /// can be checked against each other.
  final double thickness;

  /// Space between the slab's faces and its content, in logical pixels.
  ///
  /// **In-plane only, always.** A front or back inset pushes the label into
  /// the slab it is drawn on, where the panel wins the depth test and hides
  /// it with nothing to say why.
  final EdgeInsets3d padding;

  /// The narrowest the button may be, in logical pixels.
  final double minimumWidth;

  /// The shortest the button may be, in logical pixels.
  ///
  /// Material's 40dp, which is **not** the 48dp touch target: the target is
  /// grown in the hit test by a `TapTarget3d` outside the panel, so a row of
  /// buttons stays 40dp tall and still answers a finger 4dp above it.
  final double minimumHeight;

  /// Which type token the label takes. `labelLarge` for every variant.
  final Typography3dToken labelStyle;

  /// How tall an icon inside the button is, in logical pixels.
  ///
  /// 18dp beside a label, 24dp when the icon *is* the button — an
  /// `IconButton3d` or a floating action button.
  final double iconSize;

  /// This style with the given fields replaced.
  ButtonStyle3d copyWith({
    Color? container,
    Color? content,
    Color? disabledContainer,
    Color? disabledContent,
    double? elevation,
    double? hoveredElevation,
    Color? outline,
    Color? focusedOutline,
    Color? disabledOutline,
    double? outlineWidth,
    BorderRadius3d? shape,
    double? thickness,
    EdgeInsets3d? padding,
    double? minimumWidth,
    double? minimumHeight,
    Typography3dToken? labelStyle,
    double? iconSize,
  }) => ButtonStyle3d(
    container: container ?? this.container,
    content: content ?? this.content,
    disabledContainer: disabledContainer ?? this.disabledContainer,
    disabledContent: disabledContent ?? this.disabledContent,
    elevation: elevation ?? this.elevation,
    hoveredElevation: hoveredElevation ?? this.hoveredElevation,
    outline: outline ?? this.outline,
    focusedOutline: focusedOutline ?? this.focusedOutline,
    disabledOutline: disabledOutline ?? this.disabledOutline,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    shape: shape ?? this.shape,
    thickness: thickness ?? this.thickness,
    padding: padding ?? this.padding,
    minimumWidth: minimumWidth ?? this.minimumWidth,
    minimumHeight: minimumHeight ?? this.minimumHeight,
    labelStyle: labelStyle ?? this.labelStyle,
    iconSize: iconSize ?? this.iconSize,
  );

  /// What this style draws as, for a button in [states].
  ///
  /// The whole of the state table, in one place, in a fixed order of
  /// precedence:
  ///
  ///  1. **Disabled wins everything.** The container becomes
  ///     [disabledContainer], the content [disabledContent], the outline
  ///     [disabledOutline], and the elevation zero — a disabled control does
  ///     not float. The wash goes with it: an `InkWell3d` that is disabled
  ///     drops every state it was in, so nothing here has to unpick them.
  ///  2. **Hovered, and not pressed, raises the button** to
  ///     [hoveredElevation]. A press puts it back down.
  ///  3. **Focused moves the outline** to [focusedOutline].
  ///
  /// Everything else a state does is the *wash*, which is not this class's
  /// business at all: `StateLayerOpacity3d` resolves it and the ink
  /// controller writes it onto the panel without rebuilding anything. Keeping
  /// the two apart is what lets a hover be a uniform write while a disable is
  /// a rebuild.
  ResolvedButtonStyle3d resolve(
    Set<Material3dState> states, {
    required bool enabled,
  }) {
    if (!enabled) {
      return ResolvedButtonStyle3d(
        style: this,
        container: disabledContainer,
        content: disabledContent,
        elevation: 0.0,
        border: disabledOutline == null
            ? Border3d.none
            : Border3d(width: outlineWidth, color: disabledOutline!),
      );
    }
    final hovered =
        states.contains(Material3dState.hovered) &&
        !states.contains(Material3dState.pressed);
    final borderColor = states.contains(Material3dState.focused)
        ? focusedOutline
        : outline;
    return ResolvedButtonStyle3d(
      style: this,
      container: container,
      content: content,
      elevation: hovered ? hoveredElevation : elevation,
      border: borderColor == null
          ? Border3d.none
          : Border3d(width: outlineWidth, color: borderColor),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ButtonStyle3d &&
      other.container == container &&
      other.content == content &&
      other.disabledContainer == disabledContainer &&
      other.disabledContent == disabledContent &&
      other.elevation == elevation &&
      other.hoveredElevation == hoveredElevation &&
      other.outline == outline &&
      other.focusedOutline == focusedOutline &&
      other.disabledOutline == disabledOutline &&
      other.outlineWidth == outlineWidth &&
      other.shape == shape &&
      other.thickness == thickness &&
      other.padding == padding &&
      other.minimumWidth == minimumWidth &&
      other.minimumHeight == minimumHeight &&
      other.labelStyle == labelStyle &&
      other.iconSize == iconSize;

  @override
  int get hashCode => Object.hash(
    container,
    content,
    disabledContainer,
    disabledContent,
    elevation,
    hoveredElevation,
    outline,
    focusedOutline,
    disabledOutline,
    outlineWidth,
    shape,
    thickness,
    padding,
    minimumWidth,
    minimumHeight,
    Object.hash(labelStyle, iconSize),
  );

  @override
  String toString() =>
      'ButtonStyle3d($container on $content, ${elevation}dp, '
      '${thickness}dp thick)';
}

/// One button variant in one state: the four values that vary, and the style
/// the rest came from.
///
/// Handed straight to a [Material3d] — [container] is its colour, [content]
/// its content colour, [elevation] its lift, [border] its outline — so a
/// component that has resolved a style has nothing left to decide.
@immutable
class ResolvedButtonStyle3d {
  /// Records what [style] resolved to.
  const ResolvedButtonStyle3d({
    required this.style,
    required this.container,
    required this.content,
    required this.elevation,
    required this.border,
  });

  /// The style this was resolved from, for everything a state does not
  /// change: the shape, the thickness, the padding, the minimum size, the
  /// type token and the icon size.
  final ButtonStyle3d style;

  /// The slab's colour, in this state.
  final Color container;

  /// The label, icon and wash colour, in this state.
  final Color content;

  /// The lift, in logical pixels, in this state.
  final double elevation;

  /// The outline, in this state. [Border3d.none] for a variant without one.
  final Border3d border;

  @override
  bool operator ==(Object other) =>
      other is ResolvedButtonStyle3d &&
      other.style == style &&
      other.container == container &&
      other.content == content &&
      other.elevation == elevation &&
      other.border == border;

  @override
  int get hashCode => Object.hash(style, container, content, elevation, border);

  @override
  String toString() =>
      'ResolvedButtonStyle3d($container on $content, ${elevation}dp, $border)';
}
