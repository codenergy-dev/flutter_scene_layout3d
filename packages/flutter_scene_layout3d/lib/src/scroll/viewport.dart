import 'dart:math' as math;

import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'scroll_controller.dart';
import 'scrollable.dart';

/// A window onto a child that may be longer than the window, the 3D analogue
/// of [SingleChildScrollView].
///
/// The child is laid out unbounded along [axis] and the viewport shows the
/// slice at [controller]'s offset. Nothing is culled and nothing is clipped:
/// the child keeps its geometry, it simply slides. For long lists, prefer
/// [ListView3d], which only builds what is near the window.
class Viewport3d extends SingleChildLayout3d implements Scrollable3d {
  /// Creates a scrolling window along [axis].
  Viewport3d({
    Axis3d axis = Axis3d.vertical,
    Scroll3dController? controller,
    super.child,
    super.name,
  }) : _axis = axis,
       _controller = controller ?? Scroll3dController(),
       _ownsController = controller == null {
    _controller.addListener(_handleScrollChanged);
  }

  Axis3d _axis;

  /// The axis the content scrolls along.
  Axis3d get axis => _axis;

  @override
  Axis3d get scrollAxis => _axis;

  set axis(Axis3d value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  Scroll3dController _controller;
  bool _ownsController;

  /// The scroll position, and the metrics this viewport measured.
  @override
  Scroll3dController get controller => _controller;

  set controller(Scroll3dController value) {
    if (identical(_controller, value)) return;
    _controller.removeListener(_handleScrollChanged);
    // A controller supplied from outside belongs to whoever supplied it.
    if (_ownsController) _controller.dispose();
    _ownsController = false;
    _controller = value..addListener(_handleScrollChanged);
    markNeedsLayout();
  }

  bool _layingOut = false;

  void _handleScrollChanged() {
    if (_layingOut) return;
    markNeedsLayout();
  }

  /// A scrolling window takes the hit across its whole extent, gaps between
  /// items included, the way Flutter's `Scrollable` sits behind an opaque
  /// hit-test behaviour. Without that, a drag that starts on empty space
  /// inside the list would fall through to whatever is behind the plane.
  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  void performLayout() {
    _layingOut = true;
    try {
      final child = this.child;
      final axis = _axis;
      final bounded = constraints.hasBoundedAlong(axis);
      if (child == null) {
        size = constraints.constrain(Size3d.zero);
        _controller.applyViewportMetrics(
          maxScrollExtent: 0.0,
          viewportExtent: bounded ? constraints.maxAlong(axis) : 0.0,
          contentExtent: 0.0,
        );
        return;
      }
      child.layout(
        constraints.withAxis(axis, min: 0.0, max: double.infinity),
        parentUsesSize: true,
      );
      final contentExtent = child.size.alongAxis(axis);
      final viewportExtent = bounded
          ? constraints.maxAlong(axis)
          : contentExtent;
      size = constraints.constrain(child.size.withAxis(axis, viewportExtent));
      _controller.applyViewportMetrics(
        maxScrollExtent: math.max(0.0, contentExtent - viewportExtent),
        viewportExtent: viewportExtent,
        contentExtent: contentExtent,
      );
      child.place(Offset3d.along(axis, -_controller.offset));
    } finally {
      _layingOut = false;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScrollChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}
