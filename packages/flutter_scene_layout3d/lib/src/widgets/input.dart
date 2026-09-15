import 'dart:ui' show Offset, Size;

import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerExitEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerPanZoomEndEvent,
        PointerPanZoomStartEvent,
        PointerPanZoomUpdateEvent,
        PointerScrollEvent,
        PointerScrollInertiaCancelEvent,
        PointerSignalEvent,
        PointerUpEvent;
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Focus,
        FocusManager,
        FocusNode,
        FocusScopeNode,
        HitTestBehavior,
        InheritedWidget,
        Listener,
        MouseRegion,
        State,
        StatefulWidget,
        Widget,
        WidgetsBinding;
import 'package:flutter_scene/scene.dart' show Camera;
import 'package:vector_math/vector_math.dart' show Ray;

import '../hit_test.dart';
import '../layout3d.dart';
import '../input/focus.dart';
import '../input/pointer.dart';
import '../input/pointer_group.dart';
import '../input/shortcuts.dart';
import '../overlay/overlay.dart';
import '../surface.dart';

/// What an event was doing when it found something.
///
/// Keys are not here and will not be: a key goes to the focus, not to what is
/// under the cursor, so there is no hit to report.
enum Input3dHitPhase {
  /// A press going down.
  press,

  /// A pointer moving with nothing pressed.
  hover,

  /// A wheel turning, or two fingers starting a pan on a trackpad.
  scroll,
}

/// What a pointer found, reported to [SceneInput3d.onHit].
class Input3dHit {
  /// Creates a report.
  const Input3dHit({
    required this.result,
    required this.phase,
    this.grabbedScrollable = false,
  });

  /// The path the ray took on the front-most surface that answered, empty
  /// when nothing did.
  final HitTestResult3d result;

  /// What the pointer was doing.
  final Input3dHitPhase phase;

  /// Whether the event took hold of a scrolling view.
  ///
  /// The one piece of news a press or a scroll carries that the path does
  /// not: a [Scrollable3d] under the ray has started following this pointer,
  /// or is about to move under a wheel, so an application animating that
  /// scroll position for show knows to stop. Always false for a hover.
  final bool grabbedScrollable;
}

/// Called when a press or a hover has found what is under it.
typedef Input3dHitCallback = void Function(Input3dHit hit);

/// The input host in force above a widget.
///
/// A [SceneInput3d] owns one. It is the registry every surface below it
/// announces itself to, the [Layout3dPointerGroup] the rays are dispatched
/// through, and the [camera] they are cast from — the seam a navigator, a
/// keyboard layer or a test harness reaches through rather than rebuilding
/// the wiring.
///
/// A `SceneLayout3d` and a `SceneOverlay3d` register themselves, so an
/// application never calls any of this. Register by hand only for a surface
/// built imperatively, which the declarative layer cannot see.
abstract class Input3dHost {
  /// The group every registered surface is tested through.
  Layout3dPointerGroup get pointers;

  /// The camera rays are cast from, or null when none was given.
  Camera? get camera;

  /// Puts [surface] in the group, or restates where it stands.
  ///
  /// [zOrder] is what is in front of what, highest first; [absorbs] says
  /// whether a hit here ends the walk. Calling it again for a surface
  /// already here rewrites both and does nothing else.
  void registerSurface(
    Layout3dSurface surface, {
    double zOrder = 0.0,
    bool absorbs = true,
  });

  /// Takes [surface] out of the group, cancelling anything it had captured.
  void unregisterSurface(Layout3dSurface surface);

  /// Keeps [overlay]'s detached entries in the group from now on.
  ///
  /// The entries themselves are synced immediately before each dispatch
  /// rather than now: what is in an overlay changes when a dialog opens, and
  /// the only moment the answer is consumed is the moment an event arrives.
  void registerOverlay(Overlay3d overlay);

  /// Stops tracking [overlay], and takes its entries out of the group.
  void unregisterOverlay(Overlay3d overlay);

  /// Hands the keyboard back to the scene, and reports whether anything took
  /// it.
  ///
  /// The front-most surface that can take the focus gets it: back to wherever
  /// its focus last was, when something on it has held the focus before, and
  /// to its first focusable box in tree order otherwise. The call for "the
  /// user came back to the scene" — a click on its window, a menu command.
  /// Arriving by Tab is different, and lands on the first box of the scene
  /// instead; see [SceneInput3d]'s *A key*.
  bool requestSceneFocus();

  /// Every path a press at [position] would be dispatched to, front to back,
  /// with nothing dispatched.
  ///
  /// [position] is in this host's own coordinates — a pointer event's
  /// `localPosition`. The answer is the one a press there would get: the ray
  /// the camera casts through that point, the overlays' entries synced first,
  /// the front-most surface that answers and those behind it for as long as
  /// the surfaces answering do not absorb. Empty when nothing answers, and
  /// when there is no camera or the view has no extent yet.
  ///
  /// The question a tooltip, an editor's pick or a debugging readout asks,
  /// and the one a test asks before it presses something: "would a person
  /// pressing here reach this box?" See
  /// [Layout3dPointerGroup.hitTestAll].
  List<HitTestResult3d> hitTestAt(Offset position);
}

/// Imperative access to the [Input3dHost] a [SceneInput3d] owns.
///
/// The counterpart of `Layout3dController` for input: the widget that *builds*
/// a [SceneInput3d] has no context below it, so it reaches the host through
/// one of these. Anything built inside uses [SceneInput3d.of] instead.
class Input3dController {
  Input3dHost? _host;

  /// The host, or null while the widget is unmounted.
  Input3dHost? get host => _host;
}

/// Routes the platform's pointers into every layout surface in a scene.
///
/// Wrap the `SceneView` in one, give it the camera the view renders with, and
/// the wiring is done: a `SceneLayout3d` anywhere below announces its surface
/// on mount, a `SceneOverlay3d` announces its dialogs, and a press, a drag or
/// a hover reaches the box under the cursor through
/// [Layout3dPointerGroup]'s ordering rules.
///
/// ```dart
/// SceneInput3d(
///   camera: camera,
///   child: SceneView(
///     scene,
///     camera: camera,
///     children: [
///       SceneLayout3d(
///         size: const Size3d(3.5, 4.8, 0.6),
///         child: const MaterialScreen(),
///       ),
///     ],
///   ),
/// )
/// ```
///
/// **It wraps the view rather than replacing it**, and that is deliberate: a
/// `SceneView` has more than twenty parameters, and a widget that forwarded
/// them would be a list that rots every time the engine grows one. The author
/// keeps the view they know — its `onTick`, its loading gate, its camera
/// builder — and this owns only the input.
///
/// ## What is in front of what
///
/// Stated, not derived, on each `SceneLayout3d`'s `zOrder`. Geometry cannot
/// answer it: a panel turned away from the camera is in front of another
/// panel for some pixels and behind it for others, while a pointer needs one
/// answer for the whole surface. Ties go to the surface nearest the [camera].
/// A dialog is put one whole step in front of the surface whose overlay
/// opened it, so nothing has to restate that relationship.
///
/// ## A wheel and a trackpad
///
/// A wheel goes where a press would have gone — the front-most surface that
/// answers the ray, so a wheel over a dialog does not scroll the page behind
/// it — and on that surface to the innermost view that would actually move,
/// which is Flutter's rule; see [PointerScroll3d]. It claims the wheel through
/// Flutter's `pointerSignalResolver`, and only when something would move, so a
/// scroll view in the widget tree around the scene keeps working. Shift turns
/// a mouse wheel sideways, as it does in Flutter.
///
/// Two fingers on a trackpad are a **drag by a finger that went down where the
/// cursor is**, run through the same arithmetic a touch drag uses, so the
/// content stays under the fingers at any angle and flings when they lift. A
/// pan presses nothing: no control under it is tapped or focused. Its scale
/// and rotation are ignored — this widget zooms neither the camera nor the
/// layout — and an application that wants a pinch wraps a `Listener` of its
/// own around this one.
///
/// ## A key
///
/// A key goes to the focus, not to the cursor, and it reaches a box on a
/// plane without passing through this widget; [Shortcuts3d] explains the
/// walk. What this widget adds is the way in, the way across and the way out.
///
/// **In.** A keyboard cannot reach a scene nothing has focused, so the host is
/// one focusable widget in Flutter's own traversal, and hands the focus into
/// the scene the moment it receives it: to the first box of the first surface,
/// or to the last box of the last one when Shift is held — the direction a
/// Shift-Tab arrives from. [autofocus] does that on the first frame.
///
/// **Across.** Tab off the end of one surface goes on to the next, in the
/// order the surfaces mounted, with each overlay's floating entries straight
/// after the panel that opened them. A dialog that traps the focus still
/// cycles inside itself, as a `ModalRoute` does.
///
/// **Out.** Tab off the end of the last surface hands the focus back to
/// Flutter's traversal, from this widget's place in it, so it lands on the
/// next focusable widget after the scene. When there is none — a window that
/// is nothing but the scene — the traversal comes straight back in at the
/// other end, and Tab goes round the whole scene.
class SceneInput3d extends StatefulWidget {
  /// Creates an input host over [child].
  const SceneInput3d({
    super.key,
    this.camera,
    this.controller,
    this.onHit,
    this.viewSize,
    this.autofocus = false,
    required this.child,
  });

  /// The camera a pointer position is turned into a world ray with.
  ///
  /// Usually the same camera the enclosing `SceneView` renders with —
  /// anything else aims the rays somewhere other than where the picture is.
  /// Published to everything below, so a `SceneLayout3d` with a camera
  /// binding and a `SceneOverlay3d` need not be given one of their own.
  final Camera? camera;

  /// Imperative access to the host this widget owns.
  final Input3dController? controller;

  /// Called after a press, a hover or a scroll, with what it found.
  ///
  /// Not after a move: a move goes to the surfaces that captured the press
  /// and does not ask what is under the ray, so there would be nothing fresh
  /// to report.
  final Input3dHitCallback? onHit;

  /// Whether the scene takes the keyboard on the first frame.
  ///
  /// The focus goes to the first focusable box on the front-most surface that
  /// has one. Leave it false in an application where the scene is one part of
  /// a screen: a scene nobody has interacted with should not take the
  /// keyboard away from the widgets around it.
  final bool autofocus;

  /// The logical size of the view the rays are cast against.
  ///
  /// Leave it null in the common case: this widget's own box is the view,
  /// because the view is its child. Supply it when the `SceneView` renders
  /// into a sub-rectangle of this box.
  final Size? viewSize;

  /// The subtree the pointers are routed into — the `SceneView`, normally.
  final Widget child;

  /// The host above [context], or null when there is none.
  ///
  /// The caller becomes a dependent: it rebuilds when the host or its camera
  /// changes.
  static Input3dHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Input3dScope>()?.host;

  /// The host above [context].
  ///
  /// Asserts when there is none, because the quiet alternative is an
  /// application whose screens cannot be pressed and which says nothing about
  /// why.
  static Input3dHost of(BuildContext context) {
    final host = maybeOf(context);
    assert(
      host != null,
      'SceneInput3d.of() found no input host above this context. Wrap the '
      'SceneView in a SceneInput3d; use maybeOf() if being outside one is a '
      'legitimate state.',
    );
    return host!;
  }

  @override
  State<SceneInput3d> createState() => _SceneInput3dState();
}

/// Publishes the [Input3dHost] to the subtree.
///
/// Public because the widgets that register with it live in other libraries
/// of this package; there is nothing here an application needs that
/// [SceneInput3d.of] does not answer.
class Input3dScope extends InheritedWidget {
  /// Creates a scope over [child].
  const Input3dScope({
    super.key,
    required this.host,
    required this.camera,
    required super.child,
  });

  /// The host in force.
  final Input3dHost host;

  /// The camera the host casts rays from, repeated here so that a change to
  /// it notifies dependents.
  final Camera? camera;

  @override
  bool updateShouldNotify(Input3dScope oldWidget) =>
      !identical(oldWidget.host, host) || !identical(oldWidget.camera, camera);
}

class _SceneInput3dState extends State<SceneInput3d> implements Input3dHost {
  late final Layout3dPointerGroup _group = Layout3dPointerGroup(
    camera: widget.camera,
  );

  /// The overlays whose detached entries this host keeps in the group, and
  /// the surface each of them is laid out on once that is knowable.
  final List<Overlay3d> _overlays = <Overlay3d>[];

  /// Which surface owns which layout tree, so an overlay can be placed in
  /// front of the panel it belongs to.
  ///
  /// A `Layout3d` knows its [Layout3dOwner] and not the surface above it,
  /// and every surface attaches its tree to an owner of its own — so this
  /// map, filled in as surfaces register, is what turns one into the other.
  final Map<Layout3dOwner, Layout3dSurface> _surfacesByOwner =
      <Layout3dOwner, Layout3dSurface>{};

  /// Every registered surface, in the order it registered, with its z-order.
  ///
  /// Insertion-ordered, and a re-registration keeps its place, so the keys are
  /// also the order Tab walks the panels in.
  final Map<Layout3dSurface, double> _zOrders = <Layout3dSurface, double>{};

  /// Set while the host takes the focus in order to hand it on, so that
  /// taking it does not hand it straight back into the scene.
  bool _leaving = false;

  /// The host's place in Flutter's own focus traversal: the door a keyboard
  /// comes into the scene through. It never keeps the focus when something
  /// in the scene can take it.
  final FocusNode _focusNode = FocusNode(debugLabel: 'SceneInput3d');

  @override
  void initState() {
    super.initState();
    widget.controller?._host = this;
  }

  @override
  void didUpdateWidget(SceneInput3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      if (identical(oldWidget.controller?._host, this)) {
        oldWidget.controller?._host = null;
      }
      widget.controller?._host = this;
    }
    if (!identical(widget.camera, oldWidget.camera)) {
      _group.camera = widget.camera;
    }
  }

  @override
  void dispose() {
    if (identical(widget.controller?._host, this)) {
      widget.controller?._host = null;
    }
    for (final overlay in _overlays) {
      overlay.entriesChanged.removeListener(_watchEntryEdges);
    }
    for (final surface in _zOrders.keys) {
      surface.owner?.onFocusTraversalEdge = null;
    }
    _group.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --- Input3dHost -------------------------------------------------------

  @override
  Layout3dPointerGroup get pointers => _group;

  @override
  Camera? get camera => widget.camera;

  @override
  void registerSurface(
    Layout3dSurface surface, {
    double zOrder = 0.0,
    bool absorbs = true,
  }) {
    _group.addSurface(surface, zOrder: zOrder, absorbs: absorbs);
    _zOrders[surface] = zOrder;
    final owner = surface.owner;
    if (owner != null) _surfacesByOwner[owner] = surface;
    _watchTraversalEdge(surface);
  }

  @override
  void unregisterSurface(Layout3dSurface surface) {
    _group.removeSurface(surface);
    _zOrders.remove(surface);
    _surfacesByOwner.removeWhere((_, value) => identical(value, surface));
    surface.owner?.onFocusTraversalEdge = null;
  }

  @override
  void registerOverlay(Overlay3d overlay) {
    if (_overlays.contains(overlay)) return;
    _overlays.add(overlay);
    overlay.entriesChanged.addListener(_watchEntryEdges);
    _watchEntryEdges();
  }

  @override
  void unregisterOverlay(Overlay3d overlay) {
    if (!_overlays.remove(overlay)) return;
    overlay.entriesChanged.removeListener(_watchEntryEdges);
    _group.forgetDetachedEntries(overlay);
  }

  @override
  bool requestSceneFocus() {
    _syncOverlays();
    for (final surface in _group.surfaces) {
      final owner = surface.owner;
      // Back to where the focus last was on this surface — which, with a
      // dialog open, is inside the dialog — rather than to the first box in
      // tree order, which could be behind the barrier.
      if (owner != null &&
          owner.hasFocusScope &&
          owner.focusScope.focusedChild != null) {
        owner.focusScope.requestFocus();
        return true;
      }
      final first = const Focus3dTraversal().firstFocus(surface);
      if (first != null) {
        first.requestFocus();
        return true;
      }
    }
    return false;
  }

  @override
  List<HitTestResult3d> hitTestAt(Offset position) {
    final camera = widget.camera;
    final size = _viewSize;
    if (camera == null || size == null) return <HitTestResult3d>[];
    _syncOverlays();
    return _group.hitTestAll(camera.screenPointToRay(position, size));
  }

  /// Passes the focus straight through to the scene when Flutter gives it to
  /// the host.
  ///
  /// Flutter's traversal does not say which way it was going when it landed
  /// here, and the key that sent it is still held: Shift means Shift-Tab, so
  /// the scene is entered from its far end.
  ///
  /// A surface laid out for the first time in the frame that asked has no
  /// sizes yet, and traversal skips a box without one; so a first attempt
  /// that finds nothing tries once more after the frame.
  void _handleFocusChange(bool focused) {
    if (_leaving || !focused || !_focusNode.hasPrimaryFocus) return;
    final forward = !HardwareKeyboard.instance.isShiftPressed;
    if (_enterScene(forward: forward)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasPrimaryFocus) return;
      _enterScene(forward: forward);
    });
  }

  // --- traversal between surfaces ----------------------------------------

  /// The order Tab walks the scene's surfaces in.
  ///
  /// The panels in the order they registered, which is the order they
  /// mounted, and after each one the floating entries of the overlays laid
  /// out on it, in their own order — so a snack bar's action comes after the
  /// screen that showed it. Entries of an overlay whose panel cannot be
  /// resolved come last.
  List<Layout3dSurface> _traversalOrder() {
    final order = <Layout3dSurface>[];
    final placed = <Overlay3d>{};
    for (final surface in _zOrders.keys) {
      order.add(surface);
      for (final overlay in _overlays) {
        final owner = overlay.owner;
        if (owner == null || !identical(_surfacesByOwner[owner], surface)) {
          continue;
        }
        order.addAll(overlay.detachedSurfaces);
        placed.add(overlay);
      }
    }
    for (final overlay in _overlays) {
      if (!placed.contains(overlay)) order.addAll(overlay.detachedSurfaces);
    }
    return order;
  }

  /// Asks [surface]'s tree to consult this host before Tab wraps round it.
  void _watchTraversalEdge(Layout3dSurface surface) {
    surface.owner?.onFocusTraversalEdge = (forward) =>
        _handleTraversalEdge(surface, forward: forward);
  }

  /// The same, for every floating entry the overlays hold now.
  ///
  /// Run when an overlay's entries change rather than at dispatch, because a
  /// Tab needs the answer and no pointer event has to come first: a snack
  /// bar that appears while the keyboard is in use must be reachable by it.
  void _watchEntryEdges() {
    for (final overlay in _overlays) {
      overlay.detachedSurfaces.forEach(_watchTraversalEdge);
    }
  }

  /// Tab ran off the end of [from]: on to the next surface that has something
  /// to focus, or out of the scene when none does.
  bool _handleTraversalEdge(Layout3dSurface from, {required bool forward}) {
    final order = _traversalOrder();
    final index = order.indexOf(from);
    if (index < 0) return false;
    final onward = forward
        ? order.sublist(index + 1)
        : order.sublist(0, index).reversed;
    for (final surface in onward) {
      if (_focusInto(surface, forward: forward)) return true;
    }
    return _leaveScene(forward: forward);
  }

  /// Focuses [surface]'s first box, or its last one going backwards.
  ///
  /// Except when a dialog on it holds the focus: arriving on a panel with a
  /// trapping entry open lands inside the entry, never on a box behind its
  /// barrier. The owner's scope remembers the dialog's scope as the child
  /// that had the focus, and asking the dialog's scope restores its own.
  bool _focusInto(Layout3dSurface surface, {required bool forward}) {
    final owner = surface.owner;
    if (owner != null && owner.hasFocusScope) {
      final held = owner.focusScope.focusedChild;
      if (held is FocusScopeNode) {
        held.requestFocus();
        return true;
      }
    }
    const traversal = Focus3dTraversal();
    final target = forward
        ? traversal.firstFocus(surface)
        : traversal.lastFocus(surface);
    target?.requestFocus();
    return target != null;
  }

  /// The first box of the scene, or the last going backwards.
  bool _enterScene({required bool forward}) {
    final order = _traversalOrder();
    for (final surface in forward ? order : order.reversed) {
      if (_focusInto(surface, forward: forward)) return true;
    }
    return false;
  }

  /// Hands the focus to Flutter's traversal, from the host's own place in it.
  ///
  /// Flutter moves from whatever holds the focus in a scope, so the host takes
  /// it first — quietly, or [_handleFocusChange] would hand it straight back —
  /// and then asks for the next widget. When that comes back to the host
  /// itself, there is nothing else to go to, and the scene is entered again
  /// from the other end.
  bool _leaveScene({required bool forward}) {
    _leaving = true;
    try {
      _focusNode.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
    } finally {
      _leaving = false;
    }
    if (forward) {
      _focusNode.nextFocus();
    } else {
      _focusNode.previousFocus();
    }
    FocusManager.instance.applyFocusChangesIfNeeded();
    if (!_focusNode.hasPrimaryFocus) return true;
    return _enterScene(forward: forward);
  }

  // --- dispatch ----------------------------------------------------------

  /// Brings the group up to date with what the overlays hold, just before the
  /// answer is consumed.
  ///
  /// Every entry of an overlay is a surface of its own, and it is in front of
  /// the panel that opened it by one whole z-order step. A host surface that
  /// cannot be resolved yet — an overlay whose tree is not attached — falls
  /// back to zero, which is the same base the group has always defaulted to.
  void _syncOverlays() {
    for (final overlay in _overlays) {
      final owner = overlay.owner;
      final host = owner == null ? null : _surfacesByOwner[owner];
      final base = host == null ? 0.0 : (_zOrders[host] ?? 0.0);
      _group.syncDetachedEntries(overlay, zOrder: base + 1.0);
    }
  }

  /// The logical size of the view, from this widget's own box.
  Size? get _viewSize {
    final explicit = widget.viewSize;
    if (explicit != null) return explicit;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;
    return box.size;
  }

  Ray? _rayAt(Offset position) {
    final camera = widget.camera;
    assert(
      camera != null,
      'A pointer reached a SceneInput3d with no camera, so there is nothing '
      'to cast a ray with. Give it the camera the enclosing SceneView '
      'renders with.',
    );
    if (camera == null) return null;
    final size = _viewSize;
    assert(
      size != null,
      'A pointer reached a SceneInput3d whose box has no extent, so there is '
      'nothing to cast a ray against. The child is normally the SceneView, '
      'which fills what it is given; a child that takes no space leaves this '
      'widget with none either. Give it a child that fills, or state the '
      'view\'s size with SceneInput3d.viewSize.',
    );
    if (size == null) return null;
    return camera.screenPointToRay(position, size);
  }

  void _report(Input3dHitPhase phase, {bool grabbedScrollable = false}) {
    final onHit = widget.onHit;
    if (onHit == null) return;
    onHit(
      Input3dHit(
        result: _group.lastHit,
        phase: phase,
        grabbedScrollable: grabbedScrollable,
      ),
    );
  }

  void _handleDown(PointerDownEvent event) {
    final ray = _rayAt(event.localPosition);
    if (ray == null) return;
    _syncOverlays();
    final grabbed = _group.down(
      ray,
      pointer: event.pointer,
      kind: event.kind,
      buttons: event.buttons,
      timeStamp: event.timeStamp,
    );
    _report(Input3dHitPhase.press, grabbedScrollable: grabbed);
  }

  void _handleMove(PointerMoveEvent event) {
    final ray = _rayAt(event.localPosition);
    if (ray == null) return;
    _group.move(ray, pointer: event.pointer, timeStamp: event.timeStamp);
  }

  void _handleUp(PointerUpEvent event) {
    _group.up(
      worldRay: _rayAt(event.localPosition),
      pointer: event.pointer,
      timeStamp: event.timeStamp,
    );
  }

  void _handleCancel(PointerCancelEvent event) {
    _group.cancel(pointer: event.pointer, timeStamp: event.timeStamp);
  }

  void _handleHover(PointerHoverEvent event) {
    final ray = _rayAt(event.localPosition);
    if (ray == null) return;
    _syncOverlays();
    _group.hover(ray, pointer: event.pointer, timeStamp: event.timeStamp);
    _report(Input3dHitPhase.hover);
  }

  void _handleSignal(PointerSignalEvent event) {
    if (event is PointerScrollInertiaCancelEvent) {
      final ray = _rayAt(event.localPosition);
      if (ray == null) return;
      _syncOverlays();
      // Not through the resolver, which is Flutter's position too: the
      // fingers are on every view under them, and every one of them stops.
      _group.cancelScrollInertia(ray);
      return;
    }
    if (event is! PointerScrollEvent) return;
    final ray = _rayAt(event.localPosition);
    if (ray == null) return;
    _syncOverlays();
    final scroll = _group.resolveScroll(ray, _scrollDeltaOf(event));
    _report(Input3dHitPhase.scroll, grabbedScrollable: scroll != null);
    if (scroll == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (!scroll.apply()) return;
      if (resolved is PointerScrollEvent) {
        // Tells the platform the wheel was used, so a web page around the
        // application does not scroll as well.
        resolved.respond(allowPlatformDefault: false);
      }
    });
  }

  /// The wheel's delta, turned sideways for a mouse while Shift is held.
  ///
  /// Flutter's `ScrollBehavior.pointerAxisModifiers`, and only for a mouse:
  /// a trackpad arriving as a wheel (on the web) already has both axes, and
  /// swapping them would send a vertical swipe sideways.
  static Offset _scrollDeltaOf(PointerScrollEvent event) {
    final delta = event.scrollDelta;
    if (event.kind != PointerDeviceKind.mouse) return delta;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final shifted =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    return shifted ? Offset(delta.dy, delta.dx) : delta;
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    final ray = _rayAt(event.localPosition);
    if (ray == null) return;
    _syncOverlays();
    final grabbed = _group.panZoomStart(
      ray,
      pointer: event.pointer,
      timeStamp: event.timeStamp,
    );
    _report(Input3dHitPhase.scroll, grabbedScrollable: grabbed);
  }

  /// The virtual finger is the cursor moved by the pan so far.
  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final ray = _rayAt(event.localPosition + event.localPan);
    if (ray == null) return;
    _group.panZoomUpdate(
      ray,
      pointer: event.pointer,
      timeStamp: event.timeStamp,
    );
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) =>
      _group.panZoomEnd(pointer: event.pointer, timeStamp: event.timeStamp);

  /// Takes the pointer off every surface when it leaves the view.
  ///
  /// Without this a box lit by a hover keeps its state layer when the cursor
  /// leaves the window, because nothing else will ever tell it otherwise: a
  /// hover only ends when a later hover lands somewhere else.
  void _handleExit(PointerExitEvent event) =>
      _group.exit(pointer: event.pointer, timeStamp: event.timeStamp);

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _handleFocusChange,
      child: MouseRegion(
        opaque: false,
        onExit: _handleExit,
        child: Listener(
          // Translucent, the position SceneView's own listener takes: the
          // whole box reports pointers whether or not the scene drew anything
          // there, and widgets behind the view still get their events.
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handleDown,
          onPointerMove: _handleMove,
          onPointerUp: _handleUp,
          onPointerCancel: _handleCancel,
          onPointerHover: _handleHover,
          onPointerSignal: _handleSignal,
          onPointerPanZoomStart: _handlePanZoomStart,
          onPointerPanZoomUpdate: _handlePanZoomUpdate,
          onPointerPanZoomEnd: _handlePanZoomEnd,
          child: Input3dScope(
            host: this,
            camera: widget.camera,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
