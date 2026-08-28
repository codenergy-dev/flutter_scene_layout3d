import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, EnumProperty;
import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerEnterEvent,
        PointerExitEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerUpEvent;

import '../geometry/offset3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import 'events.dart';

/// What a box is handed when a pointer event reaches it.
typedef PointerEvent3dCallback = void Function(PointerEvent3d event);

/// A pass-through box that decides how it takes part in a hit test.
///
/// The 3D analogue of `RenderProxyBoxWithHitTestBehavior`, and the base of
/// every interactive box here. Without one of these a component made of a
/// decoration and a label answers a ray only where the label is: the padding
/// that gives the button its shape is a hole. [HitTestBehavior3d.opaque]
/// closes the hole.
abstract class ProxyLayout3dWithHitTestBehavior extends ProxyLayout3d {
  /// Creates a pass-through box with the given [behavior].
  ProxyLayout3dWithHitTestBehavior({
    HitTestBehavior3d behavior = HitTestBehavior3d.deferToChild,
    super.child,
    super.name,
  }) : _behavior = behavior;

  HitTestBehavior3d _behavior;

  /// How this box takes part in a hit test.
  ///
  /// Costs nothing to change: hit testing reads it as it walks, so nothing is
  /// laid out again behind a change here.
  // A field would do, but every other property in the package is a getter and
  // setter pair, and one that is a field cannot later grow a setter without
  // breaking its callers.
  // ignore: unnecessary_getters_setters
  HitTestBehavior3d get behavior => _behavior;

  set behavior(HitTestBehavior3d value) {
    _behavior = value;
  }

  @override
  bool hitTestSelf(Offset3d position) => _behavior == HitTestBehavior3d.opaque;

  /// The base walk, plus the one thing [HitTestBehavior3d.translucent] adds:
  /// the box joins the path even though it did not answer the hit, so it
  /// receives the events its extent covers while the ray carries on to
  /// whatever stands behind it.
  ///
  /// Deliberately a copy of [Layout3d.hitTest] rather than a call to it —
  /// there is no way to say "add me anyway" through that contract, and
  /// Flutter's `RenderProxyBoxWithHitTestBehavior` duplicates it for the same
  /// reason.
  @override
  bool hitTest(HitTestResult3d result, {required Ray3d ray}) {
    if (!hasSize) return false;
    final range = ray.intersectBox(size);
    if (range == null) return false;
    final entry = ray.at(range.near);
    if (!entry.isFinite) return false;
    final inside = ray.clampedTo(range.near, range.far);
    final hit = hitTestChildren(result, ray: inside) || hitTestSelf(entry);
    if (hit || _behavior == HitTestBehavior3d.translucent) {
      result.add(HitTestEntry3d(this, entry));
    }
    return hit;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<HitTestBehavior3d>('behavior', behavior));
  }
}

/// Claims a region of the plane for the pointer, without doing anything with
/// it.
///
/// The box to reach for when the shape of a target and the shape of the
/// content disagree: a 24dp icon inside a 48dp button, the whole face of a
/// card whose content is one line of text in the corner. It changes nothing
/// about layout — its size is its child's — only what a ray finds.
///
/// ```dart
/// HitTestArea3d(
///   child: Padding3d(
///     padding: EdgeInsets3d.symmetric(horizontal: metrics.dp(24)),
///     child: IgnorePointer3d(child: Text3d('Continue')),
///   ),
/// )
/// ```
///
/// The [IgnorePointer3d] around the label is the usual companion: a [Text3d]
/// answers hit tests on its own account, and a component that wants to be one
/// target rather than two takes its label out of the way.
class HitTestArea3d extends ProxyLayout3dWithHitTestBehavior {
  /// Creates a hit-test region, opaque by default.
  HitTestArea3d({
    super.behavior = HitTestBehavior3d.opaque,
    super.child,
    super.name,
  });
}

/// Calls back when a pointer does something inside it, the 3D analogue of
/// [Listener] — with the enter and exit of `MouseRegion` folded in.
///
/// The raw-event box, one step below [GestureDetector3d]: no recognition, no
/// arena, no disambiguation, just the events as they arrive. Reach for it
/// when the event *is* the behaviour — a knob that follows the pointer, a
/// panel that lights up under it — and for [GestureDetector3d] when the
/// question is "was that a tap".
///
/// Enter and exit are here rather than in a box of their own because there is
/// no separate mouse-tracking pass in this package: hover is a walk of the
/// same path everything else is dispatched along, so the same box can serve
/// both. They arrive only for a pointer the host feeds to
/// [Layout3dPointer.hover]; a pressed pointer moving is [onPointerMove].
///
/// Driving a state layer from it is two lines, and costs no layout:
///
/// ```dart
/// final panel = DecoratedBox3d(decoration: decoration, child: label);
/// Listener3d(
///   behavior: HitTestBehavior3d.opaque,
///   onPointerEnter: (_) => panel.stateLayer = hover,
///   onPointerExit: (_) => panel.stateLayer = StateLayer3d.none,
///   onPointerDown: (_) => panel.stateLayer = pressed,
///   onPointerUp: (_) => panel.stateLayer = hover,
///   child: panel,
/// );
/// ```
class Listener3d extends ProxyLayout3dWithHitTestBehavior
    implements HitTestTarget3d {
  /// Creates a box that reports the pointer events it is handed.
  Listener3d({
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this.onPointerHover,
    this.onPointerEnter,
    this.onPointerExit,
    super.behavior = HitTestBehavior3d.deferToChild,
    super.child,
    super.name,
  });

  /// Called when a pointer comes down on this box.
  PointerEvent3dCallback? onPointerDown;

  /// Called when a pointer that came down on this box moves, wherever it has
  /// moved to: the path is captured at the press.
  PointerEvent3dCallback? onPointerMove;

  /// Called when a pointer that came down on this box is lifted.
  PointerEvent3dCallback? onPointerUp;

  /// Called when the press is abandoned without an up.
  PointerEvent3dCallback? onPointerCancel;

  /// Called when an unpressed pointer moves over this box.
  PointerEvent3dCallback? onPointerHover;

  /// Called when an unpressed pointer arrives over this box.
  PointerEvent3dCallback? onPointerEnter;

  /// Called when an unpressed pointer leaves this box, including when it
  /// leaves the surface entirely.
  PointerEvent3dCallback? onPointerExit;

  @override
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry) {
    final raw = event.event;
    if (raw is PointerDownEvent) {
      onPointerDown?.call(event);
    } else if (raw is PointerMoveEvent) {
      onPointerMove?.call(event);
    } else if (raw is PointerUpEvent) {
      onPointerUp?.call(event);
    } else if (raw is PointerCancelEvent) {
      onPointerCancel?.call(event);
    } else if (raw is PointerHoverEvent) {
      onPointerHover?.call(event);
    } else if (raw is PointerEnterEvent) {
      onPointerEnter?.call(event);
    } else if (raw is PointerExitEvent) {
      onPointerExit?.call(event);
    }
  }
}
