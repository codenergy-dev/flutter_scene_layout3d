import 'dart:math' as math;

import 'package:flutter/foundation.dart' show protected;

import 'boxes/flex.dart' show CrossAxisAlignment3d;
import 'geometry/constraints3d.dart';
import 'geometry/offset3d.dart';
import 'layout3d.dart';
import 'layout_pass.dart';

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

/// Why a built view refuses a child list edit from outside.
///
/// A built view tracks its children by index, and everything it does —
/// measuring, placing, culling, releasing — goes through that map. A child
/// inserted from outside is in the child list but not in the map, so it is
/// never laid out (the first read of its size trips the "has not been laid
/// out yet" assert) and never released.
///
/// Written once because two layouts refuse the same edit: the view that keeps
/// the map, and a `BoxScrollView3d` that forwards its child list to one. The
/// wrapper has to say so in its own name — a caller who wrote
/// `ListView3d.builder` is not helped by a message about the sliver inside it
/// — so it asserts before forwarding, with this.
String builtChildEditRefused({
  required Object view,
  required String method,
  required String itemNoun,
}) =>
    'Cannot call $method on a ${view.runtimeType}.builder. Its $itemNoun come '
    'from itemBuilder and are tracked by index; a child added from outside is '
    'never laid out and never released. Set itemCount, or call refresh() '
    'when the data behind the builder changed.';

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
///
/// [runLayoutPass] comes from [Layout3dLayoutPassMixin], which this depends
/// on: building and releasing children edits the child list, and those edits
/// must not re-dirty the view that is being laid out.
mixin Layout3dBuiltChildrenMixin<ParentDataType extends ParentData3d>
    on Layout3dWithChildrenMixin<ParentDataType>, Layout3dLayoutPassMixin {
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

  /// Refuses a child list edit from outside, which the bookkeeping would not
  /// survive.
  void _assertNotBuilt(String method) {
    assert(
      itemBuilder == null,
      builtChildEditRefused(view: this, method: method, itemNoun: itemNoun),
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

/// Builds the one item a list measures to learn how long an item is.
///
/// The answer to "my items are all the same size, but I cannot tell you the
/// number": see [Layout3dMeasuredChildrenMixin.prototypeItem].
typedef Layout3dPrototypeBuilder = Layout3d Function();

/// States how long a list's content is, for a list that cannot know.
///
/// See [Layout3dMeasuredChildrenMixin.contentExtentEstimator].
typedef Layout3dContentExtentEstimator = double Function(int itemCount);

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
///
/// Measuring is the fallback, not the goal. Three ways out live here too, in
/// the order they are worth reaching for: [itemExtent], when the caller knows
/// how long an item is; [prototypeItem], when the items are uniform but only
/// the content knows the number; and [contentExtentEstimator], when the items
/// really are ragged but the caller knows the total anyway. The first two
/// turn every offset into arithmetic; the third leaves the offsets measured
/// and only steadies the total.
mixin Layout3dMeasuredChildrenMixin<ParentDataType extends ParentData3d>
    on Layout3dBuiltChildrenMixin<ParentDataType> {
  /// The gap between adjacent children, which the running sums include.
  @protected
  double get itemSpacing;

  double? _itemExtent;

  /// A fixed extent for every item along the scroll axis.
  ///
  /// Makes a built list exactly lazy: item offsets become arithmetic, so the
  /// total extent is known without measuring anything and nothing outside the
  /// window is ever built.
  ///
  /// Mutually exclusive with [prototypeItem], which answers the same question
  /// from the content instead of from the caller.
  double? get itemExtent => _itemExtent;

  set itemExtent(double? value) {
    if (_itemExtent == value) return;
    assert(value == null || value > 0.0);
    assert(value == null || _prototypeItem == null, _oneExtentOnly);
    _itemExtent = value;
    resetMeasurements();
    markNeedsLayout();
  }

  Layout3dPrototypeBuilder? _prototypeItem;
  Layout3d? _prototype;
  Constraints3d? _prototypeConstraints;
  double? _prototypeExtent;
  bool _prototypeMeasured = false;

  /// An item built once and measured, standing for the extent of them all.
  ///
  /// [itemExtent] for a list whose items are uniform in a size the caller
  /// cannot state as a number — a card whose height comes from a model's
  /// bounds, say. The list builds one of these, lays it out against the same
  /// constraints an item gets, and uses what comes back everywhere it would
  /// have used [itemExtent]:
  ///
  /// ```dart
  /// ListView3d.builder(
  ///   itemCount: 5000,
  ///   prototypeItem: () => NodeBox3d(content: sampleCard),
  ///   itemBuilder: (index) => NodeBox3d(content: cards[index]),
  /// )
  /// ```
  ///
  /// Every offset becomes arithmetic again, which is what removes the two
  /// costs of a measured list: a reachable range that moves as more items are
  /// measured, and a jump into the middle that measures everything before it.
  ///
  /// The prototype is measured, never shown. It is laid out on its own rather
  /// than as one of the items, and its node is never put in the scene, so it
  /// cannot be hit, culled, or drawn. It is measured again when the
  /// constraints an item gets change, and dropped by [refresh].
  ///
  /// Mutually exclusive with [itemExtent].
  Layout3dPrototypeBuilder? get prototypeItem => _prototypeItem;

  set prototypeItem(Layout3dPrototypeBuilder? value) {
    if (identical(_prototypeItem, value)) return;
    assert(value == null || _itemExtent == null, _oneExtentOnly);
    _prototypeItem = value;
    _discardPrototype();
    resetMeasurements();
    markNeedsLayout();
  }

  static const String _oneExtentOnly =
      'itemExtent and prototypeItem are two answers to the same question — '
      'how long is an item — and a list takes one of them. State the number, '
      'or hand over an item to measure, not both.';

  void _discardPrototype() {
    _prototype?.dispose();
    _prototype = null;
    _prototypeConstraints = null;
    _prototypeExtent = null;
    _prototypeMeasured = false;
  }

  @override
  void refresh() {
    // The prototype comes from the same data the items do, so it is as stale
    // as they are.
    _discardPrototype();
    super.refresh();
  }

  @override
  void dispose() {
    _discardPrototype();
    super.dispose();
  }

  /// The extent every item takes along [axis], when the view can know it
  /// without measuring the items.
  ///
  /// [itemExtent] when the caller stated one, the [prototypeItem]'s measured
  /// extent when it handed over an item instead, and null when the view has
  /// neither and has to measure as it goes. [childConstraints] are what an
  /// item is offered with the scroll axis left free, which is what the
  /// prototype is measured against.
  ///
  /// Measures at most once per layout: the answer is kept until the
  /// constraints change.
  @protected
  double? resolveItemExtent(Constraints3d childConstraints, Axis3d axis) {
    final fixed = _itemExtent;
    if (fixed != null) return fixed;
    final builder = _prototypeItem;
    if (builder == null) return null;
    final prototype = _prototype ??= builder();
    if (!_prototypeMeasured || _prototypeConstraints != childConstraints) {
      prototype.layout(childConstraints, parentUsesSize: true);
      // Belt and braces. The node is never mounted, which is what actually
      // keeps the prototype off the screen; this is so that a reader who
      // finds it in a debugger does not have to work that out.
      prototype.node.visible = false;
      final extent = prototype.size.alongAxis(axis);
      final usable = extent > 0.0 && extent.isFinite;
      assert(
        usable,
        'The prototypeItem of $runtimeType measured $extent along $axis. A '
        'prototype stands for how long every item is, so it has to be that '
        'long itself; this list is falling back to measuring its items.',
      );
      _prototypeConstraints = childConstraints;
      _prototypeExtent = usable ? extent : null;
      _prototypeMeasured = true;
    }
    return _prototypeExtent;
  }

  Layout3dContentExtentEstimator? _contentExtentEstimator;

  /// The total extent along the scroll axis, when the caller knows it.
  ///
  /// A list of free-sized items can only average what it has measured, and
  /// that average moves as it measures more, taking the reachable range with
  /// it. An application that knows the real total — because it knows the data
  /// — can say so and stop the range from moving.
  ///
  /// Called with the item count, and only while there is something left to
  /// estimate: once every item has been measured the exact total is used.
  /// An answer shorter than what has already been measured is raised to it,
  /// because where an item sits comes from that measurement and is exact.
  ///
  /// Unnecessary with [itemExtent] or [prototypeItem], which give the list an
  /// exact total of their own; it is ignored there.
  Layout3dContentExtentEstimator? get contentExtentEstimator =>
      _contentExtentEstimator;

  set contentExtentEstimator(Layout3dContentExtentEstimator? value) {
    if (identical(_contentExtentEstimator, value)) return;
    _contentExtentEstimator = value;
    markNeedsLayout();
  }

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

  /// The total extent: exact once every child has been measured, whatever
  /// [contentExtentEstimator] says before that, and an average of what has
  /// been measured when there is no estimator either.
  ///
  /// The average is the same approximation Flutter's `SliverList` makes, and
  /// it has the same consequence: the answer changes as more children are
  /// measured. That is what the estimator is for.
  @protected
  double estimatedContentExtent(int count) {
    final measured = measuredCount;
    if (measured >= count) return contentExtentOf(count);
    final estimator = _contentExtentEstimator;
    if (estimator != null) {
      return math.max(contentExtentOf(measured), estimator(count));
    }
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

  /// How many children one pass may measure before it is worth complaining
  /// about, for [debugMeasuringPassWasSane].
  static const int debugMeasuringPassLimit = 500;

  /// Whether a pass that measured [measured] children did a sane amount of
  /// work, for an `assert` at the end of a measuring loop.
  ///
  /// A measured list starts its running total at the first item, so reaching
  /// an offset deep into it builds every item before it in one pass and
  /// throws all but the window away again. There is no cheap fix inside this
  /// mode — knowing where item 4000 starts means knowing the extent of the
  /// 4000 before it — so what this does is turn a mysterious frame hitch into
  /// a message naming the two ways out.
  ///
  /// Only for a window that is bounded: a list asked to lay out in unbounded
  /// room is genuinely showing all of its items, and measuring them is the
  /// work, not a symptom of it.
  @protected
  bool debugMeasuringPassWasSane(int measured, {required bool boundedWindow}) {
    assert(
      !boundedWindow || measured <= debugMeasuringPassLimit,
      'A single layout of this $runtimeType measured $measured $itemNoun to '
      'reach the window, and kept only what the window shows. A list without '
      'an itemExtent measures forward from its first item, so a deep scroll '
      'offset costs every item before it. Give it an itemExtent if you know '
      'how long an item is, or a prototypeItem if the items are uniform but '
      'you do not.',
    );
    return true;
  }
}
