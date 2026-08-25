import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A sliver of a fixed length that reports what it was asked, so the
/// viewport's bookkeeping can be read off it directly.
class ProbeSliver3d extends Sliver3d {
  ProbeSliver3d(this.extent, {super.name});

  final double extent;

  /// Every window this sliver has been handed, in order.
  final List<SliverConstraints3d> windows = <SliverConstraints3d>[];

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

/// A sliver that asks the viewport to move the scroll offset once, the way a
/// section that discovers its content is elsewhere would.
class CorrectingSliver3d extends Sliver3d {
  CorrectingSliver3d(this.extent, this.correction, {super.name});

  final double extent;
  final double correction;
  int passes = 0;
  bool corrected = false;

  @override
  void performSliverLayout() {
    passes++;
    if (!corrected) {
      corrected = true;
      geometry = SliverGeometry3d(scrollOffsetCorrection: correction);
      return;
    }
    final constraints = sliverConstraints;
    geometry = SliverGeometry3d(
      scrollExtent: extent,
      paintExtent: constraints.paintPortion(from: 0.0, to: extent),
      maxPaintExtent: extent,
    );
  }
}

List<TestBox> items(int count, [Size3d size = const Size3d(1, 2, 1)]) =>
    List.generate(count, (index) => TestBox(size, name: 'item$index'));

Layout3dSurface viewportOf(
  CustomScrollView3d view, {
  Size3d size = const Size3d(4, 10, 2),
}) => laidOut(view, constraints: Constraints3d.tight(size));

void main() {
  group('the protocol values', () {
    const window = SliverConstraints3d(
      axis: Axis3d.vertical,
      scrollOffset: 10,
      precedingScrollExtent: 0,
      remainingPaintExtent: 20,
      crossAxisExtent: 4,
      depthExtent: 2,
      viewportMainAxisExtent: 20,
      remainingCacheExtent: 25,
      cacheOrigin: -5,
    );

    test('paintPortion measures the part inside the window', () {
      // The window covers 10..30 of this sliver's own scroll coordinates.
      expect(window.paintPortion(from: 0, to: 5), 0);
      expect(window.paintPortion(from: 0, to: 15), 5);
      expect(window.paintPortion(from: 12, to: 18), 6);
      expect(window.paintPortion(from: 0, to: 100), 20);
    });

    test('cachePortion reaches back before the window', () {
      // The cache covers 5..35, so content just above the window counts.
      expect(window.cachePortion(from: 0, to: 8), 3);
      expect(window.cachePortion(from: 0, to: 100), 30);
    });

    test('box constraints span the cross axis and free the depth', () {
      final box = window.asBoxConstraints(maxExtent: 3);

      expect(box.minHeight, 0);
      expect(box.maxHeight, 3);
      expect(box.minWidth, 4);
      expect(box.maxWidth, 4);
      expect(box.minDepth, 0);
      expect(box.maxDepth, 2);
      expect(window.asBoxConstraints(stretchDepth: true).minDepth, 2);
    });

    test('geometry fills in what it was not told', () {
      const geometry = SliverGeometry3d(scrollExtent: 10, paintExtent: 4);

      expect(geometry.layoutExtent, 4);
      expect(geometry.maxPaintExtent, 4);
      expect(geometry.hitTestExtent, 4);
      expect(geometry.cacheExtent, 4);
      expect(geometry.visible, isTrue);
      expect(SliverGeometry3d.zero.visible, isFalse);
    });
  });

  group('the viewport', () {
    test(
      'rejects a child that is not a sliver, where the caller can see it',
      () {
        // The constructor is typed, but the child-list mixin is not, and the
        // declarative layer hands over plain widgets. Caught at adoption, the
        // message can name the fix; caught during layout it was a bare cast
        // failure with no idea what to do about it.
        final view = CustomScrollView3d();
        expect(
          () => view.add(TestBox(const Size3d(1, 1, 1))),
          throwsA(
            isA<AssertionError>().having(
              (error) => error.message,
              'message',
              contains('SliverToBoxAdapter3d'),
            ),
          ),
        );
      },
    );

    test('lays its slivers out one after another', () {
      final first = ProbeSliver3d(4);
      final second = ProbeSliver3d(3);
      final view = CustomScrollView3d(slivers: [first, second]);
      viewportOf(view);

      expect(first.offset, Offset3d.zero);
      expect(second.offset, const Offset3d(0, 4, 0));
      expect(first.geometry.paintExtent, 4);
      expect(second.geometry.paintExtent, 3);
      // The second was told what came before it, which is what lets a sliver
      // know where it sits in the whole.
      expect(second.windows.last.precedingScrollExtent, 4);
    });

    test('adds their scroll extents into one scroll range', () {
      final view = CustomScrollView3d(
        slivers: [ProbeSliver3d(8), ProbeSliver3d(9)],
      );
      viewportOf(view);

      expect(view.controller.contentExtent, 17);
      expect(view.controller.viewportExtent, 10);
      expect(view.controller.maxScrollExtent, 7);
    });

    test('one position moves every section', () {
      final first = ProbeSliver3d(8);
      final second = ProbeSliver3d(9);
      final view = CustomScrollView3d(slivers: [first, second]);
      final surface = viewportOf(view);

      view.controller.jumpTo(5);
      surface.flush();

      // The first has five of its eight scrolled off, so it keeps only the
      // rest of the window; the second follows straight after it.
      expect(first.windows.last.scrollOffset, 5);
      expect(first.geometry.paintExtent, 3);
      expect(second.offset, const Offset3d(0, 3, 0));
      expect(second.windows.last.scrollOffset, 0);
    });

    test('a section scrolled clean off reports nothing and is hidden', () {
      final first = ProbeSliver3d(8);
      final second = ProbeSliver3d(20);
      final view = CustomScrollView3d(slivers: [first, second]);
      final surface = viewportOf(view);

      view.controller.jumpTo(10);
      surface.flush();

      expect(first.geometry.paintExtent, 0);
      expect(first.geometry.visible, isFalse);
      expect(first.node.visible, isFalse);
      expect(second.node.visible, isTrue);
    });

    test('the window a section sees shrinks as earlier ones fill it', () {
      final first = ProbeSliver3d(4);
      final second = ProbeSliver3d(4);
      final view = CustomScrollView3d(slivers: [first, second]);
      viewportOf(view);

      expect(first.windows.last.remainingPaintExtent, 10);
      expect(second.windows.last.remainingPaintExtent, 6);
    });

    test('a cache extent reaches beyond the window on both sides', () {
      final sliver = ProbeSliver3d(40);
      final view = CustomScrollView3d(cacheExtent: 3, slivers: [sliver]);
      final surface = viewportOf(view);

      // At the very start there is nothing above to cache.
      expect(sliver.windows.last.cacheOrigin, 0);
      expect(sliver.windows.last.remainingCacheExtent, 13);

      view.controller.jumpTo(20);
      surface.flush();

      expect(sliver.windows.last.cacheOrigin, -3);
      expect(sliver.windows.last.remainingCacheExtent, 16);
    });

    test('applies a scroll offset correction and lays out again', () {
      final correcting = CorrectingSliver3d(30, 5);
      final view = CustomScrollView3d(slivers: [correcting]);
      viewportOf(view);

      expect(correcting.passes, 2);
      expect(view.controller.offset, 5);
      expect(correcting.geometry.paintExtent, 10);
    });

    test('pulls the offset back in when the content shrinks under it', () {
      final sliver = ProbeSliver3d(40);
      final view = CustomScrollView3d(slivers: [sliver]);
      final surface = viewportOf(view);

      view.controller.jumpTo(30);
      surface.flush();
      expect(view.controller.offset, 30);

      // Half the content goes away while the offset is deep in it.
      view.syncSlivers([ProbeSliver3d(12)]);
      surface.flush();

      expect(view.controller.offset, 2);
      expect(view.slivers.single.geometry.paintExtent, 10);
    });

    test('is opaque, so a drag between sections still scrolls it', () {
      final view = CustomScrollView3d(
        slivers: [ProbeSliver3d(4), ProbeSliver3d(4)],
      );
      final surface = viewportOf(view);

      expect(surface.hitTestAt(const Offset3d(2, 9, 1)).target, same(view));
      expect(
        surface.hitTestAt(const Offset3d(2, 9, 1)).firstOf<Scrollable3d>(),
        same(view),
      );
    });
  });

  group('SliverToBoxAdapter3d', () {
    test('gives a box its turn in the scroll', () {
      final box = TestBox(const Size3d(1, 6, 1));
      final adapter = SliverToBoxAdapter3d(child: box);
      final view = CustomScrollView3d(slivers: [adapter, ProbeSliver3d(6)]);
      viewportOf(view);

      expect(adapter.geometry.scrollExtent, 6);
      expect(adapter.geometry.paintExtent, 6);
      expect(box.offset, Offset3d.zero);
      expect(view.controller.contentExtent, 12);
    });

    test('slides its child as it scrolls past', () {
      final box = TestBox(const Size3d(1, 6, 1));
      final view = CustomScrollView3d(
        slivers: [
          SliverToBoxAdapter3d(child: box),
          ProbeSliver3d(20),
        ],
      );
      final surface = viewportOf(view);

      view.controller.jumpTo(4);
      surface.flush();

      expect(box.offset, const Offset3d(0, -4, 0));
    });

    test('an empty adapter takes no room', () {
      final adapter = SliverToBoxAdapter3d();
      viewportOf(CustomScrollView3d(slivers: [adapter]));

      expect(adapter.geometry.scrollExtent, 0);
    });
  });

  group('SliverList3d', () {
    test('a shrunken itemCount shortens the measured content with it', () {
      // The measured prefix is what the list knows about where its items sit,
      // and it outlives a change to how many there are. Left alone, a list
      // that had measured ten items went on reporting all ten as its length
      // after being told there were five.
      final list = SliverList3d.builder(
        itemCount: 10,
        itemBuilder: (index) => TestBox(const Size3d(1, 2, 1)),
      );
      final view = CustomScrollView3d(slivers: [list]);
      final surface = viewportOf(view, size: const Size3d(4, 20, 2));
      expect(list.geometry.scrollExtent, 20);

      list.itemCount = 5;
      surface.flush();
      expect(list.geometry.scrollExtent, 10);
    });

    test('stacks its items along the scroll axis', () {
      final boxes = items(4);
      final list = SliverList3d(spacing: 1, children: boxes);
      final view = CustomScrollView3d(slivers: [list]);
      viewportOf(view);

      expect(boxes[0].offset.y, 0);
      expect(boxes[1].offset.y, 3);
      expect(list.geometry.scrollExtent, 11);
      // Items are centred across, not stretched: a 1 wide box in a 4 wide
      // viewport sits at 1.5.
      expect(boxes[0].offset.x, 1.5);
    });

    test('follows another sliver rather than starting from the top', () {
      final boxes = items(8);
      final view = CustomScrollView3d(
        slivers: [
          ProbeSliver3d(4),
          SliverList3d(children: boxes),
        ],
      );
      final surface = viewportOf(view);

      // The list's own coordinates start at its leading edge; the viewport
      // puts that edge at 4.
      expect(boxes[0].offset.y, 0);
      expect(view.slivers[1].offset, const Offset3d(0, 4, 0));

      view.controller.jumpTo(6);
      surface.flush();

      // Now two of the list's units have scrolled past.
      expect(boxes[0].offset.y, -2);
      expect(view.slivers[1].offset, Offset3d.zero);
    });

    test('a fixed item extent builds only the window', () {
      final built = <int>[];
      final list = SliverList3d.builder(
        itemCount: 500,
        itemExtent: 2,
        itemBuilder: (index) {
          built.add(index);
          return TestBox(const Size3d(1, 2, 1));
        },
      );
      final view = CustomScrollView3d(slivers: [list]);
      viewportOf(view);

      // A window of 10 over items of 2: six rows, and the whole extent known
      // without touching the other 494.
      expect(list.geometry.scrollExtent, 1000);
      expect(built.length, 6);
      expect(list.childCount, 6);
    });

    test('measures as it goes when the items size themselves', () {
      final list = SliverList3d.builder(
        itemCount: 100,
        itemBuilder: (index) => TestBox(const Size3d(1, 2, 1)),
      );
      final view = CustomScrollView3d(slivers: [list]);
      viewportOf(view);

      // Six measured, the rest estimated from their average stride.
      expect(list.childCount, lessThan(10));
      expect(list.geometry.scrollExtent, 200);
    });

    test('releases what scrolls away and builds what arrives', () {
      final list = SliverList3d.builder(
        itemCount: 50,
        itemExtent: 2,
        itemBuilder: (index) => TestBox(const Size3d(1, 2, 1), name: '$index'),
      );
      final view = CustomScrollView3d(slivers: [list]);
      final surface = viewportOf(view);
      final first = list.children.first;

      view.controller.jumpTo(40);
      surface.flush();

      expect(list.children, isNot(contains(first)));
      expect(list.childCount, 6);
    });

    test('an empty list is a sliver of no length', () {
      final list = SliverList3d();
      viewportOf(CustomScrollView3d(slivers: [list]));

      expect(list.geometry.scrollExtent, 0);
      expect(list.geometry.visible, isFalse);
    });
  });

  group('SliverGrid3d', () {
    const twoAcross = Grid3dDelegateWithFixedCrossAxisCount(crossAxisCount: 2);

    test('lays cells out on the same grid a GridView3d would', () {
      final cells = items(4, Size3d.zero);
      final grid = SliverGrid3d(gridDelegate: twoAcross, children: cells);
      viewportOf(CustomScrollView3d(slivers: [grid]));

      // Two cells across 4 wide, square: 2 by 2.
      expect(grid.gridLayout!.cellCrossAxisExtent, 2);
      expect(cells[0].offset.x, 0);
      expect(cells[1].offset.x, 2);
      expect(cells[2].offset.y, 2);
      expect(grid.geometry.scrollExtent, 4);
    });

    test('is exactly lazy', () {
      final built = <int>[];
      final grid = SliverGrid3d.builder(
        gridDelegate: twoAcross,
        itemCount: 1000,
        itemBuilder: (index) {
          built.add(index);
          return TestBox(Size3d.zero);
        },
      );
      viewportOf(CustomScrollView3d(slivers: [grid]));

      // 500 rows of 2, known without building any of them.
      expect(grid.geometry.scrollExtent, 1000);
      expect(built.length, lessThan(16));
    });

    test('takes its turn after a list', () {
      final grid = SliverGrid3d(
        gridDelegate: twoAcross,
        children: items(2, Size3d.zero),
      );
      final view = CustomScrollView3d(
        slivers: [
          SliverToBoxAdapter3d(child: TestBox(const Size3d(1, 3, 1))),
          grid,
        ],
      );
      viewportOf(view);

      expect(view.slivers[1].offset, const Offset3d(0, 3, 0));
      expect(grid.geometry.scrollExtent, 2);
      // Shorter than the window, so there is nowhere to scroll, but the
      // content extent still says how long it actually is.
      expect(view.controller.contentExtent, 5);
      expect(view.controller.maxScrollExtent, 0);
    });
  });
}
