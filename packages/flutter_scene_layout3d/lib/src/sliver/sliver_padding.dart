import 'dart:math' as math;

import '../geometry/edge_insets3d.dart';
import '../geometry/offset3d.dart';
import '../layout3d.dart';
import 'sliver.dart';
import 'sliver_constraints.dart';

/// Insets another sliver, the 3D analogue of [SliverPadding].
///
/// A [Padding3d] cannot do this job, because a sliver does not answer the box
/// protocol: it is handed a window and reports what it filled, so padding it
/// means moving the window rather than shrinking a size. This sliver does
/// that translation. It hands its child a window shortened at both ends and
/// narrowed across, and reports back what the child filled with the insets
/// added on again.
///
/// The leading inset is the interesting one. It is scroll extent like any
/// other, so it scrolls away: once the viewer has scrolled past it, the
/// child's own scroll offset starts counting, and the inset stops taking any
/// of the visible window. That is what makes a gap between two sections
/// behave like a gap rather than like a sticky margin, and it is why every
/// extent here is measured through [SliverConstraints3d.paintPortion] instead
/// of being added on directly.
///
/// The depth insets are ordinary room off the child's depth extent, the same
/// as the cross axis: a sliver's children fill the width they are given and
/// are free in depth, so an inset there is a thinner slab rather than a
/// shorter one.
///
/// ```dart
/// CustomScrollView3d(
///   slivers: [
///     SliverPadding3d(
///       padding: const EdgeInsets3d.all(0.5),
///       sliver: SliverList3d(children: rows),
///     ),
///   ],
/// )
/// ```
class SliverPadding3d extends Sliver3d with Layout3dWithChildMixin {
  /// Creates a sliver that insets [sliver].
  SliverPadding3d({
    EdgeInsets3d padding = EdgeInsets3d.zero,
    Sliver3d? sliver,
    super.name,
  }) : _padding = padding,
       assert(padding.isNonNegative, 'SliverPadding3d.padding is an inset.') {
    child = sliver;
  }

  EdgeInsets3d _padding;

  /// The inset on each of the six faces.
  EdgeInsets3d get padding => _padding;

  set padding(EdgeInsets3d value) {
    if (_padding == value) return;
    assert(value.isNonNegative, 'SliverPadding3d.padding is an inset.');
    _padding = value;
    markNeedsLayout();
  }

  /// The sliver being inset, the same thing as [child] under the name a
  /// caller uses.
  Sliver3d? get sliver => child as Sliver3d?;

  set sliver(Sliver3d? value) => child = value;

  @override
  set child(Layout3d? value) {
    assert(
      value == null || value is Sliver3d,
      'SliverPadding3d insets a sliver. Wrap a box in a SliverToBoxAdapter3d '
      'to put it in a CustomScrollView3d, and pad the box itself with a '
      'Padding3d.',
    );
    super.child = value;
  }

  @override
  void performSliverLayout() {
    final constraints = sliverConstraints;
    final axis = constraints.axis;
    final (crossAxis, depthAxis) = constraints.crossAxes;
    final before = _padding.lowAlong(axis);
    final mainAxisPadding = _padding.alongAxis(axis);
    final crossAxisPadding = _padding.alongAxis(crossAxis);
    final depthPadding = _padding.alongAxis(depthAxis);

    final child = sliver;
    if (child == null) {
      // Nothing to inset, but the insets themselves are still scroll extent:
      // an empty padded section is a gap, not nothing.
      final paintExtent = constraints.paintPortion(
        from: 0,
        to: mainAxisPadding,
      );
      geometry = SliverGeometry3d(
        scrollExtent: mainAxisPadding,
        paintExtent: paintExtent,
        maxPaintExtent: mainAxisPadding,
        cacheExtent: constraints.cachePortion(from: 0, to: mainAxisPadding),
      );
      return;
    }

    final beforePaintExtent = constraints.paintPortion(from: 0.0, to: before);
    final beforeCacheExtent = constraints.cachePortion(from: 0.0, to: before);

    child.layoutSliver(
      constraints.copyWith(
        // The leading inset is scrolled through before the child's own
        // content starts, so it comes off the child's scroll offset.
        scrollOffset: math.max(0.0, constraints.scrollOffset - before),
        cacheOrigin: math.min(0.0, constraints.cacheOrigin + before),
        precedingScrollExtent: constraints.precedingScrollExtent + before,
        overlap: 0.0,
        remainingPaintExtent: math.max(
          0.0,
          constraints.remainingPaintExtent - beforePaintExtent,
        ),
        remainingCacheExtent: math.max(
          0.0,
          constraints.remainingCacheExtent - beforeCacheExtent,
        ),
        crossAxisExtent: math.max(
          0.0,
          constraints.crossAxisExtent - crossAxisPadding,
        ),
        depthExtent: math.max(0.0, constraints.depthExtent - depthPadding),
      ),
    );

    final childGeometry = child.geometry;
    final correction = childGeometry.scrollOffsetCorrection;
    if (correction != null) {
      // The child has discovered its content is not where the offset assumed.
      // Pass the ask up unchanged: the viewport applies it and lays the whole
      // chain out again, this sliver included.
      geometry = SliverGeometry3d(scrollOffsetCorrection: correction);
      return;
    }

    final afterPaintExtent = constraints.paintPortion(
      from: before + childGeometry.scrollExtent,
      to: mainAxisPadding + childGeometry.scrollExtent,
    );
    final paddingPaintExtent = beforePaintExtent + afterPaintExtent;
    final paddingCacheExtent =
        beforeCacheExtent +
        constraints.cachePortion(
          from: before + childGeometry.scrollExtent,
          to: mainAxisPadding + childGeometry.scrollExtent,
        );
    final paintExtent = math.min(
      paddingPaintExtent + childGeometry.paintExtent,
      constraints.remainingPaintExtent,
    );

    geometry = SliverGeometry3d(
      scrollExtent: mainAxisPadding + childGeometry.scrollExtent,
      paintExtent: paintExtent,
      layoutExtent: math.min(
        paddingPaintExtent + childGeometry.layoutExtent,
        paintExtent,
      ),
      maxPaintExtent: mainAxisPadding + childGeometry.maxPaintExtent,
      // A child that answers hits further than it fills — a list keeping a
      // cached row reachable — keeps that reach, moved past the leading inset.
      hitTestExtent: math.max(
        paddingPaintExtent + childGeometry.paintExtent,
        beforePaintExtent + childGeometry.hitTestExtent,
      ),
      cacheExtent: math.min(
        paddingCacheExtent + childGeometry.cacheExtent,
        constraints.remainingCacheExtent,
      ),
      maxScrollObstructionExtent: childGeometry.maxScrollObstructionExtent,
      paintOrigin: childGeometry.paintOrigin,
    );

    child.place(
      Offset3d.zero
          .withAxis(axis, beforePaintExtent)
          .withAxis(crossAxis, _padding.lowAlong(crossAxis))
          .withAxis(depthAxis, _padding.lowAlong(depthAxis)),
    );
    child.node.visible = childGeometry.visible;
  }
}
