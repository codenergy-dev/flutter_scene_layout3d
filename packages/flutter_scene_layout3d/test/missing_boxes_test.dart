// The boxes a component catalogue asks for by name: LimitedBox3d,
// UnconstrainedBox3d, OverflowBox3d, FractionallySizedBox3d, IndexedStack3d,
// AspectRatio3d, FittedBox3d, Table3d, CustomMultiChildLayout3d, Flow3d,
// LayoutBuilder3d and SliverPadding3d.

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'support.dart';

/// A leaf with a baseline of its own, for the table's baseline row.
class BaselineBox extends Layout3d {
  BaselineBox(this.preferred, this.baseline, {super.name});

  final Size3d preferred;
  final double baseline;

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      preferred.alongAxis(axis);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      preferred.alongAxis(axis);

  @override
  double? computeDistanceToActualBaseline(Axis3d axis) =>
      axis == Axis3d.vertical ? baseline : null;

  @override
  void performLayout() {
    size = constraints.constrain(preferred);
  }
}

/// A delegate that puts a bar across the top and gives the body the rest,
/// which is the arrangement a Scaffold3d wants.
class PanelDelegate extends MultiChildLayout3dDelegate {
  PanelDelegate({this.barHeight = 1.0});

  final double barHeight;

  /// The order the delegate asked for its children in.
  final List<Object> order = <Object>[];

  @override
  void performLayout(Size3d size) {
    order.clear();
    var top = 0.0;
    if (hasChild('bar')) {
      order.add('bar');
      final bar = layoutChild(
        'bar',
        Constraints3d(
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: barHeight,
          maxHeight: barHeight,
        ),
      );
      positionChild('bar', Offset3d.zero);
      top = bar.height;
    }
    if (hasChild('body')) {
      order.add('body');
      layoutChild(
        'body',
        Constraints3d.tight(Size3d(size.width, size.height - top, size.depth)),
      );
      positionChild('body', Offset3d(0, top, 0));
    }
  }

  @override
  bool shouldRelayout(PanelDelegate oldDelegate) =>
      oldDelegate.barHeight != barHeight;
}

/// A flow that puts each child a fixed step further along, optionally through
/// a scale.
class StepFlow extends Flow3dDelegate {
  StepFlow({this.step = 2.0, this.scale, this.skipLast = false, super.repaint});

  final double step;
  final double? scale;
  final bool skipLast;

  int passes = 0;

  @override
  void paintChildren(Flow3dPaintingContext context) {
    passes++;
    final count = skipLast ? context.childCount - 1 : context.childCount;
    for (var index = 0; index < count; index++) {
      context.paintChild(
        index,
        offset: Offset3d(index * step, 0, 0),
        transform: scale == null
            ? null
            : Matrix4.diagonal3Values(scale!, scale!, 1),
      );
    }
  }

  @override
  bool shouldRepaint(StepFlow oldDelegate) =>
      oldDelegate.step != step || oldDelegate.scale != scale;
}

/// A sliver of a fixed length, so a padding's arithmetic can be read off it.
class ProbeSliver extends Sliver3d {
  ProbeSliver(this.extent, {super.name});

  final double extent;

  SliverConstraints3d? window;

  @override
  void performSliverLayout() {
    final constraints = sliverConstraints;
    window = constraints;
    geometry = SliverGeometry3d(
      scrollExtent: extent,
      paintExtent: constraints.paintPortion(from: 0.0, to: extent),
      maxPaintExtent: extent,
      cacheExtent: constraints.cachePortion(from: 0.0, to: extent),
    );
  }
}

void main() {
  final tight10 = Constraints3d.tight(const Size3d(10, 10, 10));

  group('LimitedBox3d', () {
    test('caps an unbounded axis and leaves a bounded one alone', () {
      final child = TestBox(const Size3d(100, 100, 100));
      final limited = LimitedBox3d(
        maxWidth: 3,
        maxHeight: 4,
        maxDepth: 5,
        child: child,
      );
      laidOut(limited, constraints: const Constraints3d(maxHeight: 2));
      // Width and depth were unbounded, so the limits applied; the height was
      // bounded already, so the parent's 2 won.
      expect(child.size, const Size3d(3, 2, 5));
      expect(limited.size, const Size3d(3, 2, 5));
    });

    test('a limit never raises a minimum', () {
      final child = TestBox(const Size3d(1, 1, 1));
      laidOut(
        LimitedBox3d(maxWidth: 2, child: child),
        constraints: const Constraints3d(minWidth: 6),
      );
      expect(child.size.width, 6);
    });

    test('holds its intrinsics to the limit', () {
      final child = TestBox(const Size3d(100, 1, 1));
      final limited = LimitedBox3d(maxWidth: 3, child: child);
      laidOut(limited);
      expect(
        limited.getMaxIntrinsicExtent(Axis3d.horizontal, Size3d.infinite),
        3,
      );
      expect(
        limited.getMaxIntrinsicExtent(Axis3d.vertical, Size3d.infinite),
        1,
      );
    });

    test('with no child it is as small as the limits allow', () {
      final limited = LimitedBox3d(maxWidth: 3);
      laidOut(limited, constraints: const Constraints3d(minDepth: 1));
      expect(limited.size, const Size3d(0, 0, 1));
    });
  });

  group('UnconstrainedBox3d', () {
    test('hands the child unbounded room and reports what it can', () {
      final child = TestBox(const Size3d(20, 20, 20));
      final box = UnconstrainedBox3d(child: child);
      laidOut(box, constraints: tight10);
      expect(child.size, const Size3d(20, 20, 20));
      // The box itself still obeys its own constraints; the child overflows.
      expect(box.size, const Size3d(10, 10, 10));
    });

    test('keeps the axes named in constrainedAxes', () {
      final child = TestBox(const Size3d(20, 20, 20));
      laidOut(
        UnconstrainedBox3d(constrainedAxes: const {Axis3d.depth}, child: child),
        constraints: tight10,
      );
      expect(child.size, const Size3d(20, 20, 10));
    });

    test('aligns the child in the room it was given', () {
      final child = TestBox(const Size3d(2, 2, 2));
      laidOut(
        UnconstrainedBox3d(alignment: Alignment3d.topLeftFront, child: child),
        constraints: tight10,
      );
      expect(child.offset, Offset3d.zero);
    });
  });

  group('OverflowBox3d', () {
    test('replaces the bounds it names and fills the room it was given', () {
      final child = TestBox(const Size3d(50, 50, 50));
      final box = OverflowBox3d(maxWidth: 20, child: child);
      laidOut(box, constraints: tight10);
      expect(child.size.width, 20);
      expect(child.size.height, 10);
      expect(box.size, const Size3d(10, 10, 10));
      // Centred by default, so the overflow is symmetric.
      expect(child.offset.x, -5);
    });

    test('shrink-wraps an axis the parent left unbounded', () {
      final child = TestBox(const Size3d(3, 3, 3));
      final box = OverflowBox3d(child: child);
      laidOut(box);
      expect(box.size, const Size3d(3, 3, 3));
    });
  });

  group('FractionallySizedBox3d', () {
    test('sizes the child to a fraction of the room', () {
      final child = TestBox(const Size3d(100, 100, 100));
      final box = FractionallySizedBox3d(
        widthFactor: 0.5,
        heightFactor: 1.5,
        child: child,
      );
      laidOut(box, constraints: tight10);
      expect(child.size.width, 5);
      expect(child.size.height, 15);
      // Depth had no factor, so the child chose it inside the loosened room.
      expect(child.size.depth, 10);
      expect(box.size, const Size3d(10, 10, 10));
    });

    test('an axis with no factor is left to the child', () {
      final child = TestBox(const Size3d(2, 2, 2));
      final box = FractionallySizedBox3d(widthFactor: 0.5, child: child);
      laidOut(box, constraints: const Constraints3d(maxWidth: 8));
      expect(child.size, const Size3d(4, 2, 2));
      // Bounded on width so it fills; unbounded elsewhere so it wraps.
      expect(box.size, const Size3d(8, 2, 2));
    });

    test('refuses a factor on an unbounded axis, naming the fix', () {
      final box = FractionallySizedBox3d(
        widthFactor: 0.5,
        child: TestBox(const Size3d(2, 2, 2)),
      );
      expect(
        () => laidOut(box),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            contains('fraction of an unbounded extent'),
          ),
        ),
      );
    });
  });

  group('IndexedStack3d', () {
    test('lays every child out and shows one', () {
      final first = TestBox(const Size3d(2, 2, 1));
      final second = TestBox(const Size3d(4, 3, 1));
      final stack = IndexedStack3d(index: 1, children: [first, second]);
      laidOut(stack);

      expect(stack.size, const Size3d(4, 3, 1));
      expect(first.layoutCount, 1);
      expect(first.node.visible, isFalse);
      expect(second.node.visible, isTrue);
    });

    test('changing the index does not relayout', () {
      final first = TestBox(const Size3d(2, 2, 1));
      final second = TestBox(const Size3d(2, 2, 1));
      final stack = IndexedStack3d(children: [first, second]);
      final surface = laidOut(stack);
      expect(first.layoutCount, 1);

      stack.index = 1;
      surface.flush();

      expect(first.layoutCount, 1);
      expect(second.layoutCount, 1);
      expect(first.node.visible, isFalse);
      expect(second.node.visible, isTrue);
    });

    test('a hidden child is out of reach of a ray', () {
      final first = TestBox(const Size3d(4, 4, 1), pointable: true);
      final second = TestBox(const Size3d(4, 4, 1), pointable: true);
      final stack = IndexedStack3d(index: 0, children: [first, second]);
      final surface = laidOut(
        stack,
        constraints: Constraints3d.tight(const Size3d(4, 4, 1)),
      );

      final hit = surface.hitTestRay(rayAt(surface, const Offset3d(2, 2, 0)));
      expect(hit.target, same(first));
    });

    test('a null index hides everything and keeps the room', () {
      final child = TestBox(const Size3d(2, 2, 1));
      final stack = IndexedStack3d(index: null, children: [child]);
      laidOut(stack);
      expect(stack.size, const Size3d(2, 2, 1));
      expect(child.node.visible, isFalse);
    });
  });

  group('AspectRatio3d', () {
    test('derives the cross extent from a bounded main one', () {
      final child = TestBox(const Size3d(100, 100, 1));
      final box = AspectRatio3d(aspectRatio: 2, child: child);
      laidOut(box, constraints: const Constraints3d(maxWidth: 8));
      expect(box.size.width, 8);
      expect(box.size.height, 4);
      expect(child.size.width, 8);
      expect(child.size.height, 4);
    });

    test('derives the main extent when only the cross one is bounded', () {
      final box = AspectRatio3d(
        aspectRatio: 2,
        child: TestBox(const Size3d(1, 1, 1)),
      );
      laidOut(box, constraints: const Constraints3d(maxHeight: 3));
      expect(box.size.width, 6);
      expect(box.size.height, 3);
    });

    test('walks back inside the constraints when the ratio does not fit', () {
      final box = AspectRatio3d(
        aspectRatio: 2,
        child: TestBox(const Size3d(1, 1, 1)),
      );
      laidOut(
        box,
        constraints: const Constraints3d(maxWidth: 10, maxHeight: 2),
      );
      expect(box.size.height, 2);
      expect(box.size.width, 4);
    });

    test('names other axes, and leaves the third one to the child', () {
      final child = TestBox(const Size3d(9, 7, 9));
      final box = AspectRatio3d(
        aspectRatio: 2,
        relativeTo: Axis3d.depth,
        child: child,
      );
      laidOut(box, constraints: const Constraints3d(maxWidth: 4));
      expect(box.size.width, 4);
      expect(box.size.depth, 2);
      // The vertical axis was never spoken for.
      expect(box.size.height, 7);
    });

    test('answers an intrinsic query from the ratio alone', () {
      final child = TestBox(const Size3d(100, 100, 1));
      final box = AspectRatio3d(aspectRatio: 2, child: child);
      laidOut(box, constraints: const Constraints3d(maxWidth: 8));
      child.intrinsicQueries = 0;
      expect(
        box.getMaxIntrinsicExtent(
          Axis3d.horizontal,
          const Size3d(double.infinity, 3, double.infinity),
        ),
        6,
      );
      expect(child.intrinsicQueries, 0);
    });

    test('refuses two unbounded axes, naming the fix', () {
      final box = AspectRatio3d(
        aspectRatio: 2,
        child: TestBox(const Size3d(1, 1, 1)),
      );
      expect(
        () => laidOut(box),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            contains('no upper bound on either'),
          ),
        ),
      );
    });
  });

  group('FittedBox3d', () {
    test('lays the child out unbounded and scales it down to fit', () {
      final child = TestBox(const Size3d(20, 10, 0));
      final box = FittedBox3d(child: child);
      laidOut(box, constraints: Constraints3d.tight(const Size3d(10, 10, 0)));

      // The child never hears about the fit: it is laid out at its own size.
      expect(child.size, const Size3d(20, 10, 0));
      expect(box.size, const Size3d(10, 10, 0));
      expect(box.scale.x, 0.5);
      expect(box.scale.y, 0.5);
      // Contained and centred: half of 10 is 5 tall, so 2.5 down from the top.
      expect(box.childOrigin.y, 2.5);
    });

    test('fill scales each axis on its own', () {
      final child = TestBox(const Size3d(20, 10, 0));
      final box = FittedBox3d(fit: BoxFit3d.fill, child: child);
      laidOut(box, constraints: Constraints3d.tight(const Size3d(10, 20, 0)));
      expect(box.scale.x, 0.5);
      expect(box.scale.y, 2.0);
    });

    test('scaleDown never scales up', () {
      final box = FittedBox3d(
        fit: BoxFit3d.scaleDown,
        child: TestBox(const Size3d(2, 2, 0)),
      );
      laidOut(box, constraints: Constraints3d.tight(const Size3d(10, 10, 0)));
      expect(box.scale.x, 1.0);
    });

    test('a ray reaches the child where the viewer sees it', () {
      final child = TestBox(const Size3d(20, 20, 1), pointable: true);
      final box = FittedBox3d(child: child);
      final surface = laidOut(
        box,
        constraints: Constraints3d.tight(const Size3d(10, 10, 1)),
      );

      final hit = surface.hitTestRay(rayAt(surface, const Offset3d(1, 1, 0)));
      expect(hit.target, same(child));
      // Scaled by a half, so a point 1 into the box is 2 into the child.
      final local = hit.path.first.localPosition;
      expect(local.x, closeTo(2.0, 1e-6));
      expect(local.y, closeTo(2.0, 1e-6));
    });

    test('a ray outside the box reaches nothing', () {
      final child = TestBox(const Size3d(20, 20, 1), pointable: true);
      final surface = laidOut(
        Padding3d(
          padding: const EdgeInsets3d.all(2),
          child: FittedBox3d(child: child),
        ),
        constraints: Constraints3d.tight(const Size3d(14, 14, 1)),
      );

      final hit = surface.hitTestRay(rayAt(surface, const Offset3d(1, 1, 0)));
      expect(hit.target, isNull);
    });
  });

  group('Table3d', () {
    List<TestBox> cells(List<Size3d> sizes) =>
        sizes.map(TestBox.new).toList(growable: false);

    test('flex columns share the width evenly', () {
      final children = cells(const [
        Size3d(1, 1, 0),
        Size3d(1, 2, 0),
        Size3d(1, 1, 0),
        Size3d(1, 1, 0),
      ]);
      final table = Table3d(columnCount: 2, children: children);
      laidOut(table, constraints: const Constraints3d(maxWidth: 10));

      expect(children[0].size.width, 5);
      expect(children[1].size.width, 5);
      expect(children[1].offset.x, 5);
      // The first row is as tall as its tallest cell.
      expect(children[2].offset.y, 2);
      expect(table.size, const Size3d(10, 3, 0));
    });

    test('a fixed column keeps its width and the flex takes the rest', () {
      final children = cells(const [Size3d(1, 1, 0), Size3d(1, 1, 0)]);
      final table = Table3d(
        columnCount: 2,
        columnWidths: const {0: FixedColumnWidth3d(3)},
        children: children,
      );
      laidOut(table, constraints: const Constraints3d(maxWidth: 10));
      expect(children[0].size.width, 3);
      expect(children[1].size.width, 7);
    });

    test('an intrinsic column fits its widest cell', () {
      final children = cells(const [
        Size3d(2, 1, 0),
        Size3d(1, 1, 0),
        Size3d(4, 1, 0),
        Size3d(1, 1, 0),
      ]);
      final table = Table3d(
        columnCount: 2,
        columnWidths: const {0: IntrinsicColumnWidth3d()},
        children: children,
      );
      laidOut(table, constraints: const Constraints3d(maxWidth: 10));
      expect(children[0].size.width, 4);
      expect(children[1].size.width, 6);
    });

    test('spacing sits between the columns and the rows', () {
      final children = cells(const [
        Size3d(1, 1, 0),
        Size3d(1, 1, 0),
        Size3d(1, 1, 0),
        Size3d(1, 1, 0),
      ]);
      final table = Table3d(
        columnCount: 2,
        columnSpacing: 1,
        rowSpacing: 2,
        columnWidths: const {
          0: FixedColumnWidth3d(2),
          1: FixedColumnWidth3d(2),
        },
        children: children,
      );
      laidOut(table);
      expect(children[1].offset.x, 3);
      expect(children[2].offset.y, 3);
      expect(table.size.width, 5);
    });

    test('a short last row leaves its columns empty', () {
      final children = cells(const [
        Size3d(1, 1, 0),
        Size3d(1, 1, 0),
        Size3d(1, 1, 0),
      ]);
      final table = Table3d(columnCount: 2, children: children);
      laidOut(table, constraints: const Constraints3d(maxWidth: 4));
      expect(table.rowCount, 2);
      expect(table.cellAt(1, 1), isNull);
      expect(children[2].offset, const Offset3d(0, 1, 0));
    });

    test('vertical alignment places a short cell in its row', () {
      final children = cells(const [Size3d(1, 1, 0), Size3d(1, 3, 0)]);
      final table = Table3d(
        columnCount: 2,
        defaultVerticalAlignment: TableCellAlignment3d.middle,
        children: children,
      );
      laidOut(table, constraints: const Constraints3d(maxWidth: 4));
      expect(children[0].offset.y, 1);
    });

    test('fill stretches a cell to the height of its row', () {
      final children = cells(const [Size3d(1, 1, 0), Size3d(1, 3, 0)]);
      final table = Table3d(
        columnCount: 2,
        defaultVerticalAlignment: TableCellAlignment3d.fill,
        children: children,
      );
      laidOut(table, constraints: const Constraints3d(maxWidth: 4));
      expect(children[0].size.height, 3);
      expect(children[0].layoutCount, 2);
      // The cell that already filled the row is not laid out twice.
      expect(children[1].layoutCount, 1);
    });

    test('baseline alignment puts the cells on one line', () {
      final tall = BaselineBox(const Size3d(1, 4, 0), 3);
      final short = BaselineBox(const Size3d(1, 2, 0), 1);
      final table = Table3d(
        columnCount: 2,
        defaultVerticalAlignment: TableCellAlignment3d.baseline,
        children: [tall, short],
      );
      laidOut(table, constraints: const Constraints3d(maxWidth: 4));
      expect(tall.offset.y, 0);
      expect(short.offset.y, 2);
      // Deepest ascent plus deepest descent, which is more than either cell.
      expect(table.size.height, 4);
    });

    test('depth is an alignment axis, not a wrapping one', () {
      final thin = TestBox(const Size3d(1, 1, 1));
      final thick = TestBox(const Size3d(1, 1, 3));
      final table = Table3d(columnCount: 2, children: [thin, thick]);
      laidOut(table, constraints: const Constraints3d(maxWidth: 4));
      expect(table.size.depth, 3);
      expect(thin.offset.z, 1);
      expect(thick.offset.z, 0);
    });

    test('its width intrinsic is the sum of its columns', () {
      final table = Table3d(
        columnCount: 2,
        columnWidths: const {
          0: FixedColumnWidth3d(2),
          1: FixedColumnWidth3d(3),
        },
        columnSpacing: 1,
        children: [
          TestBox(const Size3d(1, 1, 0)),
          TestBox(const Size3d(1, 1, 0)),
        ],
      );
      laidOut(table);
      expect(
        table.getMaxIntrinsicExtent(Axis3d.horizontal, Size3d.infinite),
        6,
      );
    });
  });

  group('CustomMultiChildLayout3d', () {
    test('the delegate arranges the children it names', () {
      final bar = TestBox(const Size3d(1, 1, 1));
      final body = TestBox(const Size3d(1, 1, 1));
      final delegate = PanelDelegate();
      final layout = CustomMultiChildLayout3d(
        delegate: delegate,
        children: [
          LayoutId3d(id: 'bar', child: bar),
          LayoutId3d(id: 'body', child: body),
        ],
      );
      laidOut(layout, constraints: tight10);

      expect(layout.size, const Size3d(10, 10, 10));
      // The delegate said nothing about depth, so the cell chose its own.
      expect(bar.size, const Size3d(10, 1, 1));
      expect(body.size, const Size3d(10, 9, 10));
      expect(body.parent!.offset, const Offset3d(0, 1, 0));
      // Measured in the order the delegate asked for, not in child order.
      expect(delegate.order, <Object>['bar', 'body']);
    });

    test('hasChild reports what the delegate was given', () {
      final delegate = PanelDelegate();
      final body = TestBox(const Size3d(1, 1, 1));
      final layout = CustomMultiChildLayout3d(
        delegate: delegate,
        children: [LayoutId3d(id: 'body', child: body)],
      );
      // The body takes the whole panel when hasChild('bar') says there is no
      // bar, rather than the delegate asking for a child that is not there.
      laidOut(layout, constraints: tight10);
      expect(body.size.height, 10);
      expect(delegate.order, <Object>['body']);
    });

    test('a delegate that skips a child is refused', () {
      final layout = CustomMultiChildLayout3d(
        delegate: PanelDelegate(),
        children: [
          LayoutId3d(id: 'bar', child: TestBox(const Size3d(1, 1, 1))),
          LayoutId3d(id: 'body', child: TestBox(const Size3d(1, 1, 1))),
          LayoutId3d(id: 'extra', child: TestBox(const Size3d(1, 1, 1))),
        ],
      );
      expect(
        () => laidOut(layout, constraints: tight10),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            contains('did not lay out extra'),
          ),
        ),
      );
    });

    test('a new delegate of the same type relayouts only when it says so', () {
      final bar = TestBox(const Size3d(1, 1, 1));
      final layout = CustomMultiChildLayout3d(
        delegate: PanelDelegate(),
        children: [
          LayoutId3d(id: 'bar', child: bar),
          LayoutId3d(id: 'body', child: TestBox(const Size3d(1, 1, 1))),
        ],
      );
      final surface = laidOut(layout, constraints: tight10);
      expect(bar.layoutCount, 1);

      layout.delegate = PanelDelegate();
      surface.flush();
      expect(bar.layoutCount, 1);

      layout.delegate = PanelDelegate(barHeight: 2);
      surface.flush();
      expect(bar.layoutCount, 2);
      expect(bar.size.height, 2);
    });

    test('its intrinsics come from the delegate, not from the children', () {
      final child = TestBox(const Size3d(1, 1, 1));
      final layout = CustomMultiChildLayout3d(
        delegate: PanelDelegate(),
        children: [
          LayoutId3d(id: 'bar', child: child),
          LayoutId3d(id: 'body', child: TestBox(const Size3d(1, 1, 1))),
        ],
      );
      laidOut(layout, constraints: tight10);
      child.intrinsicQueries = 0;
      expect(
        layout.getMaxIntrinsicExtent(
          Axis3d.horizontal,
          const Size3d(double.infinity, 4, double.infinity),
        ),
        0,
      );
      expect(child.intrinsicQueries, 0);
    });
  });

  group('Flow3d', () {
    test('places children by node transform, not by layout', () {
      final children = [
        TestBox(const Size3d(1, 1, 1)),
        TestBox(const Size3d(1, 1, 1)),
      ];
      final flow = Flow3d(delegate: StepFlow(), children: children);
      laidOut(flow, constraints: tight10);

      // Every child's box is at the origin corner...
      expect(children[1].offset, Offset3d.zero);
      // ...and the geometry is where the delegate put it.
      expect(children[1].nodeOffset, const Offset3d(2, 0, 0));
      expect(translationOf(children[1]), const Offset3d(2, 0, 0));
    });

    test('a repaint re-places the children without laying anything out', () {
      final children = [TestBox(const Size3d(1, 1, 1))];
      final repaint = ChangeNotifier();
      final delegate = StepFlow(repaint: repaint);
      final flow = Flow3d(delegate: delegate, children: children);
      laidOut(flow, constraints: tight10);
      expect(delegate.passes, 1);
      expect(children.first.layoutCount, 1);

      repaint.notifyListeners();

      expect(delegate.passes, 2);
      expect(children.first.layoutCount, 1);
      repaint.dispose();
    });

    test('a child the delegate left out is hidden', () {
      final children = [
        TestBox(const Size3d(1, 1, 1)),
        TestBox(const Size3d(1, 1, 1)),
      ];
      final flow = Flow3d(
        delegate: StepFlow(skipLast: true),
        children: children,
      );
      laidOut(flow, constraints: tight10);
      expect(children[0].node.visible, isTrue);
      expect(children[1].node.visible, isFalse);
    });

    test('a ray follows the geometry, transform and all', () {
      final children = [
        TestBox(const Size3d(2, 2, 1), pointable: true),
        TestBox(const Size3d(2, 2, 1), pointable: true),
      ];
      final flow = Flow3d(delegate: StepFlow(step: 4), children: children);
      final surface = laidOut(
        flow,
        constraints: Constraints3d.tight(const Size3d(10, 10, 1)),
      );

      expect(
        surface.hitTestRay(rayAt(surface, const Offset3d(1, 1, 0))).target,
        same(children[0]),
      );
      expect(
        surface.hitTestRay(rayAt(surface, const Offset3d(5, 1, 0))).target,
        same(children[1]),
      );
      // Between them there is nothing, because the boxes moved with the
      // geometry rather than staying stacked at the origin.
      expect(
        surface.hitTestRay(rayAt(surface, const Offset3d(3, 1, 0))).target,
        isNull,
      );
    });

    test('a ray goes through a scale the delegate applied', () {
      final child = TestBox(const Size3d(2, 2, 1), pointable: true);
      final flow = Flow3d(delegate: StepFlow(scale: 2), children: [child]);
      final surface = laidOut(
        flow,
        constraints: Constraints3d.tight(const Size3d(10, 10, 1)),
      );

      final hit = surface.hitTestRay(rayAt(surface, const Offset3d(3, 3, 0)));
      expect(hit.target, same(child));
      expect(hit.path.first.localPosition.x, closeTo(1.5, 1e-6));
    });
  });

  group('LayoutBuilder3d', () {
    test('builds from the constraints it was given', () {
      Constraints3d? seen;
      final builder = LayoutBuilder3d(
        builder: (constraints) {
          seen = constraints;
          return TestBox(Size3d(constraints.maxWidth > 5 ? 4.0 : 1.0, 1, 1));
        },
      );
      laidOut(builder, constraints: const Constraints3d(maxWidth: 10));

      expect(seen!.maxWidth, 10);
      expect(builder.size, const Size3d(4, 1, 1));
    });

    test('rebuilds when the constraints change, and not otherwise', () {
      var builds = 0;
      final builder = LayoutBuilder3d(
        builder: (constraints) {
          builds++;
          return TestBox(const Size3d(1, 1, 1));
        },
      );
      final surface = laidOut(builder, constraints: tight10);
      expect(builds, 1);

      surface.flush();
      expect(builds, 1);

      surface.configuration = Constraints3d.tight(const Size3d(4, 4, 4));
      surface.flush();
      expect(builds, 2);
    });

    test('disposes the subtree it replaced', () {
      var wide = true;
      final built = <TestBox>[];
      final builder = LayoutBuilder3d(
        builder: (constraints) {
          final box = TestBox(Size3d(wide ? 4.0 : 1.0, 1, 1));
          built.add(box);
          return box;
        },
      );
      final surface = laidOut(builder, constraints: tight10);
      wide = false;
      surface.configuration = Constraints3d.tight(const Size3d(4, 4, 4));
      surface.flush();

      expect(built, hasLength(2));
      expect(built.first.debugDisposed, isTrue);
      expect(built.last.debugDisposed, isFalse);
    });

    test('refuses an intrinsic query, naming the fix', () {
      final builder = LayoutBuilder3d(
        builder: (constraints) => TestBox(const Size3d(1, 1, 1)),
      );
      laidOut(builder, constraints: tight10);
      expect(
        () => builder.getMaxIntrinsicExtent(Axis3d.horizontal, Size3d.infinite),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            contains('function of the constraints'),
          ),
        ),
      );
    });
  });

  group('SliverPadding3d', () {
    test('adds its insets to the scroll extent and moves the child', () {
      final probe = ProbeSliver(4);
      final view = CustomScrollView3d(
        slivers: [
          SliverPadding3d(
            padding: const EdgeInsets3d.only(top: 1, bottom: 2, left: 0.5),
            sliver: probe,
          ),
        ],
      );
      laidOut(view, constraints: Constraints3d.tight(const Size3d(4, 10, 2)));

      expect(view.slivers.first.geometry.scrollExtent, 7);
      expect(view.slivers.first.geometry.paintExtent, 7);
      expect(probe.offset.y, 1);
      expect(probe.offset.x, 0.5);
      // The cross axis is narrowed by the insets across it.
      expect(probe.window!.crossAxisExtent, 3.5);
    });

    test('the leading inset scrolls away', () {
      final probe = ProbeSliver(20);
      final scroll = Scroll3dController();
      final view = CustomScrollView3d(
        controller: scroll,
        slivers: [
          SliverPadding3d(
            padding: const EdgeInsets3d.only(top: 2),
            sliver: probe,
          ),
        ],
      );
      final surface = laidOut(
        view,
        constraints: Constraints3d.tight(const Size3d(4, 10, 2)),
      );

      scroll.jumpTo(5);
      surface.flush();

      // Two of the five scrolled through were the inset, so the child has
      // scrolled three of its own.
      expect(probe.window!.scrollOffset, 3);
      expect(probe.offset.y, 0);
      scroll.dispose();
    });

    test('an empty padding is still a gap', () {
      final view = CustomScrollView3d(
        slivers: [SliverPadding3d(padding: const EdgeInsets3d.all(1))],
      );
      laidOut(view, constraints: Constraints3d.tight(const Size3d(4, 10, 2)));
      expect(view.slivers.first.geometry.scrollExtent, 2);
    });
  });

  group('PageView3d', () {
    List<TestBox> pages(int count) => List.generate(
      count,
      (index) => TestBox(const Size3d(1, 1, 1), name: 'page$index'),
    );

    test('every page is as long as the window', () {
      final children = pages(3);
      final view = PageView3d(children: children);
      laidOut(view, constraints: Constraints3d.tight(const Size3d(6, 4, 1)));

      expect(view.pageExtent, 6);
      for (final page in children) {
        expect(page.size.width, 6);
        // Stretched across, which is what a page means.
        expect(page.size.height, 4);
      }
      expect(children[1].offset.x, 6);
      expect(view.controller.contentExtent, 18);
    });

    test('a resize re-pages', () {
      final children = pages(3);
      final view = PageView3d(children: children);
      final surface = laidOut(
        view,
        constraints: Constraints3d.tight(const Size3d(6, 4, 1)),
      );

      surface.configuration = Constraints3d.tight(const Size3d(10, 4, 1));
      surface.flush();

      expect(view.pageExtent, 10);
      expect(children[1].offset.x, 10);
    });

    test('page counts the offset in pages, fractionally', () {
      final view = PageView3d(children: pages(3));
      final surface = laidOut(
        view,
        constraints: Constraints3d.tight(const Size3d(6, 4, 1)),
      );

      view.controller.jumpTo(9);
      surface.flush();
      expect(view.page, 1.5);

      view.jumpToPage(2);
      surface.flush();
      expect(view.page, 2);
      expect(view.controller.offset, 12);
    });

    test('it needs a bounded window, and says so', () {
      final view = PageView3d(children: pages(2));
      expect(
        () => laidOut(view, constraints: const Constraints3d(maxHeight: 4)),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            contains('needs a bounded extent'),
          ),
        ),
      );
    });

    test('a view that makes its own position gives it page physics', () {
      final view = PageView3d(children: pages(2));
      expect(view.controller.physics, isA<PageScroll3dPhysics>());

      final mine = Scroll3dController();
      final borrowed = PageView3d(controller: mine, children: pages(2));
      expect(borrowed.controller.physics, isA<ClampingScroll3dPhysics>());
      borrowed.dispose();
      mine.dispose();
    });
  });

  group('PageScroll3dPhysics', () {
    Scroll3dController positioned({
      required double offset,
      double pages = 3,
      double window = 6,
    }) {
      final controller =
          Scroll3dController(
            initialOffset: offset,
            physics: PageScroll3dPhysics(),
          )..applyViewportMetrics(
            maxScrollExtent: window * (pages - 1),
            viewportExtent: window,
            unitsPerLogicalPixel: 1,
          );
      return controller;
    }

    test('a slow release settles on the page it is mostly on', () {
      final physics = PageScroll3dPhysics();
      final controller = positioned(offset: 7);
      expect(physics.targetOffset(controller, 0), 6);
      expect(physics.pageOf(controller), closeTo(7 / 6, 1e-9));

      final further = positioned(offset: 10);
      expect(physics.targetOffset(further, 0), 12);
      controller.dispose();
      further.dispose();
    });

    test('a flick turns the page however short it was', () {
      final physics = PageScroll3dPhysics();
      final controller = positioned(offset: 6.2);
      // Barely moved, but thrown forward: the next page.
      expect(physics.targetOffset(controller, 400), 12);
      // Thrown backward from the same place: the one behind.
      expect(physics.targetOffset(controller, -400), 6);
      controller.dispose();
    });

    test('it never settles outside the range', () {
      final physics = PageScroll3dPhysics();
      final controller = positioned(offset: 12);
      expect(physics.targetOffset(controller, 400), 12);
      controller.dispose();
    });

    test('a stride of its own snaps something that is not a page', () {
      final physics = PageScroll3dPhysics(pageExtent: 2);
      final controller =
          Scroll3dController(initialOffset: 5.2, physics: physics)
            ..applyViewportMetrics(
              maxScrollExtent: 100,
              viewportExtent: 6,
              unitsPerLogicalPixel: 1,
            );
      expect(physics.targetOffset(controller, 0), 6);
      controller.dispose();
    });
  });
}
