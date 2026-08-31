import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, IntProperty;
import 'package:flutter/scheduler.dart' show TickerProvider;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../built_children.dart';
import '../geometry/offset3d.dart';
import '../input/draggable.dart';
import '../layout3d.dart';
import '../sliver/sliver_reorderable_list.dart';
import 'box_scroll_view.dart';
import 'scroll_controller.dart';

/// A scrolling list whose items can be dragged into a different order.
///
/// The 3D analogue of Flutter's `ReorderableListView`, and a [ListView3d] in
/// every other respect: the window, the scroll position and the placement are
/// the list's, unchanged. Pick an item up, carry it, and the items it passes
/// slide aside to show where it would land.
///
/// ```dart
/// ReorderableList3d(
///   itemCount: tracks.length,
///   itemExtent: 0.4,
///   itemBuilder: (index) => trackRow(tracks[index]),
///   onReorder: (oldIndex, newIndex) {
///     tracks.insert(newIndex, tracks.removeAt(oldIndex));
///     list.refresh();
///   },
/// )
/// ```
///
/// [onReorder]'s `newIndex` is **where the item ends up** — apply it with one
/// `insert` after one `removeAt`, as above. Flutter's `ReorderableListView`
/// reports an index measured before the item is taken out and leaves the
/// caller to decrement it; see [Reorder3dCallback] for why this does not.
///
/// A list is a viewport over one [SliverReorderableList3d], the way
/// [ListView3d] is a viewport over one `SliverList3d`, so the whole of the
/// reorder — the hidden item, the node-tier gap, the insert index — lives in
/// the sliver and is available to a `CustomScrollView3d` that wants a
/// reorderable section between other slivers.
///
/// ## What it costs while an item is in flight
///
/// One matrix write per visible item, and nothing else. The dragged item is
/// not taken out of the child list: it is hidden where it stands, so its
/// extent *is* the gap, and its neighbours are slid aside on the node tier.
/// The index-to-child map never changes until the drop, so the lazy machinery
/// is untouched and nothing reaches the relayout path. See
/// [SliverReorderableList3d] for the whole of that argument.
///
/// ## The items are built, not listed
///
/// There is no constructor over an explicit child list, unlike [ListView3d].
/// [onReorder] hands back a pair of indices into the caller's own data and
/// expects the next build to reflect them, so the list has to be a function
/// of that data to mean anything: give it an [itemCount] and an
/// [itemBuilder], and call [refresh] when the data changes.
///
/// ## Picking an item up
///
/// A long press, by default. An ordinary drag on an item scrolls the list —
/// the two compete in the gesture arena and the scroll claims the pointer on
/// travel, long before the delay is up — which is what leaves a touch list
/// usable. Set [startMode] to [Drag3dStartMode.immediate] for a list of drag
/// handles, or for a list that does not scroll.
class ReorderableList3d extends BoxScrollView3d<SliverReorderableList3d> {
  /// Creates a reorderable list that builds its items on demand.
  ///
  /// The sliver has to be built before it can be handed up, and an explicit
  /// super call rules out super parameters, the same way [ListView3d] does.
  // ignore: use_super_parameters
  ReorderableList3d({
    required int itemCount,
    required Layout3dItemBuilder itemBuilder,
    required Reorder3dCallback onReorder,
    Layout3dItemBuilder? feedbackBuilder,
    Drag3dStartMode startMode = const Drag3dStartMode.longPress(),
    Duration gapDuration = const Duration(milliseconds: 200),
    Curve gapCurve = Curves.easeInOut,
    TickerProvider? vsync,
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    double spacing = 0.0,
    double? itemExtent,
    Layout3dPrototypeBuilder? prototypeItem,
    Layout3dContentExtentEstimator? contentExtentEstimator,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.center,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    double cacheExtent = 0.0,
    String? name,
  }) : super(
         sliver: SliverReorderableList3d(
           itemCount: itemCount,
           itemBuilder: itemBuilder,
           onReorder: onReorder,
           feedbackBuilder: feedbackBuilder,
           startMode: startMode,
           gapDuration: gapDuration,
           gapCurve: gapCurve,
           vsync: vsync,
           spacing: spacing,
           itemExtent: itemExtent,
           prototypeItem: prototypeItem,
           contentExtentEstimator: contentExtentEstimator,
           crossAxisAlignment: crossAxisAlignment,
           depthAxisAlignment: depthAxisAlignment,
         ),
         scrollDirection: scrollDirection,
         controller: controller,
         cacheExtent: cacheExtent,
         name: name,
       );

  /// Called once, at the drop, when an item ended somewhere else.
  Reorder3dCallback get onReorder => sliver.onReorder;

  set onReorder(Reorder3dCallback value) => sliver.onReorder = value;

  /// Builds what is carried under the pointer, given the item's index.
  ///
  /// Null means a second copy of the item itself.
  Layout3dItemBuilder? get feedbackBuilder => sliver.feedbackBuilder;

  set feedbackBuilder(Layout3dItemBuilder? value) =>
      sliver.feedbackBuilder = value;

  /// When a press on an item becomes a reorder drag.
  Drag3dStartMode get startMode => sliver.startMode;

  set startMode(Drag3dStartMode value) => sliver.startMode = value;

  /// How long the items take to slide aside when the gap moves.
  Duration get gapDuration => sliver.gapDuration;

  set gapDuration(Duration value) => sliver.gapDuration = value;

  /// The curve the items follow as they slide aside.
  Curve get gapCurve => sliver.gapCurve;

  set gapCurve(Curve value) => sliver.gapCurve = value;

  /// The index of the item being dragged, or null when nothing is.
  int? get dragIndex => sliver.dragIndex;

  /// Where the dragged item would land if it were let go now.
  int? get insertIndex => sliver.insertIndex;

  /// Whether an item of this list is in flight.
  bool get isReordering => sliver.isReordering;

  /// The gap between adjacent items.
  double get spacing => sliver.spacing;

  set spacing(double value) => sliver.spacing = value;

  /// A fixed extent for every item along the scroll axis.
  double? get itemExtent => sliver.itemExtent;

  set itemExtent(double? value) => sliver.itemExtent = value;

  /// An item built once and measured, standing for the extent of them all.
  Layout3dPrototypeBuilder? get prototypeItem => sliver.prototypeItem;

  set prototypeItem(Layout3dPrototypeBuilder? value) =>
      sliver.prototypeItem = value;

  /// The total extent along the scroll axis, when the caller knows it.
  Layout3dContentExtentEstimator? get contentExtentEstimator =>
      sliver.contentExtentEstimator;

  set contentExtentEstimator(Layout3dContentExtentEstimator? value) =>
      sliver.contentExtentEstimator = value;

  /// How items are positioned on the first cross axis.
  CrossAxisAlignment3d get crossAxisAlignment => sliver.crossAxisAlignment;

  set crossAxisAlignment(CrossAxisAlignment3d value) =>
      sliver.crossAxisAlignment = value;

  /// How items are positioned on the second cross axis.
  CrossAxisAlignment3d get depthAxisAlignment => sliver.depthAxisAlignment;

  set depthAxisAlignment(CrossAxisAlignment3d value) =>
      sliver.depthAxisAlignment = value;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IntProperty('dragIndex', dragIndex, defaultValue: null));
    properties.add(IntProperty('insertIndex', insertIndex, defaultValue: null));
  }
}
