import 'package:flutter/foundation.dart' show VoidCallback;

import '../geometry/offset3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';

/// What happened to a drag while it was over one target.
///
/// The four moments a drop target has to distinguish. [enter] and [leave]
/// bracket the time a drag spends over a target and are the cue for a
/// highlight; [move] arrives for every position in between; [drop] is the
/// release, and it goes to one target only.
enum Drag3dEventKind {
  /// A drag this target accepts has arrived over it.
  enter,

  /// A drag this target accepts moved while over it.
  move,

  /// A drag this target accepts is no longer over it.
  ///
  /// Also what a target that was over the drag is told when the drag ends
  /// somewhere else — a cancel, or a drop that another target took.
  leave,

  /// A drag this target accepts was released over it, and this target is the
  /// one that gets it.
  ///
  /// Terminal, and it takes the place of [leave]: a target that lit up on
  /// [enter] takes the highlight off on either of the two.
  drop,
}

/// Which plane the feedback of a drag is carried on.
///
/// Separate from the question of *which target is active*, deliberately: a
/// drag can be over a target on another surface entirely while the thing
/// under the finger stays on the plane it was picked up from.
enum Drag3dAnchor {
  /// The feedback stays on the plane the drag started on.
  ///
  /// The default, and what almost every real drag wants: a reorder inside one
  /// list, a move between two lists on one panel. It needs no arithmetic
  /// beyond the plane intersection every pointer event already does, so it is
  /// exact at any camera angle.
  originPlane,

  /// The feedback re-anchors to the plane of the target it is over.
  ///
  /// So that a card visibly lands on the table it is being dropped onto.
  /// Re-anchoring moves the feedback between overlays, which is a rebuild, so
  /// it can only happen on a target change and never per move.
  ///
  /// Not implemented yet; a session asked for this behaves as
  /// [originPlane] until it is.
  targetPlane,
}

/// A box that can catch a drag, the non-generic seam under [DragTarget3d].
///
/// The same shape as [HitTestTarget3d] is under [Listener3d], and for the
/// same reason: the machinery has to find drop targets on a hit-test path of
/// bare [Layout3d]s, and it cannot be parameterised on a payload type it has
/// never heard of. So the type test happens *inside* the target — where
/// [DragTarget3d] answers [willAcceptDrag3d] with `details.data is T` — and
/// the session dispatches through this interface knowing nothing.
///
/// Implement it directly when a component wants to be a drop zone without
/// inheriting a generic class: a Material drop target whose highlight is a
/// `DecoratedBox3d.stateLayer` write is four lines over this interface, and
/// dirties no layout.
///
/// ```dart
/// class DropZone extends ProxyLayout3dWithHitTestBehavior
///     implements Drag3dTarget {
///   DropZone(this.panel) : super(behavior: HitTestBehavior3d.translucent);
///
///   final DecoratedBox3d panel;
///
///   @override
///   bool willAcceptDrag3d(Drag3dDetails details) => details.data is Photo;
///
///   @override
///   void handleDrag3d(Drag3dEvent event) {
///     panel.stateLayer = event.kind == Drag3dEventKind.enter
///         ? hovered
///         : StateLayer3d.none;
///   }
/// }
/// ```
abstract interface class Drag3dTarget {
  /// Whether this target wants the drag described by [details].
  ///
  /// Asked afresh on every move, because the answer can change with the
  /// position — a target that only takes a drop in its top half is a legal
  /// thing to build. Keep it cheap and free of side effects: it is called
  /// once per target on the path, per move, for the whole of a live drag.
  bool willAcceptDrag3d(Drag3dDetails details);

  /// Handles one moment of a drag this target said it wanted.
  ///
  /// Only ever called for a drag [willAcceptDrag3d] answered true for, so
  /// there is no need to re-check the type here.
  void handleDrag3d(Drag3dEvent event);
}

/// What is being dragged, and where it is, from one target's point of view.
///
/// Handed to [Drag3dTarget.willAcceptDrag3d] before the target has agreed to
/// anything, so it carries no promise: [data] is the payload as an
/// `Object?` and testing it is the target's job.
class Drag3dDetails {
  /// Creates the description of a drag over one target.
  const Drag3dDetails({
    required this.session,
    required this.data,
    required this.origin,
    required this.localPosition,
  });

  /// The drag this describes.
  final Drag3dSession session;

  /// The payload, as the draggable declared it.
  ///
  /// Untyped here on purpose: see [Drag3dTarget]. Null is a legal payload and
  /// a `DragTarget3d<T>` refuses it, since `null is T` is false for every
  /// non-nullable `T`.
  final Object? data;

  /// Where the drag began, on the plane it was picked up from, in world
  /// units.
  ///
  /// The *point*, not the box: a session never holds its source layout, which
  /// may be disposed under it — an item scrolled out of a lazy view's cache
  /// during a long drag is gone, and the drag still has to drop correctly.
  final Offset3d origin;

  /// Where the drag is now, in this target's own frame, in world units.
  ///
  /// Read from the hit-test entry, so it is the point the ray entered the
  /// target's box at and stays exact however the surface is turned.
  final Offset3d localPosition;

  @override
  String toString() => 'Drag3dDetails($data at $localPosition)';
}

/// One moment of a drag, delivered to one target.
class Drag3dEvent {
  /// Creates a drag event.
  const Drag3dEvent({required this.kind, required this.details});

  /// What happened.
  final Drag3dEventKind kind;

  /// What is being dragged, and where.
  final Drag3dDetails details;

  /// The drag this event belongs to.
  Drag3dSession get session => details.session;

  /// The payload being dragged.
  Object? get data => details.data;

  /// Where the drag is, in this target's own frame.
  Offset3d get localPosition => details.localPosition;

  @override
  String toString() => 'Drag3dEvent(${kind.name}, $details)';
}

/// One live drag: a payload in flight, and the targets it is passing over.
///
/// The whole of the drag-and-drop machinery that is not a component. It is
/// deliberately ignorant: it does not hit-test, does not own feedback
/// geometry, does not know what a [Draggable3d] is, and holds no reference to
/// the box the drag started on. What it does is keep the answer to one
/// question up to date — *which drop targets is this drag over, and which of
/// them wants it* — and dispatch the enter, move, leave and drop that follow
/// from a change to that answer.
///
/// Something else does the hit testing and hands the result in. On one
/// surface that is [Layout3dPointer], which re-hit-tests on every move
/// anyway; across surfaces it will be [Layout3dPointerGroup]. Either way the
/// session is driven by [update], which takes a *fresh* path — what is under
/// the pointer now, not the path the press captured. That distinction is the
/// whole of why drag-and-drop needs machinery of its own: capture governs
/// where pointer events go, and the drag search deliberately ignores capture,
/// because a drag is defined by moving away from what it started on.
///
/// A session is started by hand, which is what makes the state machine
/// testable without a pointer at all:
///
/// ```dart
/// final session = Drag3dSession(data: photo, origin: pressPoint);
/// pointer.startDrag(session);
/// // ... moves arrive, targets light up ...
/// session.drop();
/// ```
class Drag3dSession {
  /// Creates a drag carrying [data] from [origin].
  Drag3dSession({
    required this.data,
    this.origin = Offset3d.zero,
    this.anchor = Drag3dAnchor.originPlane,
    this.debugLabel,
  });

  /// The payload in flight.
  final Object? data;

  /// Where the drag began, on the plane it was picked up from.
  final Offset3d origin;

  /// Which plane the feedback is carried on.
  ///
  /// Read by whoever owns the feedback, not by the session itself.
  final Drag3dAnchor anchor;

  /// A name for this session in diagnostics.
  final String? debugLabel;

  bool _active = true;
  bool _dispatching = false;
  bool _accepted = false;
  Layout3d? _acceptedBy;

  /// The targets that accepted this drag on the last [update], deepest first.
  ///
  /// The deepest is the one a drop would go to: the first the ray met, which
  /// is the same rule a press follows, so *a drop lands where a tap would
  /// land*.
  List<HitTestEntry3d> _accepting = const <HitTestEntry3d>[];

  HitTestResult3d _lastHit = HitTestResult3d();

  final List<VoidCallback> _endListeners = <VoidCallback>[];

  /// Whether this drag is still in flight.
  ///
  /// False once [drop] or [cancel] has run. A session is single-use: a second
  /// drag is a second session.
  bool get isActive => _active;

  /// The path this session last resolved against.
  ///
  /// The fresh hit, not a captured one. Kept so that a caller which can move
  /// the world under a stationary pointer — an autoscroll tick — can ask for
  /// the answer to be recomputed without a pointer event.
  HitTestResult3d get lastHit => _lastHit;

  /// Every target the drag is currently over that wants it, deepest first.
  List<Drag3dTarget> get activeTargets => <Drag3dTarget>[
    for (final entry in _accepting) entry.layout as Drag3dTarget,
  ];

  /// The target a drop would go to, or null when the drag is over nothing
  /// that wants it.
  Drag3dTarget? get target =>
      _accepting.isEmpty ? null : _accepting.first.layout as Drag3dTarget;

  /// The box behind [target], for a caller that needs to know *where* the
  /// drop would land — a drop animation aiming the feedback at it.
  Layout3d? get targetLayout =>
      _accepting.isEmpty ? null : _accepting.first.layout;

  /// Whether the drag ended on a target that took it.
  ///
  /// False while the drag is live, and false for a cancel or a release over
  /// nothing. This and [acceptedBy] are what an end listener reads to tell a
  /// completed drag from an abandoned one; they outlive the session, which is
  /// the point of them.
  bool get wasAccepted => _accepted;

  /// The box that took the drop, or null when nothing did.
  ///
  /// Where a drop animation flies the feedback to. Held after the session has
  /// ended, unlike [targetLayout].
  Layout3d? get acceptedBy => _acceptedBy;

  /// Registers [listener] to be called once, when this session ends.
  ///
  /// Every ending goes through it: an accepted drop, a rejected one, a
  /// cancel, and the session being torn down under a disposed draggable. It
  /// is how the pointer registry and the feedback are released down one path
  /// rather than four.
  ///
  /// A listener added to a session that has already ended is called at once,
  /// so a late registration cannot leak.
  void addEndListener(VoidCallback listener) {
    if (!_active) {
      listener();
      return;
    }
    _endListeners.add(listener);
  }

  /// Removes a listener [addEndListener] registered.
  void removeEndListener(VoidCallback listener) =>
      _endListeners.remove(listener);

  /// Resolves the targets under [hit] and dispatches what changed.
  ///
  /// The one pass a live drag adds. Every entry on the path whose layout is a
  /// [Drag3dTarget] is asked [Drag3dTarget.willAcceptDrag3d]; the answers are
  /// diffed against last time, and:
  ///
  ///  * every target that stopped accepting, or that the drag left, is told
  ///    [Drag3dEventKind.leave], deepest first;
  ///  * every target that started accepting is told [Drag3dEventKind.enter],
  ///    outermost first, so a list knows before the row inside it does —
  ///    the same order hover uses, for the same reason;
  ///  * everything still accepting is told [Drag3dEventKind.move].
  ///
  /// Enter and leave go to *every* accepting target on the path rather than
  /// only the deepest, so a list and the row inside it can both light up.
  /// Only the drop is exclusive.
  ///
  /// Returns true when the set of accepting targets changed.
  bool update(HitTestResult3d hit) {
    if (!_active) return false;
    _lastHit = hit;
    final was = _accepting;
    final now = <HitTestEntry3d>[];
    for (final entry in hit.path) {
      final layout = entry.layout;
      if (layout is! Drag3dTarget) continue;
      // The cast is not redundant: `Layout3d` is a public class in another
      // library and does not promote through an interface it does not
      // declare, which is why `Layout3dPointer._deliver` spells the same
      // thing out for `HitTestTarget3d`.
      if (!(layout as Drag3dTarget).willAcceptDrag3d(_detailsFor(entry))) {
        continue;
      }
      now.add(entry);
    }
    final entered = now.where((e) => !_holds(was, e.layout)).toList();
    final left = was.where((e) => !_holds(now, e.layout)).toList();
    _accepting = now;
    _dispatchAll(left, Drag3dEventKind.leave);
    // Outermost first, matching the hover pass: the component learns the drag
    // is over it before its contents do.
    _dispatchAll(entered.reversed.toList(), Drag3dEventKind.enter);
    _dispatchAll(
      now.where((e) => !_holds(entered, e.layout)).toList(),
      Drag3dEventKind.move,
    );
    return entered.isNotEmpty || left.isNotEmpty;
  }

  /// Recomputes the answer against the path this session last saw.
  ///
  /// For a caller that changed the world without moving the pointer: a view
  /// that autoscrolled under a stationary finger is over a different row than
  /// it was a frame ago, and nothing but this will notice.
  bool refresh() => update(_lastHit);

  /// Releases the drag onto the deepest target that wants it.
  ///
  /// The drop is exclusive: one target gets [Drag3dEventKind.drop] and every
  /// other target the drag was over gets [Drag3dEventKind.leave]. Ends the
  /// session either way.
  ///
  /// Returns true when a target took it, which is the caller's cue that this
  /// was a completed drag rather than a cancelled one.
  bool drop() {
    if (!_active) return false;
    final accepting = _accepting;
    _accepting = const <HitTestEntry3d>[];
    if (accepting.isEmpty) {
      _end();
      return false;
    }
    _dispatchAll(accepting.skip(1).toList(), Drag3dEventKind.leave);
    _accepted = true;
    _acceptedBy = accepting.first.layout;
    _dispatch(accepting.first, Drag3dEventKind.drop);
    _end();
    return true;
  }

  /// Abandons the drag, telling every target it was over that it has left.
  ///
  /// Safe to call twice, and safe to call on a session that never reached a
  /// target: what a cancelled pointer, a disposed draggable and a torn-down
  /// pointer all call.
  void cancel() {
    if (!_active) return;
    final accepting = _accepting;
    _accepting = const <HitTestEntry3d>[];
    _dispatchAll(accepting, Drag3dEventKind.leave);
    _end();
  }

  Drag3dDetails _detailsFor(HitTestEntry3d entry) => Drag3dDetails(
    session: this,
    data: data,
    origin: origin,
    localPosition: entry.localPosition,
  );

  void _dispatchAll(List<HitTestEntry3d> entries, Drag3dEventKind kind) {
    for (final entry in entries) {
      _dispatch(entry, kind);
    }
  }

  void _dispatch(HitTestEntry3d entry, Drag3dEventKind kind) {
    final target = entry.layout;
    if (target is! Drag3dTarget) return;
    // A target is free to change the tree it is in — a drop that removes the
    // row it landed on is an ordinary thing for a list to do — so re-entrancy
    // has to be survivable rather than merely unlikely. The flag keeps a
    // target that ends the session from its own handler out of a second pass.
    final wasDispatching = _dispatching;
    _dispatching = true;
    try {
      (target as Drag3dTarget).handleDrag3d(
        Drag3dEvent(kind: kind, details: _detailsFor(entry)),
      );
    } finally {
      _dispatching = wasDispatching;
    }
  }

  void _end() {
    _active = false;
    _lastHit = HitTestResult3d();
    final listeners = List<VoidCallback>.of(_endListeners);
    _endListeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  static bool _holds(List<HitTestEntry3d> entries, Layout3d layout) {
    for (final entry in entries) {
      if (identical(entry.layout, layout)) return true;
    }
    return false;
  }

  @override
  String toString() {
    final label = debugLabel == null ? '' : '$debugLabel, ';
    return 'Drag3dSession($label$data, ${_accepting.length} target(s)'
        '${_active ? '' : ', ended'})';
  }
}
