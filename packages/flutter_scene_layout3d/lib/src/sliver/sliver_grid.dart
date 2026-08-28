import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../built_children.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../layout3d.dart';
import '../scroll/grid_delegate.dart' show Grid3dDelegate, Grid3dLayout;
import 'sliver.dart';
import 'sliver_constraints.dart';

/// A grid of cells in a sliver world, the 3D analogue of [SliverGrid].
///
/// The sliver form of [GridView3d], sharing its [Grid3dDelegate]: the same
/// delegate lays out a standalone grid or a section of a
/// `CustomScrollView3d`. Because cell positions are arithmetic, a built grid
/// is exactly lazy — the scroll extent of ten thousand cells is known without
/// building one.
class SliverGrid3d extends SliverMultiBoxAdaptor3d {
  /// Creates a grid over an explicit set of children.
  SliverGrid3d({
    required Grid3dDelegate gridDelegate,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    List<Layout3d> children = const <Layout3d>[],
    super.name,
  }) : _gridDelegate = gridDelegate,
       _depthAxisAlignment = depthAxisAlignment,
       _builder = null {
    addAll(children);
  }

  /// Creates a grid that builds its cells on demand.
  SliverGrid3d.builder({
    required Grid3dDelegate gridDelegate,
    required int itemCount,
    required Layout3dItemBuilder itemBuilder,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    super.name,
  }) : _gridDelegate = gridDelegate,
       _depthAxisAlignment = depthAxisAlignment,
       _builder = itemBuilder,
       assert(itemCount >= 0) {
    declaredItemCount = itemCount;
  }

  Grid3dDelegate _gridDelegate;

  /// Decides the cell grid from the room across the scroll axis.
  Grid3dDelegate get gridDelegate => _gridDelegate;

  set gridDelegate(Grid3dDelegate value) {
    if (identical(_gridDelegate, value)) return;
    final old = _gridDelegate;
    _gridDelegate = value;
    if (value.runtimeType != old.runtimeType || value.shouldRelayout(old)) {
      markNeedsLayout();
    }
  }

  CrossAxisAlignment3d _depthAxisAlignment;

  /// How a cell's child sits on the depth axis.
  CrossAxisAlignment3d get depthAxisAlignment => _depthAxisAlignment;

  set depthAxisAlignment(CrossAxisAlignment3d value) {
    if (_depthAxisAlignment == value) return;
    _depthAxisAlignment = value;
    markNeedsLayout();
  }

  final Layout3dItemBuilder? _builder;

  @override
  Layout3dItemBuilder? get itemBuilder => _builder;

  @override
  String get itemNoun => 'cells';

  Grid3dLayout? _layout;

  /// The cell grid in force after the most recent layout.
  Grid3dLayout? get gridLayout => _layout;

  @override
  void performSliverLayout() => runLayoutPass(_performGridLayout);

  void _performGridLayout() {
    final constraints = sliverConstraints;
    final axis = constraints.axis;
    final (crossAxis, depthAxis) = constraints.crossAxes;
    final count = itemCount;
    final grid = _layout = _gridDelegate.layoutFor(constraints.crossAxisExtent);
    if (count == 0) {
      geometry = SliverGeometry3d.zero;
      return;
    }

    final contentExtent = grid.mainExtentFor(count);
    final windowStart = math.max(
      0.0,
      constraints.scrollOffset + constraints.cacheOrigin,
    );
    final windowEnd =
        constraints.scrollOffset + constraints.remainingCacheExtent;
    final firstIndex = math.max(0, grid.firstIndexAt(windowStart));
    final lastIndex = math.min(count - 1, grid.lastIndexAt(windowEnd, count));

    final depthLimit = constraints.depthExtent;
    final stretchDepth =
        _depthAxisAlignment == CrossAxisAlignment3d.stretch &&
        depthLimit.isFinite;
    final childConstraints = const Constraints3d()
        .withAxis(
          axis,
          min: grid.cellMainAxisExtent,
          max: grid.cellMainAxisExtent,
        )
        .withAxis(
          crossAxis,
          min: grid.cellCrossAxisExtent,
          max: grid.cellCrossAxisExtent,
        )
        .withAxis(
          depthAxis,
          min: stretchDepth ? depthLimit : 0.0,
          max: depthLimit,
        );

    if (!isLazy) {
      for (final child in children) {
        child.layout(childConstraints, parentUsesSize: true);
      }
    } else {
      for (var index = firstIndex; index <= lastIndex; index++) {
        obtainChild(index, childConstraints);
      }
      releaseOutside(firstIndex, lastIndex);
    }

    geometry = SliverGeometry3d(
      scrollExtent: contentExtent,
      paintExtent: constraints.paintPortion(from: 0.0, to: contentExtent),
      maxPaintExtent: contentExtent,
      cacheExtent: constraints.cachePortion(from: 0.0, to: contentExtent),
    );

    final visibleStart = constraints.scrollOffset;
    final visibleEnd =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    final depthExtent = depthLimit.isFinite ? depthLimit : 0.0;
    for (final (index, child) in positionedChildren()) {
      final start = grid.mainAxisOffsetOf(index);
      child.place(
        Offset3d.zero
            .withAxis(axis, start - constraints.scrollOffset)
            .withAxis(crossAxis, grid.crossAxisOffsetOf(index))
            .withAxis(
              depthAxis,
              scrollCrossOffset(
                _depthAxisAlignment,
                depthExtent,
                child.size.alongAxis(depthAxis),
              ),
            ),
      );
      child.node.visible =
          start + grid.cellMainAxisExtent > visibleStart && start < visibleEnd;
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<Grid3dDelegate>('gridDelegate', gridDelegate),
    );
  }
}
