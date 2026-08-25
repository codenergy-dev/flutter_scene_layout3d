import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import '../geometry/alignment3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// Imposes extra constraints on its child, the 3D analogue of
/// [ConstrainedBox].
///
/// The extra constraints are combined with the incoming ones through
/// [Constraints3d.enforce], so a parent's limits always win.
class ConstrainedBox3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a box that constrains its child.
  ConstrainedBox3d({
    Constraints3d additionalConstraints = const Constraints3d(),
    super.child,
    super.name,
  }) : _additionalConstraints = additionalConstraints,
       assert(additionalConstraints.isNormalized);

  Constraints3d _additionalConstraints;

  /// The constraints this box adds to those it receives.
  Constraints3d get additionalConstraints => _additionalConstraints;

  set additionalConstraints(Constraints3d value) {
    if (_additionalConstraints == value) return;
    assert(value.isNormalized);
    _additionalConstraints = value;
    markNeedsLayout();
  }

  /// The child's intrinsic extent, held to the extra constraints.
  ///
  /// An axis this box fixes outright answers with that fixed extent and never
  /// asks the child, which is what makes a [SizedBox3d] the cheap way to stop
  /// an intrinsic query from walking a subtree. An axis it *expands* on has
  /// no finite answer to give, so it passes the child's through rather than
  /// reporting an infinite intrinsic.
  double _constrainedIntrinsic(Axis3d axis, Size3d limits, {required bool min}) {
    final extra = _additionalConstraints;
    if (extra.hasTightAlong(axis) && extra.hasBoundedAlong(axis)) {
      return extra.minAlong(axis);
    }
    final child = this.child;
    final extent = child == null
        ? 0.0
        : (min
              ? child.getMinIntrinsicExtent(axis, limits)
              : child.getMaxIntrinsicExtent(axis, limits));
    if (extra.minAlong(axis).isFinite) return extra.constrainAlong(axis, extent);
    return extent;
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _constrainedIntrinsic(axis, limits, min: true);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _constrainedIntrinsic(axis, limits, min: false);

  @override
  void performLayout() {
    final combined = _additionalConstraints.enforce(constraints);
    final child = this.child;
    if (child == null) {
      size = combined.constrain(Size3d.zero);
      return;
    }
    child.layout(combined, parentUsesSize: true);
    size = child.size;
    child.place(Offset3d.zero);
  }
}

/// A box with a fixed size, the 3D analogue of [SizedBox].
///
/// Every axis is independent: give only [depth] and the box takes its width
/// and height from its child (or from the constraints, with no child), which
/// is the usual way to give a flat panel some thickness.
class SizedBox3d extends ConstrainedBox3d {
  /// Creates a box fixed on the axes given.
  SizedBox3d({
    double? width,
    double? height,
    double? depth,
    super.child,
    super.name,
  }) : super(
         additionalConstraints: Constraints3d.tightFor(
           width: width,
           height: height,
           depth: depth,
         ),
       );

  /// A box fixed to [size] on all three axes.
  SizedBox3d.fromSize(Size3d size, {super.child, super.name})
    : super(additionalConstraints: Constraints3d.tight(size));

  /// A cube [extent] on a side.
  SizedBox3d.cube(double extent, {super.child, super.name})
    : super(additionalConstraints: Constraints3d.tight(Size3d.cube(extent)));

  /// A box that takes all the room it is offered.
  SizedBox3d.expand({super.child, super.name})
    : super(additionalConstraints: const Constraints3d.expand());

  /// A box that takes as little room as possible.
  SizedBox3d.shrink({super.child, super.name})
    : super(
        additionalConstraints: const Constraints3d.tightFor(
          width: 0,
          height: 0,
          depth: 0,
        ),
      );

  /// The fixed width, or null when the width is not fixed.
  double? get width => additionalConstraints.hasTightWidth
      ? additionalConstraints.maxWidth
      : null;

  set width(double? value) {
    additionalConstraints = additionalConstraints.copyWith(
      minWidth: value ?? 0.0,
      maxWidth: value ?? double.infinity,
    );
  }

  /// The fixed height, or null when the height is not fixed.
  double? get height => additionalConstraints.hasTightHeight
      ? additionalConstraints.maxHeight
      : null;

  set height(double? value) {
    additionalConstraints = additionalConstraints.copyWith(
      minHeight: value ?? 0.0,
      maxHeight: value ?? double.infinity,
    );
  }

  /// The fixed depth, or null when the depth is not fixed.
  double? get depth => additionalConstraints.hasTightDepth
      ? additionalConstraints.maxDepth
      : null;

  set depth(double? value) {
    additionalConstraints = additionalConstraints.copyWith(
      minDepth: value ?? 0.0,
      maxDepth: value ?? double.infinity,
    );
  }
}

/// Transforms its child without affecting layout, the 3D analogue of
/// [Transform].
///
/// The matrix is applied in **layout space** (`x` right, `y` down, `z` away
/// from the viewer), around the point [alignment] picks out in this box, so
/// `Transform3d.rotate(axis: Vector3(0, 0, 1), angle: 0.2)` turns the child
/// clockwise on the plane, exactly as `Transform.rotate` does in Flutter. The
/// child is laid out and sized as if the transform were not there.
class Transform3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a transformed box.
  Transform3d({
    required Matrix4 transform,
    Alignment3d alignment = Alignment3d.center,
    super.child,
    super.name,
  }) : _transform = Matrix4.copy(transform),
       _alignment = alignment;

  /// A box that rotates its child [angle] radians about [axis].
  Transform3d.rotate({
    required Vector3 axis,
    required double angle,
    Alignment3d alignment = Alignment3d.center,
    Layout3d? child,
    String? name,
  }) : this(
         transform: Matrix4.compose(
           Vector3.zero(),
           Quaternion.axisAngle(axis.normalized(), angle),
           Vector3.all(1),
         ),
         alignment: alignment,
         child: child,
         name: name,
       );

  /// A box that scales its child.
  Transform3d.scale({
    required Vector3 scale,
    Alignment3d alignment = Alignment3d.center,
    Layout3d? child,
    String? name,
  }) : this(
         transform: Matrix4.diagonal3(scale),
         alignment: alignment,
         child: child,
         name: name,
       );

  /// A box that translates its child, in layout space.
  Transform3d.translate({
    required Offset3d offset,
    Layout3d? child,
    String? name,
  }) : this(
         transform: Matrix4.translationValues(offset.x, offset.y, offset.z),
         alignment: Alignment3d.topLeftFront,
         child: child,
         name: name,
       );

  Matrix4 _transform;

  /// The transform applied to the child, in layout space.
  ///
  /// Returns a copy; assign a new matrix rather than mutating this one.
  Matrix4 get transform => Matrix4.copy(_transform);

  set transform(Matrix4 value) {
    if (_transform == value) return;
    _transform = Matrix4.copy(value);
    if (hasSize) applyNodeTransform();
  }

  Alignment3d _alignment;

  /// The point in this box the transform pivots around.
  Alignment3d get alignment => _alignment;

  set alignment(Alignment3d value) {
    if (_alignment == value) return;
    _alignment = value;
    if (hasSize) applyNodeTransform();
  }

  @override
  Matrix4? get localTransform {
    if (!hasSize) return Matrix4.copy(_transform);
    final origin = _alignment.alongSize(size);
    return Matrix4.translationValues(origin.x, origin.y, origin.z)
        .multiplied(_transform)
        .multiplied(Matrix4.translationValues(-origin.x, -origin.y, -origin.z));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = child.size;
    child.place(Offset3d.zero);
    // The transform pivots around a point derived from the size just chosen.
    applyNodeTransform();
  }
}
