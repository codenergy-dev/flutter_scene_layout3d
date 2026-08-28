import 'dart:math' as math;

import '../clip.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import '../layout_pass.dart';
import '../scroll/scroll_controller.dart';
import '../scroll/scrollable.dart';
import 'sliver.dart';
import 'sliver_constraints.dart';

/// A scrolling window over a sequence of slivers, the 3D analogue of
/// [CustomScrollView] and the viewport inside it.
///
/// This is what the sliver protocol is for. A `ListView3d` is one list on one
/// scroll position; a custom scroll view puts several sections on one
/// position, so a header, a grid and a list scroll together as a single
/// surface, and each section is asked only about the part of the window it
/// can see.
///
/// ```dart
/// CustomScrollView3d(
///   controller: scroll,
///   slivers: [
///     SliverToBoxAdapter3d(child: NodeBox3d(content: title)),
///     SliverGrid3d(gridDelegate: ..., children: thumbnails),
///     SliverList3d.builder(itemCount: 500, itemBuilder: buildRow),
///   ],
/// )
/// ```
///
/// It is also what [ListView3d] and [GridView3d] are underneath, each over a
/// single sliver; see [BoxScrollView3d].
///
/// The window must be bounded across the scroll axis, which is what the
/// slivers are given to span. Along the scroll axis it need not be: with no
/// edge to fill, the view shrink-wraps to however long its slivers came out,
/// the way Flutter's `ShrinkWrappingViewport` does.
class CustomScrollView3d extends MultiChildLayout3d<ParentData3d>
    with Layout3dLayoutPassMixin, Scroll3dHolderMixin {
  /// Creates a viewport over [slivers].
  CustomScrollView3d({
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    double cacheExtent = 0.0,
    List<Sliver3d> slivers = const <Sliver3d>[],
    super.name,
  }) : _axis = scrollDirection,
       _cacheExtent = cacheExtent,
       assert(cacheExtent >= 0.0),
       super(children: slivers) {
    initController(controller);
  }

  /// How many times the viewport will redo its layout for a sliver asking to
  /// move the scroll offset before giving up, matching Flutter's limit.
  static const int _maxLayoutCycles = 10;

  Axis3d _axis;

  /// The axis the viewport scrolls along.
  Axis3d get scrollDirection => _axis;

  @override
  Axis3d get scrollAxis => _axis;

  set scrollDirection(Axis3d value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  double _cacheExtent;

  /// How far beyond each end of the window slivers are asked to stay alive.
  double get cacheExtent => _cacheExtent;

  set cacheExtent(double value) {
    if (_cacheExtent == value) return;
    assert(value >= 0.0);
    _cacheExtent = value;
    markNeedsLayout();
  }

  /// Rejects a child that is not a [Sliver3d], where the caller can still see
  /// what it did.
  ///
  /// The constructor is typed, but [add], [insert] and [syncChildren] come
  /// from the child-list mixin and take any [Layout3d], and the declarative
  /// layer hands over plain widgets. Without this the mistake surfaces as a
  /// cast failure in the middle of [performLayout], naming neither the child
  /// nor the fix.
  @override
  void setupParentData(Layout3d child) {
    assert(
      child is Sliver3d,
      '$runtimeType takes slivers, but was given a '
      '${child.runtimeType}. Wrap an ordinary box in a SliverToBoxAdapter3d '
      '(SceneSliverToBoxAdapter3d in the declarative layer) to give it its '
      'turn in the viewport.',
    );
    super.setupParentData(child);
  }

  /// The slivers in this viewport, in scroll order.
  List<Sliver3d> get slivers =>
      List<Sliver3d>.unmodifiable(heldChildren.cast<Sliver3d>());

  /// Replaces the sliver list, adopting what is new and dropping what is gone.
  void syncSlivers(List<Sliver3d> slivers) => syncChildren(slivers);

  /// Opaque across the whole window, so a drag that starts between two
  /// sections still scrolls the viewport.
  @override
  bool hitTestSelf(Offset3d position) => true;

  /// Tests slivers in scroll order, first one first, which is the reverse of
  /// what a [MultiChildLayout3d] does by default.
  ///
  /// A viewport's children do not sit side by side the way a `Stack3d`'s do:
  /// the leading ones are in *front*. A pinned header holds the leading edge
  /// while the list slides underneath it, so the header is what the viewer
  /// sees there and the header is what a ray aimed there must find, even
  /// though the row behind it is still a laid-out box at the same place.
  /// Flutter's viewport orders its children the same way and for the same
  /// reason — `childrenInHitTestOrder` is the reverse of a paint order that
  /// draws the first sliver last.
  @override
  bool hitTestChildren(HitTestResult3d result, {required Ray3d ray}) {
    for (final child in heldChildren) {
      if (hitTestChild(result, child, ray: ray)) return true;
    }
    return false;
  }

  /// How far into each sliver, from its own leading edge, the content is
  /// covered by a sliver that holds its place in front of it.
  ///
  /// Written by the layout pass and read by [clipRegionForChild]. Keyed by
  /// child rather than kept in parent data because it is a property of one
  /// pass over a list that is otherwise plain [ParentData3d]; a sliver that
  /// is not in here is not covered by anything.
  final Map<Layout3d, double> _obstructedTo = <Layout3d, double>{};

  /// The clip a sliver inherits, cut at the trailing edge of whatever pinned
  /// sliver is sitting on top of it.
  ///
  /// This is the half of a persistent header that two dimensions get for
  /// free. In Flutter a pinned bar simply paints over the list and the list
  /// is clipped to the viewport, so a row half under the bar shows its bottom
  /// half and no more. Nothing paints here, so the row is geometry that
  /// really is there, in front of nothing, and without a clip it draws
  /// straight through the bar.
  ///
  /// One plane is enough for it: the band is bounded on one side, at the
  /// point along the scroll axis where the bar stops. Whole-node culling
  /// cannot express it (the row is half in), and a clip box cannot either (a
  /// box is six planes and would also cut the row off at the far edge of the
  /// window, which is a different decision this viewport has not made). What
  /// a descendant does with the plane is the descendant's business: a
  /// [BoxDecoration3d] hands it to its shader, and a leaf holding an
  /// application's own material ignores it.
  @override
  Clip3dRegion clipRegionForChild(Layout3d child) {
    final base = super.clipRegionForChild(child);
    final obstructed = _obstructedTo[child];
    if (obstructed == null || obstructed <= 0.0) return base;
    // In the child's own frame, so no shift: the band is measured from the
    // child's leading edge, and `super` has already moved the inherited
    // region there.
    return base.intersect(
      Clip3dRegion(<ClipPlane3d>[
        ClipPlane3d(Offset3d.along(_axis, 1.0), -obstructed),
      ]),
    );
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  void performLayout() => runLayoutPass(_performViewportLayout);

  void _performViewportLayout() {
    final axis = _axis;
    final (crossAxis, depthAxis) = axis.others;
    assert(
      constraints.hasBoundedAlong(crossAxis),
      '$runtimeType needs a bounded extent along $crossAxis, which is what it '
      'gives its slivers to span.',
    );
    // With no edge along the scroll axis there is no window to fill, so the
    // view shrink-wraps instead: the slivers are offered an endless one and
    // the view comes out as long as they filled, which is what Flutter's
    // `ShrinkWrappingViewport` does for a `shrinkWrap: true` scroll view.
    final bounded = constraints.hasBoundedAlong(axis);
    final windowExtent = bounded ? constraints.maxAlong(axis) : double.infinity;
    final crossExtent = constraints.hasBoundedAlong(crossAxis)
        ? constraints.maxAlong(crossAxis)
        : 0.0;
    final depthExtent = constraints.maxAlong(depthAxis);

    Size3d sizeFor(double mainExtent) => constraints.constrain(
      Size3d.zero
          .withAxis(axis, mainExtent)
          .withAxis(crossAxis, crossExtent)
          .withAxis(depthAxis, depthExtent.isFinite ? depthExtent : 0.0),
    );

    // A size to fall back on, so that a view whose slivers never settle is
    // still a laid-out view. The pass below replaces it.
    size = sizeFor(bounded ? windowExtent : 0.0);

    var cycles = 0;
    while (true) {
      final total = _layoutSliverSequence(
        scrollOffset: controller.offset,
        mainExtent: windowExtent,
        crossExtent: crossExtent,
        depthExtent: depthExtent,
      );
      if (total.correction != null) {
        controller.correctBy(total.correction!);
      } else {
        size = sizeFor(bounded ? windowExtent : total.scrollExtent);
        final mainExtent = size.alongAxis(axis);
        final before = controller.offset;
        controller.applyViewportMetrics(
          maxScrollExtent: math.max(0.0, total.scrollExtent - mainExtent),
          viewportExtent: mainExtent,
          contentExtent: total.scrollExtent,
          unitsPerLogicalPixel: metrics.unitsPerLogicalPixel,
        );
        // Reporting the metrics can pull the offset back into range, and
        // then the pass that just ran was laid out at the wrong place.
        if (controller.offset == before) return;
      }
      cycles++;
      assert(
        cycles < _maxLayoutCycles,
        '$runtimeType gave up after $_maxLayoutCycles layout passes: a '
        'sliver keeps asking to move the scroll offset. A sliver that '
        'reports a scrollOffsetCorrection must settle once the viewport has '
        'applied it.',
      );
      if (cycles >= _maxLayoutCycles) return;
    }
  }

  /// Lays out every sliver in turn, and reports the total scroll extent, or
  /// the correction the first sliver to ask for one wants.
  ({double scrollExtent, double? correction}) _layoutSliverSequence({
    required double scrollOffset,
    required double mainExtent,
    required double crossExtent,
    required double depthExtent,
  }) {
    final axis = _axis;
    _obstructedTo.clear();
    // What is left of the window as the slivers eat into it, in the same
    // bookkeeping Flutter's viewport keeps.
    var remainingScroll = scrollOffset;
    var layoutOffset = 0.0;
    // How far down the window anything laid out so far still reaches. It runs
    // ahead of [layoutOffset] exactly when a sliver holds its place — a
    // pinned header whose layout extent has shrunk to nothing but which is
    // still sitting on the leading edge — and the gap between the two is the
    // `overlap` the next sliver is told about.
    var maxPaintOffset = 0.0;
    var precedingScrollExtent = 0.0;
    var cacheOrigin = math.max(-_cacheExtent, -scrollOffset);
    var remainingCache =
        mainExtent +
        2 * _cacheExtent -
        math.max(0.0, _cacheExtent - scrollOffset);

    for (final child in heldChildren) {
      final sliver = child as Sliver3d;
      final sliverScrollOffset = math.max(0.0, remainingScroll);
      final correctedCacheOrigin = math.max(cacheOrigin, -sliverScrollOffset);
      final cacheCorrection = cacheOrigin - correctedCacheOrigin;

      sliver.layoutSliver(
        SliverConstraints3d(
          axis: axis,
          scrollOffset: sliverScrollOffset,
          precedingScrollExtent: precedingScrollExtent,
          remainingPaintExtent: math.max(0.0, mainExtent - layoutOffset),
          crossAxisExtent: crossExtent,
          depthExtent: depthExtent,
          viewportMainAxisExtent: mainExtent,
          remainingCacheExtent: math.max(0.0, remainingCache + cacheCorrection),
          cacheOrigin: correctedCacheOrigin,
          overlap: math.max(0.0, maxPaintOffset - layoutOffset),
          userScrollDirection: controller.userScrollDirection,
        ),
      );

      final geometry = sliver.geometry;
      if (geometry.scrollOffsetCorrection != null) {
        return (scrollExtent: 0.0, correction: geometry.scrollOffsetCorrection);
      }

      // Where the sliver's visible part actually sits, which is where it was
      // laid out unless it asked to be somewhere else. A pinned header uses
      // the difference to stay on the leading edge while the offset that
      // positions everything after it keeps advancing.
      final paintOffset = layoutOffset + geometry.paintOrigin;

      // A sliver that has nothing in the window still needs somewhere to be:
      // park it where its leading edge would fall, so what the cache keeps
      // alive is in the right place when it scrolls back in.
      final placement = geometry.visible
          ? paintOffset
          : -sliverScrollOffset + layoutOffset;
      sliver.place(Offset3d.along(axis, placement));
      sliver.node.visible = geometry.visible;
      // What of this sliver is underneath something that came before it,
      // measured from its own leading edge; see [clipRegionForChild].
      if (geometry.visible && maxPaintOffset > placement) {
        _obstructedTo[sliver] = maxPaintOffset - placement;
      }

      maxPaintOffset = math.max(
        maxPaintOffset,
        paintOffset + geometry.paintExtent,
      );
      remainingScroll -= geometry.scrollExtent;
      precedingScrollExtent += geometry.scrollExtent;
      layoutOffset += geometry.layoutExtent;
      if (geometry.cacheExtent != 0.0) {
        remainingCache -= geometry.cacheExtent - cacheCorrection;
        cacheOrigin = math.min(
          correctedCacheOrigin + geometry.cacheExtent,
          0.0,
        );
      }
    }

    return (scrollExtent: precedingScrollExtent, correction: null);
  }
}
