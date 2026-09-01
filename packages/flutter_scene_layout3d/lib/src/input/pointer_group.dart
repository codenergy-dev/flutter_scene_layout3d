import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter_scene/scene.dart' show Camera;
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;

import '../hit_test.dart';
import '../overlay/overlay.dart';
import '../surface.dart';
import 'drag.dart';
import 'pointer.dart';

/// One surface in a [Layout3dPointerGroup], and where it stands.
class _Member {
  _Member({
    required this.pointer,
    required this.zOrder,
    required this.absorbs,
    required this.sequence,
    required this.owned,
  });

  final Layout3dPointer pointer;
  double zOrder;
  bool absorbs;

  /// Whether the group made this pointer, and so disposes it.
  final bool owned;

  /// When this member was added, which is the last tie-break.
  final int sequence;

  /// How far the surface's plane is from [eye], for ordering by depth.
  double distanceFrom(Vector3 eye) {
    final origin = pointer.surface.plane.globalTransform.getTranslation();
    return (origin - eye).length;
  }
}

/// A pointer aimed at several surfaces at once: the ray goes to the front one
/// first, and stops at the first that answers.
///
/// [Layout3dPointer] tests one surface, which is the whole story until
/// something is in front of something else. A detached [Overlay3dEntry] is
/// exactly that: a menu that overhangs its panel, or a dialog facing the
/// viewer while the panel behind it stays angled, is a second surface, and a
/// press that lands on it must not also reach the panel behind. Absorption
/// inside a surface is [AbsorbPointer3d]'s and [HitTestBehavior3d]'s job;
/// absorption *between* surfaces is this one's.
///
/// ```dart
/// final group = Layout3dPointerGroup(camera: camera)
///   ..addSurface(surface);
///
/// void onFrame() => group.syncDetachedEntries(overlay);
///
/// Listener(
///   onPointerDown: (e) => group.down(rayFor(e), pointer: e.pointer),
///   onPointerMove: (e) => group.move(rayFor(e), pointer: e.pointer),
///   onPointerUp: (e) => group.up(pointer: e.pointer),
///   onPointerHover: (e) => group.hover(rayFor(e), pointer: e.pointer),
///   child: SceneView(scene: scene, camera: camera),
/// );
/// ```
///
/// ## The order surfaces are tested in
///
/// By [zOrder], highest first: an explicit statement of what is in front of
/// what, which is what an overlay has and geometry does not. Ties go to the
/// surface nearest the [camera], when there is one, and to the more recently
/// added otherwise — the same "last one wins" an [Overlay3d]'s entries keep.
///
/// A surface *answers* when something on it took the hit, which is when its
/// [Layout3dSurface.hitTestRay] comes back non-empty. An answering surface
/// that [absorbs] (the default) ends the walk: the surfaces behind it are not
/// tested, receive no events, and are told the pointer left them. A surface
/// added with `absorbs: false` is dispatched to and the walk carries on,
/// which is what a HUD that must not block the world wants.
///
/// ## Capture
///
/// A press captures the surfaces that answered it, exactly as
/// [Layout3dPointer] captures a path: every later event of that sequence goes
/// to the same surfaces, so sliding a drag off the dialog and onto the panel
/// behind does not hand the drag to the panel.
///
/// ## A drag-and-drop deliberately ignores capture
///
/// Capture is right for every gesture that is about the thing it started on,
/// and wrong for the one gesture that is defined by leaving it. A
/// [Draggable3d] picked up on a panel and carried onto a dialog in front has
/// to find the drop target on the dialog — a surface the press never touched
/// and which the capture set therefore excludes.
///
/// So while a [Drag3dSession] is in flight on a pointer, every [move] and the
/// [up] that ends it add one pass: walk the members front to back with the
/// ordinary ordering and absorption rules, and hand the front-most answering
/// path to the session. *Where events go* and *what the drag is over* are two
/// different questions, and conflating them is what makes a cross-surface
/// drop impossible.
///
/// The pass costs one hit test per surface per move, which is what a mouse
/// move already costs for hover, and less than that in practice: a surface
/// that just handled the move has the answer for this ray already and is not
/// asked twice. The group also takes over resolution entirely — every pointer
/// it holds has [Layout3dPointer.resolvesDrags] set false — so a session is
/// resolved once a move, against the whole scene rather than one plane of it.
///
/// Nothing here is laid out: a drag search is a hit test and a path diff.
/// Feedback that has to hang over the edge of its panel is an
/// [OverlayLayer3d.detached] entry, and a detached entry whose root is an
/// [IgnorePointer3d] answers empty, so this walk goes straight past it and
/// the feedback cannot steal its own drop.
class Layout3dPointerGroup {
  /// Creates a group, optionally ordered by distance from [camera].
  Layout3dPointerGroup({this.camera});

  /// The camera whose distance breaks ties in [zOrder], or null to leave
  /// them to insertion order.
  Camera? camera;

  final List<_Member> _members = <_Member>[];
  final Map<int, List<_Member>> _captured = <int, List<_Member>>{};
  final Map<Layout3dSurface, _Member> _bySurface = <Layout3dSurface, _Member>{};

  int _nextSequence = 0;

  HitTestResult3d _lastHit = HitTestResult3d();
  Layout3dPointer? _lastPointer;

  /// The pointers in this group, front to back.
  List<Layout3dPointer> get pointers => <Layout3dPointer>[
    for (final member in _ordered()) member.pointer,
  ];

  /// The surfaces in this group, front to back.
  List<Layout3dSurface> get surfaces => <Layout3dSurface>[
    for (final member in _ordered()) member.pointer.surface,
  ];

  /// What the last operation found on the front-most surface that answered.
  ///
  /// Empty when nothing did.
  HitTestResult3d get lastHit => _lastHit;

  /// The pointer whose surface produced [lastHit], or null.
  Layout3dPointer? get lastPointer => _lastPointer;

  /// Adds [surface] and returns the pointer made for it.
  ///
  /// [zOrder] is what is in front of what, highest first; [absorbs] says
  /// whether a hit here ends the walk.
  Layout3dPointer addSurface(
    Layout3dSurface surface, {
    double zOrder = 0.0,
    bool absorbs = true,
  }) {
    final existing = _bySurface[surface];
    if (existing != null) {
      existing
        ..zOrder = zOrder
        ..absorbs = absorbs;
      return existing.pointer;
    }
    final pointer = Layout3dPointer(surface);
    _put(pointer, zOrder: zOrder, absorbs: absorbs, owned: true);
    return pointer;
  }

  /// Adds an existing [pointer], which the caller keeps ownership of.
  void add(
    Layout3dPointer pointer, {
    double zOrder = 0.0,
    bool absorbs = true,
  }) => _put(pointer, zOrder: zOrder, absorbs: absorbs, owned: false);

  void _put(
    Layout3dPointer pointer, {
    required double zOrder,
    required bool absorbs,
    required bool owned,
  }) {
    final existing = _bySurface[pointer.surface];
    if (existing != null) {
      existing
        ..zOrder = zOrder
        ..absorbs = absorbs;
      return;
    }
    final member = _Member(
      pointer: pointer,
      zOrder: zOrder,
      absorbs: absorbs,
      sequence: _nextSequence++,
      owned: owned,
    );
    // From here the group answers "what is this drag over" for this pointer,
    // across every surface rather than this one. See the class dartdoc.
    pointer.resolvesDrags = false;
    _members.add(member);
    _bySurface[pointer.surface] = member;
  }

  /// Takes [surface] out of the group, cancelling anything it had captured.
  ///
  /// Returns the pointer that was testing it, or null when it was not here.
  /// The pointer is not disposed: a caller that handed one in with [add]
  /// keeps it.
  Layout3dPointer? removeSurface(Layout3dSurface surface) {
    final member = _bySurface.remove(surface);
    if (member == null) return null;
    _members.remove(member);
    for (final captured in _captured.values) {
      captured.remove(member);
    }
    _entrySurfaces.remove(surface);
    // Handed back the way it came: a pointer the caller owns goes back to
    // resolving its own drags, since nothing else is going to.
    member.pointer.resolvesDrags = true;
    if (member.owned) member.pointer.dispose();
    if (identical(_lastPointer, member.pointer)) {
      _lastPointer = null;
      _lastHit = HitTestResult3d();
    }
    return member.pointer;
  }

  /// Whether [surface] is in this group.
  bool holds(Layout3dSurface surface) => _bySurface.containsKey(surface);

  /// The pointer testing [surface], or null.
  Layout3dPointer? pointerFor(Layout3dSurface surface) =>
      _bySurface[surface]?.pointer;

  /// Puts [overlay]'s detached entries in the group, and takes out the ones
  /// that have gone.
  ///
  /// The one call an application needs to keep a group in step with an
  /// overlay: entries come and go as dialogs open and close, and each of them
  /// is a surface a ray has to reach before the panel behind it. Each entry
  /// is given `zOrder + its index`, so a later entry is in front of an
  /// earlier one; keep the base surface's own z-order below [zOrder].
  ///
  /// Cheap enough to call every frame: an entry already here has its z-order
  /// rewritten and nothing else.
  void syncDetachedEntries(Overlay3d overlay, {double zOrder = 1.0}) {
    final wanted = overlay.detachedSurfaces;
    // Only the surfaces this call is responsible for are taken out: one added
    // by hand stays, whether or not the overlay knows about it.
    for (final surface in _entrySurfaces.toList()) {
      if (wanted.contains(surface)) continue;
      removeSurface(surface);
    }
    for (var index = 0; index < wanted.length; index++) {
      final surface = wanted[index];
      _entrySurfaces.add(surface);
      addSurface(surface, zOrder: zOrder + index);
    }
  }

  final Set<Layout3dSurface> _entrySurfaces = <Layout3dSurface>{};

  /// What [worldRay] reaches on the front-most surface that answers, without
  /// touching any sequence state.
  ///
  /// Returns an empty result when no surface answers.
  HitTestResult3d hitTest(Ray worldRay) {
    _lastHit = HitTestResult3d();
    _lastPointer = null;
    for (final member in _ordered()) {
      final hit = member.pointer.hitTest(worldRay);
      if (hit.isEmpty) continue;
      _lastHit = hit;
      _lastPointer = member.pointer;
      if (member.absorbs) break;
    }
    return _lastHit;
  }

  /// Starts a press along [worldRay], capturing the surfaces that answer.
  ///
  /// Returns true when a scrolling view was grabbed, the same thing
  /// [Layout3dPointer.down] reports.
  bool down(
    Ray worldRay, {
    int pointer = 0,
    PointerDeviceKind kind = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
    Duration? timeStamp,
  }) {
    cancel(pointer: pointer, timeStamp: timeStamp);
    final captured = <_Member>[];
    var grabbed = false;
    _lastHit = HitTestResult3d();
    _lastPointer = null;
    for (final member in _ordered()) {
      final took = member.pointer.down(
        worldRay,
        pointer: pointer,
        kind: kind,
        buttons: buttons,
        timeStamp: timeStamp,
      );
      if (!member.pointer.isDown(pointer)) continue;
      grabbed = grabbed || took;
      captured.add(member);
      if (_lastPointer == null) {
        _lastPointer = member.pointer;
        _lastHit = member.pointer.lastHit;
      }
      if (member.absorbs) break;
    }
    if (captured.isNotEmpty) _captured[pointer] = captured;
    return grabbed;
  }

  /// Continues the press along the captured surfaces.
  ///
  /// Events go to the captured surfaces and nowhere else. A drag in flight is
  /// then resolved against *every* surface, front to back — see the class
  /// dartdoc for why those are two different questions.
  bool move(Ray worldRay, {int pointer = 0, Duration? timeStamp}) {
    var moved = false;
    for (final member in _captured[pointer] ?? const <_Member>[]) {
      moved =
          member.pointer.move(
            worldRay,
            pointer: pointer,
            timeStamp: timeStamp,
          ) ||
          moved;
    }
    // After the dispatch, so that a drag recognized by this very move is
    // already in flight and resolves against the path this ray found.
    // Reusing what the captured surfaces just computed: a hit test for this
    // ray is exactly what `Layout3dPointer.move` did on each of them.
    _resolveDrags(worldRay, pointer, reuseHits: true);
    return moved;
  }

  /// Ends the press on every surface that captured it.
  ///
  /// With a [worldRay], a drag in flight takes one last look across every
  /// surface before it is released, so a drop that moved onto a dialog in the
  /// same event lands on the dialog.
  void up({Ray? worldRay, int pointer = 0, Duration? timeStamp}) {
    // Before the ups, because the up is what drops the session: by the time
    // `Layout3dPointer.up` returns, the drag is over and its targets are
    // gone.
    if (worldRay != null) {
      _resolveDrags(worldRay, pointer, reuseHits: false);
    }
    for (final member in _captured.remove(pointer) ?? const <_Member>[]) {
      member.pointer.up(
        worldRay: worldRay,
        pointer: pointer,
        timeStamp: timeStamp,
      );
    }
  }

  /// The drag the pointer with this id is carrying, or null.
  ///
  /// A drag lives on the pointer of the surface it was picked up from, which
  /// is one of the captured ones; it is found here whatever surface it has
  /// since wandered over.
  Drag3dSession? dragFor(int pointer) {
    for (final member in _members) {
      final session = member.pointer.dragFor(pointer);
      if (session != null) return session;
    }
    return null;
  }

  /// Every drag in flight anywhere in this group.
  Iterable<Drag3dSession> get drags => <Drag3dSession>[
    for (final member in _members) ...member.pointer.drags,
  ];

  /// Whether any pointer in this group is carrying a payload.
  bool get isDraggingPayload => drags.isNotEmpty;

  /// Resolves the drags [pointer] is carrying against the whole group.
  ///
  /// Returns true when the set of accepting targets changed anywhere, which
  /// is the same thing [Drag3dSession.update] reports.
  bool _resolveDrags(Ray worldRay, int pointer, {required bool reuseHits}) {
    List<Drag3dSession>? sessions;
    for (final member in _members) {
      final session = member.pointer.dragFor(pointer);
      if (session == null) continue;
      (sessions ??= <Drag3dSession>[]).add(session);
    }
    // The common case, and it has to stay cheap: a group with nothing in
    // flight pays a walk of a handful of members and no hit test at all.
    if (sessions == null) return false;
    final hit = _dragHitTest(worldRay, pointer: pointer, reuseHits: reuseHits);
    var changed = false;
    for (final session in sessions) {
      // Re-installed on every resolution rather than once, because the ray is
      // what changes: the closure carries the latest one, and a tick that
      // arrives between two moves asks the group the same question the last
      // move asked. Without this a tick would fall back to the path this walk
      // produced — right for a reorder, which reasons in scroll coordinates,
      // and wrong for a drag over a target on a surface that has scrolled.
      session.pathResolver = () =>
          _dragHitTest(worldRay, pointer: pointer, reuseHits: false);
      changed = session.update(hit) || changed;
    }
    return changed;
  }

  /// The path a drop would land on: the front-most surface that answers.
  ///
  /// The ordinary walk, with the ordinary absorption rule — a dialog that
  /// answers ends it, so a drop cannot reach the panel behind the dialog
  /// covering it. *A drop lands where a tap would land*, which is the whole
  /// argument for the rule.
  ///
  /// [reuseHits] takes the answer a surface has already computed for this ray
  /// rather than asking again, which is legal exactly for the surfaces that
  /// hold the press: [Layout3dPointer.move] hit-tests afresh before it
  /// dispatches, so its [Layout3dPointer.lastHit] *is* this ray's answer.
  HitTestResult3d _dragHitTest(
    Ray worldRay, {
    required int pointer,
    required bool reuseHits,
  }) {
    for (final member in _ordered()) {
      final hit = reuseHits && member.pointer.isDown(pointer)
          ? member.pointer.lastHit
          : member.pointer.hitTest(worldRay);
      if (hit.isEmpty) continue;
      _lastHit = hit;
      _lastPointer = member.pointer;
      return hit;
    }
    return HitTestResult3d();
  }

  /// Abandons the press on every surface that captured it.
  void cancel({int pointer = 0, Duration? timeStamp}) {
    for (final member in _captured.remove(pointer) ?? const <_Member>[]) {
      member.pointer.cancel(pointer: pointer, timeStamp: timeStamp);
    }
  }

  /// Moves an unpressed pointer, hovering the front-most surface that answers
  /// and taking the pointer off the ones behind it.
  ///
  /// Returns true when the set of boxes under the pointer changed anywhere.
  bool hover(Ray worldRay, {int pointer = 0, Duration? timeStamp}) {
    var changed = false;
    var absorbed = false;
    _lastHit = HitTestResult3d();
    _lastPointer = null;
    for (final member in _ordered()) {
      if (absorbed) {
        member.pointer.exit(pointer: pointer, timeStamp: timeStamp);
        continue;
      }
      changed =
          member.pointer.hover(
            worldRay,
            pointer: pointer,
            timeStamp: timeStamp,
          ) ||
          changed;
      if (member.pointer.lastHit.isEmpty) continue;
      if (_lastPointer == null) {
        _lastPointer = member.pointer;
        _lastHit = member.pointer.lastHit;
      }
      if (member.absorbs) absorbed = true;
    }
    return changed;
  }

  /// Takes a hovering pointer off every surface.
  void exit({int pointer = 0, Duration? timeStamp}) {
    for (final member in _members) {
      member.pointer.exit(pointer: pointer, timeStamp: timeStamp);
    }
  }

  /// The surfaces a press is captured on, front to back.
  List<Layout3dSurface> capturedBy(int pointer) => <Layout3dSurface>[
    for (final member in _captured[pointer] ?? const <_Member>[])
      member.pointer.surface,
  ];

  /// Drops every sequence and hover on every surface, and disposes the
  /// pointers this group made.
  void dispose() {
    // Every pointer is dropped, owned or not: dispose on a pointer cancels
    // its sequences and hovers, which is what a group being torn down owes
    // the boxes wearing a pressed state layer because of it.
    for (final member in _members) {
      member.pointer
        ..dispose()
        ..resolvesDrags = true;
    }
    _members.clear();
    _bySurface.clear();
    _captured.clear();
    _entrySurfaces.clear();
    _lastPointer = null;
    _lastHit = HitTestResult3d();
  }

  /// The members front to back.
  ///
  /// Sorted rather than kept sorted, because a z-order or a camera can change
  /// between any two events and the list is short: an application has a
  /// surface and the dialogs standing in front of it, not a scene graph.
  List<_Member> _ordered() {
    final eye = _eye();
    final ordered = List<_Member>.of(_members);
    ordered.sort((a, b) {
      final byOrder = b.zOrder.compareTo(a.zOrder);
      if (byOrder != 0) return byOrder;
      if (eye != null) {
        final byDistance = a.distanceFrom(eye).compareTo(b.distanceFrom(eye));
        if (byDistance != 0) return byDistance;
      }
      return b.sequence.compareTo(a.sequence);
    });
    return ordered;
  }

  /// Where the camera is, in world space, or null without one.
  ///
  /// Read out of the inverted view matrix rather than off a position
  /// property, which is the one place every kind of [Camera] agrees.
  Vector3? _eye() {
    final camera = this.camera;
    if (camera == null) return null;
    final inverseView = Matrix4.zero();
    if (inverseView.copyInverse(camera.getViewMatrix()) == 0.0) return null;
    return inverseView.getColumn(3).xyz;
  }

  @override
  String toString() => 'Layout3dPointerGroup(${_members.length} surfaces)';
}
