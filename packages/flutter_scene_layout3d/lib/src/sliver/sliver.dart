import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty, protected;

import '../built_children.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import '../layout_pass.dart';
import 'sliver_constraints.dart';

/// A layout that answers the sliver protocol rather than the box one, the 3D
/// analogue of [RenderSliver].
///
/// Where a box is asked "given these constraints, how big are you?", a sliver
/// is asked "given this window and how far you have scrolled through it, what
/// did you fill?". It answers with a [SliverGeometry3d], and that is what lets
/// a `CustomScrollView3d` put several sections on one scroll position, and a
/// long section describe itself without laying out all of it.
///
/// A sliver is still a [Layout3d]: it owns a scene node, it is placed by its
/// parent, and it is hit-tested like anything else. Its [size] is derived from
/// the geometry it reported — the visible extent along the scroll axis, the
/// room given across the other two — so the volume it occupies in the scene is
/// the volume the viewer can actually see.
abstract class Sliver3d extends Layout3d {
  /// Creates a sliver.
  Sliver3d({super.name});

  SliverConstraints3d? _sliverConstraints;

  /// The window this sliver was last laid out against.
  SliverConstraints3d get sliverConstraints {
    assert(
      _sliverConstraints != null,
      '$runtimeType has not been laid out by a viewport yet, so it has no '
      'sliver constraints. A Sliver3d belongs in a CustomScrollView3d; it '
      'cannot be laid out as an ordinary box.',
    );
    return _sliverConstraints!;
  }

  /// Whether this sliver has been laid out by a viewport.
  bool get hasSliverConstraints => _sliverConstraints != null;

  SliverGeometry3d _geometry = SliverGeometry3d.zero;

  /// What this sliver reported after its last layout.
  SliverGeometry3d get geometry => _geometry;

  /// Records what this sliver filled. Set from [performSliverLayout].
  @protected
  set geometry(SliverGeometry3d value) {
    _geometry = value;
  }

  /// Lays this sliver out against [constraints].
  ///
  /// The sliver protocol's entry point, the way [layout] is the box
  /// protocol's, and called by the viewport. Cheap when nothing has changed:
  /// the same window on a clean sliver is a no-op.
  void layoutSliver(SliverConstraints3d constraints) {
    if (!needsLayout && constraints == _sliverConstraints) return;
    _sliverConstraints = constraints;
    // The box constraints derived from a window do not change when only the
    // scroll offset moves, so the box protocol would skip the work.
    invalidateLayout();
    layout(constraints.asBoxConstraints(), parentUsesSize: true);
  }

  /// Fills the window described by [sliverConstraints] and sets [geometry].
  ///
  /// The sliver counterpart of [performLayout]: lay out whatever children are
  /// in reach, place them relative to this sliver's own leading edge, and
  /// report what it all came to.
  @protected
  void performSliverLayout();

  @override
  void performLayout() {
    geometry = SliverGeometry3d.zero;
    performSliverLayout();
    final constraints = sliverConstraints;
    final (crossAxis, depthAxis) = constraints.crossAxes;
    // The box a sliver occupies is the part of it the viewer can see. A
    // sliver that reports a longer hit test extent than it fills gets that
    // extent instead, which is the one place the two differ.
    size = Size3d.zero
        .withAxis(
          constraints.axis,
          math.max(geometry.paintExtent, geometry.hitTestExtent),
        )
        .withAxis(
          crossAxis,
          constraints.crossAxisExtent.isFinite
              ? constraints.crossAxisExtent
              : 0.0,
        )
        .withAxis(
          depthAxis,
          constraints.depthExtent.isFinite ? constraints.depthExtent : 0.0,
        );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<SliverConstraints3d>(
        'sliverConstraints',
        hasSliverConstraints ? sliverConstraints : null,
        ifNull: 'MISSING',
      ),
    );
    properties.add(DiagnosticsProperty<SliverGeometry3d>('geometry', geometry));
  }
}

/// Puts one box in a sliver world, the 3D analogue of [SliverToBoxAdapter].
///
/// The glue between the two protocols: everything else in this package is a
/// box, and this is how a box takes its turn in a `CustomScrollView3d`
/// alongside the lists and grids. The child is laid out once, at its natural
/// extent along the scroll axis, and scrolls as one piece.
class SliverToBoxAdapter3d extends Sliver3d with Layout3dWithChildMixin {
  /// Creates an adapter around [child].
  SliverToBoxAdapter3d({Layout3d? child, super.name}) {
    this.child = child;
  }

  @override
  void performSliverLayout() {
    final child = this.child;
    final constraints = sliverConstraints;
    if (child == null) {
      geometry = SliverGeometry3d.zero;
      return;
    }
    child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = child.size.alongAxis(constraints.axis);
    final paintExtent = constraints.paintPortion(from: 0.0, to: extent);
    geometry = SliverGeometry3d(
      scrollExtent: extent,
      paintExtent: paintExtent,
      maxPaintExtent: extent,
      cacheExtent: constraints.cachePortion(from: 0.0, to: extent),
    );
    child.place(Offset3d.along(constraints.axis, -constraints.scrollOffset));
    child.node.visible = geometry.visible;
  }
}

/// A sliver holding a list of children it may build on demand, the 3D
/// analogue of [RenderSliverMultiBoxAdaptor].
///
/// What [SliverList3d] and [SliverGrid3d] have in common, which is everything
/// except where a child goes: the child list, the index-keyed bookkeeping of
/// a builder, and a layout pass that ignores the dirt it raises by building.
///
/// It is also the sliver a [BoxScrollView3d] puts in its window, and the
/// reason that class can forward a child list to whichever of the two it
/// holds.
abstract class SliverMultiBoxAdaptor3d extends Sliver3d
    with
        Layout3dWithChildrenMixin<ParentData3d>,
        Layout3dLayoutPassMixin,
        Layout3dBuiltChildrenMixin<ParentData3d> {
  /// Creates a sliver over a child list.
  SliverMultiBoxAdaptor3d({super.name});
}
