import 'dart:math' as math;

import 'package:flutter/foundation.dart' show protected;

import 'boxes/flex.dart' show CrossAxisAlignment3d;
import 'geometry/constraints3d.dart';
import 'layout3d.dart';

/// Where a child sits across an axis a scrolling view does not lay out on.
///
/// The one rule shared by every scrolling view here. [CrossAxisAlignment3d]
/// belongs to a flex, where a line of children shares an axis; a scrolling
/// view lays its children out one after another, so there is no shared line
/// for their baselines to sit on and [CrossAxisAlignment3d.baseline] falls
/// back to the start.
double scrollCrossOffset(
  CrossAxisAlignment3d alignment,
  double extent,
  double childExtent,
) => switch (alignment) {
  CrossAxisAlignment3d.start ||
  CrossAxisAlignment3d.stretch ||
  CrossAxisAlignment3d.baseline => 0.0,
  CrossAxisAlignment3d.end => extent - childExtent,
  CrossAxisAlignment3d.center => (extent - childExtent) / 2.0,
};

/// A child list that may be built on demand, for the views that hold one.
///
/// `ListView3d`, `GridView3d`, `SliverList3d` and `SliverGrid3d` all offer the
/// same two shapes: an explicit list of children, or an [itemBuilder] and a
/// count. The second shape needs bookkeeping the box protocol does not have —
/// a map from index to the child currently standing for it, built as the
/// window reaches it and disposed as the window leaves — and the four views
/// need exactly the same bookkeeping. This is it.
///
/// A view mixes this in, implements [itemBuilder], and calls [runLayoutPass],
/// [obtainChild], [releaseOutside] and [positionedChildren] from its own
/// layout. What is left in the view is the part that is actually its own:
/// where the children go.
mixin Layout3dBuiltChildrenMixin<ParentDataType extends ParentData3d>
    on Layout3dWithChildrenMixin<ParentDataType> {
  /// Builds the child standing for an index, or null when this view was given
  /// an explicit list of children instead.
  ///
  /// Implemented by the view, usually as a final field set in its `.builder`
  /// constructor.
  @protected
  Layout3dItemBuilder? get itemBuilder;

  /// What this view calls its children in an assertion message: "items" for a
  /// list, "cells" for a grid.
  @protected
  String get itemNoun => 'items';

  /// The count a built view was told to serve.
  ///
  /// Meaningless for a view built from an explicit list, which counts its
  /// children instead; read [itemCount], which knows the difference. Assign it
  /// from a `.builder` constructor body.
  @protected
  int declaredItemCount = 0;

  /// How many children this view holds.
  int get itemCount => itemBuilder == null ? childCount : declaredItemCount;

  set itemCount(int value) {
    assert(
      itemBuilder != null,
      'itemCount belongs to $runtimeType.builder; a view built from an '
      'explicit list of children takes its count from them.',
    );
    if (declaredItemCount == value) return;
    assert(value >= 0);
    declaredItemCount = value;
    // Anything cached about where the children sit was measured against the
    // old count. The children themselves are still right for their own
    // indices, so they are kept; the next layout releases whatever now falls
    // outside the window, which includes anything past the new end.
    resetMeasurements();
    markNeedsLayout();
  }

  /// Whether this view builds its children on demand.
  bool get isLazy => itemBuilder != null;

  final Map<int, Layout3d> _active = <int, Layout3d>{};

  /// The children currently built, by index.
  ///
  /// Everything for an explicit view; the window plus whatever cache the view
  /// keeps for a built one.
  Iterable<int> get activeIndices => _active.keys;

  bool _layingOut = false;

  /// Whether a layout pass is running on this view.
  @protected
  bool get layingOut => _layingOut;

  /// Runs [body] as this view's layout pass.
  ///
  /// Building and releasing children edits the child list, and those edits
  /// must not re-dirty the view that is being laid out. Wrap `performLayout`
  /// (or `performSliverLayout`) in this rather than setting a flag by hand.
  @protected
  void runLayoutPass(void Function() body) {
    _layingOut = true;
    try {
      body();
    } finally {
      _layingOut = false;
    }
  }

  @override
  void markNeedsLayout() {
    if (_layingOut) return;
    super.markNeedsLayout();
  }

  /// Refuses a child list edit from outside, which the bookkeeping would not
  /// survive.
  ///
  /// A built view tracks its children by index, and everything it does —
  /// measuring, placing, culling, releasing — goes through that map. A child
  /// inserted from outside is in the child list but not in the map, so it is
  /// never laid out (the first read of its size trips the "has not been laid
  /// out yet" assert) and never released.
  void _assertNotBuilt(String method) {
    assert(
      itemBuilder == null,
      'Cannot call $method on a $runtimeType.builder. Its $itemNoun come from '
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

  /// Drops whatever this view cached about where its children sit.
  ///
  /// Nothing, for a view whose positions are arithmetic;
  /// [Layout3dMeasuredChildrenMixin] overrides it with the prefix it keeps.
  @protected
  void resetMeasurements() {}

  /// Rebuilds every child, for when the data behind [itemBuilder] changed.
  ///
  /// The builder is the source of truth for what a built view holds, and this
  /// package cannot tell when what it returns has changed. Call this after
  /// editing the list the builder reads from.
  void refresh() {
    resetMeasurements();
    if (itemBuilder != null) {
      for (final child in _active.values.toList()) {
        super.remove(child);
        child.dispose();
      }
      _active.clear();
    }
    markNeedsLayout();
  }

  /// The child standing for [index], built if this is the first time the
  /// window has reached it, and laid out against [childConstraints].
  @protected
  Layout3d obtainChild(int index, Constraints3d childConstraints) {
    var child = _active[index];
    if (child == null) {
      child = itemBuilder!(index);
      // Kept in index order, so the child list and the scene graph read the
      // same way round however the window arrived at this index.
      final position = _active.keys.where((i) => i < index).length;
      _active[index] = child;
      super.insert(child, index: position);
    }
    child.layout(childConstraints, parentUsesSize: true);
    return child;
  }

  /// Disposes every built child outside `[first, last]`.
  @protected
  void releaseOutside(int first, int last) {
    for (final index in _active.keys.toList()) {
      if (index >= first && index <= last) continue;
      final child = _active.remove(index)!;
      super.remove(child);
      child.dispose();
    }
  }

  /// The children this view has to place, with the index each one stands for.
  @protected
  Iterable<(int, Layout3d)> positionedChildren() sync* {
    if (itemBuilder == null) {
      for (var index = 0; index < childCount; index++) {
        yield (index, childAt(index));
      }
      return;
    }
    for (final entry in _active.entries) {
      yield (entry.key, entry.value);
    }
  }

  @override
  void dispose() {
    _active.clear();
    super.dispose();
  }
}

/// Running measurements for a view whose children are not all the same size.
///
/// A grid knows where its cells are by arithmetic and needs none of this. A
/// list of free-sized children does not: it has to measure a child to know
/// where the next one starts, so it keeps the running sums as it goes and can
/// only estimate the part it has not reached yet. `ListView3d` and
/// `SliverList3d` share the whole of that.
///
/// The prefix is never dropped as the window moves on, so scrolling back needs
/// no re-measuring; it is dropped when something invalidates it outright, and
/// [resetMeasurements] is what does that.
mixin Layout3dMeasuredChildrenMixin<ParentDataType extends ParentData3d>
    on Layout3dBuiltChildrenMixin<ParentDataType> {
  /// The gap between adjacent children, which the running sums include.
  @protected
  double get itemSpacing;

  /// Running start offsets: `_prefix[i]` is where child `i` begins, and the
  /// last entry is where the next one would.
  final List<double> _prefix = <double>[0.0];

  /// How many children have been measured.
  @protected
  int get measuredCount => _prefix.length - 1;

  /// Where the next unmeasured child would begin.
  @protected
  double get measuredEnd => _prefix.last;

  /// Records that the next unmeasured child is [extent] long.
  @protected
  void recordMeasurement(double extent) {
    _prefix.add(_prefix.last + extent + itemSpacing);
  }

  @override
  @protected
  void resetMeasurements() {
    _prefix
      ..clear()
      ..add(0.0);
  }

  /// Where the child at [index] begins.
  ///
  /// Arithmetic when every child is [itemExtent] long; the measured prefix
  /// otherwise, falling back to the end for an index not reached yet.
  @protected
  double offsetOfIndex(int index, double? itemExtent) {
    if (itemExtent != null) return index * (itemExtent + itemSpacing);
    if (index < _prefix.length) return _prefix[index];
    return _prefix.last;
  }

  /// The exact extent of [count] children, all of them measured.
  @protected
  double contentExtentOf(int count) {
    if (count == 0) return 0.0;
    return math.max(0.0, _prefix.last - itemSpacing);
  }

  /// The total extent: exact once every child has been measured, and an
  /// average-based estimate before that.
  ///
  /// The same approximation Flutter's `SliverList` makes, and it has the same
  /// consequence: the answer changes as more children are measured.
  @protected
  double estimatedContentExtent(int count) {
    final measured = measuredCount;
    if (measured >= count) return contentExtentOf(count);
    if (measured == 0) return 0.0;
    final averageStride = _prefix.last / measured;
    return math.max(0.0, averageStride * count - itemSpacing);
  }

  /// The index of the child covering [offset], clamped into range.
  @protected
  int indexAtOffset(double offset) {
    if (offset <= 0.0 || measuredCount == 0) return 0;
    var low = 0;
    var high = measuredCount - 1;
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
  ///
  /// A binary search over the same sorted prefix [indexAtOffset] walks: the
  /// measured list only grows, so scanning it linearly would make the cost of
  /// a layout climb with how far the list had ever been scrolled.
  @protected
  int lastIndexBefore(double end) {
    if (measuredCount == 0 || !(_prefix[0] < end)) return 0;
    var low = 0;
    var high = measuredCount - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_prefix[middle] < end) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }
}
