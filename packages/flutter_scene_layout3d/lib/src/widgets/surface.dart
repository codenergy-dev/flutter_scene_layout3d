import 'dart:ui' show Size;

import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty, ValueListenable;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        InheritedWidget,
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
    this.metrics,
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

  /// The unit contract the whole tree is specified in: how many world units
  /// a logical pixel is worth, and the dials a component library reads beside
  /// it.
  ///
  /// The authored answer, for a panel that is not standing in for a screen —
  /// one on a wall, one on a table, one turned to face the viewer by
  /// [Layout3dCameraBinding.billboard]. Everything below reads it as
  /// [Layout3d.metrics], and a `build` method reads it as
  /// [Layout3dMetricsScope.of].
  ///
  /// Null means [Layout3dMetrics.standard], not "leave the last one alone":
  /// dropping the property on a rebuild puts the default contract back, the
  /// way dropping [basis] puts the plane back upright.
  ///
  /// **A binding that derives the contract owns it.**
  /// [Layout3dCameraBinding.screenFilling] and
  /// [Layout3dCameraBinding.fixedDensity] both write the surface's metrics
  /// every frame, so stating one here as well is an error the way giving a
  /// screen-filling binding a [size] is: the two would fight.
  final Layout3dMetrics? metrics;

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
    metrics: widget.metrics ?? Layout3dMetrics.standard,
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
    _surface.metricsListenable.addListener(_handleMetricsChanged);
    _syncSlots(const <Layout3dSlot<Object>, Object>{});
    assert(_debugCheckBinding());
    _scheduleBindingUpdate();
  }

  /// Whether the metrics being written is this state's own doing, and so is
  /// already on its way into the next build.
  bool _writingMetrics = false;

  bool _metricsRebuildScheduled = false;

  /// Writes the authored contract, without taking the change as news.
  void _writeMetrics(Layout3dMetrics value) {
    _writingMetrics = true;
    try {
      _surface.metrics = value;
    } finally {
      _writingMetrics = false;
    }
  }

  /// Republishes the contract a binding derived behind the widget layer's
  /// back.
  ///
  /// A binding writes the surface directly, from the enclosing view's
  /// per-frame clock (a `Ticker`, so the transient phase) or from a
  /// post-frame callback. Both are outside build and layout, so the rebuild
  /// this asks for lands in a build phase that *precedes* the layout the new
  /// contract governs, and a padding converted in `build` is never measured
  /// against a different number than the boxes below use.
  ///
  /// The exception is a write from inside the frame itself — `Overlay3d`
  /// pushes the host's contract onto a detached entry's surface during
  /// `performLayout` — where marking this element dirty is either illegal or
  /// too late to matter. That one takes the next frame.
  void _handleMetricsChanged() {
    if (_writingMetrics || !mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_metricsRebuildScheduled) return;
      _metricsRebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _metricsRebuildScheduled = false;
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
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
    // A binding that derives a value owns it while it is there, so dropping
    // it (or swapping it for one that derives less) hands the value back to
    // the widget's own props and their defaults, the way a dropped basis
    // does.
    if (!_bindingOwnsMetrics) {
      _writeMetrics(widget.metrics ?? Layout3dMetrics.standard);
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
    _surface.metricsListenable.removeListener(_handleMetricsChanged);
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

  /// Whether a binding, rather than [SceneLayout3d.metrics], decides the unit
  /// contract.
  bool get _bindingOwnsMetrics => widget.binding?.derivesMetrics ?? false;

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
    assert(
      !binding.derivesMetrics || widget.metrics == null,
      'This Layout3dCameraBinding writes the surface\'s metrics every frame, '
      'so it cannot also be given a metrics of its own; the two would fight. '
      'State the contract on the binding (Layout3dCameraBinding.fixedDensity) '
      'or drop the binding.',
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
      children: <Widget>[
        if (child != null)
          Layout3dMetricsScope._(metrics: _surface.metrics, child: child),
        mount,
      ],
    );
  }
}

/// The unit contract in force on the enclosing surface, for a `build` method.
///
/// Everything this package lays out is measured in world units; everything a
/// component library is *specified* in is measured in logical pixels. A
/// `Layout3d` joins the two inside `performLayout`, where the owner's
/// [Layout3dMetrics] is one getter away. A widget cannot reach that, so
/// [SceneLayout3d] publishes the same value here and a build method converts
/// its own figures before they ever reach a box:
///
/// ```dart
/// Widget build(BuildContext context) {
///   final metrics = Layout3dMetricsScope.of(context);
///   return ScenePadding3d(
///     // 16dp, the way a Material spec figure is written.
///     padding: metrics.dpInsets(const EdgeInsets3d.all(16)),
///     child: SceneSizedBox3d(height: metrics.dp(56), child: child),
///   );
/// }
/// ```
///
/// **A dependent rebuilds before the layout that uses what it computed.** A
/// camera-bound surface derives its contract during the frame, which sounds
/// like a value read in `build` could be a frame behind the boxes below, and
/// it is not: a binding is applied from the enclosing view's per-frame clock
/// (a `Ticker`, so the transient phase) or from a post-frame callback, never
/// from build or layout, so the rebuild it triggers lands in a build phase
/// that precedes the layout phase the new contract governs. What *is* one
/// frame behind on a window resize is the binding itself, since it reads a
/// view box that is only resized during layout — and that lag is shared by
/// the surface's constraints, which the same call derives from the same
/// numbers, so the panel's size and its unit contract never disagree.
///
/// **Reading this does not replace the relayout.** Writing
/// [Layout3dSurface.metrics] relayouts the whole subtree by design, because a
/// box that sized itself `metrics.dp(48)` is a different box afterward and
/// nothing hands it the number as a constraint. This scope adds a rebuild in
/// front of that relayout for the widgets that read it; it does not make a
/// metrics change any cheaper.
///
/// There is no public constructor, deliberately. The value is a report of
/// what the surface's owner actually measures with, and a second scope
/// inserted by hand would change what [of] answers without changing what a
/// single box measures — a divergence nothing would report. To give a
/// subtree a different contract, give it a surface.
class Layout3dMetricsScope extends InheritedWidget {
  const Layout3dMetricsScope._({required this.metrics, required super.child});

  /// What a logical pixel is worth on the enclosing surface.
  final Layout3dMetrics metrics;

  /// The contract in force above [context], or null when there is no surface.
  ///
  /// The caller becomes a dependent: it rebuilds when the contract changes.
  static Layout3dMetrics? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<Layout3dMetricsScope>()
      ?.metrics;

  /// The contract in force above [context].
  ///
  /// The caller becomes a dependent: it rebuilds when the contract changes.
  /// Asserts when there is no [SceneLayout3d] above, because the alternative
  /// — quietly answering [Layout3dMetrics.standard] — is the unit mistake
  /// this whole contract exists to prevent, and it would be silent.
  static Layout3dMetrics of(BuildContext context) {
    final metrics = maybeOf(context);
    assert(
      metrics != null,
      'Layout3dMetricsScope.of() found no surface above this context. The '
      'unit contract is published by SceneLayout3d, so a widget that converts '
      'a dp figure has to be built inside one; use maybeOf() if being outside '
      'is a legitimate state.',
    );
    return metrics!;
  }

  @override
  bool updateShouldNotify(Layout3dMetricsScope oldWidget) =>
      oldWidget.metrics != metrics;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Layout3dMetrics>('metrics', metrics));
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
