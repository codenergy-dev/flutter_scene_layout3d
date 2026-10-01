import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable, setEquals;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Directionality,
        IconData,
        StatelessWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        Border3d,
        BorderRadius3d,
        Constraints3d,
        CrossAxisAlignment3d,
        EdgeInsets3d,
        EdgeInsetsGeometry3d,
        MainAxisSize3d,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneConstrainedBox3d,
        SceneExpanded3d,
        SceneFlexible3d,
        SceneIgnorePointer3d,
        SceneIntrinsicWidth3d,
        ScenePadding3d,
        ScenePositioned3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneSpacer3d,
        SceneStack3d,
        SceneTapTarget3d,
        SceneText3d;

import '../theme/theme.dart';
import 'divider.dart';
import 'icon.dart';
import 'ink_well.dart';
import 'material.dart';
import 'reading_direction.dart';
import 'segmented_button_style.dart';
import 'text_style.dart';
import 'tooltip.dart';

/// Transparent: an unchosen segment's fill, and the outline's.
const Color _none = Color(0x00000000);

/// One option of a [SegmentedButton3d].
///
/// ```dart
/// const ButtonSegment3d<Calendar>(
///   value: Calendar.week,
///   label: 'Week',
///   icon: Icons.calendar_view_week,
/// )
/// ```
///
/// Flutter's `ButtonSegment`, with two of its widgets turned into what they
/// stand for. **The label is a `String`**, for `NavigationDestination3d`'s
/// reason: a `Semantics3d` gathers nothing from below, so a segment that took
/// a widget would have to be told its own name twice, and this one builds the
/// visible label and the announcement out of one string. **The icon is an
/// [IconData]**, for `IconButton3d`'s: its size is the button's token, 18dp,
/// and there is no `IconTheme` here to carry that down to a widget someone
/// else built.
@immutable
class ButtonSegment3d<T> {
  /// Creates a segment. It needs a [label], an [icon], or both.
  const ButtonSegment3d({
    required this.value,
    this.label,
    this.icon,
    this.tooltip,
    this.semanticLabel,
    this.enabled = true,
  }) : assert(label != null || icon != null);

  /// What this segment stands for.
  final T value;

  /// What the segment says, and what it announces.
  final String? label;

  /// The glyph before the label, or the whole segment when there is none.
  final IconData? icon;

  /// What a pointer resting on the segment shows, and what an icon-only
  /// segment announces when it has no [semanticLabel].
  final String? tooltip;

  /// What a screen reader announces this segment as, or null for [label],
  /// then [tooltip].
  final String? semanticLabel;

  /// Whether this one segment can be pressed.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is ButtonSegment3d<T> &&
      other.value == value &&
      other.label == label &&
      other.icon == icon &&
      other.tooltip == tooltip &&
      other.semanticLabel == semanticLabel &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(value, label, icon, tooltip, semanticLabel, enabled);

  @override
  String toString() => 'ButtonSegment3d(${label ?? value})';
}

/// A row of options in one outline, of which one — or several — are chosen.
///
/// ```dart
/// SegmentedButton3d<Calendar>(
///   segments: const <ButtonSegment3d<Calendar>>[
///     ButtonSegment3d(value: Calendar.day, label: 'Day'),
///     ButtonSegment3d(value: Calendar.week, label: 'Week'),
///     ButtonSegment3d(value: Calendar.month, label: 'Month'),
///   ],
///   selected: <Calendar>{_view},
///   onSelectionChanged: (selection) =>
///       setState(() => _view = selection.single),
/// )
/// ```
///
/// Flutter's `SegmentedButton`: a stadium outlined in `outline`, cut into
/// equal segments by 1dp rules, the chosen ones filled `secondaryContainer`
/// with a check in front of their label. Everything it is made of is in
/// [SegmentedButtonStyle3d]. [onSelectionChanged] is handed the whole next
/// selection, and what a press may do is Flutter's arithmetic: with
/// [multiSelectionEnabled] a press toggles its segment, without it a press
/// chooses its segment alone, and the last chosen segment cannot be let go
/// of unless [emptySelectionAllowed]. A press that would change nothing is
/// not reported. `onSelectionChanged: null` disables the whole button.
///
/// ## Where the rounded clip is
///
/// Flutter draws every segment as a square `TextButton` and clips it to the
/// inside of the stadium, so the first and last fills follow the outline's
/// curve. There is no rounded clip here — a clip region is an intersection
/// of planes, and so convex. What there is, is the answer a picture on a
/// panel found: **carve the shape in the panel's own signed distance
/// field**. A segment is a `Material3d` of its own, because it needs its own
/// wash, so the two end segments are drawn with the stadium's radius on
/// their outer corners and square ones inside, and the fill comes out the
/// shape Flutter's clip leaves. Start and end follow the reading direction:
/// in right to left the first segment is the one rounded on its right.
///
/// The outline and the rules are a transparent slab of their own, standing
/// [SegmentedButtonStyle3d.outlineDepthStep] in front of the segments and
/// answering no ray. Flutter paints the border after its children, and in
/// front is where that puts it.
///
/// ## 48dp tall, as Flutter's is
///
/// The outline is 40dp and the button lays out at 48, with the outline in the
/// middle — Flutter's `tapTargetVerticalPadding`. Every other control in this
/// catalogue is laid out at its visible size and grows its reach in the hit
/// test instead, and that does not work here: a press in a reach's margin
/// arrives at the *control's* centre, which for three segments is the middle
/// one. So each segment's target sits inside a 48dp slot of its own and is
/// re-aimed at its own centre, and a press just above the first segment
/// chooses the first.
///
/// ## Every segment as wide as the widest
///
/// Flutter's rule, and a row of flexible children inside an intrinsic width
/// is exactly it here. Give [expandedInsets] to make the button fill the
/// width it is offered instead, inset by that much, with the segments still
/// equal.
///
/// ## What it does not do
///
///  * **A disabled segment's stretch of outline** stays `outline`. Flutter
///    draws the border around a disabled segment in the disabled colour; the
///    outline here is one slab with one border, and only a disabled *button*
///    changes it.
///  * **`direction: Axis.vertical`**, which Flutter added for a column of
///    segments, is not here.
///
/// ## What it announces
///
/// Each segment announces its label as a button, `selected` when it is
/// chosen, and in a mutually exclusive group unless [multiSelectionEnabled]
/// — Flutter's own three properties. The button itself announces nothing.
class SegmentedButton3d<T> extends StatelessWidget {
  /// Creates a segmented button.
  const SegmentedButton3d({
    super.key,
    required this.segments,
    required this.selected,
    this.onSelectionChanged,
    this.multiSelectionEnabled = false,
    this.emptySelectionAllowed = false,
    this.expandedInsets,
    this.showSelectedIcon = true,
    this.selectedIcon,
    this.style,
    this.textDirection,
  });

  /// `Icons.check`'s code point, the glyph a chosen segment wears.
  ///
  /// Written out rather than imported, for the reason
  /// `Checkbox3d.defaultIcon` is.
  static const IconData defaultSelectedIcon = IconData(
    0xe156,
    fontFamily: 'MaterialIcons',
  );

  /// Why a button with no segments is refused, in `build`.
  ///
  /// Flutter asserts this in its constructor. A `const` constructor's asserts
  /// run at compile time here and `List.length` is not a constant
  /// expression, so the check is in `build`, as `NavigationBar3d`'s is.
  static const String noSegments =
      'A SegmentedButton3d needs at least one segment.';

  /// Why an empty selection is refused unless it is allowed.
  static const String emptySelection =
      'A SegmentedButton3d with nothing selected needs '
      'emptySelectionAllowed: true.';

  /// Why more than one selected segment is refused unless it is allowed.
  static const String multipleSelection =
      'A SegmentedButton3d with more than one segment selected needs '
      'multiSelectionEnabled: true.';

  /// The options, in reading order.
  final List<ButtonSegment3d<T>> segments;

  /// The values of the chosen segments.
  final Set<T> selected;

  /// Called with the next selection when a press changes it, or null for a
  /// disabled button.
  final void Function(Set<T> selection)? onSelectionChanged;

  /// Whether a press toggles its segment rather than choosing it alone.
  final bool multiSelectionEnabled;

  /// Whether the last chosen segment can be let go of.
  final bool emptySelectionAllowed;

  /// How far in from each edge the button stands when it fills its width,
  /// in logical pixels, or null for a button as wide as its segments.
  final EdgeInsetsGeometry3d? expandedInsets;

  /// Whether a chosen segment wears a check.
  final bool showSelectedIcon;

  /// The glyph a chosen segment wears, or null for [defaultSelectedIcon].
  final IconData? selectedIcon;

  /// The whole token set, or null for `SegmentedButtonStyle3d.of(theme)`.
  final SegmentedButtonStyle3d? style;

  /// The direction the segments' labels are announced in.
  final TextDirection? textDirection;

  /// What a press on the segment for [value] hands [onSelectionChanged], or
  /// null when it would change nothing.
  ///
  /// `SegmentedButtonState._handleOnPressed`, transcribed. Public because it
  /// is the whole of the rule and a test should be able to read it as a
  /// table.
  Set<T>? selectionAfterPressing(T value) {
    final onlySelected = selected.length == 1 && selected.contains(value);
    if (!emptySelectionAllowed && onlySelected) return null;
    final toggle =
        multiSelectionEnabled || (emptySelectionAllowed && onlySelected);
    final Set<T> next;
    if (toggle) {
      next = selected.contains(value)
          ? selected.difference(<T>{value})
          : selected.union(<T>{value});
    } else {
      next = <T>{value};
    }
    return setEquals(next, selected) ? null : next;
  }

  @override
  Widget build(BuildContext context) {
    assert(segments.isNotEmpty, noSegments);
    assert(selected.isNotEmpty || emptySelectionAllowed, emptySelection);
    assert(selected.length < 2 || multiSelectionEnabled, multipleSelection);
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? SegmentedButtonStyle3d.of(theme);
    final enabled = onSelectionChanged != null;
    final rightToLeft = Directionality.maybeOf(context) == TextDirection.rtl;
    final inset = (resolved.tapTargetHeight - resolved.height) / 2.0;

    final row = SceneRow3d(
      crossAxisAlignment: CrossAxisAlignment3d.stretch,
      children: <Widget>[
        for (var i = 0; i < segments.length; i++)
          SceneExpanded3d(
            child: _segment(
              context,
              resolved,
              index: i,
              buttonEnabled: enabled,
              rightToLeft: rightToLeft,
              inset: inset,
            ),
          ),
      ],
    );

    // The outline and the rules between segments, in front of the fills and
    // out of the way of every ray. The rules are each at the start of the
    // segment after them, in a row built the same way as the segments' so
    // that the two agree on where every boundary falls.
    final outline = SceneIgnorePointer3d(
      child: Material3d(
        color: _none,
        shape: resolved.shape,
        elevation: theme.elevation.level0,
        thickness: resolved.outlineThickness,
        border: Border3d(
          width: resolved.outlineWidth,
          color: enabled ? resolved.outline : resolved.disabledOutline,
        ),
        surfaceTint: _none,
        alignment: null,
        child: SceneRow3d(
          crossAxisAlignment: CrossAxisAlignment3d.stretch,
          children: <Widget>[
            for (var i = 0; i < segments.length; i++)
              SceneExpanded3d(
                child: i == 0
                    ? const SceneSizedBox3d()
                    : SceneRow3d(
                        crossAxisAlignment: CrossAxisAlignment3d.stretch,
                        children: <Widget>[
                          VerticalDivider3d(
                            space: resolved.outlineWidth,
                            thickness: resolved.outlineWidth,
                            depth: resolved.outlineThickness,
                            color: enabled
                                ? resolved.outline
                                : resolved.disabledOutline,
                          ),
                          const SceneSpacer3d(),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );

    Widget button = SceneSizedBox3d(
      height: metrics.dp(resolved.tapTargetHeight),
      child: SceneStack3d(
        alignment: Alignment3d.frontCenter,
        depthStep: metrics.dp(resolved.outlineDepthStep),
        children: <Widget>[
          row,
          ScenePositioned3d(
            left: 0.0,
            right: 0.0,
            top: metrics.dp(inset),
            bottom: metrics.dp(inset),
            child: outline,
          ),
        ],
      ),
    );
    final expanded = expandedInsets;
    button = expanded == null
        ? SceneIntrinsicWidth3d(child: button)
        : ScenePadding3d(padding: metrics.dpInsets(expanded), child: button);
    return button;
  }

  Widget _segment(
    BuildContext context,
    SegmentedButtonStyle3d resolved, {
    required int index,
    required bool buttonEnabled,
    required bool rightToLeft,
    required double inset,
  }) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final segment = segments[index];
    final chosen = selected.contains(segment.value);
    final active = buttonEnabled && segment.enabled;
    final content = !active
        ? resolved.disabledContent
        : (chosen ? resolved.selectedContent : resolved.content);
    // A disabled segment has no fill even when it is chosen: Flutter resolves
    // the background's disabled state before its selected one.
    final fill = chosen && active ? resolved.selectedContainer : _none;

    // The clip Flutter's stadium does, carved instead: the outer corners of
    // the end segments take the outline's radii, every inner corner is
    // square. A lone segment is the whole stadium.
    final first = index == 0;
    final last = index == segments.length - 1;
    final left = rightToLeft ? last : first;
    final right = rightToLeft ? first : last;
    final outer = resolved.shape;
    final shape = BorderRadius3d(
      topLeft: left ? outer.topLeft : 0.0,
      bottomLeft: left ? outer.bottomLeft : 0.0,
      topRight: right ? outer.topRight : 0.0,
      bottomRight: right ? outer.bottomRight : 0.0,
    );

    final glyph = chosen && showSelectedIcon
        ? (selectedIcon ?? defaultSelectedIcon)
        : (segment.label != null ? segment.icon : null);
    final Widget label = segment.label != null
        ? SceneText3d(segment.label!)
        : Icon3d(segment.icon!, size: resolved.iconSize);
    final Widget drawn = glyph == null
        ? label
        : SceneRow3d(
            mainAxisSize: MainAxisSize3d.min,
            spacing: metrics.dp(resolved.iconGap),
            children: <Widget>[
              Icon3d(glyph, size: resolved.iconSize),
              SceneFlexible3d(child: label),
            ],
          );

    void Function()? tap;
    final changed = onSelectionChanged;
    if (active && changed != null) {
      tap = () {
        final next = selectionAfterPressing(segment.value);
        if (next != null) changed(next);
      };
    }

    final surface = Material3d(
      color: fill,
      contentColor: content,
      shape: shape,
      elevation: theme.elevation.level0,
      thickness: resolved.thickness,
      surfaceTint: _none,
      textStyle: theme.textStyle(resolved.labelStyle, color: content),
      alignment: null,
      child: InkWell3d(
        // One target, and it is the one outside this panel.
        minimumSize: Size3d.zero,
        enabled: tap != null,
        onTap: tap,
        // Inside the well, so a press on the padding is a press on the
        // segment; see `docs/traps.md`, *Pointers*.
        child: ScenePadding3d(
          padding: metrics.dpInsets(
            glyph == null ? resolved.padding : resolved.iconPadding,
          ),
          child: SceneAlign3d(
            alignment: Alignment3d.frontCenter,
            child: SceneTextStyle3d(
              style: resolved.labelStyle,
              color: content,
              child: SceneIgnorePointer3d(child: drawn),
            ),
          ),
        ),
      ),
    );

    final announced = SceneSemantics3d(
      properties: SemanticsProperties(
        button: true,
        enabled: active,
        selected: chosen,
        inMutuallyExclusiveGroup: multiSelectionEnabled ? null : true,
        label: segment.semanticLabel ?? segment.label ?? segment.tooltip,
        textDirection: readingDirection3d(context, textDirection),
        onTap: tap,
      ),
      child: SceneConstrainedBox3d(
        constraints: Constraints3d(
          minWidth: metrics.dp(resolved.minimumSegmentWidth),
        ),
        child: surface,
      ),
    );

    // The slot is the full 48dp and the segment the middle 40: the target is
    // inside a box as tall as its reach, so nothing above it cuts the reach
    // off, and a press in the margin is re-aimed at *this* segment's centre.
    Widget slot = ScenePadding3d(
      padding: metrics.dpInsets(EdgeInsets3d.symmetric(vertical: inset)),
      child: SceneTapTarget3d(child: announced),
    );
    final tooltip = segment.tooltip;
    if (tooltip != null) slot = Tooltip3d(message: tooltip, child: slot);
    return slot;
  }
}
