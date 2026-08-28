import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/scheduler.dart' show TickerProvider;

import '../boxes/flex.dart' show CrossAxisAlignment3d;
import '../geometry/offset3d.dart';
import '../layout3d.dart';
import '../sliver/sliver_list.dart';
import 'box_scroll_view.dart';
import 'scroll_controller.dart';
import 'scroll_physics.dart';

/// A scrolling view whose children are each as big as the window, the 3D
/// analogue of [PageView].
///
/// A page view is a [ListView3d] with two things decided for it: every item
/// is exactly the extent of the window along the scroll axis, and the
/// position comes to rest on an item boundary rather than wherever friction
/// left it. Both are stated here rather than left to the caller, because a
/// page view where either is not true is a list.
///
/// The snapping is [PageScroll3dPhysics], set on the position this view
/// creates for itself. Hand it a [Scroll3dController] of your own and the
/// physics is yours to choose — which is the way to get pages that bounce at
/// the ends, or a stride that is not a whole page.
///
/// ```dart
/// PageView3d(
///   children: [intro, permissions, done],
/// )
/// ```
///
/// The item extent is written by this view on every pass, from the room it
/// was given, so a page view follows a surface that resizes. It therefore
/// needs a bounded extent along its scroll axis; there is no such thing as a
/// page of an unbounded window, and it says so.
///
/// Flutter's `viewportFraction` — pages narrower than the window, so the
/// neighbours peek in — is deliberately not here. It is a `ListView3d` with
/// an `itemExtent` and a `PageScroll3dPhysics(pageExtent: ...)`, which is the
/// same arrangement without a second meaning for the word page, and it leaves
/// this class with exactly one.
class PageView3d extends BoxScrollView3d<SliverList3d> {
  /// Creates a page view over an explicit set of pages.
  PageView3d({
    Axis3d scrollDirection = Axis3d.horizontal,
    Scroll3dController? controller,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.stretch,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    List<Layout3d> children = const <Layout3d>[],
    String? name,
  }) : this._(
         SliverList3d(
           crossAxisAlignment: crossAxisAlignment,
           depthAxisAlignment: depthAxisAlignment,
           children: children,
         ),
         scrollDirection: scrollDirection,
         controller: controller,
         name: name,
       );

  /// Creates a page view that builds its pages as it reaches them.
  ///
  /// The usual shape: a page view holds few pages at a time, and each of them
  /// is a whole screen of content, so building them on demand matters more
  /// here than in a list of rows.
  PageView3d.builder({
    required int itemCount,
    required Layout3dItemBuilder itemBuilder,
    Axis3d scrollDirection = Axis3d.horizontal,
    Scroll3dController? controller,
    CrossAxisAlignment3d crossAxisAlignment = CrossAxisAlignment3d.stretch,
    CrossAxisAlignment3d depthAxisAlignment = CrossAxisAlignment3d.center,
    String? name,
  }) : this._(
         SliverList3d.builder(
           itemCount: itemCount,
           itemBuilder: itemBuilder,
           crossAxisAlignment: crossAxisAlignment,
           depthAxisAlignment: depthAxisAlignment,
         ),
         scrollDirection: scrollDirection,
         controller: controller,
         name: name,
       );

  // ignore: use_super_parameters
  PageView3d._(
    SliverList3d sliver, {
    required Axis3d scrollDirection,
    required Scroll3dController? controller,
    required String? name,
  }) : super(
         sliver: sliver,
         scrollDirection: scrollDirection,
         controller: controller,
         name: name,
       ) {
    if (controller == null) this.controller.physics = PageScroll3dPhysics();
  }

  /// How pages are positioned on the first cross axis.
  ///
  /// Stretched by default, unlike a [ListView3d]: a page is a screenful, and
  /// a screenful that does not fill the window is a gap.
  CrossAxisAlignment3d get crossAxisAlignment => sliver.crossAxisAlignment;

  set crossAxisAlignment(CrossAxisAlignment3d value) =>
      sliver.crossAxisAlignment = value;

  /// How pages are positioned on the second cross axis.
  CrossAxisAlignment3d get depthAxisAlignment => sliver.depthAxisAlignment;

  set depthAxisAlignment(CrossAxisAlignment3d value) =>
      sliver.depthAxisAlignment = value;

  /// How far through the pages the position is, counted in pages.
  ///
  /// Fractional mid-drag, which is what a page indicator or a parallax
  /// background reads. Zero before the first layout, when there is no window
  /// extent to count against.
  double get page {
    final extent = pageExtent;
    if (extent <= 0.0) return 0.0;
    return controller.offset / extent;
  }

  /// The extent of one page, which is the window's own along the scroll axis.
  ///
  /// Zero until this view has been laid out.
  double get pageExtent => controller.viewportExtent;

  /// Jumps to [page] with no animation.
  void jumpToPage(int page) => controller.jumpTo(page * pageExtent);

  /// Animates to [page].
  ///
  /// A page view usually turns its pages by a flick, and this is the other
  /// way: a next button, a step in a flow, a tab bar above it.
  Future<void> animateToPage(
    int page, {
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
    TickerProvider? vsync,
  }) => controller.animateTo(
    page * pageExtent,
    duration: duration,
    curve: curve,
    vsync: vsync,
  );

  /// Swaps the position, and chooses the physics for one this view makes.
  ///
  /// A caller who brings a controller brings its physics with it, and this
  /// view leaves it alone; a caller who hands over null gets a fresh position
  /// that snaps, which is the same bargain the constructor makes.
  @override
  set controller(Scroll3dController? value) {
    super.controller = value;
    if (value == null) controller.physics = PageScroll3dPhysics();
  }

  @override
  void performLayout() {
    final axis = scrollDirection;
    assert(
      constraints.hasBoundedAlong(axis),
      'A PageView3d needs a bounded extent along $axis: a page is as long as '
      'the window, and an unbounded window has no length. Give it a size, or '
      'use a ListView3d if the content should simply be as long as it is.',
    );
    if (constraints.hasBoundedAlong(axis)) {
      // Written every pass, so a surface that resizes re-pages rather than
      // keeping the extent it was first laid out at. The sliver is about to
      // be laid out by the viewport below, so the dirt this raises is
      // resolved inside this very pass.
      final extent = constraints.maxAlong(axis);
      if (sliver.itemExtent != extent) sliver.itemExtent = extent;
    }
    super.performLayout();
  }
}
