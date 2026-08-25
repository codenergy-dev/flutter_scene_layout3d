import 'dart:math' as math;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../layout3d.dart';
import 'sliver.dart';
import 'sliver_constraints.dart';

/// Builds the layout for one item of a [SliverList3d.builder].
typedef Sliver3dItemBuilder = Layout3d Function(int index);

/// A run of items in a sliver world, the 3D analogue of [SliverList].
///
/// The same idea as [ListView3d], answering the sliver protocol instead of
/// owning a scroll position: several of these share one
/// `CustomScrollView3d`'s position, so a list can follow a grid or a header
/// as one continuous surface.
///
/// Items are not stretched across the cross axes, the same deviation
/// [ListView3d] makes: [crossAxisAlignment] and [depthAxisAlignment] place
/// them instead, because a model is not a row of text and stretching it is
/// rarely what was meant.
class SliverList3d extends Sliver3d
    with Layout3dWithChildrenMixin<ParentData3d> {
  /// Creates a list over an explicit set of children.
  SliverList3d({
    double spacing = 0.0,
    double? itemExtent,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.center,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    List<Layout3d> children = const <Layout3d>[],
    super.name,
  }) : _spacing = spacing,
       _itemExtent = itemExtent,
       _crossAxisAlignment = crossAxisAlignment,
       _depthAxisAlignment = depthAxisAlignment,
       _builder = null,
       _itemCount = children.length,
       assert(spacing >= 0.0),
       assert(itemExtent == null || itemExtent > 0.0) {
    addAll(children);
  }

  /// Creates a list that builds its items on demand.
  SliverList3d.builder({
    required int itemCount,
    required Sliver3dItemBuilder itemBuilder,
    double spacing = 0.0,
    double? itemExtent,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.center,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    super.name,
  }) : _spacing = spacing,
       _itemExtent = itemExtent,
       _crossAxisAlignment = crossAxisAlignment,
       _depthAxisAlignment = depthAxisAlignment,
       _builder = itemBuilder,
       _itemCount = itemCount,
       assert(itemCount >= 0),
       assert(spacing >= 0.0),
       assert(itemExtent == null || itemExtent > 0.0);

  double _spacing;

  /// The gap between adjacent items.
  double get spacing => _spacing;

  set spacing(double value) {
    if (_spacing == value) return;
    assert(value >= 0.0);
    _spacing = value;
    _resetMeasurements();
    markNeedsLayout();
  }

  double? _itemExtent;

  /// A fixed extent for every item along the scroll axis.
  ///
  /// Makes a built list exactly lazy: item offsets become arithmetic, so the
  /// total extent is known without measuring anything.
  double? get itemExtent => _itemExtent;

  set itemExtent(double? value) {
    if (_itemExtent == value) return;
    assert(value == null || value > 0.0);
    _itemExtent = value;
    _resetMeasurements();
    markNeedsLayout();
  }

  CrossAxisAlignment3d _crossAxisAlignment;

  /// How items are positioned on the first cross axis.
  CrossAxisAlignment3d get crossAxisAlignment => _crossAxisAlignment;

  set crossAxisAlignment(CrossAxisAlignment3d value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  CrossAxisAlignment3d _depthAxisAlignment;

  /// How items are positioned on the second cross axis.
  CrossAxisAlignment3d get depthAxisAlignment => _depthAxisAlignment;

  set depthAxisAlignment(CrossAxisAlignment3d value) {
    if (_depthAxisAlignment == value) return;
    _depthAxisAlignment = value;
    markNeedsLayout();
  }

  final Sliver3dItemBuilder? _builder;

  int _itemCount;

  /// How many items the list holds.
  int get itemCount => _builder == null ? childCount : _itemCount;

  set itemCount(int value) {
    assert(
      _builder != null,
      'itemCount belongs to SliverList3d.builder; a list built from an '
      'explicit set of children takes its count from them.',
    );
    if (_itemCount == value) return;
    assert(value >= 0);
    _itemCount = value;
    markNeedsLayout();
  }

  /// The items built and kept alive, by index. Empty for an explicit list.
  final Map<int, Layout3d> _active = <int, Layout3d>{};

  /// Running start offsets of the items measured so far; `_prefix[i]` is
  /// where item `i` begins, and the last entry is where the next one would.
  final List<double> _prefix = <double>[0.0];

  int get _measuredCount => _prefix.length - 1;

  bool _layingOut = false;

  @override
  void markNeedsLayout() {
    // Building and releasing items happens inside performLayout; those child
    // list edits must not re-dirty the list that is being laid out.
    if (_layingOut) return;
    super.markNeedsLayout();
  }

  void _resetMeasurements() {
    _prefix
      ..clear()
      ..add(0.0);
  }

  /// Rebuilds the list from scratch, for when the item builder's data
  /// changed.
  void refresh() {
    _resetMeasurements();
    if (_builder != null) {
      for (final child in _active.values.toList()) {
        remove(child);
        child.dispose();
      }
      _active.clear();
    }
    markNeedsLayout();
  }

  Constraints3d _childConstraints(SliverConstraints3d constraints) {
    var result = const Constraints3d().withAxis(
      constraints.axis,
      min: _itemExtent ?? 0.0,
      max: _itemExtent ?? double.infinity,
    );
    final (crossAxis, depthAxis) = constraints.crossAxes;
    for (final (axis, limit, alignment)
        in <(Axis3d, double, CrossAxisAlignment3d)>[
          (crossAxis, constraints.crossAxisExtent, _crossAxisAlignment),
          (depthAxis, constraints.depthExtent, _depthAxisAlignment),
        ]) {
      final stretch =
          alignment == CrossAxisAlignment3d.stretch && limit.isFinite;
      result = result.withAxis(axis, min: stretch ? limit : 0.0, max: limit);
    }
    return result;
  }

  Layout3d _obtainChild(int index, Constraints3d childConstraints) {
    var child = _active[index];
    if (child == null) {
      child = _builder!(index);
      final position = _active.keys.where((i) => i < index).length;
      _active[index] = child;
      insert(child, index: position);
    }
    child.layout(childConstraints, parentUsesSize: true);
    return child;
  }

  void _releaseOutside(int first, int last) {
    for (final index in _active.keys.toList()) {
      if (index >= first && index <= last) continue;
      final child = _active.remove(index)!;
      remove(child);
      child.dispose();
    }
  }

  @override
  void performSliverLayout() {
    _layingOut = true;
    try {
      _performListLayout();
    } finally {
      _layingOut = false;
    }
  }

  void _performListLayout() {
    final constraints = sliverConstraints;
    final axis = constraints.axis;
    final (crossAxis, depthAxis) = constraints.crossAxes;
    final count = itemCount;
    if (count == 0) {
      geometry = SliverGeometry3d.zero;
      return;
    }

    final childConstraints = _childConstraints(constraints);
    // The stretch of content this pass has to account for, in the list's own
    // scroll coordinates: the visible window plus whatever cache surrounds it.
    final windowStart = math.max(
      0.0,
      constraints.scrollOffset + constraints.cacheOrigin,
    );
    final windowEnd =
        constraints.scrollOffset + constraints.remainingCacheExtent;

    double contentExtent;
    var firstIndex = 0;
    var lastIndex = count - 1;
    final itemExtent = _itemExtent;

    if (itemExtent != null) {
      final stride = itemExtent + _spacing;
      contentExtent = count * stride - _spacing;
      firstIndex = math.max(0, (windowStart / stride).floor());
      lastIndex = math.min(count - 1, (windowEnd / stride).floor());
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
    } else if (_builder == null) {
      _resetMeasurements();
      for (final child in children) {
        child.layout(childConstraints, parentUsesSize: true);
        _prefix.add(_prefix.last + child.size.alongAxis(axis) + _spacing);
      }
      contentExtent = math.max(0.0, _prefix.last - _spacing);
    } else {
      // Measured lazily: walk forward until the window is covered, keeping
      // the running prefix so scrolling back needs no re-measuring.
      while (_measuredCount < count && _prefix.last <= windowEnd) {
        final child = _obtainChild(_measuredCount, childConstraints);
        _prefix.add(_prefix.last + child.size.alongAxis(axis) + _spacing);
      }
      contentExtent = _estimatedContentExtent(count);
      firstIndex = _indexAtOffset(windowStart);
      lastIndex = _lastIndexBefore(windowEnd);
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
    for (final (index, child) in _positionedChildren()) {
      final start = _offsetOfIndex(index, itemExtent);
      final childSize = child.size;
      final extent = itemExtent ?? childSize.alongAxis(axis);
      child.place(
        Offset3d.zero
            .withAxis(axis, start - constraints.scrollOffset)
            .withAxis(
              crossAxis,
              _crossOffset(
                _crossAxisAlignment,
                constraints.crossAxisExtent,
                childSize.alongAxis(crossAxis),
              ),
            )
            .withAxis(
              depthAxis,
              _crossOffset(
                _depthAxisAlignment,
                constraints.depthExtent.isFinite
                    ? constraints.depthExtent
                    : childSize.alongAxis(depthAxis),
                childSize.alongAxis(depthAxis),
              ),
            ),
      );
      child.node.visible = start + extent > visibleStart && start < visibleEnd;
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

  double _offsetOfIndex(int index, double? itemExtent) {
    if (itemExtent != null) return index * (itemExtent + _spacing);
    if (index < _prefix.length) return _prefix[index];
    return _prefix.last;
  }

  /// The total extent, exact once every item has been measured and an average
  /// based estimate before that.
  double _estimatedContentExtent(int count) {
    final measured = _measuredCount;
    if (measured >= count) return math.max(0.0, _prefix.last - _spacing);
    if (measured == 0) return 0.0;
    final averageStride = _prefix.last / measured;
    return math.max(0.0, averageStride * count - _spacing);
  }

  /// The index of the item covering [offset], clamped into range.
  int _indexAtOffset(double offset) {
    if (offset <= 0.0 || _measuredCount == 0) return 0;
    var low = 0;
    var high = _measuredCount - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_prefix[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// The last index that starts before [end], clamped into range.
  int _lastIndexBefore(double end) {
    var last = -1;
    for (var index = 0; index < _measuredCount; index++) {
      if (_prefix[index] < end) {
        last = index;
      } else {
        break;
      }
    }
    return math.max(0, last);
  }

  static double _crossOffset(
    CrossAxisAlignment3d alignment,
    double extent,
    double childExtent,
  ) => switch (alignment) {
    // Baseline alignment falls back to the start here: a sliver lays its
    // children out one after another, so there is no shared line for their
    // baselines to sit on.
    CrossAxisAlignment3d.start ||
    CrossAxisAlignment3d.stretch ||
    CrossAxisAlignment3d.baseline => 0.0,
    CrossAxisAlignment3d.end => extent - childExtent,
    CrossAxisAlignment3d.center => (extent - childExtent) / 2.0,
  };
}
