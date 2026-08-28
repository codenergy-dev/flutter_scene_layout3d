// The declarative half of the boxes a catalogue asks for: SceneLayoutBuilder3d
// building its child inside the layout pass, and the rest of the new widgets
// applying a property change without rebuilding the layout object.

import 'package:flutter/widgets.dart'
    show
        BuildContext,
        SizedBox,
        State,
        StatefulBuilder,
        StatefulWidget,
        StateSetter,
        Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Layout3d rootOf(Layout3dController controller) => controller.surface!.child!;

/// A child with state, so a rebuild driven by new constraints can be told
/// apart from a child thrown away and made again.
class TrackedChild extends StatefulWidget {
  const TrackedChild({required this.label, required this.log, super.key});

  final String label;
  final List<String> log;

  @override
  State<TrackedChild> createState() => TrackedChildState();
}

class TrackedChildState extends State<TrackedChild> {
  /// Something only this state knows.
  int marker = 0;

  @override
  void initState() {
    super.initState();
    widget.log.add('init ${widget.label}');
  }

  @override
  void dispose() {
    widget.log.add('dispose ${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const SceneSizedBox3d(width: 1, height: 1, depth: 1);
}

/// A flow delegate that steps its children along, for the widget form.
class StepFlow extends Flow3dDelegate {
  const StepFlow(this.step);

  final double step;

  @override
  void paintChildren(Flow3dPaintingContext context) {
    for (var index = 0; index < context.childCount; index++) {
      context.paintChild(index, offset: Offset3d(index * step, 0, 0));
    }
  }

  @override
  bool shouldRepaint(StepFlow oldDelegate) => oldDelegate.step != step;
}

/// A delegate that stacks its two named children.
class TwoPartDelegate extends MultiChildLayout3dDelegate {
  TwoPartDelegate(this.barHeight);

  final double barHeight;

  @override
  void performLayout(Size3d size) {
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
    layoutChild(
      'body',
      Constraints3d.tight(
        Size3d(size.width, size.height - bar.height, size.depth),
      ),
    );
    positionChild('body', Offset3d(0, bar.height, 0));
  }

  @override
  bool shouldRelayout(TwoPartDelegate oldDelegate) =>
      oldDelegate.barHeight != barHeight;
}

void main() {
  group('SceneLayoutBuilder3d', () {
    testWidgets('builds its child from the constraints it is given', (
      tester,
    ) async {
      final controller = Layout3dController();
      final seen = <double>[];

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 4, 1),
          controller: controller,
          child: SceneLayoutBuilder3d(
            builder: (context, constraints) {
              seen.add(constraints.maxWidth);
              return constraints.maxWidth > 6
                  ? const SceneRow3d(
                      children: [
                        SceneSizedBox3d(width: 2, height: 1, depth: 1),
                        SceneSizedBox3d(width: 2, height: 1, depth: 1),
                      ],
                    )
                  : const SceneColumn3d(
                      children: [
                        SceneSizedBox3d(width: 2, height: 1, depth: 1),
                      ],
                    );
            },
          ),
        ),
      );

      expect(seen, <double>[8]);
      final builder = rootOf(controller) as LayoutBuilder3d;
      final built = builder.built! as Flex3d;
      expect(built.direction, Axis3d.horizontal);
      expect(built.childCount, 2);
      expect(builder.size.width, 8);
    });

    testWidgets('rebuilds when the room changes, keeping the child alive', (
      tester,
    ) async {
      final controller = Layout3dController();
      final log = <String>[];
      final seen = <double>[];

      Widget frame(double width) => SceneLayout3d(
        parent: Node(),
        size: Size3d(width, 4, 1),
        controller: controller,
        child: SceneLayoutBuilder3d(
          builder: (context, constraints) {
            seen.add(constraints.maxWidth);
            return TrackedChild(label: 'body', log: log);
          },
        ),
      );

      await tester.pumpWidget(frame(8));
      expect(seen, <double>[8]);
      expect(log, <String>['init body']);
      final state = tester.state<TrackedChildState>(find.byType(TrackedChild))
        ..marker = 7;

      // A rebuild of the widget rebuilds the child, because the builder is a
      // new closure and may return anything; the constraints have not moved,
      // so the layout pass that follows does not build a second time.
      await tester.pumpWidget(frame(8));
      expect(seen, <double>[8, 8]);

      await tester.pumpWidget(frame(3));
      expect(seen, <double>[8, 8, 3]);
      // Reconciled rather than rebuilt from nothing, so the state survived.
      expect(log, <String>['init body']);
      expect(
        tester.state<TrackedChildState>(find.byType(TrackedChild)).marker,
        7,
      );
      expect(identical(state, tester.state(find.byType(TrackedChild))), isTrue);
    });

    testWidgets('a setState above the builder rebuilds the child', (
      tester,
    ) async {
      final controller = Layout3dController();
      late StateSetter setOuter;
      var extent = 1.0;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return SceneLayout3d(
              parent: Node(),
              constraints: const Constraints3d(
                maxWidth: 8,
                maxHeight: 8,
                maxDepth: 1,
              ),
              controller: controller,
              child: SceneLayoutBuilder3d(
                builder: (context, constraints) =>
                    SceneSizedBox3d(width: extent, height: extent, depth: 1),
              ),
            );
          },
        ),
      );

      final builder = rootOf(controller) as LayoutBuilder3d;
      expect(builder.built!.size.width, 1);

      setOuter(() => extent = 3);
      await tester.pump();

      expect(builder.built!.size.width, 3);
    });

    testWidgets('the built subtree is disposed when the builder goes away', (
      tester,
    ) async {
      final controller = Layout3dController();
      final log = <String>[];

      Widget frame({required bool withBuilder}) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(8, 4, 1),
        controller: controller,
        child: withBuilder
            ? SceneLayoutBuilder3d(
                builder: (context, constraints) =>
                    TrackedChild(label: 'body', log: log),
              )
            : const SceneSizedBox3d(width: 1, height: 1, depth: 1),
      );

      await tester.pumpWidget(frame(withBuilder: true));
      final builder = rootOf(controller) as LayoutBuilder3d;
      final built = builder.built!;
      expect(built.debugDisposed, isFalse);

      await tester.pumpWidget(frame(withBuilder: false));

      expect(log, <String>['init body', 'dispose body']);
      // Unparented on the way out, so the surface's own teardown does not
      // find it a second time.
      expect(built.debugDisposed, isTrue);
      expect(built.parent, isNull);

      // Tearing the whole surface down afterwards must not double-dispose.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the declarative boxes', () {
    testWidgets('an index change reconciles onto the same stack', (
      tester,
    ) async {
      final controller = Layout3dController();

      Widget frame(int index) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(8, 8, 1),
        controller: controller,
        child: SceneIndexedStack3d(
          index: index,
          children: const [
            SceneSizedBox3d(width: 2, height: 2, depth: 1),
            SceneSizedBox3d(width: 4, height: 4, depth: 1),
          ],
        ),
      );

      await tester.pumpWidget(frame(0));
      final stack = rootOf(controller) as IndexedStack3d;
      expect(stack.childAt(0).node.visible, isTrue);
      expect(stack.childAt(1).node.visible, isFalse);

      await tester.pumpWidget(frame(1));
      expect(rootOf(controller), same(stack));
      expect(stack.childAt(0).node.visible, isFalse);
      expect(stack.childAt(1).node.visible, isTrue);
    });

    testWidgets('the sizing boxes reach their layouts', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 8, 1),
          controller: controller,
          child: const SceneFractionallySizedBox3d(
            widthFactor: 0.5,
            child: SceneLimitedBox3d(
              maxHeight: 3,
              child: SceneAspectRatio3d(aspectRatio: 2),
            ),
          ),
        ),
      );

      final fractional = rootOf(controller) as FractionallySizedBox3d;
      final limited = fractional.child! as LimitedBox3d;
      final ratio = limited.child! as AspectRatio3d;
      expect(fractional.widthFactor, 0.5);
      expect(limited.maxHeight, 3);
      // Half of eight across, and the ratio halves that again downward.
      expect(ratio.size.width, 4);
      expect(ratio.size.height, 2);
    });

    testWidgets('a custom multi-child layout is arranged by its delegate', (
      tester,
    ) async {
      final controller = Layout3dController();

      Widget frame(double barHeight) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(8, 8, 1),
        controller: controller,
        child: SceneCustomMultiChildLayout3d(
          delegate: TwoPartDelegate(barHeight),
          children: const [
            SceneLayoutId3d(
              id: 'bar',
              child: SceneSizedBox3d(width: 1, height: 1, depth: 1),
            ),
            SceneLayoutId3d(
              id: 'body',
              child: SceneSizedBox3d(width: 1, height: 1, depth: 1),
            ),
          ],
        ),
      );

      await tester.pumpWidget(frame(2));
      final layout = rootOf(controller) as CustomMultiChildLayout3d;
      expect(layout.children.first.size.height, 2);
      expect(layout.children.last.offset.y, 2);

      await tester.pumpWidget(frame(3));
      expect(rootOf(controller), same(layout));
      expect(layout.children.first.size.height, 3);
      expect(layout.children.last.offset.y, 3);
    });

    testWidgets('a flow places its children by node transform', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 8, 1),
          controller: controller,
          child: const SceneFlow3d(
            delegate: StepFlow(2),
            children: [
              SceneSizedBox3d(width: 1, height: 1, depth: 1),
              SceneSizedBox3d(width: 1, height: 1, depth: 1),
            ],
          ),
        ),
      );

      final flow = rootOf(controller) as Flow3d;
      expect(flow.childAt(1).offset, Offset3d.zero);
      expect(flow.childAt(1).nodeOffset, const Offset3d(2, 0, 0));
    });

    testWidgets('a table lays its cells out in rows and columns', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 8, 1),
          controller: controller,
          child: const SceneTable3d(
            columnCount: 2,
            children: [
              SceneSizedBox3d(width: 1, height: 1, depth: 1),
              SceneSizedBox3d(width: 1, height: 2, depth: 1),
              SceneSizedBox3d(width: 1, height: 1, depth: 1),
              SceneSizedBox3d(width: 1, height: 1, depth: 1),
            ],
          ),
        ),
      );

      final table = rootOf(controller) as Table3d;
      expect(table.rowCount, 2);
      expect(table.cellAt(0, 1)!.offset.x, 4);
      expect(table.cellAt(1, 0)!.offset.y, 2);
    });

    testWidgets('a padded sliver moves the section inside it', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 8, 1),
          controller: controller,
          child: const SceneCustomScrollView3d(
            slivers: [
              SceneSliverPadding3d(
                padding: EdgeInsets3d.only(top: 1, left: 2),
                sliver: SceneSliverList3d(
                  children: [SceneSizedBox3d(width: 1, height: 2, depth: 1)],
                ),
              ),
            ],
          ),
        ),
      );

      final view = rootOf(controller) as CustomScrollView3d;
      final padding = view.slivers.first as SliverPadding3d;
      expect(padding.geometry.scrollExtent, 3);
      expect(padding.sliver!.offset, const Offset3d(2, 1, 0));
    });

    testWidgets('a page view pages the room it is given', (tester) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController(physics: PageScroll3dPhysics());

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(6, 4, 1),
          controller: controller,
          child: ScenePageView3d.builder(
            controller: scroll,
            itemCount: 20,
            itemBuilder: (context, index) =>
                const SceneSizedBox3d(width: 1, height: 1, depth: 1),
          ),
        ),
      );

      final view = rootOf(controller) as PageView3d;
      expect(view.pageExtent, 6);
      // A page each, so what is built is the one on screen and the one whose
      // leading edge is exactly at the far end of the window.
      expect(view.activeIndices.first, 0);
      expect(view.children.first.size.width, 6);

      view.jumpToPage(3);
      await tester.pump();
      expect(view.activeIndices.first, 3);
      expect(view.page, 3);
      scroll.dispose();
    });
  });
}
