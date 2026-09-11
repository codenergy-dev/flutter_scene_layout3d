// The declarative layer: widgets own layout objects, and the element tree
// reconciles the layout tree.

import 'package:flutter/widgets.dart' show ValueKey, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

List<Layout3d> childrenOf(Layout3d layout) =>
    (layout as MultiChildLayout3d).children;

Layout3d rootOf(Layout3dController controller) => controller.surface!.child!;

void main() {
  testWidgets('a const single-child widget is const, and skips its rebuild', (
    tester,
  ) async {
    // The `const` is the assertion: a single-child widget used to fold its
    // child into a list in its constructor, which no const expression can do,
    // so every one of them was rebuilt on every build of its parent while the
    // multi-child ones beside it were not.
    const padded = ScenePadding3d(
      padding: EdgeInsets3d.all(1),
      child: SceneSizedBox3d.cube(2),
    );
    final parent = Node();
    final controller = Layout3dController();

    Widget frame() => SceneLayout3d(
      parent: parent,
      size: const Size3d(10, 10, 10),
      controller: controller,
      child: padded,
    );

    await tester.pumpWidget(frame());
    final layout = rootOf(controller);
    expect(layout, isA<Padding3d>());
    expect((layout as Padding3d).padding, const EdgeInsets3d.all(1));

    // Rebuilding with the identical const widget reconciles onto the same
    // layout object rather than making a new one.
    await tester.pumpWidget(frame());
    expect(rootOf(controller), same(layout));
  });

  testWidgets('lays out a column of boxes on the plane', (tester) async {
    final parent = Node();
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: parent,
        size: const Size3d(10, 10, 10),
        controller: controller,
        child: SceneColumn3d(
          children: [
            SceneNodeBox3d(
              content: Node(),
              explicitSize: const Size3d(2, 2, 2),
            ),
            SceneNodeBox3d(
              content: Node(),
              explicitSize: const Size3d(4, 3, 2),
            ),
          ],
        ),
      ),
    );

    final surface = controller.surface!;
    expect(surface.size, const Size3d(10, 10, 10));

    final column = rootOf(controller);
    final boxes = childrenOf(column);
    expect(boxes, hasLength(2));
    expect(boxes[0].size, const Size3d(2, 2, 2));
    expect(boxes[1].size, const Size3d(4, 3, 2));
    // Centred across, and on the plane's front face in depth: a column's
    // depth cross axis starts at the front. See Flex3d.depthAxisAlignment.
    expect(boxes[0].offset, const Offset3d(4, 0, 0));
    expect(boxes[1].offset, const Offset3d(3, 2, 0));
  });

  testWidgets('an intrinsic box sizes a column to its widest child', (
    tester,
  ) async {
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        constraints: const Constraints3d(maxHeight: 10, maxDepth: 10),
        controller: controller,
        child: SceneIntrinsicWidth3d(
          child: SceneColumn3d(
            crossAxisAlignment: CrossAxisAlignment3d.stretch,
            children: [
              SceneNodeBox3d(
                content: Node(),
                explicitSize: const Size3d(2, 1, 1),
              ),
              SceneNodeBox3d(
                content: Node(),
                explicitSize: const Size3d(5, 1, 1),
              ),
            ],
          ),
        ),
      ),
    );

    final column = (rootOf(controller) as IntrinsicWidth3d).child!;
    expect(column.size.width, 5);
    for (final box in childrenOf(column)) {
      expect(box.size.width, 5);
    }
  });

  testWidgets('a row lines its children up on the baselines they declare', (
    tester,
  ) async {
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(10, 10, 10),
        controller: controller,
        child: SceneRow3d(
          crossAxisAlignment: CrossAxisAlignment3d.baseline,
          children: [
            SceneBaseline3d(
              baseline: 4,
              child: SceneNodeBox3d(
                content: Node(),
                explicitSize: const Size3d(1, 3, 1),
              ),
            ),
            SceneBaseline3d(
              baseline: 2,
              child: SceneNodeBox3d(
                content: Node(),
                explicitSize: const Size3d(1, 2, 1),
              ),
            ),
          ],
        ),
      ),
    );

    final children = childrenOf(rootOf(controller));
    expect(children[0].offset.y, 0);
    expect(children[1].offset.y, 2);
  });

  testWidgets('a declarative tree is hit-testable through its surface', (
    tester,
  ) async {
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 4, 1),
        controller: controller,
        child: SceneListView3d(
          children: [
            SceneNodeBox3d(
              content: Node(),
              explicitSize: const Size3d(4, 2, 1),
            ),
            SceneNodeBox3d(
              content: Node(),
              explicitSize: const Size3d(4, 2, 1),
            ),
          ],
        ),
      ),
    );

    final hit = controller.surface!.hitTestAt(const Offset3d(2, 3, 0.5));

    expect(hit.target, same(childrenOf(rootOf(controller))[1]));
    expect(hit.firstOf<Scrollable3d>(), same(rootOf(controller)));
  });

  testWidgets('SceneIgnorePointer3d takes its subtree out of reach', (
    tester,
  ) async {
    final controller = Layout3dController();

    Widget build({required bool ignoring}) => SceneLayout3d(
      parent: Node(),
      size: const Size3d(2, 2, 1),
      controller: controller,
      child: SceneIgnorePointer3d(
        ignoring: ignoring,
        child: SceneNodeBox3d(
          content: Node(),
          explicitSize: const Size3d(2, 2, 1),
        ),
      ),
    );

    await tester.pumpWidget(build(ignoring: false));
    expect(
      controller.surface!.hitTestAt(const Offset3d(1, 1, 0.5)).isNotEmpty,
      isTrue,
    );

    await tester.pumpWidget(build(ignoring: true));
    expect(
      controller.surface!.hitTestAt(const Offset3d(1, 1, 0.5)).isEmpty,
      isTrue,
    );
  });

  testWidgets('SceneWrap3d breaks its children into runs', (tester) async {
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(10, 10, 1),
        controller: controller,
        child: SceneWrap3d(
          children: [
            for (var index = 0; index < 3; index++)
              SceneNodeBox3d(
                content: Node(),
                explicitSize: const Size3d(4, 2, 1),
              ),
          ],
        ),
      ),
    );

    final boxes = childrenOf(rootOf(controller));

    expect(boxes[1].offset, const Offset3d(4, 0, 0));
    expect(boxes[2].offset, const Offset3d(0, 2, 0));
  });

  testWidgets('SceneGridView3d keeps its cells on an unchanged delegate', (
    tester,
  ) async {
    final controller = Layout3dController();

    final cell = Node();
    Widget build() => SceneLayout3d(
      parent: Node(),
      size: const Size3d(10, 10, 1),
      controller: controller,
      child: SceneGridView3d(
        gridDelegate: const Grid3dDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
        ),
        children: [
          SceneNodeBox3d(content: cell, explicitSize: const Size3d(1, 1, 1)),
        ],
      ),
    );

    await tester.pumpWidget(build());
    final grid = rootOf(controller) as GridView3d;
    expect(grid.gridLayout!.cellCrossAxisExtent, 5);

    await tester.pumpWidget(build());

    // A fresh but equivalent delegate must not leave the tree dirty.
    expect(controller.surface!.needsFlush, isFalse);
  });

  testWidgets('SceneCustomScrollView3d puts sections on one position', (
    tester,
  ) async {
    final controller = Layout3dController();
    final scroll = Scroll3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 6, 1),
        controller: controller,
        child: SceneCustomScrollView3d(
          controller: scroll,
          slivers: [
            SceneSliverToBoxAdapter3d(
              child: SceneNodeBox3d(
                content: Node(),
                explicitSize: const Size3d(4, 3, 1),
              ),
            ),
            SceneSliverList3d(
              children: [
                for (var index = 0; index < 3; index++)
                  SceneNodeBox3d(
                    content: Node(),
                    explicitSize: const Size3d(2, 2, 1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    final view = rootOf(controller) as CustomScrollView3d;

    expect(view.slivers, hasLength(2));
    expect(view.slivers[1], isA<SliverList3d>());
    // The header takes 3, the list of three 2-tall items takes 6.
    expect(view.slivers[1].offset, const Offset3d(0, 3, 0));
    expect(scroll.contentExtent, 9);
    expect(scroll.maxScrollExtent, 3);
  });

  testWidgets('mounts the plane under the given parent', (tester) async {
    final parent = Node();
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: parent,
        controller: controller,
        child: SceneNodeBox3d(
          content: Node(),
          explicitSize: const Size3d(1, 1, 1),
        ),
      ),
    );
    expect(parent.children, contains(controller.plane));
  });

  testWidgets('a rebuild updates the layout in place', (tester) async {
    final controller = Layout3dController();

    Widget build(double gap) => SceneLayout3d(
      parent: Node(),
      size: const Size3d(10, 10, 10),
      controller: controller,
      child: SceneColumn3d(
        spacing: gap,
        children: [
          SceneNodeBox3d(content: Node(), explicitSize: const Size3d(2, 2, 2)),
          SceneNodeBox3d(content: Node(), explicitSize: const Size3d(2, 2, 2)),
        ],
      ),
    );

    await tester.pumpWidget(build(0));
    final column = rootOf(controller);
    expect(childrenOf(column)[1].offset.y, 2);

    await tester.pumpWidget(build(1));
    // The same layout object, with the new gap applied.
    expect(identical(rootOf(controller), column), isTrue);
    expect(childrenOf(column)[1].offset.y, 3);
  });

  testWidgets('reordering keyed children reorders the layout', (tester) async {
    final controller = Layout3dController();

    Widget build(List<Widget> children) => SceneLayout3d(
      parent: Node(),
      size: const Size3d(10, 10, 10),
      controller: controller,
      child: SceneColumn3d(children: children),
    );

    final first = SceneNodeBox3d(
      key: const ValueKey('first'),
      content: Node(),
      explicitSize: const Size3d(2, 2, 2),
    );
    final second = SceneNodeBox3d(
      key: const ValueKey('second'),
      content: Node(),
      explicitSize: const Size3d(4, 4, 4),
    );

    await tester.pumpWidget(build([first, second]));
    final column = rootOf(controller);
    expect(childrenOf(column)[0].size, const Size3d(2, 2, 2));

    await tester.pumpWidget(build([second, first]));
    expect(identical(rootOf(controller), column), isTrue);
    expect(childrenOf(column)[0].size, const Size3d(4, 4, 4));
    expect(childrenOf(column)[1].size, const Size3d(2, 2, 2));
  });

  testWidgets('removing a child drops it from the layout', (tester) async {
    final controller = Layout3dController();

    Widget build({required bool showSecond}) => SceneLayout3d(
      parent: Node(),
      size: const Size3d(10, 10, 10),
      controller: controller,
      child: SceneColumn3d(
        children: [
          SceneNodeBox3d(
            key: const ValueKey('first'),
            content: Node(),
            explicitSize: const Size3d(2, 2, 2),
          ),
          if (showSecond)
            SceneNodeBox3d(
              key: const ValueKey('second'),
              content: Node(),
              explicitSize: const Size3d(2, 2, 2),
            ),
        ],
      ),
    );

    await tester.pumpWidget(build(showSecond: true));
    final column = rootOf(controller);
    expect(childrenOf(column), hasLength(2));
    final dropped = childrenOf(column)[1];

    await tester.pumpWidget(build(showSecond: false));
    expect(childrenOf(column), hasLength(1));
    expect(dropped.parent, isNull);
    expect(column.node.children, isNot(contains(dropped.node)));
  });

  testWidgets('nested layouts compose', (tester) async {
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(10, 10, 10),
        controller: controller,
        child: ScenePadding3d(
          padding: const EdgeInsets3d.all(1),
          child: SceneRow3d(
            children: [
              SceneExpanded3d(
                child: SceneNodeBox3d(
                  content: Node(),
                  explicitSize: const Size3d(1, 1, 1),
                ),
              ),
              SceneNodeBox3d(
                content: Node(),
                explicitSize: const Size3d(2, 2, 2),
              ),
            ],
          ),
        ),
      ),
    );

    final padding = rootOf(controller) as SingleChildLayout3d;
    final row = padding.child! as MultiChildLayout3d;
    expect(row.size.width, 8);
    expect(row.children[0].size.width, 6);
    expect(row.children[1].offset.x, 6);
  });

  testWidgets('a scroll controller drives the list', (tester) async {
    final controller = Layout3dController();
    final scroll = Scroll3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(10, 4, 10),
        controller: controller,
        child: SceneListView3d(
          controller: scroll,
          children: [
            for (var index = 0; index < 5; index++)
              SceneNodeBox3d(
                key: ValueKey(index),
                content: Node(),
                explicitSize: const Size3d(2, 2, 2),
              ),
          ],
        ),
      ),
    );

    final list = rootOf(controller);
    expect(scroll.maxScrollExtent, 6);
    expect(childrenOf(list)[2].offset.y, 4);

    scroll.jumpTo(4);
    await tester.pump();
    expect(childrenOf(list)[2].offset.y, 0);
  });

  testWidgets('the surface unmounts cleanly', (tester) async {
    final parent = Node();
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: parent,
        controller: controller,
        child: SceneNodeBox3d(
          content: Node(),
          explicitSize: const Size3d(1, 1, 1),
        ),
      ),
    );
    expect(parent.children, isNotEmpty);

    await tester.pumpWidget(SceneLayout3d(parent: Node()));
    expect(controller.surface, isNull);
    expect(parent.children, isEmpty);
  });

  testWidgets('SceneClipBox3d publishes its extent to the subtree', (
    tester,
  ) async {
    // The widget form phase 4 wrote a four-line adapter for. It is the one
    // widget here that publishes a Clip3dRegion at all.
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 2, 1),
        controller: controller,
        child: const SceneClipBox3d(
          child: SceneSizedBox3d(
            width: 4,
            height: 2,
            child: SceneSizedBox3d(width: 8, height: 1),
          ),
        ),
      ),
    );

    final clip = rootOf(controller);
    expect(clip, isA<ClipBox3d>());
    final inner = (clip as ClipBox3d).child!;
    expect(inner.clipRegion.planes, hasLength(4));
    expect(inner.clipRegion.contains(const Offset3d(2, 1, 0)), isTrue);
    expect(inner.clipRegion.contains(const Offset3d(6, 1, 0)), isFalse);
  });

  testWidgets('SceneClipBox3d writes its flags without rebuilding the box', (
    tester,
  ) async {
    final controller = Layout3dController();
    Widget frame({required bool clipDepth}) => SceneLayout3d(
      parent: Node(),
      size: const Size3d(4, 2, 1),
      controller: controller,
      child: SceneClipBox3d(
        clipDepth: clipDepth,
        child: const SceneSizedBox3d(width: 4, height: 2),
      ),
    );

    await tester.pumpWidget(frame(clipDepth: false));
    final box = rootOf(controller) as ClipBox3d;
    expect(box.clipDepth, isFalse);
    expect(box.ownRegion.planes, hasLength(4));

    await tester.pumpWidget(frame(clipDepth: true));
    expect(rootOf(controller), same(box));
    expect(box.clipDepth, isTrue);
    expect(box.ownRegion.planes, hasLength(Clip3dRegion.maxPlanes));
  });

  testWidgets('a widget-built pinned bar holds the leading edge', (
    tester,
  ) async {
    final controller = Layout3dController();
    final scroll = Scroll3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 10, 2),
        controller: controller,
        child: SceneCustomScrollView3d(
          controller: scroll,
          slivers: <Widget>[
            const SceneSliverPersistentHeader3d(
              minExtent: 2,
              maxExtent: 4,
              pinned: true,
              child: SceneSizedBox3d(width: 4, height: 4),
            ),
            SceneSliverList3d(
              children: <Widget>[
                for (var i = 0; i < 6; i++)
                  const SceneSizedBox3d(width: 4, height: 2),
              ],
            ),
          ],
        ),
      ),
    );

    final view = rootOf(controller) as CustomScrollView3d;
    final header = view.slivers.first as SliverPersistentHeader3d;
    // The delegate hands back the subtree the widget attached rather than
    // building one, so the header never drops it.
    final content = header.child;
    expect(content, isNotNull);
    expect(header.geometry.paintExtent, 4);

    scroll.jumpTo(6);
    await tester.pump();
    expect(header.child, same(content));
    expect(header.geometry.paintExtent, 2);
    expect(header.offset, Offset3d.zero);
    expect(header.obstructedExtent, 2);
  });

  testWidgets('and its extents and flags are writable in place', (
    tester,
  ) async {
    final controller = Layout3dController();
    Widget frame({required bool pinned, required double max}) => SceneLayout3d(
      parent: Node(),
      size: const Size3d(4, 10, 2),
      controller: controller,
      child: SceneCustomScrollView3d(
        slivers: <Widget>[
          SceneSliverPersistentHeader3d(
            minExtent: 2,
            maxExtent: max,
            pinned: pinned,
            child: const SceneSizedBox3d(width: 4, height: 4),
          ),
        ],
      ),
    );

    await tester.pumpWidget(frame(pinned: true, max: 4));
    final view = rootOf(controller) as CustomScrollView3d;
    final header = view.slivers.first as SliverPersistentHeader3d;
    expect(header.pinned, isTrue);
    expect(header.delegate.maxExtent, 4);

    await tester.pumpWidget(frame(pinned: false, max: 6));
    expect(view.slivers.first, same(header));
    expect(header.pinned, isFalse);
    expect(header.delegate.maxExtent, 6);
    expect(header.geometry.scrollExtent, 6);
  });
}
