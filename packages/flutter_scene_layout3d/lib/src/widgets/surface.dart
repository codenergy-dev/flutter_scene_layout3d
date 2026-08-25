import 'package:flutter/widgets.dart'
    show
        BuildContext,
        MultiChildRenderObjectWidget,
        State,
        StatefulWidget,
        Widget;
import 'package:flutter/rendering.dart' show RenderObject;
import 'package:flutter_scene/scene.dart'
    show Node, SceneNode, SceneNodeHost, SceneSubtree;
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import '../geometry/alignment3d.dart';
import '../geometry/basis3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/size3d.dart';
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
    this.parent,
    this.position,
    this.rotation,
    this.scale,
    this.transform,
    this.controller,
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

  @override
  void initState() {
    super.initState();
    widget.controller?._surface = _surface;
  }

  @override
  void didUpdateWidget(SceneLayout3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      if (identical(oldWidget.controller?._surface, _surface)) {
        oldWidget.controller?._surface = null;
      }
      widget.controller?._surface = _surface;
    }
    _surface.configuration = _configuration;
    _surface.origin = widget.origin;
    // A null basis means the default, not "leave the last one alone", so
    // dropping the argument on a rebuild puts the plane back upright.
    _surface.basis = widget.basis ?? LayoutBasis3d.xy;
  }

  @override
  void dispose() {
    if (identical(widget.controller?._surface, _surface)) {
      widget.controller?._surface = null;
    }
    _surface.dispose();
    super.dispose();
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
