import 'dart:math' as math;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../layout3d.dart';
import '../scroll/grid_view.dart' show Grid3dDelegate, Grid3dLayout;
import 'sliver.dart';
import 'sliver_constraints.dart';

/// A grid of cells in a sliver world, the 3D analogue of [SliverGrid].
///
/// The sliver form of [GridView3d], sharing its [Grid3dDelegate]: the same
/// delegate lays out a standalone grid or a section of a
/// `CustomScrollView3d`. Because cell positions are arithmetic, a built grid
/// is exactly lazy — the scroll extent of ten thousand cells is known without
/// building one.
class SliverGrid3d extends Sliver3d
    with Layout3dWithChildrenMixin<ParentData3d> {
  /// Creates a grid over an explicit set of children.
  SliverGrid3d({
    required Grid3dDelegate gridDelegate,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    List<Layout3d> children = const <Layout3d>[],
    super.name,
  }) : _gridDelegate = gridDelegate,
       _depthAxisAlignment = depthAxisAlignment,
       _builder = null,
       _itemCount = children.length {
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
       _itemCount = itemCount,
       assert(itemCount >= 0);

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

  int _itemCount;

  /// How many cells the grid holds.
  int get itemCount => _builder == null ? childCount : _itemCount;

  set itemCount(int value) {
    assert(
      _builder != null,
      'itemCount belongs to SliverGrid3d.builder; a grid built from an '
      'explicit set of children takes its count from them.',
    );
    if (_itemCount == value) return;
    assert(value >= 0);
    _itemCount = value;
    markNeedsLayout();
  }

  final Map<int, Layout3d> _active = <int, Layout3d>{};

  Grid3dLayout? _layout;

  /// The cell grid in force after the most recent layout.
  Grid3dLayout? get gridLayout => _layout;

  bool _layingOut = false;

  @override
  void markNeedsLayout() {
    if (_layingOut) return;
    super.markNeedsLayout();
  }

  /// Refuses a child list edit on a built grid, where the bookkeeping
  /// would not survive it.
  ///
  /// A built grid tracks its cells by index, and everything it does —
  /// measuring, placing, culling, releasing — goes through that map. A child
  /// inserted from outside is in the child list but not in the map, so it is
  /// never laid out (the first read of its size trips the "has not been laid
  /// out yet" assert) and never released. The cells of a built grid come from
  /// its builder; change [itemCount], or call [refresh] when the data behind
  /// the builder moved.
  void _assertNotBuilt(String method) {
    assert(
      _builder == null,
      'Cannot call $method on a SliverGrid3d.builder. Its cells come from '
      'itemBuilder and are tracked by index; a child added from outside is '
      'never laid out and never released. Set itemCount, or call refresh() '
      'when the data behind the builder changed.',
    );
  }

  @override
  void insert(Layout3d child, {int? index}) {
    _assertNotBuilt('insert');
    super.insert(child, index: index);
  }

  @override
  void remove(Layout3d child) {
    _assertNotBuilt('remove');
    super.remove(child);
  }

  @override
  void removeAll() {
    _assertNotBuilt('removeAll');
    super.removeAll();
  }

  @override
  void syncChildren(List<Layout3d> children) {
    _assertNotBuilt('syncChildren');
    super.syncChildren(children);
  }

  /// Rebuilds the grid from scratch, for when the item builder's data
  /// changed.
  void refresh() {
    if (_builder != null) {
      for (final child in _active.values.toList()) {
        remove(child);
        child.dispose();
      }
      _active.clear();
    }
    markNeedsLayout();
  }

  Layout3d _obtainChild(int index, Constraints3d childConstraints) {
    var child = _active[index];
    if (child == null) {
      child = _builder!(index);
      final position = _active.keys.where((i) => i < index).length;
      _active[index] = child;
      super.insert(child, index: position);
    }
    child.layout(childConstraints, parentUsesSize: true);
    return child;
  }

  void _releaseOutside(int first, int last) {
    for (final index in _active.keys.toList()) {
      if (index >= first && index <= last) continue;
      final child = _active.remove(index)!;
      super.remove(child);
      child.dispose();
    }
  }

  @override
  void performSliverLayout() {
    _layingOut = true;
    try {
      _performGridLayout();
    } finally {
      _layingOut = false;
    }
  }

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

    if (_builder == null) {
      for (final child in children) {
        child.layout(childConstraints, parentUsesSize: true);
      }
    } else {
      for (var index = firstIndex; index <= lastIndex; index++) {
        _obtainChild(index, childConstraints);
      }
      _releaseOutside(firstIndex, lastIndex);
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
    for (final (index, child) in _positionedChildren()) {
      final start = grid.mainAxisOffsetOf(index);
      child.place(
        Offset3d.zero
            .withAxis(axis, start - constraints.scrollOffset)
            .withAxis(crossAxis, grid.crossAxisOffsetOf(index))
            .withAxis(
              depthAxis,
              _depthOffset(depthExtent, child.size.alongAxis(depthAxis)),
            ),
      );
      child.node.visible =
          start + grid.cellMainAxisExtent > visibleStart && start < visibleEnd;
    }
  }

  Iterable<(int, Layout3d)> _positionedChildren() sync* {
    if (_builder == null) {
      for (var index = 0; index < childCount; index++) {
        yield (index, childAt(index));
      }
      return;
    }
    for (final entry in _active.entries) {
      yield (entry.key, entry.value);
    }
  }

  double _depthOffset(double extent, double childExtent) =>
      switch (_depthAxisAlignment) {
        // Baseline alignment falls back to the start here: a grid cell has no
        // line to share with the cells beside it.
        CrossAxisAlignment3d.start ||
        CrossAxisAlignment3d.stretch ||
        CrossAxisAlignment3d.baseline => 0.0,
        CrossAxisAlignment3d.end => extent - childExtent,
        CrossAxisAlignment3d.center => (extent - childExtent) / 2.0,
      };
}
