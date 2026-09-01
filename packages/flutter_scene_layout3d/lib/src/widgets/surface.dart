import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        MultiChildRenderObjectWidget,
        State,
        StatefulWidget,
        Widget,
        WidgetsBinding;
import 'package:flutter/rendering.dart' show RenderBox, RenderObject;
import 'package:flutter_scene/scene.dart'
    show Camera, Node, SceneNode, SceneNodeHost, SceneScope, SceneSubtree;
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import '../camera_binding.dart';
import '../geometry/alignment3d.dart';
import '../geometry/basis3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import '../metrics.dart';
import '../slot.dart';
import '../surface.dart';
import 'framework.dart';

/// Imperative access to the [Layout3dSurface] a [SceneLayout3d] owns.
///
/// Attach one to read the laid-out sizes, drive a scroll controller, or reach
/// the plane [Node] for a raycast. Writes to the plane's transform are
/// subject to the usual ownership rule: do not set what the widget also
/// declares, because the next build overwrites it.
class Layout3dController {
  Layout3dSurface? _surface;

  /// The surface, or null while the widget is unmounted.
  Layout3dSurface? get surface => _surface;

  /// The node the layout hangs from, or null while unmounted.
  Node? get plane => _surface?.plane;
}

/// The root of a declarative 3D layout: the plane its children are arranged
/// on, mounted in the enclosing scene.
///
/// Place it among a `SceneView`'s children (or below any scene widget) and
/// describe the layout in [child] with the `Scene*3d` widgets. The layout
/// runs as part of the Flutter pipeline, so the tree reconciles the way every
/// other widget tree does, and what comes out is a subtree of scene [Node]s.
///
/// ```dart
/// SceneView.declarative(
///   children: [
///     SceneLayout3d(
///       size: const Size3d(4, 3, 0.5),
///       position: Vector3(0, 1, 0),
///       child: SceneColumn3d(
///         mainAxisAlignment: MainAxisAlignment3d.center,
///         spacing: 0.2,
///         children: [
///           SceneNodeBox3d(content: cube),
///           SceneNodeBox3d(content: sphere),
///         ],
///       ),
///     ),
///   ],
/// )
/// ```
class SceneLayout3d extends StatefulWidget {
  /// Creates a layout surface.
  const SceneLayout3d({
    super.key,
    this.size,
    this.constraints,
    this.basis,
    this.origin = Alignment3d.center,
    this.camera,
    this.binding,
    this.viewSize,
    this.parent,
    this.position,
    this.rotation,
    this.scale,
    this.transform,
    this.controller,
    this.slots = const <Layout3dSlot<Object>, Object>{},
    this.child,
  }) : assert(
         size == null || constraints == null,
         'Give the surface a size or a set of constraints, not both.',
       ),
       assert(
         transform == null ||
             (position == null && rotation == null && scale == null),
         'Provide either transform or position/rotation/scale, not both.',
       );

  /// A fixed extent for the plane, the common case.
  ///
  /// Shorthand for tight [constraints]. With neither, the plane shrink-wraps
  /// its content.
  final Size3d? size;

  /// The constraints the root child is laid out against.
  final Constraints3d? constraints;

  /// How layout space maps into the plane's scene space.
  ///
  /// Defaults to [LayoutBasis3d.xy], an upright plane facing the camera.
  final LayoutBasis3d? basis;

  /// The point of the laid-out box that sits at the plane's origin.
  final Alignment3d origin;

  /// The camera a [binding] reads.
  ///
  /// Required by every binding but
  /// [Layout3dCameraBinding.fixedDensity], which is authored rather than
  /// derived. Usually the same camera the enclosing `SceneView` renders
  /// with.
  final Camera? camera;

  /// Ties the surface to the [camera], and with it the unit contract.
  ///
  /// [Layout3dCameraBinding.screenFilling] makes the plane *be* the screen:
  /// it derives the surface's constraints from the view frustum and its
  /// metrics from the view's logical height, and moves the plane to face the
  /// camera, every frame. Such a surface must not also be given a [size] or
  /// [constraints], because the two would fight.
  /// [Layout3dCameraBinding.billboard] turns the plane to face the camera and
  /// touches nothing else; [Layout3dCameraBinding.fixedDensity] states an
  /// authored scale and needs no camera at all.
  ///
  /// The binding is applied once per frame off the enclosing `SceneView`'s
  /// clock, so a moving camera is followed without the application ticking
  /// anything itself.
  final Layout3dCameraBinding? binding;

  /// The logical size of the view a [binding] derives from.
  ///
  /// Leave it null in the common case: the widget takes the size of the
  /// nearest laid-out ancestor box, which under a `SceneView` is the view
  /// itself, so nothing has to be threaded by hand. Supply it when the layout
  /// is not mounted under the view it is bound to, or when the view renders
  /// into a sub-rectangle of its box.
  final Size? viewSize;

  /// The node the plane attaches under.
  ///
  /// Defaults to the enclosing scene widget's node, or the scene root.
  final Node? parent;

  /// The plane's local translation.
  final Vector3? position;

  /// The plane's local rotation.
  final Quaternion? rotation;

  /// The plane's local scale.
  final Vector3? scale;

  /// The plane's local transform, as an alternative to the decomposed form.
  final Matrix4? transform;

  /// Imperative access to the surface this widget owns.
  final Layout3dController? controller;

  /// Tree-wide state every box on this surface can read as [Layout3d.slot].
  ///
  /// The declarative form of [Layout3dSurface.setSlot], for an application
  /// that knows its slots at the root:
  ///
  /// ```dart
  /// SceneLayout3d(
  ///   size: const Size3d(4, 3, 0.2),
  ///   slots: {themeSlot: Theme3dData.light()},
  ///   child: screen,
  /// )
  /// ```
  ///
  /// The map is reconciled on rebuild: a key whose value changed is written,
  /// and a key that disappears is cleared, so this is the whole story and not
  /// a set of initial values. Anything written here relayouts the subtree
  /// when it changes, because a slot is read during layout, so a map rebuilt
  /// with fresh values every frame is a relayout every frame — keep the
  /// values `const` or hold them in a field. [SceneSlotProvider3d] does the
  /// same write from *inside* the tree, which is where a component library's
  /// theme widget will want to sit.
  ///
  /// A value is stored, not owned: nothing here is disposed when the surface
  /// goes away.
  final Map<Layout3dSlot<Object>, Object> slots;

  /// The layout to arrange on the plane.
  final Widget? child;

  @override
  State<SceneLayout3d> createState() => _SceneLayout3dState();
}

class _SceneLayout3dState extends State<SceneLayout3d> {
  late final Layout3dSurface _surface = Layout3dSurface(
    constraints: _configuration,
    basis: widget.basis,
    origin: widget.origin,
  );

  Constraints3d get _configuration {
    final size = widget.size;
    if (size != null) return Constraints3d.tight(size);
    return widget.constraints ?? const Constraints3d();
  }

  /// The enclosing view's per-frame clock, when there is one.
  ///
  /// A binding has to run every frame, and the camera moves without anything
  /// in the widget tree changing, so a rebuild is the wrong signal. The
  /// scene's own elapsed-time notifier is the right one: it ticks once per
  /// rendered frame, which is exactly how often the plane has to be put back
  /// in front of the camera.
  ValueListenable<Duration>? _frames;

  bool _bindingUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._surface = _surface;
    _syncSlots(const <Layout3dSlot<Object>, Object>{});
    assert(_debugCheckBinding());
    _scheduleBindingUpdate();
  }

  /// Applies [SceneLayout3d.slots] onto the surface, clearing what [previous]
  /// held and this build no longer does.
  void _syncSlots(Map<Layout3dSlot<Object>, Object> previous) {
    for (final key in previous.keys) {
      if (widget.slots.containsKey(key)) continue;
      _surface.setSlot(key, null);
    }
    widget.slots.forEach(_surface.setSlot);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final frames = SceneScope.maybeOf(context)?.elapsed;
    if (identical(frames, _frames)) return;
    _frames?.removeListener(_applyBinding);
    _frames = frames;
    frames?.addListener(_applyBinding);
    _scheduleBindingUpdate();
  }

  @override
  void didUpdateWidget(SceneLayout3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(_debugCheckBinding());
    if (!identical(widget.controller, oldWidget.controller)) {
      if (identical(oldWidget.controller?._surface, _surface)) {
        oldWidget.controller?._surface = null;
      }
      widget.controller?._surface = _surface;
    }
    if (!identical(widget.slots, oldWidget.slots)) {
      _syncSlots(oldWidget.slots);
    }
    final binding = widget.binding;
    final oldBinding = oldWidget.binding;
    // A binding that derived a value owned it while it was there, so dropping
    // it (or swapping it for one that derives less) hands the value back to
    // the widget's own props and their defaults, the way a dropped basis
    // does.
    if (oldBinding != null && oldBinding.derivesMetrics && binding == null) {
      _surface.metrics = Layout3dMetrics.standard;
    }
    if (!_bindingOwnsConfiguration) {
      _surface.configuration = _configuration;
    }
    _surface.origin = widget.origin;
    // A null basis means the default, not "leave the last one alone", so
    // dropping the argument on a rebuild puts the plane back upright.
    _surface.basis = widget.basis ?? LayoutBasis3d.xy;
    if (binding != oldBinding ||
        !identical(widget.camera, oldWidget.camera) ||
        widget.viewSize != oldWidget.viewSize) {
      _scheduleBindingUpdate();
    }
  }

  @override
  void dispose() {
    _frames?.removeListener(_applyBinding);
    if (identical(widget.controller?._surface, _surface)) {
      widget.controller?._surface = null;
    }
    _surface.dispose();
    super.dispose();
  }

  /// Whether a binding, rather than [SceneLayout3d.size], decides what the
  /// root child is laid out against.
  bool get _bindingOwnsConfiguration =>
      widget.binding?.derivesConstraints ?? false;

  bool _debugCheckBinding() {
    final binding = widget.binding;
    if (binding == null) return true;
    assert(
      !binding.needsCamera || widget.camera != null,
      'This Layout3dCameraBinding derives the surface from a camera, so '
      'SceneLayout3d needs one. Pass the camera the enclosing SceneView '
      'renders with.',
    );
    assert(
      !binding.derivesConstraints ||
          (widget.size == null && widget.constraints == null),
      'A screen-filling binding derives the surface\'s constraints from the '
      'view frustum, so it cannot also be given a size or constraints of its '
      'own; the two would fight every frame.',
    );
    return true;
  }

  /// Runs the binding once, after this frame.
  ///
  /// The first application cannot happen during build or layout: it reads the
  /// enclosing view's box, and a box's size is only legible to its own parent
  /// while a layout pass is running. After the frame, everything is laid out
  /// and the read is free.
  void _scheduleBindingUpdate() {
    if (_bindingUpdateScheduled || widget.binding == null) return;
    _bindingUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bindingUpdateScheduled = false;
      _applyBinding();
    });
  }

  void _applyBinding() {
    if (!mounted) return;
    final binding = widget.binding;
    if (binding == null) return;
    final camera = widget.camera;
    if (binding.needsCamera && camera == null) return;
    Size? viewSize;
    if (binding.needsViewSize) {
      viewSize = _resolveViewSize();
      if (viewSize == null) return;
    }
    binding.update(_surface, camera: camera, viewSize: viewSize);
  }

  /// The logical size of the view the binding derives from.
  ///
  /// [SceneLayout3d.viewSize] when it is given. Otherwise the size of the
  /// nearest laid-out ancestor box: a declarative scene child is mounted in a
  /// chain of zero-sized hosts (they exist to reconcile the layout tree, not
  /// to take space), so the first ancestor with an extent is the `SceneView`
  /// itself, whose box is the view. Null when there is no such ancestor,
  /// which is the case for a layout pumped on its own, and which the caller
  /// answers by passing [SceneLayout3d.viewSize].
  Size? _resolveViewSize() {
    final explicit = widget.viewSize;
    if (explicit != null) return explicit;
    RenderObject? node = context.findRenderObject();
    while (node != null) {
      if (node is RenderBox && node.hasSize && !node.size.isEmpty) {
        return node.size;
      }
      node = node.parent;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasTransform =
        widget.position != null ||
        widget.rotation != null ||
        widget.scale != null ||
        widget.transform != null;
    Widget mount = hasTransform
        ? SceneNode(
            name: 'SceneLayout3d',
            position: widget.position,
            rotation: widget.rotation,
            scale: widget.scale,
            transform: widget.transform,
            children: [SceneNodeHost(node: _surface.plane)],
          )
        : SceneNodeHost(node: _surface.plane);
    final parent = widget.parent;
    if (parent != null) {
      mount = SceneSubtree(parent: parent, children: [mount]);
    }
    final child = widget.child;
    return _Layout3dRoot(
      surface: _surface,
      children: <Widget>[if (child != null) child, mount],
    );
  }
}

class _Layout3dRoot extends MultiChildRenderObjectWidget {
  const _Layout3dRoot({required this.surface, required super.children});

  final Layout3dSurface surface;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      Layout3dRootRenderBox(surface);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant Layout3dRootRenderBox renderObject,
  ) {
    assert(identical(renderObject.surface, surface));
  }
}
