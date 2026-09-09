import 'dart:ui' show Color;

import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;
import 'package:flutter/widgets.dart' show BuildContext, InheritedWidget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        DecoratedBox3d,
        Layout3d,
        Layout3dAnchoring,
        Offset3d,
        Ripple3d,
        StateLayer3d;

import '../tokens/state_layer.dart';
import 'ink_ripple.dart';

/// The seam a hover, a focus or a press reaches a [Material3d] through,
/// **without rebuilding anything**.
///
/// This is the load-bearing class of the interaction layer, and the reason it
/// exists is the animation tier. `DecoratedBox3d.stateLayer` is a setter that
/// writes one shader uniform and asks for a repaint; it never calls
/// `markNeedsLayout` and never marks a widget dirty. An `InkWell3d` that
/// answered a hover with `setState` would throw all of that away — a pointer
/// crossing a list of twenty tiles would rebuild twenty subtrees and relay
/// out each of them — so the ink does not travel through the widget tree at
/// all. The surface publishes a controller once, at build time; an interactive
/// widget looks it up once, in `didChangeDependencies`; and every state change
/// afterwards is a method call that ends in one field assignment on a box.
///
/// Flutter reaches the same arrangement from the other side, with
/// `MaterialInkController` and an ink feature that paints itself. The
/// constraint here is the tier, not the spelling.
///
/// A component reads [states] to resolve its own tokens — a filled button is a
/// different colour when pressed, not merely washed — but reading it does not
/// subscribe to it. Anything that has to *rebuild* on a state change is a
/// state a component must hold itself; this channel is for the wash.
abstract class InkController3d {
  /// The states in force, as a value that must not be mutated.
  Set<Material3dState> get states;

  /// Whether [state] is in force.
  bool isIn(Material3dState state) => states.contains(state);

  /// Adds or removes [state] and writes the resulting wash.
  ///
  /// Cheap and idempotent: a state that is already in the set writes nothing
  /// at all, which matters because a pointer moving inside a box produces a
  /// hover event per frame.
  void setInkState(Material3dState state, {required bool active});

  /// Drops every state, for a control that has just been disabled or has lost
  /// the pointer and the focus at once.
  ///
  /// A ripple in flight is dropped with them rather than faded: a control that
  /// has gone disabled or left the tree has nothing left to ripple on.
  void clearInkStates();

  /// Notes where a press landed, so the ripple that may follow knows where to
  /// start.
  ///
  /// [point] is in [source]'s own frame and in **world units**, which is
  /// exactly what `PointerEvent3d.localPosition` reports — the box that
  /// recognizes a press and the box that draws the wash are never the same
  /// box, so the controller does the change of frame with
  /// `Layout3d.localPointFrom`.
  ///
  /// Call it on the pointer *down*. The ripple itself does not start until the
  /// press is reported, which is later and arena-resolved; a point noted for a
  /// press that never happens is simply overwritten by the next one.
  void noteRipplePoint(Layout3d source, Offset3d point);

  /// The controller published by the nearest [Material3d] above [context], or
  /// null when there is none.
  ///
  /// The caller becomes a dependent, which costs nothing: a `Material3d`
  /// keeps one controller for its whole life, so the scope never notifies.
  static InkController3d? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<InkController3dScope>()
      ?.controller;

  /// The controller published by the nearest [Material3d] above [context].
  ///
  /// Asserts when there is none. An `InkWell3d` outside a `Material3d` is
  /// almost always a mistake — there is no surface for the wash to be drawn
  /// on — but it is a survivable one, so `InkWell3d` itself uses [maybeOf]
  /// and simply does not light anything up.
  static InkController3d of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'InkController3d.of() found no Material3d above this context. A wash '
      'is drawn by the panel underneath it, so an interactive component has '
      'to be built inside a Material3d; use maybeOf() when being outside is '
      'a legitimate state.',
    );
    return controller!;
  }
}

/// Publishes one [InkController3d] to the subtree a [Material3d] covers.
///
/// An ordinary inherited widget with a value that never changes, so
/// [updateShouldNotify] is all but always false and looking the controller up
/// subscribes a widget to nothing.
class InkController3dScope extends InheritedWidget {
  /// Publishes [controller] below.
  const InkController3dScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// The controller of the enclosing surface.
  final InkController3d controller;

  @override
  bool updateShouldNotify(InkController3dScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

/// The implementation a [Material3d] owns, and the only writer of a panel's
/// state layer.
///
/// Split out of the widget so the whole channel can be tested without a GPU,
/// a painter or a pointer: give it a box, set a state, read the box's layer.
class MutableInkController3d implements InkController3d {
  /// Creates a controller washing in [color] at [opacities].
  ///
  /// [vsync] is what makes the press ripple move. Without one the controller
  /// still works exactly as it did before there was a ripple — a press is the
  /// uniform press wash, arriving all at once — which is what keeps this class
  /// constructible in a test that has no ticker to give it, and what a caller
  /// that wants the plain wash passes. `Material3d` always supplies one.
  MutableInkController3d({
    required Color color,
    StateLayerOpacity3d opacities = StateLayerOpacity3d.baseline,
    TickerProvider? vsync,
    InkRipple3dStyle rippleStyle = InkRipple3dStyle.material,
  }) : _color = color,
       _opacities = opacities,
       _vsync = vsync,
       _rippleStyle = rippleStyle;

  final Set<Material3dState> _states = <Material3dState>{};
  DecoratedBox3d? _box;
  Color _color;
  StateLayerOpacity3d _opacities;

  final TickerProvider? _vsync;
  final InkRipple3dStyle _rippleStyle;
  Ticker? _ticker;
  InkRipple3dRun? _run;
  Offset3d? _pressPoint;

  /// The run's own clock, which is not the ticker's.
  ///
  /// The two part company on purpose: the ticker is *stopped* while a ripple
  /// sits at full radius under a held finger, so a button held down for a
  /// minute schedules no frames at all, and the minute is not counted. See
  /// [InkRipple3dRun.isSettledAt].
  Duration _elapsed = Duration.zero;
  Duration _base = Duration.zero;

  @override
  Set<Material3dState> get states => _states;

  @override
  bool isIn(Material3dState state) => _states.contains(state);

  /// The press ripple in flight, or null when none is.
  InkRipple3dRun? get ripple => _run;

  /// Whether this controller is currently asking for frames.
  ///
  /// False whenever nothing is moving, which includes a press being *held*
  /// after its ripple has finished growing.
  bool get isAnimating => _ticker?.isActive ?? false;

  /// The layer the current states resolve to.
  ///
  /// With no ripple in flight this is Material's rule and nothing else: one
  /// wash, at the strongest of the states in force.
  ///
  /// With one, the same figure is split in two. The uniform half is what the
  /// states *other than* the press resolve to, and the ripple carries what the
  /// press adds on top of it — `(press - rest) / (1 - rest)`, which is the
  /// alpha that composites to exactly the press figure over the wash already
  /// there. So a hovered control that is pressed still reads 8% outside the
  /// circle and 10% inside it, and never the 18% a sum would give.
  StateLayer3d get layer {
    final run = _run;
    if (run == null) return _opacities.resolve(_states, _color);

    final rest = <Material3dState>{..._states}..remove(Material3dState.pressed);
    final uniform = _opacities.forStates(rest);
    // The press counts toward the peak even after the finger has lifted:
    // what ends a ripple is its own fade, not the state leaving the set.
    final peak = _opacities.forStates(<Material3dState>{
      ...rest,
      Material3dState.pressed,
    });
    final over = uniform >= 1.0
        ? 0.0
        : ((peak - uniform) / (1.0 - uniform)).clamp(0.0, 1.0);

    return StateLayer3d(
      color: _color,
      opacity: uniform,
      ripple: Ripple3d(
        origin: run.origin,
        radius: run.radiusAt(_elapsed),
        opacity: over * run.opacityAt(_elapsed),
      ),
    );
  }

  /// The box this controller washes, or null before the first build.
  DecoratedBox3d? get box => _box;

  /// Points this controller at the box a [Material3d] just created or
  /// updated, and writes the current wash onto it.
  ///
  /// Called from the layout widget's `createLayout` and `updateLayout`, which
  /// is what keeps the box and the controller in step across a rebuild that
  /// replaces neither.
  void attach(DecoratedBox3d box) {
    _box = box;
    box.stateLayer = layer;
  }

  /// Forgets the box, when the [Material3d] that owned it is disposed.
  ///
  /// A ripple in flight goes with it: there is nothing left to write it onto,
  /// and a ticker still running would be asking for frames on behalf of a box
  /// that no longer exists.
  void detach() {
    _dropRipple();
    _box = null;
  }

  /// Re-resolves the wash against a new content colour or a new set of
  /// opacities, which is what a theme change looks like from here.
  ///
  /// Returns true when anything actually changed, so a caller can skip the
  /// write. A theme change also relayouts, so this is not on a hot path; it
  /// is here so that a rebuild with an equal theme writes nothing.
  bool restyle({required Color color, required StateLayerOpacity3d opacities}) {
    if (_color == color && _opacities == opacities) return false;
    _color = color;
    _opacities = opacities;
    _apply();
    return true;
  }

  @override
  void setInkState(Material3dState state, {required bool active}) {
    final changed = active ? _states.add(state) : _states.remove(state);
    if (!changed) return;
    if (state == Material3dState.pressed) {
      if (active) {
        _startRipple();
      } else {
        _releaseRipple();
      }
    }
    _apply();
  }

  @override
  void clearInkStates() {
    final hadRipple = _run != null;
    if (_states.isEmpty && !hadRipple) return;
    _states.clear();
    _dropRipple();
    _apply();
  }

  @override
  void noteRipplePoint(Layout3d source, Offset3d point) {
    _pressPoint = _box?.localPointFrom(source, point);
  }

  /// Stops the ticker and forgets the ripple, without disposing anything.
  ///
  /// Call it when the surface goes away; the controller is reusable
  /// afterwards, which [detach] and [attach] rely on.
  void dispose() {
    _dropRipple();
    final ticker = _ticker;
    _ticker = null;
    // stop() before dispose(): a Ticker with a live future asserts it is not
    // active when it is disposed, and a control taken out of the tree
    // mid-press has exactly that.
    ticker?.stop(canceled: true);
    ticker?.dispose();
  }

  void _startRipple() {
    final box = _box;
    final vsync = _vsync;
    if (box == null || vsync == null || !box.hasSize) return;
    final size = box.size;
    // A press with no noted point — a keyboard activation, a component driving
    // the controller directly — ripples from the middle of the surface.
    final origin =
        _pressPoint ?? Offset3d(size.width / 2.0, size.height / 2.0, 0.0);
    // A second press while the first is still fading replaces it. One box
    // carries one ripple, because one box carries one pair of uniforms, and
    // the finger that is down now is the one the user is looking at.
    _run = InkRipple3dRun.covering(
      size: size,
      origin: origin,
      // The peak is applied by [layer], because it depends on the other
      // states in force and those can change while the ripple runs.
      opacity: 1.0,
      style: _rippleStyle,
    );
    _elapsed = Duration.zero;
    _base = Duration.zero;
    _ticker?.stop();
    _ensureTicking();
  }

  void _releaseRipple() {
    final run = _run;
    if (run == null) return;
    run.release(_elapsed);
    _ensureTicking();
  }

  void _dropRipple() {
    if (_run == null) return;
    _run = null;
    _pressPoint = null;
    _ticker?.stop();
  }

  void _ensureTicking() {
    final vsync = _vsync;
    if (vsync == null) return;
    final ticker = _ticker ??= vsync.createTicker(_tick);
    if (!ticker.isActive) ticker.start();
  }

  void _tick(Duration tickerElapsed) {
    final run = _run;
    if (run == null) {
      _ticker?.stop();
      return;
    }
    _elapsed = _base + tickerElapsed;
    if (run.isDoneAt(_elapsed)) {
      _dropRipple();
    } else if (run.isSettledAt(_elapsed)) {
      // Nothing about the picture will change until the finger lifts, so hold
      // the clock where it is and stop asking for frames. This is the line
      // that keeps a held button off the per-frame path entirely.
      _base = _elapsed;
      _ticker?.stop();
    }
    _apply();
  }

  /// The one line the whole design is arranged around: a field assignment on
  /// a box, on the repaint-only tier, with nothing marked dirty anywhere.
  void _apply() => _box?.stateLayer = layer;

  @override
  String toString() =>
      'MutableInkController3d(${_states.isEmpty ? 'idle' : _states.join(', ')}'
      '${_run == null ? '' : ', rippling'})';
}
