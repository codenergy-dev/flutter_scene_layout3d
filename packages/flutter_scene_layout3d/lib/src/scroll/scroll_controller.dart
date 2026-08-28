import 'dart:async' show Completer;
import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/physics.dart' show Simulation, Tolerance;
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;

import '../metrics.dart';
import 'scroll_physics.dart';

/// Which way a scroll position is currently moving, under a finger or a
/// simulation.
///
/// Flutter's `ScrollDirection`, with Flutter's slightly counter-intuitive
/// naming kept because everything written against that framework already
/// reads it this way: [forward] is the *content* moving forward, which is the
/// offset getting **smaller** — a viewer dragging a list downward to see what
/// is above. [reverse] is the offset growing.
enum ScrollDirection3d {
  /// Nothing is moving the position.
  idle,

  /// The offset is decreasing: the content is moving toward the end of the
  /// window, which is a drag back toward the start of the list.
  forward,

  /// The offset is increasing: the content is moving toward the start of the
  /// window, which is a drag further into the list.
  reverse,
}

/// The scroll offset of a [Viewport3d] or [ListView3d], the metrics the view
/// reports back, and the animation and physics over both.
///
/// Still deliberately thin about *input*: in a 3D scene the gesture that
/// drives scrolling is the application's to choose (a drag on the
/// `SceneView`, a raycast, a controller stick), so there is no equivalent of
/// Flutter's `ScrollDragController` here — [Layout3dPointer] drives this
/// object through [beginUserScroll], [applyUserOffset] and [endUserScroll],
/// and so can anything else.
///
/// What it is *not* thin about, since the input question does not touch them:
///
///  * **Physics.** [physics] decides what the ends feel like and what a
///    release does with its velocity. [ClampingScroll3dPhysics] by default.
///  * **Animation.** [animateTo], [fling] and [ensureVisible3d] all run a
///    simulation on a [Ticker]. Every menu, every focus traversal and every
///    "scroll to top" needs that, and none of them is a gesture.
///
/// ## Where the ticker comes from
///
/// A controller is a plain [ChangeNotifier] with no element behind it, so it
/// has nothing to get a [TickerProvider] from. Give it one — [vsync], set on
/// the constructor or later, or passed to the individual call — whenever
/// there is a `State` in the picture, so that `TickerMode` can mute the
/// animation with the route it is on. Without one the controller makes a bare
/// [Ticker], which schedules through the same [SchedulerBinding] and works
/// perfectly well; it simply cannot be muted from outside.
class Scroll3dController extends ChangeNotifier {
  /// Creates a controller starting at [initialOffset].
  Scroll3dController({
    double initialOffset = 0.0,
    Scroll3dPhysics physics = const ClampingScroll3dPhysics(),
    this.vsync,
  }) : _offset = initialOffset,
       _physics = physics;

  /// The ticker provider [animateTo] and [fling] use when they are not given
  /// one.
  ///
  /// Null means a bare [Ticker]; see the class docs.
  TickerProvider? vsync;

  Scroll3dPhysics _physics;

  /// What the ends feel like, and what a release does.
  Scroll3dPhysics get physics => _physics;

  set physics(Scroll3dPhysics value) {
    if (identical(_physics, value)) return;
    _physics = value;
  }

  double _offset;

  /// How far the content is scrolled, in layout units along the view's axis.
  ///
  /// Zero shows the start of the content; larger values move the content
  /// toward the low face (up, for a vertical list), the same sense as
  /// Flutter's scroll offsets.
  ///
  /// Assigning goes through [Scroll3dPhysics.applyBoundaryConditions], so
  /// under the default clamping physics this is the scrollable range and
  /// under a bouncing one it is not.
  double get offset => _offset;

  set offset(double value) {
    _setOffset(value);
  }

  /// Moves to [value], refusing whatever the physics refuses, and answers how
  /// much was refused.
  double _setOffset(double value) {
    final overscroll = _physics.applyBoundaryConditions(this, value);
    final applied = value - overscroll;
    if (applied == _offset) return overscroll;
    _updateUserScrollDirection(applied - _offset);
    _offset = applied;
    notifyListeners();
    return overscroll;
  }

  /// The smallest useful [offset], which is always zero here.
  ///
  /// Present because the physics is written against a range rather than
  /// against zero, and because a scroll view with a leading edge somewhere
  /// else (a centred sliver list) is the obvious extension.
  double get minScrollExtent => 0.0;

  double _maxScrollExtent = 0.0;

  /// The largest useful [offset], set by the view during layout.
  double get maxScrollExtent => _maxScrollExtent;

  double _viewportExtent = 0.0;

  /// The extent of the scrolling window along its axis, set by the view.
  double get viewportExtent => _viewportExtent;

  double _contentExtent = 0.0;

  /// The extent of the content along the view's axis.
  ///
  /// Reported by the view, because the scroll range alone cannot tell:
  /// content shorter than the window has nowhere to scroll, so
  /// [maxScrollExtent] is zero either way.
  double get contentExtent => _contentExtent;

  double _unitsPerLogicalPixel = Layout3dMetrics.defaultUnitsPerLogicalPixel;

  /// The unit contract the view holding this position was laid out under.
  ///
  /// Recorded by the view, and read by [physics]: Flutter's fling and spring
  /// curves are tuned in logical pixels, so a simulation has to know what a
  /// layout unit is worth before it can run. See [Scroll3dPhysics].
  double get unitsPerLogicalPixel => _unitsPerLogicalPixel;

  /// Whether the content is longer than the window.
  bool get canScroll => _maxScrollExtent > 0.0;

  /// Whether the position is outside the range the content allows.
  ///
  /// Only a physics that permits it can get here; the default cannot.
  bool get outOfRange =>
      _offset < minScrollExtent || _offset > _maxScrollExtent;

  /// How far past an end the position is, negative before the start and
  /// positive past the end, zero in between.
  ///
  /// The number an overscroll effect is driven from. In a scene that need not
  /// be a glow: bend, tilt or compress the content instead, on the node-only
  /// path, and it costs no layout at all.
  double get overscroll {
    if (_offset < minScrollExtent) return _offset - minScrollExtent;
    if (_offset > _maxScrollExtent) return _offset - _maxScrollExtent;
    return 0.0;
  }

  ScrollDirection3d _userScrollDirection = ScrollDirection3d.idle;

  /// Which way the position last moved, or [ScrollDirection3d.idle] when
  /// nothing is moving it.
  ///
  /// Read by [SliverPersistentHeader3d]: a floating header comes back when
  /// the viewer scrolls forward, and should *not* come back because a
  /// bouncing fling overshot the end and the spring is carrying the offset
  /// backwards on its own. Idle while a programmatic [jumpTo] or
  /// [animateTo] moves the position, since neither is the viewer scrolling.
  ScrollDirection3d get userScrollDirection => _userScrollDirection;

  bool _dragging = false;

  /// Whether a pointer is holding this position.
  bool get isDragging => _dragging;

  void _updateUserScrollDirection(double delta) {
    if (!_dragging && !_ballistic) return;
    if (delta == 0.0) return;
    _userScrollDirection = delta < 0.0
        ? ScrollDirection3d.forward
        : ScrollDirection3d.reverse;
  }

  /// Jumps to [value], subject to the physics' boundary conditions.
  void jumpTo(double value) => offset = value;

  /// Moves by [delta], subject to the physics' boundary conditions.
  void jumpBy(double delta) => offset = _offset + delta;

  /// Shifts the position by [correction] without clamping and without
  /// notifying, the 3D analogue of [ScrollPosition.correctBy].
  ///
  /// For a viewport applying a [SliverGeometry3d.scrollOffsetCorrection] in
  /// the middle of its own layout: a sliver has discovered that the content
  /// is not where this offset assumed, and the layout is about to be redone
  /// from the corrected position. Nobody is told, because nothing has moved
  /// as far as the outside world is concerned.
  void correctBy(double correction) {
    _offset += correction;
  }

  /// Records the metrics measured during layout, applying the physics'
  /// boundary conditions to [offset] in the new range.
  ///
  /// Called by the view; a change here notifies listeners so a host can
  /// react, but the view has already used the settled value for this pass.
  void applyViewportMetrics({
    required double maxScrollExtent,
    required double viewportExtent,
    double? contentExtent,
    double? unitsPerLogicalPixel,
  }) {
    final clampedMax = math.max(0.0, maxScrollExtent);
    _maxScrollExtent = clampedMax;
    _viewportExtent = viewportExtent;
    _contentExtent = contentExtent ?? clampedMax + viewportExtent;
    if (unitsPerLogicalPixel != null) {
      _unitsPerLogicalPixel = unitsPerLogicalPixel;
    }
    // A physics that cannot overscroll snaps: a list that just got shorter
    // has to show its end this frame, not spring toward it over the next
    // several. One that can overscroll keeps the position and settles it
    // below.
    final settled = _physics.allowsOverscroll
        ? _offset
        : _offset.clamp(minScrollExtent, clampedMax);
    final offsetChanged = settled != _offset;
    _offset = settled;
    // Only a moved position is worth waking listeners for; the metrics
    // themselves are recorded silently, because this runs during layout.
    if (offsetChanged) notifyListeners();
    // A physics that allows overscroll can be left outside the range by a
    // list that got shorter, with nothing running to bring it back. Settle it
    // — unless something already is, in which case that simulation was built
    // for the range it will discover on the next frame anyway.
    if (outOfRange && !_dragging && !isAnimating) {
      _startSimulation(_physics.createBallisticSimulation(this, 0.0));
    }
  }

  // ------------------------------------------------------------ user input

  /// Takes hold of the position for a drag, stopping anything that was
  /// animating it.
  ///
  /// Called by [Layout3dPointer] when a press grabs a scrolling view.
  void beginUserScroll() {
    stopAnimation();
    _dragging = true;
  }

  /// Moves the position by [delta] layout units of finger travel.
  ///
  /// The drag path, and the only one that goes through
  /// [Scroll3dPhysics.applyPhysicsToUserOffset]: a bouncing physics damps a
  /// drag that is already past an end, so the content lags the finger further
  /// and further out.
  void applyUserOffset(double delta) {
    if (delta == 0.0) return;
    _setOffset(_offset + _physics.applyPhysicsToUserOffset(this, delta));
  }

  /// Releases the position at [velocity] layout units per second, letting the
  /// physics carry it on.
  ///
  /// A velocity of zero still runs a simulation when the position is out of
  /// range, which is how a bouncing overscroll springs back from a release
  /// that was not a fling.
  void endUserScroll({double velocity = 0.0}) {
    _dragging = false;
    final simulation = _physics.createBallisticSimulation(this, velocity);
    if (simulation == null) {
      _userScrollDirection = ScrollDirection3d.idle;
      return;
    }
    _startSimulation(simulation);
  }

  // ------------------------------------------------------------- animation

  Ticker? _ticker;
  Simulation? _simulation;
  Completer<void>? _completer;
  bool _ballistic = false;

  /// Whether a simulation is currently moving the position.
  bool get isAnimating => _ticker != null;

  /// Animates to [to] over [duration], subject to the physics' boundary
  /// conditions.
  ///
  /// The imperative half of scrolling, and the reason this class has a ticker
  /// at all. A second call interrupts the first: the running simulation is
  /// dropped, the new one starts from wherever the position had got to, and
  /// the interrupted future completes rather than hanging.
  ///
  /// A zero [duration] is a [jumpTo], and answers an already-complete future.
  Future<void> animateTo(
    double to, {
    required Duration duration,
    Curve curve = Curves.easeInOut,
    TickerProvider? vsync,
  }) {
    assert(!duration.isNegative);
    if (duration == Duration.zero) {
      stopAnimation();
      jumpTo(to);
      return Future<void>.value();
    }
    final target = _targetWithin(to);
    if (target == _offset) {
      stopAnimation();
      return Future<void>.value();
    }
    return _run(
      _CurvedSimulation(
        begin: _offset,
        end: target,
        duration: duration,
        curve: curve,
      ),
      vsync: vsync,
      ballistic: false,
    );
  }

  /// Throws the position at [velocity] layout units per second and lets the
  /// physics decelerate it.
  ///
  /// What a release does, and what a "flick to top" button does. Returns a
  /// future that completes when the motion stops.
  Future<void> fling(double velocity, {TickerProvider? vsync}) {
    final simulation = _physics.createBallisticSimulation(this, velocity);
    if (simulation == null) {
      stopAnimation();
      return Future<void>.value();
    }
    return _run(simulation, vsync: vsync, ballistic: true);
  }

  /// Stops whatever is animating the position, leaving it where it is.
  ///
  /// The future the interrupted call returned completes; nothing is thrown,
  /// because an interrupted scroll is an ordinary event and not an error.
  void stopAnimation() {
    final ticker = _ticker;
    _ticker = null;
    _simulation = null;
    _ballistic = false;
    ticker
      ?..stop(canceled: true)
      ..dispose();
    if (!_dragging) _userScrollDirection = ScrollDirection3d.idle;
    final completer = _completer;
    _completer = null;
    completer?.complete();
  }

  /// Where a target offset would actually land, given the physics.
  double _targetWithin(double value) =>
      value - _physics.applyBoundaryConditions(this, value);

  void _startSimulation(Simulation? simulation) {
    if (simulation == null) return;
    _run(simulation, vsync: null, ballistic: true);
  }

  Future<void> _run(
    Simulation simulation, {
    required TickerProvider? vsync,
    required bool ballistic,
  }) {
    stopAnimation();
    _simulation = simulation;
    _ballistic = ballistic;
    final completer = _completer = Completer<void>();
    final provider = vsync ?? this.vsync;
    final ticker = _ticker = provider == null
        ? Ticker(_tick, debugLabel: 'Scroll3dController')
        : provider.createTicker(_tick);
    ticker.start();
    return completer.future;
  }

  void _tick(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return;
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final refused = _setOffset(simulation.x(t));
    // Two ways to stop: the simulation says it is finished, or it walked into
    // a wall the physics would not let it through. The second is what ends a
    // clamping fling at the end of the list, since the friction curve itself
    // keeps going well past it.
    if (simulation.isDone(t) || refused != 0.0) stopAnimation();
  }

  @override
  void dispose() {
    stopAnimation();
    super.dispose();
  }
}

/// A curve between two offsets, as a [Simulation], so that [animateTo] and a
/// ballistic fling share one driver.
class _CurvedSimulation extends Simulation {
  _CurvedSimulation({
    required this.begin,
    required this.end,
    required this.duration,
    required this.curve,
  }) : _seconds = duration.inMicroseconds / Duration.microsecondsPerSecond,
       super(tolerance: Tolerance.defaultTolerance);

  final double begin;
  final double end;
  final Duration duration;
  final Curve curve;
  final double _seconds;

  @override
  double x(double time) {
    final t = (time / _seconds).clamp(0.0, 1.0);
    if (t == 1.0) return end;
    return begin + (end - begin) * curve.transform(t);
  }

  @override
  double dx(double time) {
    const epsilon = 1e-4;
    return (x(time + epsilon) - x(time - epsilon)) / (2 * epsilon);
  }

  @override
  bool isDone(double time) => time >= _seconds;
}
