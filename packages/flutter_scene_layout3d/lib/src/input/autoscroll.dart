import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;

import '../scroll/scrollable.dart';
import 'drag.dart';

/// How far into the edge of a scrolling view a drag has to be, and how fast
/// the view moves when it is there.
///
/// Both distances are in logical pixels, taken through
/// [Layout3dMetrics.dp] against the metrics of the view the drag is over, so
/// one setting reads the same on a panel laid out at any scale. Fifty dp is
/// the Material figure and the reason the default is stated in dp rather than
/// in world units.
///
/// ```dart
/// ReorderableList3d(
///   autoscroll: const Drag3dAutoscroll(edgeExtent: 72, maxVelocity: 600),
///   // ...
/// )
/// ```
class Drag3dAutoscroll {
  /// Creates a set of autoscroll settings.
  const Drag3dAutoscroll({
    this.edgeExtent = 50.0,
    this.minVelocity = 60.0,
    this.maxVelocity = 1000.0,
  }) : assert(edgeExtent >= 0.0),
       assert(minVelocity >= 0.0),
       assert(maxVelocity >= minVelocity);

  /// How deep the band at each end of the window is, in logical pixels.
  ///
  /// A drag inside it scrolls the view; a drag outside it does not. Zero
  /// switches autoscroll off entirely, which is what [isEnabled] reports.
  final double edgeExtent;

  /// How fast the view moves at the outer edge of the band, in dp per second.
  ///
  /// Not zero, deliberately: a ramp that starts at nothing means a finger
  /// resting just inside the band appears to do nothing at all, and the
  /// viewer cannot tell "not scrolling yet" from "not scrolling ever".
  final double minVelocity;

  /// How fast the view moves at the very edge of the window, in dp per
  /// second, and beyond it.
  final double maxVelocity;

  /// Whether these settings can move anything.
  bool get isEnabled => edgeExtent > 0.0 && maxVelocity > 0.0;

  /// The speed, in dp per second, for a drag [t] of the way through the band.
  ///
  /// `t` is zero at the inner edge of the band and one at the window's edge;
  /// past the window it stays one, so a finger dragged clean off the end of a
  /// list scrolls at [maxVelocity] rather than at some extrapolated speed.
  double velocityAt(double t) =>
      minVelocity + (maxVelocity - minVelocity) * t.clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is Drag3dAutoscroll &&
      other.edgeExtent == edgeExtent &&
      other.minVelocity == minVelocity &&
      other.maxVelocity == maxVelocity;

  @override
  int get hashCode => Object.hash(edgeExtent, minVelocity, maxVelocity);

  @override
  String toString() =>
      'Drag3dAutoscroll(edge: ${edgeExtent}dp, '
      '$minVelocity-$maxVelocity dp/s)';
}

/// Moves the scrolling view a drag is held at the edge of.
///
/// A finger parked at the bottom of a list sends no move events, so nothing
/// on the pointer stream can carry a drag past the end of the window. This is
/// the piece that can: a [Ticker], a band at each end of the nearest
/// [Scrollable3d] on the drag's own path, and a velocity that ramps with how
/// far into that band the drag is.
///
/// ## What a tick does, and in what order
///
/// 1. Moves the view by `velocity * dt`, through [Scroll3dController.jumpBy]
///    and clamped to the scroll range by hand. *Not* `applyUserOffset`: an
///    autoscroll is not the viewer scrolling, so it must not bounce past the
///    end and must not fling when the drag is released. The clamp is by hand
///    rather than left to the physics because a bouncing physics permits
///    overscroll, and a drag held at the edge would then drift off the end of
///    the content for as long as the viewer held it.
/// 2. Re-resolves the drag through [Drag3dSession.tick]. This is the detail
///    that is easy to miss and expensive to find: **the window moved under a
///    stationary pointer, so the drop target — or, in a reorderable list, the
///    insert index — has changed with no pointer event to notice it.**
/// 3. Re-reads the band, because the view may have reached its end, in which
///    case the ticker stops.
///
/// Nothing here is laid out. The scroll is one offset write and the view
/// relayouts on its own schedule; the drag's own feedback is still one matrix
/// write a frame.
///
/// ## Where the tick's answer comes from
///
/// [Drag3dSession.tick] goes through [Drag3dSession.pathResolver] when one is
/// installed, which is how a drag on a [Layout3dPointerGroup] gets the
/// group's cross-surface walk rather than one surface's answer, and falls
/// back to [Drag3dSession.refresh] — the last path, re-read — when there is
/// none. Either is enough for the case that matters, because a reorderable
/// list reads its insert index in *scroll* coordinates: the ray has not
/// moved, the list's own frame has not moved, and the scroll offset added to
/// the local position has. The index follows the window without a new hit
/// test at all.
///
/// ## Owning one
///
/// [Draggable3d] makes one when its `autoscroll` settings are enabled and
/// disposes it with the drag. Making one by hand is how a host with a drag
/// source of its own gets the same behaviour:
///
/// ```dart
/// final scroller = Drag3dAutoscroller(session: session, vsync: this);
/// // ... on every pointer move:
/// scroller.update();
/// ```
///
/// It registers a [Drag3dSession.addEndListener] of its own, so a session
/// that ends by any route takes the ticker with it and there is nothing to
/// unregister.
class Drag3dAutoscroller {
  /// Creates an autoscroller for [session].
  Drag3dAutoscroller({
    required this.session,
    this.settings = const Drag3dAutoscroll(),
    this.vsync,
  }) {
    session
      ..addResolveListener(update)
      ..addEndListener(dispose);
  }

  /// The drag whose position decides whether anything scrolls.
  final Drag3dSession session;

  /// How deep the band is and how fast the view moves in it.
  Drag3dAutoscroll settings;

  /// The ticker provider for the scroll.
  ///
  /// Null means a bare [Ticker], which schedules through the same
  /// [SchedulerBinding] and works outside a `State`. Give one where there is
  /// a `State` in the picture so that `TickerMode` can mute it.
  TickerProvider? vsync;

  Ticker? _ticker;
  Duration? _lastElapsed;
  Scrollable3d? _view;
  double _velocity = 0.0;
  bool _disposed = false;

  /// The view being scrolled, or null when nothing is.
  Scrollable3d? get scrollable => _view;

  /// Whether a view is being moved right now.
  bool get isScrolling => _view != null;

  /// How fast the view is moving, in world units per second along its scroll
  /// axis, signed the way [Scroll3dController.offset] runs.
  double get velocity => _view == null ? 0.0 : _velocity;

  /// Re-reads where the drag is and starts or stops the scroll.
  ///
  /// Called for you: the constructor registers it as a
  /// [Drag3dSession.addResolveListener], so every resolution of the drag —
  /// every move, and every tick of this autoscroller — asks the question
  /// again. Call it by hand only after changing [settings] mid-drag.
  ///
  /// It is cheap when nothing is happening: one walk of the hit path, no
  /// allocation, no ticker. That is what makes it affordable to ask on every
  /// move rather than keeping a ticker running for the whole drag — which
  /// would also mean a drag never settles, and `pumpAndSettle` never returns.
  void update() {
    if (_disposed) return;
    if (!session.isActive || !settings.isEnabled) {
      stop();
      return;
    }
    final measured = _measure();
    if (measured == null) {
      stop();
      return;
    }
    _view = measured.view;
    _velocity = measured.velocity;
    final running = _ticker;
    if (running != null && running.isActive) return;
    // Whatever was carrying the view — a fling the pick-up did not stop, an
    // `animateTo` — is not what the finger is asking for now.
    measured.view.controller.stopAnimation();
    _lastElapsed = null;
    final ticker = _ticker ??= vsync == null
        ? Ticker(_tick, debugLabel: 'Drag3dAutoscroller')
        : vsync!.createTicker(_tick);
    ticker.start();
  }

  /// Stops the scroll, leaving the autoscroller able to start again.
  void stop() {
    _view = null;
    _velocity = 0.0;
    _lastElapsed = null;
    final ticker = _ticker;
    if (ticker != null && ticker.isActive) ticker.stop(canceled: true);
  }

  /// Stops the scroll and gives up the ticker.
  ///
  /// Called for you when the session ends, whatever ended it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    final ticker = _ticker;
    _ticker = null;
    ticker?.dispose();
  }

  void _tick(Duration elapsed) {
    final view = _view;
    if (_disposed || view == null || !session.isActive) {
      stop();
      return;
    }
    final last = _lastElapsed;
    _lastElapsed = elapsed;
    // A ticker started inside a frame takes that frame's timestamp as its
    // start, so the first callback reports however long the frame had already
    // been running rather than zero. Scrolling by that would be a visible
    // jump at the moment the finger crossed into the band; the first tick is
    // therefore the clock's zero and moves nothing.
    if (last != null) {
      final seconds =
          (elapsed - last).inMicroseconds / Duration.microsecondsPerSecond;
      if (seconds > 0.0) {
        final controller = view.controller;
        final target = (controller.offset + _velocity * seconds).clamp(
          controller.minScrollExtent,
          controller.maxScrollExtent,
        );
        controller.jumpBy(target - controller.offset);
      }
    }
    // The window moved and the pointer did not: whatever the drag is over is
    // a question with a new answer, and nothing else is going to ask it.
    // ...which calls [update] back through the session's resolve listeners,
    // so the view reaching its end, or the drag having been carried out of
    // the band by the scroll itself, stops the ticker without a second look.
    session.tick();
  }

  _Drag3dEdge? _measure() {
    final entry = session.lastHit.entryOf<Scrollable3d>();
    if (entry == null) return null;
    final view = entry.layout as Scrollable3d;
    final controller = view.controller;
    if (!controller.canScroll) return null;
    final extent = controller.viewportExtent;
    if (extent <= 0.0) return null;
    final metrics = entry.layout.metrics;
    final band = metrics.dp(settings.edgeExtent);
    // A band deeper than half the window would have the two ends overlap, and
    // whichever was tested first would win a fight the viewer cannot see.
    if (band <= 0.0 || band * 2.0 > extent) return null;
    final along = entry.localPosition.alongAxis(view.scrollAxis);
    final double t;
    final double sign;
    if (along < band) {
      t = (band - along) / band;
      sign = -1.0;
    } else if (along > extent - band) {
      t = (along - (extent - band)) / band;
      sign = 1.0;
    } else {
      return null;
    }
    // In world units a second: the settings are in dp, the offset is not.
    final velocity =
        sign * settings.velocityAt(t) * metrics.unitsPerLogicalPixel;
    if (velocity < 0.0 && controller.offset <= controller.minScrollExtent) {
      return null;
    }
    if (velocity > 0.0 && controller.offset >= controller.maxScrollExtent) {
      return null;
    }
    return _Drag3dEdge(view, velocity);
  }

  @override
  String toString() => _view == null
      ? 'Drag3dAutoscroller(idle)'
      : 'Drag3dAutoscroller($_velocity units/s)';
}

class _Drag3dEdge {
  const _Drag3dEdge(this.view, this.velocity);

  final Scrollable3d view;
  final double velocity;
}
