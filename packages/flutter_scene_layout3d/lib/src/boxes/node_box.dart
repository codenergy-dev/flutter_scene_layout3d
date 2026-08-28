import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        DiagnosticsProperty,
        EnumProperty,
        protected,
        StringProperty;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' show Aabb3, Matrix4;

import '../geometry/alignment3d.dart';
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
  Size3d _contentScale = const Size3d.cube(1);

  /// The scale [fit] applied to the content in the most recent layout.
  ///
  /// One on every axis means the content is at its authored size. Handy when
  /// a model comes out larger or smaller than expected and the question is
  /// whether the fit or the measurement is responsible.
  Size3d get contentScale => _contentScale;

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

  /// The content's own extent, which is exactly what an intrinsic query
  /// wants: this is the leaf where a real answer comes from, and every box
  /// above it is adding to or holding down what is measured here.
  ///
  /// The minimum and the maximum are the same. Content in a scene does not
  /// reflow — a model asked to fit into less room is scaled by [fit], not
  /// rearranged — so there is no extent past which more room buys something,
  /// and none below which it starts giving something up.
  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      intrinsicSize.alongAxis(axis);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      intrinsicSize.alongAxis(axis);

  @override
  void performLayout() {
    _measure();
    final intrinsic = _explicitSize ?? _measuredSize;

    // The box takes its size the way any leaf does, from the constraints and
    // what it measured; [fit] then decides how the content is scaled into
    // that size. Doing it in this order is what keeps a loose parent from
    // inflating the box, the same contract Flutter's FittedBox keeps.
    size = constraints.constrain(intrinsic);
    final scale = _scaleFor(intrinsic, size);
    _contentScale = scale;
    final scaled = Size3d(
      intrinsic.width * scale.width,
      intrinsic.height * scale.height,
      intrinsic.depth * scale.depth,
    );

    // Place the content inside the box, then undo the surface basis so the
    // model keeps the orientation it was authored with.
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

  /// The leaf answers hits on its own account: it is the box that stands for
  /// something in the scene, so it is the one a pointer is aimed at. The hit
  /// is against the *box*, not the geometry inside it, which is what makes a
  /// model with a ragged silhouette still easy to point at. For a triangle
  /// exact answer, raycast the content node with the engine's `raycastNode`.
  ///
  /// Wrap the box in an [IgnorePointer3d] for content that should not be
  /// pointable at all.
  @override
  bool hitTestSelf(Offset3d position) => true;

  Size3d _scaleFor(Size3d intrinsic, Size3d box) => switch (_fit) {
    BoxFit3d.none => const Size3d.cube(1),
    BoxFit3d.fill => Size3d(
      _axisScale(intrinsic.width, box.width),
      _axisScale(intrinsic.height, box.height),
      _axisScale(intrinsic.depth, box.depth),
    ),
    BoxFit3d.contain => Size3d.cube(_uniformScale(intrinsic, box)),
    BoxFit3d.scaleDown => Size3d.cube(
      math.min(1.0, _uniformScale(intrinsic, box)),
    ),
  };

  /// The scale taking [from] to [to] on one axis.
  ///
  /// An axis with nothing to measure or no room to fill is left alone rather
  /// than collapsed: a box squeezed to zero depth (a panel whose padding ate
  /// its thickness, say) should still show its content, flat against the
  /// plane, instead of scaling it out of existence.
  static double _axisScale(double from, double to) {
    if (from <= 0.0 || to <= 0.0 || !to.isFinite) return 1.0;
    return to / from;
  }

  /// The largest uniform scale that fits [intrinsic] inside [box].
  ///
  /// Degenerate axes are skipped for the same reason [_axisScale] leaves them
  /// alone; a single zero-extent axis must not zero the whole scale.
  static double _uniformScale(Size3d intrinsic, Size3d box) {
    var scale = double.infinity;
    for (final (extent, limit) in <(double, double)>[
      (intrinsic.width, box.width),
      (intrinsic.height, box.height),
      (intrinsic.depth, box.depth),
    ]) {
      if (extent <= 0.0 || limit <= 0.0 || !limit.isFinite) continue;
      scale = math.min(scale, limit / extent);
    }
    return scale.isFinite ? scale : 1.0;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<BoxFit3d>('fit', fit));
    properties.add(DiagnosticsProperty<Alignment3d>('alignment', alignment));
    properties.add(
      DiagnosticsProperty<Size3d>(
        'explicitSize',
        explicitSize,
        defaultValue: null,
      ),
    );
    properties.add(DiagnosticsProperty<Size3d>('intrinsicSize', intrinsicSize));
    properties.add(StringProperty('content', content.name, quoted: true));
  }
}
