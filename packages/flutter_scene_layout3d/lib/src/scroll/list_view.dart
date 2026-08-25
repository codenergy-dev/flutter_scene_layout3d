import 'dart:math' as math;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'scroll_controller.dart';
import 'scrollable.dart';

/// Builds the layout for one item of a [ListView3d.builder].
typedef Layout3dItemBuilder = Layout3d Function(int index);

/// A scrollable line of children, the 3D analogue of [ListView].
///
/// Children are laid out one after another along [scrollDirection] and the
/// list shows the window at [controller]'s offset. Two ways to supply them:
///
///  * the default constructor takes an explicit list; every child is laid out
///    each pass, and the ones outside the window (plus [cacheExtent]) have
///    their nodes hidden rather than removed;
///  * [ListView3d.builder] builds items on demand and keeps only what is near
///    the window, disposing the rest. With [itemExtent] the offsets are
///    arithmetic and nothing off-screen is ever built; without it, items are
///    measured once as they are first scrolled past, and the total extent is
///    estimated from the average of what has been measured, the same
///    approximation Flutter's `SliverList` makes.
///
/// Unlike Flutter's `ListView`, children are not stretched across the cross
/// axes by default; [crossAxisAlignment] and [depthAxisAlignment] centre them
/// instead, which is the more useful default when the items are objects
/// rather than rows. Ask for [CrossAxisAlignment3d.stretch] to get the
/// Flutter behaviour.
class ListView3d extends MultiChildLayout3d<ParentData3d>
    implements Scrollable3d {
  /// Creates a list over an explicit set of children.
  ListView3d({
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    double spacing = 0.0,
    double? itemExtent,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.center,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double cacheExtent = 0.0,
    List<Layout3d> children = const <Layout3d>[],
    super.name,
  }) : _axis = scrollDirection,
       _controller = controller ?? Scroll3dController(),
       _ownsController = controller == null,
       _spacing = spacing,
       _itemExtent = itemExtent,
       _crossAxisAlignment = crossAxisAlignment,
       _depthAxisAlignment = depthAxisAlignment,
       _cacheExtent = cacheExtent,
       _builder = null,
       _itemCount = children.length,
       assert(spacing >= 0.0),
       assert(cacheExtent >= 0.0),
       assert(itemExtent == null || itemExtent > 0.0),
       super(children: children) {
    _controller.addListener(_handleScrollChanged);
  }

  /// Creates a list that builds its items on demand.
  ListView3d.builder({
    required int itemCount,
    required Layout3dItemBuilder itemBuilder,
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    double spacing = 0.0,
    double? itemExtent,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.center,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double cacheExtent = 0.0,
    super.name,
  }) : _axis = scrollDirection,
       _controller = controller ?? Scroll3dController(),
       _ownsController = controller == null,
       _spacing = spacing,
       _itemExtent = itemExtent,
       _crossAxisAlignment = crossAxisAlignment,
       _depthAxisAlignment = depthAxisAlignment,
       _cacheExtent = cacheExtent,
       _builder = itemBuilder,
       _itemCount = itemCount,
       assert(itemCount >= 0),
       assert(spacing >= 0.0),
       assert(cacheExtent >= 0.0),
       assert(itemExtent == null || itemExtent > 0.0) {
    _controller.addListener(_handleScrollChanged);
  }

  Axis3d _axis;

  /// The axis the list scrolls along.
  Axis3d get scrollDirection => _axis;

  @override
  Axis3d get scrollAxis => _axis;

  set scrollDirection(Axis3d value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  Scroll3dController _controller;
  bool _ownsController;

  /// The scroll position, and the metrics this list measured.
  @override
  Scroll3dController get controller => _controller;

  set controller(Scroll3dController value) {
    if (identical(_controller, value)) return;
    _controller.removeListener(_handleScrollChanged);
    // A controller supplied from outside belongs to whoever supplied it.
    if (_ownsController) _controller.dispose();
    _ownsController = false;
    _controller = value..addListener(_handleScrollChanged);
    markNeedsLayout();
  }

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
  /// Makes a built list exactly lazy: item offsets become arithmetic, so
  /// nothing outside the window is ever built or measured.
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

  double _cacheExtent;

  /// How far beyond each end of the window items are kept alive.
  double get cacheExtent => _cacheExtent;

  set cacheExtent(double value) {
    if (_cacheExtent == value) return;
    assert(value >= 0.0);
    _cacheExtent = value;
    markNeedsLayout();
  }

  final Layout3dItemBuilder? _builder;

  int _itemCount;

  /// How many items the list holds.
  ///
  /// For an explicit list this follows the child list, so adding or removing
  /// a child is reflected here; only a built list keeps a count of its own.
  int get itemCount => _builder == null ? childCount : _itemCount;

  set itemCount(int value) {
    if (_itemCount == value) return;
    assert(value >= 0);
    assert(
      _builder != null,
      'itemCount follows the child list for a ListView3d built from explicit '
      'children; use ListView3d.builder to set it directly.',
    );
    _itemCount = value;
    _resetChildren();
    markNeedsLayout();
  }

  /// Whether this list builds its items on demand.
  bool get isLazy => _builder != null;

  /// The items currently built, by index.
  ///
  /// Everything for an explicit list; the window plus [cacheExtent] for a
  /// built one.
  Iterable<int> get activeIndices => _active.keys;

  final Map<int, Layout3d> _active = <int, Layout3d>{};

  /// Prefix offsets: `_prefix[i]` is where item `i` starts, including
  /// [spacing]. Only used when items are measured rather than given a fixed
  /// [itemExtent].
  final List<double> _prefix = <double>[0.0];

  bool _layingOut = false;

  void _handleScrollChanged() {
    if (_layingOut) return;
    markNeedsLayout();
  }

  @override
  void markNeedsLayout() {
    // Building and releasing items happens inside performLayout; those child
    // list edits must not re-dirty the list that is being laid out.
    if (_layingOut) return;
    super.markNeedsLayout();
  }

  /// Drops the cached item measurements, forcing them to be measured again.
  ///
  /// Call after the content of built items changes size.
  void _resetMeasurements() {
    _prefix
      ..clear()
      ..add(0.0);
  }

  /// Drops every built item, for a change that invalidates all of them.
  void _resetChildren() {
    _resetMeasurements();
    if (_builder == null) return;
    for (final child in _active.values.toList()) {
      remove(child);
      child.dispose();
    }
    _active.clear();
  }

  /// Rebuilds the list from scratch, for when the item builder's data
  /// changed.
  void refresh() {
    _resetChildren();
    markNeedsLayout();
  }

  Constraints3d _childConstraints(double? mainExtent) {
    var result = const Constraints3d().withAxis(
      _axis,
      min: mainExtent ?? 0.0,
      max: mainExtent ?? double.infinity,
    );
    final (firstCross, secondCross) = _axis.others;
    for (final axis in <Axis3d>[firstCross, secondCross]) {
      final alignment = axis == firstCross
          ? _crossAxisAlignment
          : _depthAxisAlignment;
      final limit = constraints.maxAlong(axis);
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

  /// Opaque to hits across the whole window, spacing between items included,
  /// so a drag that starts on a gap still scrolls the list. Items culled out
  /// of the window are hidden, and [hitTestChild] skips hidden nodes, so what
  /// is out of view is out of reach.
  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  void performLayout() {
    _layingOut = true;
    try {
      _performListLayout();
    } finally {
      _layingOut = false;
    }
  }

  void _performListLayout() {
    final axis = _axis;
    final (firstCross, secondCross) = axis.others;
    final boundedMain = constraints.hasBoundedAlong(axis);
    final windowExtent = boundedMain
        ? constraints.maxAlong(axis)
        : double.infinity;

    var firstCrossExtent = 0.0;
    var secondCrossExtent = 0.0;
    void trackCross(Size3d childSize) {
      firstCrossExtent = math.max(
        firstCrossExtent,
        childSize.alongAxis(firstCross),
      );
      secondCrossExtent = math.max(
        secondCrossExtent,
        childSize.alongAxis(secondCross),
      );
    }

    final itemExtent = _itemExtent;
    final childConstraints = _childConstraints(itemExtent);
    final count = itemCount;

    // 1. Work out where every item starts, building only what is needed.
    double contentExtent;
    var firstIndex = 0;
    var lastIndex = count - 1;

    if (itemExtent != null) {
      final stride = itemExtent + _spacing;
      contentExtent = count > 0 ? count * stride - _spacing : 0.0;
      final mainSize = boundedMain ? windowExtent : contentExtent;
      final offset = _controller.offset.clamp(
        0.0,
        math.max(0.0, contentExtent - mainSize),
      );
      firstIndex = math.max(0, ((offset - _cacheExtent) / stride).floor());
      lastIndex = math.min(
        count - 1,
        ((offset + mainSize + _cacheExtent) / stride).floor(),
      );
      if (_builder == null) {
        for (final child in children) {
          child.layout(childConstraints, parentUsesSize: true);
          trackCross(child.size);
        }
      } else {
        for (var index = firstIndex; index <= lastIndex; index++) {
          trackCross(_obtainChild(index, childConstraints).size);
        }
        _releaseOutside(firstIndex, lastIndex);
      }
    } else if (_builder == null) {
      _resetMeasurements();
      for (final child in children) {
        child.layout(childConstraints, parentUsesSize: true);
        trackCross(child.size);
        _prefix.add(_prefix.last + child.size.alongAxis(axis) + _spacing);
      }
      contentExtent = _contentExtentOf(count);
    } else {
      // Measured lazily: walk forward until the window is covered, keeping
      // the running prefix so scrolling back needs no re-measuring.
      final probeEnd = _controller.offset + windowExtent + _cacheExtent;
      while (_measuredCount < count &&
          (!probeEnd.isFinite || _prefix.last <= probeEnd)) {
        final index = _measuredCount;
        final child = _obtainChild(index, childConstraints);
        trackCross(child.size);
        _prefix.add(_prefix.last + child.size.alongAxis(axis) + _spacing);
      }
      contentExtent = _estimatedContentExtent(count);
      final mainSize = boundedMain ? windowExtent : contentExtent;
      final offset = _controller.offset.clamp(
        0.0,
        math.max(0.0, contentExtent - mainSize),
      );
      firstIndex = _indexAtOffset(offset - _cacheExtent);
      lastIndex = _lastIndexBefore(offset + mainSize + _cacheExtent);
      for (var index = firstIndex; index <= lastIndex; index++) {
        trackCross(_obtainChild(index, childConstraints).size);
      }
      _releaseOutside(firstIndex, lastIndex);
    }

    // 2. Size the list, then report the metrics and read the clamped offset.
    final mainSize = boundedMain ? windowExtent : contentExtent;
    size = constraints.constrain(
      Size3d.zero
          .withAxis(axis, mainSize)
          .withAxis(
            firstCross,
            constraints.hasBoundedAlong(firstCross)
                ? constraints.maxAlong(firstCross)
                : firstCrossExtent,
          )
          .withAxis(
            secondCross,
            constraints.hasBoundedAlong(secondCross)
                ? constraints.maxAlong(secondCross)
                : secondCrossExtent,
          ),
    );
    final actualMain = size.alongAxis(axis);
    _controller.applyViewportMetrics(
      maxScrollExtent: math.max(0.0, contentExtent - actualMain),
      viewportExtent: actualMain,
      contentExtent: contentExtent,
    );
    final scrollOffset = _controller.offset;

    // 3. Place what is built, and hide what an explicit list keeps around.
    final actualFirstCross = size.alongAxis(firstCross);
    final actualSecondCross = size.alongAxis(secondCross);
    final windowStart = scrollOffset - _cacheExtent;
    final windowEnd = scrollOffset + actualMain + _cacheExtent;

    for (final entry in _positionedChildren(count)) {
      final (index, child) = entry;
      final start = _offsetOfIndex(index, itemExtent);
      final childSize = child.size;
      final extent = itemExtent ?? childSize.alongAxis(axis);
      child.place(
        Offset3d.zero
            .withAxis(axis, start - scrollOffset)
            .withAxis(
              firstCross,
              _crossOffset(
                _crossAxisAlignment,
                actualFirstCross,
                childSize.alongAxis(firstCross),
              ),
            )
            .withAxis(
              secondCross,
              _crossOffset(
                _depthAxisAlignment,
                actualSecondCross,
                childSize.alongAxis(secondCross),
              ),
            ),
      );
      child.node.visible = start + extent > windowStart && start < windowEnd;
    }
  }

  Iterable<(int, Layout3d)> _positionedChildren(int count) sync* {
    if (_builder == null) {
      for (var index = 0; index < childCount; index++) {
        yield (index, childAt(index));
      }
    } else {
      for (final entry in _active.entries) {
        yield (entry.key, entry.value);
      }
    }
  }

  int get _measuredCount => _prefix.length - 1;

  double _offsetOfIndex(int index, double? itemExtent) {
    if (itemExtent != null) return index * (itemExtent + _spacing);
    if (index < _prefix.length) return _prefix[index];
    return _prefix.last;
  }

  double _contentExtentOf(int count) {
    if (count == 0) return 0.0;
    return math.max(0.0, _prefix.last - _spacing);
  }

  /// The total extent, exact once every item has been measured and an average
  /// based estimate before that.
  double _estimatedContentExtent(int count) {
    final measured = _measuredCount;
    if (measured >= count) return _contentExtentOf(count);
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
    // Baseline alignment falls back to the start here: a scrolling view lays
    // its children out one after another, so there is no shared line for
    // their baselines to sit on.
    CrossAxisAlignment3d.start ||
    CrossAxisAlignment3d.stretch ||
    CrossAxisAlignment3d.baseline => 0.0,
    CrossAxisAlignment3d.end => extent - childExtent,
    CrossAxisAlignment3d.center => (extent - childExtent) / 2.0,
  };

  @override
  void dispose() {
    _controller.removeListener(_handleScrollChanged);
    if (_ownsController) _controller.dispose();
    _active.clear();
    super.dispose();
  }
}
