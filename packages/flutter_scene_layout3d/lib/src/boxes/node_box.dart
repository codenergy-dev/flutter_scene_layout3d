import 'dart:math' as math;

import 'package:flutter/foundation.dart' show protected;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' show Aabb3, Matrix4;

import '../geometry/alignment3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// How a [NodeBox3d] scales its content to the room it is given, the 3D
/// analogue of [BoxFit].
enum BoxFit3d {
  /// Never scale. The box takes the content's own size, clamped to the
  /// constraints.
  none,

  /// Scale uniformly until the content just fits inside the bounded axes.
  contain,

  /// Scale each axis independently to fill the bounded axes.
  fill,

  /// Like [contain], but never scale up.
  scaleDown,
}

/// A leaf that puts an engine [Node] into the layout, measuring the content's
/// own bounds to answer "how big am I?".
///
/// This is the bridge between the layout protocol and actual 3D content:
/// primitives, imported models, whole subtrees. The size comes from
/// [Node.combinedLocalBounds], the axis-aligned box covering the node's mesh
/// and every descendant's, mapped out of scene space by the surface's
/// [LayoutBasis3d]. Content that cannot report bounds (skinned meshes,
/// caller-managed geometry) measures as [fallbackSize]; pass [explicitSize]
/// to state a size outright and skip measuring altogether.
///
/// The box owns the content node's `localTransform`: it centers the measured
/// bounds in the box, applies [fit] and [alignment], and undoes the surface
/// basis so the model keeps its own upright orientation. Content that needs
/// an offset of its own should be wrapped in a plain [Node] and handed over
/// as that.
class NodeBox3d extends Layout3d {
  /// Puts [content] into the layout.
  NodeBox3d({
    required Node content,
    BoxFit3d fit = BoxFit3d.none,
    Alignment3d alignment = Alignment3d.center,
    Size3d? explicitSize,
    Size3d fallbackSize = Size3d.zero,
    super.name,
  }) : _content = content,
       _fit = fit,
       _alignment = alignment,
       _explicitSize = explicitSize,
       _fallbackSize = fallbackSize {
    node.add(_content);
  }

  Node _content;

  /// The engine content this box positions.
  Node get content => _content;

  set content(Node value) {
    if (identical(_content, value)) return;
    node.remove(_content);
    _content = value;
    node.add(value);
    markParentNeedsLayout();
  }

  BoxFit3d _fit;

  /// How the content is scaled into the space available.
  BoxFit3d get fit => _fit;

  set fit(BoxFit3d value) {
    if (_fit == value) return;
    _fit = value;
    markParentNeedsLayout();
  }

  Alignment3d _alignment;

  /// Where the content sits inside this box.
  Alignment3d get alignment => _alignment;

  set alignment(Alignment3d value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  Size3d? _explicitSize;

  /// A size to use instead of measuring the content.
  Size3d? get explicitSize => _explicitSize;

  set explicitSize(Size3d? value) {
    if (_explicitSize == value) return;
    _explicitSize = value;
    markParentNeedsLayout();
  }

  Size3d _fallbackSize;

  /// The size used when the content cannot report bounds.
  Size3d get fallbackSize => _fallbackSize;

  set fallbackSize(Size3d value) {
    if (_fallbackSize == value) return;
    _fallbackSize = value;
    markParentNeedsLayout();
  }

  Size3d _measuredSize = Size3d.zero;
  Offset3d _measuredCenter = Offset3d.zero;

  /// The content's own extent in layout space, before [fit] scales it.
  Size3d get intrinsicSize {
    _measure();
    return _explicitSize ?? _measuredSize;
  }

  /// Re-reads the content's bounds and relayouts.
  ///
  /// Node bounds are cached by the engine; call this after changing the
  /// content's geometry in place, which the cache cannot see.
  void remeasure() {
    _content.markBoundsDirty();
    markParentNeedsLayout();
  }

  /// The content's extent in scene space, or null when it cannot report one.
  ///
  /// Reads [Node.combinedLocalBounds] by default. Override to measure content
  /// the engine cannot bound on its own (a skinned mesh, caller-managed
  /// geometry) or to take the extent from somewhere else entirely.
  @protected
  Aabb3? readContentBounds() => _content.combinedLocalBounds;

  void _measure() {
    final bounds = readContentBounds();
    if (bounds == null) {
      _measuredSize = _fallbackSize;
      _measuredCenter = Offset3d.zero;
      return;
    }
    final basis = this.basis;
    _measuredSize = basis.sizeOfBounds(bounds);
    _measuredCenter = basis.centerOfBounds(bounds);
  }

  @override
  void performLayout() {
    _measure();
    final measured = _explicitSize ?? _measuredSize;
    final constraints = this.constraints;

    final scale = switch (_fit) {
      BoxFit3d.none => const Size3d.cube(1),
      BoxFit3d.fill => Size3d(
        _axisScale(measured.width, constraints.maxWidth),
        _axisScale(measured.height, constraints.maxHeight),
        _axisScale(measured.depth, constraints.maxDepth),
      ),
      BoxFit3d.contain => Size3d.cube(_uniformScale(measured, constraints)),
      BoxFit3d.scaleDown => Size3d.cube(
        math.min(1.0, _uniformScale(measured, constraints)),
      ),
    };

    final scaled = Size3d(
      measured.width * scale.width,
      measured.height * scale.height,
      measured.depth * scale.depth,
    );
    size = constraints.constrain(scaled);

    // Place the content inside the box we just took, then undo the surface
    // basis so the model keeps the orientation it was authored with.
    final origin = _alignment.inscribe(scaled, size);
    final target = origin + scaled.center;
    _content.localTransform =
        Matrix4.translationValues(target.x, target.y, target.z)
            .multiplied(
              Matrix4.diagonal3Values(scale.width, scale.height, scale.depth),
            )
            .multiplied(
              Matrix4.translationValues(
                -_measuredCenter.x,
                -_measuredCenter.y,
                -_measuredCenter.z,
              ),
            )
            .multiplied(basis.toLayoutMatrix);
  }

  static double _axisScale(double measured, double available) {
    if (measured <= 0.0 || !available.isFinite) return 1.0;
    return available / measured;
  }

  static double _uniformScale(Size3d measured, Constraints3d constraints) {
    var scale = double.infinity;
    for (final (extent, limit) in <(double, double)>[
      (measured.width, constraints.maxWidth),
      (measured.height, constraints.maxHeight),
      (measured.depth, constraints.maxDepth),
    ]) {
      if (extent <= 0.0 || !limit.isFinite) continue;
      scale = math.min(scale, limit / extent);
    }
    return scale.isFinite ? scale : 1.0;
  }
}
