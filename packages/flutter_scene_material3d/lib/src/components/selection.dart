import 'dart:ui' show Color;

import 'package:flutter/animation.dart'
    show
        Animation,
        AnimationController,
        AnimationStatus,
        Cubic,
        Curve,
        CurvedAnimation,
        Curves;
import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Directionality,
        FocusNode,
        IconData,
        State,
        StatefulWidget,
        StatelessWidget,
        TextDirection,
        TickerProviderStateMixin,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Alignment3d, Offset3d, ProxyLayout3d, Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneIgnorePointer3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneStack3d,
        SceneTapTarget3d,
        SingleChildLayout3dWidget;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../theme/theme.dart';
import 'control_in_tile.dart';
import 'icon.dart';
import 'ink_well.dart';
import 'material.dart';
import 'selection_style.dart';
import 'reading_direction.dart';

/// Transparent: the colour a wash surface and an empty box are drawn in.
const Color _none = Color(0x00000000);

/// A box that is empty or has a mark in it — or, when [tristate], a dash.
///
/// ```dart
/// Checkbox3d(
///   value: _subscribed,
///   onChanged: (value) => setState(() => _subscribed = value!),
///   semanticLabel: 'Subscribe to updates',
/// )
/// ```
///
/// The `!` is Flutter's too. [onChanged] takes a `bool?` because a
/// [tristate] box can be pressed back to null, and it is the signature a
/// ported screen already has; a two-state box never hands it one.
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
/// ## The third state is a glyph, not a row in the table
///
/// A [tristate] box whose [value] is null is *mixed* — the parent of a group
/// some of which are chosen — and Material draws it exactly as a checked box
/// is drawn, filled and with no outline, with `Icons.remove` in place of the
/// tick. So [CheckboxStyle3d] has no third column: a mixed box resolves as a
/// selected one, and what differs is which glyph goes on it and what it
/// publishes, which is `mixed` and not `checked`, as Flutter's does.
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
    this.tristate = false,
    this.style,
    this.icon,
    this.indeterminateIcon,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.textDirection,
  }) : assert(tristate || value != null);

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

  /// `Icons.remove`'s code point, the dash a mixed box is drawn with.
  static const IconData defaultIndeterminateIcon = IconData(
    0xe516,
    fontFamily: 'MaterialIcons',
  );

  /// Whether the box has a mark in it, or null for a mixed one.
  ///
  /// Null only when [tristate]; a two-state box asserts on it.
  final bool? value;

  /// Called with the value the box would become, or null for a box that
  /// cannot be changed.
  ///
  /// A press walks Flutter's cycle: empty to checked, checked to mixed when
  /// [tristate] and to empty otherwise, and mixed to empty.
  final ValueChanged<bool?>? onChanged;

  /// Whether the box has a third, mixed state, which is a null [value].
  final bool tristate;

  /// The tokens to draw with, or null for the theme's.
  final CheckboxStyle3d? style;

  /// The glyph drawn in a full box, or null for [defaultIcon].
  final IconData? icon;

  /// The glyph drawn in a mixed box, or null for [defaultIndeterminateIcon].
  final IconData? indeterminateIcon;

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

  /// What a press makes of [current], in Flutter's order.
  ///
  /// Public so the labelled tile walks the same cycle as the box it holds,
  /// rather than a second copy of it.
  static bool? next(bool? current, {required bool tristate}) =>
      switch (current) {
        false => true,
        true => tristate ? null : false,
        null => false,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tokens = style ?? CheckboxStyle3d.of(theme);
    // A mixed box is drawn as a full one: filled, no outline, a mark on it.
    final resolved = tokens.resolve(
      const {},
      selected: value != false,
      enabled: enabled,
    );
    final changed = onChanged;
    final tap = changed == null
        ? null
        : () => changed(next(value, tristate: tristate));

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
        // Flutter's pair: a mixed box is not checked, and says it is mixed.
        checked: value ?? false,
        mixed: tristate ? value == null : null,
        enabled: enabled,
        label: semanticLabel,
        textDirection: readingDirection3d(context, textDirection),
        onTap: tap,
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
            value == null
                ? indeterminateIcon ?? defaultIndeterminateIcon
                : icon ?? defaultIcon,
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
        textDirection: readingDirection3d(context, textDirection),
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
/// A 52 by 32 track with a thumb on it, Material's own figures, all in
/// [SwitchStyle3d].
///
/// ## The thumb moves on the node tier, and that is not an optimisation
///
/// A toggle is three motions at once, all transcribed from Flutter's M3
/// switch and all over `theme.motion.medium2`, which is Flutter's 300ms:
///
///  * **The slide**, on `Curves.easeOutBack` forward and its flip backward,
///    so the thumb runs a little past the end and settles.
///  * **The growth**: 16dp off and 24dp on, passing through a 34 by 22
///    stretch on the way — Flutter's three-part sequence, 11% of the run to
///    the stretch, 72% to the far size and 17% held.
///  * **The press**: a held thumb swells to 28dp over `theme.motion.short2`,
///    and lets go the same way.
///
/// None of that lays anything out. The thumb is laid out once, at 24dp, in
/// the middle of the track; a private box above it listens to the switch's
/// two controllers and writes a `nodeOffset` for the slide and a
/// `nodeTransform` scaling about the thumb's centre for everything else. A
/// toggle rebuilds the switch once, for its colours, and the 300ms after it
/// are matrices — `docs/traps.md`'s second tier, which is what a thumb moving
/// along a track is.
///
/// Two consequences to know before probing one. **`worldTransform` undoes
/// both channels**, so `screenCenter` on the thumb reports the middle of the
/// track whichever way the switch is set; a picture of a switch takes its
/// oracle from the *track*. And a stretched thumb is an **ellipse**, where
/// Flutter's is a stadium, because a scale stretches the corner radius with
/// the box — for the thirtieth of a second it is at its widest.
///
/// ## The colours change at once
///
/// Flutter cross-fades the track and the thumb over the same 300ms. Here a
/// colour is a token on a `Material3d`, and fading one means rebuilding it
/// every frame — so the colours change on the toggle's first frame and the
/// geometry takes the time. The motion reads as a thumb crossing a track that
/// has already changed, which is most of what Flutter's reads as too, since
/// its fade is on `Curves.easeOut`.
///
/// ## The thumb stands proud of the track
///
/// A thumb resting exactly on the track's front face is coplanar with it and
/// z-fights: it comes out in patches, differently on every frame and every
/// driver. [SwitchStyle3d.depthStep] lifts it clear, and the figure is
/// [Thickness3d.stepOver] of the two thicknesses rather than a constant. This
/// is the same rule `Divider3d` found for a rule on a card and
/// `NavigationStyle3d` found for a glyph on a pill.
class Switch3d extends StatefulWidget {
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
  /// than as a mark on it. A thumb with an icon is full size in both states,
  /// as Flutter's is, so the glyph is never shrunk.
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

  /// The curve the thumb slides on toward on: Flutter's M3 switch's.
  ///
  /// It overshoots, so the thumb runs past the end and settles. Toward off
  /// the thumb takes its flip, so it overshoots the other end.
  static const Curve slideCurve = Curves.easeOutBack;

  @override
  State<Switch3d> createState() => _Switch3dState();
}

class _Switch3dState extends State<Switch3d> with TickerProviderStateMixin {
  /// How far across the thumb is, from 0 at off to 1 at on, before any curve.
  ///
  /// The growth is read off this raw value and the slide off [_slide], which
  /// is Flutter's split: its size sequence animates the controller and its
  /// position the curved animation.
  late final AnimationController _position = AnimationController(
    value: widget.value ? 1.0 : 0.0,
    vsync: this,
  );

  late final CurvedAnimation _slide = CurvedAnimation(
    parent: _position,
    curve: Switch3d.slideCurve,
    reverseCurve: Switch3d.slideCurve.flipped,
  );

  /// How far the held thumb has swollen, from 0 to 1.
  late final AnimationController _press = AnimationController(vsync: this);

  @override
  void didUpdateWidget(Switch3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    if (widget.value) {
      _position.forward();
    } else {
      _position.reverse();
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _position.dispose();
    _press.dispose();
    super.dispose();
  }

  void _pressed(bool down) {
    // A gesture can be delivered after the switch has left the tree; see
    // `Button3d`'s `_note`.
    if (!mounted) return;
    if (down) {
      _press.forward();
    } else {
      _press.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tokens = widget.style ?? SwitchStyle3d.of(theme);
    final value = widget.value;
    final enabled = widget.enabled;
    final resolved = tokens.resolve(
      const {},
      selected: value,
      enabled: enabled,
    );
    final changed = widget.onChanged;
    final tap = changed == null ? null : () => changed(!value);
    final inTile = ControlInTile3d.isIn(context);

    // Read here rather than once, so a theme that slows motion down reaches
    // the next toggle.
    _position.duration = theme.motion.medium2;
    _press.duration = theme.motion.short2;

    final extent = SceneSizedBox3d(
      width: metrics.dp(tokens.trackWidth),
      height: metrics.dp(tokens.trackHeight),
    );
    final track = Material3d(
      color: resolved.track,
      contentColor: resolved.wash,
      shape: tokens.trackShape,
      elevation: theme.elevation.level0,
      thickness: tokens.trackThickness,
      border: resolved.border,
      surfaceTint: _none,
      alignment: null,
      // In a labelled tile the row is the control, so the track is only
      // drawn: see `ControlInTile3d`. With no well there is no press either,
      // so a switch in a tile slides and does not swell — Flutter's doesn't.
      child: inTile
          ? extent
          : InkWell3d(
              // One target, and it is the one outside this panel.
              minimumSize: Size3d.zero,
              enabled: enabled,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              onTap: tap,
              onHighlightChanged: _pressed,
              child: extent,
            ),
    );

    final icon = widget.thumbIcon;
    final thumb = SceneIgnorePointer3d(
      child: _SceneSwitchThumb3d(
        slide: _slide,
        position: _position,
        press: _press,
        // On is toward the end of the reading direction, so in right to left
        // it is the left, as Flutter's switch has it.
        rtl: Directionality.maybeOf(context) == TextDirection.rtl,
        travel: tokens.travel,
        drawn: tokens.thumbSize,
        unselected: icon == null
            ? tokens.unselectedThumbSize
            : tokens.thumbSize,
        selected: tokens.thumbSize,
        pressed: tokens.pressedThumbSize,
        stretchWidth: tokens.transitionalThumbWidth,
        stretchHeight: tokens.transitionalThumbHeight,
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
            child: icon == null
                ? null
                : Icon3d(
                    icon,
                    size: tokens.thumbSize * 2.0 / 3.0,
                    color: resolved.track,
                  ),
          ),
        ),
      ),
    );

    final drawn = SceneStack3d(
      alignment: Alignment3d.frontCenter,
      depthStep: metrics.dp(tokens.depthStep),
      children: <Widget>[track, thumb],
    );
    if (inTile) return SceneIgnorePointer3d(child: drawn);

    final announced = SceneSemantics3d(
      properties: SemanticsProperties(
        toggled: value,
        enabled: enabled,
        label: widget.semanticLabel,
        textDirection: readingDirection3d(context, widget.textDirection),
        onTap: tap,
      ),
      child: drawn,
    );

    // Outermost, and doing real work: a switch is 32dp tall against a 48dp
    // minimum, so the reach is eight logical pixels above and below that no
    // box in the layout knows about.
    return SceneTapTarget3d(child: announced);
  }
}

/// Flutter's thumb size at [t] of a run toward on, and toward off when
/// [forward] is false: `_MaterialSwitchPainter`'s three-part sequence.
///
/// Every figure in logical pixels, as a width and a height. At rest a run
/// toward on is at 0 and one toward off at 1, and both read the size the
/// switch is resting at.
(double, double) _thumbSizeAt(
  double t, {
  required bool forward,
  required double unselected,
  required double selected,
  required double stretchWidth,
  required double stretchHeight,
}) {
  (double, double) lerp(double aw, double ah, double bw, double bh, double f) =>
      (aw + (bw - aw) * f, ah + (bh - ah) * f);
  // The ends exactly, rather than through the curves: a `Cubic` is solved
  // to within a thousandth, so a thumb at rest would otherwise be drawn a
  // hair off its size and never lose its transform.
  if (t <= 0.0) return (unselected, unselected);
  if (t >= 1.0) return (selected, selected);
  const out = Cubic(0.31, 0.0, 0.56, 1.0);
  const settle = Cubic(0.2, 0.0, 0.0, 1.0);
  // The weights are Flutter's: 11, 72 and 17 parts of a hundred.
  if (forward) {
    if (t < 0.11) {
      return lerp(
        unselected,
        unselected,
        stretchWidth,
        stretchHeight,
        out.transform(t / 0.11),
      );
    }
    if (t < 0.83) {
      return lerp(
        stretchWidth,
        stretchHeight,
        selected,
        selected,
        settle.transform((t - 0.11) / 0.72),
      );
    }
    return (selected, selected);
  }
  if (t < 0.17) return (unselected, unselected);
  if (t < 0.89) {
    return lerp(
      unselected,
      unselected,
      stretchWidth,
      stretchHeight,
      settle.flipped.transform((t - 0.17) / 0.72),
    );
  }
  return lerp(
    stretchWidth,
    stretchHeight,
    selected,
    selected,
    out.flipped.transform((t - 0.89) / 0.11),
  );
}

/// The switch's thumb, moved and scaled on the node tier from the switch's
/// clocks.
///
/// Laid out as its child is — the thumb at its full size, centred on the
/// track — and never laid out again by any of this: a tick writes
/// [Layout3d.nodeOffset] for where the thumb is along the track and
/// [Layout3d.nodeTransform] for how big it is drawn, scaled about its own
/// centre. Every figure it is given is in logical pixels, converted through
/// the surface's metrics when it is written.
class _SwitchThumb3d extends ProxyLayout3d {
  _SwitchThumb3d({
    required Animation<double> slide,
    required AnimationController position,
    required Animation<double> press,
    required this.rtl,
    required this.travel,
    required this.drawn,
    required this.unselected,
    required this.selected,
    required this.pressed,
    required this.stretchWidth,
    required this.stretchHeight,
  }) : _slide = slide,
       _position = position,
       _press = press,
       super(name: 'Switch3d thumb') {
    _slide.addListener(_apply);
    _press.addListener(_apply);
  }

  Animation<double> _slide;
  AnimationController _position;
  Animation<double> _press;

  bool rtl;
  double travel;
  double drawn;
  double unselected;
  double selected;
  double pressed;
  double stretchWidth;
  double stretchHeight;

  void update({
    required Animation<double> slide,
    required AnimationController position,
    required Animation<double> press,
  }) {
    if (!identical(slide, _slide)) {
      _slide.removeListener(_apply);
      _slide = slide..addListener(_apply);
    }
    _position = position;
    if (!identical(press, _press)) {
      _press.removeListener(_apply);
      _press = press..addListener(_apply);
    }
    _apply();
  }

  @override
  void performLayout() {
    super.performLayout();
    _apply();
  }

  void _apply() {
    if (!hasSize) return;
    final metrics = this.metrics;

    // Where along the track: half the travel either side of the middle,
    // which is where layout put the thumb. The curved value, so it overshoots.
    final along = rtl ? 1.0 - _slide.value : _slide.value;
    nodeOffset = Offset3d(metrics.dp(travel) * (along - 0.5), 0.0, 0.0);

    // How big: Flutter's sequence off the raw value, in whichever direction
    // the run is going — a switch at rest on reads the sequence toward off
    // at its start, which is the on size — and then toward the held size by
    // however far the press has got.
    final forward =
        _position.status == AnimationStatus.forward ||
        _position.status == AnimationStatus.dismissed;
    final (width, height) = _thumbSizeAt(
      _position.value,
      forward: forward,
      unselected: unselected,
      selected: selected,
      stretchWidth: stretchWidth,
      stretchHeight: stretchHeight,
    );
    final swell = _press.value;
    final sx = (width + (pressed - width) * swell) / drawn;
    final sy = (height + (pressed - height) * swell) / drawn;

    // About the thumb's centre: the node transform pivots on its origin
    // corner, so the corner moves in by what the scale takes off each side.
    final centre = size.width / 2.0;
    if (sx == 1.0 && sy == 1.0) {
      nodeTransform = null;
      return;
    }
    nodeTransform = Matrix4.diagonal3Values(sx, sy, 1.0)
      ..setTranslationRaw(centre * (1.0 - sx), centre * (1.0 - sy), 0.0);
  }

  @override
  void dispose() {
    _slide.removeListener(_apply);
    _press.removeListener(_apply);
    super.dispose();
  }
}

class _SceneSwitchThumb3d extends SingleChildLayout3dWidget {
  const _SceneSwitchThumb3d({
    required this.slide,
    required this.position,
    required this.press,
    required this.rtl,
    required this.travel,
    required this.drawn,
    required this.unselected,
    required this.selected,
    required this.pressed,
    required this.stretchWidth,
    required this.stretchHeight,
    super.child,
  });

  final Animation<double> slide;
  final AnimationController position;
  final Animation<double> press;
  final bool rtl;
  final double travel;
  final double drawn;
  final double unselected;
  final double selected;
  final double pressed;
  final double stretchWidth;
  final double stretchHeight;

  @override
  _SwitchThumb3d createLayout(BuildContext context) => _SwitchThumb3d(
    slide: slide,
    position: position,
    press: press,
    rtl: rtl,
    travel: travel,
    drawn: drawn,
    unselected: unselected,
    selected: selected,
    pressed: pressed,
    stretchWidth: stretchWidth,
    stretchHeight: stretchHeight,
  );

  @override
  void updateLayout(BuildContext context, _SwitchThumb3d layout) {
    layout
      ..rtl = rtl
      ..travel = travel
      ..drawn = drawn
      ..unselected = unselected
      ..selected = selected
      ..pressed = pressed
      ..stretchWidth = stretchWidth
      ..stretchHeight = stretchHeight
      ..update(slide: slide, position: position, press: press);
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
    final inTile = ControlInTile3d.isIn(context);

    final size = SceneSizedBox3d(
      width: metrics.dp(extent),
      height: metrics.dp(extent),
    );
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
      // In a labelled tile the row is the control and this is only its
      // picture — no well, so no focus and no wash of its own. The surface
      // stays, so the control is the same size and depth in a tile as out of
      // one. See `ControlInTile3d`.
      child: inTile
          ? size
          : InkWell3d(
              // One target, and it is the one outside this panel.
              minimumSize: Size3d.zero,
              enabled: enabled,
              focusNode: focusNode,
              autofocus: autofocus,
              onTap: onTap,
              child: size,
            ),
    );

    final drawn = SceneStack3d(
      alignment: Alignment3d.frontCenter,
      depthStep: metrics.dp(depthStep),
      children: <Widget>[
        surface,
        // The ink answers no ray: everything a pointer needs to find is the
        // well behind it, and a `Text3d` mark would otherwise answer on its
        // own account.
        for (final child in children) SceneIgnorePointer3d(child: child),
      ],
    );
    if (inTile) return SceneIgnorePointer3d(child: drawn);

    final announced = SceneSemantics3d(properties: properties, child: drawn);

    // Outermost, for the reason every component here puts it there: a target
    // reaches past its own extent and its parent does not. A checkbox is
    // 40dp against a 48dp minimum, so the reach is four logical pixels on
    // every side — including the corners, which is where it is thinnest.
    return SceneTapTarget3d(child: announced);
  }
}
