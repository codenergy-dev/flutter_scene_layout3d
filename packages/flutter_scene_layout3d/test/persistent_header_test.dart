import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A box that takes every bit of room it is offered, the way a bar's
/// background does, and that answers a ray on its own account so a hit test
/// has something to land on.
class FillBox extends Layout3d {
  FillBox({super.name});

  /// How many times this box has been laid out.
  int layoutCount = 0;

  /// Whether the header disposed of it.
  bool disposed = false;

  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  void performLayout() {
    layoutCount++;
    size = constraints.constrain(constraints.biggest);
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// A delegate over one [FillBox], recording everything the header told it.
class ProbeHeader3dDelegate extends SliverPersistentHeader3dDelegate {
  ProbeHeader3dDelegate({
    this.minExtent = 2.0,
    this.maxExtent = 4.0,
    FillBox? content,
  }) : content = content ?? FillBox(name: 'header');

  @override
  final double minExtent;

  @override
  final double maxExtent;

  /// The one subtree this delegate keeps, which is the shape the dartdoc
  /// asks for: build hands the same instance back every time.
  final FillBox content;

  /// Every shrink offset this delegate has been built at, in order.
  final List<double> shrinkOffsets = <double>[];

  /// Whether the header said it was covering content, per build.
  final List<bool> overlaps = <bool>[];

  @override
  Layout3d build(double shrinkOffset, {required bool overlapsContent}) {
    shrinkOffsets.add(shrinkOffset);
    overlaps.add(overlapsContent);
    return content;
  }

  @override
  bool shouldRebuild(ProbeHeader3dDelegate oldDelegate) =>
      !identical(oldDelegate.content, content);
}

/// A sliver of a fixed length that keeps every window it was handed, so the
/// overlap the viewport computed can be read off it.
class RecordingSliver3d extends Sliver3d {
  RecordingSliver3d(this.extent, {super.name});

  final double extent;

  final List<SliverConstraints3d> windows = <SliverConstraints3d>[];

  SliverConstraints3d get window => windows.last;

  @override
  void performSliverLayout() {
    final constraints = sliverConstraints;
    windows.add(constraints);
    geometry = SliverGeometry3d(
      scrollExtent: extent,
      paintExtent: constraints.paintPortion(from: 0.0, to: extent),
      maxPaintExtent: extent,
      cacheExtent: constraints.cachePortion(from: 0.0, to: extent),
    );
  }
}

Layout3dSurface viewportOf(
  CustomScrollView3d view, {
  Size3d size = const Size3d(4, 10, 2),
}) => laidOut(view, constraints: Constraints3d.tight(size));

void main() {
  group('the protocol fields', () {
    test('overlap is zero unless a viewport says otherwise', () {
      const window = SliverConstraints3d(
        axis: Axis3d.vertical,
        scrollOffset: 0,
        precedingScrollExtent: 0,
        remainingPaintExtent: 10,
        crossAxisExtent: 4,
        depthExtent: 2,
        viewportMainAxisExtent: 10,
        remainingCacheExtent: 10,
        cacheOrigin: 0,
      );

      expect(window.overlap, 0);
      expect(window.copyWith(overlap: 3).overlap, 3);
      expect(window.copyWith(overlap: 3) == window, isFalse);
      expect(window.copyWith(overlap: 3).copyWith(overlap: 0), window);
    });

    test('a geometry paints where it was laid out unless it says so', () {
      const geometry = SliverGeometry3d(scrollExtent: 4, paintExtent: 4);

      expect(geometry.paintOrigin, 0);
      expect(geometry.maxScrollObstructionExtent, 0);
      expect(geometry.copyWith(paintOrigin: -2).paintOrigin, -2);
      expect(
        geometry
            .copyWith(maxScrollObstructionExtent: 2)
            .maxScrollObstructionExtent,
        2,
      );
    });
  });

  group('a header that scrolls away', () {
    test('shrinks to its minimum, then leaves with the content', () {
      final delegate = ProbeHeader3dDelegate();
      final header = SliverPersistentHeader3d(delegate: delegate);
      final view = CustomScrollView3d(slivers: [header, RecordingSliver3d(20)]);
      final surface = viewportOf(view);

      // At rest it is its whole self, and takes that much of the window.
      expect(header.geometry.scrollExtent, 4);
      expect(header.geometry.paintExtent, 4);
      expect(header.geometry.layoutExtent, 4);
      expect(header.geometry.maxPaintExtent, 4);
      expect(delegate.content.size.height, 4);

      // Halfway: squeezed to the minimum and sliding off, because two units
      // of content will not fit in the one unit of window it has left.
      view.controller.jumpTo(3);
      surface.flush();
      expect(header.geometry.paintExtent, 1);
      expect(header.geometry.layoutExtent, 1);
      expect(delegate.content.size.height, 2);
      expect(header.child!.offset, const Offset3d(0, -1, 0));

      // Past its own length there is nothing of it left.
      view.controller.jumpTo(5);
      surface.flush();
      expect(header.geometry.paintExtent, 0);
      expect(header.geometry.visible, isFalse);
    });

    test('tells the delegate how far it has been squeezed, and no further', () {
      final delegate = ProbeHeader3dDelegate();
      final header = SliverPersistentHeader3d(delegate: delegate);
      final view = CustomScrollView3d(slivers: [header, RecordingSliver3d(20)]);
      final surface = viewportOf(view);

      view.controller.jumpTo(3);
      surface.flush();
      view.controller.jumpTo(9);
      surface.flush();

      expect(delegate.shrinkOffsets, <double>[0, 3, 4]);
      // Nothing has scrolled under it: it is where the viewport put it.
      expect(delegate.overlaps, everyElement(isFalse));
    });

    test('obstructs nothing, so the sliver after it is not covered', () {
      final delegate = ProbeHeader3dDelegate();
      final header = SliverPersistentHeader3d(delegate: delegate);
      final next = RecordingSliver3d(20);
      final view = CustomScrollView3d(slivers: [header, next]);
      final surface = viewportOf(view);

      view.controller.jumpTo(3);
      surface.flush();

      expect(header.geometry.maxScrollObstructionExtent, 0);
      expect(next.window.overlap, 0);
      expect(next.clipRegion.isUnbounded, isTrue);
      expect(translationOf(header).z, 0);
    });
  });

  group('a pinned header', () {
    test('holds the leading edge while the content moves under it', () {
      final delegate = ProbeHeader3dDelegate();
      final header = SliverPersistentHeader3d(delegate: delegate, pinned: true);
      final next = RecordingSliver3d(20);
      final view = CustomScrollView3d(slivers: [header, next]);
      final surface = viewportOf(view);

      expect(header.offset, Offset3d.zero);
      expect(next.offset, const Offset3d(0, 4, 0));

      view.controller.jumpTo(3);
      surface.flush();
      // Collapsed to its minimum and still at the top; what it gave up is
      // layout extent, which is what the sliver after it moved by.
      expect(header.offset, Offset3d.zero);
      expect(header.geometry.paintExtent, 2);
      expect(header.geometry.layoutExtent, 1);
      expect(next.offset, const Offset3d(0, 1, 0));

      // Scrolled past its own length: it stays, and the content is under it.
      view.controller.jumpTo(6);
      surface.flush();
      expect(header.offset, Offset3d.zero);
      expect(header.geometry.paintExtent, 2);
      expect(header.geometry.layoutExtent, 0);
      expect(header.geometry.maxScrollObstructionExtent, 2);
      expect(next.offset, Offset3d.zero);
      expect(next.window.scrollOffset, 2);
    });

    test('the overlap it leaves reaches the sliver after it', () {
      final delegate = ProbeHeader3dDelegate();
      final header = SliverPersistentHeader3d(delegate: delegate, pinned: true);
      final next = RecordingSliver3d(20);
      final view = CustomScrollView3d(slivers: [header, next]);
      final surface = viewportOf(view);

      expect(next.window.overlap, 0);

      view.controller.jumpTo(3);
      surface.flush();
      expect(next.window.overlap, 1);

      view.controller.jumpTo(6);
      surface.flush();
      expect(next.window.overlap, 2);
    });

    test('two of them stack rather than land on each other', () {
      final first = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(),
        pinned: true,
      );
      final second = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(minExtent: 1, maxExtent: 2),
        pinned: true,
      );
      final next = RecordingSliver3d(20);
      final view = CustomScrollView3d(slivers: [first, second, next]);
      final surface = viewportOf(view);

      view.controller.jumpTo(6);
      surface.flush();

      // The first is on the edge, the second sits directly under it, and the
      // content is under both.
      expect(first.offset, Offset3d.zero);
      expect(first.geometry.paintExtent, 2);
      expect(second.offset, const Offset3d(0, 2, 0));
      expect(second.geometry.paintOrigin, 2);
      expect(second.geometry.paintExtent, 1);
      expect(next.offset, Offset3d.zero);
      expect(next.window.overlap, 3);
    });

    test('tells the delegate when content has gone under it', () {
      final delegate = ProbeHeader3dDelegate();
      final second = ProbeHeader3dDelegate(minExtent: 1, maxExtent: 2);
      final view = CustomScrollView3d(
        slivers: [
          SliverPersistentHeader3d(delegate: delegate, pinned: true),
          SliverPersistentHeader3d(delegate: second, pinned: true),
          RecordingSliver3d(20),
        ],
      );
      final surface = viewportOf(view);

      view.controller.jumpTo(6);
      surface.flush();

      // The leading bar covers nothing but the list; the second is sitting on
      // the band the first left, which is what `overlapsContent` reports.
      expect(delegate.overlaps.last, isFalse);
      expect(second.overlaps.last, isTrue);
    });
  });

  group('what keeps the content out of the bar', () {
    test('the header is lifted toward the viewer while it covers', () {
      final header = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(),
        pinned: true,
        lift: 0.5,
      );
      final view = CustomScrollView3d(slivers: [header, RecordingSliver3d(20)]);
      final surface = viewportOf(view);

      // Nothing is under it yet, so it stays in the plane.
      expect(translationOf(header), Offset3d.zero);

      view.controller.jumpTo(6);
      surface.flush();
      // The node moved toward the viewer; the box did not move at all.
      expect(translationOf(header), const Offset3d(0, 0, -0.5));
      expect(header.offset, Offset3d.zero);
      expect(header.size.height, 2);

      // And it goes back when the list scrolls home again.
      view.controller.jumpTo(0);
      surface.flush();
      expect(translationOf(header), Offset3d.zero);
    });

    test('the default lift is one logical pixel, and zero disables it', () {
      final lifted = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(),
        pinned: true,
      );
      final flat = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(minExtent: 1, maxExtent: 1),
        pinned: true,
        lift: 0,
      );
      final view = CustomScrollView3d(
        slivers: [lifted, flat, RecordingSliver3d(20)],
      );
      final surface = viewportOf(view);

      view.controller.jumpTo(6);
      surface.flush();

      expect(lifted.effectiveLift, Layout3dMetrics.standard.dp(1));
      // The node's transform is a float32 matrix, so the lift comes back a
      // hair off the double it went in as.
      expect(
        translationOf(lifted).z,
        closeTo(-Layout3dMetrics.standard.dp(1), 1e-9),
      );
      expect(translationOf(flat).z, 0);
    });

    test('the sliver under the bar is clipped at the bar\'s edge', () {
      final header = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(),
        pinned: true,
      );
      final next = RecordingSliver3d(20);
      final view = CustomScrollView3d(slivers: [header, next]);
      final surface = viewportOf(view);

      // Nothing is covered while the bar is at full height.
      expect(next.clipRegion.isUnbounded, isTrue);

      view.controller.jumpTo(6);
      surface.flush();

      final region = next.clipRegion;
      expect(region.planes, hasLength(1));
      // The band from the sliver's leading edge to the bar's trailing edge is
      // out; everything past it is in.
      expect(region.contains(const Offset3d(2, 1, 0)), isFalse);
      expect(region.contains(const Offset3d(2, 3, 0)), isTrue);
      // A row that is half under the bar is neither wholly out nor wholly in,
      // which is exactly why culling cannot do this job.
      expect(
        region.excludes(const Offset3d(0, 1, 0), const Size3d(4, 2, 1)),
        isFalse,
      );
      expect(
        region.containsBox(const Offset3d(0, 1, 0), const Size3d(4, 2, 1)),
        isFalse,
      );
      // And it is a plane block a material can take.
      expect(region.toPlaneBlock().take(4), <double>[0, 1, 0, -2]);
    });

    test('the clip follows a box down into the sliver it lands in', () {
      final content = FillBox(name: 'content');
      final adapter = SliverToBoxAdapter3d(child: content);
      final header = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(),
        pinned: true,
      );
      final view = CustomScrollView3d(slivers: [header, adapter]);
      final surface = viewportOf(view);

      view.controller.jumpTo(6);
      surface.flush();

      // The adapter is at the top of the window with two units of it under
      // the bar, and its child is pulled up by the two units of itself that
      // have already scrolled past, so in the child's own frame the covered
      // band runs to four.
      expect(content.offset, const Offset3d(0, -2, 0));
      expect(content.clipRegion.contains(const Offset3d(2, 3, 0)), isFalse);
      expect(content.clipRegion.contains(const Offset3d(2, 5, 0)), isTrue);
    });

    test('a ray at the bar finds the bar, not the row behind it', () {
      final delegate = ProbeHeader3dDelegate();
      final header = SliverPersistentHeader3d(delegate: delegate, pinned: true);
      final content = FillBox(name: 'content');
      final view = CustomScrollView3d(
        slivers: [
          header,
          SliverToBoxAdapter3d(child: content),
        ],
      );
      final surface = viewportOf(view);

      view.controller.jumpTo(6);
      surface.flush();

      // One unit down is inside both boxes; the bar is in front.
      expect(
        surface.hitTestAt(const Offset3d(2, 1, 1)).target,
        same(delegate.content),
      );
      // Below the bar there is only the content.
      expect(surface.hitTestAt(const Offset3d(2, 5, 1)).target, same(content));
    });

    test('a half-scrolled header answers only over what is left of it', () {
      final delegate = ProbeHeader3dDelegate();
      final header = SliverPersistentHeader3d(delegate: delegate);
      final content = FillBox(name: 'content');
      final view = CustomScrollView3d(
        slivers: [
          header,
          SliverToBoxAdapter3d(child: content),
        ],
      );
      final surface = viewportOf(view);

      view.controller.jumpTo(3);
      surface.flush();

      // One unit of the header is showing, and its hit test extent is that
      // unit: past it the ray goes through to the content, even though the
      // header's child is a two-unit box that has slid up behind it.
      expect(header.size.height, 1);
      expect(
        surface.hitTestAt(const Offset3d(2, 0.5, 1)).target,
        same(delegate.content),
      );
      expect(
        surface.hitTestAt(const Offset3d(2, 1.5, 1)).target,
        same(content),
      );
    });
  });

  group('a floating header', () {
    test('comes back as soon as the viewer scrolls the other way', () {
      final delegate = ProbeHeader3dDelegate();
      final header = SliverPersistentHeader3d(
        delegate: delegate,
        floating: true,
      );
      final next = RecordingSliver3d(20);
      final view = CustomScrollView3d(slivers: [header, next]);
      final surface = viewportOf(view);

      view.controller.jumpTo(8);
      surface.flush();
      expect(header.geometry.paintExtent, 0);
      expect(header.geometry.visible, isFalse);

      // One unit back up the list and one unit of the bar is showing, though
      // the scroll offset is still nowhere near the top.
      view.controller.jumpTo(7);
      surface.flush();
      expect(header.geometry.paintExtent, 1);
      expect(header.geometry.visible, isTrue);
      expect(delegate.overlaps.last, isTrue);

      view.controller.jumpTo(5);
      surface.flush();
      expect(header.geometry.paintExtent, 3);
    });

    test('floats over the content instead of pushing it down', () {
      final header = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(),
        floating: true,
      );
      final next = RecordingSliver3d(20);
      final view = CustomScrollView3d(slivers: [header, next]);
      final surface = viewportOf(view);

      view.controller.jumpTo(8);
      surface.flush();
      view.controller.jumpTo(7);
      surface.flush();

      // The bar is showing again, the content has not moved, and the scroll
      // position was left exactly where the viewer put it: a floating header
      // covers, it does not correct.
      expect(header.geometry.layoutExtent, 0);
      expect(next.offset, Offset3d.zero);
      expect(view.controller.offset, 7);
      expect(next.window.overlap, 1);
      expect(next.clipRegion.isUnbounded, isFalse);
    });

    test('pinned as well, it never shrinks past its minimum', () {
      final header = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(),
        pinned: true,
        floating: true,
      );
      final next = RecordingSliver3d(20);
      final view = CustomScrollView3d(slivers: [header, next]);
      final surface = viewportOf(view);

      view.controller.jumpTo(8);
      surface.flush();
      expect(header.geometry.paintExtent, 2);
      expect(header.geometry.maxScrollObstructionExtent, 2);

      // Coming back undoes the shrink before it undoes the collapse: the
      // first two units of scrolling back are the two the header gave up on
      // the way down, and it is still at its minimum when they are spent.
      view.controller.jumpTo(7);
      surface.flush();
      expect(header.geometry.paintExtent, 2);
      view.controller.jumpTo(6);
      surface.flush();
      expect(header.geometry.paintExtent, 2);
      view.controller.jumpTo(5);
      surface.flush();
      expect(header.geometry.paintExtent, 3);
      expect(header.offset, Offset3d.zero);
      expect(next.offset, Offset3d.zero);
    });
  });

  group('the delegate', () {
    test('is asked again only when it says the content must change', () {
      final first = ProbeHeader3dDelegate();
      final header = SliverPersistentHeader3d(delegate: first);
      final view = CustomScrollView3d(slivers: [header, RecordingSliver3d(20)]);
      final surface = viewportOf(view);
      expect(header.child, same(first.content));

      // A delegate holding the same subtree keeps it.
      final same_ = ProbeHeader3dDelegate(content: first.content);
      header.delegate = same_;
      surface.flush();
      expect(header.child, same(first.content));
      expect(first.content.disposed, isFalse);

      // One holding another does not, and the header disposes what it drops.
      final other = ProbeHeader3dDelegate();
      header.delegate = other;
      surface.flush();
      expect(header.child, same(other.content));
      expect(first.content.disposed, isTrue);
    });

    test('is not allowed a maximum below its minimum', () {
      final header = SliverPersistentHeader3d(
        delegate: ProbeHeader3dDelegate(minExtent: 4, maxExtent: 2),
      );
      final view = CustomScrollView3d(slivers: [header, RecordingSliver3d(20)]);

      expect(
        () => viewportOf(view),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            contains('minExtent'),
          ),
        ),
      );
    });
  });
}
