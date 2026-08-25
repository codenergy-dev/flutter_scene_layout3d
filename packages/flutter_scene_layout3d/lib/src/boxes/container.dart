import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' show Matrix4;

import '../geometry/alignment3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/edge_insets3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// A convenience box combining margin, constraints, padding, alignment, and a
/// transform, the 3D analogue of [Container].
///
/// The composition order is Flutter's, from the outside in: [margin], then
/// [constraints] (and [width] / [height] / [depth]), then [padding], then
/// [alignment]. [transform] is applied last and, as in Flutter, affects only
/// where the content lands, never the layout.
///
/// This is a layout container. Making it *visible* (a panel, a frame, a
/// backing plane) is a matter of putting a mesh in the tree, which is what
/// `NodeBox3d` is for; nothing in this package draws on its own.
class Container3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a container.
  Container3d({
    Alignment3d? alignment,
    EdgeInsets3d padding = EdgeInsets3d.zero,
    EdgeInsets3d margin = EdgeInsets3d.zero,
    Constraints3d? constraints,
    double? width,
    double? height,
    double? depth,
    Matrix4? transform,
    Alignment3d transformAlignment = Alignment3d.center,
    super.child,
    super.name,
  }) : _alignment = alignment,
       _padding = padding,
       _margin = margin,
       _transform = transform == null ? null : Matrix4.copy(transform),
       _transformAlignment = transformAlignment,
       _additionalConstraints = resolveConstraints(
         constraints,
         width,
         height,
         depth,
       ),
       assert(padding.isNonNegative),
       assert(margin.isNonNegative);

  /// Folds fixed extents into [constraints], the way the constructor does.
  ///
  /// Public so a declarative layer can redo the fold when the properties
  /// change without rebuilding the layout object.
  static Constraints3d? resolveConstraints(
    Constraints3d? constraints,
    double? width,
    double? height,
    double? depth,
  ) {
    if (width == null && height == null && depth == null) return constraints;
    final tightened = Constraints3d.tightFor(
      width: width,
      height: height,
      depth: depth,
    );
    if (constraints == null) return tightened;
    return constraints.tighten(width: width, height: height, depth: depth);
  }

  Alignment3d? _alignment;

  /// Where the child sits inside the padded content box.
  ///
  /// Null means the container shrink-wraps the child, exactly as a Flutter
  /// `Container` without an alignment does.
  Alignment3d? get alignment => _alignment;

  set alignment(Alignment3d? value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  EdgeInsets3d _padding;

  /// Space between the container's faces and its child.
  EdgeInsets3d get padding => _padding;

  set padding(EdgeInsets3d value) {
    if (_padding == value) return;
    assert(value.isNonNegative);
    _padding = value;
    markNeedsLayout();
  }

  EdgeInsets3d _margin;

  /// Space around the container, inside the box it was given.
  EdgeInsets3d get margin => _margin;

  set margin(EdgeInsets3d value) {
    if (_margin == value) return;
    assert(value.isNonNegative);
    _margin = value;
    markNeedsLayout();
  }

  Constraints3d? _additionalConstraints;

  /// Extra constraints imposed on the content, before padding.
  Constraints3d? get additionalConstraints => _additionalConstraints;

  set additionalConstraints(Constraints3d? value) {
    if (_additionalConstraints == value) return;
    _additionalConstraints = value;
    markNeedsLayout();
  }

  Matrix4? _transform;

  /// A transform applied to the container's contents, in layout space.
  ///
  /// Returns a copy; assign a new matrix rather than mutating this one.
  Matrix4? get transform =>
      _transform == null ? null : Matrix4.copy(_transform!);

  set transform(Matrix4? value) {
    if (_transform == value) return;
    _transform = value == null ? null : Matrix4.copy(value);
    if (hasSize) applyNodeTransform();
  }

  Alignment3d _transformAlignment;

  /// The point [transform] pivots around.
  Alignment3d get transformAlignment => _transformAlignment;

  set transformAlignment(Alignment3d value) {
    if (_transformAlignment == value) return;
    _transformAlignment = value;
    if (hasSize) applyNodeTransform();
  }

  @override
  Matrix4? get localTransform {
    final transform = _transform;
    if (transform == null) return null;
    if (!hasSize) return Matrix4.copy(transform);
    final origin = _transformAlignment.alongSize(size);
    return Matrix4.translationValues(origin.x, origin.y, origin.z)
        .multiplied(transform)
        .multiplied(Matrix4.translationValues(-origin.x, -origin.y, -origin.z));
  }

  /// The child's intrinsic extent, taken through the same sequence
  /// [performLayout] uses: padding is added to it, the extra constraints hold
  /// the result, and the margin is added around that.
  ///
  /// [alignment] plays no part. An aligning container fills whatever bounded
  /// room it is given, and an intrinsic query is asking what it would do
  /// without being given any.
  double _containerIntrinsic(Axis3d axis, Size3d limits, {required bool min}) {
    final insets = _margin + _padding;
    var content = _padding.alongAxis(axis);
    final child = this.child;
    if (child != null) {
      var childLimits = limits;
      for (final other in Axis3d.values) {
        if (other == axis) continue;
        childLimits = childLimits.withAxis(
          other,
          math.max(0.0, limits.alongAxis(other) - insets.alongAxis(other)),
        );
      }
      content += min
          ? child.getMinIntrinsicExtent(axis, childLimits)
          : child.getMaxIntrinsicExtent(axis, childLimits);
    }
    final extra = _additionalConstraints;
    final inner = extra == null || !extra.minAlong(axis).isFinite
        ? content
        : extra.constrainAlong(axis, content);
    return inner + _margin.alongAxis(axis);
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _containerIntrinsic(axis, limits, min: true);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _containerIntrinsic(axis, limits, min: false);

  @override
  void performLayout() {
    final incoming = constraints;
    final afterMargin = incoming.deflate(_margin);
    final inner = _additionalConstraints == null
        ? afterMargin
        : _additionalConstraints!.enforce(afterMargin);

    final child = this.child;
    if (child == null) {
      // Like a Flutter Container with no child: as big as it is allowed to
      // be, and no bigger than the padding when that is unbounded.
      final content = Size3d(
        inner.hasBoundedWidth ? inner.maxWidth : _padding.horizontal,
        inner.hasBoundedHeight ? inner.maxHeight : _padding.vertical,
        inner.hasBoundedDepth ? inner.maxDepth : _padding.depth,
      );
      size = incoming.constrain(_margin.inflateSize(inner.constrain(content)));
      applyNodeTransform();
      return;
    }

    final contentConstraints = inner.deflate(_padding);
    final alignment = _alignment;
    child.layout(
      alignment == null ? contentConstraints : contentConstraints.loosen(),
      parentUsesSize: true,
    );
    final childSize = child.size;

    final Size3d contentSize;
    if (alignment == null) {
      contentSize = childSize;
    } else {
      // The aligning content box fills every axis it is bounded on, and
      // shrink-wraps the rest, the way Align does.
      contentSize = contentConstraints.constrain(
        Size3d(
          contentConstraints.hasBoundedWidth
              ? contentConstraints.maxWidth
              : childSize.width,
          contentConstraints.hasBoundedHeight
              ? contentConstraints.maxHeight
              : childSize.height,
          contentConstraints.hasBoundedDepth
              ? contentConstraints.maxDepth
              : childSize.depth,
        ),
      );
    }

    final innerSize = inner.constrain(_padding.inflateSize(contentSize));
    size = incoming.constrain(_margin.inflateSize(innerSize));

    final contentBox = _padding.deflateSize(innerSize);
    final childOffset =
        _margin.topLeftFront +
        _padding.topLeftFront +
        (alignment == null
            ? Offset3d.zero
            : alignment.inscribe(childSize, contentBox));
    child.place(childOffset);
    applyNodeTransform();
  }
}
