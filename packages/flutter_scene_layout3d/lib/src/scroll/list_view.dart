import 'dart:math' as math;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../built_children.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'scroll_controller.dart';
import 'scrollable.dart';

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
    with
        Layout3dBuiltChildrenMixin<ParentData3d>,
        Layout3dMeasuredChildrenMixin<ParentData3d>
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
       assert(itemCount >= 0),
       assert(spacing >= 0.0),
       assert(cacheExtent >= 0.0),
       assert(itemExtent == null || itemExtent > 0.0) {
    declaredItemCount = itemCount;
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

  /// Sets the position, or hands ownership back with null.
  ///
  /// Null means "make one of your own", the same thing it means in the
  /// constructor, so a declarative caller that stops passing a controller gets
  /// a fresh one rather than keeping the last one it happened to pass. A
  /// controller supplied from outside belongs to whoever supplied it and is
  /// never disposed here; one this view made is.
  set controller(Scroll3dController? value) {
    if (identical(_controller, value)) return;
    _controller.removeListener(_handleScrollChanged);
    if (_ownsController) _controller.dispose();
    _ownsController = value == null;
    _controller = (value ?? Scroll3dController())
      ..addListener(_handleScrollChanged);
    markNeedsLayout();
  }

  double _spacing;

  /// The gap between adjacent items.
  double get spacing => _spacing;

  @override
  double get itemSpacing => _spacing;

  set spacing(double value) {
    if (_spacing == value) return;
    assert(value >= 0.0);
    _spacing = value;
    resetMeasurements();
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
    resetMeasurements();
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

  @override
  Layout3dItemBuilder? get itemBuilder => _builder;

  /// A scroll position that moved needs a new layout, unless it moved
  /// *during* one — and [markNeedsLayout] already ignores that case.
  void _handleScrollChanged() => markNeedsLayout();

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
  void performLayout() => runLayoutPass(_performListLayout);

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
          trackCross(obtainChild(index, childConstraints).size);
        }
        releaseOutside(firstIndex, lastIndex);
      }
    } else if (_builder == null) {
      resetMeasurements();
      for (final child in children) {
        child.layout(childConstraints, parentUsesSize: true);
        trackCross(child.size);
        recordMeasurement(child.size.alongAxis(axis));
      }
      contentExtent = contentExtentOf(count);
    } else {
      // Measured lazily: walk forward until the window is covered, keeping
      // the running prefix so scrolling back needs no re-measuring.
      final probeEnd = _controller.offset + windowExtent + _cacheExtent;
      while (measuredCount < count &&
          (!probeEnd.isFinite || measuredEnd <= probeEnd)) {
        final child = obtainChild(measuredCount, childConstraints);
        trackCross(child.size);
        recordMeasurement(child.size.alongAxis(axis));
      }
      contentExtent = estimatedContentExtent(count);
      final mainSize = boundedMain ? windowExtent : contentExtent;
      final offset = _controller.offset.clamp(
        0.0,
        math.max(0.0, contentExtent - mainSize),
      );
      firstIndex = indexAtOffset(offset - _cacheExtent);
      lastIndex = lastIndexBefore(offset + mainSize + _cacheExtent);
      for (var index = firstIndex; index <= lastIndex; index++) {
        trackCross(obtainChild(index, childConstraints).size);
      }
      releaseOutside(firstIndex, lastIndex);
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

    for (final entry in positionedChildren()) {
      final (index, child) = entry;
      final start = offsetOfIndex(index, itemExtent);
      final childSize = child.size;
      final extent = itemExtent ?? childSize.alongAxis(axis);
      child.place(
        Offset3d.zero
            .withAxis(axis, start - scrollOffset)
            .withAxis(
              firstCross,
              scrollCrossOffset(
                _crossAxisAlignment,
                actualFirstCross,
                childSize.alongAxis(firstCross),
              ),
            )
            .withAxis(
              secondCross,
              scrollCrossOffset(
                _depthAxisAlignment,
                actualSecondCross,
                childSize.alongAxis(secondCross),
              ),
            ),
      );
      child.node.visible = start + extent > windowStart && start < windowEnd;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScrollChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}
