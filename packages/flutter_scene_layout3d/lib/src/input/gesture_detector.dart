import 'package:flutter/gestures.dart'
    show
        DoubleTapGestureRecognizer,
        GestureDragCancelCallback,
        GestureDragDownCallback,
        GestureDragEndCallback,
        GestureDragStartCallback,
        GestureDragUpdateCallback,
        GestureLongPressCallback,
        GestureLongPressEndCallback,
        GestureLongPressMoveUpdateCallback,
        GestureLongPressStartCallback,
        GestureRecognizer,
        GestureTapCallback,
        GestureTapCancelCallback,
        GestureTapDownCallback,
        GestureTapUpCallback,
        LongPressGestureRecognizer,
        PanGestureRecognizer,
        PointerDownEvent,
        TapGestureRecognizer;

import '../hit_test.dart';
import 'events.dart';
import 'listener.dart';

/// Recognizes gestures on a plane, the 3D analogue of [GestureDetector].
///
/// It owns Flutter's own recognizers — [TapGestureRecognizer],
/// [DoubleTapGestureRecognizer], [LongPressGestureRecognizer],
/// [PanGestureRecognizer] — and hands them the events the surface
/// synthesizes, so Material's gesture semantics are the ones Flutter already
/// ships: the same deadlines, the same slop, and above all the same *arena*.
/// A tap on a list item and a drag of the list it sits in compete exactly as
/// they do on a screen, and the finger decides which one it meant.
///
/// ```dart
/// GestureDetector3d(
///   onTapDown: (details) => panel.stateLayer = pressed,
///   onTapCancel: () => panel.stateLayer = StateLayer3d.none,
///   onTap: () {
///     panel.stateLayer = StateLayer3d.none;
///     submit();
///   },
///   child: panel,
/// )
/// ```
///
/// ## What the callbacks are measured in
///
/// Logical pixels, on the surface's plane. `details.localPosition` is the
/// point in this box's own frame and `details.globalPosition` the point on
/// the surface, both in dp, because that is the currency Flutter's
/// recognizers are tuned in — `kTouchSlop` has to mean 18dp rather than 18
/// world units. Multiply by `metrics.unitsPerLogicalPixel` to get back to
/// layout units, or reach for [Listener3d] and
/// [PointerEvent3d.localPosition], which is in units and stays exact for a
/// box seen at any angle.
///
/// ## What it needs
///
/// Flutter's gesture binding: recognizers reach for `GestureBinding.instance`
/// themselves. `runApp` has already initialized it; a test wants
/// `TestWidgetsFlutterBinding.ensureInitialized()`.
///
/// ## Differences from [GestureDetector]
///
///  * [HitTestBehavior3d.opaque] by default, because a component is a target
///    over its whole face including the padding that shapes it. Flutter's
///    default depends on whether there is a child; here the common case wins.
///  * One drag rather than three: [onPanStart] and friends. A view that
///    scrolls is a [Scrollable3d] and competes for the pointer through
///    `Layout3dPointer` rather than through a recognizer of its own.
class GestureDetector3d extends ProxyLayout3dWithHitTestBehavior
    implements HitTestTarget3d {
  /// Creates a gesture detector.
  ///
  /// Every callback is a plain mutable field: set one after construction and
  /// the recognizer behind it appears on the next press. Nothing here touches
  /// layout.
  GestureDetector3d({
    this.onTapDown,
    this.onTapUp,
    this.onTap,
    this.onTapCancel,
    this.onDoubleTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onPanDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    super.behavior = HitTestBehavior3d.opaque,
    super.child,
    super.name,
  });

  /// Called when a pointer that might turn into a tap comes down.
  GestureTapDownCallback? onTapDown;

  /// Called when the pointer that will produce a tap is lifted.
  GestureTapUpCallback? onTapUp;

  /// Called when a tap has happened.
  GestureTapCallback? onTap;

  /// Called when the pointer that produced [onTapDown] will not tap after
  /// all, because something else won the pointer — the list underneath
  /// started scrolling, most often. The cue to take a pressed state layer
  /// back off.
  GestureTapCancelCallback? onTapCancel;

  /// Called when the box is tapped twice in quick succession.
  GestureTapCallback? onDoubleTap;

  /// Called when a long press is recognized.
  GestureLongPressCallback? onLongPress;

  /// Called when a long press is recognized, with where it happened.
  GestureLongPressStartCallback? onLongPressStart;

  /// Called when the pointer moves during a recognized long press.
  GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  /// Called when a long press ends.
  GestureLongPressEndCallback? onLongPressEnd;

  /// Called when a pointer that might turn into a pan comes down.
  GestureDragDownCallback? onPanDown;

  /// Called when a pan begins, which is when the pointer has moved far enough
  /// to have meant it.
  GestureDragStartCallback? onPanStart;

  /// Called as a recognized pan moves. `details.delta` is in logical pixels
  /// on the plane.
  GestureDragUpdateCallback? onPanUpdate;

  /// Called when a recognized pan ends.
  GestureDragEndCallback? onPanEnd;

  /// Called when a pan that had begun to be recognized is abandoned.
  GestureDragCancelCallback? onPanCancel;

  TapGestureRecognizer? _tap;
  DoubleTapGestureRecognizer? _doubleTap;
  LongPressGestureRecognizer? _longPress;
  PanGestureRecognizer? _pan;

  /// The recognizers currently armed, for a test or a debugger to look at.
  ///
  /// Built on demand: a detector with no callbacks owns nothing, which is
  /// what makes it cheap to wrap every component in one.
  Iterable<GestureRecognizer> get recognizers => <GestureRecognizer>[
    if (_tap != null) _tap!,
    if (_doubleTap != null) _doubleTap!,
    if (_longPress != null) _longPress!,
    if (_pan != null) _pan!,
  ];

  @override
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry) {
    if (event.event is! PointerDownEvent) return;
    _syncRecognizers();
    for (final recognizer in recognizers) {
      event.addPointerToRecognizer(recognizer);
    }
  }

  /// Brings the recognizers into line with the callbacks that are set.
  ///
  /// Called at every press rather than at every property change, because the
  /// callbacks are fields: this is the one moment the answer has to be right,
  /// and it is a handful of null checks.
  void _syncRecognizers() {
    final wantsTap =
        onTap != null ||
        onTapDown != null ||
        onTapUp != null ||
        onTapCancel != null;
    if (wantsTap) {
      final tap = _tap ??= TapGestureRecognizer(debugOwner: this);
      tap
        ..onTapDown = onTapDown
        ..onTapUp = onTapUp
        ..onTap = onTap
        ..onTapCancel = onTapCancel;
    } else {
      _tap = _disposed(_tap);
    }

    if (onDoubleTap != null) {
      (_doubleTap ??= DoubleTapGestureRecognizer(
        debugOwner: this,
      )).onDoubleTap = onDoubleTap;
    } else {
      _doubleTap = _disposed(_doubleTap);
    }

    final wantsLongPress =
        onLongPress != null ||
        onLongPressStart != null ||
        onLongPressMoveUpdate != null ||
        onLongPressEnd != null;
    if (wantsLongPress) {
      final longPress = _longPress ??= LongPressGestureRecognizer(
        debugOwner: this,
      );
      longPress
        ..onLongPress = onLongPress
        ..onLongPressStart = onLongPressStart
        ..onLongPressMoveUpdate = onLongPressMoveUpdate
        ..onLongPressEnd = onLongPressEnd;
    } else {
      _longPress = _disposed(_longPress);
    }

    final wantsPan =
        onPanDown != null ||
        onPanStart != null ||
        onPanUpdate != null ||
        onPanEnd != null ||
        onPanCancel != null;
    if (wantsPan) {
      final pan = _pan ??= PanGestureRecognizer(debugOwner: this);
      pan
        ..onDown = onPanDown
        ..onStart = onPanStart
        ..onUpdate = onPanUpdate
        ..onEnd = onPanEnd
        ..onCancel = onPanCancel;
    } else {
      _pan = _disposed(_pan);
    }
  }

  static T? _disposed<T extends GestureRecognizer>(T? recognizer) {
    recognizer?.dispose();
    return null;
  }

  @override
  void dispose() {
    _tap = _disposed(_tap);
    _doubleTap = _disposed(_doubleTap);
    _longPress = _disposed(_longPress);
    _pan = _disposed(_pan);
    super.dispose();
  }
}
