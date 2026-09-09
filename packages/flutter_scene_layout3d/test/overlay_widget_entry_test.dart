// A widget subtree as the content of an overlay entry, and the arithmetic
// that puts one box over another.
//
// The overlays plan left widget-built entries open and named this package's
// Material catalogue as the customer that would want them first. It did.

import 'package:flutter/widgets.dart'
    show BuildContext, Builder, State, StatefulWidget, StatelessWidget, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A surface with an overlay in it, and the handles a test wants.
class Pumped {
  Pumped(this.controller, this.overlayController);

  final Layout3dController controller;
  final Overlay3dController overlayController;

  Layout3dSurface get surface => controller.surface!;
  Overlay3d get overlay => overlayController.overlay!;
}

Future<Pumped> pumpOverlay(
  WidgetTester tester, {
  Widget? child,
  Size3d size = const Size3d(10, 10, 10),
}) async {
  final controller = Layout3dController();
  final overlayController = Overlay3dController();
  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      size: size,
      controller: controller,
      child: SceneOverlay3d(controller: overlayController, child: child),
    ),
  );
  return Pumped(controller, overlayController);
}

/// Every box of type [T] in [surface].
List<T> boxesOf<T extends Layout3d>(Layout3dSurface surface) {
  final found = <T>[];
  void walk(Layout3d box) {
    if (box is T) found.add(box);
    box.visitChildren(walk);
  }

  final child = surface.child;
  if (child != null) walk(child);
  return found;
}

/// A leaf that counts how many times it was built, so a test can say what a
/// rebuild of the overlay actually cost.
class _Counted extends StatelessWidget {
  const _Counted(this.builds);

  static const Size3d size = Size3d(2, 1, 0.1);

  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds[0]++;
    return SceneSizedBox3d(
      width: size.width,
      height: size.height,
      depth: size.depth,
    );
  }
}

/// A widget that keeps a number, so a test can prove the element survived a
/// rebuild rather than being made again.
class _Stateful extends StatefulWidget {
  const _Stateful(this.seen);

  final List<int> seen;

  @override
  State<_Stateful> createState() => _StatefulState();
}

class _StatefulState extends State<_Stateful> {
  int count = 0;

  @override
  void initState() {
    super.initState();
    widget.seen.add(0);
  }

  @override
  Widget build(BuildContext context) => const SceneSizedBox3d.cube(1);
}

// ---------------------------------------------------- The README's two new
// snippets, verbatim, so the compiler keeps the page honest.

Future<String?> pushWidgetRoute(
  Navigator3d navigator,
  Widget Function({required void Function([String? result]) onPick}) myDialog,
) => navigator.push(
  WidgetPageRoute3d<String>(
    builder: (context, route) => myDialog(onPick: route.pop),
  ),
);

void anchorAMenu(Layout3d menu, Layout3d button) {
  final placed = menu.anchorOffsetTo(
    button,
    self: Alignment3d.topLeft,
    target: Alignment3d.bottomLeft,
  );
  if (placed != null) menu.nodeOffset = placed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the README snippets compile as written', () {
    expect(pushWidgetRoute, isNotNull);
    expect(anchorAMenu, isNotNull);
  });

  group('a widget under an entry', () {
    testWidgets('arrives on the frame after the entry does', (tester) async {
      final pumped = await pumpOverlay(tester);
      final builds = <int>[0];

      final entry = WidgetOverlay3dEntry(
        contentBuilder: (context, _) => _Counted(builds),
      );
      pumped.overlay.insertEntry(entry);

      // The slot is in the tree at once, and it is empty: nothing has built.
      expect(entry.contentSlot, isNotNull);
      expect(entry.contentSlot!.child, isNull);
      expect(builds.single, 0);

      await tester.pump();

      expect(builds.single, 1);
      expect(entry.contentSlot!.child, isA<SizedBox3d>());
      expect(entry.contentSlot!.size, const Size3d(2, 1, 0.1));
    });

    testWidgets('is laid out under the entry, not beside it', (tester) async {
      final pumped = await pumpOverlay(tester);
      final entry = WidgetOverlay3dEntry(
        contentBuilder: (context, _) => const SceneSizedBox3d.cube(2),
      );
      pumped.overlay.insertEntry(entry);
      await tester.pump();

      // Walking up from the box the widget made reaches the entry's content
      // root, which is what "in front of everything" means here.
      Layout3d? node = entry.contentSlot!.child;
      final ancestors = <Layout3d>[];
      while (node != null) {
        ancestors.add(node);
        node = node.parent;
      }
      expect(ancestors, contains(entry.contentSlot));
      expect(ancestors, contains(pumped.overlay));
      expect(ancestors.last, isA<Layout3dSurface>());
    });

    testWidgets('leaves a zero-sized anchor among the base children', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: const SceneSizedBox3d.cube(3),
      );
      final entry = WidgetOverlay3dEntry(
        contentBuilder: (context, _) => const SceneSizedBox3d.cube(2),
      );
      pumped.overlay.insertEntry(entry);
      await tester.pump();

      // Base child, anchor, entry host — in that order, the entry last.
      final children = pumped.overlay.children;
      expect(children, hasLength(3));
      expect(children.first, isA<SizedBox3d>());
      expect(children[1].size, Size3d.zero);
    });

    testWidgets('keeps its state across a rebuild of the overlay', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester);
      final seen = <int>[];

      pumped.overlay.insertEntry(
        WidgetOverlay3dEntry(contentBuilder: (context, _) => _Stateful(seen)),
      );
      await tester.pump();
      expect(seen, hasLength(1));

      // A second entry rebuilds the overlay's child list. The first entry's
      // element is keyed on the entry, so it moves rather than being made
      // again — which is the whole reason the content is widgets.
      pumped.overlay.insertEntry(
        WidgetOverlay3dEntry(
          contentBuilder: (context, _) => const SceneSizedBox3d.cube(1),
        ),
      );
      await tester.pump();
      expect(seen, hasLength(1));
    });

    testWidgets('goes away with the entry, and is disposed once', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester);
      final entry = WidgetOverlay3dEntry(
        contentBuilder: (context, _) => const SceneSizedBox3d.cube(2),
      );
      pumped.overlay.insertEntry(entry);
      await tester.pump();

      final content = entry.contentSlot!.child!;
      entry.remove();

      // Released rather than disposed: the widget still holds it for one
      // more frame, and disposing it here would make the entry a second
      // owner of a subtree the element tree is still driving.
      expect(content.parent, isNull);

      await tester.pump();
      expect(boxesOf<SizedBox3d>(pumped.surface), isEmpty);
      // Disposed exactly once: a second dispose asserts.
      expect(() => content.dispose(), throwsAssertionError);
    });

    testWidgets('a modal entry traps focus around a widget subtree', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester);
      final entry = WidgetOverlay3dEntry(
        modal: true,
        contentBuilder: (context, _) => const SceneSizedBox3d.cube(2),
      );
      pumped.overlay.insertEntry(entry);
      await tester.pump();

      expect(entry.focusScope, isNotNull);
      // The barrier is up from the insertion, before the content exists.
      expect(boxesOf<ModalBarrier3d>(pumped.surface), hasLength(1));
    });

    testWidgets('an entry with no widgets in it costs no rebuild', (
      tester,
    ) async {
      final builds = <int>[0];
      final pumped = await pumpOverlay(
        tester,
        child: Builder(
          builder: (context) {
            builds[0]++;
            return const SceneSizedBox3d.cube(3);
          },
        ),
      );
      expect(builds.single, 1);

      // A `Draggable3d`'s feedback is an entry of this kind, inserted and
      // removed once per gesture. None of them may rebuild the overlay.
      final entry = Overlay3dEntry(
        builder: (_) => TestBox(const Size3d(1, 1, 1)),
      );
      pumped.overlay.insertEntry(entry);
      await tester.pump();
      expect(builds.single, 1);

      entry.remove();
      await tester.pump();
      expect(builds.single, 1);
    });
  });

  group('a route built from widgets', () {
    testWidgets('pushes, shows and pops with a result', (tester) async {
      final pumped = await pumpOverlay(tester);
      final navigator = Navigator3d(pumped.overlay);

      late WidgetPageRoute3d<String> route;
      route = WidgetPageRoute3d<String>(
        builder: (context, self) => const SceneSizedBox3d.cube(2),
      );
      final result = navigator.push(route);
      await tester.pump();

      expect(boxesOf<SizedBox3d>(pumped.surface), hasLength(1));
      expect(navigator.canPop, isTrue);

      route.pop('yes');
      await tester.pump();

      expect(await result, 'yes');
      expect(navigator.canPop, isFalse);
      expect(boxesOf<SizedBox3d>(pumped.surface), isEmpty);
    });

    testWidgets('a tap on the barrier pops it', (tester) async {
      final pumped = await pumpOverlay(tester);
      final navigator = Navigator3d(pumped.overlay);
      final result = navigator.push(
        WidgetPageRoute3d<String>(
          builder: (context, route) => const SceneSizedBox3d.cube(2),
        ),
      );
      await tester.pump();

      final pointer = Layout3dPointer(pumped.surface);
      pointer.down(rayAt(pumped.surface, const Offset3d(0.2, 0.2, 0)));
      pointer.up();
      await tester.pump();

      expect(await result, isNull);
      expect(navigator.canPop, isFalse);
    });
  });

  group('anchoring one box over another', () {
    /// An overlay with a 2 x 2 box pinned to its top-left corner, and a
    /// centred entry holding a 2-cube. The anchor's centre is at (1, 1) and
    /// the entry's at (5, 5).
    Future<(Layout3d anchor, Overlay3dContentSlot3d follower)> pumpAnchored(
      WidgetTester tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: const ScenePositioned3d(
          left: 0,
          top: 0,
          front: 0,
          child: SceneSizedBox3d(width: 2, height: 2, depth: 2),
        ),
      );
      final entry = WidgetOverlay3dEntry(
        contentBuilder: (context, _) => const SceneSizedBox3d.cube(2),
      );
      pumped.overlay.insertEntry(entry);
      await tester.pump();
      final anchor = boxesOf<SizedBox3d>(pumped.surface).first;
      return (anchor, entry.contentSlot!);
    }

    testWidgets('puts a follower over its anchor', (tester) async {
      final (anchor, follower) = await pumpAnchored(tester);
      final delta = follower.anchorOffsetTo(anchor);
      expect(delta, isNotNull);
      expect(delta!.x, closeTo(-4, 1e-6));
      expect(delta.y, closeTo(-4, 1e-6));
      // Depth is left alone, so the entry keeps the lift that put it in
      // front of the content it covers.
      expect(delta.z, 0);
    });

    testWidgets('is a position, so anchoring twice does not double it', (
      tester,
    ) async {
      final (anchor, follower) = await pumpAnchored(tester);
      follower.nodeOffset = follower.anchorOffsetTo(anchor)!;
      await tester.pump();

      // worldTransform reports the frame layout put the box in, with the
      // node nudges undone, so the second answer is the first one again.
      final again = follower.anchorOffsetTo(anchor)!;
      expect(again.x, closeTo(-4, 1e-6));
      expect(again.y, closeTo(-4, 1e-6));
      expect(follower.nodeOffset.x, closeTo(-4, 1e-6));
    });

    testWidgets('honours the two alignments it is given', (tester) async {
      final (anchor, follower) = await pumpAnchored(tester);
      // A menu's top-left corner on its button's bottom-left one, which is
      // where a popup menu goes.
      final delta = follower.anchorOffsetTo(
        anchor,
        self: Alignment3d.topLeft,
        target: Alignment3d.bottomLeft,
      )!;
      // The follower's top-left is at (4, 4); the anchor's bottom-left at
      // (0, 2).
      expect(delta.x, closeTo(-4, 1e-6));
      expect(delta.y, closeTo(-2, 1e-6));
    });

    testWidgets('answers null before either box has a size', (tester) async {
      final (anchor, _) = await pumpAnchored(tester);
      expect(TestBox(const Size3d(1, 1, 1)).anchorOffsetTo(anchor), isNull);
    });

    testWidgets('carries an arbitrary point between the two frames', (
      tester,
    ) async {
      // The half of this arithmetic a ripple needs: not an alignment on
      // either box, but the exact point a finger landed on. The anchor spans
      // (0, 0) to (2, 2) of the surface and the follower's own origin is at
      // (4, 4), so the anchor's centre is (-3, -3) in the follower's frame.
      final (anchor, follower) = await pumpAnchored(tester);
      final point = follower.localPointFrom(anchor, const Offset3d(1, 1, 0))!;
      expect(point.x, closeTo(-3, 1e-6));
      expect(point.y, closeTo(-3, 1e-6));

      // And it is the same arithmetic anchorOffsetTo is written in terms of:
      // mapping the anchor's centre and subtracting the follower's own is
      // exactly what that method answers.
      final delta = follower.anchorOffsetTo(anchor)!;
      expect(point.x - 1.0, closeTo(delta.x, 1e-6));
    });

    testWidgets('answers null for a point out of an unlaid-out box', (
      tester,
    ) async {
      final (anchor, follower) = await pumpAnchored(tester);
      expect(
        follower.localPointFrom(TestBox(const Size3d(1, 1, 1)), Offset3d.zero),
        isNull,
      );
    });

    testWidgets('takes depth too, when asked', (tester) async {
      final (anchor, follower) = await pumpAnchored(tester);
      follower.nodeOffset = const Offset3d(0, 0, -0.5);
      final flat = follower.anchorOffsetTo(anchor)!;
      final deep = follower.anchorOffsetTo(anchor, includeDepth: true)!;
      // The lift the entry already has is kept, not overwritten.
      expect(flat.z, -0.5);
      expect(deep.z, isNot(-0.5));
    });
  });
}
