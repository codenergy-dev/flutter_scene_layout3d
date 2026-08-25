import 'dart:math' as math;

import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
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
/// The window must be bounded along the scroll axis and across it: a viewport
/// with no edges has no window to fill.
class CustomScrollView3d extends MultiChildLayout3d<ParentData3d>
    implements Scrollable3d {
  /// Creates a viewport over [slivers].
  CustomScrollView3d({
    Axis3d scrollDirection = Axis3d.vertical,
    Scroll3dController? controller,
    double cacheExtent = 0.0,
    List<Sliver3d> slivers = const <Sliver3d>[],
    super.name,
  }) : _axis = scrollDirection,
       _controller = controller ?? Scroll3dController(),
       _ownsController = controller == null,
       _cacheExtent = cacheExtent,
       assert(cacheExtent >= 0.0),
       super(children: slivers) {
    _controller.addListener(_handleScrollChanged);
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

  Scroll3dController _controller;
  bool _ownsController;

  /// The scroll position shared by every sliver in this viewport.
  @override
  Scroll3dController get controller => _controller;

  set controller(Scroll3dController value) {
    if (identical(_controller, value)) return;
    _controller.removeListener(_handleScrollChanged);
    // A controller supplied from outside belongs to whoever supplied it.
    if (_ownsController) _controller.dispose();
    _ownsController = false;
    _controller = value..addListener(_handleScrollChanged);
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

  /// The slivers in this viewport, in scroll order.
  List<Sliver3d> get slivers =>
      List<Sliver3d>.unmodifiable(children.cast<Sliver3d>());

  /// Replaces the sliver list, adopting what is new and dropping what is gone.
  void syncSlivers(List<Sliver3d> slivers) => syncChildren(slivers);

  bool _layingOut = false;

  void _handleScrollChanged() {
    if (_layingOut) return;
    markNeedsLayout();
  }

  @override
  void markNeedsLayout() {
    if (_layingOut) return;
    super.markNeedsLayout();
  }

  /// Opaque across the whole window, so a drag that starts between two
  /// sections still scrolls the viewport.
  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      noIntrinsicExtent(this, axis);

  @override
  void performLayout() {
    _layingOut = true;
    try {
      _performViewportLayout();
    } finally {
      _layingOut = false;
    }
  }

  void _performViewportLayout() {
    final axis = _axis;
    final (crossAxis, depthAxis) = axis.others;
    assert(
      constraints.hasBoundedAlong(axis),
      'CustomScrollView3d needs a bounded extent along $axis: a window with '
      'no edge has nothing for its slivers to fill.',
    );
    assert(
      constraints.hasBoundedAlong(crossAxis),
      'CustomScrollView3d needs a bounded extent along $crossAxis, which is '
      'what it gives its slivers to span.',
    );
    final mainExtent = constraints.hasBoundedAlong(axis)
        ? constraints.maxAlong(axis)
        : 0.0;
    final crossExtent = constraints.hasBoundedAlong(crossAxis)
        ? constraints.maxAlong(crossAxis)
        : 0.0;
    final depthExtent = constraints.maxAlong(depthAxis);

    size = constraints.constrain(
      Size3d.zero
          .withAxis(axis, mainExtent)
          .withAxis(crossAxis, crossExtent)
          .withAxis(depthAxis, depthExtent.isFinite ? depthExtent : 0.0),
    );

    var cycles = 0;
    while (true) {
      final total = _layoutSliverSequence(
        scrollOffset: _controller.offset,
        mainExtent: mainExtent,
        crossExtent: crossExtent,
        depthExtent: depthExtent,
      );
      if (total.correction != null) {
        _controller.correctBy(total.correction!);
      } else {
        final before = _controller.offset;
        _controller.applyViewportMetrics(
          maxScrollExtent: math.max(0.0, total.scrollExtent - mainExtent),
          viewportExtent: mainExtent,
          contentExtent: total.scrollExtent,
        );
        // Reporting the metrics can pull the offset back into range, and
        // then the pass that just ran was laid out at the wrong place.
        if (_controller.offset == before) return;
      }
      cycles++;
      assert(
        cycles < _maxLayoutCycles,
        'CustomScrollView3d gave up after $_maxLayoutCycles layout passes: a '
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
    // What is left of the window as the slivers eat into it, in the same
    // bookkeeping Flutter's viewport keeps.
    var remainingScroll = scrollOffset;
    var layoutOffset = 0.0;
    var precedingScrollExtent = 0.0;
    var cacheOrigin = math.max(-_cacheExtent, -scrollOffset);
    var remainingCache =
        mainExtent +
        2 * _cacheExtent -
        math.max(0.0, _cacheExtent - scrollOffset);

    for (final child in children) {
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
        ),
      );

      final geometry = sliver.geometry;
      if (geometry.scrollOffsetCorrection != null) {
        return (scrollExtent: 0.0, correction: geometry.scrollOffsetCorrection);
      }

      // A sliver that has nothing in the window still needs somewhere to be:
      // park it where its leading edge would fall, so what the cache keeps
      // alive is in the right place when it scrolls back in.
      sliver.place(
        Offset3d.along(
          axis,
          geometry.visible ? layoutOffset : -sliverScrollOffset + layoutOffset,
        ),
      );
      sliver.node.visible = geometry.visible;

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

  @override
  void dispose() {
    _controller.removeListener(_handleScrollChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}
