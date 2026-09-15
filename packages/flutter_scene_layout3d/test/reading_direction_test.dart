// Reading direction: start and end, a row that runs from the right, a column
// that runs from the bottom, and the ambient Directionality reaching a scene.
//
// Every expected position below was worked by hand from Flutter's own
// RenderFlex, RenderWrap and RenderTable at the SDK this repository resolves:
// a flipped line is walked from its top-left child, which is its last.

import 'package:flutter/widgets.dart'
    show Directionality, TextDirection, VerticalDirection, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support.dart';

const rtl = TextDirection.rtl;
const ltr = TextDirection.ltr;

void main() {
  final tight10 = Constraints3d.tight(const Size3d(10, 10, 10));

  List<TestBox> boxes(List<double> widths, {double height = 2}) => [
    for (final width in widths) TestBox(Size3d(width, height, 2)),
  ];

  group('EdgeInsetsGeometry3d', () {
    const directional = EdgeInsetsDirectional3d.only(
      start: 1,
      top: 2,
      end: 3,
      bottom: 4,
      front: 5,
      back: 6,
    );

    test(
      'start is the left in left to right and the right in right to left',
      () {
        expect(
          directional.resolve(ltr),
          const EdgeInsets3d.fromLTRBFB(1, 2, 3, 4, 5, 6),
        );
        expect(
          directional.resolve(rtl),
          const EdgeInsets3d.fromLTRBFB(3, 2, 1, 4, 5, 6),
        );
      },
    );

    test('no direction reads left to right, where Flutter would assert', () {
      expect(directional.resolve(null), directional.resolve(ltr));
    });

    test('front and back are physical in every direction', () {
      final resolved = directional.resolve(rtl);
      expect(resolved.front, 5);
      expect(resolved.back, 6);
    });

    test('a physical inset ignores the direction', () {
      const physical = EdgeInsets3d.only(left: 1);
      expect(identical(physical.resolve(rtl), physical), isTrue);
    });

    test('the totals do not depend on the direction', () {
      expect(directional.horizontal, 4);
      expect(directional.vertical, 6);
      expect(directional.depth, 11);
      expect(directional.collapsedSize, const Size3d(4, 6, 11));
      expect(
        directional.inflateSize(const Size3d(1, 1, 1)),
        const Size3d(5, 7, 12),
      );
    });

    test('kinds compare by their sides', () {
      expect(EdgeInsets3d.zero, EdgeInsetsDirectional3d.zero);
      expect(EdgeInsets3d.zero.hashCode, EdgeInsetsDirectional3d.zero.hashCode);
      expect(
        const EdgeInsets3d.only(left: 1),
        isNot(const EdgeInsetsDirectional3d.only(start: 1)),
      );
    });

    test('adding two of a kind keeps the kind', () {
      expect(
        const EdgeInsets3d.only(left: 1).add(const EdgeInsets3d.only(left: 2)),
        isA<EdgeInsets3d>(),
      );
      expect(
        const EdgeInsetsDirectional3d.only(
          start: 1,
        ).add(const EdgeInsetsDirectional3d.only(end: 2)),
        const EdgeInsetsDirectional3d.only(start: 1, end: 2),
      );
    });

    test('adding a physical to a directional inset waits for a direction', () {
      final mixed = const EdgeInsets3d.only(
        left: 1,
        top: 1,
      ).add(const EdgeInsetsDirectional3d.only(start: 2, back: 1));
      expect(mixed, isNot(isA<EdgeInsets3d>()));
      expect(mixed, isNot(isA<EdgeInsetsDirectional3d>()));
      expect(
        mixed.resolve(ltr),
        const EdgeInsets3d.only(left: 3, top: 1, back: 1),
      );
      expect(
        mixed.resolve(rtl),
        const EdgeInsets3d.only(left: 1, right: 2, top: 1, back: 1),
      );
      expect(mixed.horizontal, 3);
    });

    test('lerp keeps the kind when it can and mixes when it cannot', () {
      expect(
        EdgeInsetsGeometry3d.lerp(
          const EdgeInsetsDirectional3d.only(start: 0),
          const EdgeInsetsDirectional3d.only(start: 4),
          0.5,
        ),
        const EdgeInsetsDirectional3d.only(start: 2),
      );
      final halfway = EdgeInsetsGeometry3d.lerp(
        const EdgeInsets3d.only(left: 4),
        const EdgeInsetsDirectional3d.only(start: 4),
        0.5,
      )!;
      expect(halfway.resolve(ltr), const EdgeInsets3d.only(left: 4));
      expect(halfway.resolve(rtl), const EdgeInsets3d.only(left: 2, right: 2));
      expect(
        EdgeInsetsGeometry3d.lerp(null, const EdgeInsets3d.all(2), 0.5),
        const EdgeInsets3d.all(1),
      );
    });

    test('the tween interpolates across kinds', () {
      final tween = EdgeInsetsGeometry3dTween(
        begin: const EdgeInsets3d.only(right: 2),
        end: const EdgeInsetsDirectional3d.only(end: 4),
      );
      expect(tween.transform(0.5).resolve(ltr).right, 3);
      expect(tween.transform(0.5).resolve(rtl).right, 1);
      expect(tween.transform(0.5).resolve(rtl).left, 2);
    });

    test('a dp inset in world units is still the kind it was', () {
      const metrics = Layout3dMetrics(unitsPerLogicalPixel: 0.01);
      final converted = metrics.dpInsets(
        const EdgeInsetsDirectional3d.only(start: 16, end: 24),
      );
      expect(converted, isA<EdgeInsetsDirectional3d>());
      expect(converted.start, closeTo(0.16, 1e-12));
      expect(converted.end, closeTo(0.24, 1e-12));
      // The physical kind keeps its static type, so existing readers compile.
      expect(
        metrics.dpInsets(const EdgeInsets3d.all(10)).left,
        closeTo(0.1, 1e-12),
      );
    });
  });

  group('AlignmentGeometry3d', () {
    test('start is -1 at the reading direction\'s first side', () {
      expect(AlignmentDirectional3d.topStart.resolve(ltr), Alignment3d.topLeft);
      expect(
        AlignmentDirectional3d.topStart.resolve(rtl),
        Alignment3d.topRight,
      );
      expect(
        AlignmentDirectional3d.centerEnd.resolve(rtl),
        Alignment3d.centerLeft,
      );
      expect(
        AlignmentDirectional3d.topStartFront.resolve(rtl),
        const Alignment3d(1, -1, -1),
      );
      expect(
        AlignmentDirectional3d.bottomEnd.resolve(null),
        Alignment3d.bottomRight,
      );
    });

    test('kinds compare by their components', () {
      expect(Alignment3d.center, AlignmentDirectional3d.center);
      expect(Alignment3d.topLeft, isNot(AlignmentDirectional3d.topStart));
    });

    test('a mixed alignment resolves both parts', () {
      final mixed = const Alignment3d(
        0.5,
        0,
        -1,
      ).add(const AlignmentDirectional3d(0.25, 1, 0));
      expect(mixed.resolve(ltr), const Alignment3d(0.75, 1, -1));
      expect(mixed.resolve(rtl), const Alignment3d(0.25, 1, -1));
    });

    test('lerp and the tween cross kinds', () {
      final tween = AlignmentGeometry3dTween(
        begin: Alignment3d.centerLeft,
        end: AlignmentDirectional3d.centerStart,
      );
      expect(tween.transform(0.5).resolve(ltr), Alignment3d.centerLeft);
      expect(tween.transform(0.5).resolve(rtl), Alignment3d.center);
      expect(
        AlignmentGeometry3d.lerp(
          AlignmentDirectional3d.topStart,
          AlignmentDirectional3d.topEnd,
          0.5,
        ),
        AlignmentDirectional3d.topCenter,
      );
    });
  });

  group('Row3d in right to left', () {
    test('the first child is at the right, and start packs to the right', () {
      final children = boxes([2, 3]);
      laidOut(
        Row3d(textDirection: rtl, children: children),
        constraints: tight10,
      );
      expect(children[0].offset.x, 8);
      expect(children[1].offset.x, 5);
    });

    test('end packs to the left', () {
      final children = boxes([2, 3]);
      laidOut(
        Row3d(
          textDirection: rtl,
          mainAxisAlignment: MainAxisAlignment3d.end,
          children: children,
        ),
        constraints: tight10,
      );
      expect(children[1].offset.x, 0);
      expect(children[0].offset.x, 3);
    });

    test('spaceBetween reverses the order and keeps the gaps', () {
      final children = boxes([2, 2, 2]);
      laidOut(
        Row3d(
          textDirection: rtl,
          mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
          children: children,
        ),
        constraints: tight10,
      );
      expect(children.map((child) => child.offset.x), [8, 4, 0]);
    });

    test('a lone child under spaceBetween starts, at the right', () {
      final children = boxes([2]);
      laidOut(
        Row3d(
          textDirection: rtl,
          mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
          children: children,
        ),
        constraints: tight10,
      );
      expect(children[0].offset.x, 8);
    });

    test('spacing sits between the children the same way', () {
      final children = boxes([2, 2]);
      laidOut(
        Row3d(textDirection: rtl, spacing: 1, children: children),
        constraints: tight10,
      );
      expect(children[0].offset.x, 8);
      expect(children[1].offset.x, 5);
    });

    test('an overflowing row keeps its last child at the left edge', () {
      // Flutter's walk, not a mirror: with no free space the leading gap is
      // zero, so the first child is pushed out past the right.
      final children = boxes([6, 6]);
      final row = Row3d(textDirection: rtl, children: children);
      laidOut(row, constraints: tight10);
      expect(children[1].offset.x, 0);
      expect(children[0].offset.x, 6);
      expect(row.debugOverflow.width, 2);
    });

    test('no direction is left to right', () {
      final children = boxes([2, 3]);
      laidOut(Row3d(children: children), constraints: tight10);
      expect(children[0].offset.x, 0);
      expect(children[1].offset.x, 2);
    });

    test('changing the direction lays the line out again', () {
      final children = boxes([2, 3]);
      final row = Row3d(children: children);
      final surface = laidOut(row, constraints: tight10);
      row.textDirection = rtl;
      expect(row.needsLayout, isTrue);
      surface.flush();
      expect(children[0].offset.x, 8);
    });

    test('verticalDirection up puts the cross start at the bottom', () {
      final children = boxes([2]);
      laidOut(
        Row3d(
          verticalDirection: VerticalDirection.up,
          crossAxisAlignment: CrossAxisAlignment3d.start,
          children: children,
        ),
        constraints: tight10,
      );
      expect(children[0].offset.y, 8);
    });

    test('the depth axis never flips', () {
      final children = boxes([2]);
      laidOut(
        Row3d(
          textDirection: rtl,
          verticalDirection: VerticalDirection.up,
          children: children,
        ),
        constraints: tight10,
      );
      // The second cross axis defaults to the front, and front is where the
      // viewer is in every language.
      expect(children[0].offset.z, 0);
    });
  });

  group('Column3d', () {
    test('verticalDirection up puts the first child at the bottom', () {
      final children = boxes([2, 2]);
      laidOut(
        Column3d(verticalDirection: VerticalDirection.up, children: children),
        constraints: tight10,
      );
      expect(children[0].offset.y, 8);
      expect(children[1].offset.y, 6);
    });

    test('in right to left the cross start is the right edge', () {
      for (final (alignment, x) in [
        (CrossAxisAlignment3d.start, 8.0),
        (CrossAxisAlignment3d.end, 0.0),
        (CrossAxisAlignment3d.center, 4.0),
        (CrossAxisAlignment3d.stretch, 0.0),
      ]) {
        final children = boxes([2]);
        laidOut(
          Column3d(
            textDirection: rtl,
            crossAxisAlignment: alignment,
            children: children,
          ),
          constraints: tight10,
        );
        expect(children[0].offset.x, x, reason: '$alignment');
      }
    });

    test('the main axis ignores the text direction', () {
      final children = boxes([2, 2]);
      laidOut(
        Column3d(textDirection: rtl, children: children),
        constraints: tight10,
      );
      expect(children[0].offset.y, 0);
      expect(children[1].offset.y, 2);
    });
  });

  test('a Depth3d keeps its order and flips both of its cross axes', () {
    final children = [
      TestBox(const Size3d(2, 2, 2)),
      TestBox(const Size3d(2, 2, 2)),
    ];
    laidOut(
      Depth3d(
        textDirection: rtl,
        verticalDirection: VerticalDirection.up,
        crossAxisAlignment: CrossAxisAlignment3d.start,
        depthAxisAlignment: CrossAxisAlignment3d.start,
        children: children,
      ),
      constraints: tight10,
    );
    expect(children[0].offset, const Offset3d(8, 8, 0));
    expect(children[1].offset, const Offset3d(8, 8, 2));
  });

  group('Wrap3d', () {
    // Three 4-wide children in 10: two share the first run, one starts the
    // second.
    List<TestBox> three() => [
      for (var i = 0; i < 3; i++) TestBox(const Size3d(4, 1, 1)),
    ];

    test('in right to left each run starts at the right', () {
      final children = three();
      laidOut(
        Wrap3d(textDirection: rtl, children: children),
        constraints: const Constraints3d(
          minWidth: 10,
          maxWidth: 10,
          maxHeight: 10,
          maxDepth: 10,
        ),
      );
      expect(children[0].offset, const Offset3d(6, 0, 0));
      expect(children[1].offset, const Offset3d(2, 0, 0));
      expect(children[2].offset, const Offset3d(6, 1, 0));
    });

    test('which children share a run does not change', () {
      final ltrChildren = three();
      final rtlChildren = three();
      const room = Constraints3d(maxWidth: 10, maxHeight: 10, maxDepth: 10);
      laidOut(Wrap3d(children: ltrChildren), constraints: room);
      laidOut(
        Wrap3d(textDirection: rtl, children: rtlChildren),
        constraints: room,
      );
      for (var i = 0; i < 3; i++) {
        expect(rtlChildren[i].offset.y, ltrChildren[i].offset.y);
      }
    });

    test('verticalDirection up stacks the runs from the bottom', () {
      final children = three();
      laidOut(
        Wrap3d(verticalDirection: VerticalDirection.up, children: children),
        constraints: tight10,
      );
      expect(children[2].offset.y, 8);
      expect(children[0].offset.y, 9);
      expect(children[1].offset.y, 9);
    });

    test('the cross alignment trades start for end on a flipped axis', () {
      final short = TestBox(const Size3d(2, 1, 1));
      final tall = TestBox(const Size3d(2, 3, 1));
      laidOut(
        Wrap3d(
          verticalDirection: VerticalDirection.up,
          crossAxisAlignment: WrapCrossAlignment3d.start,
          children: [short, tall],
        ),
        constraints: const Constraints3d(
          maxWidth: 10,
          maxHeight: 10,
          maxDepth: 10,
        ),
      );
      expect(short.offset.y, 2);
      expect(tall.offset.y, 0);
    });
  });

  test('a Table3d puts its first column at the right in right to left', () {
    final cells = [
      TestBox(const Size3d(1, 1, 1)),
      TestBox(const Size3d(1, 1, 1)),
    ];
    laidOut(
      Table3d(
        columnCount: 2,
        textDirection: rtl,
        columnWidths: const {
          0: FixedColumnWidth3d(2),
          1: FixedColumnWidth3d(3),
        },
        children: cells,
      ),
    );
    expect(cells[0].offset.x, 3);
    expect(cells[1].offset.x, 0);
  });

  group('boxes that take a geometry', () {
    test('Padding3d resolves a directional padding in its direction', () {
      final child = TestBox(const Size3d(1, 1, 1));
      final padding = Padding3d(
        padding: const EdgeInsetsDirectional3d.only(start: 1, end: 2),
        textDirection: rtl,
        child: child,
      );
      laidOut(padding);
      expect(child.offset.x, 2);
      expect(padding.size.width, 4);
    });

    test('a physical padding does not relayout for a new direction', () {
      final padding = Padding3d(
        padding: const EdgeInsets3d.only(left: 1),
        child: TestBox(const Size3d(1, 1, 1)),
      );
      laidOut(padding);
      padding.textDirection = rtl;
      expect(padding.needsLayout, isFalse);
    });

    test('a directional padding does', () {
      final padding = Padding3d(
        padding: const EdgeInsetsDirectional3d.only(start: 1),
        child: TestBox(const Size3d(1, 1, 1)),
      );
      final surface = laidOut(padding);
      padding.textDirection = rtl;
      expect(padding.needsLayout, isTrue);
      surface.flush();
      expect(padding.child!.offset.x, 0);
    });

    test('Align3d, Stack3d and FittedBox3d place at the start', () {
      final aligned = TestBox(const Size3d(2, 2, 2));
      laidOut(
        Align3d(
          alignment: AlignmentDirectional3d.centerStart,
          textDirection: rtl,
          child: aligned,
        ),
        constraints: tight10,
      );
      expect(aligned.offset.x, 8);

      final stacked = TestBox(const Size3d(2, 2, 2));
      laidOut(
        Stack3d(
          alignment: AlignmentDirectional3d.topStartFront,
          textDirection: rtl,
          children: [stacked],
        ),
        constraints: tight10,
      );
      expect(stacked.offset, const Offset3d(8, 0, 0));

      final unconstrained = TestBox(const Size3d(2, 2, 2));
      laidOut(
        UnconstrainedBox3d(
          alignment: AlignmentDirectional3d.centerEnd,
          textDirection: rtl,
          child: unconstrained,
        ),
        constraints: tight10,
      );
      expect(unconstrained.offset.x, 0);
    });

    test('Positioned3d.directional pins start to the right', () {
      final pinned = TestBox(const Size3d(2, 2, 2));
      final positioned = Positioned3d.directional(
        textDirection: rtl,
        start: 1,
        width: 3,
        child: pinned,
      );
      expect(positioned.right, 1);
      expect(positioned.left, isNull);
      laidOut(
        Stack3d(children: [TestBox(const Size3d(10, 10, 10)), positioned]),
      );
      expect(positioned.offset.x, 6);
    });

    test('Container3d resolves its margin, padding and alignment together', () {
      final child = TestBox(const Size3d(2, 2, 2));
      laidOut(
        Container3d(
          margin: const EdgeInsetsDirectional3d.only(start: 1),
          padding: const EdgeInsets3d.only(
            left: 1,
          ).add(const EdgeInsetsDirectional3d.only(start: 2)),
          alignment: AlignmentDirectional3d.centerStart,
          textDirection: rtl,
          child: child,
        ),
        constraints: tight10,
      );
      // Margin 1 on the right, padding 1 on the left and 2 on the right: the
      // content box runs from 1 to 6, and its start is the right.
      expect(child.offset.x, 5);
    });

    test('Transform3d pivots around the start', () {
      final transform = Transform3d.scale(
        scale: Vector3(2, 1, 1),
        alignment: AlignmentDirectional3d.centerStart,
        textDirection: rtl,
        child: TestBox(const Size3d(10, 10, 10)),
      );
      laidOut(transform);
      // Pivoting at the right edge, x = 10, a doubling moves the origin to -10.
      expect(transform.localTransform!.getTranslation().x, -10);
    });
  });

  group('the widget forms', () {
    Widget frame(
      Layout3dController controller,
      Widget child, {
      TextDirection? direction,
    }) {
      final surface = SceneLayout3d(
        parent: Node(),
        size: const Size3d(10, 10, 10),
        controller: controller,
        child: child,
      );
      return direction == null
          ? surface
          : Directionality(textDirection: direction, child: surface);
    }

    List<Layout3d> childrenOf(Layout3dController controller) =>
        (controller.surface!.child! as MultiChildLayout3d).children;

    testWidgets('a row reads the ambient direction, and follows it', (
      tester,
    ) async {
      final controller = Layout3dController();
      const row = SceneRow3d(
        children: [SceneSizedBox3d.cube(2), SceneSizedBox3d.cube(3)],
      );

      await tester.pumpWidget(frame(controller, row));
      expect(childrenOf(controller).first.offset.x, 0);

      await tester.pumpWidget(frame(controller, row, direction: rtl));
      expect(childrenOf(controller).first.offset.x, 8);

      await tester.pumpWidget(frame(controller, row, direction: ltr));
      expect(childrenOf(controller).first.offset.x, 0);
    });

    testWidgets('a stated direction wins over the ambient one', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        frame(
          controller,
          const SceneRow3d(
            textDirection: ltr,
            children: [SceneSizedBox3d.cube(2), SceneSizedBox3d.cube(3)],
          ),
          direction: rtl,
        ),
      );
      expect(childrenOf(controller).first.offset.x, 0);
    });

    testWidgets('a column can run upward', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        frame(
          controller,
          const SceneColumn3d(
            verticalDirection: VerticalDirection.up,
            children: [SceneSizedBox3d.cube(2), SceneSizedBox3d.cube(2)],
          ),
        ),
      );
      expect(childrenOf(controller).first.offset.y, 8);
    });

    testWidgets('a padding and an align read the ambient direction', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        frame(
          controller,
          const SceneAlign3d(
            alignment: AlignmentDirectional3d.topStart,
            child: ScenePadding3d(
              padding: EdgeInsetsDirectional3d.only(start: 1),
              child: SceneSizedBox3d.cube(2),
            ),
          ),
          direction: rtl,
        ),
      );
      final padding = (controller.surface!.child! as Align3d).child!;
      expect(padding.offset.x, 7);
      expect((padding as Padding3d).child!.offset.x, 0);
    });

    testWidgets('a wrap and a table read the ambient direction', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        frame(
          controller,
          const SceneWrap3d(
            children: [SceneSizedBox3d.cube(4), SceneSizedBox3d.cube(4)],
          ),
          direction: rtl,
        ),
      );
      expect(childrenOf(controller).first.offset.x, 6);

      await tester.pumpWidget(
        frame(
          controller,
          const SceneTable3d(
            columnCount: 2,
            columnWidths: {0: FixedColumnWidth3d(2), 1: FixedColumnWidth3d(3)},
            children: [SceneSizedBox3d.cube(1), SceneSizedBox3d.cube(1)],
          ),
          direction: rtl,
        ),
      );
      expect(childrenOf(controller).first.offset.x, 3);
    });

    testWidgets(
      'a directional positioned child follows the ambient direction',
      (tester) async {
        final controller = Layout3dController();
        Widget stack(TextDirection direction) => frame(
          controller,
          const SceneStack3d(
            fit: StackFit3d.expand,
            children: [
              SceneSizedBox3d.cube(10),
              ScenePositionedDirectional3d(
                start: 1,
                width: 3,
                child: SceneSizedBox3d.cube(3),
              ),
            ],
          ),
          direction: direction,
        );

        await tester.pumpWidget(stack(rtl));
        final pinned = childrenOf(controller)[1] as Positioned3d;
        expect(pinned.offset.x, 6);

        await tester.pumpWidget(stack(ltr));
        expect(childrenOf(controller)[1], same(pinned));
        expect(pinned.left, 1);
        expect(pinned.right, isNull);
        expect(pinned.offset.x, 1);
      },
    );

    testWidgets('an animated container goes from a side to a start', (
      tester,
    ) async {
      final controller = Layout3dController();
      Widget container(EdgeInsetsGeometry3d padding) => frame(
        controller,
        SceneAnimatedContainer3d(
          duration: const Duration(milliseconds: 100),
          padding: padding,
          child: const SceneSizedBox3d.cube(2),
        ),
        direction: rtl,
      );

      await tester.pumpWidget(container(const EdgeInsets3d.only(left: 4)));
      Layout3d child() => (controller.surface!.child! as Container3d).child!;
      expect(child().offset.x, 4);

      await tester.pumpWidget(
        container(const EdgeInsetsDirectional3d.only(start: 4)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Halfway: two on the left, and two on the start, which is the right.
      expect(child().offset.x, closeTo(2, 1e-9));

      await tester.pumpAndSettle();
      expect(child().offset.x, 0);
    });
  });
}
