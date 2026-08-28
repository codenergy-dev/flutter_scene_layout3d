import 'dart:math' as math;

import 'package:flutter/physics.dart'
    show ScrollSpringSimulation, Simulation, SpringDescription, Tolerance;
import 'package:flutter/widgets.dart'
    show BouncingScrollSimulation, ClampingScrollSimulation;

import 'scroll_controller.dart';

/// How a scroll position behaves at the edges, and what a release does with
/// the velocity it was let go at.
///
/// The 3D counterpart of `ScrollPhysics`, and deliberately a much smaller
/// object. Flutter's version is a chain of delegating instances that also
/// decides drag start distances, page snapping and whether an implicit scroll
/// is allowed; this one answers three questions and nothing else:
///
///  * [applyPhysicsToUserOffset] — what a drag of `delta` actually moves the
///    position by. The identity in the middle of the range; less than
///    `delta`, and shrinking, when a bouncing physics is already past an
///    edge.
///  * [applyBoundaryConditions] — how much of a proposed offset to refuse.
///    This is what makes a clamping physics stop dead at the end and a
///    bouncing one carry on past it.
///  * [createBallisticSimulation] — the motion after the finger leaves, from
///    a release velocity. Null means "there is nothing left to do", which is
///    a release at rest in the middle of the range.
///
/// ## Units
///
/// Everything this package measures is in layout units, and everything
/// Flutter's simulations are *tuned* in is logical pixels: a friction curve
/// copied from Android and a spring with a stiffness of 100 both assume
/// numbers of the size a screen produces. A world unit is a hundred logical
/// pixels by default, so handing a simulation raw layout units would give a
/// fling a thirtieth of its proper duration.
///
/// So the conversion happens here. The arguments and the values a simulation
/// produces are layout units; inside, the numbers are taken through the
/// tree's [Layout3dMetrics] — recorded on the controller by the view that
/// laid it out — into logical pixels, the Flutter simulation runs there, and
/// the result is scaled back. A fling therefore feels like a fling at any
/// unit contract, and a panel authored at ten times the scale does not fling
/// ten times as far.
abstract class Scroll3dPhysics {
  /// Creates a physics.
  const Scroll3dPhysics();

  /// How close to the end of a simulation counts as arrived, in logical
  /// pixels per second and logical pixels.
  Tolerance get tolerance => Tolerance.defaultTolerance;

  /// The spring a position out of range is pulled back with.
  static final SpringDescription defaultSpring =
      SpringDescription.withDampingRatio(
        mass: 0.5,
        stiffness: 100.0,
        ratio: 1.1,
      );

  /// What a user drag of [delta] layout units should actually move the
  /// position by.
  ///
  /// The identity, unless the position is already outside the range and this
  /// physics allows that.
  double applyPhysicsToUserOffset(Scroll3dController position, double delta) =>
      delta;

  /// Whether this physics lets the position leave the range the content
  /// allows.
  ///
  /// False for a clamping physics, and that is what lets a view snap a stale
  /// offset back into range the instant it measures a shorter content, rather
  /// than springing it back over the following frames.
  bool get allowsOverscroll => false;

  /// How much of a move to [value] to refuse, in layout units.
  ///
  /// Zero means the whole move is allowed. The convention is Flutter's: the
  /// return value is the *overscroll*, and the caller applies
  /// `value - applyBoundaryConditions(position, value)`.
  double applyBoundaryConditions(Scroll3dController position, double value) =>
      0.0;

  /// The motion that carries on after the pointer is released at [velocity]
  /// layout units per second, or null when there is none.
  Simulation? createBallisticSimulation(
    Scroll3dController position,
    double velocity,
  );

  /// Wraps a simulation stated in logical pixels so it reads out in layout
  /// units.
  ///
  /// The seam described in the class docs. Subclasses building on Flutter's
  /// simulations should go through this rather than feeding them layout
  /// units.
  static Simulation scaled(
    Simulation simulation,
    double unitsPerLogicalPixel,
  ) => _ScaledSimulation(simulation, unitsPerLogicalPixel);
}

/// A simulation in logical pixels, read out in layout units.
class _ScaledSimulation extends Simulation {
  _ScaledSimulation(this._inner, this._scale)
    : super(tolerance: _inner.tolerance);

  final Simulation _inner;
  final double _scale;

  @override
  double x(double time) => _inner.x(time) * _scale;

  @override
  double dx(double time) => _inner.dx(time) * _scale;

  @override
  bool isDone(double time) => _inner.isDone(time);

  @override
  String toString() => '${_inner.runtimeType} scaled by $_scale';
}

/// A scroll position that stops dead at the ends, the Android feel and this
/// package's default.
///
/// A drag past the end moves nothing, and a fling that reaches the end stops
/// there. There is no glow, because nothing here paints; a component library
/// that wants to show the edge has been reached should watch
/// [Scroll3dController.offset] settling against
/// [Scroll3dController.maxScrollExtent] and do something with geometry.
class ClampingScroll3dPhysics extends Scroll3dPhysics {
  /// Creates a clamping physics.
  const ClampingScroll3dPhysics({this.friction = 0.015});

  /// How quickly a fling decelerates. Android's number, in Android's units.
  final double friction;

  @override
  double applyBoundaryConditions(Scroll3dController position, double value) {
    final pixels = position.offset;
    final min = position.minScrollExtent;
    final max = position.maxScrollExtent;
    // Flutter's four cases, and the reason a hard `clamp` is not enough: a
    // position that is *already* out of range (a correction, a shrinking
    // list) must be allowed to move back toward the range rather than being
    // snapped into it, or the ballistic settle could never run.
    if (value < pixels && pixels <= min) return value - pixels;
    if (max <= pixels && pixels < value) return value - pixels;
    if (value < min && min < pixels) return value - min;
    if (pixels < max && max < value) return value - max;
    return 0.0;
  }

  @override
  Simulation? createBallisticSimulation(
    Scroll3dController position,
    double velocity,
  ) {
    final scale = position.unitsPerLogicalPixel;
    final pixels = position.offset / scale;
    final min = position.minScrollExtent / scale;
    final max = position.maxScrollExtent / scale;
    final speed = velocity / scale;
    if (position.outOfRange) {
      final end = position.offset > position.maxScrollExtent ? max : min;
      return Scroll3dPhysics.scaled(
        ScrollSpringSimulation(
          Scroll3dPhysics.defaultSpring,
          pixels,
          end,
          math.min(0.0, speed),
          tolerance: tolerance,
        ),
        scale,
      );
    }
    if (speed.abs() < tolerance.velocity) return null;
    if (speed > 0.0 && pixels >= max) return null;
    if (speed < 0.0 && pixels <= min) return null;
    return Scroll3dPhysics.scaled(
      ClampingScrollSimulation(
        position: pixels,
        velocity: speed,
        friction: friction,
        tolerance: tolerance,
      ),
      scale,
    );
  }
}

/// A scroll position that can be pulled past its ends and springs back, the
/// iOS feel.
///
/// The drag is damped as it goes further out, and a release anywhere outside
/// the range returns through [Scroll3dPhysics.defaultSpring].
///
/// ## Overscroll in a scene need not be a spring
///
/// This is the two-dimensional answer, ported. A scene can do better: the
/// content can bend away from the finger, tilt on the axis it was pulled
/// past, or compress like a stack of cards, and none of that is a scroll
/// offset at all — it is a transform on the geometry, which is the node-only
/// path ([NodeTransform3d]) and costs no layout. Watch
/// [Scroll3dController.overscroll] and animate whatever you like from it;
/// this class is the conservative default underneath.
class BouncingScroll3dPhysics extends Scroll3dPhysics {
  /// Creates a bouncing physics.
  BouncingScroll3dPhysics({SpringDescription? spring})
    : spring = spring ?? Scroll3dPhysics.defaultSpring;

  /// The spring that returns the position to the range.
  final SpringDescription spring;

  /// How much of a drag survives, as a fraction, at [overscrollFraction] of
  /// the window past the end. Flutter's curve.
  double frictionFactor(double overscrollFraction) =>
      0.52 * math.pow(1 - overscrollFraction, 2);

  @override
  double applyPhysicsToUserOffset(Scroll3dController position, double delta) {
    if (!position.outOfRange || delta == 0.0) return delta;
    final pastStart = math.max(position.minScrollExtent - position.offset, 0.0);
    final pastEnd = math.max(position.offset - position.maxScrollExtent, 0.0);
    final past = math.max(pastStart, pastEnd);
    // Pulling further out is damped; letting the content come back is not,
    // so a finger returning from an overscroll tracks exactly.
    final easing =
        (pastStart > 0.0 && delta < 0.0) || (pastEnd > 0.0 && delta > 0.0);
    final window = position.viewportExtent;
    if (window <= 0.0) return delta;
    final friction = easing
        ? frictionFactor((past - delta.abs()) / window)
        : frictionFactor(past / window);
    return delta.sign * _applyFriction(past, delta.abs(), friction);
  }

  static double _applyFriction(
    double extentOutside,
    double absDelta,
    double gamma,
  ) {
    var remaining = absDelta;
    var total = 0.0;
    if (extentOutside > 0) {
      final toLimit = extentOutside / gamma;
      if (remaining < toLimit) return remaining * gamma;
      total += extentOutside;
      remaining -= toLimit;
    }
    return total + remaining;
  }

  @override
  bool get allowsOverscroll => true;

  /// Nothing is refused: this is the physics that lets the position leave the
  /// range in the first place.
  @override
  double applyBoundaryConditions(Scroll3dController position, double value) =>
      0.0;

  @override
  Simulation? createBallisticSimulation(
    Scroll3dController position,
    double velocity,
  ) {
    final scale = position.unitsPerLogicalPixel;
    final speed = velocity / scale;
    if (speed.abs() < tolerance.velocity && !position.outOfRange) return null;
    return Scroll3dPhysics.scaled(
      BouncingScrollSimulation(
        spring: spring,
        position: position.offset / scale,
        velocity: speed,
        leadingExtent: position.minScrollExtent / scale,
        trailingExtent: position.maxScrollExtent / scale,
        tolerance: tolerance,
      ),
      scale,
    );
  }
}

/// A scroll position that comes to rest on a page boundary, the 3D analogue
/// of [PageScrollPhysics].
///
/// The ends behave exactly as [ClampingScroll3dPhysics] — this extends it —
/// and what differs is the release: instead of coasting to a stop wherever
/// friction leaves it, the position springs to the nearest page. Which page
/// is "nearest" takes the throw into account, the way Flutter's does: any
/// deliberate flick carries a whole page, however short it was, while a slow
/// release settles back onto whichever page it is more than half onto.
///
/// [pageExtent] is the stride, and defaults to the whole window, which is
/// what [PageView3d] wants. State it to snap something that is not a full
/// page — a carousel of cards in a `ListView3d` with an `itemExtent`, where
/// the neighbours are meant to peek in:
///
/// ```dart
/// Scroll3dController(
///   physics: PageScroll3dPhysics(pageExtent: cardExtent + spacing),
/// )
/// ```
class PageScroll3dPhysics extends ClampingScroll3dPhysics {
  /// Creates a snapping physics.
  PageScroll3dPhysics({
    this.pageExtent,
    SpringDescription? spring,
    super.friction,
  }) : spring = spring ?? Scroll3dPhysics.defaultSpring,
       assert(pageExtent == null || pageExtent > 0.0);

  /// The distance between two resting places, or null for the window's own
  /// extent.
  final double? pageExtent;

  /// The spring that carries the position onto the page it settled for.
  final SpringDescription spring;

  /// The stride in force for [position], in layout units.
  double strideFor(Scroll3dController position) =>
      pageExtent ?? position.viewportExtent;

  /// Where [position] is, counted in pages.
  ///
  /// Fractional between two of them, which is what a page indicator reads to
  /// follow a drag rather than jumping when it ends.
  double pageOf(Scroll3dController position) {
    final stride = strideFor(position);
    if (stride <= 0.0) return 0.0;
    return position.offset / stride;
  }

  /// The offset a release at [velocity] layout units per second settles on.
  ///
  /// Half a page of bias in the direction of the throw, so a flick that
  /// barely moved still turns the page, and then rounded and held inside the
  /// scrollable range.
  double targetOffset(Scroll3dController position, double velocity) {
    final stride = strideFor(position);
    if (stride <= 0.0) return position.offset;
    var page = pageOf(position);
    final speed = velocity / position.unitsPerLogicalPixel;
    if (speed < -tolerance.velocity) {
      page -= 0.5;
    } else if (speed > tolerance.velocity) {
      page += 0.5;
    }
    return (page.roundToDouble() * stride).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    Scroll3dController position,
    double velocity,
  ) {
    // A throw off the end has nothing to snap to; the clamping physics is
    // already the right answer there, and it is the one that stops dead.
    if ((velocity <= 0.0 && position.offset <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.offset >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final target = targetOffset(position, velocity);
    final scale = position.unitsPerLogicalPixel;
    if (((target - position.offset) / scale).abs() < tolerance.distance) {
      return null;
    }
    return Scroll3dPhysics.scaled(
      ScrollSpringSimulation(
        spring,
        position.offset / scale,
        target / scale,
        velocity / scale,
        tolerance: tolerance,
      ),
      scale,
    );
  }
}
