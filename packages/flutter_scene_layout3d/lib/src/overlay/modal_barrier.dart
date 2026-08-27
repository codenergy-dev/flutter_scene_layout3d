import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/gestures.dart'
    show PointerCancelEvent, PointerDownEvent, PointerUpEvent;

import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../hit_test.dart';
import '../input/events.dart';
import '../layout3d.dart';

/// The slab in front of everything a modal covers: it fills the space it is
/// given, swallows every ray that reaches it, and reports the tap that ought
/// to dismiss what is above it.
///
/// The 3D analogue of Flutter's `ModalBarrier`, and the same two jobs. The
/// first is absorption, which [AbsorbPointer3d] would also do — a barrier is
/// an absorber that answers for itself rather than for a subtree. The second
/// is dismissal: a tap that starts *and ends* on the barrier is a tap
/// outside, and calls [onDismiss]. A press that starts on the barrier and
/// slides onto the content still ends on the barrier, because the path is
/// captured at the press, which is the same rule Flutter's barrier keeps.
///
/// A tap on the content never reaches here at all: the content is a later
/// sibling in the [Overlay3d]'s stack, so the ray finds it first and stops.
///
/// ## What a scrim is, in a scene
///
/// A dimmed background is not an alpha wash over a display list here; there
/// is no display list. It is geometry: a slab, [thickness] deep, carrying
/// whatever [child] the caller decorates it with — usually a
/// [DecoratedBox3d]. Until the opacity contract lands (see the size-driven
/// geometry plan) a translucent scrim is not expressible, and the honest
/// fallback is a dark material or a dimming tint on the decoration. Leaving
/// [child] null gives a barrier that blocks input and shows nothing, which is
/// what a menu wants.
///
/// [thickness] defaults to zero, so a barrier is a plane rather than a box:
/// a ray still reaches it (a zero-extent slab is intersected on both faces),
/// and nothing behind it is displaced.
class ModalBarrier3d extends SingleChildLayout3d implements HitTestTarget3d {
  /// Creates a barrier that fills what it is given.
  ModalBarrier3d({
    this.onDismiss,
    bool dismissible = true,
    double thickness = 0.0,
    super.child,
    super.name,
  }) : _dismissible = dismissible,
       _thickness = thickness;

  /// Called when a tap lands on the barrier itself.
  ///
  /// The hook a dialog pops itself from, and a menu closes on. Null, or
  /// [dismissible] false, makes the barrier inert without making it
  /// transparent: the press is still swallowed.
  VoidCallback? onDismiss;

  bool _dismissible;

  /// Whether a tap on the barrier calls [onDismiss].
  ///
  /// Costs nothing to flip, for the same reason [AbsorbPointer3d.absorbing]
  /// does: dispatch reads it as the event arrives.
  // ignore: unnecessary_getters_setters
  bool get dismissible => _dismissible;

  set dismissible(bool value) {
    _dismissible = value;
  }

  double _thickness;

  /// The barrier's extent along the depth axis, in world units.
  double get thickness => _thickness;

  set thickness(double value) {
    if (_thickness == value) return;
    _thickness = value;
    markNeedsLayout();
  }

  bool _pressed = false;

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      axis == Axis3d.depth ? _thickness : 0.0;

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      axis == Axis3d.depth ? _thickness : double.infinity;

  @override
  void performLayout() {
    // As big as it is allowed to be on the two in-plane axes, and exactly
    // [thickness] deep. An unbounded axis collapses to its minimum rather
    // than to infinity: a barrier in an unbounded overlay covers nothing,
    // which is visible, where an infinite one would poison every arithmetic
    // downstream of it.
    size = constraints.constrain(
      Size3d(
        constraints.hasBoundedWidth
            ? constraints.maxWidth
            : constraints.minWidth,
        constraints.hasBoundedHeight
            ? constraints.maxHeight
            : constraints.minHeight,
        _thickness,
      ),
    );
    final child = this.child;
    if (child == null) return;
    child.layout(Constraints3d.tight(size));
    child.place(Offset3d.zero);
  }

  /// The barrier answers for itself, which is what stops the ray.
  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry) {
    final pointerEvent = event.event;
    if (pointerEvent is PointerDownEvent) {
      _pressed = true;
      return;
    }
    if (pointerEvent is PointerCancelEvent) {
      _pressed = false;
      return;
    }
    if (pointerEvent is! PointerUpEvent) return;
    if (!_pressed) return;
    _pressed = false;
    if (!_dismissible) return;
    onDismiss?.call();
  }

  @override
  String toString() =>
      'ModalBarrier3d(${_dismissible ? 'dismissible' : 'inert'})';
}
