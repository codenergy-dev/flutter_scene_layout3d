import 'dart:math' as math;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../built_children.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../layout3d.dart';
import 'sliver.dart';
import 'sliver_constraints.dart';

/// Builds the layout for one item of a [SliverList3d.builder].
@Deprecated(
  'Use Layout3dItemBuilder, which every builder in the package shares. '
  'This alias will be removed in a future release.',
)
typedef Sliver3dItemBuilder = Layout3dItemBuilder;

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
///
/// Without an [itemExtent] the length of the list is a guess, and the guess
/// changes. Items are measured as they are first scrolled past, and the total
/// is the average of what has been measured so far, so a list of unequal items
/// reports one `scrollExtent` early on and a different one later. Anything
/// after it in the viewport moves when it does, and this sliver does not issue
/// a [SliverGeometry3d.scrollOffsetCorrection] to absorb the difference.
/// Giving every item the same [itemExtent] makes the length arithmetic and the
/// problem disappear; it is worth doing whenever the items really are uniform.
class SliverList3d extends Sliver3d
    with
        Layout3dWithChildrenMixin<ParentData3d>,
        Layout3dBuiltChildrenMixin<ParentData3d>,
        Layout3dMeasuredChildrenMixin<ParentData3d> {
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
       assert(spacing >= 0.0),
       assert(itemExtent == null || itemExtent > 0.0) {
    addAll(children);
  }

  /// Creates a list that builds its items on demand.
  SliverList3d.builder({
    required int itemCount,
    required Layout3dItemBuilder itemBuilder,
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
       assert(itemCount >= 0),
       assert(spacing >= 0.0),
       assert(itemExtent == null || itemExtent > 0.0) {
    declaredItemCount = itemCount;
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
  /// Makes a built list exactly lazy: item offsets become arithmetic, so the
  /// total extent is known without measuring anything.
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

  final Layout3dItemBuilder? _builder;

  @override
  Layout3dItemBuilder? get itemBuilder => _builder;

  /// What an item is offered: its fixed extent along the scroll axis if there
  /// is one, the sliver's own room across the other two.
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

  @override
  void performSliverLayout() => runLayoutPass(_performListLayout);

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
          obtainChild(index, childConstraints);
        }
        releaseOutside(firstIndex, lastIndex);
      }
    } else if (_builder == null) {
      resetMeasurements();
      for (final child in children) {
        child.layout(childConstraints, parentUsesSize: true);
        recordMeasurement(child.size.alongAxis(axis));
      }
      contentExtent = contentExtentOf(count);
    } else {
      // Measured lazily: walk forward until the window is covered, keeping
      // the running prefix so scrolling back needs no re-measuring.
      while (measuredCount < count && measuredEnd <= windowEnd) {
        final child = obtainChild(measuredCount, childConstraints);
        recordMeasurement(child.size.alongAxis(axis));
      }
      contentExtent = estimatedContentExtent(count);
      firstIndex = indexAtOffset(windowStart);
      lastIndex = lastIndexBefore(windowEnd);
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
    for (final (index, child) in positionedChildren()) {
      final start = offsetOfIndex(index, itemExtent);
      final childSize = child.size;
      final extent = itemExtent ?? childSize.alongAxis(axis);
      child.place(
        Offset3d.zero
            .withAxis(axis, start - constraints.scrollOffset)
            .withAxis(
              crossAxis,
              scrollCrossOffset(
                _crossAxisAlignment,
                constraints.crossAxisExtent,
                childSize.alongAxis(crossAxis),
              ),
            )
            .withAxis(
              depthAxis,
              scrollCrossOffset(
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
}
