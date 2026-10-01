import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/animation.dart'
    show
        Animation,
        AnimationController,
        Curve,
        Cubic,
        Curves,
        Interval,
        SawTooth;
import 'package:flutter/painting.dart' show SweepGradient;
import 'package:flutter/semantics.dart' show SemanticsProperties, SemanticsRole;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Directionality,
        SingleTickerProviderStateMixin,
        State,
        StatefulWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        Border3d,
        BoxDecoration3d,
        Constraints3d,
        DecoratedBox3d,
        Offset3d,
        ProxyLayout3d,
        SingleChildLayout3d,
        Size3d,
        StackFit3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneSemantics3d,
        SceneSizedBox3d,
        Layout3dWidget,
        SceneStack3d,
        SingleChildLayout3dWidget;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../theme/theme.dart';
import 'material.dart';
import 'progress_indicator_style.dart';
import 'reading_direction.dart';

/// Transparent: the colour of the ring's middle, and of an arc's absence.
const Color _none = Color(0x00000000);

/// A bar that fills as something finishes, or — with no [value] — two lines
/// that chase each other along it while something is under way.
///
/// ```dart
/// LinearProgressIndicator3d(
///   value: _received / _total,
///   semanticsLabel: 'Downloading',
/// )
/// ```
///
/// Flutter's own parameters and Flutter's default look: a 4dp bar in
/// `primary` on a `secondaryContainer` track, with square ends. See
/// [ProgressIndicatorStyle3d] for which of Flutter's two Material 3 designs
/// that is, and why.
///
/// ## A bar that fills is a scale, not a width
///
/// The obvious bar gives the filled part a width and changes it, which is a
/// relayout for every value. Here the filled part is a slab as long as the
/// track, stretched along x on the **node tier** from the end it grows from:
/// one matrix, nothing laid out, which is what `docs/traps.md` says about a
/// bar that fills and what `Slider3d` already does with its active track.
///
/// The difference from the slider is that a slider knows its width when it is
/// built and this bar does not — it fills whatever its parent gives it, as
/// Flutter's does. So the stretch is written by a box that holds the span as
/// two fractions and turns them into a matrix from its own `performLayout`,
/// once it has a size, as well as whenever they change. In right to left the
/// span is mirrored inside that box and the bar fills from the right.
///
/// ## Indeterminate is two spans on Flutter's timeline
///
/// Flutter's indeterminate bar is two lines whose ends follow four curves over
/// 1800ms, repeating; this is the same two lines on the same four curves,
/// each one a span box listening to the clock directly. **No widget is built
/// and no box is laid out** for as long as it runs, which is the property
/// `test/progress_indicator_test.dart` holds it to. The track is drawn whole
/// behind the lines rather than in the pieces Flutter paints between them,
/// because here it is a slab and the lines stand one step in front of it.
///
/// An indeterminate bar never stops asking for frames, exactly as Flutter's
/// does — so a test that settles a screen with one on it never settles.
class LinearProgressIndicator3d extends StatefulWidget {
  /// Creates a linear progress indicator.
  const LinearProgressIndicator3d({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.minHeight,
    this.style,
    this.semanticsLabel,
    this.semanticsValue,
    this.textDirection,
  }) : assert(minHeight == null || minHeight > 0.0);

  /// How much is done, from 0 to 1, or null for an indeterminate bar.
  ///
  /// Held to `[0, 1]`, as Flutter's is.
  final double? value;

  /// The colour of the part that shows progress, or null for the style's.
  final Color? color;

  /// The track's colour, or null for the style's.
  final Color? backgroundColor;

  /// How tall the bar is, in logical pixels, or null for the style's 4dp.
  final double? minHeight;

  /// The tokens to draw with, or null for the theme's.
  final ProgressIndicatorStyle3d? style;

  /// What a screen reader announces this bar as.
  final String? semanticsLabel;

  /// What a screen reader announces as the bar's value, or null for the
  /// percentage — which is Flutter's default, and is only published for a
  /// determinate bar.
  final String? semanticsValue;

  /// The direction [semanticsLabel] reads in.
  final TextDirection? textDirection;

  /// How long one pass of the indeterminate lines takes: Flutter's 1800ms,
  /// which is public there as `LinearProgressIndicator.defaultAnimationDuration`.
  static const Duration indeterminateDuration = Duration(milliseconds: 1800);

  // Flutter's four curves, transcribed from `_LinearProgressIndicatorPainter`,
  // where they are private: for each of the two lines, where its leading end
  // (the head) and its trailing end (the tail) are at a point of the pass.
  static const Curve _line1Head = Interval(
    0.0,
    750.0 / 1800.0,
    curve: Cubic(0.2, 0.0, 0.8, 1.0),
  );
  static const Curve _line1Tail = Interval(
    333.0 / 1800.0,
    (333.0 + 750.0) / 1800.0,
    curve: Cubic(0.4, 0.0, 1.0, 1.0),
  );
  static const Curve _line2Head = Interval(
    1000.0 / 1800.0,
    (1000.0 + 567.0) / 1800.0,
    curve: Cubic(0.0, 0.0, 0.65, 1.0),
  );
  static const Curve _line2Tail = Interval(
    1267.0 / 1800.0,
    (1267.0 + 533.0) / 1800.0,
    curve: Cubic(0.10, 0.0, 0.45, 1.0),
  );

  /// Where the first indeterminate line runs, from its tail to its head, at
  /// [t] of a pass.
  ///
  /// Fractions of the bar, measured from the end it grows from. Public so a
  /// test can ask where the line should be without transcribing the curves a
  /// second time.
  static (double, double) firstLineAt(double t) =>
      (_line1Tail.transform(t), _line1Head.transform(t));

  /// Where the second indeterminate line runs at [t] of a pass.
  static (double, double) secondLineAt(double t) =>
      (_line2Tail.transform(t), _line2Head.transform(t));

  @override
  State<LinearProgressIndicator3d> createState() =>
      _LinearProgressIndicator3dState();
}

class _LinearProgressIndicator3dState extends State<LinearProgressIndicator3d>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    duration: LinearProgressIndicator3d.indeterminateDuration,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    if (widget.value == null) _clock.repeat();
  }

  @override
  void didUpdateWidget(LinearProgressIndicator3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && !_clock.isAnimating) {
      _clock.repeat();
    } else if (widget.value != null && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tokens = widget.style ?? ProgressIndicatorStyle3d.of(theme);
    // The ambient direction for the drawing, as Flutter's painter reads it;
    // the widget's own `textDirection` is what the label is announced in.
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final value = widget.value?.clamp(0.0, 1.0);

    Widget slab(Color color) => Material3d(
      color: color,
      shape: theme.shape.none,
      elevation: theme.elevation.level0,
      thickness: tokens.thickness,
      surfaceTint: _none,
    );

    final bar = slab(widget.color ?? tokens.color);
    final spans = value == null
        ? <Widget>[
            _SceneProgressSpan3d(
              animation: _clock,
              spanAt: LinearProgressIndicator3d.firstLineAt,
              rtl: rtl,
              name: 'LinearProgressIndicator3d first line',
              child: bar,
            ),
            _SceneProgressSpan3d(
              animation: _clock,
              spanAt: LinearProgressIndicator3d.secondLineAt,
              rtl: rtl,
              name: 'LinearProgressIndicator3d second line',
              child: slab(widget.color ?? tokens.color),
            ),
          ]
        : <Widget>[
            _SceneProgressSpan3d(
              start: 0.0,
              end: value,
              rtl: rtl,
              name: 'LinearProgressIndicator3d value',
              child: bar,
            ),
          ];

    return SceneSemantics3d(
      properties: _semantics(
        context,
        value: value,
        label: widget.semanticsLabel,
        semanticsValue: widget.semanticsValue,
        textDirection: widget.textDirection,
      ),
      // As wide as the parent allows, as Flutter's is: its bar is a
      // `Container` with an infinite minimum width.
      child: SceneSizedBox3d(
        width: double.infinity,
        height: metrics.dp(widget.minHeight ?? tokens.linearMinHeight),
        child: SceneStack3d(
          alignment: Alignment3d.frontCenter,
          // Every slab fills the bar in the plane and keeps its own depth:
          // `expand` would hand each one the stack's depth as well.
          fit: StackFit3d.passthrough,
          depthStep: metrics.dp(tokens.depthStep),
          children: <Widget>[
            slab(widget.backgroundColor ?? tokens.linearTrackColor),
            ...spans,
          ],
        ),
      ),
    );
  }
}

/// A ring that fills clockwise from twelve o'clock as something finishes, or
/// — with no [value] — an arc that chases itself round while something is
/// under way.
///
/// ```dart
/// SceneSizedBox3d(
///   width: metrics.dp(20),
///   height: metrics.dp(20),
///   child: const CircularProgressIndicator3d(strokeWidth: 2),
/// )
/// ```
///
/// Flutter's own parameters and Flutter's default geometry: a 36dp box, a 4dp
/// stroke in `primary`, and no track unless [backgroundColor] asks for one.
///
/// ## An arc is a ring with a gradient on its border
///
/// Flutter draws this with one `drawArc`. The panel shader draws rounded boxes,
/// and a transparent circle with a 4dp border is the **ring**; what makes it
/// an arc is `Border3d.gradient`, a `SweepGradient` on the border with a hard
/// stop at the value, so the band is drawn where the ramp is opaque and
/// discarded where it is not. The track, when there is one, is the rest of the
/// same ramp — one slab, not two that could z-fight.
///
/// A sweep starts at three o'clock and the shader cannot turn it, so **the
/// panel is turned instead**, on the node tier: to twelve o'clock for a value,
/// and wherever Flutter's head and tail have got to for an indeterminate arc.
/// A circle's distance field does not care which way it faces.
///
/// ## The stroke overhangs the box, as Flutter's does
///
/// Flutter centres its stroke on the circle inscribed in the box, so a 36dp
/// indicator draws a ring 40dp across and 32dp inside. This one draws the same
/// ring: the panel is laid out half a stroke larger than the box on every side
/// and placed over it, and the box a caller lays out against is still 36dp.
/// Nothing reaches the overhang with a ray — every ancestor gates a ray on its
/// own extent — and nothing needs to.
///
/// ## Indeterminate is a decoration and a turn
///
/// Flutter's head and tail follow two halves of a `fastOutSlowIn` every
/// 1333ms while the whole arc turns every 2222ms; this reads the same curves
/// off the same clock. Each frame writes the arc's length into the border's
/// gradient, which is a shader parameter — the repaint tier — and its start
/// into the panel's node transform. Nothing is built and nothing is laid out.
///
/// Flutter's indeterminate arc has square caps and its determinate one butt
/// caps. Both ends of an arc here are the band cut along a radius, which is a
/// butt cap; the indeterminate arc is lengthened by half a stroke at each end,
/// which is what a square cap on a circle nearly is. The ends are also a hard
/// stop in the ramp and are **not anti-aliased** the way the ring's two edges
/// are.
class CircularProgressIndicator3d extends StatefulWidget {
  /// Creates a circular progress indicator.
  const CircularProgressIndicator3d({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.strokeWidth,
    this.style,
    this.semanticsLabel,
    this.semanticsValue,
    this.textDirection,
  }) : assert(strokeWidth == null || strokeWidth > 0.0);

  /// How much is done, from 0 to 1, or null for an indeterminate arc.
  final double? value;

  /// The arc's colour, or null for the style's.
  final Color? color;

  /// The track's colour, or null for the style's — which is none.
  final Color? backgroundColor;

  /// How thick the stroke is, in logical pixels, or null for the style's
  /// 4dp.
  final double? strokeWidth;

  /// The tokens to draw with, or null for the theme's.
  final ProgressIndicatorStyle3d? style;

  /// What a screen reader announces this indicator as.
  final String? semanticsLabel;

  /// What a screen reader announces as the indicator's value, or null for the
  /// percentage of a determinate one.
  final String? semanticsValue;

  /// The direction [semanticsLabel] reads in.
  final TextDirection? textDirection;

  // Flutter's clock: one controller whose period is the least common multiple
  // of the arc's 1333ms and the turn's 2222ms, cut back into those two by a
  // saw-tooth each. Transcribed from `_CircularProgressIndicatorState`.
  static const int _headPeriod = 1333;
  static const int _turnPeriod = 2222;
  static const Duration _clockPeriod = Duration(
    milliseconds: _headPeriod * _turnPeriod,
  );
  static const Curve _pass = SawTooth(_turnPeriod);
  static const Curve _turn = SawTooth(_headPeriod);
  static const Curve _head = Interval(0.0, 0.5, curve: Curves.fastOutSlowIn);
  static const Curve _tail = Interval(0.5, 1.0, curve: Curves.fastOutSlowIn);

  /// Where an indeterminate arc starts, and how far it runs, in radians, at
  /// [t] of Flutter's clock — measured clockwise from three o'clock, as a
  /// `Canvas.drawArc` measures it.
  ///
  /// Flutter's arithmetic, before this package lengthens the arc by its caps.
  /// Public so a test can ask where the arc should be without transcribing
  /// the curves a second time.
  static (double, double) indeterminateArcAt(double t) {
    final pass = _pass.transform(t);
    final head = _head.transform(pass);
    final tail = _tail.transform(pass);
    final turn = _turn.transform(t);
    final start =
        -math.pi / 2.0 +
        tail * 3.0 / 2.0 * math.pi +
        turn * math.pi * 2.0 +
        pass * 0.5 * math.pi;
    final sweep = math.max(
      head * 3.0 / 2.0 * math.pi - tail * 3.0 / 2.0 * math.pi,
      0.001,
    );
    return (start, sweep);
  }

  @override
  State<CircularProgressIndicator3d> createState() =>
      _CircularProgressIndicator3dState();
}

class _CircularProgressIndicator3dState
    extends State<CircularProgressIndicator3d>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    duration: CircularProgressIndicator3d._clockPeriod,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    if (widget.value == null) _clock.repeat();
  }

  @override
  void didUpdateWidget(CircularProgressIndicator3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && !_clock.isAnimating) {
      _clock.repeat();
    } else if (widget.value != null && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tokens = widget.style ?? ProgressIndicatorStyle3d.of(theme);
    final value = widget.value?.clamp(0.0, 1.0);
    final side = metrics.dp(tokens.circularSize);

    return SceneSemantics3d(
      properties: _semantics(
        context,
        value: value,
        label: widget.semanticsLabel,
        semanticsValue: widget.semanticsValue,
        textDirection: widget.textDirection,
      ),
      child: SceneSizedBox3d(
        width: side,
        height: side,
        child: _SceneRingFrame3d(
          strokeWidth: widget.strokeWidth ?? tokens.strokeWidth,
          thickness: tokens.thickness,
          child: _SceneRingPanel3d(
            // Everything but the border, which the ring writes itself: the
            // resolution stays in the one place a token becomes a decoration.
            base: Material3d.decorationFor(
              theme,
              color: _none,
              shape: theme.shape.full,
              elevation: theme.elevation.level0,
              thickness: tokens.thickness,
              surfaceTint: _none,
            ),
            color: widget.color ?? tokens.color,
            track: widget.backgroundColor ?? tokens.circularTrackColor,
            strokeWidth: widget.strokeWidth ?? tokens.strokeWidth,
            value: value,
            animation: value == null ? _clock : null,
          ),
        ),
      ),
    );
  }
}

/// Flutter's progress semantics: a progress bar from 0 to 100 when there is a
/// value, a loading spinner when there is not.
SemanticsProperties _semantics(
  BuildContext context, {
  required double? value,
  required String? label,
  required String? semanticsValue,
  required TextDirection? textDirection,
}) {
  final determinate = value != null;
  return SemanticsProperties(
    label: label,
    role: determinate
        ? SemanticsRole.progressBar
        : SemanticsRole.loadingSpinner,
    minValue: determinate ? '0' : null,
    maxValue: determinate ? '100' : null,
    value: semanticsValue ?? (determinate ? '${(value * 100).round()}' : null),
    textDirection: readingDirection3d(context, textDirection),
  );
}

/// The span of a bar a [_ProgressSpan3d] stretches its child over, from the
/// end the bar grows from.
typedef _SpanAt = (double, double) Function(double t);

/// Stretches its child over a span of its own width **on the node tier**.
///
/// The child is laid out across the whole box; the span is two fractions of
/// it, and the box writes `T(x₀·w) · S(x₁ − x₀)` onto its own node whenever
/// they change and whenever it is laid out — the second because the width is
/// not known until then. The transform pivots on the box's origin corner, so
/// the span's left end is `x₀` of the way across.
class _ProgressSpan3d extends ProxyLayout3d {
  _ProgressSpan3d({
    double start = 0.0,
    double end = 1.0,
    Animation<double>? animation,
    _SpanAt? spanAt,
    bool rtl = false,
    super.name,
  }) : _start = start,
       _end = end,
       _animation = animation,
       _spanAt = spanAt,
       _rtl = rtl {
    animation?.addListener(_apply);
  }

  double _start;
  double _end;
  _SpanAt? _spanAt;
  bool _rtl;
  Animation<double>? _animation;

  set start(double value) {
    if (_start == value) return;
    _start = value;
    _apply();
  }

  set end(double value) {
    if (_end == value) return;
    _end = value;
    _apply();
  }

  set spanAt(_SpanAt? value) {
    if (_spanAt == value) return;
    _spanAt = value;
    _apply();
  }

  set rtl(bool value) {
    if (_rtl == value) return;
    _rtl = value;
    _apply();
  }

  set animation(Animation<double>? value) {
    if (identical(_animation, value)) return;
    _animation?.removeListener(_apply);
    _animation = value?..addListener(_apply);
    _apply();
  }

  @override
  void performLayout() {
    super.performLayout();
    // The width exists now, so the span can be turned into world units. This
    // is the write that makes the first frame right: on the frame the box is
    // made, a setter or a tick arrives before there is anything to measure.
    _apply();
  }

  void _apply() {
    if (!hasSize) return;
    final animation = _animation;
    final spanAt = _spanAt;
    final (from, to) = animation != null && spanAt != null
        ? spanAt(animation.value)
        : (_start, _end);
    final start = from.clamp(0.0, 1.0);
    final end = to.clamp(0.0, 1.0);
    final length = end > start ? end - start : 0.0;
    // Mirrored inside the box in right to left, as Flutter's painter mirrors
    // its rectangle: the span grows from the right.
    final left = _rtl ? 1.0 - end : start;
    nodeTransform = left == 0.0 && length == 1.0
        ? null
        : (Matrix4.translationValues(left * size.width, 0.0, 0.0)
            ..scaleByDouble(length, 1.0, 1.0, 1.0));
  }

  @override
  void dispose() {
    _animation?.removeListener(_apply);
    super.dispose();
  }
}

class _SceneProgressSpan3d extends SingleChildLayout3dWidget {
  const _SceneProgressSpan3d({
    this.start = 0.0,
    this.end = 1.0,
    this.animation,
    this.spanAt,
    required this.rtl,
    required this.name,
    super.child,
  });

  final double start;
  final double end;
  final Animation<double>? animation;
  final _SpanAt? spanAt;
  final bool rtl;
  final String name;

  @override
  _ProgressSpan3d createLayout(BuildContext context) => _ProgressSpan3d(
    start: start,
    end: end,
    animation: animation,
    spanAt: spanAt,
    rtl: rtl,
    name: name,
  );

  @override
  void updateLayout(BuildContext context, _ProgressSpan3d layout) {
    layout
      ..start = start
      ..end = end
      ..spanAt = spanAt
      ..rtl = rtl
      ..animation = animation;
  }
}

/// The box a [CircularProgressIndicator3d] lays out against, holding its
/// ring half a stroke larger on every side.
///
/// Pure layout: the box is whatever size it is given, and its one child —
/// the [_RingPanel3d] — is laid out as the box's shorter side plus one stroke
/// across and placed over the box's centre. That is Flutter's geometry, whose
/// stroke is centred on the circle the box inscribes.
class _RingFrame3d extends SingleChildLayout3d {
  _RingFrame3d({required double strokeWidth, required double thickness})
    : _strokeWidth = strokeWidth,
      _thickness = thickness,
      super(name: 'CircularProgressIndicator3d');

  /// In logical pixels.
  double _strokeWidth;
  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    _strokeWidth = value;
    markNeedsLayout();
  }

  /// In logical pixels.
  double _thickness;
  set thickness(double value) {
    if (_thickness == value) return;
    _thickness = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final depth = metrics.dp(_thickness);
    size = constraints.constrain(Size3d(0.0, 0.0, depth));
    final panel = child;
    if (panel == null) return;
    final across = math.min(size.width, size.height) + metrics.dp(_strokeWidth);
    panel.layout(Constraints3d.tight(Size3d(across, across, depth)));
    panel.place(
      Offset3d(
        (size.width - across) / 2.0,
        (size.height - across) / 2.0,
        (size.depth - depth) / 2.0,
      ),
    );
  }
}

class _SceneRingFrame3d extends SingleChildLayout3dWidget {
  const _SceneRingFrame3d({
    required this.strokeWidth,
    required this.thickness,
    super.child,
  });

  final double strokeWidth;
  final double thickness;

  @override
  _RingFrame3d createLayout(BuildContext context) =>
      _RingFrame3d(strokeWidth: strokeWidth, thickness: thickness);

  @override
  void updateLayout(BuildContext context, _RingFrame3d layout) {
    layout
      ..strokeWidth = strokeWidth
      ..thickness = thickness;
  }
}

/// The ring itself: a panel that writes its own border and its own turn.
///
/// A `DecoratedBox3d` rather than a widget-built one because both are
/// written every frame of an indeterminate arc — the arc's length into the
/// border's gradient, which is a shader parameter, and its start into the
/// node transform, which is a matrix — and a widget would have to be rebuilt
/// to do either. Neither lays anything out.
class _RingPanel3d extends DecoratedBox3d {
  _RingPanel3d({
    required BoxDecoration3d base,
    required Color color,
    required Color? track,
    required double strokeWidth,
    required double? value,
    required Animation<double>? animation,
  }) : _base = base,
       _color = color,
       _track = track,
       _strokeWidth = strokeWidth,
       _value = value,
       _animation = animation,
       super(decoration: base, name: 'CircularProgressIndicator3d ring') {
    animation?.addListener(_apply);
  }

  /// The panel's decoration, before the border is written onto it.
  BoxDecoration3d _base;
  set base(BoxDecoration3d value) {
    if (_base == value) return;
    _base = value;
    _apply();
  }

  Color _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    _apply();
  }

  Color? _track;
  set track(Color? value) {
    if (_track == value) return;
    _track = value;
    _apply();
  }

  /// In logical pixels, as a border is.
  double _strokeWidth;
  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    _strokeWidth = value;
    _apply();
  }

  double? _value;
  set value(double? value) {
    if (_value == value) return;
    _value = value;
    _apply();
  }

  Animation<double>? _animation;
  set animation(Animation<double>? value) {
    if (identical(_animation, value)) return;
    _animation?.removeListener(_apply);
    _animation = value?..addListener(_apply);
    _apply();
  }

  @override
  void performLayout() {
    super.performLayout();
    _apply();
  }

  void _apply() {
    if (!hasSize) return;
    final double start;
    final double sweep;
    final animation = _animation;
    final stroke = metrics.dp(_strokeWidth);
    if (_value == null && animation != null) {
      final (flutterStart, flutterSweep) =
          CircularProgressIndicator3d.indeterminateArcAt(animation.value);
      // Flutter's indeterminate arc has square caps, which reach half a
      // stroke past each end. On a circle that is nearly an arc half a
      // stroke longer at each end, measured along the stroke's centre.
      final radius = (size.width - stroke) / 2.0;
      final cap = radius > 0.0 ? stroke / 2.0 / radius : 0.0;
      start = flutterStart - cap;
      sweep = flutterSweep + 2.0 * cap;
    } else {
      start = -math.pi / 2.0;
      sweep = (_value ?? 0.0) * 2.0 * math.pi;
    }

    final fraction = (sweep / (2.0 * math.pi)).clamp(0.0, 1.0);
    final rest = _track ?? _color.withValues(alpha: 0.0);
    decoration = _base.copyWith(
      border: Border3d(
        width: _strokeWidth,
        // From three o'clock, clockwise: the arc, a hard stop, then the
        // track or nothing. An empty arc is all track, rather than a ramp
        // whose first stop could catch a pixel on the three o'clock line.
        gradient: SweepGradient(
          colors: fraction <= 0.0
              ? <Color>[rest, rest]
              : <Color>[_color, _color, rest, rest],
          stops: fraction <= 0.0
              ? const <double>[0.0, 1.0]
              : <double>[0.0, fraction, fraction, 1.0],
        ),
      ),
    );

    // Turned about its own centre, which is the circle's: the sweep's zero
    // lands wherever the arc should start.
    final centre = size.width / 2.0;
    nodeTransform = Matrix4.translationValues(centre, centre, 0.0)
      ..rotateZ(start)
      ..translateByDouble(-centre, -centre, 0.0, 1.0);
  }

  @override
  void dispose() {
    _animation?.removeListener(_apply);
    super.dispose();
  }
}

/// A leaf as far as the widget layer knows: the panel draws everything it
/// needs itself.
class _SceneRingPanel3d extends Layout3dWidget {
  const _SceneRingPanel3d({
    required this.base,
    required this.color,
    required this.track,
    required this.strokeWidth,
    required this.value,
    required this.animation,
  });

  final BoxDecoration3d base;
  final Color color;
  final Color? track;
  final double strokeWidth;
  final double? value;
  final Animation<double>? animation;

  @override
  _RingPanel3d createLayout(BuildContext context) => _RingPanel3d(
    base: base,
    color: color,
    track: track,
    strokeWidth: strokeWidth,
    value: value,
    animation: animation,
  );

  @override
  void updateLayout(BuildContext context, _RingPanel3d layout) {
    layout
      ..base = base
      ..color = color
      ..track = track
      ..strokeWidth = strokeWidth
      ..value = value
      ..animation = animation;
  }
}
