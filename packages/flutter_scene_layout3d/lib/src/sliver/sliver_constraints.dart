import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';

/// What a viewport tells a sliver about the room it is scrolling through, the
/// 3D analogue of [SliverConstraints].
///
/// This is the second layout protocol in the package, and it exists because
/// the box protocol cannot answer the question a long list asks. A box is
/// handed a size and gives one back; a sliver is handed a *window* — how far
/// it has already scrolled past, how much of the viewport is still unfilled —
/// and reports how it filled it. That is what lets several sections share one
/// scroll position, and what lets a section a mile long describe itself
/// without laying out a mile of children.
///
/// A word on the names: [remainingPaintExtent] and its friends in
/// [SliverGeometry3d] keep Flutter's spelling even though nothing here paints.
/// The quantity is the same one — how much of the visible window is at stake —
/// and porting sliver code is easier when the words match. Read "paint" as
/// "the part of the window the viewer can see".
class SliverConstraints3d {
  /// Creates the constraints for one sliver.
  const SliverConstraints3d({
    required this.axis,
    required this.scrollOffset,
    required this.precedingScrollExtent,
    required this.remainingPaintExtent,
    required this.crossAxisExtent,
    required this.depthExtent,
    required this.viewportMainAxisExtent,
    required this.remainingCacheExtent,
    required this.cacheOrigin,
  }) : assert(scrollOffset >= 0.0),
       assert(cacheOrigin <= 0.0);

  /// The axis the viewport scrolls along.
  final Axis3d axis;

  /// How much of this sliver has already scrolled past the leading edge.
  ///
  /// Zero while the sliver's start is still inside the window; once it has
  /// scrolled off, this is how far off.
  final double scrollOffset;

  /// The scroll extent of every sliver before this one.
  final double precedingScrollExtent;

  /// How much of the visible window is still unfilled.
  final double remainingPaintExtent;

  /// The room across the scroll axis.
  final double crossAxisExtent;

  /// The room on the axis that is neither the scroll axis nor the cross axis.
  final double depthExtent;

  /// The extent of the whole window along the scroll axis.
  final double viewportMainAxisExtent;

  /// How much room is left in the window plus the cache around it.
  final double remainingCacheExtent;

  /// How far before [scrollOffset] the cache reaches, never above zero.
  final double cacheOrigin;

  /// The two axes that are not [axis], in canonical order.
  (Axis3d, Axis3d) get crossAxes => axis.others;

  /// Box constraints for a child that should span the cross axes and take
  /// `[minExtent, maxExtent]` along the scroll axis.
  ///
  /// The 3D analogue of [SliverConstraints.asBoxConstraints]. The cross axis
  /// is tight, because a sliver's children fill its width the way a Flutter
  /// list item does; the depth axis is loose, so a shallow model is not
  /// stretched into the plane's whole thickness.
  Constraints3d asBoxConstraints({
    double minExtent = 0.0,
    double maxExtent = double.infinity,
    bool stretchDepth = false,
  }) {
    final (crossAxis, depthAxis) = crossAxes;
    return const Constraints3d()
        .withAxis(axis, min: minExtent, max: maxExtent)
        .withAxis(crossAxis, min: crossAxisExtent, max: crossAxisExtent)
        .withAxis(
          depthAxis,
          min: stretchDepth ? depthExtent : 0.0,
          max: depthExtent,
        );
  }

  /// How much of `[from, to]`, in this sliver's own scroll coordinates, lands
  /// in the visible window.
  ///
  /// The 3D form of Flutter's `calculatePaintOffset`, and the arithmetic every
  /// sliver does to decide how much of a child is showing.
  double paintPortion({required double from, required double to}) {
    final start = scrollOffset;
    final end = scrollOffset + remainingPaintExtent;
    return to.clamp(start, end) - from.clamp(start, end);
  }

  /// How much of `[from, to]` lands in the cache around the window.
  ///
  /// The 3D form of Flutter's `calculateCacheOffset`. A sliver reports this
  /// as its `cacheExtent` so the viewport can tell how much of the cache is
  /// left for whatever comes next.
  double cachePortion({required double from, required double to}) {
    final start = scrollOffset + cacheOrigin;
    final end = scrollOffset + remainingCacheExtent;
    return to.clamp(start, end) - from.clamp(start, end);
  }

  /// A copy with the given fields replaced.
  SliverConstraints3d copyWith({
    Axis3d? axis,
    double? scrollOffset,
    double? precedingScrollExtent,
    double? remainingPaintExtent,
    double? crossAxisExtent,
    double? depthExtent,
    double? viewportMainAxisExtent,
    double? remainingCacheExtent,
    double? cacheOrigin,
  }) => SliverConstraints3d(
    axis: axis ?? this.axis,
    scrollOffset: scrollOffset ?? this.scrollOffset,
    precedingScrollExtent: precedingScrollExtent ?? this.precedingScrollExtent,
    remainingPaintExtent: remainingPaintExtent ?? this.remainingPaintExtent,
    crossAxisExtent: crossAxisExtent ?? this.crossAxisExtent,
    depthExtent: depthExtent ?? this.depthExtent,
    viewportMainAxisExtent:
        viewportMainAxisExtent ?? this.viewportMainAxisExtent,
    remainingCacheExtent: remainingCacheExtent ?? this.remainingCacheExtent,
    cacheOrigin: cacheOrigin ?? this.cacheOrigin,
  );

  @override
  bool operator ==(Object other) =>
      other is SliverConstraints3d &&
      other.axis == axis &&
      other.scrollOffset == scrollOffset &&
      other.precedingScrollExtent == precedingScrollExtent &&
      other.remainingPaintExtent == remainingPaintExtent &&
      other.crossAxisExtent == crossAxisExtent &&
      other.depthExtent == depthExtent &&
      other.viewportMainAxisExtent == viewportMainAxisExtent &&
      other.remainingCacheExtent == remainingCacheExtent &&
      other.cacheOrigin == cacheOrigin;

  @override
  int get hashCode => Object.hash(
    axis,
    scrollOffset,
    precedingScrollExtent,
    remainingPaintExtent,
    crossAxisExtent,
    depthExtent,
    viewportMainAxisExtent,
    remainingCacheExtent,
    cacheOrigin,
  );

  @override
  String toString() =>
      'SliverConstraints3d(${axis.name}, scrollOffset: $scrollOffset, '
      'remainingPaint: $remainingPaintExtent, cross: $crossAxisExtent)';
}

/// What a sliver reports back about the window it filled, the 3D analogue of
/// [SliverGeometry].
///
/// The pair to [SliverConstraints3d]: constraints describe the window, this
/// describes what happened in it. [scrollExtent] is how long the sliver is in
/// scroll terms, which is what the viewport adds up to know how far the whole
/// thing scrolls; [paintExtent] is how much of the visible window it took,
/// which is what the viewport subtracts as it moves on to the next one.
class SliverGeometry3d {
  /// Creates a report of one sliver's layout.
  const SliverGeometry3d({
    this.scrollExtent = 0.0,
    this.paintExtent = 0.0,
    double? layoutExtent,
    double? maxPaintExtent,
    double? hitTestExtent,
    bool? visible,
    double? cacheExtent,
    this.scrollOffsetCorrection,
  }) : assert(scrollExtent >= 0.0),
       assert(paintExtent >= 0.0),
       assert(
         scrollOffsetCorrection != 0.0,
         'A scrollOffsetCorrection of zero asks the viewport to redo its '
         'layout for no change; leave it null instead.',
       ),
       _layoutExtent = layoutExtent,
       _maxPaintExtent = maxPaintExtent,
       _hitTestExtent = hitTestExtent,
       _visible = visible,
       _cacheExtent = cacheExtent;

  /// A sliver that filled nothing and takes up no scroll room.
  static const SliverGeometry3d zero = SliverGeometry3d();

  /// How long this sliver is in scroll terms.
  final double scrollExtent;

  /// How much of the visible window this sliver took.
  final double paintExtent;

  final double? _layoutExtent;

  /// How far the next sliver starts beyond this one's leading edge.
  ///
  /// Defaults to [paintExtent], and differs only for slivers that hold their
  /// place while their content moves.
  double get layoutExtent => _layoutExtent ?? paintExtent;

  final double? _maxPaintExtent;

  /// The most of the window this sliver could take, were it given room.
  double get maxPaintExtent => _maxPaintExtent ?? paintExtent;

  final double? _hitTestExtent;

  /// How much of this sliver answers hit tests. Defaults to [paintExtent].
  double get hitTestExtent => _hitTestExtent ?? paintExtent;

  final bool? _visible;

  /// Whether this sliver put anything in the window.
  bool get visible => _visible ?? paintExtent > 0.0;

  final double? _cacheExtent;

  /// How much of the cache this sliver consumed. Defaults to [layoutExtent].
  double get cacheExtent => _cacheExtent ?? layoutExtent;

  /// A shift the viewport must apply to the scroll offset before laying out
  /// again, or null when the layout stands.
  ///
  /// A sliver asks for this when it discovers, mid-layout, that its content
  /// is not where the offset assumed — a list that measured its items and
  /// found them shorter than the estimate that got it here. The viewport
  /// applies it and starts over, exactly as Flutter's does.
  final double? scrollOffsetCorrection;

  /// A copy with the given fields replaced.
  SliverGeometry3d copyWith({
    double? scrollExtent,
    double? paintExtent,
    double? layoutExtent,
    double? maxPaintExtent,
    double? hitTestExtent,
    bool? visible,
    double? cacheExtent,
    double? scrollOffsetCorrection,
  }) => SliverGeometry3d(
    scrollExtent: scrollExtent ?? this.scrollExtent,
    paintExtent: paintExtent ?? this.paintExtent,
    layoutExtent: layoutExtent ?? _layoutExtent,
    maxPaintExtent: maxPaintExtent ?? _maxPaintExtent,
    hitTestExtent: hitTestExtent ?? _hitTestExtent,
    visible: visible ?? _visible,
    cacheExtent: cacheExtent ?? _cacheExtent,
    scrollOffsetCorrection:
        scrollOffsetCorrection ?? this.scrollOffsetCorrection,
  );

  @override
  String toString() =>
      'SliverGeometry3d(scroll: $scrollExtent, paint: $paintExtent'
      '${scrollOffsetCorrection == null ? '' : ', correction: '
                '$scrollOffsetCorrection'})';
}
