import 'dart:ui' show Offset, Size;

import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerExitEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerUpEvent;
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        HitTestBehavior,
        InheritedWidget,
        Listener,
        MouseRegion,
        State,
        StatefulWidget,
        Widget;
import 'package:flutter_scene/scene.dart' show Camera;
import 'package:vector_math/vector_math.dart' show Ray;

import '../hit_test.dart';
import '../layout3d.dart';
import '../input/pointer_group.dart';
import '../overlay/overlay.dart';
import '../surface.dart';

/// What an event was doing when it found something.
///
/// Open on purpose: the inputs this stack routes are not all here yet — a
/// wheel and a key are their own plan — and a reader should be able to tell a
/// phase that is missing from one that was forgotten.
enum Input3dHitPhase {
  /// A press going down.
  press,

  /// A pointer moving with nothing pressed.
  hover,
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

  /// Whether a press took hold of a scrolling view.
  ///
  /// The one piece of news a press carries that the path does not: a
  /// [Scrollable3d] under the ray has started following this pointer, so an
  /// application animating that scroll position for show knows to stop.
  /// Always false for a hover.
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
/// ## The events it does not route yet
///
/// A wheel, a trackpad gesture and a key. They belong here — this is where
/// they will land — and wiring them to nothing would hide that they are
/// missing, so they are left visibly absent rather than quietly dropped.
class SceneInput3d extends StatefulWidget {
  /// Creates an input host over [child].
  const SceneInput3d({
    super.key,
    this.camera,
    this.controller,
    this.onHit,
    this.viewSize,
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

  /// Called after a press or a hover, with what it found.
  ///
  /// Not after a move: a move goes to the surfaces that captured the press
  /// and does not ask what is under the ray, so there would be nothing fresh
  /// to report.
  final Input3dHitCallback? onHit;

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

  final Map<Layout3dSurface, double> _zOrders = <Layout3dSurface, double>{};

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
    _group.dispose();
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
  }

  @override
  void unregisterSurface(Layout3dSurface surface) {
    _group.removeSurface(surface);
    _zOrders.remove(surface);
    _surfacesByOwner.removeWhere((_, value) => identical(value, surface));
  }

  @override
  void registerOverlay(Overlay3d overlay) {
    if (_overlays.contains(overlay)) return;
    _overlays.add(overlay);
  }

  @override
  void unregisterOverlay(Overlay3d overlay) {
    if (!_overlays.remove(overlay)) return;
    _group.forgetDetachedEntries(overlay);
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

  /// Takes the pointer off every surface when it leaves the view.
  ///
  /// Without this a box lit by a hover keeps its state layer when the cursor
  /// leaves the window, because nothing else will ever tell it otherwise: a
  /// hover only ends when a later hover lands somewhere else.
  void _handleExit(PointerExitEvent event) =>
      _group.exit(pointer: event.pointer, timeStamp: event.timeStamp);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      opaque: false,
      onExit: _handleExit,
      child: Listener(
        // Translucent, the position SceneView's own listener takes: the whole
        // box reports pointers whether or not the scene drew anything there,
        // and widgets behind the view still get their events.
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleDown,
        onPointerMove: _handleMove,
        onPointerUp: _handleUp,
        onPointerCancel: _handleCancel,
        onPointerHover: _handleHover,
        child: Input3dScope(
          host: this,
          camera: widget.camera,
          child: widget.child,
        ),
      ),
    );
  }
}
