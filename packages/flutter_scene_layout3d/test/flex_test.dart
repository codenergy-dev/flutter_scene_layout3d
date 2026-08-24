// Row3d, Column3d, and Depth3d: the flex protocol on three axes.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final tight10 = Constraints3d.tight(const Size3d(10, 10, 10));

  group('Column3d', () {
    test('stacks children along y and centres them on the cross axes', () {
      final children = [
        TestBox(const Size3d(2, 2, 2)),
        TestBox(const Size3d(2, 2, 2)),
        TestBox(const Size3d(2, 2, 2)),
      ];
      final column = Column3d(children: children);
      final surface = laidOut(column, constraints: tight10);

      expect(surface.size, const Size3d(10, 10, 10));
      expect(children[0].offset, const Offset3d(4, 0, 4));
      expect(children[1].offset, const Offset3d(4, 2, 4));
      expect(children[2].offset, const Offset3d(4, 4, 4));
    });

    test('spaceBetween spreads the leftover room', () {
      final children = [
        TestBox(const Size3d(2, 2, 2)),
        TestBox(const Size3d(2, 2, 2)),
        TestBox(const Size3d(2, 2, 2)),
      ];
      laidOut(
        Column3d(
          mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
          children: children,
        ),
        constraints: tight10,
      );
      expect(children[0].offset.y, 0);
      expect(children[1].offset.y, 4);
      expect(children[2].offset.y, 8);
    });

    test('spacing inserts a fixed gap', () {
      final children = [
        TestBox(const Size3d(2, 2, 2)),
        TestBox(const Size3d(2, 2, 2)),
      ];
      laidOut(Column3d(spacing: 1, children: children), constraints: tight10);
      expect(children[0].offset.y, 0);
      expect(children[1].offset.y, 3);
    });

    test('mainAxisSize.min shrink-wraps the line', () {
      final column = Column3d(
        mainAxisSize: MainAxisSize3d.min,
        children: [
          TestBox(const Size3d(2, 2, 2)),
          TestBox(const Size3d(2, 3, 2)),
        ],
      );
      laidOut(
        column,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
      );
      expect(column.size, const Size3d(2, 5, 2));
    });

    test('shrink-wraps when the main axis is unbounded', () {
      final column = Column3d(
        children: [
          TestBox(const Size3d(2, 2, 2)),
          TestBox(const Size3d(2, 3, 2)),
        ],
      );
      laidOut(column);
      expect(column.size, const Size3d(2, 5, 2));
    });

    test('Expanded3d divides what is left', () {
      final fixed = TestBox(const Size3d(2, 2, 2));
      final grown = TestBox(const Size3d(1, 1, 1));
      final expanded = Expanded3d(child: grown);
      laidOut(Column3d(children: [fixed, expanded]), constraints: tight10);
      expect(fixed.size.height, 2);
      expect(grown.size.height, 8);
      // The flexible wrapper is a real layout, so it is the one the column
      // positions; the child sits at its origin.
      expect(expanded.offset.y, 2);
      expect(grown.offset.y, 0);
    });

    test('flex factors split the free space in proportion', () {
      final one = TestBox(const Size3d(1, 1, 1));
      final two = TestBox(const Size3d(1, 1, 1));
      laidOut(
        Column3d(
          children: [
            Expanded3d(child: one),
            Expanded3d(flex: 3, child: two),
          ],
        ),
        constraints: tight10,
      );
      expect(one.size.height, 2.5);
      expect(two.size.height, 7.5);
    });

    test('loose fit lets a flexible child stay small', () {
      final child = TestBox(const Size3d(1, 1, 1));
      laidOut(
        Column3d(children: [Flexible3d(child: child)]),
        constraints: tight10,
      );
      expect(child.size.height, 1);
    });

    test('stretch fills the cross axis', () {
      final child = TestBox(const Size3d(1, 1, 1));
      laidOut(
        Column3d(
          crossAxisAlignment: CrossAxisAlignment3d.stretch,
          children: [child],
        ),
        constraints: tight10,
      );
      expect(child.size.width, 10);
      expect(child.offset.x, 0);
    });

    test('cross axis end aligns to the far face', () {
      final child = TestBox(const Size3d(2, 2, 2));
      laidOut(
        Column3d(
          crossAxisAlignment: CrossAxisAlignment3d.end,
          depthAxisAlignment: CrossAxisAlignment3d.start,
          children: [child],
        ),
        constraints: tight10,
      );
      expect(child.offset.x, 8);
      expect(child.offset.z, 0);
    });
  });

  group('Row3d', () {
    test('runs along x', () {
      final children = [
        TestBox(const Size3d(2, 2, 2)),
        TestBox(const Size3d(3, 2, 2)),
      ];
      laidOut(Row3d(children: children), constraints: tight10);
      expect(children[0].offset.x, 0);
      expect(children[1].offset.x, 2);
      expect(children[0].offset.y, 4);
    });

    test('centres the whole line', () {
      final child = TestBox(const Size3d(2, 2, 2));
      laidOut(
        Row3d(mainAxisAlignment: MainAxisAlignment3d.center, children: [child]),
        constraints: tight10,
      );
      expect(child.offset.x, 4);
    });
  });

  group('Depth3d', () {
    test('runs away from the viewer', () {
      final children = [
        TestBox(const Size3d(2, 2, 1)),
        TestBox(const Size3d(2, 2, 3)),
      ];
      laidOut(Depth3d(children: children), constraints: tight10);
      expect(children[0].offset.z, 0);
      expect(children[1].offset.z, 1);
      // The cross axes of a depth flex are x and y.
      expect(children[0].offset.x, 4);
      expect(children[0].offset.y, 4);
    });
  });

  test('Spacer3d pushes its siblings apart', () {
    final top = TestBox(const Size3d(2, 2, 2));
    final bottom = TestBox(const Size3d(2, 2, 2));
    laidOut(
      Column3d(children: [top, Spacer3d(), bottom]),
      constraints: tight10,
    );
    expect(top.offset.y, 0);
    expect(bottom.offset.y, 8);
  });
}
