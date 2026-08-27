import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show ValueListenable, VoidCallback;
import 'package:flutter/rendering.dart' show RenderBox, RenderObject;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        InheritedWidget,
        State,
        StatefulWidget,
        Widget,
        WidgetsBinding;
import 'package:flutter_scene/scene.dart' show Camera, SceneScope;

import '../boxes/stack.dart';
import '../geometry/alignment3d.dart';
import '../layout3d.dart';
import '../overlay/modal_barrier.dart';
import '../overlay/overlay.dart';
import 'framework.dart';

/// Imperative access to the [Overlay3d] a [SceneOverlay3d] owns.
///
/// Attach one where the overlay is described and entries can be inserted from
/// anywhere that has the controller, without a `BuildContext` in hand — a
/// component's own state object, a service, a test.
class Overlay3dController {
  Overlay3d? _overlay;

  /// The overlay, or null while the widget is unmounted.
  Overlay3d? get overlay => _overlay;
}

/// The declarative form of [Overlay3d]: a stack of things in front of
/// everything else.
///
/// Put one high in a layout — around a whole panel, usually — and every
/// descendant can put something in front of it with
/// `SceneOverlay3d.of(context).insertEntry(...)`. The base content is
/// [child]; the entries are inserted imperatively, because that is what
/// "from anywhere, at any time, outliving the widget that asked" means: a
/// dialog opened from a button's callback is not part of that button's
/// subtree.
///
/// ```dart
/// SceneOverlay3d(
///   camera: camera,
///   child: SceneColumn3d(children: [...]),
/// )
///
/// // ... from a button, deep inside:
/// final overlay = SceneOverlay3d.of(context);
/// late final Overlay3dEntry entry;
/// entry = Overlay3dEntry(
///   modal: true,
///   onDismiss: () => entry.remove(),
///   builder: (_) => dialogLayout,
/// );
/// overlay.insertEntry(entry);
/// ```
///
/// An entry's content is a [Layout3d] rather than a widget, which is the one
/// place this differs from Flutter's `Overlay`. The layout objects are the
/// same ones the widgets drive, so nothing is out of reach; what an entry
/// does not get is reconciliation, so a component that rebuilds its dialog
/// calls [Overlay3dEntry.markNeedsBuild].
class SceneOverlay3d extends StatefulWidget {
  /// Creates an overlay over [child].
  const SceneOverlay3d({
    super.key,
    this.alignment = Alignment3d.center,
    this.fit = StackFit3d.loose,
    this.depthStep = 0.0,
    this.camera,
    this.viewSize,
    this.controller,
    this.child,
  });

  /// Where entries and base children sit.
  final Alignment3d alignment;

  /// How non-positioned children are sized.
  final StackFit3d fit;

  /// How far toward the viewer each successive child's geometry is pulled.
  ///
  /// Independent of an entry's own lift, which is
  /// [OverlayLayer3d.inPlane]'s job.
  final double depthStep;

  /// The camera the detached entries' bindings read.
  ///
  /// With one, [Overlay3d.updateCameraBindings] runs off the enclosing
  /// scene's per-frame clock, so a billboarded dialog keeps facing the viewer
  /// without the application ticking anything. Entries without a binding cost
  /// nothing.
  final Camera? camera;

  /// The logical size of the view a screen-filling entry derives from.
  ///
  /// Leave it null in the common case: the size of the nearest laid-out
  /// ancestor box is used, which under a `SceneView` is the view itself.
  final Size? viewSize;

  /// Imperative access to the overlay this widget owns.
  final Overlay3dController? controller;

  /// The content the entries stand in front of.
  final Widget? child;

  /// The overlay above [context].
  ///
  /// Throws when there is none, which is a programming error: a component
  /// that opens a dialog needs somewhere to put it. Use [maybeOf] where the
  /// absence is a real case.
  static Overlay3d of(BuildContext context) {
    final overlay = maybeOf(context);
    assert(
      overlay != null,
      'SceneOverlay3d.of found no SceneOverlay3d above this context. Wrap the '
      'part of the layout that opens dialogs in one.',
    );
    return overlay!;
  }

  /// The overlay above [context], or null.
  static Overlay3d? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Overlay3dScope>()?.overlay;

  @override
  State<SceneOverlay3d> createState() => _SceneOverlay3dState();
}

class _SceneOverlay3dState extends State<SceneOverlay3d> {
  late final Overlay3d _overlay = Overlay3d(
    alignment: widget.alignment,
    fit: widget.fit,
    depthStep: widget.depthStep,
    name: 'SceneOverlay3d',
  );

  /// The enclosing view's per-frame clock, when there is one.
  ///
  /// A camera binding has to run every frame and the camera moves without
  /// anything in the widget tree changing, so a rebuild is the wrong signal —
  /// the same reasoning [SceneLayout3d] follows for its own binding.
  ValueListenable<Duration>? _frames;

  @override
  void initState() {
    super.initState();
    widget.controller?._overlay = _overlay;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyBindings());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final frames = SceneScope.maybeOf(context)?.elapsed;
    if (identical(frames, _frames)) return;
    _frames?.removeListener(_applyBindings);
    _frames = frames;
    frames?.addListener(_applyBindings);
  }

  @override
  void didUpdateWidget(SceneOverlay3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      if (identical(oldWidget.controller?._overlay, _overlay)) {
        oldWidget.controller?._overlay = null;
      }
      widget.controller?._overlay = _overlay;
    }
  }

  @override
  void dispose() {
    _frames?.removeListener(_applyBindings);
    if (identical(widget.controller?._overlay, _overlay)) {
      widget.controller?._overlay = null;
    }
    // The entries are this widget's to release: each detached one holds a
    // surface of its own, which nothing else in the tree walks over. The
    // overlay layout itself follows the rule every layout widget keeps and is
    // disposed with the surface it hangs in.
    _overlay.clearEntries();
    super.dispose();
  }

  void _applyBindings() {
    if (!mounted) return;
    final camera = widget.camera;
    if (camera == null) return;
    _overlay.updateCameraBindings(camera: camera, viewSize: _resolveViewSize());
  }

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
    final child = widget.child;
    return _Overlay3dScope(
      overlay: _overlay,
      child: _Overlay3dWidget(
        overlay: _overlay,
        alignment: widget.alignment,
        fit: widget.fit,
        depthStep: widget.depthStep,
        children: <Widget>[if (child != null) child],
      ),
    );
  }
}

/// Carries the overlay down to the descendants that put things in it.
class _Overlay3dScope extends InheritedWidget {
  const _Overlay3dScope({required this.overlay, required super.child});

  final Overlay3d overlay;

  @override
  bool updateShouldNotify(_Overlay3dScope oldWidget) =>
      !identical(overlay, oldWidget.overlay);
}

/// Hosts the overlay the state owns.
///
/// The layout is made by the state rather than by [createLayout], because
/// [SceneOverlay3d.of] has to hand it to descendants that are built *inside*
/// this widget: the handle has to exist before the subtree it serves does.
class _Overlay3dWidget extends Layout3dWidget {
  const _Overlay3dWidget({
    required this.overlay,
    required this.alignment,
    required this.fit,
    required this.depthStep,
    required super.children,
  });

  final Overlay3d overlay;
  final Alignment3d alignment;
  final StackFit3d fit;
  final double depthStep;

  @override
  Overlay3d createLayout(BuildContext context) => overlay;

  @override
  void updateLayout(BuildContext context, Overlay3d layout) {
    assert(identical(layout, overlay));
    layout
      ..alignment = alignment
      ..fit = fit
      ..depthStep = depthStep;
  }
}

/// The declarative form of [ModalBarrier3d]: a slab that fills what it is
/// given, swallows every ray, and reports the tap that should dismiss what is
/// in front of it.
///
/// [Overlay3dEntry.modal] puts one in for you; this is for a barrier that is
/// part of a layout described in widgets.
class SceneModalBarrier3d extends SingleChildLayout3dWidget {
  /// Creates a barrier.
  const SceneModalBarrier3d({
    super.key,
    this.onDismiss,
    this.dismissible = true,
    this.thickness = 0.0,
    super.child,
  });

  /// Called when a tap lands on the barrier itself.
  final VoidCallback? onDismiss;

  /// Whether a tap calls [onDismiss].
  final bool dismissible;

  /// The barrier's extent along the depth axis, in world units.
  final double thickness;

  @override
  ModalBarrier3d createLayout(BuildContext context) => ModalBarrier3d(
    onDismiss: onDismiss,
    dismissible: dismissible,
    thickness: thickness,
  );

  @override
  void updateLayout(BuildContext context, ModalBarrier3d layout) {
    layout
      ..onDismiss = onDismiss
      ..dismissible = dismissible
      ..thickness = thickness;
  }
}
