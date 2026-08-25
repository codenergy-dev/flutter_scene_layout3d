// The measurement protocol: intrinsic extents, baselines, and the boxes
// built on them.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import 'support.dart';

void main() {
  final tight10 = Constraints3d.tight(const Size3d(10, 10, 10));

  group('the protocol', () {
    test('a leaf reports what it wants on each axis', () {
      final box = TestBox(
        const Size3d(2, 3, 4),
        minimum: const Size3d(1, 1, 1),
      );
      expect(box.getMaxIntrinsicExtent(Axis3d.horizontal), 2);
      expect(box.getMaxIntrinsicExtent(Axis3d.vertical), 3);
      expect(box.getMaxIntrinsicExtent(Axis3d.depth), 4);
      expect(box.getMinIntrinsicExtent(Axis3d.horizontal), 1);
    });

    test('the answer is asked for once and kept', () {
      final box = TestBox(const Size3d(2, 3, 4));
      box.getMaxIntrinsicExtent(Axis3d.horizontal);
      box.getMaxIntrinsicExtent(Axis3d.horizontal);
      expect(box.intrinsicQueries, 1);

      // A different question: different axis, different limits, minimum
      // rather than maximum.
      box.getMaxIntrinsicExtent(Axis3d.vertical);
      box.getMaxIntrinsicExtent(Axis3d.horizontal, const Size3d(0, 5, 5));
      box.getMinIntrinsicExtent(Axis3d.horizontal);
      expect(box.intrinsicQueries, 4);
    });

    test('the limit along the queried axis is not part of the question', () {
      final box = TestBox(const Size3d(2, 3, 4));
      expect(box.getMaxIntrinsicExtent(Axis3d.horizontal, Size3d.infinite), 2);
      expect(
        box.getMaxIntrinsicExtent(Axis3d.horizontal, const Size3d(99, 0, 0)),
        2,
      );
      // The first call's limits and the second's differ only where the answer
      // cannot depend on them, so the second is the same question.
      expect(
        box.getMaxIntrinsicExtent(
          Axis3d.horizontal,
          const Size3d(7, double.infinity, double.infinity),
        ),
        2,
      );
      expect(box.intrinsicQueries, 2);
    });

    test('going dirty drops the answer', () {
      final box = TestBox(const Size3d(2, 3, 4));
      expect(box.getMaxIntrinsicExtent(Axis3d.horizontal), 2);
      box.preferred = const Size3d(6, 3, 4);
      expect(box.getMaxIntrinsicExtent(Axis3d.horizontal), 6);
    });

    test('a box that was measured pushes its dirt past its own boundary', () {
      Column3d makeColumn() =>
          Column3d(children: <Layout3d>[TestBox(const Size3d(2, 2, 2))]);

      // Tight constraints make the column its own relayout boundary, so a
      // change inside it normally stops there.
      final quiet = makeColumn();
      final quietParent = SizedBox3d.cube(10, child: quiet);
      laidOut(quietParent);
      quiet.spacing = 1;
      expect(quiet.needsLayout, isTrue);
      expect(quietParent.needsLayout, isFalse);

      // Unless someone asked it how big it wants to be, in which case the
      // answer they were given is stale and only the parent can ask again.
      final measured = makeColumn();
      final measuredParent = SizedBox3d.cube(10, child: measured);
      laidOut(measuredParent);
      measured.getMaxIntrinsicExtent(Axis3d.horizontal);
      measured.spacing = 1;
      expect(measuredParent.needsLayout, isTrue);
    });
  });

  group('boxes that add room', () {
    test('Padding3d adds its insets and deflates what it passes on', () {
      final child = TestBox(const Size3d(2, 3, 4));
      final padding = Padding3d(
        padding: const EdgeInsets3d.all(1),
        child: child,
      );
      expect(padding.getMaxIntrinsicExtent(Axis3d.horizontal), 4);
      expect(padding.getMinIntrinsicExtent(Axis3d.vertical), 5);

      padding.getMaxIntrinsicExtent(Axis3d.vertical, const Size3d(10, 0, 10));
      expect(child.lastIntrinsicLimits, const Size3d(8, 0, 8));
    });

    test('Padding3d with no child is its own thickness', () {
      final padding = Padding3d(padding: const EdgeInsets3d.all(2));
      expect(padding.getMaxIntrinsicExtent(Axis3d.horizontal), 4);
    });

    test('Container3d folds in padding, margin, and its constraints', () {
      final child = TestBox(const Size3d(2, 2, 2));
      final container = Container3d(
        padding: const EdgeInsets3d.all(1),
        margin: const EdgeInsets3d.all(2),
        child: child,
      );
      expect(container.getMaxIntrinsicExtent(Axis3d.horizontal), 8);

      container.additionalConstraints = Container3d.resolveConstraints(
        null,
        10,
        null,
        null,
      );
      // The fixed width answers for the content, and the margin is added
      // around it: 10 + 2 + 2.
      expect(container.getMaxIntrinsicExtent(Axis3d.horizontal), 14);
      expect(container.getMaxIntrinsicExtent(Axis3d.vertical), 8);
    });
  });

  group('boxes that impose limits', () {
    test('a fixed axis answers without asking the child', () {
      final child = TestBox(const Size3d(2, 3, 4));
      final box = SizedBox3d(width: 7, child: child);
      expect(box.getMaxIntrinsicExtent(Axis3d.horizontal), 7);
      expect(child.intrinsicQueries, 0);
      expect(box.getMaxIntrinsicExtent(Axis3d.vertical), 3);
      expect(child.intrinsicQueries, 1);
    });

    test('extra constraints clamp what the child asked for', () {
      final box = ConstrainedBox3d(
        additionalConstraints: const Constraints3d(minWidth: 5, maxHeight: 2),
        child: TestBox(const Size3d(2, 3, 4)),
      );
      expect(box.getMaxIntrinsicExtent(Axis3d.horizontal), 5);
      expect(box.getMaxIntrinsicExtent(Axis3d.vertical), 2);
    });

    test('an expanding box has no finite answer of its own', () {
      final box = SizedBox3d.expand(child: TestBox(const Size3d(2, 3, 4)));
      expect(box.getMaxIntrinsicExtent(Axis3d.horizontal), 2);
    });

    test('Transform3d measures the child untransformed', () {
      final box = Transform3d.rotate(
        axis: Vector3(0, 0, 1),
        angle: 0.7,
        child: TestBox(const Size3d(2, 3, 4)),
      );
      expect(box.getMaxIntrinsicExtent(Axis3d.horizontal), 2);
    });
  });

  group('boxes that arrange children', () {
    test('a line adds up along its axis and overlaps across it', () {
      final column = Column3d(
        spacing: 1,
        children: <Layout3d>[
          TestBox(const Size3d(2, 3, 4)),
          TestBox(const Size3d(5, 1, 2)),
        ],
      );
      expect(column.getMaxIntrinsicExtent(Axis3d.vertical), 5);
      expect(column.getMaxIntrinsicExtent(Axis3d.horizontal), 5);
      expect(column.getMaxIntrinsicExtent(Axis3d.depth), 4);
    });

    test('a flexible child sets the pace for the whole line', () {
      final column = Column3d(
        children: <Layout3d>[
          TestBox(const Size3d(2, 3, 4)),
          Expanded3d(flex: 2, child: TestBox(const Size3d(2, 4, 4))),
        ],
      );
      // The flexible child wants 4 for two flex units, so two units cost 4
      // and the run is 3 + 4 long.
      expect(column.getMaxIntrinsicExtent(Axis3d.vertical), 7);
    });

    test('a stack is as big as its largest unpositioned child', () {
      final stack = Stack3d(
        children: <Layout3d>[
          TestBox(const Size3d(2, 2, 2)),
          Positioned3d(left: 0, child: TestBox(const Size3d(9, 9, 9))),
        ],
      );
      expect(stack.getMaxIntrinsicExtent(Axis3d.horizontal), 2);
    });

    test('a wrap wants one run and can live with its widest child', () {
      final wrap = Wrap3d(
        spacing: 1,
        children: <Layout3d>[
          TestBox(const Size3d(2, 1, 1)),
          TestBox(const Size3d(3, 1, 1)),
        ],
      );
      expect(wrap.getMaxIntrinsicExtent(Axis3d.horizontal), 6);
      expect(wrap.getMinIntrinsicExtent(Axis3d.horizontal), 3);
      expect(wrap.getMaxIntrinsicExtent(Axis3d.vertical), 1);
    });

    test('a scrolling view refuses the question', () {
      final list = ListView3d(
        children: <Layout3d>[TestBox(const Size3d(2, 2, 2))],
      );
      expect(
        () => list.getMaxIntrinsicExtent(Axis3d.vertical),
        throwsAssertionError,
      );
    });
  });

  group('IntrinsicExtent3d', () {
    test('sizes a column to its widest child', () {
      final children = <Layout3d>[
        TestBox(const Size3d(2, 1, 1)),
        TestBox(const Size3d(5, 1, 1)),
      ];
      final column = Column3d(
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        children: children,
      );
      laidOut(IntrinsicWidth3d(child: column));
      expect(column.size.width, 5);
      expect(children[0].size.width, 5);
      expect(children[1].size.width, 5);
    });

    test('a step rounds the extent up', () {
      final intrinsic = IntrinsicWidth3d(
        step: 2,
        child: TestBox(const Size3d(5, 1, 1)),
      );
      laidOut(intrinsic);
      expect(intrinsic.size.width, 6);
    });

    test('an axis the parent already fixed is not measured', () {
      final child = TestBox(const Size3d(5, 1, 1));
      laidOut(IntrinsicWidth3d(child: child), constraints: tight10);
      expect(child.intrinsicQueries, 0);
      expect(child.size.width, 10);
    });

    test('depth is an axis like any other', () {
      final children = <Layout3d>[
        TestBox(const Size3d(1, 1, 2)),
        TestBox(const Size3d(1, 1, 5)),
      ];
      final row = Row3d(
        depthAxisAlignment: CrossAxisAlignment3d.stretch,
        children: children,
      );
      laidOut(IntrinsicDepth3d(child: row));
      expect(row.size.depth, 5);
      expect(children[0].size.depth, 5);
    });

    test('reports the extent it would take as both minimum and maximum', () {
      final box = IntrinsicWidth3d(
        child: TestBox(const Size3d(5, 1, 1), minimum: const Size3d(1, 1, 1)),
      );
      expect(box.getMinIntrinsicExtent(Axis3d.horizontal), 5);
      expect(box.getMaxIntrinsicExtent(Axis3d.horizontal), 5);
    });

    test('a measured child that changes is measured again', () {
      final children = <Layout3d>[
        TestBox(const Size3d(2, 1, 1)),
        TestBox(const Size3d(5, 1, 1)),
      ];
      final column = Column3d(
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        children: children,
      );
      final surface = laidOut(IntrinsicWidth3d(child: column));
      expect(column.size.width, 5);

      (children[1] as TestBox).preferred = const Size3d(8, 1, 1);
      surface.flush();
      expect(column.size.width, 8);
    });
  });

  group('baselines', () {
    test('a box has none of its own, and stands on its far edge', () {
      final box = TestBox(const Size3d(2, 3, 4));
      laidOut(box);
      expect(
        box.getDistanceToBaseline(Axis3d.vertical, onlyReal: true),
        isNull,
      );
      expect(box.getDistanceToBaseline(Axis3d.vertical), 3);
      expect(box.getDistanceToBaseline(Axis3d.depth), 4);
    });

    test('Baseline3d puts the child on the line and declares it', () {
      final child = TestBox(const Size3d(2, 3, 1));
      final baseline = Baseline3d(baseline: 5, child: child);
      laidOut(baseline);
      expect(child.offset.y, 2);
      expect(baseline.size.height, 5);
      expect(
        baseline.getDistanceToBaseline(Axis3d.vertical, onlyReal: true),
        5,
      );
    });

    test('padding moves the baseline with the child', () {
      final padded = Padding3d(
        padding: const EdgeInsets3d.all(1),
        child: Baseline3d(baseline: 3, child: TestBox(const Size3d(1, 3, 1))),
      );
      laidOut(padded);
      expect(padded.getDistanceToBaseline(Axis3d.vertical, onlyReal: true), 4);
    });

    test('a stack hangs from the highest baseline among its children', () {
      final stack = Stack3d(
        children: <Layout3d>[
          Baseline3d(baseline: 3, child: TestBox(const Size3d(2, 3, 1))),
          Baseline3d(baseline: 1, child: TestBox(const Size3d(2, 1, 1))),
        ],
      );
      laidOut(stack);
      expect(stack.getDistanceToBaseline(Axis3d.vertical, onlyReal: true), 1);
    });

    test('a column takes the baseline of its first child', () {
      final column = Column3d(
        children: <Layout3d>[
          Baseline3d(baseline: 4, child: TestBox(const Size3d(1, 3, 1))),
          Baseline3d(baseline: 1, child: TestBox(const Size3d(1, 1, 1))),
        ],
      );
      laidOut(column);
      expect(column.getDistanceToBaseline(Axis3d.vertical, onlyReal: true), 4);
    });
  });

  group('CrossAxisAlignment3d.baseline', () {
    test('lines two children up on the line they declare', () {
      final tall = Baseline3d(
        baseline: 4,
        child: TestBox(const Size3d(1, 3, 1)),
      );
      final short = Baseline3d(
        baseline: 2,
        child: TestBox(const Size3d(1, 2, 1)),
      );
      final row = Row3d(
        crossAxisAlignment: CrossAxisAlignment3d.baseline,
        children: <Layout3d>[tall, short],
      );
      laidOut(row);
      expect(tall.offset.y, 0);
      expect(short.offset.y, 2);
      // Both baselines land on the same line.
      expect(
        tall.offset.y + tall.getDistanceToBaseline(Axis3d.vertical)!,
        short.offset.y + short.getDistanceToBaseline(Axis3d.vertical)!,
      );
      expect(row.size.height, 4);
    });

    test('the line is as thick as what hangs above and below it', () {
      // A child whose baseline is not at its own far edge is what pushes the
      // line's extremes apart.
      final above = Baseline3d(
        baseline: 4,
        child: TestBox(const Size3d(1, 3, 1)),
      );
      final below = Padding3d(
        padding: const EdgeInsets3d.only(bottom: 2),
        child: Baseline3d(baseline: 1, child: TestBox(const Size3d(1, 1, 1))),
      );
      final row = Row3d(
        crossAxisAlignment: CrossAxisAlignment3d.baseline,
        children: <Layout3d>[above, below],
      );
      laidOut(row);
      expect(above.size.height, 4);
      expect(below.size.height, 3);
      // Four above the line and two below it, though neither child is 6 thick.
      expect(row.size.height, 6);
      expect(above.offset.y, 0);
      expect(below.offset.y, 3);
    });

    test('a child with no baseline sits at the start of the line', () {
      final onLine = Baseline3d(
        baseline: 4,
        child: TestBox(const Size3d(1, 3, 1)),
      );
      final plain = TestBox(const Size3d(1, 6, 1));
      final row = Row3d(
        crossAxisAlignment: CrossAxisAlignment3d.baseline,
        children: <Layout3d>[onLine, plain],
      );
      laidOut(row);
      expect(onLine.offset.y, 0);
      expect(plain.offset.y, 0);
      expect(row.size.height, 6);
    });

    test('the depth axis can carry a line of its own', () {
      final near = Baseline3d(
        baseline: 3,
        axis: Axis3d.depth,
        child: TestBox(const Size3d(1, 1, 2)),
      );
      final far = Baseline3d(
        baseline: 1,
        axis: Axis3d.depth,
        child: TestBox(const Size3d(1, 1, 1)),
      );
      final row = Row3d(
        depthAxisAlignment: CrossAxisAlignment3d.baseline,
        children: <Layout3d>[near, far],
      );
      laidOut(row);
      expect(near.offset.z, 0);
      expect(far.offset.z, 2);
      expect(row.size.depth, 3);
    });
  });

  group('the transform is untouched', () {
    test('a measured subtree still places its nodes where it did', () {
      final child = TestBox(const Size3d(2, 1, 1));
      final column = Column3d(
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        children: <Layout3d>[child, TestBox(const Size3d(5, 1, 1))],
      );
      laidOut(IntrinsicWidth3d(child: column));
      expect(child.node.localTransform, isA<Matrix4>());
      expect(translationOf(child), Offset3d.zero);
    });
  });
}
