import 'dart:async' show Timer;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        DiagnosticsProperty,
        FlagProperty,
        ValueChanged,
        VoidCallback;
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
        computeHitSlop,
        kLongPressTimeout;
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import '../boxes/ignore_pointer.dart';
import '../geometry/offset3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import '../overlay/overlay.dart';
import 'autoscroll.dart';
import 'drag.dart';
import 'events.dart';
import 'listener.dart';

/// Builds the geometry carried under the pointer during a drag.
///
/// Called once, when the drag is recognized, and the subtree it returns
/// belongs to the overlay entry that hosts it: it is disposed when the drag
/// ends, whatever ended it.
typedef Drag3dFeedbackBuilder = Layout3d Function(Drag3dSession session);

/// Asks whether a target wants a particular payload.
typedef Drag3dWillAccept<T> = bool Function(T data, Drag3dDetails details);

/// Told that a payload did something over a target.
typedef Drag3dTargetCallback<T> = void Function(T data, Drag3dDetails details);

/// When a press on a [Draggable3d] turns into a drag.
///
/// Flutter's semantics without Flutter's classes, which is not a stylistic
/// choice: in this build `DragGestureRecognizer` delivers `onStart` and
/// nothing after it, and `LongPressGestureRecognizer` never fires at all —
/// both reproduced with no code from this package involved. So the threshold
/// is arithmetic here and the delay is a plain [Timer], and both are
/// exercised by ordinary tests.
class Drag3dStartMode {
  /// The drag begins as soon as the pointer has travelled past the slop.
  ///
  /// What a dismissible row and a desktop drag want.
  const Drag3dStartMode.immediate() : delay = null;

  /// The drag begins when the pointer has been held still for [delay].
  ///
  /// Travelling past the slop before the delay is up cancels it: the press
  /// was a scroll, or a swipe, and never a pick-up. Lifting cancels it too.
  const Drag3dStartMode.longPress([this.delay = kLongPressTimeout]);

  /// How long the press must be held, or null for [Drag3dStartMode.immediate].
  final Duration? delay;

  /// Whether the drag starts on travel rather than on a delay.
  bool get isImmediate => delay == null;

  @override
  bool operator ==(Object other) =>
      other is Drag3dStartMode && other.delay == delay;

  @override
  int get hashCode => Object.hash(Drag3dStartMode, delay);

  @override
  String toString() => delay == null
      ? 'Drag3dStartMode.immediate()'
      : 'Drag3dStartMode.longPress($delay)';
}

/// A box whose contents can be picked up and carried to a [DragTarget3d].
///
/// The 3D analogue of Flutter's `Draggable`, and the same three moving parts:
/// a payload, a piece of feedback that follows the pointer, and a drop that
/// either lands on a target or does not.
///
/// ```dart
/// Draggable3d<Photo>(
///   data: photo,
///   feedbackBuilder: (_) => Container3d(
///     size: const Size3d(0.6, 0.4, 0.02),
///     decoration: cardDecoration,
///   ),
///   child: thumbnail,
/// )
/// ```
///
/// ## What it costs per frame
///
/// One matrix write. The feedback is laid out once, when the drag is
/// recognized, and every move after that writes its [Layout3d.nodeOffset] —
/// the node tier, which never calls `markNeedsLayout`. Nothing is rebuilt and
/// no geometry is remade, which is the rule `docs/traps.md` sets for anything
/// on a per-frame path and a drag is the most per-frame path there is.
///
/// Note *which* channel. `ParentData3d.sceneOffset` belongs to the parent and
/// [Overlay3d] is a [Stack3d], whose `depthStep` rewrites it on every
/// placement — an animation stored there is silently erased. The two layout
/// passes a drag does cost are the insertion of the feedback entry at the
/// start and its removal at the end, and there is no way around either: an
/// overlay entry is a child of a stack, and adding a child is a layout.
///
/// ## Where the feedback lives
///
/// In the nearest [Overlay3d] above this box, found by [Overlay3d.of], or in
/// [overlay] when one is named. A draggable with no overlay above it still
/// drags — the session runs, targets light up, the drop lands — it simply
/// carries nothing visible, which is the right failure for a headless test
/// and a loud one on screen.
///
/// The feedback is wrapped in an [IgnorePointer3d], and that is mandatory
/// rather than tidy. Hit testing deliberately ignores [Layout3d.nodeOffset],
/// so the feedback's *laid-out* position is still hit-testable even though it
/// is drawn somewhere else, and a [Text3d] inside it would answer a ray on
/// its own account and steal the drop.
///
/// ## How it competes for the pointer
///
/// Through [PointerSequence3d.addArenaMember], as its own
/// [GestureArenaMember]. Adding one marks the sequence contested, which makes
/// a [Scrollable3d] under this box wait for the touch slop rather than
/// scrolling out from under the drag; then the first of the two to cross its
/// own slop, on its own axis, claims the pointer. Give [axis] to a draggable
/// inside a list running the other way and the two stop fighting: the row
/// claims on horizontal travel, the list on vertical.
///
/// Winning the arena and *recognizing* the drag are kept apart on purpose. A
/// draggable that is alone in the arena is handed the pointer by default as
/// soon as the arena closes, a microtask after the press, and starting the
/// drag there would mean no threshold at all.
class Draggable3d<T extends Object> extends ProxyLayout3dWithHitTestBehavior
    implements HitTestTarget3d {
  /// Creates a draggable box carrying [data].
  Draggable3d({
    this.data,
    this.feedbackBuilder,
    this.startMode = const Drag3dStartMode.immediate(),
    this.axis,
    this.anchor = Drag3dAnchor.originPlane,
    this.overlay,
    this.feedbackLayer = const OverlayLayer3d.inPlane(),
    this.dropDuration = const Duration(milliseconds: 200),
    this.dropCurve = Curves.easeOutCubic,
    this.autoscroll,
    this.vsync,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCompleted,
    this.onDraggableCanceled,
    super.behavior = HitTestBehavior3d.opaque,
    super.child,
    super.name,
  });

  /// What this box carries.
  ///
  /// A target takes it only when `data is T` for the target's own `T`, so a
  /// null payload is refused by every `DragTarget3d<T>`: `null is T` is false
  /// for a non-nullable `T`. A draggable with no data is still a legal thing
  /// to build — it drags and lands on nothing — but it is rarely what was
  /// meant.
  T? data;

  /// Builds what is carried under the pointer, or null to carry nothing
  /// visible.
  Drag3dFeedbackBuilder? feedbackBuilder;

  /// When a press here becomes a drag.
  Drag3dStartMode startMode;

  /// The axis travel is measured on, or null for travel in any direction.
  ///
  /// Naming one is how a draggable row inside a scrolling list stops fighting
  /// the list: each claims on its own axis, and the finger decides.
  Axis3d? axis;

  /// Which plane the feedback is carried on.
  ///
  /// Only [Drag3dAnchor.originPlane] is implemented — a cross-surface drag
  /// carries its feedback on the plane it was picked up from and lands on the
  /// target all the same. [Drag3dAnchor.targetPlane] is reserved and says
  /// there why. The session carries the value either way, so that a
  /// re-anchoring pass can read it without a new seam.
  Drag3dAnchor anchor;

  /// The overlay the feedback goes into, or null for the nearest one above.
  Overlay3d? overlay;

  /// Which layer of the overlay the feedback goes on.
  ///
  /// In-plane by default: one surface, one layout pass, and the stack's own
  /// ordering already lifts the entry toward the viewer, which is what a
  /// picked-up card does anyway. [OverlayLayer3d.detached] is the opt-in for
  /// a drag that has to leave the panel it started on.
  OverlayLayer3d feedbackLayer;

  /// How long the feedback takes to settle when the drag ends.
  ///
  /// [Duration.zero] removes it at once. The animation is a node-tier tween
  /// and delays nothing but the removal.
  Duration dropDuration;

  /// The curve the drop animation follows.
  Curve dropCurve;

  /// How a drag carried to the edge of a scrolling view moves it, or null for
  /// no autoscroll at all.
  ///
  /// Null by default, which is Flutter's default for `Draggable` too and is
  /// the right one for a card dragged between two panels: nothing about
  /// picking something up says the view underneath should start moving. A
  /// list that reorders itself is the case where it is always wanted, and
  /// [SliverReorderableList3d] turns it on for its own items.
  ///
  /// The settings are read afresh on every drag, so changing them between
  /// drags takes effect; changing them *during* one does not, since the
  /// autoscroller holds the value it was made with.
  Drag3dAutoscroll? autoscroll;

  /// The ticker provider for the drop animation.
  ///
  /// Null means a bare [Ticker], which schedules through the same
  /// [SchedulerBinding] and works outside a `State`. Give one where there is
  /// a `State` in the picture so that `TickerMode` can mute it.
  TickerProvider? vsync;

  /// Called when a drag begins here.
  VoidCallback? onDragStarted;

  /// Called as the drag moves, with how far it has travelled from the press,
  /// in this box's own frame.
  ValueChanged<Offset3d>? onDragUpdate;

  /// Called when the drag ends, before the feedback has finished settling.
  ///
  /// The session is ended by then: read [Drag3dSession.wasAccepted] and
  /// [Drag3dSession.acceptedBy] to tell a completed drag from an abandoned
  /// one.
  ValueChanged<Drag3dSession>? onDragEnd;

  /// Called when a target took the payload.
  VoidCallback? onDragCompleted;

  /// Called when the drag ended over nothing, with where it ended.
  ValueChanged<Offset3d>? onDraggableCanceled;

  final Map<int, _Drag3dGesture> _gestures = <int, _Drag3dGesture>{};

  Drag3dSession? _session;
  Overlay3dEntry? _feedbackEntry;
  Layout3d? _feedback;

  /// Where the feedback has to sit, in its own frame, to cover this box.
  ///
  /// Computed once, the first time the feedback has been laid out — which is
  /// never on the frame it was inserted — and reused after that, because the
  /// source box may be disposed under a long drag and a session must survive
  /// that.
  Offset3d? _feedbackHome;

  /// Takes a travel measured in this box's frame into the feedback's.
  ///
  /// The two are axis-aligned unless a `Transform3d` stands between them, and
  /// this costs the same either way.
  Matrix4? _travelToFeedback;

  Drag3dAutoscroller? _autoscroller;

  /// The autoscroller running under the live drag, or null when there is no
  /// drag or [autoscroll] is off.
  Drag3dAutoscroller? get autoscroller => _autoscroller;

  Offset3d _travel = Offset3d.zero;
  Offset3d _dropFrom = Offset3d.zero;
  Offset3d _dropTo = Offset3d.zero;
  Ticker? _dropTicker;
  bool _disposed = false;

  /// The drag this box is carrying, or null when it is not being dragged.
  Drag3dSession? get session => _session;

  /// Whether a drag started here is in flight.
  bool get isDragging => _session != null;

  /// How far the live drag has travelled from the press, in this box's frame.
  Offset3d get travel => _travel;

  @override
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry) {
    final raw = event.event;
    if (raw is PointerDownEvent) {
      // One drag at a time from one box: a second finger on a card that is
      // already in flight is not a second copy of it.
      if (_session != null) return;
      final gesture = _Drag3dGesture(
        owner: this,
        press: event.localPosition,
        kind: raw.kind,
        metricsScale: event.metricsScale,
      );
      _gestures[event.pointer] = gesture;
      gesture.begin(event);
    } else if (raw is PointerMoveEvent) {
      _gestures[event.pointer]?.update(event);
    } else if (raw is PointerUpEvent) {
      _gestures.remove(event.pointer)?.finish();
    } else if (raw is PointerCancelEvent) {
      _gestures.remove(event.pointer)?.abandon();
    }
  }

  /// Puts a session in flight, with feedback if there is an overlay for it.
  void _startDrag(_Drag3dGesture gesture, PointerSequence3d? sequence) {
    if (_session != null || _disposed) return;
    _stopDropAnimation();
    _feedbackHome = null;
    _travelToFeedback = null;
    _travel = gesture.travel;
    final session = Drag3dSession(
      data: data,
      origin: gesture.press,
      anchor: anchor,
      debugLabel: node.name,
    );
    _session = session;
    // Registered before the session is handed to the pointer, so that a
    // session which ends inside its own first resolution — a target that
    // takes the drop the instant it sees it — is still released down this
    // path rather than leaking an overlay entry.
    session.addEndListener(() => _handleDragEnd(session));
    _insertFeedback(session);
    sequence?.startDrag(session);
    // After the session is in flight, so it already has a path and a
    // `pathResolver`: the autoscroller reads both on its very first look, and
    // a drag picked up with the finger already in the edge band starts
    // scrolling on the next frame rather than on the next move.
    final settings = autoscroll;
    if (settings != null && settings.isEnabled) {
      _autoscroller = Drag3dAutoscroller(
        session: session,
        settings: settings,
        vsync: vsync,
      )..update();
    }
    _track();
    onDragStarted?.call();
  }

  void _insertFeedback(Drag3dSession session) {
    final builder = feedbackBuilder;
    if (builder == null) return;
    final host = overlay ?? Overlay3d.of(this);
    if (host == null) return;
    final entry = Overlay3dEntry(
      layer: feedbackLayer,
      debugLabel: 'Draggable3d feedback',
      builder: (_) {
        final feedback = IgnorePointer3d(child: builder(session));
        _feedback = feedback;
        return feedback;
      },
    );
    _feedbackEntry = entry;
    host.insertEntry(entry);
  }

  /// Moves the feedback to where the pointer is. One matrix write.
  void _track() {
    final feedback = _feedback;
    if (feedback == null) return;
    final home = _feedbackHome ??= _homeOver(this, feedback);
    final rotation = _travelToFeedback;
    if (home == null || rotation == null) return;
    feedback.nodeOffset = home + _rotate(rotation, _travel);
  }

  /// The [Layout3d.nodeOffset] that would put [feedback] over [layout].
  ///
  /// Both boxes are somewhere under one surface, so the walk between their
  /// frames is exact however either is turned: take [layout]'s centre into
  /// world space and back out into [feedback]'s own frame, and subtract
  /// [feedback]'s own centre. Null while either box is unlaid — the feedback
  /// always is on the frame it was inserted — and the caller tries again.
  ///
  /// Records the rotation between the two frames on the way past, since the
  /// inverse it needs has just been computed.
  Offset3d? _homeOver(Layout3d layout, Layout3d feedback) {
    if (!layout.hasSize || !feedback.hasSize) return null;
    final toFeedback = Matrix4.zero();
    if (toFeedback.copyInverse(feedback.worldTransform) == 0.0) return null;
    final fromLayout = layout.worldTransform;
    _travelToFeedback = toFeedback.multiplied(fromLayout);
    final centre = toFeedback.transformed3(
      fromLayout.transformed3(_centreOf(layout)),
    );
    final home = centre - _centreOf(feedback);
    // The two plane axes only, and the depth axis deliberately left alone.
    //
    // This correction exists to cancel the *overlay's alignment*: an entry is
    // placed by the overlay's own [Stack3d.alignment], which is nowhere near
    // the box the drag was picked up from, so without it the card would jump
    // to the middle of the panel at the moment it is lifted. That is a
    // question about where things sit on the plane.
    //
    // Depth is a different question and it already has an answer:
    // [OverlayLayer3d.lift] is what puts a picked-up card in front of the
    // content it is carried over. Correcting z as well would land the
    // feedback exactly on the source box in all three axes — cancelling the
    // lift, leaving the card coplanar with the rows it is dragged across, and
    // making the depth test a coin toss between two surfaces at the same z.
    // It did exactly that until `drag_feedback_depth` in
    // `examples/render_probe` caught it: the scene passed once on a
    // z-fight and failed the next run, which is the signature `stack_depth`
    // already records for coplanar geometry.
    return Offset3d(home.x, home.y, 0.0);
  }

  void _handleDragEnd(Drag3dSession session) {
    if (!identical(_session, session)) return;
    _session = null;
    // The autoscroller disposes itself through its own end listener; letting
    // go of it here only keeps a dead one from being poked by a late move.
    _autoscroller = null;
    for (final gesture in _gestures.values.toList()) {
      gesture.abandon();
    }
    _gestures.clear();
    onDragEnd?.call(session);
    if (session.wasAccepted) {
      onDragCompleted?.call();
    } else {
      onDraggableCanceled?.call(_travel);
    }
    _settleFeedback(session);
  }

  /// Runs the drop animation, then takes the feedback away.
  ///
  /// The single disposal path: every ending reaches [_releaseFeedback]
  /// through here or through [dispose], and the animation delays that
  /// removal and nothing else.
  void _settleFeedback(Drag3dSession session) {
    final feedback = _feedback;
    final home = _feedbackHome;
    if (feedback == null || home == null || _disposed) {
      _releaseFeedback();
      return;
    }
    final accepted = session.acceptedBy;
    final destination = accepted == null
        ? home
        : _homeOver(accepted, feedback) ?? home;
    _dropFrom = feedback.nodeOffset;
    _dropTo = destination;
    if (dropDuration <= Duration.zero || _dropFrom == _dropTo) {
      _releaseFeedback();
      return;
    }
    final provider = vsync;
    final ticker = _dropTicker = provider == null
        ? Ticker(_tickDrop, debugLabel: 'Draggable3d drop')
        : provider.createTicker(_tickDrop);
    ticker.start();
  }

  void _tickDrop(Duration elapsed) {
    final feedback = _feedback;
    if (feedback == null) {
      _releaseFeedback();
      return;
    }
    final t = (elapsed.inMicroseconds / dropDuration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    feedback.nodeOffset = Offset3d.lerp(
      _dropFrom,
      _dropTo,
      dropCurve.transform(t),
    );
    if (t >= 1.0) _releaseFeedback();
  }

  void _stopDropAnimation() {
    final ticker = _dropTicker;
    _dropTicker = null;
    ticker
      ?..stop(canceled: true)
      ..dispose();
  }

  /// Takes the feedback out of the overlay, which disposes what it built.
  void _releaseFeedback() {
    _stopDropAnimation();
    final entry = _feedbackEntry;
    _feedbackEntry = null;
    _feedback = null;
    _feedbackHome = null;
    _travelToFeedback = null;
    entry?.remove();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final gesture in _gestures.values.toList()) {
      gesture.abandon();
    }
    _gestures.clear();
    // Cancelling tells every target the drag has left, and its end listener
    // reaches `_settleFeedback`, which removes the entry at once rather than
    // animating it because `_disposed` is already set.
    _session?.cancel();
    _session = null;
    _releaseFeedback();
    super.dispose();
  }

  static Vector3 _centreOf(Layout3d layout) {
    final size = layout.size;
    return Vector3(size.width / 2, size.height / 2, size.depth / 2);
  }

  static Offset3d _rotate(Matrix4 matrix, Offset3d offset) {
    final rotated = matrix.rotated3(offset.toVector3());
    return Offset3d(rotated.x, rotated.y, rotated.z);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Object?>('data', data, defaultValue: null))
      ..add(DiagnosticsProperty<Drag3dStartMode>('startMode', startMode))
      ..add(FlagProperty('isDragging', value: isDragging, ifTrue: 'dragging'));
  }
}

/// One press on a [Draggable3d], competing for the pointer.
///
/// The same shape as `_Sequence` in `pointer.dart`, which is the package's
/// other hand-rolled drag recognizer: accumulate travel on one axis, compare
/// it against [computeHitSlop] taken through the tree's metrics, and resolve
/// the arena entry when it crosses. Fifty lines, and they owe Flutter's
/// recognizer classes nothing but the arena.
class _Drag3dGesture implements GestureArenaMember {
  _Drag3dGesture({
    required this.owner,
    required this.press,
    required this.kind,
    required this.metricsScale,
  });

  final Draggable3d<Object> owner;

  /// Where the press landed, in the draggable's own frame, in world units.
  final Offset3d press;

  final PointerDeviceKind kind;

  /// World units per logical pixel, so the slop can be judged in dp.
  final double metricsScale;

  PointerSequence3d? _sequence;
  GestureArenaEntry? _entry;
  Timer? _timer;

  /// How far the pointer has travelled from [press].
  Offset3d travel = Offset3d.zero;

  /// Whether this gesture holds the pointer.
  ///
  /// Not the same thing as having started a drag: a lone member wins the
  /// arena by default a microtask after the press, long before the finger has
  /// said anything.
  bool _won = false;

  bool _started = false;
  bool _dead = false;

  void begin(PointerEvent3d event) {
    _sequence = event.sequence;
    _entry = event.addArenaMember(this);
    final delay = owner.startMode.delay;
    if (delay != null) _timer = Timer(delay, _handleLongPress);
  }

  void update(PointerEvent3d event) {
    if (_dead) return;
    travel = event.localPosition - press;
    if (_started) {
      owner._travel = travel;
      owner._track();
      owner.onDragUpdate?.call(travel);
      return;
    }
    if (travel.distance < _slop) return;
    final axis = owner.axis;
    if (axis != null && travel.alongAxis(axis).abs() < _slop) {
      // Travel on some other axis. Not this draggable's gesture yet, and not
      // a reason to give up either: a finger that wanders diagonally and then
      // commits along the axis is still a drag.
      return;
    }
    if (owner.startMode.isImmediate) {
      _recognize(event.sequence);
    } else {
      // Moving before the delay is up says the press was a scroll or a swipe.
      // The pointer is left to whoever else wants it.
      _fail();
    }
  }

  void finish() {
    _timer?.cancel();
    _timer = null;
    // The drop itself belongs to `Layout3dPointer.up`, which resolves the
    // session against a last hit test before releasing it. Nothing to do here
    // but stop competing.
    if (!_started) _fail();
    _dead = true;
  }

  void abandon() {
    _timer?.cancel();
    _timer = null;
    if (!_started && !_dead) _entry?.resolve(GestureDisposition.rejected);
    _dead = true;
  }

  void _handleLongPress() {
    _timer = null;
    if (_dead || _started) return;
    _recognize(_sequence);
  }

  void _recognize(PointerSequence3d? sequence) {
    if (_started || _dead) return;
    _started = true;
    _timer?.cancel();
    _timer = null;
    // Claiming rejects every other member still in the arena, so the list
    // under the card stops scrolling and the tap that was pending cancels —
    // exactly what accepting does in Flutter. A resolution after the pointer
    // has been swept is silently dropped, which is why the long-press timer
    // is cancelled by the up.
    _entry?.resolve(GestureDisposition.accepted);
    owner._travel = travel;
    owner._startDrag(this, sequence ?? _sequence);
  }

  void _fail() {
    _timer?.cancel();
    _timer = null;
    _dead = true;
    _entry?.resolve(GestureDisposition.rejected);
  }

  /// The touch slop, in world units on the draggable's plane.
  double get _slop => computeHitSlop(kind, null) * metricsScale;

  @override
  void acceptGesture(int pointer) {
    // Won, not recognized: see [_won]. The threshold is this gesture's own
    // business and the arena has no opinion about it.
    _won = true;
  }

  @override
  void rejectGesture(int pointer) {
    _won = false;
    if (_started) return;
    _timer?.cancel();
    _timer = null;
    _dead = true;
  }

  @override
  String toString() =>
      '_Drag3dGesture(${_started ? 'dragging' : 'pending'}'
      '${_won ? ', won' : ''})';
}

/// A box that catches what a [Draggable3d] carries.
///
/// The 3D analogue of Flutter's `DragTarget`, and the generic half of
/// [Drag3dTarget]: the payload type is tested here, inside the target, rather
/// than in the machinery, which walks a path of bare [Layout3d]s and has
/// never heard of `T`.
///
/// ```dart
/// DragTarget3d<Photo>(
///   onWillAccept: (photo, _) => photo.album != album,
///   onEnter: (_, _) => panel.stateLayer = hovered,
///   onLeave: (_, _) => panel.stateLayer = StateLayer3d.none,
///   onAccept: (photo, _) {
///     panel.stateLayer = StateLayer3d.none;
///     album.add(photo);
///   },
///   child: panel,
/// )
/// ```
///
/// Every callback here is a repaint at most — a state layer, a decoration —
/// and none of them has to be. Nothing in this class touches layout.
///
/// ## Which target a drop lands on
///
/// [Drag3dEventKind.enter] and [Drag3dEventKind.leave] go to *every*
/// accepting target the ray passes through, so a list and the row inside it
/// can both light up. The drop goes to the deepest one only, which is the
/// first the ray met — the same rule a press follows, so *a drop lands where
/// a tap would land*.
///
/// The sharp edge that comes with that rule is in `docs/traps.md`:
/// `Stack3d.depthStep` does not separate children thicker than the step, so a
/// slab reaching further toward the viewer than the step can win the depth
/// test while sitting behind in the stack, and a drop then lands on what
/// looks like the back card. Keep drop targets thin relative to the step.
///
/// ## `DragTarget3d<Object>` accepts everything
///
/// Inherited from Flutter, along with the trap: `data is Object` is true of
/// every non-null payload. Name a real type, and use [onWillAccept] for the
/// conditions a type cannot express.
class DragTarget3d<T extends Object> extends ProxyLayout3dWithHitTestBehavior
    implements Drag3dTarget {
  /// Creates a drop target for payloads of type [T].
  DragTarget3d({
    this.onWillAccept,
    this.onEnter,
    this.onMove,
    this.onLeave,
    this.onAccept,
    super.behavior = HitTestBehavior3d.translucent,
    super.child,
    super.name,
  });

  /// Whether this target wants a particular payload, beyond its type.
  ///
  /// Asked afresh on every move, so an answer that depends on where the drag
  /// is — a target that only takes a drop in its top half — is legal. Null
  /// means every payload of type [T] is welcome. Keep it cheap and free of
  /// side effects.
  Drag3dWillAccept<T>? onWillAccept;

  /// Called when an acceptable drag arrives over this target.
  Drag3dTargetCallback<T>? onEnter;

  /// Called as an acceptable drag moves over this target.
  Drag3dTargetCallback<T>? onMove;

  /// Called when an acceptable drag leaves without dropping here.
  ///
  /// Including when the drag ends elsewhere: a cancel, or a drop another
  /// target took.
  Drag3dTargetCallback<T>? onLeave;

  /// Called when a payload is dropped here.
  ///
  /// Terminal, and it takes the place of [onLeave] for this target: a
  /// highlight put on by [onEnter] comes off in one of the two.
  Drag3dTargetCallback<T>? onAccept;

  final List<Drag3dSession> _candidates = <Drag3dSession>[];

  /// Whether a drag this target would take is over it now.
  ///
  /// What a highlight is driven from, if the component would rather read a
  /// flag than keep one.
  bool get isCandidate => _candidates.isNotEmpty;

  /// The payloads currently over this target, deepest pointer first.
  ///
  /// More than one only when more than one pointer is dragging at once.
  List<T> get candidateData => <T>[
    for (final session in _candidates) session.data as T,
  ];

  @override
  bool willAcceptDrag3d(Drag3dDetails details) {
    final data = details.data;
    if (data is! T) return false;
    return onWillAccept?.call(data, details) ?? true;
  }

  @override
  void handleDrag3d(Drag3dEvent event) {
    final data = event.data as T;
    switch (event.kind) {
      case Drag3dEventKind.enter:
        _candidates.add(event.session);
        onEnter?.call(data, event.details);
      case Drag3dEventKind.move:
        onMove?.call(data, event.details);
      case Drag3dEventKind.leave:
        _candidates.remove(event.session);
        onLeave?.call(data, event.details);
      case Drag3dEventKind.drop:
        _candidates.remove(event.session);
        onAccept?.call(data, event.details);
    }
  }

  @override
  void dispose() {
    _candidates.clear();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty('isCandidate', value: isCandidate, ifTrue: 'candidate'),
    );
  }
}
