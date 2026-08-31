import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, IntProperty;
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../built_children.dart';
import '../geometry/offset3d.dart';
import '../input/drag.dart';
import '../input/draggable.dart';
import '../layout3d.dart';
import 'sliver_list.dart';

/// Told that an item moved from [oldIndex] to [newIndex].
///
/// **[newIndex] is where the item ends up**, so applying it is one line:
///
/// ```dart
/// onReorder: (oldIndex, newIndex) {
///   setState(() => items.insert(newIndex, items.removeAt(oldIndex)));
///   list.refresh();
/// }
/// ```
///
/// This is a deliberate deviation from Flutter's `ReorderableListView`, whose
/// `newIndex` is measured *before* the item is taken out and so has to be
/// decremented by the caller when it moved down the list. That off-by-one is
/// the single most reported confusion about that widget; there is nothing
/// this package gains by inheriting it.
typedef Reorder3dCallback = void Function(int oldIndex, int newIndex);

/// A run of items that can be dragged into a different order.
///
/// The sliver behind [ReorderableList3d], and a [SliverList3d] in every other
/// respect: the placement, the measuring, the lazy window and the extent
/// estimate are all the list's, unchanged. What this adds is one item lifted
/// out under the pointer, a gap where it would land, and one call to
/// [onReorder] at the drop.
///
/// ```dart
/// SliverReorderableList3d(
///   itemCount: tracks.length,
///   itemBuilder: (index) => trackRow(tracks[index]),
///   onReorder: (oldIndex, newIndex) {
///     tracks.insert(newIndex, tracks.removeAt(oldIndex));
///     list.refresh();
///   },
/// )
/// ```
///
/// ## Nothing is reordered until the drop
///
/// This is the whole design, and both of the hard requirements fall out of
/// it. During a drag the dragged item **stays exactly where it is in the
/// list**, hidden with `node.visible = false` — the trick [IndexedStack3d]
/// and the scrolling views already use, which costs no layout — so its extent
/// stays in the flow and *is* the gap. Every other item near it is pushed
/// forward or back by that extent with [Layout3d.nodeOffset], the node tier,
/// which writes one matrix and never calls `markNeedsLayout`.
///
/// So:
///
///  * **the lazy machinery is untouched.** The index-to-child map never
///    changes while a drag is live: no `createChild`, no `removeChild`, no
///    rebuild, and the item at index 7 is still the item at index 7 when the
///    finger lets go;
///  * **nothing reaches the relayout path.** Every visible change a reorder
///    makes is a matrix write. The two layout passes a drag costs are the
///    ones every drag costs — putting the feedback into the overlay and
///    taking it out again — plus the one at the end, which is the caller's
///    own rebuild.
///
/// At the drop the list reports `(oldIndex, newIndex)` once, the caller
/// reorders its data and calls [refresh], and one ordinary layout puts
/// everything where it belongs.
///
/// ## The items are built, not listed
///
/// Unlike [SliverList3d] there is no constructor over an explicit child list.
/// A reorder is a statement about the caller's data — [onReorder] hands back
/// a pair of indices into it and expects the next build to reflect them — so
/// the list has to be a function of that data to be coherent at all. Give it
/// an [itemCount] and an [itemBuilder]; call [refresh] when the data changes.
///
/// ## Where the gap goes when items differ in extent
///
/// The gap is exactly the dragged item's own extent, and nothing smarter,
/// which is what Flutter does and which jitters slightly when a short row is
/// dragged past a tall one. The insert index is read from the pointer's
/// position in scroll space against the *leading edges* of the items the view
/// currently holds — see [insertIndexAt] — so the item under the finger is
/// the one whose place is taken.
class SliverReorderableList3d extends SliverList3d implements Drag3dTarget {
  /// Creates a reorderable list that builds its items on demand.
  ///
  /// The sliver has to be handed a builder that wraps the caller's own, and
  /// an explicit super call rules out super parameters, so the list's
  /// ordinary knobs are spelled out here rather than forwarded.
  // ignore: use_super_parameters
  SliverReorderableList3d({
    required int itemCount,
    required Layout3dItemBuilder itemBuilder,
    required this.onReorder,
    this.feedbackBuilder,
    Drag3dStartMode startMode = const Drag3dStartMode.longPress(),
    this.gapDuration = const Duration(milliseconds: 200),
    this.gapCurve = Curves.easeInOut,
    this.vsync,
    double spacing = 0.0,
    double? itemExtent,
    Layout3dPrototypeBuilder? prototypeItem,
    Layout3dContentExtentEstimator? contentExtentEstimator,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.center,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    String? name,
  }) : _rawBuilder = itemBuilder,
       _startMode = startMode,
       super.builder(
         itemCount: itemCount,
         itemBuilder: itemBuilder,
         spacing: spacing,
         itemExtent: itemExtent,
         prototypeItem: prototypeItem,
         contentExtentEstimator: contentExtentEstimator,
         crossAxisAlignment: crossAxisAlignment,
         depthAxisAlignment: depthAxisAlignment,
         name: name,
       );

  /// Called once, at the drop, when an item ended somewhere else.
  ///
  /// Not called when the item was let go where it started, and not called
  /// when the drag was cancelled. See [Reorder3dCallback] for what the two
  /// indices mean — the second one is where the item *ends up*, which is not
  /// what Flutter's `ReorderableListView` reports.
  Reorder3dCallback onReorder;

  /// The builder the caller gave, before this list wrapped its items.
  ///
  /// Every item is wrapped in a [Draggable3d] that carries a token only this
  /// list accepts, which is how a press on an item becomes a reorder without
  /// the caller having to build a drag handle. [itemBuilder] is overridden to
  /// hand the wrapped builder to the machinery, so the wrapping is invisible
  /// to everything that walks the child list.
  final Layout3dItemBuilder _rawBuilder;

  Layout3d _buildWrapped(int index) => _wrap(_rawBuilder(index), index);

  @override
  Layout3dItemBuilder? get itemBuilder => _buildWrapped;

  /// Builds what is carried under the pointer, given the item's index.
  ///
  /// Null means a second copy of the item itself, built from the same
  /// `itemBuilder` — which is almost always what was meant, and costs one
  /// build per drag rather than one per frame. Name a builder to carry
  /// something else: a flattened row, a card with a shadow, a proxy that is
  /// not the item at all.
  Layout3dItemBuilder? feedbackBuilder;

  Drag3dStartMode _startMode;

  /// When a press on an item becomes a reorder drag.
  ///
  /// A long press by default, which is what keeps an ordinary drag on the
  /// items free for scrolling the list: the two compete in the arena, and the
  /// scroll claims the pointer on travel long before the delay is up.
  /// [Drag3dStartMode.immediate] belongs on a list whose items are drag
  /// handles and which does not scroll.
  Drag3dStartMode get startMode => _startMode;

  set startMode(Drag3dStartMode value) {
    if (_startMode == value) return;
    _startMode = value;
    // The items already built took a copy at construction, so they are told
    // rather than left one mode behind the list they are in.
    for (final (_, child) in positionedChildren()) {
      if (child is _Reorder3dHandle) child.startMode = value;
    }
  }

  /// How long the items take to slide aside when the gap moves.
  ///
  /// [Duration.zero] moves them at once, which is what a test wants.
  Duration gapDuration;

  /// The curve the items follow as they slide aside.
  Curve gapCurve;

  /// The ticker provider for the gap animation.
  ///
  /// Null means a bare [Ticker], which schedules through the same
  /// [SchedulerBinding] and works outside a `State`. Give one where there is
  /// a `State` in the picture so that `TickerMode` can mute it.
  TickerProvider? vsync;

  int? _dragIndex;
  int _insertIndex = 0;
  double _gapExtent = 0.0;

  /// Where each item sat along the scroll axis when the gap last moved.
  ///
  /// The start of the slide, so that an insert index that changes twice in
  /// quick succession is animated from where the items really are rather than
  /// from where the last slide began.
  final Map<int, double> _slideFrom = <int, double>{};

  double _slideT = 1.0;
  Ticker? _slideTicker;

  /// The index of the item being dragged, or null when nothing is.
  ///
  /// It does not move while the drag is live: the child list is not reordered
  /// until the drop.
  int? get dragIndex => _dragIndex;

  /// Where the dragged item would land if it were let go now, or null when
  /// nothing is being dragged.
  ///
  /// In the same terms [onReorder] reports: the index the item ends up at.
  int? get insertIndex => _dragIndex == null ? null : _insertIndex;

  /// Whether an item of this list is in flight.
  bool get isReordering => _dragIndex != null;

  // --------------------------------------------------------- the drop target

  @override
  bool willAcceptDrag3d(Drag3dDetails details) {
    final data = details.data;
    return data is _Reorder3dPayload && identical(data.list, this);
  }

  @override
  void handleDrag3d(Drag3dEvent event) {
    if (_dragIndex == null || !hasSliverConstraints) return;
    switch (event.kind) {
      case Drag3dEventKind.enter:
      case Drag3dEventKind.move:
        _moveGapTo(insertIndexAt(scrollOffsetOf(event.localPosition)));
      case Drag3dEventKind.leave:
        // The pointer wandered off the list. The gap stays where it was, so
        // coming back from the same side does not shuffle everything twice;
        // if the drag ends out there the session is cancelled and nothing is
        // reordered at all.
        break;
      case Drag3dEventKind.drop:
        final from = _dragIndex!;
        final to = _insertIndex;
        // Reported before the session ends, so the caller's own rebuild and
        // the release of the gap happen in that order rather than the reverse.
        if (from != to) onReorder(from, to);
    }
  }

  /// A point in this sliver's own frame, in the list's scroll coordinates.
  ///
  /// Items are placed at `start - scrollOffset`, so adding the scroll offset
  /// back is the whole conversion. Hit testing deliberately ignores
  /// [Layout3d.nodeOffset], so the point that arrives here is measured against
  /// the items where layout put them rather than where the gap animation has
  /// slid them — which is exactly the frame [insertIndexAt] reasons in.
  double scrollOffsetOf(Offset3d localPosition) =>
      localPosition.alongAxis(sliverConstraints.axis) +
      sliverConstraints.scrollOffset;

  /// The index whose place an item let go at [scrollOffset] would take.
  ///
  /// The last item whose leading edge the offset has passed, out of the items
  /// the view is currently holding — which is all the view knows and all it
  /// needs, since the pointer is inside the window by definition and anything
  /// further away is autoscroll's problem.
  ///
  /// Reasoned in the *unshifted* layout: the slots are where the items were
  /// laid out, not where the node tier has since slid them. That is what makes
  /// the answer stable — the slot the finger is over is the slot the item
  /// lands in, whatever has been moved aside to show it.
  int insertIndexAt(double scrollOffset) {
    final count = itemCount;
    if (count == 0) return 0;
    final axis = sliverConstraints.axis;
    final origin = sliverConstraints.scrollOffset;
    int? best;
    var bestStart = double.negativeInfinity;
    int? first;
    var firstStart = double.infinity;
    for (final (index, child) in positionedChildren()) {
      final start = child.offset.alongAxis(axis) + origin;
      if (start < firstStart) {
        firstStart = start;
        first = index;
      }
      if (start <= scrollOffset && (best == null || start > bestStart)) {
        best = index;
        bestStart = start;
      }
    }
    return math.min(count - 1, best ?? first ?? 0);
  }

  // ------------------------------------------------------------- the gap

  /// Takes the item [handle] stands for out of the flow, visually.
  ///
  /// Called from the draggable's own `onDragStarted`, which runs after the
  /// feedback has been inserted, so the one layout pass a drag costs has
  /// already been paid by the time anything here writes a matrix.
  void _startReorder(_Reorder3dHandle handle) {
    final session = handle.session;
    if (session == null) return;
    final index = _indexOf(handle) ?? handle.buildIndex;
    _dragIndex = index;
    _insertIndex = index;
    _gapExtent = _strideOf(index);
    _slideFrom.clear();
    _slideT = 1.0;
    // The session's own end listener rather than the draggable's `onDragEnd`,
    // because a caller who reorders its data from [onReorder] may dispose the
    // dragged item inside the drop — and a disposed draggable never reports
    // its end to anyone.
    session.addEndListener(_endReorder);
    _applyDrag();
  }

  void _endReorder() {
    if (_dragIndex == null) return;
    _stopSlide();
    _dragIndex = null;
    _slideFrom.clear();
    _slideT = 1.0;
    // A surface torn down under a live reorder disposes this list before it
    // disposes the item that owns the session, so the end of the drag can
    // arrive here after there is nothing left to put back.
    if (_disposed) return;
    for (final (_, child) in positionedChildren()) {
      child.nodeOffset = Offset3d.zero;
    }
    // The hidden item has to be shown again, and what an item's visibility
    // should be is a question only the window can answer. A layout at the end
    // of a drag is free: the feedback is coming out of the overlay on this
    // same frame, which is a layout pass either way.
    markNeedsLayout();
  }

  /// The room the dragged item takes out of the flow: its extent plus the
  /// spacing that follows it.
  double _strideOf(int index) {
    if (!hasSliverConstraints) return 0.0;
    final axis = sliverConstraints.axis;
    for (final (i, child) in positionedChildren()) {
      if (i != index || !child.hasSize) continue;
      return child.size.alongAxis(axis) + itemSpacing;
    }
    return 0.0;
  }

  int? _indexOf(Layout3d child) {
    for (final (index, candidate) in positionedChildren()) {
      if (identical(candidate, child)) return index;
    }
    return null;
  }

  /// Where item [index] has to sit while the gap is at [_insertIndex].
  ///
  /// Everything between the item's own slot and the slot it would land in
  /// moves one place; everything outside that run stays where layout put it.
  double _shiftOf(int index, int drag) {
    if (index > drag && index <= _insertIndex) return -_gapExtent;
    if (index < drag && index >= _insertIndex) return _gapExtent;
    return 0.0;
  }

  void _moveGapTo(int index) {
    if (index == _insertIndex || _dragIndex == null) return;
    if (!hasSliverConstraints) return;
    final axis = sliverConstraints.axis;
    _slideFrom
      ..clear()
      ..addEntries(<MapEntry<int, double>>[
        for (final (i, child) in positionedChildren())
          MapEntry<int, double>(i, child.nodeOffset.alongAxis(axis)),
      ]);
    _insertIndex = index;
    if (gapDuration <= Duration.zero) {
      _slideT = 1.0;
      _applyDrag();
      return;
    }
    _slideT = 0.0;
    _applyDrag();
    _startSlide();
  }

  /// Writes the hidden item and every item's offset. One matrix each.
  void _applyDrag() {
    final drag = _dragIndex;
    if (drag == null || !hasSliverConstraints) return;
    final axis = sliverConstraints.axis;
    final t = gapCurve.transform(_slideT);
    for (final (index, child) in positionedChildren()) {
      if (index == drag) {
        child.node.visible = false;
        child.nodeOffset = Offset3d.zero;
        continue;
      }
      final to = _shiftOf(index, drag);
      final from = _slideFrom[index] ?? to;
      child.nodeOffset = Offset3d.along(axis, from + (to - from) * t);
    }
  }

  void _startSlide() {
    _stopSlide();
    final provider = vsync;
    final ticker = _slideTicker = provider == null
        ? Ticker(_tickSlide, debugLabel: 'SliverReorderableList3d gap')
        : provider.createTicker(_tickSlide);
    ticker.start();
  }

  void _tickSlide(Duration elapsed) {
    _slideT = (elapsed.inMicroseconds / gapDuration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    _applyDrag();
    if (_slideT >= 1.0) _stopSlide();
  }

  void _stopSlide() {
    final ticker = _slideTicker;
    _slideTicker = null;
    ticker
      ?..stop(canceled: true)
      ..dispose();
  }

  // ------------------------------------------------------------- the list

  Layout3d _wrap(Layout3d item, int index) => _Reorder3dHandle(
    list: this,
    buildIndex: index,
    startMode: _startMode,
    child: item,
  );

  /// Answers a ray on its own account while a reorder is live.
  ///
  /// A list is not a target as a rule — a ray through the gap between two
  /// items passes through — but the gap a reorder opens is precisely a place
  /// where there is no item to hit, and it is the one place the pointer
  /// spends most of its time. Without this the list would stop hearing about
  /// the drag exactly where it matters most.
  @override
  bool hitTestSelf(Offset3d position) => _dragIndex != null;

  /// Keeps the dragged item alive even when the window has left it behind.
  ///
  /// Disposing it would dispose the [Draggable3d] wrapped around it, which
  /// cancels the session it owns, which ends the drag — from the viewer's
  /// point of view the card would vanish mid-flight. So the released range is
  /// widened to reach the dragged index. The run in between is kept as well,
  /// which is the price of the mixin releasing a contiguous range; it only
  /// grows once autoscroll can carry a drag far from where it started.
  @override
  void releaseOutside(int first, int last) {
    final index = _dragIndex;
    if (index == null) {
      super.releaseOutside(first, last);
      return;
    }
    super.releaseOutside(math.min(first, index), math.max(last, index));
  }

  @override
  void performSliverLayout() {
    super.performSliverLayout();
    // The pass above wrote every item's visibility from the window, which
    // would have shown the dragged item again, and any item built during the
    // drag has no offset yet. Both are one matrix write.
    _applyDrag();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _stopSlide();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IntProperty('dragIndex', _dragIndex, defaultValue: null));
    properties.add(IntProperty('insertIndex', insertIndex, defaultValue: null));
  }
}

/// What an item of a [SliverReorderableList3d] carries while it is in flight.
///
/// Private on purpose. It identifies the list rather than the item, so that a
/// session outlives the box it was picked up from — the list holds the index
/// itself — and so that no [DragTarget3d] of the caller's can be handed a
/// reorder it has no way to interpret. The one exception is
/// `DragTarget3d<Object>`, which accepts everything and always did.
class _Reorder3dPayload {
  const _Reorder3dPayload(this.list);

  final SliverReorderableList3d list;

  @override
  String toString() => 'reorder(${list.node.name})';
}

/// One item of a [SliverReorderableList3d], wrapped so it can be picked up.
///
/// A plain [Draggable3d] with the list's own token as its payload: the drag
/// recognizer, the arena competition, the overlay-hosted feedback, the single
/// disposal path and the node-tier tracking are all inherited rather than
/// written a second time.
class _Reorder3dHandle extends Draggable3d<Object> {
  // The payload has to be built from `list`, and an explicit super call rules
  // out super parameters.
  // ignore: use_super_parameters
  _Reorder3dHandle({
    required this.list,
    required this.buildIndex,
    required Drag3dStartMode startMode,
    required Layout3d child,
  }) : super(
         startMode: startMode,
         child: child,
         data: _Reorder3dPayload(list),
         // The slot an item lands in does not exist until the caller has
         // reordered its data and the list has been laid out again, so there
         // is nowhere to fly the feedback to. It is taken away at the drop.
         dropDuration: Duration.zero,
       ) {
    feedbackBuilder = _buildFeedback;
    onDragStarted = () => list._startReorder(this);
  }

  final SliverReorderableList3d list;

  /// The index this item was built for.
  ///
  /// A fallback for the moment the drag begins, when the item is certainly
  /// still in the list; [SliverReorderableList3d._indexOf] is the truth.
  final int buildIndex;

  Layout3d _buildFeedback(Drag3dSession session) {
    final index = list._indexOf(this) ?? buildIndex;
    final builder = list.feedbackBuilder ?? list._rawBuilder;
    return builder(index);
  }
}
