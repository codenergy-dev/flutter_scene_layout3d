import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Border3d, BorderRadius3d;

import '../theme/theme_data.dart';
import '../tokens/color_scheme.dart';
import '../tokens/depth.dart';
import '../tokens/state_layer.dart';

/// The transparent colour every one of these tables uses for "nothing here".
const Color _none = Color(0x00000000);

/// Everything a [Checkbox3d] is made of, before a state has had its say.
///
/// Material's checkbox is **18dp of ink inside a 40dp state layer inside a
/// 48dp touch target**, and all three of those figures are in this table
/// because all three are things a component draws or reaches with. The 18dp
/// is `Checkbox.width`, which is one of the few Material figures Flutter
/// publishes as a public constant, so `test/selection_defaults_test.dart`
/// reads it rather than transcribing it.
///
/// Every figure is in logical pixels.
///
/// ## The mark is the whole signal, unlike a filter chip's
///
/// Phase 4 declined to draw a checkmark on a selected filter chip, because
/// the container substitution already carried the signal and a glyph would
/// have been a second voice saying the same thing. A checkbox is the opposite
/// case: the container substitution *is* the box turning `primary`, and
/// without the mark a selected checkbox and a filled 18dp square are the same
/// picture. So the mark is drawn, at [markSize], as one glyph of the icon
/// font — the same path `Icon3d` takes.
@immutable
class CheckboxStyle3d {
  /// Creates a checkbox style. Every field is required, for the reason
  /// `ButtonStyle3d`'s are: a table with a default in it is a table that can
  /// drift from the specification without anybody noticing.
  const CheckboxStyle3d({
    required this.size,
    required this.stateLayerSize,
    required this.shape,
    required this.container,
    required this.selectedContainer,
    required this.disabledContainer,
    required this.disabledSelectedContainer,
    required this.mark,
    required this.disabledMark,
    required this.markSize,
    required this.outline,
    required this.disabledOutline,
    required this.outlineWidth,
    required this.thickness,
    required this.depthStep,
    required this.selectedWash,
    required this.wash,
  }) : assert(size > 0.0),
       assert(stateLayerSize >= size),
       assert(markSize > 0.0),
       assert(outlineWidth >= 0.0),
       assert(thickness >= 0.0),
       assert(depthStep > thickness / 2.0);

  /// The style Material publishes, out of [theme]'s tokens.
  ///
  /// Checked in `test/selection_defaults_test.dart` against
  /// `_CheckboxDefaultsM3`'s figures. The 18dp comes from `Checkbox.width`,
  /// which is public; the 2dp corner and the 2dp outline are transcriptions
  /// and say so in the test.
  factory CheckboxStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return CheckboxStyle3d(
      size: defaultSize,
      stateLayerSize: defaultStateLayerSize,
      shape: const BorderRadius3d.circular(2.0),
      container: _none,
      selectedContainer: scheme.primary,
      disabledContainer: _none,
      // Material keeps a disabled *selected* checkbox filled, at the same
      // 38% figure a disabled label uses, so the reader can still see what
      // the answer was.
      disabledSelectedContainer: scheme.disabledContent,
      mark: scheme.onPrimary,
      disabledMark: scheme.surface,
      markSize: defaultSize,
      outline: scheme.onSurfaceVariant,
      disabledOutline: scheme.disabledContent,
      outlineWidth: 2.0,
      thickness: theme.thickness.thin,
      depthStep: Thickness3d.stepOver(
        theme.thickness.thin,
        theme.thickness.thin,
      ),
      wash: scheme.onSurface,
      selectedWash: scheme.primary,
    );
  }

  /// Material's checkbox size, in logical pixels: `Checkbox.width`.
  static const double defaultSize = 18.0;

  /// Material's checkbox state-layer size, in logical pixels.
  ///
  /// Not the touch target, which is 48dp and comes from
  /// `TapTarget3d.materialMinimum`. This is the circle the hover, focus and
  /// press wash fills, and it is the control's own *extent* — so a row of
  /// checkboxes is 40dp tall and the extra eight are reach that no box in
  /// the layout knows about.
  static const double defaultStateLayerSize = 40.0;

  /// How wide and tall the box is, in logical pixels: 18dp.
  final double size;

  /// How wide the wash around it is, in logical pixels: 40dp.
  final double stateLayerSize;

  /// The box's corner radii, in logical pixels: 2dp.
  final BorderRadius3d shape;

  /// The box's colour when it is not selected: transparent.
  final Color container;

  /// The box's colour when it is: `primary`.
  final Color selectedContainer;

  /// The box's colour when disabled and unselected: transparent.
  final Color disabledContainer;

  /// The box's colour when disabled and selected: `onSurface` at 38%.
  final Color disabledSelectedContainer;

  /// The checkmark's colour: `onPrimary`.
  final Color mark;

  /// The checkmark's colour on a disabled selected box: `surface`.
  final Color disabledMark;

  /// How tall the checkmark glyph is, in logical pixels.
  ///
  /// The same 18dp as the box, because a glyph's em box is bigger than its
  /// ink: `Icons.check` at 18dp draws roughly 13 by 9 of actual mark, which
  /// is what sits inside an 18dp square with a margin.
  final double markSize;

  /// The outline's colour when the box is empty: `onSurfaceVariant`.
  final Color outline;

  /// The outline's colour when the box is empty and disabled.
  final Color disabledOutline;

  /// How thick the outline is, in logical pixels: 2dp.
  final double outlineWidth;

  /// How deep the box's slab is, in logical pixels: `thickness.thin`.
  final double thickness;

  /// How far the mark stands in front of the box, in logical pixels.
  ///
  /// [Thickness3d.stepOver], because a glyph drawn exactly on the box's front
  /// face is coplanar with it and z-fights — the same argument `Divider3d`
  /// makes about a rule on a card and `NavigationStyle3d.indicatorDepthStep`
  /// makes about a glyph on a pill.
  final double depthStep;

  /// The wash colour when the box is empty: `onSurface`.
  final Color wash;

  /// The wash colour when it is full: `primary`.
  final Color selectedWash;

  /// This style with the given fields replaced.
  CheckboxStyle3d copyWith({
    double? size,
    double? stateLayerSize,
    BorderRadius3d? shape,
    Color? container,
    Color? selectedContainer,
    Color? disabledContainer,
    Color? disabledSelectedContainer,
    Color? mark,
    Color? disabledMark,
    double? markSize,
    Color? outline,
    Color? disabledOutline,
    double? outlineWidth,
    double? thickness,
    double? depthStep,
    Color? wash,
    Color? selectedWash,
  }) => CheckboxStyle3d(
    size: size ?? this.size,
    stateLayerSize: stateLayerSize ?? this.stateLayerSize,
    shape: shape ?? this.shape,
    container: container ?? this.container,
    selectedContainer: selectedContainer ?? this.selectedContainer,
    disabledContainer: disabledContainer ?? this.disabledContainer,
    disabledSelectedContainer:
        disabledSelectedContainer ?? this.disabledSelectedContainer,
    mark: mark ?? this.mark,
    disabledMark: disabledMark ?? this.disabledMark,
    markSize: markSize ?? this.markSize,
    outline: outline ?? this.outline,
    disabledOutline: disabledOutline ?? this.disabledOutline,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    thickness: thickness ?? this.thickness,
    depthStep: depthStep ?? this.depthStep,
    wash: wash ?? this.wash,
    selectedWash: selectedWash ?? this.selectedWash,
  );

  /// What this style draws as, for a box that is [selected] or not and
  /// [enabled] or not.
  ///
  /// The precedence is `ButtonStyle3d.resolve`'s and `ChipStyle3d.resolve`'s:
  /// disabled wins everything except the *fact* of the selection, which is
  /// information the reader still needs; selection substitutes the container,
  /// the outline and the mark; and the wash is not this class's business.
  ///
  /// [states] is taken for symmetry with the other tables and because a
  /// restyled checkbox may want to read it. The baseline table uses none of
  /// it — which is exactly why a checkbox's hover costs no rebuild.
  ResolvedCheckboxStyle3d resolve(
    Set<Material3dState> states, {
    required bool selected,
    required bool enabled,
  }) {
    if (!enabled) {
      return ResolvedCheckboxStyle3d(
        style: this,
        selected: selected,
        container: selected ? disabledSelectedContainer : disabledContainer,
        mark: selected ? disabledMark : _none,
        // A filled box has no outline: the fill is the edge.
        border: selected
            ? Border3d.none
            : Border3d(width: outlineWidth, color: disabledOutline),
        wash: selected ? selectedWash : wash,
      );
    }
    return ResolvedCheckboxStyle3d(
      style: this,
      selected: selected,
      container: selected ? selectedContainer : container,
      mark: selected ? mark : _none,
      border: selected
          ? Border3d.none
          : Border3d(width: outlineWidth, color: outline),
      wash: selected ? selectedWash : wash,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CheckboxStyle3d &&
      other.size == size &&
      other.stateLayerSize == stateLayerSize &&
      other.shape == shape &&
      other.container == container &&
      other.selectedContainer == selectedContainer &&
      other.disabledContainer == disabledContainer &&
      other.disabledSelectedContainer == disabledSelectedContainer &&
      other.mark == mark &&
      other.disabledMark == disabledMark &&
      other.markSize == markSize &&
      other.outline == outline &&
      other.disabledOutline == disabledOutline &&
      other.outlineWidth == outlineWidth &&
      other.thickness == thickness &&
      other.depthStep == depthStep &&
      other.wash == wash &&
      other.selectedWash == selectedWash;

  @override
  int get hashCode => Object.hash(
    size,
    stateLayerSize,
    shape,
    container,
    selectedContainer,
    disabledContainer,
    disabledSelectedContainer,
    mark,
    disabledMark,
    markSize,
    outline,
    disabledOutline,
    outlineWidth,
    thickness,
    depthStep,
    Object.hash(wash, selectedWash),
  );

  @override
  String toString() => 'CheckboxStyle3d(${size}dp in ${stateLayerSize}dp)';
}

/// One checkbox in one state: the four values that vary, and the style the
/// rest came from.
@immutable
class ResolvedCheckboxStyle3d {
  /// Records what [style] resolved to.
  const ResolvedCheckboxStyle3d({
    required this.style,
    required this.selected,
    required this.container,
    required this.mark,
    required this.border,
    required this.wash,
  });

  /// The style this was resolved from.
  final CheckboxStyle3d style;

  /// Whether the box is drawn as full.
  final bool selected;

  /// The box's colour, in this state.
  final Color container;

  /// The checkmark's colour, or transparent when there is no mark.
  final Color mark;

  /// The box's outline, in this state.
  final Border3d border;

  /// The colour the state layer washes with.
  final Color wash;

  /// Whether a mark is drawn at all.
  bool get hasMark => mark.a > 0.0;

  @override
  bool operator ==(Object other) =>
      other is ResolvedCheckboxStyle3d &&
      other.style == style &&
      other.selected == selected &&
      other.container == container &&
      other.mark == mark &&
      other.border == border &&
      other.wash == wash;

  @override
  int get hashCode =>
      Object.hash(style, selected, container, mark, border, wash);

  @override
  String toString() =>
      'ResolvedCheckboxStyle3d($container, mark $mark, $border)';
}

/// Everything a [Radio3d] is made of, before a state has had its say.
///
/// Two concentric stadiums, which is all a radio button is: a ring at
/// [outerSize] with an [outlineWidth] edge and nothing inside it, and a dot
/// at [innerSize] that appears when the option is chosen.
/// `ShapeScale3d.full` makes a circle out of a square box, so neither of
/// those needed anything the catalogue did not already have.
///
/// Every figure is in logical pixels.
@immutable
class RadioStyle3d {
  /// Creates a radio style.
  const RadioStyle3d({
    required this.outerSize,
    required this.innerSize,
    required this.stateLayerSize,
    required this.outline,
    required this.selectedOutline,
    required this.disabledOutline,
    required this.outlineWidth,
    required this.dot,
    required this.disabledDot,
    required this.thickness,
    required this.depthStep,
    required this.wash,
    required this.selectedWash,
  }) : assert(outerSize > 0.0),
       assert(innerSize > 0.0),
       assert(innerSize < outerSize),
       assert(stateLayerSize >= outerSize),
       assert(outlineWidth >= 0.0),
       assert(thickness >= 0.0),
       assert(depthStep > thickness / 2.0);

  /// The style Material publishes, out of [theme]'s tokens.
  ///
  /// The two diameters are transcriptions: Flutter's `_kOuterRadius` and
  /// `_kInnerRadius` are private and there is no accessor for either, so
  /// `test/selection_defaults_test.dart` states them as figures and says so.
  /// The colours are `ColorScheme3d` roles, which the colour-scheme suite
  /// already checks against Flutter's generated table.
  factory RadioStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return RadioStyle3d(
      outerSize: defaultOuterSize,
      innerSize: defaultInnerSize,
      stateLayerSize: CheckboxStyle3d.defaultStateLayerSize,
      outline: scheme.onSurfaceVariant,
      selectedOutline: scheme.primary,
      disabledOutline: scheme.disabledContent,
      outlineWidth: 2.0,
      dot: scheme.primary,
      disabledDot: scheme.disabledContent,
      thickness: theme.thickness.thin,
      depthStep: Thickness3d.stepOver(
        theme.thickness.thin,
        theme.thickness.thin,
      ),
      wash: scheme.onSurface,
      selectedWash: scheme.primary,
    );
  }

  /// The ring's diameter, in logical pixels: Flutter's `_kOuterRadius * 2`.
  static const double defaultOuterSize = 16.0;

  /// The dot's diameter, in logical pixels: Flutter's `_kInnerRadius * 2`.
  static const double defaultInnerSize = 9.0;

  /// How wide the ring is, in logical pixels.
  final double outerSize;

  /// How wide the dot inside it is, in logical pixels.
  final double innerSize;

  /// How wide the wash around both is, in logical pixels: 40dp.
  final double stateLayerSize;

  /// The ring's colour when the option is not chosen: `onSurfaceVariant`.
  final Color outline;

  /// The ring's colour when it is: `primary`.
  final Color selectedOutline;

  /// The ring's colour when the control is disabled.
  final Color disabledOutline;

  /// How thick the ring is, in logical pixels: 2dp.
  final double outlineWidth;

  /// The dot's colour: `primary`.
  final Color dot;

  /// The dot's colour when the control is disabled.
  final Color disabledDot;

  /// How deep the ring's slab is, in logical pixels: `thickness.thin`.
  final double thickness;

  /// How far the dot stands in front of the ring, in logical pixels.
  final double depthStep;

  /// The wash colour when the option is not chosen: `onSurface`.
  final Color wash;

  /// The wash colour when it is: `primary`.
  final Color selectedWash;

  /// This style with the given fields replaced.
  RadioStyle3d copyWith({
    double? outerSize,
    double? innerSize,
    double? stateLayerSize,
    Color? outline,
    Color? selectedOutline,
    Color? disabledOutline,
    double? outlineWidth,
    Color? dot,
    Color? disabledDot,
    double? thickness,
    double? depthStep,
    Color? wash,
    Color? selectedWash,
  }) => RadioStyle3d(
    outerSize: outerSize ?? this.outerSize,
    innerSize: innerSize ?? this.innerSize,
    stateLayerSize: stateLayerSize ?? this.stateLayerSize,
    outline: outline ?? this.outline,
    selectedOutline: selectedOutline ?? this.selectedOutline,
    disabledOutline: disabledOutline ?? this.disabledOutline,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    dot: dot ?? this.dot,
    disabledDot: disabledDot ?? this.disabledDot,
    thickness: thickness ?? this.thickness,
    depthStep: depthStep ?? this.depthStep,
    wash: wash ?? this.wash,
    selectedWash: selectedWash ?? this.selectedWash,
  );

  /// What this style draws as, for an option that is [selected] or not and
  /// [enabled] or not.
  ResolvedRadioStyle3d resolve(
    Set<Material3dState> states, {
    required bool selected,
    required bool enabled,
  }) {
    final ring = !enabled
        ? disabledOutline
        : (selected ? selectedOutline : outline);
    return ResolvedRadioStyle3d(
      style: this,
      selected: selected,
      border: Border3d(width: outlineWidth, color: ring),
      dot: selected ? (enabled ? dot : disabledDot) : _none,
      wash: selected ? selectedWash : wash,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RadioStyle3d &&
      other.outerSize == outerSize &&
      other.innerSize == innerSize &&
      other.stateLayerSize == stateLayerSize &&
      other.outline == outline &&
      other.selectedOutline == selectedOutline &&
      other.disabledOutline == disabledOutline &&
      other.outlineWidth == outlineWidth &&
      other.dot == dot &&
      other.disabledDot == disabledDot &&
      other.thickness == thickness &&
      other.depthStep == depthStep &&
      other.wash == wash &&
      other.selectedWash == selectedWash;

  @override
  int get hashCode => Object.hash(
    outerSize,
    innerSize,
    stateLayerSize,
    outline,
    selectedOutline,
    disabledOutline,
    outlineWidth,
    dot,
    disabledDot,
    thickness,
    depthStep,
    wash,
    selectedWash,
  );

  @override
  String toString() => 'RadioStyle3d($outerSize over $innerSize)';
}

/// One radio button in one state.
@immutable
class ResolvedRadioStyle3d {
  /// Records what [style] resolved to.
  const ResolvedRadioStyle3d({
    required this.style,
    required this.selected,
    required this.border,
    required this.dot,
    required this.wash,
  });

  /// The style this was resolved from.
  final RadioStyle3d style;

  /// Whether this option is the chosen one.
  final bool selected;

  /// The ring, in this state.
  final Border3d border;

  /// The dot's colour, or transparent when there is no dot.
  final Color dot;

  /// The colour the state layer washes with.
  final Color wash;

  /// Whether a dot is drawn at all.
  bool get hasDot => dot.a > 0.0;

  @override
  bool operator ==(Object other) =>
      other is ResolvedRadioStyle3d &&
      other.style == style &&
      other.selected == selected &&
      other.border == border &&
      other.dot == dot &&
      other.wash == wash;

  @override
  int get hashCode => Object.hash(style, selected, border, dot, wash);

  @override
  String toString() => 'ResolvedRadioStyle3d($border, dot $dot)';
}

/// Everything a [Switch3d] is made of, before a state has had its say.
///
/// A 52 by 32 track with a thumb that slides along it — Material's own
/// figures, and the only two-part control in the catalogue whose parts move
/// relative to each other.
///
/// ## The thumb is one size, and Material's is two
///
/// Material grows the thumb from 16dp to 24dp as it slides across, and
/// shrinks it again on the way back. That is an **animation**, and this
/// package has no motion tokens — the same reason phase 6 shipped a dialog
/// that appears rather than one that grows. A thumb that jumped between two
/// sizes on a toggle would also put a size change on the interaction path,
/// where every other state in this catalogue is a colour. So [thumbSize] is
/// one figure, Material's selected 24dp, and what moves is the position.
///
/// Every figure is in logical pixels.
@immutable
class SwitchStyle3d {
  /// Creates a switch style.
  const SwitchStyle3d({
    required this.trackWidth,
    required this.trackHeight,
    required this.trackShape,
    required this.thumbSize,
    required this.track,
    required this.selectedTrack,
    required this.disabledTrack,
    required this.disabledSelectedTrack,
    required this.trackOutline,
    required this.selectedTrackOutline,
    required this.disabledTrackOutline,
    required this.trackOutlineWidth,
    required this.thumb,
    required this.selectedThumb,
    required this.disabledThumb,
    required this.disabledSelectedThumb,
    required this.trackThickness,
    required this.thumbThickness,
    required this.depthStep,
    required this.wash,
    required this.selectedWash,
  }) : assert(trackWidth > 0.0),
       assert(trackHeight > 0.0),
       assert(thumbSize > 0.0),
       assert(thumbSize <= trackHeight),
       assert(thumbSize <= trackWidth),
       assert(trackOutlineWidth >= 0.0),
       assert(trackThickness >= 0.0),
       assert(thumbThickness >= 0.0),
       // The rule the whole catalogue keeps re-deriving: a slab resting on
       // another slab's front face is coplanar with it, and one lifted by
       // exactly its own depth has its back face there instead.
       assert(depthStep > (trackThickness + thumbThickness) / 2.0);

  /// The style Material publishes, out of [theme]'s tokens.
  ///
  /// Checked in `test/selection_defaults_test.dart` against
  /// `_SwitchConfigM3` and `_SwitchDefaultsM3`. Both are private, so the
  /// geometry is a transcription and says so; the colours are
  /// `ColorScheme3d` roles.
  factory SwitchStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return SwitchStyle3d(
      trackWidth: defaultTrackWidth,
      trackHeight: defaultTrackHeight,
      trackShape: theme.shape.full,
      thumbSize: defaultThumbSize,
      track: scheme.surfaceContainerHighest,
      selectedTrack: scheme.primary,
      // Flutter's figure: the resting track at Material's 12% container
      // opacity, which is what `disabledContainer` is for `onSurface`.
      disabledTrack: scheme.surfaceContainerHighest.withValues(
        alpha: ColorScheme3d.disabledContainerOpacity,
      ),
      disabledSelectedTrack: scheme.disabledContainer,
      trackOutline: scheme.outline,
      // A filled track drops its outline, for the reason a selected chip
      // does: the fill is the signal and an edge round it competes with it.
      selectedTrackOutline: null,
      disabledTrackOutline: scheme.disabledContainer,
      trackOutlineWidth: 2.0,
      thumb: scheme.outline,
      selectedThumb: scheme.onPrimary,
      disabledThumb: scheme.disabledContent,
      disabledSelectedThumb: scheme.surface,
      trackThickness: theme.thickness.thin,
      thumbThickness: theme.thickness.standard,
      depthStep: Thickness3d.stepOver(
        theme.thickness.thin,
        theme.thickness.standard,
      ),
      wash: scheme.onSurface,
      selectedWash: scheme.primary,
    );
  }

  /// Material's track width, in logical pixels: 52dp.
  static const double defaultTrackWidth = 52.0;

  /// Material's track height, in logical pixels: 32dp.
  static const double defaultTrackHeight = 32.0;

  /// Material's selected thumb diameter, in logical pixels: 24dp.
  static const double defaultThumbSize = 24.0;

  /// How wide the track is, in logical pixels.
  final double trackWidth;

  /// How tall it is, in logical pixels.
  final double trackHeight;

  /// The track's corner radii: `shape.full`, which makes a stadium.
  final BorderRadius3d trackShape;

  /// How wide the thumb is, in logical pixels.
  final double thumbSize;

  /// The track's colour when the switch is off: `surfaceContainerHighest`.
  final Color track;

  /// Its colour when the switch is on: `primary`.
  final Color selectedTrack;

  /// Its colour when the switch is off and disabled.
  final Color disabledTrack;

  /// Its colour when the switch is on and disabled.
  final Color disabledSelectedTrack;

  /// The track's outline when the switch is off: `outline`.
  final Color? trackOutline;

  /// Its outline when the switch is on: none.
  final Color? selectedTrackOutline;

  /// Its outline when the switch is off and disabled.
  final Color? disabledTrackOutline;

  /// How thick that outline is, in logical pixels: 2dp.
  final double trackOutlineWidth;

  /// The thumb's colour when the switch is off: `outline`.
  final Color thumb;

  /// Its colour when the switch is on: `onPrimary`.
  final Color selectedThumb;

  /// Its colour when the switch is off and disabled.
  final Color disabledThumb;

  /// Its colour when the switch is on and disabled: `surface`.
  final Color disabledSelectedThumb;

  /// How deep the track's slab is, in logical pixels: `thickness.thin`.
  final double trackThickness;

  /// How deep the thumb's slab is, in logical pixels: `thickness.standard`.
  final double thumbThickness;

  /// How far the thumb stands in front of the track, in logical pixels.
  ///
  /// [Thickness3d.stepOver] of the two thicknesses. A thumb resting exactly
  /// on the track's front face is coplanar with it and z-fights: the thumb
  /// comes out in patches, differently on every frame and every driver. This
  /// is the third component to need that arithmetic — after `Divider3d`'s
  /// rule on a card and `NavigationStyle3d`'s glyph on a pill — which is why
  /// the rule is a method on the thickness scale now rather than a fourth
  /// hand-written figure.
  final double depthStep;

  /// The wash colour when the switch is off: `onSurface`.
  final Color wash;

  /// The wash colour when it is on: `primary`.
  final Color selectedWash;

  /// The margin between the thumb and the track's edge, in logical pixels.
  ///
  /// What is left over, halved: a 24dp thumb in a 32dp track sits 4dp from
  /// the top, the bottom, and — at each end of its travel — the ends.
  double get thumbMargin => (trackHeight - thumbSize) / 2.0;

  /// How far the thumb slides, in logical pixels.
  ///
  /// The track's width less the thumb and the margin at each end: 20dp for
  /// Material's own figures. Derived rather than stated, so a restyled switch
  /// cannot have a travel that disagrees with its track.
  double get travel => trackWidth - thumbSize - 2.0 * thumbMargin;

  /// This style with the given fields replaced.
  SwitchStyle3d copyWith({
    double? trackWidth,
    double? trackHeight,
    BorderRadius3d? trackShape,
    double? thumbSize,
    Color? track,
    Color? selectedTrack,
    Color? disabledTrack,
    Color? disabledSelectedTrack,
    Color? trackOutline,
    Color? selectedTrackOutline,
    Color? disabledTrackOutline,
    double? trackOutlineWidth,
    Color? thumb,
    Color? selectedThumb,
    Color? disabledThumb,
    Color? disabledSelectedThumb,
    double? trackThickness,
    double? thumbThickness,
    double? depthStep,
    Color? wash,
    Color? selectedWash,
  }) => SwitchStyle3d(
    trackWidth: trackWidth ?? this.trackWidth,
    trackHeight: trackHeight ?? this.trackHeight,
    trackShape: trackShape ?? this.trackShape,
    thumbSize: thumbSize ?? this.thumbSize,
    track: track ?? this.track,
    selectedTrack: selectedTrack ?? this.selectedTrack,
    disabledTrack: disabledTrack ?? this.disabledTrack,
    disabledSelectedTrack: disabledSelectedTrack ?? this.disabledSelectedTrack,
    trackOutline: trackOutline ?? this.trackOutline,
    selectedTrackOutline: selectedTrackOutline ?? this.selectedTrackOutline,
    disabledTrackOutline: disabledTrackOutline ?? this.disabledTrackOutline,
    trackOutlineWidth: trackOutlineWidth ?? this.trackOutlineWidth,
    thumb: thumb ?? this.thumb,
    selectedThumb: selectedThumb ?? this.selectedThumb,
    disabledThumb: disabledThumb ?? this.disabledThumb,
    disabledSelectedThumb: disabledSelectedThumb ?? this.disabledSelectedThumb,
    trackThickness: trackThickness ?? this.trackThickness,
    thumbThickness: thumbThickness ?? this.thumbThickness,
    depthStep: depthStep ?? this.depthStep,
    wash: wash ?? this.wash,
    selectedWash: selectedWash ?? this.selectedWash,
  );

  /// What this style draws as, for a switch that is [selected] or not and
  /// [enabled] or not.
  ResolvedSwitchStyle3d resolve(
    Set<Material3dState> states, {
    required bool selected,
    required bool enabled,
  }) {
    final Color? outline;
    if (!enabled) {
      outline = selected ? null : disabledTrackOutline;
    } else {
      outline = selected ? selectedTrackOutline : trackOutline;
    }
    return ResolvedSwitchStyle3d(
      style: this,
      selected: selected,
      track: !enabled
          ? (selected ? disabledSelectedTrack : disabledTrack)
          : (selected ? selectedTrack : track),
      thumb: !enabled
          ? (selected ? disabledSelectedThumb : disabledThumb)
          : (selected ? selectedThumb : thumb),
      border: outline == null
          ? Border3d.none
          : Border3d(width: trackOutlineWidth, color: outline),
      wash: selected ? selectedWash : wash,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SwitchStyle3d &&
      other.trackWidth == trackWidth &&
      other.trackHeight == trackHeight &&
      other.trackShape == trackShape &&
      other.thumbSize == thumbSize &&
      other.track == track &&
      other.selectedTrack == selectedTrack &&
      other.disabledTrack == disabledTrack &&
      other.disabledSelectedTrack == disabledSelectedTrack &&
      other.trackOutline == trackOutline &&
      other.selectedTrackOutline == selectedTrackOutline &&
      other.disabledTrackOutline == disabledTrackOutline &&
      other.trackOutlineWidth == trackOutlineWidth &&
      other.thumb == thumb &&
      other.selectedThumb == selectedThumb &&
      other.disabledThumb == disabledThumb &&
      other.disabledSelectedThumb == disabledSelectedThumb &&
      other.trackThickness == trackThickness &&
      other.thumbThickness == thumbThickness &&
      other.depthStep == depthStep &&
      other.wash == wash &&
      other.selectedWash == selectedWash;

  @override
  int get hashCode => Object.hash(
    trackWidth,
    trackHeight,
    trackShape,
    thumbSize,
    track,
    selectedTrack,
    disabledTrack,
    disabledSelectedTrack,
    trackOutline,
    selectedTrackOutline,
    disabledTrackOutline,
    trackOutlineWidth,
    thumb,
    selectedThumb,
    disabledThumb,
    disabledSelectedThumb,
    trackThickness,
    thumbThickness,
    depthStep,
    Object.hash(wash, selectedWash),
  );

  @override
  String toString() =>
      'SwitchStyle3d(${trackWidth}x$trackHeight, ${thumbSize}dp thumb)';
}

/// One switch in one state.
@immutable
class ResolvedSwitchStyle3d {
  /// Records what [style] resolved to.
  const ResolvedSwitchStyle3d({
    required this.style,
    required this.selected,
    required this.track,
    required this.thumb,
    required this.border,
    required this.wash,
  });

  /// The style this was resolved from.
  final SwitchStyle3d style;

  /// Whether the switch is on.
  final bool selected;

  /// The track's colour, in this state.
  final Color track;

  /// The thumb's colour, in this state.
  final Color thumb;

  /// The track's outline, in this state.
  final Border3d border;

  /// The colour the state layer washes with.
  final Color wash;

  @override
  bool operator ==(Object other) =>
      other is ResolvedSwitchStyle3d &&
      other.style == style &&
      other.selected == selected &&
      other.track == track &&
      other.thumb == thumb &&
      other.border == border &&
      other.wash == wash;

  @override
  int get hashCode => Object.hash(style, selected, track, thumb, border, wash);

  @override
  String toString() => 'ResolvedSwitchStyle3d($track, thumb $thumb)';
}

/// Everything a [Slider3d] is made of, before a state has had its say.
///
/// Material has shipped two M3 sliders: the one with a 4dp track and a 20dp
/// round thumb, and the 2024 "expressive" one with a 16dp track and a 4 by
/// 44 bar handle. This package takes the **round-thumb** one, and the reason
/// is the depth: a thumb standing proud of a track is exactly the shape this
/// catalogue's third dimension is for, while a handle inset into a track of
/// its own height is a picture of a slider that a 3D scene has nothing to add
/// to. `RoundSliderThumbShape.enabledThumbRadius` and
/// `RoundSliderOverlayShape.overlayRadius` are both public in Flutter, so
/// two of the three figures here are read rather than transcribed.
///
/// Every figure is in logical pixels.
@immutable
class SliderStyle3d {
  /// Creates a slider style.
  const SliderStyle3d({
    required this.trackHeight,
    required this.thumbSize,
    required this.stateLayerSize,
    required this.minimumTrackWidth,
    required this.trackShape,
    required this.activeTrack,
    required this.inactiveTrack,
    required this.disabledActiveTrack,
    required this.disabledInactiveTrack,
    required this.thumb,
    required this.disabledThumb,
    required this.trackThickness,
    required this.thumbThickness,
    required this.depthStep,
    required this.wash,
  }) : assert(trackHeight > 0.0),
       assert(thumbSize > 0.0),
       assert(stateLayerSize >= thumbSize),
       assert(minimumTrackWidth >= thumbSize),
       assert(trackThickness >= 0.0),
       assert(thumbThickness >= 0.0),
       assert(depthStep > (trackThickness + thumbThickness) / 2.0);

  /// The style Material publishes, out of [theme]'s tokens.
  factory SliderStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return SliderStyle3d(
      trackHeight: defaultTrackHeight,
      thumbSize: defaultThumbSize,
      stateLayerSize: defaultStateLayerSize,
      minimumTrackWidth: defaultMinimumTrackWidth,
      trackShape: theme.shape.full,
      activeTrack: scheme.primary,
      inactiveTrack: scheme.surfaceContainerHighest,
      disabledActiveTrack: scheme.disabledContent,
      disabledInactiveTrack: scheme.disabledContainer,
      thumb: scheme.primary,
      disabledThumb: scheme.disabledContent,
      trackThickness: theme.thickness.thin,
      thumbThickness: theme.thickness.standard,
      depthStep: Thickness3d.stepOver(
        theme.thickness.thin,
        theme.thickness.standard,
      ),
      wash: scheme.primary,
    );
  }

  /// Material's track height, in logical pixels: 4dp.
  static const double defaultTrackHeight = 4.0;

  /// Material's thumb diameter, in logical pixels: 20dp.
  ///
  /// Twice `RoundSliderThumbShape.enabledThumbRadius`, which is public.
  static const double defaultThumbSize = 20.0;

  /// Material's overlay diameter, in logical pixels: 48dp.
  ///
  /// Twice `RoundSliderOverlayShape.overlayRadius`, which is public. It is
  /// also, by coincidence rather than by construction, the touch target — so
  /// a slider is the one control here whose wash and whose reach agree.
  static const double defaultStateLayerSize = 48.0;

  /// The narrowest track Material will lay out, in logical pixels: 144dp.
  static const double defaultMinimumTrackWidth = 144.0;

  /// How tall the track is, in logical pixels.
  final double trackHeight;

  /// How wide the thumb is, in logical pixels.
  final double thumbSize;

  /// How tall the control is, in logical pixels, and the diameter of the wash.
  final double stateLayerSize;

  /// The narrowest the track may be laid out at, in logical pixels.
  final double minimumTrackWidth;

  /// The track's corner radii: `shape.full`, which makes each end a cap.
  final BorderRadius3d trackShape;

  /// The colour of the part behind the thumb: `primary`.
  final Color activeTrack;

  /// The colour of the part in front of it: `surfaceContainerHighest`.
  final Color inactiveTrack;

  /// The active part's colour when the slider is disabled.
  final Color disabledActiveTrack;

  /// The inactive part's colour when it is.
  final Color disabledInactiveTrack;

  /// The thumb's colour: `primary`.
  final Color thumb;

  /// The thumb's colour when the slider is disabled.
  final Color disabledThumb;

  /// How deep the track's slab is, in logical pixels: `thickness.thin`.
  final double trackThickness;

  /// How deep the thumb's slab is, in logical pixels: `thickness.standard`.
  final double thumbThickness;

  /// How far the thumb — and the active track — stand in front of the
  /// inactive track, in logical pixels.
  final double depthStep;

  /// The colour the state layer washes with: `primary`.
  final Color wash;

  /// This style with the given fields replaced.
  SliderStyle3d copyWith({
    double? trackHeight,
    double? thumbSize,
    double? stateLayerSize,
    double? minimumTrackWidth,
    BorderRadius3d? trackShape,
    Color? activeTrack,
    Color? inactiveTrack,
    Color? disabledActiveTrack,
    Color? disabledInactiveTrack,
    Color? thumb,
    Color? disabledThumb,
    double? trackThickness,
    double? thumbThickness,
    double? depthStep,
    Color? wash,
  }) => SliderStyle3d(
    trackHeight: trackHeight ?? this.trackHeight,
    thumbSize: thumbSize ?? this.thumbSize,
    stateLayerSize: stateLayerSize ?? this.stateLayerSize,
    minimumTrackWidth: minimumTrackWidth ?? this.minimumTrackWidth,
    trackShape: trackShape ?? this.trackShape,
    activeTrack: activeTrack ?? this.activeTrack,
    inactiveTrack: inactiveTrack ?? this.inactiveTrack,
    disabledActiveTrack: disabledActiveTrack ?? this.disabledActiveTrack,
    disabledInactiveTrack: disabledInactiveTrack ?? this.disabledInactiveTrack,
    thumb: thumb ?? this.thumb,
    disabledThumb: disabledThumb ?? this.disabledThumb,
    trackThickness: trackThickness ?? this.trackThickness,
    thumbThickness: thumbThickness ?? this.thumbThickness,
    depthStep: depthStep ?? this.depthStep,
    wash: wash ?? this.wash,
  );

  /// What this style draws as, for a slider that is [enabled] or not.
  ///
  /// A slider has no selected state — its value is a position rather than a
  /// substitution — so this table is the smallest in the catalogue and the
  /// only thing that changes it is enablement.
  ResolvedSliderStyle3d resolve(
    Set<Material3dState> states, {
    required bool enabled,
  }) => ResolvedSliderStyle3d(
    style: this,
    activeTrack: enabled ? activeTrack : disabledActiveTrack,
    inactiveTrack: enabled ? inactiveTrack : disabledInactiveTrack,
    thumb: enabled ? thumb : disabledThumb,
    wash: wash,
  );

  @override
  bool operator ==(Object other) =>
      other is SliderStyle3d &&
      other.trackHeight == trackHeight &&
      other.thumbSize == thumbSize &&
      other.stateLayerSize == stateLayerSize &&
      other.minimumTrackWidth == minimumTrackWidth &&
      other.trackShape == trackShape &&
      other.activeTrack == activeTrack &&
      other.inactiveTrack == inactiveTrack &&
      other.disabledActiveTrack == disabledActiveTrack &&
      other.disabledInactiveTrack == disabledInactiveTrack &&
      other.thumb == thumb &&
      other.disabledThumb == disabledThumb &&
      other.trackThickness == trackThickness &&
      other.thumbThickness == thumbThickness &&
      other.depthStep == depthStep &&
      other.wash == wash;

  @override
  int get hashCode => Object.hash(
    trackHeight,
    thumbSize,
    stateLayerSize,
    minimumTrackWidth,
    trackShape,
    activeTrack,
    inactiveTrack,
    disabledActiveTrack,
    disabledInactiveTrack,
    thumb,
    disabledThumb,
    trackThickness,
    thumbThickness,
    depthStep,
    wash,
  );

  @override
  String toString() =>
      'SliderStyle3d(${trackHeight}dp track, ${thumbSize}dp thumb)';
}

/// One slider in one state.
@immutable
class ResolvedSliderStyle3d {
  /// Records what [style] resolved to.
  const ResolvedSliderStyle3d({
    required this.style,
    required this.activeTrack,
    required this.inactiveTrack,
    required this.thumb,
    required this.wash,
  });

  /// The style this was resolved from.
  final SliderStyle3d style;

  /// The colour of the part behind the thumb.
  final Color activeTrack;

  /// The colour of the part in front of it.
  final Color inactiveTrack;

  /// The thumb's colour.
  final Color thumb;

  /// The colour the state layer washes with.
  final Color wash;

  @override
  bool operator ==(Object other) =>
      other is ResolvedSliderStyle3d &&
      other.style == style &&
      other.activeTrack == activeTrack &&
      other.inactiveTrack == inactiveTrack &&
      other.thumb == thumb &&
      other.wash == wash;

  @override
  int get hashCode =>
      Object.hash(style, activeTrack, inactiveTrack, thumb, wash);

  @override
  String toString() =>
      'ResolvedSliderStyle3d($activeTrack over $inactiveTrack)';
}
