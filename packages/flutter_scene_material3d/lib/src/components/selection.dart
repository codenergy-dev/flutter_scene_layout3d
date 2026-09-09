import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueChanged;
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
    show Alignment3d, Offset3d, Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneIgnorePointer3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneStack3d,
        SceneTapTarget3d;

import '../theme/theme.dart';
import 'icon.dart';
import 'ink_well.dart';
import 'material.dart';
import 'node_shift.dart';
import 'selection_style.dart';

/// Transparent: the colour a wash surface and an empty box are drawn in.
const Color _none = Color(0x00000000);

/// A box that is empty or has a mark in it.
///
/// ```dart
/// Checkbox3d(
///   value: _subscribed,
///   onChanged: (value) => setState(() => _subscribed = value),
///   semanticLabel: 'Subscribe to updates',
/// )
/// ```
///
/// 18dp of ink in a 40dp wash in a 48dp touch target, which is three
/// rectangles for one control and is what Material specifies. All three are
/// in [CheckboxStyle3d], and the reason they are three rather than one is the
/// rule every component here obeys: a `TapTarget3d` reaches past its own
/// extent and its parent does not, so the reach has to sit outside every box
/// whose size it would otherwise grow.
///
/// ## The mark, and why a chip did not get one
///
/// Phase 4 declined to draw a checkmark on a selected filter chip: the
/// container substitution already said "selected", and a glyph would have
/// been a second voice saying the same thing. A checkbox is the case where
/// that reasoning runs the other way. The substitution here is an 18dp square
/// turning `primary`, which on its own is indistinguishable from a filled
/// swatch — the mark **is** the signal, and Material draws one for that
/// reason.
///
/// It is one glyph of the icon font, drawn through the label atlas, exactly
/// as [Icon3d] is. That was not obvious: an icon in this catalogue is
/// normally 18 to 24dp of a glyph whose ink fills its em box, and a checkmark
/// at 18dp is the smallest thing the atlas has been asked to rasterize.
/// `examples/render_probe`'s `checkbox_mark` scene is what settled it, the
/// same way `icon_glyph` settled the icon question in phase 2.
///
/// ## Three slabs, and none of them coplanar
///
/// The wash circle, the box, and the mark are three surfaces drawn one on
/// another, and a surface resting exactly on another's front face z-fights
/// it. [CheckboxStyle3d.depthStep] is the separation, and it comes from
/// [Thickness3d.stepOver] rather than from a figure typed in here — which is
/// the fourth component in the catalogue to need that arithmetic and the
/// reason it stopped being written out by hand.
class Checkbox3d extends StatelessWidget {
  /// Creates a checkbox.
  const Checkbox3d({
    super.key,
    required this.value,
    this.onChanged,
    this.style,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.textDirection,
  });

  /// `Icons.check`'s code point in the `MaterialIcons` font.
  ///
  /// Written out rather than imported, for the reason
  /// `Chip3d.defaultDeleteIcon` is: `package:flutter/material.dart` is a
  /// large dependency for one glyph, and a checkbox must keep working when an
  /// application ships an icon font of its own.
  static const IconData defaultIcon = IconData(
    0xe156,
    fontFamily: 'MaterialIcons',
  );

  /// Whether the box has a mark in it.
  final bool value;

  /// Called with the value the box would become, or null for a box that
  /// cannot be changed.
  final ValueChanged<bool>? onChanged;

  /// The tokens to draw with, or null for the theme's.
  final CheckboxStyle3d? style;

  /// The glyph drawn in a full box, or null for [defaultIcon].
  final IconData? icon;

  /// The node holding this control's place in the focus tree.
  final FocusNode? focusNode;

  /// Whether the control takes the focus as soon as it is laid out.
  final bool autofocus;

  /// What a screen reader announces this checkbox as.
  ///
  /// **State it.** Nothing here gathers a label from a label beside it: a
  /// `Semantics3d` publishes what it is given and nothing else, so a checkbox
  /// in a row with a `SceneText3d` announces itself as an unnamed checkbox
  /// unless it is told. The `checked` state is published for you.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// Whether the box responds to a pointer.
  bool get enabled => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tokens = style ?? CheckboxStyle3d.of(theme);
    final resolved = tokens.resolve(
      const {},
      selected: value,
      enabled: enabled,
    );
    final changed = onChanged;

    return _SelectionControl3d(
      extent: tokens.stateLayerSize,
      thickness: tokens.thickness,
      depthStep: tokens.depthStep,
      wash: resolved.wash,
      enabled: enabled,
      onTap: changed == null ? null : () => changed(!value),
      focusNode: focusNode,
      autofocus: autofocus,
      properties: SemanticsProperties(
        checked: value,
        enabled: enabled,
        label: semanticLabel,
        textDirection: textDirection,
        onTap: changed == null ? null : () => changed(!value),
      ),
      children: <Widget>[
        SceneSizedBox3d(
          width: metrics.dp(tokens.size),
          height: metrics.dp(tokens.size),
          child: Material3d(
            color: resolved.container,
            shape: tokens.shape,
            elevation: theme.elevation.level0,
            thickness: tokens.thickness,
            border: resolved.border,
            surfaceTint: _none,
          ),
        ),
        if (resolved.hasMark)
          Icon3d(
            icon ?? defaultIcon,
            size: tokens.markSize,
            color: resolved.mark,
          ),
      ],
    );
  }
}

/// One option of a set, of which exactly one can be chosen.
///
/// ```dart
/// Radio3d<Delivery>(
///   value: Delivery.standard,
///   groupValue: _delivery,
///   onChanged: (value) => setState(() => _delivery = value),
///   semanticLabel: 'Standard delivery',
/// )
/// ```
///
/// Two concentric stadiums and nothing else, which is the whole of the
/// design: `ShapeScale3d.full` is a radius that clears half the shorter side,
/// so a square box drawn with it is a circle, and the catalogue's own
/// primitive draws both the ring and the dot. Phase 5 found the same thing
/// about Material's navigation pill — a stadium needed no new machinery — and
/// this is the second time that has paid.
///
/// The dot stands one [RadioStyle3d.depthStep] in front of the ring rather
/// than resting on it, because two coplanar surfaces z-fight.
class Radio3d<T> extends StatelessWidget {
  /// Creates a radio button.
  const Radio3d({
    super.key,
    required this.value,
    required this.groupValue,
    this.onChanged,
    this.toggleable = false,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.textDirection,
  });

  /// What this button stands for.
  final T value;

  /// Which of the group is currently chosen.
  final T? groupValue;

  /// Called with the newly chosen value, or null for a group that cannot be
  /// changed.
  ///
  /// Called with null when a [toggleable] button that was already chosen is
  /// pressed again, which is Flutter's own contract.
  final ValueChanged<T?>? onChanged;

  /// Whether pressing the chosen button clears the group.
  ///
  /// False, as Flutter's is: a radio group normally has no way back to "none
  /// of these".
  final bool toggleable;

  /// The tokens to draw with, or null for the theme's.
  final RadioStyle3d? style;

  /// The node holding this control's place in the focus tree.
  final FocusNode? focusNode;

  /// Whether the control takes the focus as soon as it is laid out.
  final bool autofocus;

  /// What a screen reader announces this option as. **State it.**
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// Whether this button is the chosen one.
  bool get selected => value == groupValue;

  /// Whether it responds to a pointer.
  bool get enabled => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tokens = style ?? RadioStyle3d.of(theme);
    final resolved = tokens.resolve(
      const {},
      selected: selected,
      enabled: enabled,
    );
    final changed = onChanged;

    void Function()? tap;
    if (changed != null && (!selected || toggleable)) {
      tap = () => changed(selected ? null : value);
    }

    return _SelectionControl3d(
      extent: tokens.stateLayerSize,
      thickness: tokens.thickness,
      depthStep: tokens.depthStep,
      wash: resolved.wash,
      enabled: enabled,
      onTap: tap,
      focusNode: focusNode,
      autofocus: autofocus,
      properties: SemanticsProperties(
        checked: selected,
        inMutuallyExclusiveGroup: true,
        enabled: enabled,
        label: semanticLabel,
        textDirection: textDirection,
        onTap: tap,
      ),
      children: <Widget>[
        SceneSizedBox3d(
          width: metrics.dp(tokens.outerSize),
          height: metrics.dp(tokens.outerSize),
          child: Material3d(
            color: _none,
            shape: theme.shape.full,
            elevation: theme.elevation.level0,
            thickness: tokens.thickness,
            border: resolved.border,
            surfaceTint: _none,
          ),
        ),
        if (resolved.hasDot)
          SceneSizedBox3d(
            width: metrics.dp(tokens.innerSize),
            height: metrics.dp(tokens.innerSize),
            child: Material3d(
              color: resolved.dot,
              shape: theme.shape.full,
              elevation: theme.elevation.level0,
              thickness: tokens.thickness,
              surfaceTint: _none,
            ),
          ),
      ],
    );
  }
}

/// A thumb that slides along a track.
///
/// ```dart
/// Switch3d(
///   value: _wifi,
///   onChanged: (value) => setState(() => _wifi = value),
///   semanticLabel: 'Wi-Fi',
/// )
/// ```
///
/// A 52 by 32 track with a 24dp thumb on it, Material's own figures, all in
/// [SwitchStyle3d].
///
/// ## The slide is on the node tier, and that is not an optimisation
///
/// The thumb's position is a `nodeOffset` — one matrix, written by
/// [SceneNodeShift3d], with no relayout at all — and `docs/traps.md`'s three
/// tiers are why. A control that moved its thumb by laying the track out
/// again would relayout on every toggle, and the moment this package grows
/// motion tokens it would do so on every frame of the transition. Layout
/// centres the thumb on the track; the shift carries it half the travel
/// either way.
///
/// The consequence to know before probing one: **`worldTransform` undoes a
/// `nodeOffset`**, so `screenCenter` on the thumb reports the middle of the
/// track whichever way the switch is set. A picture of a switch has to take
/// its oracle from the *track*, which is the same finding phase 6 wrote down
/// about an anchored menu.
///
/// ## The thumb stands proud of the track
///
/// A thumb resting exactly on the track's front face is coplanar with it and
/// z-fights: it comes out in patches, differently on every frame and every
/// driver. [SwitchStyle3d.depthStep] lifts it clear, and the figure is
/// [Thickness3d.stepOver] of the two thicknesses rather than a constant. This
/// is the same rule `Divider3d` found for a rule on a card and
/// `NavigationStyle3d` found for a glyph on a pill.
///
/// ## What Material animates and this does not
///
/// Material's thumb grows from 16dp to 24dp as it crosses. That is an
/// animation, and this package has no motion tokens — so the thumb is one
/// size and what moves is where it is. See [SwitchStyle3d] for the argument.
class Switch3d extends StatelessWidget {
  /// Creates a switch.
  const Switch3d({
    super.key,
    required this.value,
    this.onChanged,
    this.style,
    this.thumbIcon,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.textDirection,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the value the switch would become, or null for a switch that
  /// cannot be changed.
  final ValueChanged<bool>? onChanged;

  /// The tokens to draw with, or null for the theme's.
  final SwitchStyle3d? style;

  /// A glyph drawn on the thumb, or null for a plain one.
  ///
  /// Material's optional thumb icon — a tick when on, a cross when off. It is
  /// drawn in the track's colour, so it reads as a hole in the thumb rather
  /// than as a mark on it.
  final IconData? thumbIcon;

  /// The node holding this control's place in the focus tree.
  final FocusNode? focusNode;

  /// Whether the control takes the focus as soon as it is laid out.
  final bool autofocus;

  /// What a screen reader announces this switch as. **State it.**
  ///
  /// The `toggled` state is published for you — which is the property
  /// `SemanticsProperties` has for a switch, where a checkbox has `checked`.
  /// The distinction is Flutter's and it is worth keeping: a reader says
  /// "on"/"off" for one and "ticked"/"unticked" for the other.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// Whether the switch responds to a pointer.
  bool get enabled => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tokens = style ?? SwitchStyle3d.of(theme);
    final resolved = tokens.resolve(
      const {},
      selected: value,
      enabled: enabled,
    );
    final changed = onChanged;
    final tap = changed == null ? null : () => changed(!value);

    final track = Material3d(
      color: resolved.track,
      contentColor: resolved.wash,
      shape: tokens.trackShape,
      elevation: theme.elevation.level0,
      thickness: tokens.trackThickness,
      border: resolved.border,
      surfaceTint: _none,
      alignment: null,
      child: InkWell3d(
        // One target, and it is the one outside this panel.
        minimumSize: Size3d.zero,
        enabled: enabled,
        focusNode: focusNode,
        autofocus: autofocus,
        onTap: tap,
        child: SceneSizedBox3d(
          width: metrics.dp(tokens.trackWidth),
          height: metrics.dp(tokens.trackHeight),
        ),
      ),
    );

    // Half the travel either way from the middle, which is where layout puts
    // it. A `nodeOffset`: no relayout, and nothing under it is measured
    // again.
    final shift = metrics.dp(tokens.travel) / 2.0 * (value ? 1.0 : -1.0);
    final thumb = SceneIgnorePointer3d(
      child: SceneNodeShift3d(
        shift: Offset3d(shift, 0.0, 0.0),
        child: SceneSizedBox3d(
          width: metrics.dp(tokens.thumbSize),
          height: metrics.dp(tokens.thumbSize),
          child: Material3d(
            color: resolved.thumb,
            contentColor: resolved.track,
            shape: theme.shape.full,
            elevation: theme.elevation.level0,
            thickness: tokens.thumbThickness,
            surfaceTint: _none,
            child: thumbIcon == null
                ? null
                : Icon3d(
                    thumbIcon!,
                    size: tokens.thumbSize * 2.0 / 3.0,
                    color: resolved.track,
                  ),
          ),
        ),
      ),
    );

    final announced = SceneSemantics3d(
      properties: SemanticsProperties(
        toggled: value,
        enabled: enabled,
        label: semanticLabel,
        textDirection: textDirection,
        onTap: tap,
      ),
      child: SceneStack3d(
        alignment: Alignment3d.frontCenter,
        depthStep: metrics.dp(tokens.depthStep),
        children: <Widget>[track, thumb],
      ),
    );

    // Outermost, and doing real work: a switch is 32dp tall against a 48dp
    // minimum, so the reach is eight logical pixels above and below that no
    // box in the layout knows about.
    return SceneTapTarget3d(child: announced);
  }
}

/// The frame a checkbox and a radio button share: a wash, a target, an
/// announcement, and a stack of slabs that do not touch.
///
/// Not exported. Two components, one arrangement, and the arrangement is the
/// part that is easy to get subtly wrong — which is exactly what
/// `buildNavigationDestination3d` is for the bar and the rail.
class _SelectionControl3d extends StatelessWidget {
  const _SelectionControl3d({
    required this.extent,
    required this.thickness,
    required this.depthStep,
    required this.wash,
    required this.enabled,
    required this.onTap,
    required this.focusNode,
    required this.autofocus,
    required this.properties,
    required this.children,
  });

  /// How wide and tall the wash is, in logical pixels.
  final double extent;

  /// How deep the wash's slab is, in logical pixels.
  final double thickness;

  /// How far apart the slabs in [children] stand, in logical pixels.
  final double depthStep;

  /// The colour the state layer washes with.
  final Color wash;

  final bool enabled;
  final void Function()? onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final SemanticsProperties properties;

  /// The ink: a box and a mark, or a ring and a dot. Each one is stepped one
  /// [depthStep] in front of the one behind it.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);

    // Its own surface, so its own state layer, and transparent so that what
    // shows is the wash and nothing else. An `InkWell3d` finds the enclosing
    // `Material3d`, so this is also what keeps a checkbox in a list tile from
    // lighting the whole row up.
    final surface = Material3d(
      color: _none,
      contentColor: wash,
      shape: theme.shape.full,
      elevation: theme.elevation.level0,
      thickness: thickness,
      surfaceTint: _none,
      alignment: null,
      child: InkWell3d(
        // One target, and it is the one outside this panel.
        minimumSize: Size3d.zero,
        enabled: enabled,
        focusNode: focusNode,
        autofocus: autofocus,
        onTap: onTap,
        child: SceneSizedBox3d(
          width: metrics.dp(extent),
          height: metrics.dp(extent),
        ),
      ),
    );

    final announced = SceneSemantics3d(
      properties: properties,
      child: SceneStack3d(
        alignment: Alignment3d.frontCenter,
        depthStep: metrics.dp(depthStep),
        children: <Widget>[
          surface,
          // The ink answers no ray: everything a pointer needs to find is the
          // well behind it, and a `Text3d` mark would otherwise answer on its
          // own account.
          for (final child in children) SceneIgnorePointer3d(child: child),
        ],
      ),
    );

    // Outermost, for the reason every component here puts it there: a target
    // reaches past its own extent and its parent does not. A checkbox is
    // 40dp against a 48dp minimum, so the reach is four logical pixels on
    // every side — including the corners, which is where it is thinnest.
    return SceneTapTarget3d(child: announced);
  }
}
