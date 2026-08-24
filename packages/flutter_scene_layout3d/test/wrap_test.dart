import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Four boxes 4 wide in a wrap 10 across: two per run.
List<TestBox> squares(int count, [Size3d size = const Size3d(4, 2, 1)]) =>
    List.generate(count, (index) => TestBox(size, name: 'box$index'));

void main() {
  group('runs', () {
    test('breaks when the next child would not fit', () {
      final boxes = squares(5);
      laidOut(
        Wrap3d(children: boxes),
        constraints: Constraints3d.loose(const Size3d(10, 20, 5)),
      );

      // 4 + 4 fits in 10, a third 4 does not.
      expect(boxes[0].offset, const Offset3d(0, 0, 0));
      expect(boxes[1].offset, const Offset3d(4, 0, 0));
      expect(boxes[2].offset, const Offset3d(0, 2, 0));
      expect(boxes[3].offset, const Offset3d(4, 2, 0));
      expect(boxes[4].offset, const Offset3d(0, 4, 0));
    });

    test('counts the spacing when deciding to break', () {
      final boxes = squares(2);
      laidOut(
        // 4 + 3 + 4 = 11, over the 10 available, so the second child wraps
        // even though the two boxes alone would fit.
        Wrap3d(spacing: 3, children: boxes),
        constraints: Constraints3d.loose(const Size3d(10, 20, 5)),
      );

      expect(boxes[1].offset, const Offset3d(0, 2, 0));
    });

    test('separates runs by runSpacing', () {
      final boxes = squares(3);
      laidOut(
        Wrap3d(runSpacing: 1.5, children: boxes),
        constraints: Constraints3d.loose(const Size3d(10, 20, 5)),
      );

      expect(boxes[2].offset, const Offset3d(0, 3.5, 0));
    });

    test('an unbounded main axis never breaks', () {
      final boxes = squares(6);
      laidOut(Wrap3d(children: boxes), constraints: const Constraints3d());

      expect(boxes.last.offset, const Offset3d(20, 0, 0));
    });

    test('shrink-wraps to the runs it made', () {
      final wrap = Wrap3d(children: squares(3));
      laidOut(wrap, constraints: Constraints3d.loose(const Size3d(10, 20, 5)));

      // Two runs: 8 across at the widest, 4 down, 1 deep.
      expect(wrap.size, const Size3d(8, 4, 1));
    });

    test('a run is as thick as its tallest child', () {
      final short = TestBox(const Size3d(4, 1, 1));
      final tall = TestBox(const Size3d(4, 3, 1));
      final next = TestBox(const Size3d(4, 1, 1));
      laidOut(
        Wrap3d(children: [short, tall, next]),
        constraints: Constraints3d.loose(const Size3d(10, 20, 5)),
      );

      expect(next.offset, const Offset3d(0, 3, 0));
    });
  });

  group('alignment', () {
    test('distributes the leftover room along a run', () {
      final boxes = squares(2);
      laidOut(
        Wrap3d(alignment: WrapAlignment3d.spaceBetween, children: boxes),
        constraints: Constraints3d.tight(const Size3d(10, 10, 1)),
      );

      expect(boxes[0].offset, const Offset3d(0, 0, 0));
      expect(boxes[1].offset, const Offset3d(6, 0, 0));
    });

    test('centres a run', () {
      final boxes = squares(1);
      laidOut(
        Wrap3d(alignment: WrapAlignment3d.center, children: boxes),
        constraints: Constraints3d.tight(const Size3d(10, 10, 1)),
      );

      expect(boxes[0].offset, const Offset3d(3, 0, 0));
    });

    test('distributes the runs across the cross axis', () {
      final boxes = squares(3);
      laidOut(
        Wrap3d(runAlignment: WrapAlignment3d.end, children: boxes),
        constraints: Constraints3d.tight(const Size3d(10, 10, 1)),
      );

      // Two runs, 4 thick in total, pushed to the far end of 10.
      expect(boxes[0].offset, const Offset3d(0, 6, 0));
      expect(boxes[2].offset, const Offset3d(0, 8, 0));
    });

    test('places a child across its own run, not the whole box', () {
      final tall = TestBox(const Size3d(4, 4, 1));
      final short = TestBox(const Size3d(4, 2, 1));
      laidOut(
        Wrap3d(
          crossAxisAlignment: WrapCrossAlignment3d.center,
          children: [tall, short],
        ),
        constraints: Constraints3d.tight(const Size3d(10, 20, 1)),
      );

      // The run is 4 thick, so the shorter box is inset by 1, regardless of
      // the 20 the wrap itself was given.
      expect(short.offset, const Offset3d(4, 1, 0));
    });

    test('centres on the axis that does not wrap', () {
      final deep = TestBox(const Size3d(4, 2, 3));
      final shallow = TestBox(const Size3d(4, 2, 1));
      laidOut(
        Wrap3d(children: [deep, shallow]),
        constraints: Constraints3d.loose(const Size3d(10, 20, 5)),
      );

      expect(deep.offset, const Offset3d(0, 0, 0));
      expect(shallow.offset, const Offset3d(4, 0, 1));
    });

    test('a depth-aligned wrap can pin to the back face instead', () {
      final deep = TestBox(const Size3d(4, 2, 3));
      final shallow = TestBox(const Size3d(4, 2, 1));
      laidOut(
        Wrap3d(
          depthAxisAlignment: WrapCrossAlignment3d.end,
          children: [deep, shallow],
        ),
        constraints: Constraints3d.loose(const Size3d(10, 20, 5)),
      );

      expect(shallow.offset, const Offset3d(4, 0, 2));
    });
  });

  group('as a running layout', () {
    test('an empty wrap takes the smallest size allowed', () {
      final wrap = Wrap3d();
      laidOut(wrap, constraints: Constraints3d.loose(const Size3d(10, 10, 10)));

      expect(wrap.size, Size3d.zero);
    });

    test('a direction change relays out', () {
      final boxes = squares(3);
      final wrap = Wrap3d(children: boxes);
      final surface = laidOut(
        wrap,
        constraints: Constraints3d.loose(const Size3d(10, 20, 5)),
      );

      expect(boxes[2].offset, const Offset3d(0, 2, 0));

      wrap.direction = Axis3d.vertical;
      surface.flush();

      // Running down the plane now, wrapping across it: 2 + 2 fit in 20,
      // and so does the third.
      expect(boxes[2].offset, const Offset3d(0, 4, 0));
    });

    test('children that overflow a run are not pushed outside the box', () {
      final wide = TestBox(const Size3d(20, 2, 1));
      final wrap = Wrap3d(children: [wide]);
      laidOut(wrap, constraints: Constraints3d.loose(const Size3d(10, 20, 5)));

      // The child is constrained to the room available rather than left to
      // overflow, the same as Flutter's Wrap.
      expect(wide.size.width, 10);
      expect(wrap.size.width, 10);
    });
  });
}
