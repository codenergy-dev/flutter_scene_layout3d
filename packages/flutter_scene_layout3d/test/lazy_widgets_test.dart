// Lazily built children in the widget layer: the four `.builder` widgets, the
// element that is their child manager, and what happens to an item's state,
// its painter and its focus node when the window leaves it.

import 'package:flutter/widgets.dart'
    show
        BuildContext,
        FocusNode,
        GlobalKey,
        InheritedWidget,
        State,
        StatefulWidget,
        ValueKey,
        Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Layout3d rootOf(Layout3dController controller) => controller.surface!.child!;

/// A painter that records what it was asked to do and builds nothing, so the
/// painter cache can be watched without a GPU.
class RecordingPainter extends Decoration3dPainter {
  RecordingPainter(this.shape);

  final String shape;
  final List<Node> released = <Node>[];
  bool disposed = false;

  @override
  void paint(Decoration3dPaintRequest request) {}

  @override
  void release(Node node) => released.add(node);

  @override
  void dispose() => disposed = true;
}

/// A decoration whose painter is one of the recording ones above.
class TestDecoration3d extends Decoration3d {
  const TestDecoration3d(this.shape);

  final String shape;

  @override
  Object get cacheKey => shape;

  @override
  bool shouldRebuild(TestDecoration3d old) => false;

  @override
  Decoration3dPainter? createPainter() => RecordingPainter(shape);

  @override
  bool operator ==(Object other) =>
      other is TestDecoration3d && other.shape == shape;

  @override
  int get hashCode => shape.hashCode;
}

/// An item that takes a painter from the surface's cache, standing in for
/// anything a Material catalogue would decorate.
class DecoratedItem extends SingleChildLayout3dWidget {
  const DecoratedItem({super.key, super.child});

  @override
  DecoratedBox3d createLayout(BuildContext context) =>
      DecoratedBox3d(decoration: const TestDecoration3d('panel'));

  @override
  void updateLayout(BuildContext context, DecoratedBox3d layout) {}
}

/// The extent an item should take, handed down the widget tree rather than
/// passed to the list, so that an item has to read it from its context.
class ItemExtent extends InheritedWidget {
  const ItemExtent({required this.extent, required super.child, super.key});

  final double extent;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ItemExtent>()!.extent;

  @override
  bool updateShouldNotify(ItemExtent old) => old.extent != extent;
}

/// An item with state, which says when it was created and destroyed.
class TrackedItem extends StatefulWidget {
  const TrackedItem({required this.label, required this.log, super.key});

  final String label;
  final List<String> log;

  @override
  State<TrackedItem> createState() => TrackedItemState();
}

class TrackedItemState extends State<TrackedItem> {
  /// Something only this state knows, so that a moved item can be recognised.
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
      const SceneSizedBox3d(width: 4, height: 2, depth: 1);
}

void main() {
  group('a built list', () {
    testWidgets('builds the window and nothing else', (tester) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();
      final built = <int>[];

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 6, 1),
          controller: controller,
          child: SceneListView3d.builder(
            controller: scroll,
            itemCount: 1000,
            itemExtent: 2,
            itemBuilder: (context, index) {
              built.add(index);
              return const SceneSizedBox3d(width: 4, height: 2, depth: 1);
            },
          ),
        ),
      );

      final list = rootOf(controller) as ListView3d;
      // Six of room, two to an item: four of them start inside the window.
      expect(built, <int>[0, 1, 2, 3]);
      expect(list.activeIndices, <int>[0, 1, 2, 3]);
      expect(list.children, hasLength(4));
      expect(list.children[2].offset.y, 4);
      // A thousand items, and the list knows how long it is without building
      // any of the rest.
      expect(scroll.contentExtent, 2000);
    });

    testWidgets('builds what the window reaches as it scrolls, and releases '
        'what it leaves', (tester) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();
      final built = <int>[];

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 1),
          controller: controller,
          child: SceneListView3d.builder(
            controller: scroll,
            itemCount: 50,
            itemExtent: 2,
            itemBuilder: (context, index) {
              built.add(index);
              return const SceneSizedBox3d(width: 4, height: 2, depth: 1);
            },
          ),
        ),
      );
      final list = rootOf(controller) as ListView3d;
      expect(built, <int>[0, 1, 2]);
      final leaving = list.children.first;

      built.clear();
      scroll.jumpTo(20);
      await tester.pump();

      expect(built, <int>[10, 11, 12]);
      expect(list.activeIndices, <int>[10, 11, 12]);
      // What the window left is off the tree and finished with, which is what
      // releases the scene node it hung from its parent.
      expect(leaving.debugDisposed, isTrue);
      expect(leaving.parent, isNull);
    });

    testWidgets('an item reads an inherited widget declared above the list', (
      tester,
    ) async {
      final controller = Layout3dController();

      Widget frame(double extent) => ItemExtent(
        extent: extent,
        child: SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 6, 1),
          controller: controller,
          child: SceneListView3d.builder(
            itemCount: 20,
            itemExtent: 2,
            itemBuilder: (context, index) => SceneSizedBox3d(
              width: ItemExtent.of(context),
              height: 2,
              depth: 1,
            ),
          ),
        ),
      );

      await tester.pumpWidget(frame(3));
      final list = rootOf(controller) as ListView3d;
      expect(list.children.first.size.width, 3);

      // The item is a real element, so the inherited value reaching it is
      // Flutter's own dependency machinery rather than anything here.
      await tester.pumpWidget(frame(1.5));
      expect(list.children.first.size.width, 1.5);
    });

    testWidgets('an item keeps its state in the window and loses it when the '
        'window leaves', (tester) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();
      final log = <String>[];

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 1),
          controller: controller,
          child: SceneListView3d.builder(
            controller: scroll,
            itemCount: 50,
            itemExtent: 2,
            itemBuilder: (context, index) =>
                TrackedItem(label: '$index', log: log),
          ),
        ),
      );
      expect(log, <String>['init 0', 'init 1', 'init 2']);

      log.clear();
      scroll.jumpTo(2);
      await tester.pump();
      // The window moved by one item: one arrived, one left, and the two in
      // the middle were not rebuilt from scratch.
      expect(log, <String>['init 3', 'dispose 0']);

      log.clear();
      scroll.jumpTo(0);
      await tester.pump();
      expect(log, <String>['init 0', 'dispose 3']);
    });

    testWidgets('a keyed reorder puts the right item at each index', (
      tester,
    ) async {
      final controller = Layout3dController();
      final log = <String>[];

      Widget frame(List<String> labels) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 8, 1),
        controller: controller,
        child: SceneListView3d.builder(
          itemCount: labels.length,
          itemExtent: 2,
          itemBuilder: (context, index) => TrackedItem(
            key: ValueKey(labels[index]),
            label: labels[index],
            log: log,
          ),
        ),
      );

      await tester.pumpWidget(frame(<String>['a', 'b', 'c']));
      expect(log, <String>['init a', 'init b', 'init c']);

      log.clear();
      await tester.pumpWidget(frame(<String>['c', 'a', 'b']));

      final list = rootOf(controller) as ListView3d;
      expect(list.activeIndices, <int>[0, 1, 2]);
      expect(list.children, hasLength(3));
      // A local key only says "this index holds something else now", so the
      // element at that index is replaced rather than moved. Flutter's own
      // sliver avoids that with a delegate that can find an index by key;
      // there is no delegate here, and a GlobalKey is what moves an item
      // with its state intact.
      expect(log, containsAll(<String>['init c', 'dispose a']));
    });

    testWidgets('a GlobalKey item moves between indices without losing state', (
      tester,
    ) async {
      final controller = Layout3dController();
      final key = GlobalKey<TrackedItemState>();
      final log = <String>[];

      Widget frame(List<String> labels) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 8, 1),
        controller: controller,
        child: SceneListView3d.builder(
          itemCount: labels.length,
          itemExtent: 2,
          itemBuilder: (context, index) => TrackedItem(
            key: labels[index] == 'moved' ? key : ValueKey(labels[index]),
            label: labels[index],
            log: log,
          ),
        ),
      );

      await tester.pumpWidget(frame(<String>['moved', 'b', 'c']));
      final state = key.currentState!;
      state.marker = 7;

      log.clear();
      await tester.pumpWidget(frame(<String>['b', 'c', 'moved']));

      // The same element, carried to its new index by its key rather than
      // rebuilt there.
      expect(key.currentState, same(state));
      expect(key.currentState!.marker, 7);
      expect(log.where((entry) => entry.startsWith('init moved')), isEmpty);
      final list = rootOf(controller) as ListView3d;
      expect(list.activeIndices, <int>[0, 1, 2]);
      expect(list.children, hasLength(3));
    });

    testWidgets('itemCount changing rebuilds the right range', (tester) async {
      final controller = Layout3dController();
      final built = <int>[];

      Widget frame(int count) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 20, 1),
        controller: controller,
        child: SceneListView3d.builder(
          itemCount: count,
          itemExtent: 2,
          itemBuilder: (context, index) {
            built.add(index);
            return const SceneSizedBox3d(width: 4, height: 2, depth: 1);
          },
        ),
      );

      await tester.pumpWidget(frame(3));
      final list = rootOf(controller) as ListView3d;
      expect(list.activeIndices, <int>[0, 1, 2]);

      built.clear();
      await tester.pumpWidget(frame(5));
      expect(list.itemCount, 5);
      expect(list.activeIndices, <int>[0, 1, 2, 3, 4]);
      // The two new indices are built; the three standing are rebuilt in
      // place, because a new builder closure may build anything.
      expect(built..sort(), <int>[0, 1, 2, 3, 4]);

      built.clear();
      await tester.pumpWidget(frame(2));
      expect(list.itemCount, 2);
      expect(list.activeIndices, <int>[0, 1]);
      expect(list.children, hasLength(2));
      expect(built..sort(), <int>[0, 1]);
    });

    testWidgets('a list that measures its items builds forward to the window', (
      tester,
    ) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 1),
          controller: controller,
          child: SceneListView3d.builder(
            controller: scroll,
            itemCount: 10,
            itemBuilder: (context, index) => SceneSizedBox3d(
              width: 4,
              height: index.isEven ? 1 : 3,
              depth: 1,
            ),
          ),
        ),
      );

      final list = rootOf(controller) as ListView3d;
      // Item 0 is one tall and item 1 three, so item 2 starts exactly at the
      // end of the window and is not in it.
      expect(list.activeIndices, <int>[0, 1]);
      expect(list.children[1].offset.y, 1);

      scroll.jumpTo(4);
      await tester.pump();
      expect(list.activeIndices, unorderedEquals(<int>[2, 3]));
    });
  });

  group('the other three views', () {
    testWidgets('SceneGridView3d.builder builds the cells in the window', (
      tester,
    ) async {
      final controller = Layout3dController();
      final built = <int>[];

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 1),
          controller: controller,
          child: SceneGridView3d.builder(
            gridDelegate: const Grid3dDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 2,
            ),
            itemCount: 100,
            itemBuilder: (context, index) {
              built.add(index);
              return const SceneSizedBox3d(width: 2, height: 2, depth: 1);
            },
          ),
        ),
      );

      final grid = rootOf(controller) as GridView3d;
      // Two cells to a row, two rows in the window, and the row that starts
      // exactly at the far edge of it.
      expect(built, <int>[0, 1, 2, 3, 4, 5]);
      expect(grid.activeIndices, <int>[0, 1, 2, 3, 4, 5]);
    });

    testWidgets('the sliver views build inside a CustomScrollView3d', (
      tester,
    ) async {
      final controller = Layout3dController();
      final listBuilt = <int>[];
      final gridBuilt = <int>[];

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 6, 1),
          controller: controller,
          child: SceneCustomScrollView3d(
            slivers: [
              SceneSliverList3d.builder(
                itemCount: 100,
                itemExtent: 2,
                itemBuilder: (context, index) {
                  listBuilt.add(index);
                  return const SceneSizedBox3d(width: 4, height: 2, depth: 1);
                },
              ),
              SceneSliverGrid3d.builder(
                gridDelegate: const Grid3dDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 2,
                ),
                itemCount: 100,
                itemBuilder: (context, index) {
                  gridBuilt.add(index);
                  return const SceneSizedBox3d(width: 2, height: 2, depth: 1);
                },
              ),
            ],
          ),
        ),
      );

      final view = rootOf(controller) as CustomScrollView3d;
      expect(listBuilt, <int>[0, 1, 2, 3]);
      // The list fills the window on its own, so the grid below it has
      // nothing to paint; it still builds its first row, which is the row
      // that starts at its own leading edge.
      expect(gridBuilt, <int>[0, 1]);
      expect((view.slivers[0] as SliverList3d).activeIndices, <int>[
        0,
        1,
        2,
        3,
      ]);
      expect(view.slivers[1].geometry.paintExtent, 0);
    });
  });

  group('the lifecycle of a released item', () {
    testWidgets('gives back the painter it took', (tester) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 1),
          controller: controller,
          child: SceneListView3d.builder(
            controller: scroll,
            itemCount: 50,
            itemExtent: 2,
            itemBuilder: (context, index) => const DecoratedItem(
              child: SceneSizedBox3d(width: 4, height: 2, depth: 1),
            ),
          ),
        ),
      );

      final list = rootOf(controller) as ListView3d;
      final owner = list.owner!;
      final leaving = list.children.first;
      // One painter, shared by the three decorated items in the window.
      expect(owner.painters.length, 1);

      scroll.jumpTo(20);
      await tester.pump();

      expect(leaving.debugDisposed, isTrue);
      // Three items left and three arrived, so the painter is still shared —
      // but the ones that left gave their use of it back, which is what stops
      // a long scroll from leaking one per item.
      expect(owner.painters.length, 1);
    });

    testWidgets('disposes the focus node it owns', (tester) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 1),
          controller: controller,
          child: SceneListView3d.builder(
            controller: scroll,
            itemCount: 50,
            itemExtent: 2,
            itemBuilder: (context, index) => const SceneFocus3d(
              child: SceneSizedBox3d(width: 4, height: 2, depth: 1),
            ),
          ),
        ),
      );

      final list = rootOf(controller) as ListView3d;
      final leaving = list.children.first as Focus3d;
      final FocusNode node = leaving.focusNode;

      scroll.jumpTo(20);
      await tester.pump();

      expect(leaving.debugDisposed, isTrue);
      // A disposed FocusNode refuses to be listened to, which is the only
      // thing it says about itself from outside.
      expect(() => node.addListener(() {}), throwsA(isA<AssertionError>()));
    });

    testWidgets('the surface tears down without disposing an item twice', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 1),
          controller: controller,
          child: SceneListView3d.builder(
            itemCount: 50,
            itemExtent: 2,
            itemBuilder: (context, index) => const DecoratedItem(
              child: SceneSizedBox3d(width: 4, height: 2, depth: 1),
            ),
          ),
        ),
      );
      final list = rootOf(controller) as ListView3d;
      final items = List<Layout3d>.of(list.children);
      expect(items, isNotEmpty);

      await tester.pumpWidget(SceneLayout3d(parent: Node()));

      expect(tester.takeException(), isNull);
      expect(controller.surface, isNull);
      for (final item in items) {
        expect(item.debugDisposed, isTrue);
      }
    });
  });

  group('building during layout', () {
    testWidgets('does not re-enter the surface flush', (tester) async {
      final controller = Layout3dController();
      final built = <int>[];

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 6, 1),
          controller: controller,
          child: SceneListView3d.builder(
            itemCount: 40,
            itemExtent: 2,
            itemBuilder: (context, index) {
              built.add(index);
              return const SceneSizedBox3d(width: 4, height: 2, depth: 1);
            },
          ),
        ),
      );

      // Each index was built once: a flush that re-entered itself would lay
      // the list out again from inside its own pass and build them all over.
      expect(built, <int>[0, 1, 2, 3]);
      expect(controller.surface!.needsFlush, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is legal from a partial relayout deeper in the surface', (
      tester,
    ) async {
      final controller = Layout3dController();
      final built = <int>[];

      // The spacers are a sibling of the list, not an ancestor of it. Editing
      // that child list dirties the spacers' own hosting box and nothing
      // else, so Flutter lays that box out alone — and the surface flush it
      // drives is the one that has to build the items the list can now
      // reach. A flush from a box that does not contain the list is the case
      // this is here for.
      Widget frame(int spacers) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 10, 1),
        controller: controller,
        child: SceneColumn3d(
          children: [
            SceneColumn3d(
              children: <Widget>[
                for (var i = 0; i < spacers; i++)
                  SceneSizedBox3d(key: ValueKey(i), width: 4, height: 1),
              ],
            ),
            SceneExpanded3d(
              child: SceneListView3d.builder(
                itemCount: 40,
                itemExtent: 2,
                itemBuilder: (context, index) {
                  built.add(index);
                  return const SceneSizedBox3d(width: 4, height: 2, depth: 1);
                },
              ),
            ),
          ],
        ),
      );

      await tester.pumpWidget(frame(4));
      expect(built, <int>[0, 1, 2, 3]);

      built.clear();
      await tester.pumpWidget(frame(0));

      expect(tester.takeException(), isNull);
      // Two more items of room, and the pair that fills it was built during
      // that pass rather than a frame later. The four already standing are
      // rebuilt too, because the whole tree was.
      expect(built, <int>[0, 1, 2, 3, 4, 5]);
    });
  });
}
