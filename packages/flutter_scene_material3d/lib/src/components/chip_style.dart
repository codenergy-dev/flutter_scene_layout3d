import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Border3d, BorderRadius3d, EdgeInsets3d;

import '../theme/theme_data.dart';
import '../tokens/state_layer.dart';
import '../tokens/typography.dart';

/// Which of Material 3's four chips a [ChipStyle3d] is for.
///
/// They differ in remarkably little — one label colour and whether a
/// selection is meaningful — which is the same result the seven buttons gave
/// and is the reason this is a token table rather than four widgets.
enum ChipVariant3d {
  /// A chip that performs an action on the thing beside it. It has no
  /// selected state: `Chip3d.selected` on one is ignored by the table.
  assist,

  /// A chip that toggles a filter on and off. The variant selection was
  /// designed for.
  filter,

  /// A chip standing for something the user entered, usually with a delete
  /// affordance.
  input,

  /// A chip offering a suggested reply or query.
  suggestion,
}

/// Everything a chip variant is made of, before a state has had its say.
///
/// The same shape as `ButtonStyle3d`, with one addition that matters: a chip
/// is the first component in this catalogue whose **selection** changes its
/// tokens. Selection is a substitution here, not a wash — `Material3dState`
/// deliberately has no `selected` — so it lives in this table beside the
/// disabled figures and [resolve] applies both.
///
/// Every figure is in logical pixels.
@immutable
class ChipStyle3d {
  /// Creates a chip style. Every field is required, for the reason
  /// `ButtonStyle3d`'s are.
  const ChipStyle3d({
    required this.container,
    required this.content,
    required this.selectedContainer,
    required this.selectedContent,
    required this.disabledContainer,
    required this.disabledContent,
    required this.outline,
    required this.selectedOutline,
    required this.disabledOutline,
    required this.outlineWidth,
    required this.shape,
    required this.thickness,
    required this.padding,
    required this.height,
    required this.labelStyle,
    required this.iconSize,
    required this.selectable,
  }) : assert(thickness >= 0.0),
       assert(outlineWidth >= 0.0),
       assert(height >= 0.0),
       assert(iconSize > 0.0);

  /// The style Material publishes for [variant], out of [theme]'s tokens.
  ///
  /// Checked in `test/chip_test.dart` against the figures Flutter's own chip
  /// defaults use. Two of those — the 32dp height and the 8dp radius — are
  /// transcriptions and say so in the test: `_ChipDefaultsM3` is private,
  /// `ChipTheme.of` returns an application's overrides rather than the
  /// resolved defaults, and `_kChipHeight` is a private constant. The colours
  /// are `ColorScheme3d` roles, which the colour-scheme suite already checks
  /// against Flutter's generated table.
  factory ChipStyle3d.of(Theme3dData theme, ChipVariant3d variant) {
    final scheme = theme.colorScheme;
    const transparent = Color(0x00000000);
    ChipStyle3d common({required Color content, bool selectable = true}) =>
        ChipStyle3d(
          container: transparent,
          content: content,
          selectedContainer: scheme.secondaryContainer,
          selectedContent: scheme.onSecondaryContainer,
          // A chip's container is transparent at rest, so a disabled one has
          // nothing to dim; Material dims the outline and the label instead,
          // exactly as it does for an outlined button.
          disabledContainer: transparent,
          disabledContent: scheme.disabledContent,
          outline: scheme.outlineVariant,
          // A selected chip has a filled container and drops its outline —
          // the container is the signal, and an outline round it would read
          // as a second, competing one.
          selectedOutline: null,
          disabledOutline: scheme.disabledContainer,
          outlineWidth: 1.0,
          shape: theme.shape.small,
          thickness: theme.thickness.thin,
          padding: const EdgeInsets3d.symmetric(
            horizontal: 16.0,
            vertical: 6.0,
          ),
          height: defaultHeight,
          labelStyle: Typography3dToken.labelLarge,
          iconSize: 18.0,
          selectable: selectable,
        );

    return switch (variant) {
      // An assist chip's label is `onSurface` rather than `onSurfaceVariant`,
      // and it has no selected state at all: it performs an action.
      ChipVariant3d.assist => common(
        content: scheme.onSurface,
        selectable: false,
      ),
      ChipVariant3d.filter => common(content: scheme.onSurfaceVariant),
      ChipVariant3d.input => common(content: scheme.onSurfaceVariant),
      ChipVariant3d.suggestion => common(content: scheme.onSurfaceVariant),
    };
  }

  /// Material's chip height, in logical pixels.
  static const double defaultHeight = 32.0;

  /// The slab's colour at rest: transparent for every variant Material
  /// publishes.
  final Color container;

  /// The label, icon and wash colour at rest.
  final Color content;

  /// The slab's colour when selected: `secondaryContainer`.
  final Color selectedContainer;

  /// The label, icon and wash colour when selected: `onSecondaryContainer`.
  final Color selectedContent;

  /// The slab's colour when disabled.
  final Color disabledContainer;

  /// The label and icon colour when disabled: `onSurface` at 38%.
  final Color disabledContent;

  /// The outline's colour at rest: `outlineVariant`.
  final Color? outline;

  /// The outline's colour when selected, or null for none.
  final Color? selectedOutline;

  /// The outline's colour when disabled: `onSurface` at 12%.
  final Color? disabledOutline;

  /// How thick the outline is, in logical pixels.
  ///
  /// One, which at the default unit rate is a hundredth of a world unit. See
  /// `Divider3d` for what that means when something has to *see* it.
  final double outlineWidth;

  /// The corner radii, in logical pixels: `shape.small`, 8dp.
  final BorderRadius3d shape;

  /// How deep the slab is, in logical pixels: `thickness.thin`, 1dp.
  ///
  /// The thinnest component in the catalogue, and deliberately so — a chip is
  /// a label with an edge, not an object. It also means a row of chips on a
  /// card never fights the card for the depth buffer, whatever the step.
  final double thickness;

  /// Space between the slab's faces and its content, in logical pixels.
  ///
  /// 16dp horizontally — Material's 8dp of chip padding plus 8dp of label
  /// padding, which this package folds into one figure because there is no
  /// second box between them to hang the other half on — and 6dp vertically,
  /// which is what leaves a 20dp `labelLarge` line inside a 32dp chip.
  ///
  /// **In-plane only.**
  final EdgeInsets3d padding;

  /// How tall the chip is, in logical pixels: Material's 32dp.
  final double height;

  /// Which type token the label takes: `labelLarge`.
  final Typography3dToken labelStyle;

  /// How tall a leading or trailing icon is, in logical pixels: 18dp.
  final double iconSize;

  /// Whether a selection means anything for this variant.
  ///
  /// False for an assist chip, which performs an action rather than holding a
  /// state. [resolve] ignores `selected` when this is false, so a caller
  /// cannot accidentally draw an assist chip as a filter one.
  final bool selectable;

  /// This style with the given fields replaced.
  ChipStyle3d copyWith({
    Color? container,
    Color? content,
    Color? selectedContainer,
    Color? selectedContent,
    Color? disabledContainer,
    Color? disabledContent,
    Color? outline,
    Color? selectedOutline,
    Color? disabledOutline,
    double? outlineWidth,
    BorderRadius3d? shape,
    double? thickness,
    EdgeInsets3d? padding,
    double? height,
    Typography3dToken? labelStyle,
    double? iconSize,
    bool? selectable,
  }) => ChipStyle3d(
    container: container ?? this.container,
    content: content ?? this.content,
    selectedContainer: selectedContainer ?? this.selectedContainer,
    selectedContent: selectedContent ?? this.selectedContent,
    disabledContainer: disabledContainer ?? this.disabledContainer,
    disabledContent: disabledContent ?? this.disabledContent,
    outline: outline ?? this.outline,
    selectedOutline: selectedOutline ?? this.selectedOutline,
    disabledOutline: disabledOutline ?? this.disabledOutline,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    shape: shape ?? this.shape,
    thickness: thickness ?? this.thickness,
    padding: padding ?? this.padding,
    height: height ?? this.height,
    labelStyle: labelStyle ?? this.labelStyle,
    iconSize: iconSize ?? this.iconSize,
    selectable: selectable ?? this.selectable,
  );

  /// What this style draws as, for a chip that is [selected] or not and
  /// [enabled] or not.
  ///
  /// The precedence, and it is the same one `ButtonStyle3d.resolve` uses:
  ///
  ///  1. **Disabled wins everything**, selection included. A disabled
  ///     selected chip keeps its selected *container* — the selection is
  ///     information the reader still needs — and dims its label and its
  ///     outline.
  ///  2. **Selected substitutes** the container, the content and the outline.
  ///  3. Everything else a state does is the wash, which is not this class's
  ///     business: `StateLayerOpacity3d` resolves it and the ink controller
  ///     writes it without rebuilding anything.
  ///
  /// [states] is taken for symmetry with `ButtonStyle3d.resolve` and because
  /// a restyled chip may want to read it; the baseline table uses none of it,
  /// which is exactly why a chip's hover, focus and press cost no rebuild.
  ResolvedChipStyle3d resolve(
    Set<Material3dState> states, {
    required bool selected,
    required bool enabled,
  }) {
    final isSelected = selected && selectable;
    if (!enabled) {
      return ResolvedChipStyle3d(
        style: this,
        selected: isSelected,
        container: isSelected ? selectedContainer : disabledContainer,
        content: disabledContent,
        border: disabledOutline == null || isSelected
            ? Border3d.none
            : Border3d(width: outlineWidth, color: disabledOutline!),
      );
    }
    final color = isSelected ? selectedOutline : outline;
    return ResolvedChipStyle3d(
      style: this,
      selected: isSelected,
      container: isSelected ? selectedContainer : container,
      content: isSelected ? selectedContent : content,
      border: color == null
          ? Border3d.none
          : Border3d(width: outlineWidth, color: color),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChipStyle3d &&
      other.container == container &&
      other.content == content &&
      other.selectedContainer == selectedContainer &&
      other.selectedContent == selectedContent &&
      other.disabledContainer == disabledContainer &&
      other.disabledContent == disabledContent &&
      other.outline == outline &&
      other.selectedOutline == selectedOutline &&
      other.disabledOutline == disabledOutline &&
      other.outlineWidth == outlineWidth &&
      other.shape == shape &&
      other.thickness == thickness &&
      other.padding == padding &&
      other.height == height &&
      other.labelStyle == labelStyle &&
      other.iconSize == iconSize &&
      other.selectable == selectable;

  @override
  int get hashCode => Object.hash(
    container,
    content,
    selectedContainer,
    selectedContent,
    disabledContainer,
    disabledContent,
    outline,
    selectedOutline,
    disabledOutline,
    outlineWidth,
    shape,
    thickness,
    padding,
    height,
    Object.hash(labelStyle, iconSize, selectable),
  );

  @override
  String toString() =>
      'ChipStyle3d($container on $content, ${height}dp, '
      '${thickness}dp thick)';
}

/// One chip variant in one state: the three values that vary, and the style
/// the rest came from.
@immutable
class ResolvedChipStyle3d {
  /// Records what [style] resolved to.
  const ResolvedChipStyle3d({
    required this.style,
    required this.selected,
    required this.container,
    required this.content,
    required this.border,
  });

  /// The style this was resolved from.
  final ChipStyle3d style;

  /// Whether the chip is drawn as selected, after the variant has had its say
  /// — false on an assist chip whatever the caller asked for.
  final bool selected;

  /// The slab's colour, in this state.
  final Color container;

  /// The label, icon and wash colour, in this state.
  final Color content;

  /// The outline, in this state.
  final Border3d border;

  @override
  bool operator ==(Object other) =>
      other is ResolvedChipStyle3d &&
      other.style == style &&
      other.selected == selected &&
      other.container == container &&
      other.content == content &&
      other.border == border;

  @override
  int get hashCode => Object.hash(style, selected, container, content, border);

  @override
  String toString() =>
      'ResolvedChipStyle3d($container on $content, $border'
      '${selected ? ', selected' : ''})';
}
