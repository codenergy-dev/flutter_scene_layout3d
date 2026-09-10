import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueChanged, VoidCallback;
import 'package:flutter/gestures.dart'
    show
        GestureArenaEntry,
        GestureArenaMember,
        GestureDisposition,
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerMoveEvent,
        PointerUpEvent,
        computeHitSlop;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, FocusNode, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        HitTestBehavior3d,
        HitTestEntry3d,
        HitTestTarget3d,
        Offset3d,
        PointerEvent3d,
        ProxyLayout3dWithHitTestBehavior,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneIgnorePointer3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneStack3d,
        SceneTapTarget3d,
        SingleChildLayout3dWidget;

import '../theme/theme.dart';
import 'ink_well.dart';
import 'material.dart';
import 'node_shift.dart';
import 'selection_style.dart';
import 'reading_direction.dart';

/// Transparent.
const Color _none = Color(0x00000000);

/// A value chosen by sliding a thumb along a track.
///
/// ```dart
/// Slider3d(
///   value: _volume,
///   onChanged: (value) => setState(() => _volume = value),
///   semanticLabel: 'Volume',
/// )
/// ```
///
/// The catalogue's first component that is *dragged* rather than pressed, and
/// the drag lane's first customer outside a list. Everything it is made of is
/// in [SliderStyle3d].
///
/// ## Winning the pointer, and why that needed a seam
///
/// A slider inside a scrolling list has to take a horizontal drag while the
/// list keeps a vertical one, and the only thing that can arbitrate that is
/// the gesture arena. Two of Flutter's four recognizers do not fire in this
/// build at all, which is why `PointerSequence3d.addArenaMember` exists —
/// the drag plan named "a knob, a slider, a rotation handle" as its
/// customers, and this is the first of them. [SliderGesture3d] is the member:
/// it enters the arena on the press, claims the pointer the moment the finger
/// crosses the touch slop along the slider's own axis, and is rejected
/// without a fuss when the list crosses its slop first.
///
/// A press that never moves is a **tap**, and Material's slider jumps to
/// where it landed. That case is the arena's other half: the member claims at
/// the up, before the sweep, which is legal because what ends an arena is the
/// sweep rather than the close.
///
/// ## Nothing about a drag lays anything out
///
/// The thumb's position is a `nodeOffset` and the active track's length is a
/// `nodeTransform` — [SceneNodeShift3d] writes both, and neither calls
/// `markNeedsLayout`. That second one is the part worth knowing, because the
/// obvious way to fill a track is to give a box a width and change it, which
/// is a relayout on every frame of the drag. A node transform pivots on the
/// box's **origin corner**, so a full-length track scaled by the value keeps
/// its left end exactly where layout put it and stops where the thumb is.
///
/// ## Probing one
///
/// `worldTransform` undoes both channels, so `screenCenter` on the thumb
/// reports the middle of the track whatever the value is. A picture of a
/// slider takes its oracle from the **track**, exactly as phase 6's anchored
/// menu takes its from the button.
class Slider3d extends StatelessWidget {
  /// Creates a slider.
  const Slider3d({
    super.key,
    required this.value,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.width,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.semanticFormatter,
    this.textDirection,
  }) : assert(min <= max),
       assert(divisions == null || divisions > 0),
       assert(width == null || width > 0.0);

  /// Where the thumb is, between [min] and [max].
  final double value;

  /// Called as the thumb moves, or null for a slider that cannot be changed.
  final ValueChanged<double>? onChanged;

  /// Called once, with the value at the press, when a drag begins.
  final VoidCallback? onChangeStart;

  /// Called once when it ends, however it ends.
  final VoidCallback? onChangeEnd;

  /// The smallest value the slider can hold.
  final double min;

  /// The largest.
  final double max;

  /// How many steps the range is divided into, or null for a continuous one.
  final int? divisions;

  /// How wide the slider is, in logical pixels, or null for Material's
  /// narrowest: [SliderStyle3d.minimumTrackWidth], 144dp.
  ///
  /// Flutter's `Slider` fills whatever room it is given and clamps at 144dp.
  /// This one takes a figure, because the position of the thumb is written on
  /// the node tier from the widget that builds it — so the width has to be
  /// known before layout rather than after it. A slider that has to fill a
  /// row can be given the row's width; a slider whose width is not known
  /// until layout is a different component.
  final double? width;

  /// The tokens to draw with, or null for the theme's.
  final SliderStyle3d? style;

  /// The node holding this control's place in the focus tree.
  final FocusNode? focusNode;

  /// Whether the control takes the focus as soon as it is laid out.
  final bool autofocus;

  /// What a screen reader announces this slider as. **State it.**
  final String? semanticLabel;

  /// Turns a value into the string a reader announces, or null for a
  /// percentage.
  final String Function(double value)? semanticFormatter;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// Whether the slider responds to a pointer.
  bool get enabled => onChanged != null;

  /// [value] as a fraction of the range, clamped into it.
  ///
  /// A degenerate range — `min == max` — is a slider with one possible
  /// answer, and it reads as empty rather than as a division by zero.
  double get fraction =>
      max <= min ? 0.0 : ((value - min) / (max - min)).clamp(0.0, 1.0);

  /// [fraction] snapped to [divisions], if there are any.
  double snap(double fraction) {
    final divisions = this.divisions;
    if (divisions == null) return fraction.clamp(0.0, 1.0);
    return (fraction.clamp(0.0, 1.0) * divisions).round() / divisions;
  }

  /// The value a fraction of the range stands for.
  double valueFor(double fraction) => min + snap(fraction) * (max - min);

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tokens = style ?? SliderStyle3d.of(theme);
    final resolved = tokens.resolve(const {}, enabled: enabled);

    final extent = width ?? tokens.minimumTrackWidth;
    // The track is inset by half a thumb at each end, so that the thumb's
    // centre reaches the track's ends rather than its edges — which is what
    // makes an empty slider draw no active track at all.
    final travel = extent - tokens.thumbSize;
    final at = snap(fraction);

    final inactive = SceneSizedBox3d(
      width: metrics.dp(travel),
      height: metrics.dp(tokens.trackHeight),
      child: Material3d(
        color: resolved.inactiveTrack,
        shape: tokens.trackShape,
        elevation: theme.elevation.level0,
        thickness: tokens.trackThickness,
        surfaceTint: _none,
      ),
    );

    // The whole track, stretched to the value about its own left end. One
    // matrix; no box changes size, so nothing is laid out again.
    final active = SceneNodeShift3d(
      scaleX: at,
      child: SceneSizedBox3d(
        width: metrics.dp(travel),
        height: metrics.dp(tokens.trackHeight),
        child: Material3d(
          color: resolved.activeTrack,
          shape: tokens.trackShape,
          elevation: theme.elevation.level0,
          thickness: tokens.trackThickness,
          surfaceTint: _none,
        ),
      ),
    );

    final thumb = SceneNodeShift3d(
      shift: Offset3d(metrics.dp(travel) * (at - 0.5), 0.0, 0.0),
      child: SceneSizedBox3d(
        width: metrics.dp(tokens.thumbSize),
        height: metrics.dp(tokens.thumbSize),
        child: Material3d(
          color: resolved.thumb,
          shape: theme.shape.full,
          elevation: theme.elevation.level0,
          thickness: tokens.thumbThickness,
          surfaceTint: _none,
        ),
      ),
    );

    final changed = onChanged;
    final ink = Material3d(
      color: _none,
      contentColor: resolved.wash,
      shape: theme.shape.full,
      elevation: theme.elevation.level0,
      thickness: tokens.trackThickness,
      surfaceTint: _none,
      alignment: null,
      child: InkWell3d(
        // One target, and it is the one outside this panel.
        minimumSize: Size3d.zero,
        enabled: enabled,
        focusNode: focusNode,
        autofocus: autofocus,
        child: SceneSizedBox3d(
          width: metrics.dp(extent),
          height: metrics.dp(tokens.stateLayerSize),
        ),
      ),
    );

    final body = SceneSliderGesture3d(
      enabled: enabled,
      padding: metrics.dp(tokens.thumbSize / 2.0),
      onChanged: changed == null ? null : (f) => changed(valueFor(f)),
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      child: SceneStack3d(
        alignment: Alignment3d.frontCenter,
        depthStep: metrics.dp(tokens.depthStep),
        children: <Widget>[
          // The wash and the focus, behind everything: an `InkWell3d` finds
          // the enclosing `Material3d`, so a slider inside a card would
          // otherwise light the card up.
          ink,
          SceneIgnorePointer3d(child: inactive),
          SceneIgnorePointer3d(child: active),
          SceneIgnorePointer3d(child: thumb),
        ],
      ),
    );

    final announced = SceneSemantics3d(
      properties: SemanticsProperties(
        slider: true,
        enabled: enabled,
        label: semanticLabel,
        value: (semanticFormatter ?? _percent)(value),
        textDirection: readingDirection3d(context, textDirection),
      ),
      child: body,
    );

    return SceneTapTarget3d(child: announced);
  }

  static String _percent(double value) => '${(value * 100).round()}%';
}

/// The pointer half of a [Slider3d]: a box that turns a press and a drag into
/// a fraction along its own width.
///
/// Separated from the geometry because it is the reusable half. The drag plan
/// in the layout package named the customers of
/// `PointerSequence3d.addArenaMember` as "a knob, a slider, a rotation
/// handle", and what all three want is exactly this: enter the arena on the
/// press so that a scrolling view underneath waits for the slop instead of
/// scrolling out from under the gesture, claim the pointer when the finger
/// commits, and give it up when something else claims first.
///
/// Three things about the arena, all of them settled by test in the drag plan
/// and all of them load-bearing here:
///
///  * **A member alone in the arena wins by default**, a microtask after the
///    press. Winning and *recognizing* are therefore two different events,
///    and this class keeps them apart: `acceptGesture` records a flag and
///    starts nothing.
///  * **A member may resolve long after the arena closes.** What ends it is
///    the sweep at the up. So a slider can wait for the finger to move, and a
///    press that never moves can still claim at the up — which is how a tap
///    on the track lands.
///  * **A member cannot be added after the close**, so the entry is taken
///    during the down dispatch, before anything knows whether it is wanted.
class SliderGesture3d extends ProxyLayout3dWithHitTestBehavior
    implements HitTestTarget3d {
  /// Creates a slider's pointer region.
  SliderGesture3d({
    this.enabled = true,
    this.padding = 0.0,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    super.behavior = HitTestBehavior3d.opaque,
    super.name = 'SliderGesture3d',
  }) : assert(padding >= 0.0);

  /// Whether presses are answered at all.
  bool enabled;

  /// The dead zone at each end, in world units: half a thumb.
  ///
  /// The thumb's *centre* travels between the two, so a press at the very
  /// left of the control reports zero rather than a fraction of a thumb.
  double padding;

  /// Called with a fraction between zero and one as the finger moves.
  ValueChanged<double>? onChanged;

  /// Called when a press becomes a change, before the first [onChanged].
  VoidCallback? onChangeStart;

  /// Called when the gesture ends, however it ends.
  VoidCallback? onChangeEnd;

  final Map<int, _SliderPress3d> _presses = <int, _SliderPress3d>{};

  /// Whether a finger is currently changing the value.
  bool get isDragging => _presses.values.any((press) => press.started);

  /// The fraction a point in this box's own frame stands for.
  ///
  /// Clamped, so a finger dragged past either end holds the slider at its
  /// end rather than running off it — which is what Flutter's does and is the
  /// only behaviour that lets a viewer overshoot without losing the value.
  double fractionAt(Offset3d local) {
    final usable = size.width - 2.0 * padding;
    if (usable <= 0.0) return 0.0;
    return ((local.x - padding) / usable).clamp(0.0, 1.0);
  }

  @override
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry) {
    final raw = event.event;
    if (raw is PointerDownEvent) {
      if (!enabled) return;
      final press = _SliderPress3d(
        owner: this,
        origin: event.localPosition,
        kind: raw.kind,
        metricsScale: event.metricsScale,
      );
      _presses[event.pointer] = press;
      press.begin(event);
    } else if (raw is PointerMoveEvent) {
      _presses[event.pointer]?.update(event);
    } else if (raw is PointerUpEvent) {
      _presses.remove(event.pointer)?.finish(event);
    } else if (raw is PointerCancelEvent) {
      _presses.remove(event.pointer)?.abandon();
    }
  }

  @override
  void dispose() {
    for (final press in _presses.values) {
      press.abandon();
    }
    _presses.clear();
    super.dispose();
  }
}

/// One press on a [SliderGesture3d], competing for the pointer.
///
/// The same shape as `_Drag3dGesture` in the layout package, which is the
/// other hand-rolled arena member built on this seam: accumulate travel,
/// compare it against the touch slop taken through the tree's metrics, and
/// resolve when it crosses.
class _SliderPress3d implements GestureArenaMember {
  _SliderPress3d({
    required this.owner,
    required this.origin,
    required this.kind,
    required this.metricsScale,
  });

  final SliderGesture3d owner;

  /// Where the press landed, in the slider's own frame, in world units.
  final Offset3d origin;

  final PointerDeviceKind kind;

  /// World units per logical pixel, so the slop can be judged in dp.
  final double metricsScale;

  GestureArenaEntry? _entry;

  /// Whether this press is changing the value.
  bool started = false;

  bool _dead = false;

  /// Whether the arena has handed this member the pointer.
  ///
  /// Not the same thing as [started]: a member alone in the arena wins a
  /// microtask after the press, long before the finger has said anything.
  bool _won = false;

  void begin(PointerEvent3d event) {
    _entry = event.addArenaMember(this);
  }

  void update(PointerEvent3d event) {
    if (_dead || !owner.enabled) return;
    if (started) {
      owner.onChanged?.call(owner.fractionAt(event.localPosition));
      return;
    }
    final travel = event.localPosition - origin;
    // The slider's own axis. A finger that wanders down the screen is a
    // scroll, and letting it through is the whole point of entering the
    // arena rather than grabbing the pointer outright.
    if (travel.x.abs() < computeHitSlop(kind, null) * metricsScale) return;
    _recognize();
    owner.onChanged?.call(owner.fractionAt(event.localPosition));
  }

  void finish(PointerEvent3d event) {
    if (_dead) return;
    if (started) {
      _dead = true;
      owner.onChangeEnd?.call();
      return;
    }
    // A press that never moved: Material's slider jumps to it. Claiming at
    // the up is legal — the arena ends at the *sweep*, which has not run yet
    // — and it is what stops a list underneath from taking the pointer.
    _recognize();
    owner.onChanged?.call(owner.fractionAt(event.localPosition));
    _dead = true;
    owner.onChangeEnd?.call();
  }

  void abandon() {
    if (_dead) return;
    _dead = true;
    if (started) {
      owner.onChangeEnd?.call();
    } else {
      _entry?.resolve(GestureDisposition.rejected);
    }
  }

  void _recognize() {
    if (started) return;
    started = true;
    // Claiming rejects every other member still in the arena, so the list
    // under the slider stops scrolling and any pending tap cancels.
    _entry?.resolve(GestureDisposition.accepted);
    owner.onChangeStart?.call();
  }

  @override
  void acceptGesture(int pointer) {
    // Won, not recognized. The slop is this member's own business.
    _won = true;
  }

  @override
  void rejectGesture(int pointer) {
    _won = false;
    if (started) return;
    _dead = true;
  }

  @override
  String toString() =>
      '_SliderPress3d(${started ? 'dragging' : 'pending'}'
      '${_won ? ', won' : ''})';
}

/// The declarative form of [SliderGesture3d].
class SceneSliderGesture3d extends SingleChildLayout3dWidget {
  /// Creates a slider's pointer region around [child].
  const SceneSliderGesture3d({
    super.key,
    this.enabled = true,
    this.padding = 0.0,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    super.child,
  });

  /// Whether presses are answered at all.
  final bool enabled;

  /// The dead zone at each end, in world units.
  final double padding;

  /// Called with a fraction between zero and one as the finger moves.
  final ValueChanged<double>? onChanged;

  /// Called when a press becomes a change.
  final VoidCallback? onChangeStart;

  /// Called when the gesture ends.
  final VoidCallback? onChangeEnd;

  @override
  SliderGesture3d createLayout(BuildContext context) => SliderGesture3d(
    enabled: enabled,
    padding: padding,
    onChanged: onChanged,
    onChangeStart: onChangeStart,
    onChangeEnd: onChangeEnd,
  );

  @override
  void updateLayout(BuildContext context, SliderGesture3d layout) {
    layout
      ..enabled = enabled
      ..padding = padding
      ..onChanged = onChanged
      ..onChangeStart = onChangeStart
      ..onChangeEnd = onChangeEnd;
  }
}
