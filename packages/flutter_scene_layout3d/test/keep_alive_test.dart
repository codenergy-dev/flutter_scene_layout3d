// An item that keeps its state: `KeepAlive3d`, the bucket a lazy view parks a
// child in instead of releasing it, and the seam that lets a view hold
// something other than what was built.
//
// The claim under the keep-alive half is that parking is not hiding. A parked
// child is off the layout tree entirely — not laid out, not placed, not
// drawn, not reachable — and comes back with everything its subtree held. So
// these tests watch two things at once: that the `State` survives, and that
// nothing the view walks can see the child while it is away.

import 'package:flutter/widgets.dart'
    show BuildContext, State, StatefulWidget, VoidCallback, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Ray;

import 'support.dart';

Layout3d rootOf(Layout3dController controller) => controller.surface!.child!;

/// An item with something to lose: a counter only its own state knows, and a
/// log of when it was made and unmade.
class Counter extends StatefulWidget {
  const Counter({required this.label, required this.log, super.key});

  final String label;
  final List<String> log;

  @override
  State<Counter> createState() => CounterState();
}

class CounterState extends State<Counter> {
  int count = 0;

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

/// A different kind of item, so that a rebuild can swap one for the other and
/// the element under an index really does get unmounted.
class Plain extends StatelessWidgetShim {
  const Plain({super.key});

  @override
  Widget build(BuildContext context) =>
      const SceneSizedBox3d(width: 4, height: 2, depth: 1);
}

/// `StatelessWidget` under another name, so `Plain` cannot be reconciled
/// against `Counter` and Flutter has to unmount one to build the other.
abstract class StatelessWidgetShim extends StatefulWidget {
  const StatelessWidgetShim({super.key});

  Widget build(BuildContext context);

  @override
  State<StatelessWidgetShim> createState() => _StatelessWidgetShimState();
}

class _StatelessWidgetShimState extends State<StatelessWidgetShim> {
  @override
  Widget build(BuildContext context) => widget.build(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an item that asks to be kept', () {
    testWidgets('comes back with its state after the window has left it', (
      tester,
    ) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();
      final log = <String>[];
      final states = <int, CounterState>{};

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 1),
          controller: controller,
          child: SceneListView3d.builder(
            controller: scroll,
            itemCount: 50,
            itemExtent: 2,
            itemBuilder: (context, index) => SceneKeepAlive3d(
              child: Counter(label: '$index', log: log),
            ),
          ),
        ),
      );

      final list = rootOf(controller) as ListView3d;
      states[0] = tester.state<CounterState>(find.byType(Counter).first);
      states[0]!.count = 7;

      scroll.jumpTo(40);
      await tester.pump();

      // The window is nowhere near index 0 any more, and nothing was
      // disposed: the item is parked rather than released.
      expect(list.activeIndices, isNot(contains(0)));
      expect(list.sliver.keptAliveIndices, contains(0));
      expect(log, isNot(contains('dispose 0')));

      scroll.jumpTo(0);
      await tester.pump();

      expect(list.activeIndices, contains(0));
      expect(list.sliver.keptAliveIndices, isNot(contains(0)));
      // The very same state, with the number only it knew.
      final back = tester.state<CounterState>(find.byType(Counter).first);
      expect(identical(back, states[0]), isTrue);
      expect(back.count, 7);
      expect(log.where((entry) => entry == 'init 0'), hasLength(1));
    });

    testWidgets('is off the layout tree while it is parked', (tester) async {
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
            itemBuilder: (context, index) => const SceneKeepAlive3d(
              child: SceneSizedBox3d(width: 4, height: 2, depth: 1),
            ),
          ),
        ),
      );

      final list = rootOf(controller) as ListView3d;
      final sliver = list.sliver;
      final parked = sliver.childAt(0);

      scroll.jumpTo(40);
      await tester.pump();

      // Parked, not hidden: unparented, off its parent's node, and absent
      // from everything the view walks.
      expect(parked.debugDisposed, isFalse);
      expect(parked.parent, isNull);
      expect(sliver.children, isNot(contains(parked)));
      expect(sliver.node.children, isNot(contains(parked.node)));
      expect(parked.node.visible, isFalse);
    });

    testWidgets('an item without one is released as before', (tester) async {
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
            itemBuilder: (context, index) => Counter(label: '$index', log: log),
          ),
        ),
      );

      final list = rootOf(controller) as ListView3d;
      scroll.jumpTo(40);
      await tester.pump();

      expect(list.sliver.keptAliveIndices, isEmpty);
      expect(log, contains('dispose 0'));
    });

    testWidgets('one that stops asking is released the next time the window '
        'leaves it', (tester) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();
      final log = <String>[];

      Widget frame(bool keep) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 4, 1),
        controller: controller,
        child: SceneListView3d.builder(
          controller: scroll,
          itemCount: 50,
          itemExtent: 2,
          itemBuilder: (context, index) => SceneKeepAlive3d(
            keepAlive: keep,
            child: Counter(label: '$index', log: log),
          ),
        ),
      );

      await tester.pumpWidget(frame(true));
      final list = rootOf(controller) as ListView3d;
      scroll.jumpTo(40);
      await tester.pump();
      expect(list.sliver.keptAliveIndices, contains(0));

      // Turning it off does not release what is already parked; coming back
      // and leaving again does.
      await tester.pumpWidget(frame(false));
      scroll.jumpTo(0);
      await tester.pump();
      scroll.jumpTo(40);
      await tester.pump();

      expect(list.sliver.keptAliveIndices, isEmpty);
      expect(log, contains('dispose 0'));
    });

    testWidgets('a count that shrank past a parked index releases it', (
      tester,
    ) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();
      final log = <String>[];

      Widget frame(int count) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 4, 1),
        controller: controller,
        child: SceneListView3d.builder(
          controller: scroll,
          itemCount: count,
          itemExtent: 2,
          itemBuilder: (context, index) => SceneKeepAlive3d(
            child: Counter(label: '$index', log: log),
          ),
        ),
      );

      await tester.pumpWidget(frame(50));
      final list = rootOf(controller) as ListView3d;
      scroll.jumpTo(40);
      await tester.pump();
      expect(list.sliver.keptAliveIndices, contains(0));

      // Index 0 is still inside the data, so it stays parked; the point of
      // the assertion below is the one that is not.
      scroll.jumpTo(0);
      await tester.pump();
      scroll.jumpTo(40);
      await tester.pump();
      expect(list.sliver.keptAliveIndices, contains(0));

      await tester.pumpWidget(frame(3));
      await tester.pump();

      expect(list.sliver.keptAliveIndices, everyElement(lessThan(3)));
      expect(log, contains('dispose 20'));
    });

    testWidgets('a parked item is disposed once when the list goes away', (
      tester,
    ) async {
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
            itemBuilder: (context, index) => SceneKeepAlive3d(
              child: Counter(label: '$index', log: log),
            ),
          ),
        ),
      );
      scroll.jumpTo(40);
      await tester.pump();

      log.clear();
      await tester.pumpWidget(const SizedBoxShim());

      // Once each, and no assert about a layout disposed twice.
      expect(log.where((entry) => entry == 'dispose 0'), hasLength(1));
    });

    testWidgets('a parked index rebuilt to a different widget is evicted', (
      tester,
    ) async {
      final controller = Layout3dController();
      final scroll = Scroll3dController();
      final log = <String>[];

      Widget frame(bool counters) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 4, 1),
        controller: controller,
        child: SceneListView3d.builder(
          controller: scroll,
          itemCount: 50,
          itemExtent: 2,
          itemBuilder: (context, index) => SceneKeepAlive3d(
            child: counters
                ? Counter(label: '$index', log: log)
                : const Plain(),
          ),
        ),
      );

      await tester.pumpWidget(frame(true));
      final list = rootOf(controller) as ListView3d;
      scroll.jumpTo(40);
      await tester.pump();
      expect(list.sliver.keptAliveIndices, contains(0));

      // The parked item's element is rebuilt into a widget of another type,
      // which unmounts it. Leaving the disposed layout in the bucket is what
      // would fail when the window came back.
      await tester.pumpWidget(frame(false));
      scroll.jumpTo(0);
      await tester.pump();

      expect(list.activeIndices, contains(0));
      expect(list.children.first.debugDisposed, isFalse);
    });

    test('an imperative list parks and disposes its own', () {
      final scroll = Scroll3dController();
      final built = <int>[];
      final list = ListView3d.builder(
        controller: scroll,
        itemCount: 50,
        itemExtent: 2,
        itemBuilder: (index) {
          built.add(index);
          return KeepAlive3d(child: TestBox(const Size3d(4, 2, 1)));
        },
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(4, 4, 1)),
      );
      addTearDown(() {
        surface.dispose();
        scroll.dispose();
      });

      final parked = list.sliver.childAt(0);
      built.clear();
      scroll.jumpTo(40);
      surface.flush();

      expect(list.sliver.keptAliveIndices, contains(0));
      expect(parked.debugDisposed, isFalse);

      scroll.jumpTo(0);
      surface.flush();

      // Nothing was built again: the parked child is the one that came back.
      expect(built, isNot(contains(0)));
      expect(identical(list.sliver.childAt(0), parked), isTrue);
    });

    test('refresh releases what is parked, because the data changed', () {
      final scroll = Scroll3dController();
      final list = ListView3d.builder(
        controller: scroll,
        itemCount: 50,
        itemExtent: 2,
        itemBuilder: (index) =>
            KeepAlive3d(child: TestBox(const Size3d(4, 2, 1))),
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(4, 4, 1)),
      );
      addTearDown(() {
        surface.dispose();
        scroll.dispose();
      });

      scroll.jumpTo(40);
      surface.flush();
      final parked = list.sliver.keptAliveIndices.toList();
      expect(parked, isNotEmpty);

      list.refresh();
      surface.flush();

      expect(list.sliver.keptAliveIndices, isEmpty);
    });
  });

  group('the seam a view holds its children through', () {
    testWidgets('a reorderable list built from widgets reorders them', (
      tester,
    ) async {
      final controller = Layout3dController();
      final reorders = <(int, int)>[];
      final order = <String>['a', 'b', 'c', 'd', 'e'];

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(1, 3, 1),
          controller: controller,
          child: StatefulBuilderShim(
            builder: (context, setState) => SceneReorderableList3d(
              itemCount: order.length,
              itemExtent: 1,
              startMode: const Drag3dStartMode.immediate(),
              gapDuration: Duration.zero,
              itemBuilder: (context, index) => SceneHitTestArea3d(
                child: SceneSizedBox3d(width: 1, height: 1, depth: 0),
              ),
              feedbackBuilder: (index) =>
                  TestBox(const Size3d(1, 1, 0), name: 'feedback'),
              onReorder: (oldIndex, newIndex) {
                reorders.add((oldIndex, newIndex));
                setState(
                  () => order.insert(newIndex, order.removeAt(oldIndex)),
                );
              },
            ),
          ),
        ),
      );

      final list = rootOf(controller) as ReorderableList3d;
      final surface = controller.surface!;
      final pointer = Layout3dPointer(surface);
      Ray at(double y) => rayAt(surface, Offset3d(0.5, y, 0));

      // Each item is inside a handle the list wrapped around it, which is the
      // whole of what the seam is for: the manager built the box, the list
      // holds the draggable.
      expect(list.sliver.childAt(0), isA<Draggable3d<Object>>());

      pointer
        ..down(at(0.5))
        ..move(at(0.8))
        ..move(at(1.5));
      expect(list.sliver.dragIndex, 0);
      expect(list.sliver.insertIndex, 1);

      pointer.up();
      await tester.pump();

      expect(reorders, <(int, int)>[(0, 1)]);
      expect(order, <String>['b', 'a', 'c', 'd', 'e']);
    });
  });
}

/// An empty frame to pump when a test wants the surface torn down.
class SizedBoxShim extends StatefulWidget {
  const SizedBoxShim({super.key});

  @override
  State<SizedBoxShim> createState() => _SizedBoxShimState();
}

class _SizedBoxShimState extends State<SizedBoxShim> {
  @override
  Widget build(BuildContext context) =>
      const SceneSizedBox3d(width: 1, height: 1, depth: 1);
}

/// `StatefulBuilder` under a name this file owns, so a test can rebuild the
/// list from inside `onReorder` the way an application would.
class StatefulBuilderShim extends StatefulWidget {
  const StatefulBuilderShim({required this.builder, super.key});

  final Widget Function(BuildContext context, void Function(VoidCallback) set)
  builder;

  @override
  State<StatefulBuilderShim> createState() => _StatefulBuilderShimState();
}

class _StatefulBuilderShimState extends State<StatefulBuilderShim> {
  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
}
