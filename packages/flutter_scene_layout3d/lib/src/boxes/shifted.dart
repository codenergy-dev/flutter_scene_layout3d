import 'package:flutter/foundation.dart' show protected;

import '../geometry/alignment3d.dart';
import '../geometry/edge_insets3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// A layout that sizes and positions a single child somewhere inside itself.
///
/// The shared base of [Padding3d] and [Align3d], mirroring
/// `RenderShiftedBox`.
abstract class ShiftedLayout3d extends SingleChildLayout3d {
  /// Creates a shifting layout around [child].
  ShiftedLayout3d({super.child, super.name});
}

/// Insets its child by [padding], the 3D analogue of [Padding].
///
/// With no child, the padding collapses to a box of its own thickness.
class Padding3d extends ShiftedLayout3d {
  /// Creates a padded box.
  Padding3d({EdgeInsets3d padding = EdgeInsets3d.zero, super.child, super.name})
    : _padding = padding;

  EdgeInsets3d _padding;

  /// The inset on each of the six faces.
  EdgeInsets3d get padding => _padding;

  set padding(EdgeInsets3d value) {
    if (_padding == value) return;
    assert(value.isNonNegative, 'Padding3d.padding must be non-negative.');
    _padding = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(_padding.collapsedSize);
      return;
    }
    child.layout(constraints.deflate(_padding), parentUsesSize: true);
    size = constraints.constrain(_padding.inflateSize(child.size));
    child.place(_padding.topLeftFront);
  }
}

/// Aligns its child within itself and optionally sizes itself to a multiple
/// of the child's size, the 3D analogue of [Align].
///
/// Unconstrained on an axis, an [Align3d] shrink-wraps the child on that
/// axis; bounded, it expands to fill, which is what makes
/// `Align3d(alignment: Alignment3d.topLeft)` push a child to a corner of the
/// space it was given.
class Align3d extends ShiftedLayout3d {
  /// Creates an aligning box.
  Align3d({
    Alignment3d alignment = Alignment3d.center,
    double? widthFactor,
    double? heightFactor,
    double? depthFactor,
    super.child,
    super.name,
  }) : _alignment = alignment,
       _widthFactor = widthFactor,
       _heightFactor = heightFactor,
       _depthFactor = depthFactor,
       assert(widthFactor == null || widthFactor >= 0.0),
       assert(heightFactor == null || heightFactor >= 0.0),
       assert(depthFactor == null || depthFactor >= 0.0);

  Alignment3d _alignment;

  /// Where the child sits inside this box.
  Alignment3d get alignment => _alignment;

  set alignment(Alignment3d value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  double? _widthFactor;

  /// If non-null, this box's width is the child's width times this factor.
  double? get widthFactor => _widthFactor;

  set widthFactor(double? value) {
    if (_widthFactor == value) return;
    _widthFactor = value;
    markNeedsLayout();
  }

  double? _heightFactor;

  /// If non-null, this box's height is the child's height times this factor.
  double? get heightFactor => _heightFactor;

  set heightFactor(double? value) {
    if (_heightFactor == value) return;
    _heightFactor = value;
    markNeedsLayout();
  }

  double? _depthFactor;

  /// If non-null, this box's depth is the child's depth times this factor.
  double? get depthFactor => _depthFactor;

  set depthFactor(double? value) {
    if (_depthFactor == value) return;
    _depthFactor = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    final shrinkWrapWidth =
        _widthFactor != null || !constraints.hasBoundedWidth;
    final shrinkWrapHeight =
        _heightFactor != null || !constraints.hasBoundedHeight;
    final shrinkWrapDepth =
        _depthFactor != null || !constraints.hasBoundedDepth;

    final child = this.child;
    if (child == null) {
      size = constraints.constrain(
        Size3d(
          shrinkWrapWidth ? 0.0 : double.infinity,
          shrinkWrapHeight ? 0.0 : double.infinity,
          shrinkWrapDepth ? 0.0 : double.infinity,
        ),
      );
      return;
    }

    child.layout(constraints.loosen(), parentUsesSize: true);
    final childSize = child.size;
    size = constraints.constrain(
      Size3d(
        shrinkWrapWidth
            ? childSize.width * (_widthFactor ?? 1.0)
            : double.infinity,
        shrinkWrapHeight
            ? childSize.height * (_heightFactor ?? 1.0)
            : double.infinity,
        shrinkWrapDepth
            ? childSize.depth * (_depthFactor ?? 1.0)
            : double.infinity,
      ),
    );
    child.place(_alignment.inscribe(childSize, size));
  }
}

/// Centers its child, the 3D analogue of [Center].
class Center3d extends Align3d {
  /// Creates a centering box.
  Center3d({
    super.widthFactor,
    super.heightFactor,
    super.depthFactor,
    super.child,
    super.name,
  });
}

/// Applies a fixed offset to its child without affecting layout, useful for
/// nudging content off the plane.
class Offset3dBox extends ShiftedLayout3d {
  /// Creates a box that shifts its child by [shift].
  Offset3dBox({Offset3d shift = Offset3d.zero, super.child, super.name})
    : _shift = shift;

  Offset3d _shift;

  /// The extra offset applied to the child.
  Offset3d get shift => _shift;

  set shift(Offset3d value) {
    if (_shift == value) return;
    _shift = value;
    markNeedsLayout();
  }

  @protected
  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = child.size;
    child.place(_shift);
  }
}
