import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        FlagProperty,
        IntProperty,
        IterableProperty,
        protected;

import '../built_children.dart';
import '../layout3d.dart';
import '../sliver/custom_scroll_view.dart';
import '../sliver/sliver.dart';

/// A scrolling view over a single sliver, the 3D analogue of [BoxScrollView].
///
/// Flutter's `ListView` is not a viewport of its own kind: it is a
/// `ScrollView`, the same one `CustomScrollView` is, whose slivers happen to
/// be a single `SliverList` chosen on the caller's behalf. There is no
/// `RenderListView` — a list's items are placed by `RenderSliverList` inside a
/// `RenderViewport` — and this is that shape. [ListView3d] and [GridView3d]
/// *are* viewports, over one [SliverList3d] and one [SliverGrid3d], so where
/// an item goes is decided in one place rather than two.
///
/// **The child list still means the items.** A caller who writes
/// `ListView3d(children: models)` means those models, and asking the list for
/// its [children] gives them back. So [children], [childCount], [childAt],
/// [add], [insert], [remove], [removeAll] and [syncChildren] are forwarded to
/// the [sliver] — as are [itemCount], [activeIndices], [isLazy] and
/// [refresh] — while the child this view holds and lays out is the sliver
/// itself. [visitChildren] and hit testing walk the tree as it really is, so
/// a ray reaches an item through the sliver, and the [Scrollable3d] it finds
/// on the way out is this view.
abstract class BoxScrollView3d<SliverType extends SliverMultiBoxAdaptor3d>
    extends CustomScrollView3d
    implements Layout3dBuiltChildrenHost {
  /// Creates a view over [sliver], which holds the children.
  BoxScrollView3d({
    required this.sliver,
    super.scrollDirection,
    super.controller,
    super.cacheExtent,
    super.name,
  }) {
    // Straight to the viewport's own child list, past the forwarding below:
    // this is the one child this view really holds, and [add] would send it
    // into itself.
    super.insert(sliver);
  }

  /// The one sliver in this view's window, which holds its children and
  /// decides where each of them goes.
  final SliverType sliver;

  /// The sliver, which is what actually holds the children.
  ///
  /// So that the declarative layer can hand a child manager to a
  /// `SceneListView3d.builder` without knowing that a list is a window with a
  /// sliver in it.
  @override
  Layout3dBuiltChildrenMixin get builtChildren => sliver;

  /// What this view calls its children in an assertion message: "items" for a
  /// list, "cells" for a grid.
  @protected
  String get itemNoun => 'items';

  /// Refuses an edit in this view's own name before forwarding it, so a
  /// caller who wrote `ListView3d.builder` is told about `ListView3d` rather
  /// than about the sliver inside it.
  void _assertNotBuilt(String method) {
    assert(
      !sliver.isLazy,
      builtChildEditRefused(view: this, method: method, itemNoun: itemNoun),
    );
  }

  // --------------------------------------------------- the children, forwarded

  @override
  List<Layout3d> get children => sliver.children;

  @override
  int get childCount => sliver.childCount;

  @override
  Layout3d childAt(int index) => sliver.childAt(index);

  @override
  void add(Layout3d child) => insert(child);

  @override
  void insert(Layout3d child, {int? index}) {
    _assertNotBuilt('insert');
    sliver.insert(child, index: index);
  }

  @override
  void remove(Layout3d child) {
    _assertNotBuilt('remove');
    sliver.remove(child);
  }

  @override
  void removeAll() {
    _assertNotBuilt('removeAll');
    sliver.removeAll();
  }

  @override
  void syncChildren(List<Layout3d> children) {
    _assertNotBuilt('syncChildren');
    sliver.syncChildren(children);
  }

  /// Refuses a sliver list: this view decides its own, and there is one.
  ///
  /// Inherited from the viewport, where it means "replace the sections".
  /// Here the child list is forwarded to the one sliver, so a caller who
  /// reached for this would be putting slivers *inside* a list of items.
  @override
  void syncSlivers(List<Sliver3d> slivers) {
    assert(
      false,
      'The slivers of a $runtimeType are its own: it holds exactly one, and '
      'its child list is the $itemNoun in that sliver. Use syncChildren for '
      'those, or a CustomScrollView3d if you want to decide the sections.',
    );
  }

  /// How many children this view holds: the child list for an explicit view,
  /// the count a builder was given for a lazy one.
  int get itemCount => sliver.itemCount;

  set itemCount(int value) {
    // Refused here as well as in the sliver, for the same reason the child
    // list edits above are: the caller wrote this class's name, not the
    // sliver's.
    assert(
      sliver.isLazy,
      explicitChildCountRefused(view: this, itemNoun: itemNoun),
    );
    sliver.itemCount = value;
  }

  /// Whether this view builds its children on demand.
  bool get isLazy => sliver.isLazy;

  /// The indices of the children currently built.
  Iterable<int> get activeIndices => sliver.activeIndices;

  /// Rebuilds every child, for when the data behind the builder changed.
  void refresh() => sliver.refresh();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IntProperty('itemCount', itemCount));
    properties.add(FlagProperty('isLazy', value: isLazy, ifTrue: 'lazy'));
    properties.add(
      IterableProperty<int>(
        'activeIndices',
        isLazy ? activeIndices : null,
        defaultValue: null,
      ),
    );
  }
}
