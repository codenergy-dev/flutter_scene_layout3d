// Reordering a list by dragging one of its items.
//
// The claim under all of this is a negative, and it is the same one
// `drag_test.dart` makes: a reorder moves nothing. The dragged item stays
// exactly where it is in the child list, hidden, so its extent *is* the gap,
// and every other item is slid aside by one matrix write. So what these tests
// mostly check is that the index-to-child map does not change and that
// `needsFlush` stays false — if a reorder ever gets onto the relayout path or
// starts rebuilding items, one of these fails first.
//
// These need Flutter's gesture binding, because picking an item up means
// competing in the arena with the list it is in.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Ray;

import 'support.dart';

/// A list of five one-unit rows in a window three units tall.
///
/// The geometry every test below reasons in: item `i` covers `y` from `i` to
/// `i + 1` in the surface's own coordinates, so a ray at `y = 1.4` is over the
/// middle of item 1 and the arithmetic can be read off the assertions.
class Fixture {
  Fixture({
    int itemCount = 5,
    double itemExtent = 1.0,
    double viewportExtent = 3.0,
    double spacing = 0.0,
    Drag3dStartMode startMode = const Drag3dStartMode.immediate(),
    Duration gapDuration = Duration.zero,
    List<double>? extents,
    bool overlay = false,
  }) {
    controller = Scroll3dController();
    list = ReorderableList3d(
      itemCount: itemCount,
      itemExtent: extents == null ? itemExtent : null,
      spacing: spacing,
      startMode: startMode,
      gapDuration: gapDuration,
      controller: controller,
      itemBuilder: (index) {
        builds.add(index);
        return TestBox(
          Size3d(1, extents == null ? itemExtent : extents[index], 0),
          pointable: true,
          name: 'item $index',
        );
      },
      onReorder: (oldIndex, newIndex) => reorders.add((oldIndex, newIndex)),
    );
    this.overlay = overlay ? Overlay3d(children: <Layout3d>[list]) : null;
    surface = laidOut(
      this.overlay ?? list,
      constraints: Constraints3d.tight(Size3d(1, viewportExtent, 0)),
    );
    pointer = Layout3dPointer(surface);
  }

  late final Scroll3dController controller;
  late final ReorderableList3d list;
  late final Overlay3d? overlay;
  late final Layout3dSurface surface;
  late final Layout3dPointer pointer;

  /// Every index the caller's own item builder was asked for.
  ///
  /// The feedback is a second copy of the item, so it shows up here too —
  /// once per drag, which is the point of building it in the overlay rather
  /// than under the finger.
  final List<int> builds = <int>[];

  /// The `(oldIndex, newIndex)` pairs the list reported.
  final List<(int, int)> reorders = <(int, int)>[];

  SliverReorderableList3d get sliver => list.sliver;

  /// Aims a ray at [y] on the surface's plane, half a unit in from the side.
  Ray at(double y) => rayAt(surface, Offset3d(0.5, y, 0));

  /// Picks item [index] up and carries the pointer to [y].
  ///
  /// Two moves: the first crosses the touch slop and is what recognizes the
  /// drag, the second is the one the gap follows.
  void lift(int index, {double? to}) {
    pointer
      ..down(at(index + 0.5))
      ..move(at(index + 0.5 + 0.3));
    if (to != null) pointer.move(at(to));
  }

  void dispose() {
    surface.dispose();
    controller.dispose();
  }

  /// Where item [index] has been slid to, along the scroll axis.
  double shiftOf(int index) {
    for (final entry in sliver.activeIndices) {
      if (entry != index) continue;
      return _childAt(index).nodeOffset.y;
    }
    return 0.0;
  }

  bool visibilityOf(int index) => _childAt(index).node.visible;

  Layout3d _childAt(int index) {
    final ordered = sliver.activeIndices.toList()..sort();
    return sliver.childAt(ordered.indexOf(index));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the gap', () {
    test('opens where the item would land, and nothing else moves', () {
      final f = Fixture();
      addTearDown(f.dispose);

      f.lift(0, to: 1.4);

      expect(f.sliver.dragIndex, 0);
      expect(f.sliver.insertIndex, 1);
      // The item is still in the list, in its own slot, and hidden — so its
      // extent is the gap. The one below it has moved up into the space.
      expect(f.visibilityOf(0), isFalse);
      expect(f.shiftOf(0), 0.0);
      expect(f.shiftOf(1), closeTo(-1.0, 1e-9));
      expect(f.shiftOf(2), 0.0);
    });

    test('follows the pointer down the list and back up again', () {
      final f = Fixture();
      addTearDown(f.dispose);

      f.lift(0, to: 2.5);
      expect(f.sliver.insertIndex, 2);
      expect(f.shiftOf(1), closeTo(-1.0, 1e-9));
      expect(f.shiftOf(2), closeTo(-1.0, 1e-9));

      f.pointer.move(f.at(1.5));
      expect(f.sliver.insertIndex, 1);
      expect(f.shiftOf(2), 0.0);

      // Back over its own slot, which is the gap: nothing is shifted at all.
      f.pointer.move(f.at(0.5));
      expect(f.sliver.insertIndex, 0);
      expect(f.shiftOf(1), 0.0);
    });

    test('pushes the other way when an item is carried up the list', () {
      final f = Fixture();
      addTearDown(f.dispose);

      f.lift(2, to: 0.4);

      expect(f.sliver.dragIndex, 2);
      expect(f.sliver.insertIndex, 0);
      expect(f.shiftOf(0), closeTo(1.0, 1e-9));
      expect(f.shiftOf(1), closeTo(1.0, 1e-9));
      expect(f.visibilityOf(2), isFalse);
    });

    test('is the dragged item\'s own extent, spacing included', () {
      final f = Fixture(
        extents: <double>[0.5, 1.5, 1.0, 0.5, 0.5],
        spacing: 0.25,
      );
      addTearDown(f.dispose);

      // Leading edges at 0, 0.75, 2.5, 3.75, 4.5 with the spacing counted in.
      expect(f.sliver.insertIndexAt(0.4), 0);
      expect(f.sliver.insertIndexAt(0.8), 1);
      expect(f.sliver.insertIndexAt(2.6), 2);

      f.pointer
        ..down(f.at(1.5))
        ..move(f.at(1.9))
        ..move(f.at(2.6));

      expect(f.sliver.dragIndex, 1);
      expect(f.sliver.insertIndex, 2);
      // 1.5 of item, 0.25 of spacing: what leaving the flow frees up.
      expect(f.shiftOf(2), closeTo(-1.75, 1e-9));
    });

    test('catches the ray over the hole it opened', () {
      final f = Fixture();
      addTearDown(f.dispose);

      f.lift(0, to: 2.5);
      expect(f.sliver.insertIndex, 2);

      // Item 0's slot is empty — the item in it is hidden, and hidden children
      // are out of reach of a ray. Without the list answering on its own
      // account while a reorder is live, the drag would be over nothing here
      // and the gap would be stuck at the bottom of the list.
      f.pointer.move(f.at(0.2));
      expect(f.sliver.insertIndex, 0);
    });
  });

  group('the drop', () {
    test('reports where the item ended up', () {
      final f = Fixture();
      addTearDown(f.dispose);

      f.lift(0, to: 2.5);
      f.pointer.up();

      expect(f.reorders, [(0, 2)]);
      expect(f.sliver.isReordering, isFalse);
      expect(f.sliver.dragIndex, isNull);
    });

    test('says nothing when the item was let go where it started', () {
      final f = Fixture();
      addTearDown(f.dispose);

      f.lift(0, to: 0.9);
      f.pointer.up();

      expect(f.reorders, isEmpty);
    });

    test('says nothing when the drag was cancelled', () {
      final f = Fixture();
      addTearDown(f.dispose);

      f.lift(0, to: 2.5);
      f.pointer.cancel();

      expect(f.reorders, isEmpty);
      expect(f.sliver.dragIndex, isNull);
    });

    test('puts every item back where layout had it', () {
      final f = Fixture();
      addTearDown(f.dispose);

      f.lift(0, to: 2.5);
      expect(f.shiftOf(1), closeTo(-1.0, 1e-9));

      f.pointer.up();
      f.surface.flush();

      expect(f.shiftOf(1), 0.0);
      expect(f.shiftOf(2), 0.0);
      // The hidden item is shown again by the layout the end of a drag asks
      // for: what an item's visibility should be is a question only the
      // window can answer.
      expect(f.visibilityOf(0), isTrue);
    });

    test('survives the surface being torn down mid-flight', () {
      final f = Fixture(overlay: true);

      f.lift(0, to: 2.5);
      expect(f.sliver.isReordering, isTrue);

      // The list is disposed before the item that owns the session is, so the
      // end of the drag arrives after there is nothing left to put back.
      f.surface.dispose();
      f.controller.dispose();

      expect(f.reorders, isEmpty);
    });

    test('survives the caller reordering its data from inside the drop', () {
      final data = <String>['a', 'b', 'c', 'd', 'e'];
      final controller = Scroll3dController();
      addTearDown(controller.dispose);
      late final ReorderableList3d list;
      list = ReorderableList3d(
        itemCount: data.length,
        itemExtent: 1.0,
        controller: controller,
        startMode: const Drag3dStartMode.immediate(),
        itemBuilder: (index) =>
            TestBox(const Size3d(1, 1, 0), pointable: true, name: data[index]),
        onReorder: (oldIndex, newIndex) {
          data.insert(newIndex, data.removeAt(oldIndex));
          // Disposes every built item, including the one under the finger.
          list.refresh();
        },
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(1, 3, 0)),
      );
      addTearDown(surface.dispose);
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(0.5, 0.9, 0)))
        ..move(rayAt(surface, const Offset3d(0.5, 2.5, 0)))
        ..up();
      surface.flush();

      expect(data, ['b', 'c', 'a', 'd', 'e']);
      expect(list.dragIndex, isNull);
      expect(list.isReordering, isFalse);
    });
  });

  group('what a reorder costs', () {
    test('nothing between the lift and the drop reaches the relayout path', () {
      final f = Fixture(overlay: true);
      addTearDown(f.dispose);

      f.lift(0);
      // Putting the feedback into the overlay is a layout, and it is the only
      // one a live reorder costs: the hidden item and every shifted item are
      // matrix writes.
      expect(f.surface.needsFlush, isTrue);
      f.surface.flush();

      for (var i = 0; i <= 20; i++) {
        f.pointer.move(f.at(0.8 + i * 0.1));
        expect(f.surface.needsFlush, isFalse, reason: 'move $i dirtied layout');
      }
      expect(f.sliver.insertIndex, 2);

      f.pointer.up();
      // And the removal of the feedback, plus the list asking to be laid out
      // once now that the drag is over, are the other side of it.
      expect(f.surface.needsFlush, isTrue);
    });

    test('builds and releases nothing while an item is in flight', () {
      final f = Fixture(overlay: true);
      addTearDown(f.dispose);
      f.builds.clear();

      f.lift(0);
      final held = f.sliver.activeIndices.toList()..sort();
      // One build, and it is the feedback: a second copy of the item, made
      // once when the drag is recognized rather than once a frame.
      expect(f.builds, [0]);

      for (var i = 0; i <= 20; i++) {
        f.pointer.move(f.at(0.8 + i * 0.1));
      }

      expect(f.builds, [0], reason: 'an item was rebuilt mid-drag');
      expect(
        f.sliver.activeIndices.toList()..sort(),
        held,
        reason: 'the index-to-child map changed mid-drag',
      );
      f.pointer.up();
    });

    test('carries a second copy of the item in the overlay', () {
      final f = Fixture(overlay: true);
      addTearDown(f.dispose);

      f.lift(1, to: 2.5);
      expect(f.overlay!.entries, hasLength(1));

      f.pointer.up();
      expect(f.overlay!.entries, isEmpty);
    });

    test('carries whatever a feedback builder says instead', () {
      final built = <int>[];
      final f = Fixture(overlay: true);
      addTearDown(f.dispose);
      f.list.feedbackBuilder = (index) {
        built.add(index);
        return TestBox(const Size3d(0.4, 0.4, 0));
      };

      f.lift(2);

      expect(built, [2]);
      f.pointer.up();
    });
  });

  group('under a clock', () {
    testWidgets('a long press picks an item up; a drag scrolls the list', (
      tester,
    ) async {
      final f = Fixture(
        startMode: const Drag3dStartMode.longPress(Duration(milliseconds: 300)),
      );
      addTearDown(f.dispose);

      f.pointer
        ..down(f.at(0.5))
        ..move(f.at(0.1));
      await tester.pump(const Duration(milliseconds: 400));

      // Travel before the delay is up says the press was a scroll, and the
      // list is the only one left in the arena.
      expect(f.sliver.isReordering, isFalse);
      expect(f.controller.offset, greaterThan(0.0));
      f.pointer.up();

      f.controller.jumpTo(0.0);
      f.pointer.down(f.at(0.5));
      await tester.pump(const Duration(milliseconds: 400));

      expect(f.sliver.isReordering, isTrue);
      expect(f.sliver.dragIndex, 0);
      expect(f.controller.offset, 0.0);
      f.pointer.up();
    });

    testWidgets('the items slide aside rather than jumping', (tester) async {
      final f = Fixture(gapDuration: const Duration(milliseconds: 200));
      addTearDown(f.dispose);

      f.lift(0, to: 1.4);
      // The gap has been asked for but nothing has moved yet.
      expect(f.shiftOf(1), 0.0);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final halfway = f.shiftOf(1);
      expect(halfway, lessThan(0.0));
      expect(halfway, greaterThan(-1.0));
      expect(f.surface.needsFlush, isFalse, reason: 'the slide is node-tier');

      await tester.pump(const Duration(milliseconds: 200));
      expect(f.shiftOf(1), closeTo(-1.0, 1e-9));
      f.pointer.up();
    });
  });
}
