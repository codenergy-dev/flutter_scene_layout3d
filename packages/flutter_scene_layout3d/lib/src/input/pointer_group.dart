import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter_scene/scene.dart' show Camera;
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;

import '../hit_test.dart';
import '../overlay/overlay.dart';
import '../surface.dart';
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
    return moved;
  }

  /// Ends the press on every surface that captured it.
  void up({Ray? worldRay, int pointer = 0, Duration? timeStamp}) {
    for (final member in _captured.remove(pointer) ?? const <_Member>[]) {
      member.pointer.up(
        worldRay: worldRay,
        pointer: pointer,
        timeStamp: timeStamp,
      );
    }
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
      member.pointer.dispose();
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
