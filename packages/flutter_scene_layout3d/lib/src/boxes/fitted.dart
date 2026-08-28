import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty, EnumProperty;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import '../geometry/alignment3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import 'node_box.dart' show BoxFit3d;

/// A box that lays its child out at whatever size it wants and then scales
/// the result into the room available, the 3D analogue of [FittedBox].
///
/// [NodeBox3d] already does this for engine content, where "the content" is a
/// mesh with bounds. This is the same idea for a laid-out *subtree*: the child
/// is laid out under unbounded constraints, so it reports its natural size,
/// and the difference between that and the room this box was given becomes a
/// scale on the child's scene node. Nothing below is laid out twice, and
/// nothing below knows it was scaled — which is exactly why a scaled subtree
/// is cheap here and why the text in it does not re-shape.
///
/// It is also why the result is not the same as sizing the child down. A
/// [Text3d] scaled to 0.5 is a half-size glyph run, not a run laid out for
/// half the width; a decorated box scaled to 0.5 has half-size corners, not
/// corners of the size the design system asked for. Reach for this when the
/// subtree is a picture of a fixed thing (a preview, a thumbnail, a scene
/// miniature); reach for constraints when it is a piece of user interface
/// that should stay legible.
///
/// ## Hit testing
///
/// The scale lives in [localTransform], which makes this box a relative of
/// [Transform3d] — and that box is the documented exception in hit testing:
/// it neither answers a hit itself nor gates its children on its own extent,
/// because its size is measured in the frame *before* the matrix and the two
/// cannot be compared.
///
/// This box does better, on the half that can be done better. Its size is the
/// room it fills, in the frame the ray arrives in, and the scale is what puts
/// the child inside that room — so the extent gate is meaningful here and is
/// applied: a ray that misses the fitted box misses everything in it, and one
/// that hits it is mapped through the scale so it reaches the child where the
/// viewer sees it. What it keeps from [Transform3d] is the other half: it is
/// not a target itself, so a ray through a gap in the child passes on
/// through.
///
/// The gate is exact for every fit that puts the child inside the box, which
/// is all of them except [BoxFit3d.none], where a child larger than the box
/// keeps its own size and the part outside the box is out of reach. That is
/// the same bargain Flutter strikes, where the overflowing part is clipped.
class FittedBox3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a box that scales its child into the room available.
  FittedBox3d({
    BoxFit3d fit = BoxFit3d.contain,
    Alignment3d alignment = Alignment3d.center,
    super.child,
    super.name,
  }) : _fit = fit,
       _alignment = alignment;

  BoxFit3d _fit;

  /// How the child is scaled into the room available.
  BoxFit3d get fit => _fit;

  set fit(BoxFit3d value) {
    if (_fit == value) return;
    _fit = value;
    markNeedsLayout();
  }

  Alignment3d _alignment;

  /// Where the scaled child sits inside this box.
  Alignment3d get alignment => _alignment;

  set alignment(Alignment3d value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  Vector3 _scale = Vector3.all(1);

  /// The scale currently applied to the child, per axis.
  ///
  /// Meaningful once this box has been laid out. All ones until then, and for
  /// [BoxFit3d.none].
  Vector3 get scale => _scale.clone();

  Offset3d _childOrigin = Offset3d.zero;

  /// Where the scaled child's origin corner sits in this box.
  Offset3d get childOrigin => _childOrigin;

  @override
  Matrix4? get localTransform {
    if (_scale.x == 1.0 && _scale.y == 1.0 && _scale.z == 1.0) {
      if (_childOrigin == Offset3d.zero) return null;
      return Matrix4.translationValues(
        _childOrigin.x,
        _childOrigin.y,
        _childOrigin.z,
      );
    }
    return Matrix4.translationValues(
      _childOrigin.x,
      _childOrigin.y,
      _childOrigin.z,
    )..multiply(Matrix4.diagonal3(_scale));
  }

  /// The per-axis scale taking [source] to [destination] under [fit].
  ///
  /// An axis the child has no extent on — a flat panel's depth — is left at
  /// one and kept out of the uniform fits, because a zero extent has no ratio
  /// to a finite one and letting it in would scale the whole subtree to
  /// nothing or to infinity.
  static Vector3 fitScale(BoxFit3d fit, Size3d source, Size3d destination) {
    if (fit == BoxFit3d.none) return Vector3.all(1);
    final ratios = <Axis3d, double>{};
    for (final axis in Axis3d.values) {
      final from = source.alongAxis(axis);
      final to = destination.alongAxis(axis);
      if (from <= 0.0 || !from.isFinite || !to.isFinite) continue;
      ratios[axis] = to / from;
    }
    if (ratios.isEmpty) return Vector3.all(1);
    if (fit == BoxFit3d.fill) {
      return Vector3(
        ratios[Axis3d.horizontal] ?? 1.0,
        ratios[Axis3d.vertical] ?? 1.0,
        ratios[Axis3d.depth] ?? 1.0,
      );
    }
    var uniform = ratios.values.reduce(math.min);
    if (fit == BoxFit3d.scaleDown) uniform = math.min(uniform, 1.0);
    return Vector3.all(uniform);
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    final child = this.child;
    if (child == null) {
      _scale = Vector3.all(1);
      _childOrigin = Offset3d.zero;
      size = constraints.smallest;
      return;
    }

    // Unbounded, so the child reports what it wants rather than what it was
    // offered. That is the measurement the fit is computed from.
    child.layout(const Constraints3d(), parentUsesSize: true);
    final natural = child.size;
    size = constraints.constrain(natural);
    _scale = fitScale(_fit, natural, size);
    final scaled = Size3d(
      natural.width * _scale.x,
      natural.height * _scale.y,
      natural.depth * _scale.z,
    );
    _childOrigin = _alignment.inscribe(scaled, size);
    child.place(Offset3d.zero);
    // The child's own offset is zero; everything about where it ends up is in
    // this box's localTransform, which the place() above has already folded
    // into its node.
    applyNodeTransform();
  }

  @override
  bool hitTest(HitTestResult3d result, {required Ray3d ray}) {
    if (!hasSize) return false;
    // Unlike Transform3d, the gate is meaningful: this box's size and the
    // incoming ray are in the same frame, and the fit is what put the child
    // inside that size.
    final range = ray.intersectBox(size);
    if (range == null) return false;
    final entry = ray.at(range.near);
    if (!entry.isFinite) return false;
    var inside = ray.clampedTo(range.near, range.far);
    final transform = localTransform;
    if (transform != null) {
      final inverse = Matrix4.zero();
      if (inverse.copyInverse(transform) == 0.0) return false;
      inside = inside.transformed(inverse);
    }
    if (hitTestChildren(result, ray: inside)) {
      result.add(HitTestEntry3d(this, entry));
      return true;
    }
    return false;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<BoxFit3d>('fit', fit));
    properties.add(DiagnosticsProperty<Alignment3d>('alignment', alignment));
    properties.add(
      DiagnosticsProperty<Vector3>(
        'scale',
        hasSize ? scale : null,
        defaultValue: null,
      ),
    );
  }
}
