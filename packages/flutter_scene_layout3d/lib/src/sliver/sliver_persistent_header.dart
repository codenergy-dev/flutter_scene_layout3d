import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DoubleProperty, FlagProperty;

import '../geometry/offset3d.dart';
import '../layout3d.dart';
import '../layout_pass.dart';
import '../scroll/scroll_controller.dart';
import 'sliver.dart';
import 'sliver_constraints.dart';

/// What a [SliverPersistentHeader3d] shows, and how far it may shrink, the 3D
/// analogue of [SliverPersistentHeaderDelegate].
///
/// Two numbers and a build. [maxExtent] is the header at rest, [minExtent] is
/// the header collapsed, and [build] is asked for the content at a given
/// [shrinkOffset] — how far, in scroll units, the header has been squeezed
/// from its maximum toward its minimum. A bar that only shrinks reads the
/// offset and ignores it; a bar that fades a title, scales a picture, or
/// swaps a large title for a small one reads it and does something.
///
/// **The header owns what this builds.** [build] runs on every layout the
/// header does, which while scrolling is every frame, and a delegate that
/// returns a fresh subtree each time will be building and disposing geometry
/// at frame rate. That is why the ordinary shape is to keep one subtree in
/// the delegate, mutate it, and return the same instance: the header adopts a
/// returned layout only when it is not the one it already holds, and disposes
/// the one it drops. Returning a layout the caller still holds a reference to
/// and intends to use later is therefore a mistake.
///
/// ```dart
/// class _Bar extends SliverPersistentHeader3dDelegate {
///   _Bar(this._panel, this._label);
///
///   final DecoratedBox3d _panel;
///   final Text3d _label;
///
///   @override
///   double get minExtent => 0.5;
///
///   @override
///   double get maxExtent => 2.0;
///
///   @override
///   Layout3d build(double shrinkOffset, {required bool overlapsContent}) {
///     // One subtree, told what the scroll position did to it.
///     _label.scale = 1.0 - shrinkOffset / (maxExtent - minExtent) * 0.5;
///     return _panel;
///   }
///
///   @override
///   bool shouldRebuild(_Bar old) => old._panel != _panel;
/// }
/// ```
abstract class SliverPersistentHeader3dDelegate {
  /// Allows subclasses to be const.
  const SliverPersistentHeader3dDelegate();

  /// The extent of the header when it has shrunk as far as it will go.
  ///
  /// A pinned header never goes below this, which is why a pinned bar with a
  /// [minExtent] of zero disappears rather than pins.
  double get minExtent;

  /// The extent of the header before anything has scrolled past it.
  ///
  /// Must be at least [minExtent]. Both are along the viewport's scroll axis
  /// and in layout units, so a delegate stating a size in logical pixels
  /// converts through [Layout3d.metrics] — a header knows its own metrics
  /// before it builds, and [SliverPersistentHeader3d.metrics] is the same
  /// object.
  double get maxExtent;

  /// The header's content, squeezed by [shrinkOffset].
  ///
  /// [shrinkOffset] runs from zero at rest to `maxExtent - minExtent` when
  /// fully collapsed. [overlapsContent] is true when the header is sitting on
  /// top of content that has scrolled underneath it, which is the cue for a
  /// bar to raise its elevation the way Material does.
  Layout3d build(double shrinkOffset, {required bool overlapsContent});

  /// Whether a header holding [oldDelegate] must throw its content away and
  /// ask this one instead.
  ///
  /// Called when a delegate is swapped for another of the same type, exactly
  /// as Flutter calls it. Answering false keeps the built subtree; answering
  /// true drops it, which disposes it.
  bool shouldRebuild(covariant SliverPersistentHeader3dDelegate oldDelegate);
}

/// A sliver whose child stays at the leading edge, shrinking as the content
/// scrolls past it, the 3D analogue of [SliverPersistentHeader].
///
/// The sliver `SliverAppBar` is built on, and the first one in this package
/// whose paint position is not where the viewport laid it out. Three
/// behaviours, from the two flags:
///
///  * Neither: the header shrinks from `maxExtent` to `minExtent` as the
///    content scrolls, then scrolls away with it.
///  * [pinned]: it shrinks the same way, and then stays, occupying
///    `minExtent` of the leading edge for as long as the viewport is
///    scrolled. Everything after it is laid out as though it were not there
///    — that is what [SliverGeometry3d.layoutExtent] going to zero means —
///    so the content slides underneath.
///  * [floating]: it comes back as soon as the viewer scrolls backwards,
///    without waiting for the scroll offset to reach the top. With [pinned]
///    as well, it is both: never smaller than `minExtent`, and expanding on
///    the way back.
///
/// **What is different here is what "underneath" means.** In two dimensions a
/// pinned bar simply paints over the rows and the viewport clips them; here
/// the rows are geometry that is really there, in front of nothing, and left
/// alone they draw straight through the bar. Two mechanisms answer that, and
/// they compose:
///
///  * [lift] moves the header's *geometry* toward the viewer, so content
///    passes behind it rather than through it. This is the honest answer in a
///    scene, it costs nothing, and for an opaque bar spanning the cross axis
///    it gives exactly the 2D picture. It is written to
///    [ParentData3d.sceneOffset], so the header's box does not move: layout
///    and hit testing are untouched, the same trade `Stack3d.depthStep`
///    makes.
///  * `CustomScrollView3d` publishes a clip plane at the trailing edge of
///    whatever this header is obstructing, which is what cuts a row *in half*
///    at the bar's edge. That reaches the content through
///    [Layout3d.clipRegion], and a material that reads clip planes (a
///    [BoxDecoration3d], today) honours it; one that does not is still
///    behind the bar rather than through it, because of [lift].
///
/// Neither is free of the other: the lift alone leaves a row visible past the
/// bar's silhouette, and the clip alone leaves a shader that ignores planes
/// interpenetrating the bar.
class SliverPersistentHeader3d extends Sliver3d
    with Layout3dWithChildMixin, Layout3dLayoutPassMixin {
  /// Creates a header showing what [delegate] builds.
  SliverPersistentHeader3d({
    required SliverPersistentHeader3dDelegate delegate,
    bool pinned = false,
    bool floating = false,
    double? lift,
    super.name,
  }) : _delegate = delegate,
       _pinned = pinned,
       _floating = floating,
       _lift = lift;

  SliverPersistentHeader3dDelegate _delegate;

  /// What the header shows, and how far it shrinks.
  SliverPersistentHeader3dDelegate get delegate => _delegate;

  set delegate(SliverPersistentHeader3dDelegate value) {
    if (identical(_delegate, value)) return;
    final old = _delegate;
    _delegate = value;
    if (value.runtimeType != old.runtimeType || value.shouldRebuild(old)) {
      _dropChild();
    }
    markNeedsLayout();
  }

  bool _pinned;

  /// Whether the header stays at the leading edge once it has collapsed.
  bool get pinned => _pinned;

  set pinned(bool value) {
    if (_pinned == value) return;
    _pinned = value;
    markNeedsLayout();
  }

  bool _floating;

  /// Whether the header comes back as soon as the viewer scrolls backwards.
  bool get floating => _floating;

  set floating(bool value) {
    if (_floating == value) return;
    _floating = value;
    _effectiveScrollOffset = null;
    _lastActualScrollOffset = null;
    markNeedsLayout();
  }

  double? _lift;

  /// How far toward the viewer the header's geometry is pulled while it is
  /// covering content, or null for one logical pixel.
  ///
  /// Null rather than zero by default because a pinned header that does not
  /// stand in front of what it covers is not pinned in any sense a viewer
  /// would recognise: it is a bar with a list drawn through it. One logical
  /// pixel — read from [Layout3d.metrics], so it is the same distance on any
  /// scale — is enough to separate them in the depth buffer without making
  /// the bar look like it is floating off the surface. Set a larger value for
  /// a bar that should visibly hover, or zero for one that must stay in the
  /// plane because something else (a clip the content honours, an opaque
  /// backdrop) already keeps them apart.
  double? get lift => _lift;

  set lift(double? value) {
    if (_lift == value) return;
    _lift = value;
    markNeedsLayout();
  }

  /// [lift] with its default resolved against the tree's unit contract.
  double get effectiveLift => _lift ?? metrics.dp(1.0);

  /// Where the child sits relative to this sliver's leading edge, along the
  /// scroll axis. Never positive: a header that has run out of room slides
  /// off the leading edge rather than shrinking below [minExtent].
  double _childPosition = 0.0;

  /// The scroll offset the header behaves as though it were at.
  ///
  /// Only a floating header has one that differs from the real offset: it is
  /// dragged back toward zero as the viewer scrolls backwards, which is how
  /// the bar comes in without the list having reached the top. Null until the
  /// first layout.
  double? _effectiveScrollOffset;

  /// The real scroll offset at the previous layout, so the next one can tell
  /// which way the viewer went.
  double? _lastActualScrollOffset;

  /// How much of the window this header is currently occupying that the
  /// layout gave to something else.
  ///
  /// Zero for a header that is where the viewport put it. It is what decides
  /// whether [lift] is applied: a header is only in front of anything when
  /// its paint extent has outrun its layout extent.
  double get obstructedExtent =>
      math.max(0.0, geometry.paintExtent - geometry.layoutExtent);

  @override
  void performSliverLayout() => runLayoutPass(_layoutHeader);

  void _layoutHeader() {
    final constraints = sliverConstraints;
    final maxExtent = _delegate.maxExtent;
    final minExtent = _delegate.minExtent;
    assert(
      minExtent >= 0.0 && maxExtent >= minExtent,
      '$runtimeType has a delegate whose maxExtent ($maxExtent) is below its '
      'minExtent ($minExtent). A header shrinks from the first toward the '
      'second, so the first is the larger of the two.',
    );

    final scrollOffset = constraints.scrollOffset;
    final effectiveScrollOffset = _floating
        ? _floatingScrollOffset(
            scrollOffset,
            maxExtent,
            constraints.userScrollDirection,
          )
        : scrollOffset;
    _effectiveScrollOffset = effectiveScrollOffset;
    _lastActualScrollOffset = scrollOffset;

    // A floating header that has been dragged back in front of the content is
    // overlapping it; a pinned one is overlapping whatever a pinned header
    // before it left covered. Both are the cue a Material bar raises its
    // elevation on.
    final overlapsContent = _floating
        ? effectiveScrollOffset < scrollOffset
        : (_pinned && constraints.overlap > 0.0);

    final childExtent = _layoutChild(
      constraints,
      shrinkOffset: math.min(effectiveScrollOffset, maxExtent),
      minExtent: minExtent,
      maxExtent: maxExtent,
      overlapsContent: overlapsContent,
    );

    if (_pinned && _floating) {
      _updateFloatingPinnedGeometry(
        constraints,
        minExtent: minExtent,
        maxExtent: maxExtent,
      );
    } else if (_pinned) {
      _updatePinnedGeometry(
        constraints,
        minExtent: minExtent,
        maxExtent: maxExtent,
        childExtent: childExtent,
      );
    } else {
      _updateScrollingGeometry(
        constraints,
        maxExtent: maxExtent,
        effectiveScrollOffset: effectiveScrollOffset,
        childExtent: childExtent,
      );
    }

    final child = this.child;
    if (child != null) {
      child.place(Offset3d.along(constraints.axis, _childPosition));
      child.node.visible = geometry.visible;
    }
    _applyLift(obstructedExtent > 0.0 ? effectiveLift : 0.0);
  }

  /// The offset a floating header behaves as though it were at.
  ///
  /// Flutter's arithmetic, with its one missing term now supplied. There, a
  /// floating header expands only while the viewer is *scrolling* forward, so
  /// a bouncing fling that overshoots the end and springs backwards does not
  /// pull the bar in; that test reads `SliverConstraints.userScrollDirection`,
  /// which this package's scroll position did not carry until it grew a
  /// physics to have a direction at all.
  ///
  /// It does now, and this reads it — but only to *refuse*. A backwards
  /// movement while the viewer is scrolling the other way (a spring settling
  /// past the end) leaves the header where it is; anything else, including a
  /// programmatic `jumpTo` or an `animateTo` backwards, brings it back by the
  /// same amount, which is what a viewer expects of a menu that scrolls the
  /// list to a chosen item.
  double _floatingScrollOffset(
    double scrollOffset,
    double maxExtent,
    ScrollDirection3d direction,
  ) {
    var effective = _effectiveScrollOffset;
    final last = _lastActualScrollOffset;
    if (last == null || effective == null) return scrollOffset;
    if (direction == ScrollDirection3d.reverse) return scrollOffset;
    if (scrollOffset >= last && effective >= maxExtent) return scrollOffset;
    final delta = last - scrollOffset;
    // Snapping back from far down the list starts the bar at its full height
    // rather than unrolling it from wherever the offset happened to be.
    if (effective > maxExtent) effective = maxExtent;
    return (effective - delta).clamp(0.0, scrollOffset);
  }

  /// Asks the delegate for the header's content, adopts it if it is not what
  /// is already here, lays it out, and reports its extent along the scroll
  /// axis.
  double _layoutChild(
    SliverConstraints3d constraints, {
    required double shrinkOffset,
    required double minExtent,
    required double maxExtent,
    required bool overlapsContent,
  }) {
    final built = _delegate.build(
      shrinkOffset,
      overlapsContent: overlapsContent,
    );
    if (!identical(built, child)) {
      _dropChild();
      child = built;
    }
    // Loose, not tight, exactly as Flutter lays a header's child out: the
    // delegate says how much room there is, and a child that wants less of it
    // gets less. A pinned bar whose content came out shorter than `minExtent`
    // pins to what the content actually is.
    final extent = math.max(minExtent, maxExtent - shrinkOffset);
    built.layout(
      constraints.asBoxConstraints(maxExtent: extent),
      parentUsesSize: true,
    );
    return built.size.alongAxis(constraints.axis);
  }

  /// A header that shrinks and then leaves.
  void _updateScrollingGeometry(
    SliverConstraints3d constraints, {
    required double maxExtent,
    required double effectiveScrollOffset,
    required double childExtent,
  }) {
    final paintExtent = maxExtent - effectiveScrollOffset;
    final layoutExtent = maxExtent - constraints.scrollOffset;
    geometry = SliverGeometry3d(
      scrollExtent: maxExtent,
      // Never positive: a floating header that is early may hang back over
      // the content it is about to cover, but a scrolling header never asks
      // to be pushed further down the window than it was laid out.
      paintOrigin: math.min(constraints.overlap, 0.0),
      paintExtent: paintExtent.clamp(0.0, constraints.remainingPaintExtent),
      layoutExtent: layoutExtent.clamp(0.0, constraints.remainingPaintExtent),
      maxPaintExtent: maxExtent,
      cacheExtent: constraints.cachePortion(from: 0.0, to: maxExtent),
    );
    // Once the header has collapsed to its minimum, what is left of it is
    // pushed off the leading edge instead, so the last of it scrolls away
    // rather than sitting there. Measured against the unclamped extent, so a
    // header running out of window slides rather than stalls.
    _childPosition = math.min(0.0, paintExtent - childExtent);
  }

  /// A header that shrinks and then stays.
  void _updatePinnedGeometry(
    SliverConstraints3d constraints, {
    required double minExtent,
    required double maxExtent,
    required double childExtent,
  }) {
    // The room a pinned header before this one is already sitting on is room
    // this one cannot have, which is how two pinned bars stack rather than
    // land on each other.
    final remaining = math.max(
      0.0,
      constraints.remainingPaintExtent - constraints.overlap,
    );
    final layoutExtent = (maxExtent - constraints.scrollOffset).clamp(
      0.0,
      remaining,
    );
    geometry = SliverGeometry3d(
      scrollExtent: maxExtent,
      // The whole of pinning, in one number: the viewport places this sliver
      // at the layout offset of everything before it, and the offset that
      // positions what comes *after* keeps advancing through `layoutExtent`.
      // The header therefore stays where it is while the list moves under it.
      paintOrigin: constraints.overlap,
      paintExtent: math.min(childExtent, remaining),
      layoutExtent: layoutExtent,
      maxPaintExtent: maxExtent,
      maxScrollObstructionExtent: minExtent,
      // A pinned header is alive whenever the viewport is, so it takes the
      // cache reaching back before the window along with the room it holds.
      cacheExtent: layoutExtent > 0.0
          ? -constraints.cacheOrigin + layoutExtent
          : layoutExtent,
    );
    _childPosition = 0.0;
  }

  /// A header that is both: it never shrinks below its minimum, and it
  /// expands again on the way back.
  void _updateFloatingPinnedGeometry(
    SliverConstraints3d constraints, {
    required double minExtent,
    required double maxExtent,
  }) {
    final minAllowed = math.min(minExtent, constraints.remainingPaintExtent);
    final paintExtent = (maxExtent - _effectiveScrollOffset!).clamp(
      minAllowed,
      constraints.remainingPaintExtent,
    );
    geometry = SliverGeometry3d(
      scrollExtent: maxExtent,
      paintOrigin: math.min(constraints.overlap, 0.0),
      paintExtent: paintExtent,
      layoutExtent: (maxExtent - constraints.scrollOffset).clamp(
        0.0,
        paintExtent,
      ),
      maxPaintExtent: maxExtent,
      maxScrollObstructionExtent: minExtent,
      cacheExtent: constraints.cachePortion(from: 0.0, to: maxExtent),
    );
    _childPosition = 0.0;
  }

  /// Pulls this sliver's node [distance] toward the viewer without moving its
  /// box.
  ///
  /// Written to the parent data the viewport owns, which is legitimate only
  /// because [ParentData3d.sceneOffset] is exactly that: a nudge to the scene
  /// node that layout and hit testing never see. The viewport re-applies the
  /// transform when it places this sliver, right after this runs, so writing
  /// it here is enough.
  void _applyLift(double distance) {
    final data = parentData;
    if (data == null) return;
    // Toward the viewer is negative depth, the same direction
    // `Stack3d.depthStep` separates its children in.
    final wanted = distance == 0.0 ? Offset3d.zero : Offset3d(0, 0, -distance);
    if (data.sceneOffset == wanted) return;
    data.sceneOffset = wanted;
    applyNodeTransform();
  }

  /// Drops the built content and disposes it.
  ///
  /// The header owns what the delegate built; see
  /// [SliverPersistentHeader3dDelegate].
  void _dropChild() {
    final old = child;
    if (old == null) return;
    child = null;
    old.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(FlagProperty('pinned', value: pinned, ifTrue: 'pinned'));
    properties.add(
      FlagProperty('floating', value: floating, ifTrue: 'floating'),
    );
    properties.add(DoubleProperty('lift', lift, defaultValue: null));
    properties.add(DoubleProperty('obstructedExtent', obstructedExtent));
  }
}
