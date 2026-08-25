import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Cells take whatever the grid gives them, which is a tight cell.
List<TestBox> cells(int count) =>
    List.generate(count, (index) => TestBox(Size3d.zero, name: 'cell$index'));

const Grid3dDelegate twoAcross = Grid3dDelegateWithFixedCrossAxisCount(
  crossAxisCount: 2,
);

void main() {
  group('the cell grid', () {
    test('divides the room across the scroll axis', () {
      final boxes = cells(4);
      final grid = GridView3d(gridDelegate: twoAcross, children: boxes);
      laidOut(grid, constraints: Constraints3d.tight(const Size3d(10, 10, 2)));

      // Two cells across 10, square by default: 5 by 5. The z of 1 is the
      // depth centring: a flat cell in a grid 2 deep sits in the middle.
      expect(boxes[0].size.width, 5);
      expect(boxes[0].size.height, 5);
      expect(boxes[0].offset, const Offset3d(0, 0, 1));
      expect(boxes[1].offset, const Offset3d(5, 0, 1));
      expect(boxes[2].offset, const Offset3d(0, 5, 1));
      expect(boxes[3].offset, const Offset3d(5, 5, 1));
    });

    test('takes the spacings out of the room first', () {
      final boxes = cells(4);
      laidOut(
        GridView3d(
          gridDelegate: const Grid3dDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 2,
            mainAxisSpacing: 1,
          ),
          children: boxes,
        ),
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );

      // (10 - 2) / 2 = 4 across, square, so 4 down as well.
      expect(boxes[0].size.width, 4);
      expect(boxes[1].offset, const Offset3d(6, 0, 1));
      expect(boxes[2].offset, const Offset3d(0, 5, 1));
    });

    test('the aspect ratio sets the main extent', () {
      final boxes = cells(2);
      laidOut(
        GridView3d(
          gridDelegate: const Grid3dDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.0,
          ),
          children: boxes,
        ),
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );

      expect(boxes[0].size.width, 5);
      expect(boxes[0].size.height, 2.5);
    });

    test('a fixed main extent overrides the aspect ratio', () {
      final boxes = cells(2);
      laidOut(
        GridView3d(
          gridDelegate: const Grid3dDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.0,
            mainAxisExtent: 3.0,
          ),
          children: boxes,
        ),
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );

      expect(boxes[0].size.height, 3);
    });

    test('a maximum cell size fits as many cells as it can', () {
      final layout = const Grid3dDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 4,
      ).layoutFor(10);

      // Three cells of 10/3 rather than two of 5, because 5 is over the
      // maximum; the same rounding Flutter's delegate does.
      expect(layout.crossAxisCount, 3);
      expect(layout.cellCrossAxisExtent, closeTo(10 / 3, 1e-9));
    });

    test('cell positions are arithmetic, with no children involved', () {
      const layout = Grid3dLayout(
        crossAxisCount: 3,
        cellCrossAxisExtent: 2,
        cellMainAxisExtent: 4,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      );

      expect(layout.mainAxisOffsetOf(4), 5);
      expect(layout.crossAxisOffsetOf(4), 3);
      expect(layout.rowCountFor(7), 3);
      expect(layout.mainExtentFor(7), 14);
      expect(layout.firstIndexAt(5), 3);
      expect(layout.lastIndexAt(5, 7), 5);
    });
  });

  group('scrolling', () {
    test('reports the metrics it measured', () {
      final grid = GridView3d(gridDelegate: twoAcross, children: cells(8));
      laidOut(grid, constraints: Constraints3d.tight(const Size3d(10, 10, 2)));

      // Four rows of 5 is 20 of content in a window of 10.
      expect(grid.controller.contentExtent, 20);
      expect(grid.controller.viewportExtent, 10);
      expect(grid.controller.maxScrollExtent, 10);
    });

    test('the offset slides the cells', () {
      final boxes = cells(8);
      final grid = GridView3d(gridDelegate: twoAcross, children: boxes);
      final surface = laidOut(
        grid,
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );

      grid.controller.jumpTo(3);
      surface.flush();

      expect(boxes[0].offset, const Offset3d(0, -3, 1));
      expect(boxes[2].offset, const Offset3d(0, 2, 1));
    });

    test('hides the rows outside the window', () {
      final boxes = cells(8);
      final grid = GridView3d(gridDelegate: twoAcross, children: boxes);
      laidOut(grid, constraints: Constraints3d.tight(const Size3d(10, 10, 2)));

      expect(boxes[0].node.visible, isTrue);
      expect(boxes[3].node.visible, isTrue);
      expect(boxes[4].node.visible, isFalse);
      expect(boxes[7].node.visible, isFalse);
    });

    test('takes the hit over the gaps between cells', () {
      final grid = GridView3d(
        gridDelegate: const Grid3dDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 4,
        ),
        children: cells(2),
      );
      final surface = laidOut(
        grid,
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );

      // Straight down the 4-wide gutter between the two cells.
      expect(surface.hitTestAt(const Offset3d(5, 1, 1)).target, same(grid));
    });
  });

  // What the class is underneath: a viewport over one sliver, the shape
  // Flutter's GridView has. None of it changes what a caller sees.
  group('GridView3d is a viewport over one SliverGrid3d', () {
    test('holds the sliver, and answers children with the cells in it', () {
      final boxes = cells(2);
      final grid = GridView3d(gridDelegate: twoAcross, children: boxes);
      laidOut(grid, constraints: Constraints3d.tight(const Size3d(10, 10, 2)));

      expect(grid.children, boxes);
      expect(grid.sliver.children, boxes);
      expect(boxes[0].parent, same(grid.sliver));
      // The grid it reports is the one its sliver laid the cells out on.
      expect(grid.gridLayout, same(grid.sliver.gridLayout));
    });
  });

  group('building on demand', () {
    GridView3d lazyGrid({double cacheExtent = 0.0, int itemCount = 8}) =>
        GridView3d.builder(
          gridDelegate: twoAcross,
          itemCount: itemCount,
          cacheExtent: cacheExtent,
          itemBuilder: (index) => TestBox(Size3d.zero, name: 'cell$index'),
        );

    test('builds only the rows in the window', () {
      final grid = lazyGrid();
      laidOut(grid, constraints: Constraints3d.tight(const Size3d(10, 10, 2)));

      // Rows at 0, 5 and 10: the third starts exactly at the window's end.
      expect(grid.childCount, 6);
      expect(grid.controller.maxScrollExtent, 10);
    });

    test('the extent is exact, not estimated', () {
      final grid = lazyGrid(itemCount: 101);
      laidOut(grid, constraints: Constraints3d.tight(const Size3d(10, 10, 2)));

      // 51 rows of 5, known without building a single one of them.
      expect(grid.controller.contentExtent, 255);
      expect(grid.childCount, lessThan(10));
    });

    test('releases what scrolls out and builds what scrolls in', () {
      final grid = lazyGrid();
      final surface = laidOut(
        grid,
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );
      final firstPass = grid.children.first;

      grid.controller.jumpTo(10);
      surface.flush();

      expect(grid.childCount, 4);
      expect(grid.children, isNot(contains(firstPass)));
    });

    test('a cache extent keeps neighbours alive', () {
      final grid = lazyGrid(cacheExtent: 5);
      final surface = laidOut(
        grid,
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );

      grid.controller.jumpTo(10);
      surface.flush();

      // The window covers rows 2 and 3; the cache reaches back to row 1.
      expect(grid.childCount, 6);
    });
  });

  group('the delegate', () {
    test('an equivalent delegate does not relayout', () {
      final grid = GridView3d(gridDelegate: twoAcross, children: cells(2));
      final surface = laidOut(
        grid,
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );

      grid.gridDelegate = const Grid3dDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
      );

      expect(surface.needsFlush, isFalse);
    });

    test('a changed one does', () {
      final boxes = cells(2);
      final grid = GridView3d(gridDelegate: twoAcross, children: boxes);
      final surface = laidOut(
        grid,
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );

      grid.gridDelegate = const Grid3dDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
      );

      expect(surface.needsFlush, isTrue);
      surface.flush();
      expect(boxes[1].offset, const Offset3d(0, 10, 1));
    });

    test('a delegate of another kind always does', () {
      final grid = GridView3d(gridDelegate: twoAcross, children: cells(2));
      final surface = laidOut(
        grid,
        constraints: Constraints3d.tight(const Size3d(10, 10, 2)),
      );

      grid.gridDelegate = const Grid3dDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 5,
      );

      expect(surface.needsFlush, isTrue);
    });
  });

  group('the depth axis', () {
    test('cells are as deep as the grid allows, and shallow ones centre', () {
      final shallow = TestBox(const Size3d(0, 0, 1));
      laidOut(
        GridView3d(gridDelegate: twoAcross, children: [shallow]),
        constraints: Constraints3d.tight(const Size3d(10, 10, 5)),
      );

      expect(shallow.size.depth, 1);
      expect(shallow.offset.z, 2);
    });

    test('stretch fills the depth instead', () {
      final box = TestBox(const Size3d(0, 0, 1));
      laidOut(
        GridView3d(
          gridDelegate: twoAcross,
          depthAxisAlignment: CrossAxisAlignment3d.stretch,
          children: [box],
        ),
        constraints: Constraints3d.tight(const Size3d(10, 10, 5)),
      );

      expect(box.size.depth, 5);
      expect(box.offset.z, 0);
    });
  });
}
