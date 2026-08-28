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

/// Why a view built from an explicit list of children refuses an `itemCount`.
///
/// The mirror of [builtChildEditRefused], and written beside it for the same
/// reason: the wrapper has to refuse in its own name, or a caller who wrote
/// `ListView3d(children: ...)` is told about a `SliverList3d` they never
/// mentioned.
String explicitChildCountRefused({
  required Object view,
  required String itemNoun,
}) =>
    'itemCount belongs to ${view.runtimeType}.builder; a view built from an '
    'explicit list of children takes its count from the $itemNoun in it. Edit '
    'the child list instead, with add, remove or syncChildren.';

/// A layout that can point at the view holding its built children.
///
/// Two layouts answer this: a view that holds them itself, and a
/// `BoxScrollView3d`, which is a window around one sliver and forwards
/// everything about its children to it. The declarative layer needs the
/// difference resolved — a `SceneListView3d.builder` creates a `ListView3d`
/// but the manager belongs on the `SliverList3d` inside it — and this is how
/// it asks without knowing which it has.
abstract interface class Layout3dBuiltChildrenHost {
  /// The view that holds the children, which may be this layout itself.
  Layout3dBuiltChildrenMixin get builtChildren;
}

/// The view holding [layout]'s built children.
///
/// Throws if [layout] holds none, which for the declarative layer is a bug in
/// a widget's `createLayout` rather than anything a caller did.
Layout3dBuiltChildrenMixin builtChildrenOf(Layout3d layout) {
  assert(
    layout is Layout3dBuiltChildrenHost,
    '${layout.runtimeType} does not build its children on demand, so it '
    'cannot be given a child manager.',
  );
  return (layout as Layout3dBuiltChildrenHost).builtChildren;
}

/// Builds and disposes the children of a view that builds them on demand.
///
/// The 3D analogue of `RenderSliverBoxChildManager`, and the seam that lets a
/// lazily built child be a *widget* rather than a bare [Layout3d]. A view that
/// mixes in [Layout3dBuiltChildrenMixin] asks its manager for the child at an
/// index instead of calling a [Layout3dItemBuilder] itself, so the same
/// `SliverList3d` serves both shapes: the imperative builder, which is a
/// manager over a function, and the declarative one, whose manager is an
/// element that inflates a widget inside a build scope.
///
/// Every call happens inside the view's layout pass. That is legal for the
/// same reason it is legal in Flutter — the pass runs inside Flutter's own
/// layout phase, in the window `SliverMultiBoxAdaptorElement` builds in — but
/// it does mean an implementation must not do anything a layout cannot do,
/// such as marking an ancestor as needing layout.
abstract class Layout3dChildManager {
  /// Creates a manager. Implementations are usually elements.
  const Layout3dChildManager();

  /// How many children this manager can build, or null when it does not know.
  ///
  /// A view falls back to the count it was given directly when this is null.
  int? get estimatedChildCount;

  /// Builds the child standing for [index], or returns null when there is
  /// none.
  ///
  /// Called once per index per pass, and only for an index the view does not
  /// already hold. The child comes back unparented; the view adopts it.
  Layout3d? createChild(int index);

  /// Releases the child standing for [index], which the view has already
  /// removed from its child list.
  ///
  /// Whoever created the child disposes it: a manager over a function does it
  /// here and now, while an element hands the child's element to Flutter to
  /// deactivate and lets the render tree dispose the layout when the element
  /// is finally unmounted, so that a `GlobalKey` can still reclaim it.
  void removeChild(int index, Layout3d child);

  /// Called before a layout pass touches any child.
  void didStartLayout() {}

  /// Called after a layout pass has finished building and releasing.
  void didFinishLayout() {}
}

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
    on Layout3dWithChildrenMixin<ParentDataType>, Layout3dLayoutPassMixin
    implements Layout3dBuiltChildrenHost {
  @override
  Layout3dBuiltChildrenMixin get builtChildren => this;

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

  Layout3dChildManager? _childManager;

  /// Who builds this view's children, when something other than an
  /// [itemBuilder] does.
  ///
  /// Set by the declarative layer, whose element is the manager. A view with
  /// a manager is lazy in exactly the same way a view with an [itemBuilder]
  /// is: the two are the same mode reached from two directions, and nothing
  /// below this line asks which of them it is.
  Layout3dChildManager? get childManager => _childManager;

  set childManager(Layout3dChildManager? value) {
    if (identical(_childManager, value)) return;
    assert(
      value == null || itemBuilder == null,
      'A view builds its children from an itemBuilder or from a child '
      'manager, not both.',
    );
    // One manager, set when the element that is the manager mounts and
    // cleared when it unmounts. Swapping one for another would leave children
    // behind that the new manager never built and cannot release; the element
    // layer never does it, because a new element builds a new layout.
    assert(
      value == null || _childManager == null,
      'A view has one child manager, and $runtimeType already has one.',
    );
    _childManager = value;
    resetMeasurements();
    markNeedsLayout();
  }

  /// How many children this view holds.
  int get itemCount {
    if (!isLazy) return childCount;
    return _childManager?.estimatedChildCount ?? declaredItemCount;
  }

  set itemCount(int value) {
    assert(isLazy, explicitChildCountRefused(view: this, itemNoun: itemNoun));
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
  bool get isLazy => itemBuilder != null || _childManager != null;

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
      !isLazy,
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
    if (isLazy) {
      final manager = _childManager;
      for (final entry in _active.entries.toList()) {
        super.remove(entry.value);
        if (manager != null) {
          manager.removeChild(entry.key, entry.value);
        } else {
          entry.value.dispose();
        }
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
      final manager = _childManager;
      final built = manager == null
          ? itemBuilder!(index)
          : manager.createChild(index);
      assert(
        built != null,
        'The child manager of $runtimeType built nothing for index $index, '
        'which is inside the $itemCount $itemNoun it says it has.',
      );
      child = built!;
      // Kept in index order, so the child list and the scene graph read the
      // same way round however the window arrived at this index.
      final position = _active.keys.where((i) => i < index).length;
      _active[index] = child;
      super.insert(child, index: position);
    }
    child.layout(childConstraints, parentUsesSize: true);
    return child;
  }

  /// The child standing for [index], rebuilt from the manager even though one
  /// is already standing there.
  ///
  /// [obtainChild] builds an index once and then keeps it, which is what a
  /// scrolling view wants: the item at index 7 does not change because the
  /// window moved. A `LayoutBuilder3d` is the other case — its one child is a
  /// function of the constraints, so a new set of constraints means asking
  /// for it again — and this is that ask.
  ///
  /// The manager reconciles rather than rebuilds from nothing, so the item's
  /// element, and everything it holds, survives. It may still hand back a
  /// different layout (a widget that changed type), and the one it replaced
  /// is unparented here; disposing it belongs to whoever created it, which
  /// for the declarative layer is the element being unmounted.
  ///
  /// Returns what stands for [index] afterwards, or null when the manager
  /// built nothing.
  @protected
  Layout3d? rebuildChild(int index) {
    final manager = _childManager;
    if (manager == null) return _active[index];
    final previous = _active[index];
    final built = manager.createChild(index);
    if (identical(previous, built)) return built;
    if (previous != null) {
      _active.remove(index);
      if (identical(previous.parent, this)) super.remove(previous);
    }
    if (built == null) return null;
    final position = _active.keys.where((i) => i < index).length;
    _active[index] = built;
    if (!identical(built.parent, this)) super.insert(built, index: position);
    return built;
  }

  /// Disposes every built child outside `[first, last]`.
  @protected
  void releaseOutside(int first, int last) {
    for (final index in _active.keys.toList()) {
      if (index >= first && index <= last) continue;
      final child = _active.remove(index)!;
      super.remove(child);
      final manager = _childManager;
      if (manager != null) {
        manager.removeChild(index, child);
      } else {
        child.dispose();
      }
    }
  }

  /// The children this view has to place, with the index each one stands for.
  @protected
  Iterable<(int, Layout3d)> positionedChildren() sync* {
    if (!isLazy) {
      for (var index = 0; index < childCount; index++) {
        yield (index, childAt(index));
      }
      return;
    }
    for (final entry in _active.entries) {
      yield (entry.key, entry.value);
    }
  }

  /// Brackets the pass with the manager's own hooks.
  ///
  /// [Layout3dChildManager.didStartLayout] and
  /// [Layout3dChildManager.didFinishLayout] are where an element locks its
  /// child bookkeeping for the duration of a pass, the way
  /// `SliverMultiBoxAdaptorElement` does.
  @override
  @protected
  void runLayoutPass(void Function() body) {
    final manager = _childManager;
    if (manager == null) {
      super.runLayoutPass(body);
      return;
    }
    manager.didStartLayout();
    try {
      super.runLayoutPass(body);
    } finally {
      manager.didFinishLayout();
    }
  }

  /// Drops [child] without telling the manager, because the manager is the
  /// one asking.
  ///
  /// The teardown path of the declarative layer. A widget-built child is
  /// disposed when its element is unmounted, which for a whole tree going
  /// away happens child-first, *before* the surface disposes what is left of
  /// itself. Unless the child leaves this view's books on the way out, that
  /// second walk finds it and disposes it again.
  ///
  /// Only for a manager. A built view otherwise owns its children outright
  /// and releases them through [releaseOutside].
  void forgetBuiltChild(Layout3d child) {
    assert(_childManager != null);
    for (final index in _active.keys.toList()) {
      if (identical(_active[index], child)) {
        _active.remove(index);
        break;
      }
    }
    if (identical(child.parent, this)) super.remove(child);
    resetMeasurements();
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

  /// The exact extent of the first [count] children, all of them measured.
  ///
  /// A count past what has been measured is answered with the whole prefix,
  /// which is as far as this can be exact.
  @protected
  double contentExtentOf(int count) {
    if (count <= 0) return 0.0;
    final end = count < _prefix.length ? _prefix[count] : _prefix.last;
    return math.max(0.0, end - itemSpacing);
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

  /// How many children one pass may measure *and throw away* before it is
  /// worth complaining about, for [debugMeasuringPassWasSane].
  static const int debugMeasuringPassLimit = 500;

  /// Whether a pass that measured [measured] children and released
  /// [discarded] of them again did a sane amount of work, for an `assert` at
  /// the end of a measuring loop.
  ///
  /// A measured list starts its running total at the first item, so reaching
  /// an offset deep into it builds every item before it in one pass and
  /// throws all but the window away again. There is no cheap fix inside this
  /// mode — knowing where item 4000 starts means knowing the extent of the
  /// 4000 before it — so what this does is turn a mysterious frame hitch into
  /// a message naming the two ways out.
  ///
  /// It is the *discarded* items that say this happened, not the measured
  /// ones. A list in a long window genuinely shows hundreds of items at once,
  /// and measuring those is the work rather than a symptom of it; so is a
  /// list laid out in unbounded room, which shows all of them. In both of
  /// those nothing is thrown away, and this says nothing.
  @protected
  bool debugMeasuringPassWasSane({
    required int measured,
    required int discarded,
  }) {
    assert(
      discarded <= debugMeasuringPassLimit,
      'A single layout of this $runtimeType measured $measured $itemNoun to '
      'reach the window and threw $discarded of them away again. A list '
      'without an itemExtent measures forward from its first item, so a deep '
      'scroll offset costs every item before it. Give it an itemExtent if you '
      'know how long an item is, or a prototypeItem if the items are uniform '
      'but you do not.',
    );
    return true;
  }
}
