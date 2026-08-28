import 'dart:ui' show Offset;

import 'package:flutter/gestures.dart'
    show
        GestureArenaEntry,
        GestureArenaMember,
        GestureBinding,
        GestureDisposition,
        GestureRecognizer,
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerEnterEvent,
        PointerEvent,
        PointerExitEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerUpEvent,
        computeHitSlop,
        kMaxFlingVelocity,
        kMinFlingVelocity,
        kPrimaryButton;
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;
import 'package:vector_math/vector_math_64.dart' as vm64 show Matrix4;

import '../geometry/offset3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import '../scroll/scrollable.dart';
import '../surface.dart';
import 'events.dart';

/// A pointer aimed at a layout surface: hit testing, event dispatch, gesture
/// recognition, hover, and the drag that scrolls what it grabbed.
///
/// Feed it the ray the camera makes from a screen position and call [down],
/// [move], [up] and [hover] as the events arrive:
///
/// ```dart
/// Listener(
///   onPointerDown: (event) => pointer.down(rayFor(event), pointer: event.pointer),
///   onPointerMove: (event) => pointer.move(rayFor(event), pointer: event.pointer),
///   onPointerUp: (event) => pointer.up(pointer: event.pointer),
///   onPointerHover: (event) => pointer.hover(rayFor(event), pointer: event.pointer),
///   child: SceneView(scene: scene, camera: camera),
/// )
///
/// Ray rayFor(PointerEvent event) =>
///     camera.screenPointToRay(event.localPosition, viewSize);
/// ```
///
/// ## What it does with a press
///
/// The chain is hit test, dispatch, recognition, state, and each step is
/// separable. [down] hit-tests once and **captures the path**; every later
/// event of that sequence is delivered along the captured path rather than
/// re-tested, which is the ordinary pointer-capture rule and the reason
/// sliding off the end of a list does not drop the drag. Every layout on the
/// path that implements [HitTestTarget3d] is handed the event, deepest first.
///
/// Positions come in two currencies. [PointerEvent3d.localPosition] is world
/// units on the target's own plane, measured by intersecting the ray with the
/// plane the press landed on, so the content stays under the finger whatever
/// angle the surface is seen from. [PointerEvent3d.event] is a real Flutter
/// [PointerEvent] in **logical pixels**, taken through the tree's
/// [Layout3dMetrics]: that is what lets Flutter's own recognizers, tuned in
/// logical pixels, be used unchanged — a `kTouchSlop` of 18 means 18dp on the
/// plane rather than 18 world units, which would be most of a panel.
///
/// ## Several pointers
///
/// State is keyed by the `pointer` id the caller passes, so two fingers on
/// two lists scroll them independently, and a mouse and a VR controller can
/// coexist. Pass the device's own id (`event.pointer`); the default of zero
/// is the single-pointer case.
///
/// ## Its relationship to `ScenePointer`
///
/// flutter_scene's `ScenePointer` solves capture, hover and occlusion for
/// *widget surfaces*: rectangles of Flutter UI pasted into the scene, where
/// the thing under the pointer is a texture with its own event loop. This
/// stays parallel to it rather than being built on it, because the two answer
/// different questions — `ScenePointer` decides which surface a screen point
/// belongs to and hands the event to Flutter, while this one walks a layout
/// tree that has no widgets in it and dispatches in three dimensions. A scene
/// that has both should let `ScenePointer` test first: a widget surface is
/// opaque, and a ray that reached one never needed to reach the layout below
/// it.
///
/// ## What it needs
///
/// Recognition uses Flutter's own [GestureBinding]: its arena and its pointer
/// router, because [GestureRecognizer] reaches for `GestureBinding.instance`
/// directly and cannot be pointed at a private one. So a tree with a
/// [GestureDetector3d] in it needs the binding initialized —
/// `WidgetsFlutterBinding.ensureInitialized()`, which `runApp` has already
/// done, or `TestWidgetsFlutterBinding.ensureInitialized()` in a test.
/// Hit testing, dispatch, hover and the plain scroll drag need nothing.
class Layout3dPointer {
  /// Creates a pointer into [surface].
  Layout3dPointer(this.surface);

  /// The surface this pointer tests against.
  final Layout3dSurface surface;

  final Map<int, _Sequence> _sequences = <int, _Sequence>{};
  final Map<int, _Hover> _hovers = <int, _Hover>{};

  final Stopwatch _clock = Stopwatch()..start();

  HitTestResult3d _lastHit = HitTestResult3d();

  /// What the last [hitTest], [down], [move] or [hover] found.
  ///
  /// A fresh hit test, so during a drag it is *not* the captured path: it is
  /// what is under the pointer now. Ask [pathFor] for the captured one.
  HitTestResult3d get lastHit => _lastHit;

  /// The view the pointer with this id is dragging, or null.
  Scrollable3d? draggedScrollableFor(int pointer) =>
      _sequences[pointer]?.scrollable;

  /// The view this pointer is dragging, or null.
  ///
  /// The single-pointer reading of [draggedScrollableFor]: the first sequence
  /// that has a view in hand.
  Scrollable3d? get draggedScrollable {
    for (final sequence in _sequences.values) {
      final scrollable = sequence.scrollable;
      if (scrollable != null) return scrollable;
    }
    return null;
  }

  /// Whether any pointer is dragging a scrolling view.
  bool get isDragging => draggedScrollable != null;

  /// The path the pointer with this id captured at [down], or null when it is
  /// not down.
  HitTestResult3d? pathFor(int pointer) => _sequences[pointer]?.hit;

  /// Whether the pointer with this id is down on this surface.
  bool isDown(int pointer) => _sequences.containsKey(pointer);

  /// What the pointers hovering this surface are over, deepest first.
  ///
  /// Empty for a pointer that is not hovering, which is every pointer until
  /// [hover] is called.
  List<Layout3d> hoveredFor(int pointer) =>
      _hovers[pointer]?.path.map((entry) => entry.layout).toList() ??
      const <Layout3d>[];

  /// What [worldRay] hits, without touching any sequence state.
  HitTestResult3d hitTest(Ray worldRay) =>
      _lastHit = surface.hitTestRay(worldRay);

  /// Starts a press along [worldRay].
  ///
  /// Captures the path, dispatches a [PointerDownEvent] along it deepest
  /// first, and grabs the nearest scrolling view if there is one. Returns
  /// true when it grabbed a view, which is the caller's cue that later moves
  /// mean something. A press that hits nothing dispatches nothing and clears
  /// [lastHit].
  ///
  /// [pointer] is the device's pointer id and keys everything this sequence
  /// owns. The id Flutter's gesture arena sees is *not* this one: a private
  /// id is allocated per sequence, well above the range the engine's own
  /// pointer ids reach, so that a synthesized sequence on the plane cannot
  /// collide in the arena with the real pointer that produced it — the
  /// enclosing widget tree is still handling that one.
  bool down(
    Ray worldRay, {
    int pointer = 0,
    PointerDeviceKind kind = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
    Duration? timeStamp,
  }) {
    cancel(pointer: pointer);
    final hit = hitTest(worldRay);
    if (hit.isEmpty) return false;
    final sequence = _Sequence(
      owner: this,
      devicePointer: pointer,
      hit: hit,
      kind: kind,
      buttons: buttons,
    );
    _sequences[pointer] = sequence;
    sequence.begin(worldRay, timeStamp ?? _clock.elapsed);
    return sequence.scrollable != null;
  }

  /// Continues the press along [worldRay].
  ///
  /// Dispatches a [PointerMoveEvent] along the captured path, routes it to
  /// whatever recognizers are competing, and moves the grabbed view. Returns
  /// true when the scroll position moved, which is what it has always
  /// reported; false means nothing was grabbed, the drag has not been claimed
  /// yet, or the ray now runs parallel to the grabbed view's plane and there
  /// is no sensible place to say the pointer is.
  bool move(Ray worldRay, {int pointer = 0, Duration? timeStamp}) {
    final sequence = _sequences[pointer];
    if (sequence == null) return false;
    _lastHit = surface.hitTestRay(worldRay);
    return sequence.move(worldRay, timeStamp ?? _clock.elapsed);
  }

  /// Ends the press, dispatching a [PointerUpEvent] and sweeping the arena.
  ///
  /// Safe to call when nothing was grabbed. [worldRay] is optional and only
  /// sharpens the last position reported; without it the pointer is taken to
  /// have stayed where it was.
  void up({Ray? worldRay, int pointer = 0, Duration? timeStamp}) {
    final sequence = _sequences.remove(pointer);
    sequence?.end(worldRay, timeStamp ?? _clock.elapsed);
  }

  /// Abandons the press, dispatching a [PointerCancelEvent].
  ///
  /// The sequence is dropped without any gesture being recognized: what a
  /// host calls when the platform takes the pointer away, and what [down]
  /// calls on itself when a pointer goes down twice without coming up.
  void cancel({int pointer = 0, Duration? timeStamp}) {
    final sequence = _sequences.remove(pointer);
    sequence?.abandon(timeStamp ?? _clock.elapsed);
  }

  /// Moves an unpressed pointer to [worldRay], emitting enter and exit along
  /// the way.
  ///
  /// The pass that drives hover state layers. It hit-tests afresh — hover has
  /// nothing captured — diffs the path against the one this pointer was on
  /// last time, and dispatches [PointerExitEvent] to the boxes it left
  /// (deepest first) and [PointerEnterEvent] to the boxes it entered
  /// (outermost first, so a card knows before its label does). Everything
  /// still under the pointer is then handed a [PointerHoverEvent].
  ///
  /// Returns true when the set of boxes under the pointer changed.
  bool hover(Ray worldRay, {int pointer = 0, Duration? timeStamp}) {
    final hit = hitTest(worldRay);
    return _updateHover(
      pointer,
      hit.path,
      worldRay,
      timeStamp ?? _clock.elapsed,
    );
  }

  /// Takes a hovering pointer off the surface entirely.
  ///
  /// Dispatches [PointerExitEvent] to everything it was over. Call it when
  /// the pointer leaves the view, or when the ray stops being aimed at this
  /// surface because something else took it.
  void exit({int pointer = 0, Duration? timeStamp}) {
    _updateHover(
      pointer,
      const <HitTestEntry3d>[],
      null,
      timeStamp ?? _clock.elapsed,
    );
    _hovers.remove(pointer);
  }

  /// Drops every sequence and every hover, dispatching cancels and exits.
  ///
  /// A pointer holds no resources of its own, but a sequence holds an arena
  /// entry and a box may be wearing a pressed state layer because of it.
  void dispose() {
    for (final pointer in _sequences.keys.toList()) {
      cancel(pointer: pointer);
    }
    for (final pointer in _hovers.keys.toList()) {
      exit(pointer: pointer);
    }
  }

  bool _updateHover(
    int devicePointer,
    List<HitTestEntry3d> path,
    Ray? worldRay,
    Duration timeStamp,
  ) {
    final previous = _hovers[devicePointer];
    final id = previous?.arenaPointer ?? _allocateArenaPointer();
    final was = previous?.path ?? const <HitTestEntry3d>[];
    final now = path;
    final entered = now.where((e) => !_holds(was, e.layout)).toList();
    final left = was.where((e) => !_holds(now, e.layout)).toList();
    if (now.isEmpty) {
      _hovers.remove(devicePointer);
    } else {
      _hovers[devicePointer] = _Hover(arenaPointer: id, path: now);
    }
    for (final entry in left) {
      _deliver(
        entry,
        PointerExitEvent(pointer: id, timeStamp: timeStamp),
        worldRay,
        entry.localPosition.z,
      );
    }
    // Outermost first: a component learns the pointer is over it before the
    // label inside it does, which is the order a state layer wants.
    for (final entry in entered.reversed) {
      _deliver(
        entry,
        PointerEnterEvent(pointer: id, timeStamp: timeStamp),
        worldRay,
        entry.localPosition.z,
      );
    }
    if (worldRay != null) {
      for (final entry in now) {
        _deliver(
          entry,
          PointerHoverEvent(pointer: id, timeStamp: timeStamp),
          worldRay,
          entry.localPosition.z,
        );
      }
    }
    return entered.isNotEmpty || left.isNotEmpty;
  }

  /// Hands one already-built Flutter event to one target, filling in the
  /// three-dimensional half around it, and reports the local position it
  /// used.
  ///
  /// [fallback] is where the pointer was on this box last time, for an event
  /// no ray stands behind: an up without one says the pointer is where it
  /// got to, not where it was pressed.
  Offset3d? _deliver(
    HitTestEntry3d entry,
    PointerEvent event,
    Ray? worldRay,
    double depth, {
    PointerSequence3d? sequence,
    Offset? globalPosition,
    Offset3d? fallback,
  }) {
    final target = entry.layout;
    if (target is! HitTestTarget3d) return null;
    final scale = surface.metrics.unitsPerLogicalPixel;
    final localRay = worldRay == null ? null : localRayFor(target, worldRay);
    final position =
        (localRay == null ? null : pointOnPlane(localRay, depth)) ??
        fallback ??
        entry.localPosition;
    final local = Offset(position.x / scale, position.y / scale);
    final global = globalPosition ?? local;
    (target as HitTestTarget3d).handleEvent(
      PointerEvent3d(
        event: _place(event, global, local),
        entry: entry,
        localPosition: position,
        metricsScale: scale,
        ray: localRay,
        sequence: sequence,
      ),
      entry,
    );
    return position;
  }

  /// [event] moved to [global] and transformed so its local position is
  /// [local].
  ///
  /// The transform is what a recognizer picks up from
  /// `PointerDownEvent.transform` and registers with the pointer router, so
  /// that every later event it is routed reports positions in this target's
  /// frame. It is the translation between the two frames at the moment of the
  /// event, which is exact for a box parallel to the surface — every box is,
  /// unless a `Transform3d` turned one — and drifts for a box seen at an
  /// angle. A control that needs the exact point in its own frame at any
  /// angle reads [PointerEvent3d.localPosition], which is computed from the
  /// ray every time.
  static PointerEvent _place(PointerEvent event, Offset global, Offset local) {
    final moved = event.copyWith(position: global);
    if (local == global) return moved;
    return moved.transformed(
      vm64.Matrix4.translationValues(
        local.dx - global.dx,
        local.dy - global.dy,
        0.0,
      ),
    );
  }

  static bool _holds(List<HitTestEntry3d> path, Layout3d layout) {
    for (final entry in path) {
      if (identical(entry.layout, layout)) return true;
    }
    return false;
  }

  /// [worldRay] in [layout]'s own frame, or null when the box's transform
  /// cannot be inverted (a subtree scaled to nothing).
  static Ray3d? localRayFor(Layout3d layout, Ray worldRay) {
    final toLayout = Matrix4.zero();
    if (toLayout.copyInverse(layout.worldTransform) == 0.0) return null;
    final origin = toLayout.transformed3(Vector3.copy(worldRay.origin));
    final direction = toLayout.rotated3(Vector3.copy(worldRay.direction));
    return Ray3d(
      Offset3d(origin.x, origin.y, origin.z),
      Offset3d(direction.x, direction.y, direction.z),
    );
  }

  /// Where [ray] crosses the plane at [depth] in its own frame, or null when
  /// it runs parallel to it.
  ///
  /// The plane is the one the press happened on, so a drag that wanders off
  /// the box, or off the surface entirely, still resolves to a position the
  /// box can be driven by.
  static Offset3d? pointOnPlane(Ray3d ray, double depth) {
    if (ray.direction.z.abs() < _parallel) return null;
    final t = (depth - ray.origin.z) / ray.direction.z;
    if (!t.isFinite || t < 0.0) return null;
    return ray.at(t);
  }

  /// The next private arena pointer id.
  ///
  /// Well above anything the engine hands out: real ids come from Flutter's
  /// pointer-event converter counting up from one, so nothing on a real
  /// device reaches sixteen million. The arena is global — recognizers reach
  /// for `GestureBinding.instance` themselves — and this is what keeps a
  /// gesture on the plane from colliding with the widget-level gesture the
  /// same finger is driving.
  static int _allocateArenaPointer() => _nextArenaPointer++;

  static int _nextArenaPointer = 1 << 24;

  static const double _parallel = 1e-9;
}

/// What a pointer that is hovering is over.
class _Hover {
  _Hover({required this.arenaPointer, required this.path});

  final int arenaPointer;
  final List<HitTestEntry3d> path;
}

/// One press, from [Layout3dPointer.down] to the up or cancel that ends it.
///
/// It is three things at once, and deliberately so: the captured path events
/// are dispatched along, the [PointerSequence3d] a target competes for the
/// pointer through, and the [GestureArenaMember] standing for the scroll
/// drag — which is what lets a drag on a list lose to a tap on one of its
/// items.
class _Sequence implements PointerSequence3d, GestureArenaMember {
  _Sequence({
    required this.owner,
    required this.devicePointer,
    required this.hit,
    required this.kind,
    required this.buttons,
  }) : arenaPointer = Layout3dPointer._allocateArenaPointer();

  final Layout3dPointer owner;
  final int devicePointer;

  /// The path captured at the press. Reused for every later event.
  final HitTestResult3d hit;

  final PointerDeviceKind kind;
  final int buttons;

  @override
  final int arenaPointer;

  bool _contested = false;

  @override
  bool get isContested => _contested;

  /// The depth, in each box's own frame, of the point the press landed on.
  ///
  /// One per entry on the path, and the plane every later position for that
  /// box is measured on.
  final Map<Layout3d, double> _depths = <Layout3d, double>{};

  /// Where the pointer was on each target last time, so an event with no ray
  /// behind it reports the last position rather than the press.
  final Map<Layout3d, Offset3d> _lastLocal = <Layout3d, Offset3d>{};

  double _surfaceDepth = 0.0;
  Offset _global = Offset.zero;

  // ------------------------------------------------------------- the drag

  Scrollable3d? _scrollable;
  Layout3d? _scrollLayout;
  Axis3d _dragAxis = Axis3d.vertical;
  double _dragDepth = 0.0;
  double _lastAlong = 0.0;
  double _pending = 0.0;
  bool _dragAccepted = false;
  GestureArenaEntry? _arenaEntry;

  /// Where the pointer has been on the grabbed view's plane, so a release can
  /// be given a speed.
  ///
  /// Not Flutter's `VelocityTracker`, which reads the gesture binding's
  /// sampling clock and so only works inside a widget test; this one is fed
  /// the timestamps the caller already passes to [Layout3dPointer.move], on
  /// the one axis that can move the view. See [_DragVelocity].
  _DragVelocity? _velocity;

  /// The view this press grabbed, or null.
  Scrollable3d? get scrollable => _scrollable;

  void begin(Ray worldRay, Duration timeStamp) {
    for (final entry in hit.path) {
      _depths[entry.layout] = entry.localPosition.z;
    }
    final surfaceEntry = hit.entryOf<Layout3dSurface>();
    _surfaceDepth = surfaceEntry?.localPosition.z ?? 0.0;
    _global = _globalFor(worldRay) ?? Offset.zero;
    final event = PointerDownEvent(
      pointer: arenaPointer,
      kind: kind,
      buttons: buttons,
      position: _global,
      timeStamp: timeStamp,
    );
    _dispatch(event, worldRay);
    _armDrag(worldRay, timeStamp);
    if (_contested) {
      // The down goes to the router as well as to the path, and after it,
      // exactly as `GestureBinding.handleEvent` does: a recognizer is armed
      // while the path is being walked, and several of them
      // (`LongPressGestureRecognizer` among them) learn where the press was
      // from the routed down rather than from `addPointer`.
      GestureBinding.instance.pointerRouter.route(event);
      GestureBinding.instance.gestureArena.close(arenaPointer);
    }
  }

  bool move(Ray worldRay, Duration timeStamp) {
    final global = _globalFor(worldRay) ?? _global;
    final delta = global - _global;
    _global = global;
    final event = PointerMoveEvent(
      pointer: arenaPointer,
      kind: kind,
      buttons: buttons,
      position: global,
      delta: delta,
      timeStamp: timeStamp,
    );
    _dispatch(event, worldRay);
    if (_contested) GestureBinding.instance.pointerRouter.route(event);
    return _dragTo(worldRay, timeStamp);
  }

  void end(Ray? worldRay, Duration timeStamp) {
    final global = (worldRay == null ? null : _globalFor(worldRay)) ?? _global;
    _global = global;
    final event = PointerUpEvent(
      pointer: arenaPointer,
      kind: kind,
      position: global,
      timeStamp: timeStamp,
    );
    _dispatch(event, worldRay);
    if (_contested) {
      GestureBinding.instance.pointerRouter.route(event);
      GestureBinding.instance.gestureArena.sweep(arenaPointer);
    }
    _releaseDrag();
  }

  void abandon(Duration timeStamp) {
    final event = PointerCancelEvent(
      pointer: arenaPointer,
      kind: kind,
      position: _global,
      timeStamp: timeStamp,
    );
    _dispatch(event, null);
    if (_contested) GestureBinding.instance.pointerRouter.route(event);
    _arenaEntry?.resolve(GestureDisposition.rejected);
    // A cancelled press is not a throw, whatever the finger was doing when
    // the platform took the pointer away.
    _velocity = null;
    _releaseDrag();
  }

  // ------------------------------------------------------------- dispatch

  void _dispatch(PointerEvent event, Ray? worldRay) {
    // A copy, because a target is free to change the tree it is in — a press
    // that removes the box it landed on is a normal thing for a control to
    // do — and the path is what we are walking.
    for (final entry in List<HitTestEntry3d>.of(hit.path)) {
      final layout = entry.layout;
      final position = owner._deliver(
        entry,
        event,
        worldRay,
        _depths[layout] ?? entry.localPosition.z,
        sequence: this,
        globalPosition: _global,
        fallback: _lastLocal[layout],
      );
      if (position != null) _lastLocal[layout] = position;
    }
  }

  @override
  void addPointerToRecognizer(
    GestureRecognizer recognizer,
    PointerDownEvent event,
  ) {
    _contested = true;
    recognizer.addPointer(event);
  }

  Offset? _globalFor(Ray worldRay) {
    final ray = Layout3dPointer.localRayFor(owner.surface, worldRay);
    if (ray == null) return null;
    final point = Layout3dPointer.pointOnPlane(ray, _surfaceDepth);
    if (point == null) return null;
    final scale = owner.surface.metrics.unitsPerLogicalPixel;
    return Offset(point.x / scale, point.y / scale);
  }

  // ----------------------------------------------------------- the drag

  /// Takes hold of the nearest scrolling view on the path.
  ///
  /// When nothing else wants the pointer the drag starts at once, which is
  /// what a list under a finger has always done here. When something does —
  /// a `GestureDetector3d` armed a recognizer while the down was being
  /// dispatched — the view instead enters the arena and waits for the touch
  /// slop before claiming the pointer, so a tap on a list item is a tap.
  void _armDrag(Ray worldRay, Duration timeStamp) {
    final entry = hit.entryOf<Scrollable3d>();
    if (entry == null) return;
    final scrollable = entry.layout as Scrollable3d;
    _scrollable = scrollable;
    _scrollLayout = entry.layout;
    _dragAxis = scrollable.scrollAxis;
    _dragDepth = entry.localPosition.z;
    _lastAlong = entry.localPosition.alongAxis(_dragAxis);
    // Taking hold stops whatever was moving the view, before the arena has
    // decided anything: a finger landing on a flinging list stops it dead,
    // and it does so even if the gesture turns out to be a tap.
    scrollable.controller.beginUserScroll();
    _velocity = _DragVelocity()..add(timeStamp, _lastAlong);
    if (!_contested) {
      _dragAccepted = true;
      return;
    }
    _arenaEntry = GestureBinding.instance.gestureArena.add(arenaPointer, this);
  }

  bool _dragTo(Ray worldRay, Duration timeStamp) {
    final layout = _scrollLayout;
    if (layout == null) return false;
    final ray = Layout3dPointer.localRayFor(layout, worldRay);
    if (ray == null) return false;
    final position = Layout3dPointer.pointOnPlane(ray, _dragDepth);
    if (position == null) return false;
    final along = position.alongAxis(_dragAxis);
    _velocity?.add(timeStamp, along);
    final delta = along - _lastAlong;
    _lastAlong = along;
    if (delta == 0.0) return false;
    if (!_dragAccepted) {
      _pending += delta;
      final slop =
          computeHitSlop(kind, null) *
          owner.surface.metrics.unitsPerLogicalPixel;
      if (_pending.abs() < slop) return false;
      // Past the slop the view claims the pointer, which rejects every
      // recognizer still in the arena: the tap that was pending becomes a
      // cancel, exactly as it does in Flutter.
      _arenaEntry?.resolve(GestureDisposition.accepted);
      // Accepting applied the whole travel, slop included.
      return _dragAccepted;
    }
    return _apply(delta);
  }

  /// Moves the grabbed view by [delta], measured on its own plane.
  ///
  /// Dragging the content one way moves the window the other way, the same
  /// sense as a finger on a Flutter list.
  bool _apply(double delta) {
    if (delta == 0.0) return false;
    final controller = _scrollable?.controller;
    if (controller == null) return false;
    final before = controller.offset;
    // Through the physics rather than straight onto the offset, so a
    // bouncing view drags less and less the further past its end it is
    // pulled.
    controller.applyUserOffset(-delta);
    return controller.offset != before;
  }

  @override
  void acceptGesture(int pointer) {
    if (_dragAccepted) return;
    _dragAccepted = true;
    final pending = _pending;
    _pending = 0.0;
    // The whole travel since the press, slop included: the content ends up
    // where the finger is rather than a slop's worth behind it.
    _apply(pending);
  }

  @override
  void rejectGesture(int pointer) {
    _dragAccepted = false;
    // The hold taken at the press is given back, with no speed: something
    // else won the pointer, so the view should sit where it is rather than
    // fling.
    _scrollable?.controller.endUserScroll();
    _scrollable = null;
    _scrollLayout = null;
    _velocity = null;
    _pending = 0.0;
  }

  /// The speed the view should be let go at, in layout units per second.
  ///
  /// Flutter's thresholds are in logical pixels a second and this package's
  /// distances are in world units, so the estimate is taken through the
  /// tree's metrics to be judged and clamped, then brought back. A flick
  /// under [kMinFlingVelocity] is not a fling at all and releases at rest.
  double _releaseVelocity() {
    final tracker = _velocity;
    if (tracker == null || !_dragAccepted) return 0.0;
    final units = tracker.estimate();
    final pixels = units * owner.surface.metrics.logicalPixelsPerUnit;
    if (pixels.abs() < kMinFlingVelocity) return 0.0;
    final clamped = pixels.clamp(-kMaxFlingVelocity, kMaxFlingVelocity);
    // Dragging the content one way throws the window the other way, the same
    // inversion `_apply` makes.
    return -clamped * owner.surface.metrics.unitsPerLogicalPixel;
  }

  void _releaseDrag() {
    _arenaEntry = null;
    _scrollable?.controller.endUserScroll(velocity: _releaseVelocity());
    _scrollable = null;
    _scrollLayout = null;
    _velocity = null;
  }

  @override
  String toString() =>
      '_Sequence(pointer $devicePointer as $arenaPointer, '
      '${hit.path.length} deep${_contested ? ', contested' : ''})';
}

/// A one-dimensional velocity estimate over the last stretch of a drag.
///
/// Flutter's `VelocityTracker` cannot be used here. It timestamps its own
/// samples from `GestureBinding.instance.samplingClock`, which in a test
/// binding asserts that a widget test is running — and this package's pointer
/// is driven from plain `test` cases, and in an application from whatever
/// clock the host has. Every position this sees already comes with the
/// timestamp the caller handed [Layout3dPointer.move], so the tracker only
/// has to do the arithmetic.
///
/// A straight least-squares fit over the samples inside [_horizon], which is
/// enough for a fling: the curve a finger draws in the last tenth of a second
/// before it lifts is close enough to a line that a quadratic fit buys
/// nothing a scroll position can feel.
class _DragVelocity {
  static const Duration _horizon = Duration(milliseconds: 100);

  /// Fewer samples than this is not a gesture with a direction.
  static const int _minSamples = 3;

  /// Samples spanning less time than this cannot be trusted.
  ///
  /// Two positions a few microseconds apart divide into an enormous speed,
  /// and that is exactly what a synthesized drag looks like when the caller
  /// leaves the timestamps to the wall clock — a whole gesture inside one
  /// millisecond. Below this the release is treated as being at rest, so a
  /// test that wants a fling passes real timestamps, which is also what a
  /// real pointer does.
  static const Duration _minSpan = Duration(milliseconds: 2);

  final List<Duration> _times = <Duration>[];
  final List<double> _positions = <double>[];

  void add(Duration time, double position) {
    _times.add(time);
    _positions.add(position);
    while (_times.length > 1 && time - _times.first > _horizon) {
      _times.removeAt(0);
      _positions.removeAt(0);
    }
  }

  /// The speed the pointer was moving at, in layout units per second, or zero
  /// when there is not enough to say.
  double estimate() {
    final count = _times.length;
    if (count < _minSamples) return 0.0;
    final span = _times.last - _times.first;
    if (span < _minSpan) return 0.0;
    final origin = _times.first;
    var sumT = 0.0;
    var sumP = 0.0;
    var sumTT = 0.0;
    var sumTP = 0.0;
    for (var i = 0; i < count; i++) {
      final t =
          (_times[i] - origin).inMicroseconds / Duration.microsecondsPerSecond;
      final p = _positions[i];
      sumT += t;
      sumP += p;
      sumTT += t * t;
      sumTP += t * p;
    }
    final denominator = count * sumTT - sumT * sumT;
    if (denominator == 0.0) return 0.0;
    return (count * sumTP - sumT * sumP) / denominator;
  }
}
