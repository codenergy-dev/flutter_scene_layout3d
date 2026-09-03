import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter/gestures.dart' show GestureTapCallback;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        FocusNode,
        IconData,
        StatelessWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        Constraints3d,
        CrossAxisAlignment3d,
        MainAxisSize3d,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneConstrainedBox3d,
        SceneGestureDetector3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneTapTarget3d;

import '../theme/theme.dart';
import 'chip_style.dart';
import 'icon.dart';
import 'ink_well.dart';
import 'material.dart';

/// A compact 32dp control holding one short label, of whichever of Material's
/// four kinds its [style] describes.
///
/// ```dart
/// Chip3d(
///   variant: ChipVariant3d.filter,
///   label: const SceneText3d('Unread'),
///   selected: _unreadOnly,
///   onSelected: (value) => setState(() => _unreadOnly = value),
///   semanticLabel: 'Unread only',
/// )
/// ```
///
/// `AssistChip3d`, `FilterChip3d`, `InputChip3d` and `SuggestionChip3d` are
/// this widget with a different [ChipStyle3d] in it.
///
/// ## The one thing a chip does that no earlier component did
///
/// It is **selectable**, and selection here is a token substitution rather
/// than a wash: a selected chip is a filled `secondaryContainer` with no
/// outline, an unselected one is transparent inside an `outlineVariant`. That
/// is why `Material3dState` has no `selected` — a wash cannot express it —
/// and it means toggling a chip rebuilds it, where a hover does not.
///
/// An assist chip is not selectable at all, and the table says so rather than
/// the widget: `ChipStyle3d.selectable` is false for that variant and
/// [ChipStyle3d.resolve] drops the selection, so an assist chip cannot be
/// drawn as a filter one by accident.
///
/// ## The 48dp target earns its keep here
///
/// A chip is **32dp tall**, which is the smallest control in the catalogue
/// and sixteen short of Material's minimum touch target. The reach the
/// `TapTarget3d` adds is therefore doing real work rather than covering a
/// rounding error: a chip answers a finger 8dp above and below itself while
/// a row of chips stays 32dp tall and nothing moves apart. The target sits
/// outermost, outside the panel *and* the semantics box, for the reason
/// `Button3d`'s does — every ancestor gates a ray on its own extent.
///
/// ## The delete affordance, and what it cannot have
///
/// [onDeleted] adds a trailing icon that removes the chip, which is what an
/// input chip is for. It is a nested gesture rather than a nested
/// `InkWell3d`, and the limitation behind that is worth knowing before you
/// try to improve it:
///
///  * **It cannot have a reach of its own.** A second `TapTarget3d` inside
///    the chip's panel would be gated by the panel — the target reaches past
///    its extent, its ancestors do not — so the reach would be silently
///    inert. The delete zone is exactly the icon and the padding around it.
///  * **It cannot have a wash of its own.** The ink controller belongs to the
///    enclosing `Material3d`, so an ink well here would light the *whole
///    chip* up when the pointer was over the delete icon. Material draws a
///    small circular state layer behind the delete icon; expressing that
///    needs a second surface, and a second surface inside a 1dp slab is
///    coplanar with it.
///
/// So the delete affordance announces itself as its own button through a
/// `SceneSemantics3d`, takes the tap because the innermost recognizer wins
/// the arena, and is otherwise plain. That is honest and small; the
/// alternative is a phase of its own.
class Chip3d extends StatelessWidget {
  /// Creates a chip of [variant], or drawn with an explicit [style].
  const Chip3d({
    super.key,
    this.variant = ChipVariant3d.assist,
    this.style,
    required this.label,
    this.avatar,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.onSelected,
    this.onDeleted,
    this.deleteIcon,
    this.deleteSemanticLabel = 'Delete',
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.textDirection,
  });

  /// Which of the four kinds this chip is, when [style] is null.
  final ChipVariant3d variant;

  /// The tokens to draw with, or null for the theme's style for [variant].
  final ChipStyle3d? style;

  /// The chip's one short label.
  final Widget label;

  /// A leading icon or avatar, drawn at `style.iconSize`.
  ///
  /// Material also draws a checkmark in this slot on a selected filter chip.
  /// This package does not: a checkmark is a second glyph competing with the
  /// container substitution for the same signal, and the container is the one
  /// that survives at a distance. See the package README for what phase 4
  /// left out and why.
  final Widget? avatar;

  /// A trailing widget, drawn after the label.
  ///
  /// Ignored when [onDeleted] is set, which puts its own icon there.
  final Widget? trailing;

  /// Whether the chip is drawn as selected. Ignored by an assist chip.
  final bool selected;

  /// Whether the chip responds at all.
  final bool enabled;

  /// Called when the chip is tapped, for a chip that performs an action.
  final GestureTapCallback? onPressed;

  /// Called with the new value when a selectable chip is tapped.
  ///
  /// Pass this *or* [onPressed]; a chip given both prefers this one, since a
  /// chip that both toggled and acted would report its tap twice.
  final ValueChanged<bool>? onSelected;

  /// Called when the delete affordance is tapped, or null for no affordance.
  final GestureTapCallback? onDeleted;

  /// The glyph the delete affordance draws, or null for a cross.
  final IconData? deleteIcon;

  /// What a screen reader announces the delete affordance as.
  final String deleteSemanticLabel;

  /// The node holding this chip's place in the focus tree.
  final FocusNode? focusNode;

  /// Whether the chip takes the focus as soon as it is laid out.
  final bool autofocus;

  /// What a screen reader announces this chip as.
  ///
  /// **State it.** Nothing here gathers a label out of [label].
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// Material's own delete glyph, as an [IconData] this package can name
  /// without importing the whole icon set.
  ///
  /// `Icons.cancel`'s code point in the `MaterialIcons` font. Written out
  /// rather than imported because `package:flutter/material.dart` is a large
  /// dependency for one glyph, and because a chip must keep working when an
  /// application ships its own icon font.
  static const IconData defaultDeleteIcon = IconData(
    0xe888,
    fontFamily: 'MaterialIcons',
  );

  /// Whether the chip responds to a pointer.
  bool get interactive =>
      enabled && (onSelected != null || onPressed != null || onDeleted != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tokens = style ?? ChipStyle3d.of(theme, variant);
    final resolved = tokens.resolve(
      const {},
      selected: selected,
      enabled: enabled,
    );

    final tap = onSelected == null
        ? onPressed
        : () => onSelected!(!resolved.selected);

    final delete = onDeleted;
    final Widget? deleteAffordance = delete == null
        ? null
        // The innermost recognizer wins the arena, exactly as it does in
        // Flutter, so this takes the tap and the chip's own ink well does
        // not. It has no target and no wash of its own; see the class doc.
        : SceneSemantics3d(
            properties: SemanticsProperties(
              button: true,
              enabled: enabled,
              label: deleteSemanticLabel,
              textDirection: textDirection,
              onTap: enabled ? delete : null,
            ),
            child: SceneGestureDetector3d(
              onTap: enabled ? delete : null,
              child: Icon3d(
                deleteIcon ?? defaultDeleteIcon,
                size: tokens.iconSize,
              ),
            ),
          );

    final row = SceneRow3d(
      mainAxisSize: MainAxisSize3d.min,
      crossAxisAlignment: CrossAxisAlignment3d.center,
      // 8dp between the label and whatever is beside it, which is Material's
      // own gap and is what makes a chip's 16dp of horizontal padding sit
      // right against an 18dp icon.
      spacing: metrics.dp(8.0),
      children: <Widget>[
        if (avatar != null) avatar!,
        label,
        if (deleteAffordance != null)
          deleteAffordance
        else if (trailing != null)
          trailing!,
      ],
    );

    final surface = Material3d(
      color: resolved.container,
      contentColor: resolved.content,
      shape: tokens.shape,
      elevation: theme.elevation.level0,
      thickness: tokens.thickness,
      border: resolved.border,
      padding: tokens.padding,
      textStyle: theme.textStyle(tokens.labelStyle, color: resolved.content),
      // The chip shrink-wraps its label, so the alignment happens below the
      // ink well with a width factor, exactly as a button's does.
      alignment: null,
      surfaceTint: const Color(0x00000000),
      child: interactive && tap != null
          ? InkWell3d(
              // One target, and it is the one outside this panel.
              minimumSize: Size3d.zero,
              enabled: enabled,
              focusNode: focusNode,
              autofocus: autofocus,
              onTap: tap,
              child: SceneAlign3d(
                alignment: Alignment3d.frontCenter,
                widthFactor: 1.0,
                heightFactor: 1.0,
                child: row,
              ),
            )
          : SceneAlign3d(
              alignment: Alignment3d.frontCenter,
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: row,
            ),
    );

    final constrained = SceneConstrainedBox3d(
      constraints: theme.effectiveConstraints(
        Constraints3d(minHeight: metrics.dp(tokens.height)),
        metrics,
      ),
      child: surface,
    );

    final announced = SceneSemantics3d(
      properties: SemanticsProperties(
        button: true,
        enabled: enabled,
        // Only a chip that can hold a selection publishes one: announcing
        // "not selected" on an assist chip tells a reader about a state the
        // control does not have.
        selected: tokens.selectable ? resolved.selected : null,
        label: semanticLabel,
        textDirection: textDirection,
        onTap: enabled ? tap : null,
      ),
      child: constrained,
    );

    // Outermost, and here it is doing real work: a chip is 32dp tall and the
    // target is 48dp, so the reach is eight logical pixels of margin on each
    // side that no box in the layout knows about.
    return SceneTapTarget3d(child: announced);
  }
}

/// A chip that performs an action on the content beside it.
///
/// Not selectable: [Chip3d.selected] on one of these is dropped by the token
/// table rather than ignored by the widget, so the two cannot disagree.
class AssistChip3d extends _VariantChip3d {
  /// Creates an assist chip.
  const AssistChip3d({
    super.key,
    required super.label,
    super.style,
    super.avatar,
    super.trailing,
    super.enabled,
    super.onPressed,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
  });

  @override
  ChipVariant3d get variant => ChipVariant3d.assist;
}

/// A chip that toggles a filter, and the variant selection was designed for.
///
/// Selected it is a filled `secondaryContainer` with no outline; unselected
/// it is transparent inside an `outlineVariant`. Both of those are token
/// substitutions, so toggling one rebuilds it — which is correct and is not
/// on a per-frame path.
class FilterChip3d extends _VariantChip3d {
  /// Creates a filter chip.
  const FilterChip3d({
    super.key,
    required super.label,
    super.style,
    super.avatar,
    super.trailing,
    super.selected,
    super.enabled,
    super.onSelected,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
  });

  @override
  ChipVariant3d get variant => ChipVariant3d.filter;
}

/// A chip standing for something the user entered, usually with a delete
/// affordance.
///
/// ```dart
/// InputChip3d(
///   label: const SceneText3d('lucas@example.com'),
///   onDeleted: () => _removeRecipient(recipient),
///   semanticLabel: 'lucas@example.com',
/// )
/// ```
class InputChip3d extends _VariantChip3d {
  /// Creates an input chip.
  const InputChip3d({
    super.key,
    required super.label,
    super.style,
    super.avatar,
    super.selected,
    super.enabled,
    super.onPressed,
    super.onSelected,
    super.onDeleted,
    super.deleteIcon,
    super.deleteSemanticLabel,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
  });

  @override
  ChipVariant3d get variant => ChipVariant3d.input;
}

/// A chip offering a suggested reply or query.
class SuggestionChip3d extends _VariantChip3d {
  /// Creates a suggestion chip.
  const SuggestionChip3d({
    super.key,
    required super.label,
    super.style,
    super.avatar,
    super.trailing,
    super.selected,
    super.enabled,
    super.onPressed,
    super.onSelected,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.textDirection,
  });

  @override
  ChipVariant3d get variant => ChipVariant3d.suggestion;
}

/// The shared body of the four named chips.
///
/// Not exported: a caller who wants a fifth writes a [Chip3d] with a
/// [ChipStyle3d] of their own.
abstract class _VariantChip3d extends StatelessWidget {
  const _VariantChip3d({
    super.key,
    required this.label,
    this.style,
    this.avatar,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.onSelected,
    this.onDeleted,
    this.deleteIcon,
    this.deleteSemanticLabel = 'Delete',
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.textDirection,
  });

  /// Which variant's tokens this chip resolves.
  ChipVariant3d get variant;

  /// The chip's one short label.
  final Widget label;

  /// The tokens to draw with, or null for the theme's style for [variant].
  final ChipStyle3d? style;

  /// A leading icon or avatar.
  final Widget? avatar;

  /// A trailing widget.
  final Widget? trailing;

  /// Whether the chip is drawn as selected.
  final bool selected;

  /// Whether the chip responds at all.
  final bool enabled;

  /// Called when the chip is tapped.
  final GestureTapCallback? onPressed;

  /// Called with the new value when a selectable chip is tapped.
  final ValueChanged<bool>? onSelected;

  /// Called when the delete affordance is tapped.
  final GestureTapCallback? onDeleted;

  /// The glyph the delete affordance draws.
  final IconData? deleteIcon;

  /// What a screen reader announces the delete affordance as.
  final String deleteSemanticLabel;

  /// The node holding this chip's place in the focus tree.
  final FocusNode? focusNode;

  /// Whether the chip takes the focus as soon as it is laid out.
  final bool autofocus;

  /// What a screen reader announces this chip as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) => Chip3d(
    variant: variant,
    style: style,
    label: label,
    avatar: avatar,
    trailing: trailing,
    selected: selected,
    enabled: enabled,
    onPressed: onPressed,
    onSelected: onSelected,
    onDeleted: onDeleted,
    deleteIcon: deleteIcon,
    deleteSemanticLabel: deleteSemanticLabel,
    focusNode: focusNode,
    autofocus: autofocus,
    semanticLabel: semanticLabel,
    textDirection: textDirection,
  );
}
