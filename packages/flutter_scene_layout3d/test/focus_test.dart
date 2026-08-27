// Focus3d and Focus3dTraversal: Flutter's focus nodes, tied to boxes on a
// plane. These need Flutter's binding, because FocusManager does.

import 'package:flutter/widgets.dart'
    show FocusManager, FocusNode, TraversalDirection;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Applies whatever focus change was asked for, which the manager otherwise
/// does on a microtask of its own.
void settleFocus() => FocusManager.instance.applyFocusChangesIfNeeded();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    FocusManager.instance.primaryFocus?.unfocus();
    settleFocus();
  });

  group('taking focus', () {
    ({Layout3dSurface surface, Focus3d focus, List<bool> changes}) button({
      bool focusOnPointerDown = true,
      bool canRequestFocus = true,
    }) {
      final changes = <bool>[];
      final focus = Focus3d(
        focusOnPointerDown: focusOnPointerDown,
        canRequestFocus: canRequestFocus,
        onFocusChange: changes.add,
        child: GestureDetector3d(child: TestBox(const Size3d(1, 1, 0))),
      );
      final surface = laidOut(
        focus,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      addTearDown(surface.dispose);
      return (surface: surface, focus: focus, changes: changes);
    }

    test('a press focuses the box it landed in', () {
      final control = button();
      final pointer = Layout3dPointer(control.surface);

      expect(control.focus.hasFocus, isFalse);

      pointer.down(rayAt(control.surface, const Offset3d(0.5, 0.5, 0)));
      settleFocus();

      expect(control.focus.hasFocus, isTrue);
      expect(control.focus.hasPrimaryFocus, isTrue);
      expect(control.changes, [true]);

      control.focus.unfocus();
      settleFocus();

      expect(control.focus.hasFocus, isFalse);
      expect(control.changes, [true, false]);
    });

    test('a box that says no is not focused by a press', () {
      final control = button(focusOnPointerDown: false);
      final pointer = Layout3dPointer(control.surface);

      pointer.down(rayAt(control.surface, const Offset3d(0.5, 0.5, 0)));
      settleFocus();

      expect(control.focus.hasFocus, isFalse);
      expect(control.changes, isEmpty);
    });

    test('a box that cannot take focus at all is not focused', () {
      final control = button(canRequestFocus: false);
      final pointer = Layout3dPointer(control.surface);

      pointer.down(rayAt(control.surface, const Offset3d(0.5, 0.5, 0)));
      settleFocus();

      expect(control.focus.hasFocus, isFalse);
    });

    test('the surface keeps no focus scope until something asks for one', () {
      final control = button();

      expect(control.surface.owner!.hasFocusScope, isFalse);

      control.focus.requestFocus();
      settleFocus();

      expect(control.surface.owner!.hasFocusScope, isTrue);
      expect(
        control.focus.focusNode.enclosingScope,
        same(control.surface.owner!.focusScope),
      );
    });

    test('Focus3d.of finds the box a control belongs to', () {
      final leaf = TestBox(const Size3d(1, 1, 0));
      final focus = Focus3d(child: Center3d(child: leaf));
      final surface = laidOut(
        focus,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      addTearDown(surface.dispose);

      expect(Focus3d.of(leaf), same(focus));
      expect(Focus3d.of(surface), isNull);
    });

    test('a node handed in is not disposed with the box, and one made is', () {
      final borrowed = FocusNode(debugLabel: 'borrowed');
      addTearDown(borrowed.dispose);
      final focus = Focus3d(
        focusNode: borrowed,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(
        focus,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );

      expect(focus.focusNode, same(borrowed));

      // Handing the node back leaves the box working, with one of its own.
      focus.focusNode = null;
      final made = focus.focusNode;

      expect(made, isNot(same(borrowed)));
      expect(isDisposed(borrowed), isFalse);

      surface.dispose();

      expect(isDisposed(made), isTrue, reason: 'the box owned that one');
    });

    test('focus follows the box when its node is swapped', () {
      final focus = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      final surface = laidOut(
        focus,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      addTearDown(surface.dispose);
      final replacement = FocusNode(debugLabel: 'replacement');
      addTearDown(replacement.dispose);

      focus.requestFocus();
      settleFocus();
      expect(focus.hasPrimaryFocus, isTrue);

      focus.focusNode = replacement;
      settleFocus();

      expect(focus.focusNode, same(replacement));
      expect(replacement.hasPrimaryFocus, isTrue);
    });
  });

  group('traversal', () {
    ({Layout3dSurface surface, List<Focus3d> boxes}) grid() {
      // Four half-unit boxes in a two-by-two grid, in reading order.
      final boxes = List.generate(
        4,
        (index) => Focus3d(
          name: 'cell $index',
          child: TestBox(const Size3d(0.5, 0.5, 0)),
        ),
      );
      final surface = laidOut(
        Column3d(
          children: [
            Row3d(children: [boxes[0], boxes[1]]),
            Row3d(children: [boxes[2], boxes[3]]),
          ],
        ),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      addTearDown(surface.dispose);
      return (surface: surface, boxes: boxes);
    }

    test('the focusable boxes come back in tree order', () {
      final panel = grid();

      expect(
        const Focus3dTraversal().focusableDescendants(panel.surface),
        panel.boxes,
      );
    });

    test('next and previous walk that order and wrap round', () {
      final panel = grid();
      const traversal = Focus3dTraversal();

      expect(traversal.firstFocus(panel.surface), same(panel.boxes.first));
      expect(
        traversal.next(panel.surface, panel.boxes[1]),
        same(panel.boxes[2]),
      );
      expect(
        traversal.next(panel.surface, panel.boxes.last),
        same(panel.boxes.first),
      );
      expect(
        traversal.previous(panel.surface, panel.boxes.first),
        same(panel.boxes.last),
      );
    });

    test('a box that cannot take focus is not a candidate', () {
      final panel = grid();
      panel.boxes[1].canRequestFocus = false;

      expect(
        const Focus3dTraversal().next(panel.surface, panel.boxes[0]),
        same(panel.boxes[2]),
      );
    });

    test('what is hidden is not a candidate either', () {
      final hidden = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      final visible = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      final surface = laidOut(
        Column3d(
          children: [
            Offstage3d(child: hidden),
            visible,
          ],
        ),
        constraints: Constraints3d.tight(const Size3d(1, 2, 0)),
      );
      addTearDown(surface.dispose);

      expect(const Focus3dTraversal().focusableDescendants(surface), [visible]);
    });

    test('direction is judged on the plane the boxes are projected onto', () {
      final panel = grid();
      const traversal = Focus3dTraversal();

      expect(
        traversal.inDirection(
          panel.surface,
          panel.boxes[0],
          TraversalDirection.right,
        ),
        same(panel.boxes[1]),
      );
      expect(
        traversal.inDirection(
          panel.surface,
          panel.boxes[0],
          TraversalDirection.down,
        ),
        same(panel.boxes[2]),
      );
      expect(
        traversal.inDirection(
          panel.surface,
          panel.boxes[3],
          TraversalDirection.up,
        ),
        same(panel.boxes[1]),
      );
      expect(
        traversal.inDirection(
          panel.surface,
          panel.boxes[1],
          TraversalDirection.right,
        ),
        isNull,
        reason: 'there is nothing further right',
      );
    });

    test('moving in a direction takes the focus with it', () {
      final panel = grid();
      const traversal = Focus3dTraversal();

      panel.boxes[0].requestFocus();
      settleFocus();

      expect(
        traversal.moveInDirection(
          panel.surface,
          panel.boxes[0],
          TraversalDirection.down,
        ),
        isTrue,
      );
      settleFocus();

      expect(panel.boxes[2].hasPrimaryFocus, isTrue);
      expect(
        traversal.moveInDirection(
          panel.surface,
          panel.boxes[2],
          TraversalDirection.left,
        ),
        isFalse,
        reason: 'nothing to the left, and so nothing moved',
      );
      expect(panel.boxes[2].hasPrimaryFocus, isTrue);
    });

    test('a projected box is where it appears, not where it was measured', () {
      final box = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      final surface = laidOut(
        Center3d(child: box),
        constraints: Constraints3d.tight(const Size3d(3, 3, 0)),
      );
      addTearDown(surface.dispose);

      final rect = Focus3dTraversal.projectedRect(box);

      expect(rect, isNotNull);
      expect(rect!.left, closeTo(1.0, 1e-6));
      expect(rect.top, closeTo(1.0, 1e-6));
      expect(rect.right, closeTo(2.0, 1e-6));
    });
  });
}
