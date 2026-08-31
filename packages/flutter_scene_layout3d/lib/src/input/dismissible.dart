import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        DiagnosticsProperty,
        DoubleProperty,
        EnumProperty,
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
        computeHitSlop;
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;

import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import 'events.dart';
import 'velocity.dart';

/// Which way a [Dismissible3d] may be swiped.
///
/// Named by the sign of the travel along [Dismissible3d.axis] rather than by
/// a reading direction, because there is no text direction in a layout plane
/// and "start" would be a guess. On the default horizontal axis [forward] is
/// to the right; on a vertical one it is toward increasing y, which is
/// downward in layout space.
enum Dismiss3dDirection {
  /// Swiping does nothing. The box still lays out and still answers rays.
  none,

  /// Either way along the axis.
  both,

  /// Only toward increasing coordinate. A swipe the other way is left to
  /// whatever else wants the pointer.
  forward,

  /// Only toward decreasing coordinate.
  reverse,
}

/// Asks whether a swipe that reached the threshold should really dismiss.
///
/// Answer false — or null, which reads as false, matching Flutter — and the
/// box slides back to rest instead. Awaited, so an "are you sure" dialog is a
/// legal answer; the box waits off to one side while it is open, which is
/// what Flutter's `Dismissible` does too.
typedef Dismiss3dConfirmCallback =
    Future<bool?> Function(Dismiss3dDirection direction);

/// A box that is swiped away, the 3D analogue of Flutter's `Dismissible`.
///
/// The thinnest thing built on the drag machinery, and the only one that
/// needs no drop target at all: there is no payload and nothing catches it,
/// only a threshold and what happens when the finger crosses it.
///
/// ```dart
/// Dismissible3d(
///   background: DecoratedBox3d(decoration: deleteRed),
///   onDismissed: (_) => setState(() => items.remove(item)),
///   child: row,
/// )
/// ```
///
/// ## The two animations, and why one of them is the expensive kind
///
/// A swipe is two movements that look like one, and they sit on different
/// tiers of `docs/traps.md`:
///
///  * **Following the finger, and settling back or flying out** is
///    [Layout3d.nodeOffset] on the child. One matrix write a frame, no
///    relayout, exactly as a [Draggable3d]'s feedback tracks the pointer.
///  * **The resize that follows a confirmed dismiss** is a real layout
///    animation, and deliberately so: the row is *gone*, the rows below it
///    have to close the gap, and no matrix write can express that. It is the
///    one implicit animation in the whole of drag-and-drop.
///
/// The resize is kept as cheap as an honest relayout can be. The child is
/// laid out once, with the same constraints on every tick, and hidden; only
/// this box's own extent along [axis] shrinks. So the parent relayouts —
/// which is the point — while the subtree under the swiped row never
/// re-measures a string or rebuilds a mesh.
///
/// Give [resizeDuration] as null to skip it entirely, for a caller that
/// animates the gap itself.
///
/// ## The backgrounds
///
/// [background] is shown while the swipe runs [Dismiss3dDirection.forward]
/// and [secondaryBackground] while it runs [Dismiss3dDirection.reverse],
/// falling back to [background] when there is no secondary one. Both are laid
/// out at the box's full size and are hidden at rest through
/// `node.visible`, which costs no layout — the same trick [IndexedStack3d]
/// and the scrolling views use.
///
/// The three slots are one ordered child list underneath — the child, then
/// the background, then the secondary background — because an ordered list is
/// what the widget layer can mirror onto a layout. Hence two rules the
/// constructor asserts and the setters keep: a background needs a child, and
/// a secondary background needs a background.
///
/// They are coplanar with the child, so unless the child is opaque geometry
/// standing in front of them they will fight for the depth buffer where they
/// overlap. [backgroundDepthStep] pushes them away from the viewer, and is
/// the same remedy [Stack3d.depthStep] is, with the same default of zero: a
/// figure only the scene knows is right.
///
/// ## How it competes for the pointer
///
/// Through [PointerSequence3d.addArenaMember], as its own
/// [GestureArenaMember] — the same seam a [Draggable3d] uses, and the same
/// two-part rule: winning the arena is not recognizing the gesture, because a
/// member alone in the arena wins by default a microtask after the press.
/// Recognition is travel past the touch slop, along [axis], in a direction
/// [direction] allows. Travel past the slop the *other* way rejects this
/// member, which is what lets a horizontally dismissible row live inside a
/// vertically scrolling list: each claims on its own axis, and the finger
/// decides.
class Dismissible3d extends MultiChildLayout3d<ParentData3d>
    implements HitTestTarget3d {
  /// Creates a box that can be swiped away.
  Dismissible3d({
    Layout3d? child,
    Layout3d? background,
    Layout3d? secondaryBackground,
    this.axis = Axis3d.horizontal,
    Dismiss3dDirection direction = Dismiss3dDirection.both,
    this.dismissThreshold = 0.4,
    this.flingVelocity = 700.0,
    this.movementDuration = const Duration(milliseconds: 200),
    this.resizeDuration = const Duration(milliseconds: 300),
    this.movementCurve = Curves.easeOut,
    this.resizeCurve = Curves.easeInOut,
    this.backgroundDepthStep = 0.0,
    this.behavior = HitTestBehavior3d.opaque,
    this.vsync,
    this.confirmDismiss,
    this.onUpdate,
    this.onResize,
    this.onDismissed,
    super.name,
  }) : _direction = direction,
       super(children: _slots(child, background, secondaryBackground));

  /// The slots as the ordered child list they are stored in.
  static List<Layout3d> _slots(
    Layout3d? child,
    Layout3d? background,
    Layout3d? secondaryBackground,
  ) {
    assert(
      child != null || (background == null && secondaryBackground == null),
      'Dismissible3d has nothing to swipe: a background needs a child.',
    );
    assert(
      background != null || secondaryBackground == null,
      'Dismissible3d.secondaryBackground needs a background beside it, the '
      'same rule Flutter\'s Dismissible has.',
    );
    return <Layout3d>[
      if (child != null) child,
      if (background != null) background,
      if (secondaryBackground != null) secondaryBackground,
    ];
  }

  /// What is swiped.
  Layout3d? get child => childCount > 0 ? childAt(0) : null;

  set child(Layout3d? value) {
    if (identical(child, value)) return;
    syncChildren(_slots(value, background, secondaryBackground));
  }

  /// What shows behind a [Dismiss3dDirection.forward] swipe.
  Layout3d? get background => childCount > 1 ? childAt(1) : null;

  set background(Layout3d? value) {
    if (identical(background, value)) return;
    syncChildren(_slots(child, value, secondaryBackground));
  }

  /// What shows behind a [Dismiss3dDirection.reverse] swipe, or null to use
  /// [background] for both.
  Layout3d? get secondaryBackground => childCount > 2 ? childAt(2) : null;

  set secondaryBackground(Layout3d? value) {
    if (identical(secondaryBackground, value)) return;
    syncChildren(_slots(child, background, value));
  }

  /// The axis the swipe runs along.
  ///
  /// Costs nothing to change while nothing is in flight; changing it under a
  /// live swipe leaves the offset where it was until the swipe settles.
  Axis3d axis;

  Dismiss3dDirection _direction;

  /// Which way along [axis] a swipe may go.
  Dismiss3dDirection get direction => _direction;

  set direction(Dismiss3dDirection value) {
    if (_direction == value) return;
    _direction = value;
    if (value == Dismiss3dDirection.none) cancelSwipe();
  }

  /// How far along the box the swipe must reach to count, as a fraction of
  /// the extent along [axis].
  ///
  /// Material's figure, and Flutter's default.
  double dismissThreshold;

  /// The speed above which a flick dismisses whatever distance it covered, in
  /// **logical pixels a second**.
  ///
  /// A Material figure, so it is stated in dp and taken through the tree's
  /// metrics at the moment of release, exactly as the scroll drag's fling
  /// threshold is. Flutter's `kMinFlingVelocity` is the same 700.
  double flingVelocity;

  /// How long the child takes to settle back, or to fly out.
  Duration movementDuration;

  /// How long the box takes to close up after a confirmed dismiss, or null to
  /// dismiss without resizing.
  Duration? resizeDuration;

  /// The curve the settle and the fly-out follow.
  Curve movementCurve;

  /// The curve the resize follows.
  Curve resizeCurve;

  /// How far behind the child the backgrounds are pushed, in world units.
  ///
  /// Zero by default, like [Stack3d.depthStep] and for the same reason: what
  /// separates two coplanar slabs without looking wrong depends on the scene.
  double backgroundDepthStep;

  /// How this box takes part in a hit test.
  HitTestBehavior3d behavior;

  /// The ticker provider for the two animations.
  ///
  /// Null means bare [Ticker]s, which schedule through the same
  /// [SchedulerBinding] and work outside a `State`. Give one where there is a
  /// `State` in the picture so that `TickerMode` can mute them.
  TickerProvider? vsync;

  /// Asked before a swipe past the threshold becomes a dismiss.
  Dismiss3dConfirmCallback? confirmDismiss;

  /// Called as the swipe moves, with the signed progress.
  ///
  /// A fraction of the extent along [axis]: negative for a
  /// [Dismiss3dDirection.reverse] swipe, and free to pass 1 during a fly-out.
  /// Write a decoration or a state layer from it, not a rebuild.
  ValueChanged<double>? onUpdate;

  /// Called on every tick of the resize.
  VoidCallback? onResize;

  /// Called once the box has closed up, with the way it went.
  ///
  /// The cue to take the item out of the underlying list. Until then the box
  /// is still in the tree with an extent of zero along [axis].
  ValueChanged<Dismiss3dDirection>? onDismissed;

  double _offset = 0.0;
  double _resizeFactor = 1.0;
  bool _dismissed = false;
  bool _swiping = false;

  double _moveFrom = 0.0;
  double _moveTo = 0.0;
  Ticker? _moveTicker;
  Ticker? _resizeTicker;
  VoidCallback? _onMoveComplete;

  final Map<int, _Dismiss3dGesture> _gestures = <int, _Dismiss3dGesture>{};

  /// How far the child has been carried along [axis], in world units.
  ///
  /// Not [Layout3d.offset], which is where this box's parent put it.
  double get swipeOffset => _offset;

  /// [swipeOffset] as a fraction of the extent along [axis], signed.
  double get progress {
    if (!hasSize) return 0.0;
    final extent = size.alongAxis(axis);
    return extent == 0.0 ? 0.0 : _offset / extent;
  }

  /// Whether a finger is carrying this box now.
  bool get isSwiping => _swiping;

  /// Whether the box has been dismissed and closed up.
  bool get isDismissed => _dismissed;

  /// How much of the box's own extent is left, from 1 down to 0.
  double get resizeFactor => _resizeFactor;

  // -------------------------------------------------------------- gesture

  @override
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry) {
    final raw = event.event;
    if (raw is PointerDownEvent) {
      if (_direction == Dismiss3dDirection.none || _dismissed) return;
      // A press during the settle takes over from where it is, which is what
      // makes a swipe interruptible.
      _stopMove();
      final gesture = _Dismiss3dGesture(
        owner: this,
        press: event.localPosition.alongAxis(axis),
        origin: _offset,
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

  /// Whether a swipe of this sign is allowed.
  bool allows(double travel) => switch (_direction) {
    Dismiss3dDirection.none => false,
    Dismiss3dDirection.both => true,
    Dismiss3dDirection.forward => travel > 0.0,
    Dismiss3dDirection.reverse => travel < 0.0,
  };

  /// The direction a signed travel belongs to.
  static Dismiss3dDirection _directionOf(double travel) =>
      travel < 0.0 ? Dismiss3dDirection.reverse : Dismiss3dDirection.forward;

  /// Moves the child, and nothing else. One matrix write, no layout.
  void _setOffset(double value) {
    final clamped = switch (_direction) {
      Dismiss3dDirection.none => 0.0,
      Dismiss3dDirection.both => value,
      Dismiss3dDirection.forward => value < 0.0 ? 0.0 : value,
      Dismiss3dDirection.reverse => value > 0.0 ? 0.0 : value,
    };
    if (_offset == clamped) return;
    _offset = clamped;
    _applyOffset();
    onUpdate?.call(progress);
  }

  void _applyOffset() {
    final resizing = _resizeFactor < 1.0;
    child
      ?..nodeOffset = Offset3d.zero.withAxis(axis, _offset)
      ..node.visible = !resizing;
    // The background under a swipe is the one on the side the child has moved
    // away from. At rest neither shows, so neither is drawn and neither
    // fights the child for the depth buffer; while the gap closes nothing
    // shows at all, because the row is already gone.
    final secondary = secondaryBackground;
    background?.node.visible =
        !resizing && (secondary == null ? _offset != 0.0 : _offset > 0.0);
    secondary?.node.visible = !resizing && _offset < 0.0;
  }

  /// Ends a live swipe at [velocity], in world units a second.
  void _release(double velocity, double flingThreshold) {
    _swiping = false;
    if (!hasSize) {
      _cancelSwipe();
      return;
    }
    final extent = size.alongAxis(axis);
    final double sign;
    if (velocity.abs() >= flingThreshold) {
      // A flick decides on its own, whatever distance it covered — including
      // a flick back the way it came, which outranks the distance and cancels
      // rather than dismisses. The same order Flutter resolves them in.
      sign = velocity < 0.0 ? -1.0 : 1.0;
      if (_offset != 0.0 && (_offset < 0.0) != (sign < 0.0)) {
        _cancelSwipe();
        return;
      }
    } else if (extent > 0.0 && progress.abs() >= dismissThreshold) {
      // A slow drag decides on distance, however slowly it got there.
      sign = _offset < 0.0 ? -1.0 : 1.0;
    } else {
      _cancelSwipe();
      return;
    }
    if (!allows(sign)) {
      _cancelSwipe();
      return;
    }
    _animateOffsetTo(sign * extent, then: () => _confirmAndResize(sign));
  }

  /// Slides the child back to rest, telling nobody anything.
  void _cancelSwipe() {
    _swiping = false;
    _animateOffsetTo(0.0);
  }

  /// Puts the child back at rest at once, without an animation.
  ///
  /// What a live swipe on a box that has just been told it cannot be
  /// dismissed does, and what [reset] uses.
  void cancelSwipe() {
    _stopMove();
    for (final gesture in _gestures.values.toList()) {
      gesture.abandon();
    }
    _gestures.clear();
    _swiping = false;
    _setOffset(0.0);
  }

  /// Puts a dismissed box back the way it was.
  ///
  /// Nothing calls this on its own: a dismissed item is normally taken out of
  /// the list, which disposes the box. It is here for the caller who keeps
  /// the box and undoes the dismissal instead.
  void reset() {
    cancelSwipe();
    _stopResize();
    _dismissed = false;
    if (_resizeFactor == 1.0) return;
    _resizeFactor = 1.0;
    _showChild(true);
    markNeedsLayout();
  }

  Future<void> _confirmAndResize(double sign) async {
    final direction = _directionOf(sign);
    final confirm = confirmDismiss;
    if (confirm != null) {
      final answer = await confirm(direction);
      // The tree can go away while the question is on screen, which is the
      // whole reason a confirmation is asynchronous.
      if (debugDisposed) return;
      if (answer != true) {
        _cancelSwipe();
        return;
      }
    }
    _startResize(direction);
  }

  void _startResize(Dismiss3dDirection direction) {
    if (_dismissed) return;
    // The child has been carried off the box by now, so hiding it costs
    // nothing visually and keeps it out of the hit test while the gap closes.
    _showChild(false);
    final duration = resizeDuration;
    if (duration == null || duration <= Duration.zero) {
      _finishResize(direction);
      return;
    }
    _stopResize();
    _resizeTicker = _makeTicker('Dismissible3d resize', (elapsed) {
      final t = (elapsed.inMicroseconds / duration.inMicroseconds).clamp(
        0.0,
        1.0,
      );
      _resizeFactor = 1.0 - resizeCurve.transform(t);
      markNeedsLayout();
      onResize?.call();
      if (t >= 1.0) _finishResize(direction);
    })..start();
  }

  void _finishResize(Dismiss3dDirection direction) {
    _stopResize();
    _resizeFactor = 0.0;
    _dismissed = true;
    markNeedsLayout();
    onDismissed?.call(direction);
  }

  void _showChild(bool visible) {
    child?.node.visible = visible;
    if (!visible) {
      background?.node.visible = false;
      secondaryBackground?.node.visible = false;
    }
  }

  // ----------------------------------------------------------- animation

  void _animateOffsetTo(double target, {VoidCallback? then}) {
    _stopMove();
    if (_offset == target || movementDuration <= Duration.zero) {
      _setOffset(target);
      then?.call();
      return;
    }
    _moveFrom = _offset;
    _moveTo = target;
    _onMoveComplete = then;
    final duration = movementDuration;
    _moveTicker = _makeTicker('Dismissible3d movement', (elapsed) {
      final t = (elapsed.inMicroseconds / duration.inMicroseconds).clamp(
        0.0,
        1.0,
      );
      final value = movementCurve.transform(t);
      _setOffset(_moveFrom + (_moveTo - _moveFrom) * value);
      if (t < 1.0) return;
      final done = _onMoveComplete;
      _stopMove();
      done?.call();
    })..start();
  }

  Ticker _makeTicker(String label, void Function(Duration) onTick) {
    final provider = vsync;
    return provider == null
        ? Ticker(onTick, debugLabel: label)
        : provider.createTicker(onTick);
  }

  void _stopMove() {
    final ticker = _moveTicker;
    _moveTicker = null;
    _onMoveComplete = null;
    ticker
      ?..stop(canceled: true)
      ..dispose();
  }

  void _stopResize() {
    final ticker = _resizeTicker;
    _resizeTicker = null;
    ticker
      ?..stop(canceled: true)
      ..dispose();
  }

  // -------------------------------------------------------------- layout

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      child?.getMinIntrinsicExtent(axis, limits) ?? 0.0;

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      child?.getMaxIntrinsicExtent(axis, limits) ?? 0.0;

  @override
  double? computeDistanceToActualBaseline(Axis3d axis) =>
      child?.getDistanceToBaseline(axis, onlyReal: true);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size3d.zero);
      return;
    }
    // The same constraints on every tick of the resize, deliberately: an
    // identical layout call is one the child can skip, so the shrinking box
    // never re-measures the subtree inside it.
    child.layout(constraints, parentUsesSize: true);
    final full = constraints.constrain(child.size);
    // Not re-constrained: the whole point of the resize is to report less
    // than the parent offered, and a tight constraint along the axis would
    // snap it straight back. A dismissible under a tight main-axis constraint
    // therefore closes up instantly rather than smoothly, which is honest —
    // there is no room for it to do anything else.
    size = _resizeFactor >= 1.0
        ? full
        : full.withAxis(axis, full.alongAxis(axis) * _resizeFactor);
    child.place(Offset3d.zero);
    _applyOffset();
    final backgroundConstraints = Constraints3d.tight(full);
    for (final slot in <Layout3d?>[background, secondaryBackground]) {
      if (slot == null) continue;
      slot.layout(backgroundConstraints);
      slot.parentData?.sceneOffset = Offset3d.zero.withAxis(
        Axis3d.depth,
        backgroundDepthStep,
      );
      slot.place(Offset3d.zero);
    }
  }

  @override
  bool hitTestSelf(Offset3d position) => behavior == HitTestBehavior3d.opaque;

  @override
  bool hitTestChildren(HitTestResult3d result, {required Ray3d ray}) {
    final child = this.child;
    // The backgrounds are decoration: they are behind the child, they are
    // hidden at rest, and a ray that reaches them has already passed through
    // the swiped row. Only the child answers.
    return child != null && hitTestChild(result, child, ray: ray);
  }

  /// The same walk [ProxyLayout3dWithHitTestBehavior] does, for the same
  /// reason: there is no way to say "add me anyway" through
  /// [Layout3d.hitTest], so [HitTestBehavior3d.translucent] has to be spelled
  /// out here.
  @override
  bool hitTest(HitTestResult3d result, {required Ray3d ray}) {
    if (!hasSize) return false;
    final range = ray.intersectBox(size);
    if (range == null) return false;
    final entry = ray.at(range.near);
    if (!entry.isFinite) return false;
    final inside = ray.clampedTo(range.near, range.far);
    final hit = hitTestChildren(result, ray: inside) || hitTestSelf(entry);
    if (hit || behavior == HitTestBehavior3d.translucent) {
      result.add(HitTestEntry3d(this, entry));
    }
    return hit;
  }

  @override
  void dispose() {
    for (final gesture in _gestures.values.toList()) {
      gesture.abandon();
    }
    _gestures.clear();
    _stopMove();
    _stopResize();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<Axis3d>('axis', axis))
      ..add(EnumProperty<Dismiss3dDirection>('direction', direction))
      ..add(DoubleProperty('swipeOffset', swipeOffset, defaultValue: 0.0))
      ..add(DoubleProperty('resizeFactor', resizeFactor, defaultValue: 1.0))
      ..add(FlagProperty('isSwiping', value: isSwiping, ifTrue: 'swiping'))
      ..add(
        FlagProperty('isDismissed', value: isDismissed, ifTrue: 'dismissed'),
      )
      ..add(
        DiagnosticsProperty<Duration?>(
          'resizeDuration',
          resizeDuration,
          defaultValue: const Duration(milliseconds: 300),
        ),
      );
  }
}

/// One press on a [Dismissible3d], competing for the pointer.
///
/// The same shape as `_Drag3dGesture` in `draggable.dart` and `_Sequence` in
/// `pointer.dart`, which are the package's other two hand-rolled drag
/// recognizers: accumulate travel on one axis, compare it against
/// [computeHitSlop] taken through the tree's metrics, and resolve the arena
/// entry when it crosses. What this one adds is a velocity estimate, because
/// a dismissal can be won by speed rather than by distance.
class _Dismiss3dGesture implements GestureArenaMember {
  _Dismiss3dGesture({
    required this.owner,
    required this.press,
    required this.origin,
    required this.kind,
    required this.metricsScale,
  });

  final Dismissible3d owner;

  /// Where the press landed along the axis, in the box's own frame.
  final double press;

  /// The offset the box was already carrying, so an interrupted settle is
  /// picked up from where it was rather than jumping to zero.
  final double origin;

  final PointerDeviceKind kind;

  /// World units per logical pixel, so the slop and the fling threshold can
  /// be judged in dp.
  final double metricsScale;

  final Drag3dVelocityTracker _velocity = Drag3dVelocityTracker();

  GestureArenaEntry? _entry;
  bool _started = false;
  bool _dead = false;

  void begin(PointerEvent3d event) {
    _entry = event.addArenaMember(this);
    _velocity.add(
      event.event.timeStamp,
      event.localPosition.alongAxis(owner.axis),
    );
  }

  void update(PointerEvent3d event) {
    if (_dead) return;
    final along = event.localPosition.alongAxis(owner.axis);
    _velocity.add(event.event.timeStamp, along);
    final travel = along - press;
    if (!_started) {
      if (travel.abs() < _slop) return;
      if (!owner.allows(travel)) {
        // Committed the way this box does not go. The pointer belongs to
        // whoever else wants it — the list underneath, usually.
        _fail();
        return;
      }
      _started = true;
      owner._swiping = true;
      // Claiming rejects every other member still in the arena, so the view
      // under the row stops scrolling and a pending tap cancels.
      _entry?.resolve(GestureDisposition.accepted);
    }
    owner._setOffset(origin + travel);
  }

  void finish() {
    if (!_started) {
      _fail();
      return;
    }
    _dead = true;
    owner._release(_velocity.estimate(), owner.flingVelocity * metricsScale);
  }

  void abandon() {
    if (_dead) return;
    _dead = true;
    if (!_started) {
      _entry?.resolve(GestureDisposition.rejected);
      return;
    }
    owner._cancelSwipe();
  }

  void _fail() {
    _dead = true;
    _entry?.resolve(GestureDisposition.rejected);
  }

  /// The touch slop, in world units on the box's own plane.
  double get _slop => computeHitSlop(kind, null) * metricsScale;

  @override
  void acceptGesture(int pointer) {
    // Won, not recognized: a lone member wins the arena by default a
    // microtask after the press, long before the finger has said anything.
  }

  @override
  void rejectGesture(int pointer) {
    if (_started) return;
    _dead = true;
  }

  @override
  String toString() => '_Dismiss3dGesture(${_started ? 'swiping' : 'pending'})';
}
