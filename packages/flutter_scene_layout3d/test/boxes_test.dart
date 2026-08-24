// Padding3d, Align3d, SizedBox3d, Container3d, Stack3d, Transform3d.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import 'support.dart';

void main() {
  final tight10 = Constraints3d.tight(const Size3d(10, 10, 10));

  group('Padding3d', () {
    test('grows by the insets and offsets the child', () {
      final child = TestBox(const Size3d(2, 2, 2));
      final padding = Padding3d(
        padding: const EdgeInsets3d.all(1),
        child: child,
      );
      laidOut(padding);
      expect(padding.size, const Size3d(4, 4, 4));
      expect(child.offset, const Offset3d(1, 1, 1));
    });

    test('deflates the constraints it passes down', () {
      final child = TestBox(const Size3d(20, 20, 20));
      laidOut(
        Padding3d(padding: const EdgeInsets3d.all(1), child: child),
        constraints: tight10,
      );
      expect(child.size, const Size3d(8, 8, 8));
    });

    test('collapses to its own thickness with no child', () {
      final padding = Padding3d(padding: const EdgeInsets3d.all(2));
      laidOut(padding);
      expect(padding.size, const Size3d(4, 4, 4));
    });
  });

  group('Align3d', () {
    test('fills the bounded space and positions the child', () {
      final child = TestBox(const Size3d(2, 2, 2));
      final align = Align3d(alignment: Alignment3d.topLeft, child: child);
      laidOut(align, constraints: tight10);
      expect(align.size, const Size3d(10, 10, 10));
      // Centred in depth, because Alignment3d.topLeft leaves z at 0.
      expect(child.offset, const Offset3d(0, 0, 4));
    });

    test('shrink-wraps where it is unbounded', () {
      final child = TestBox(const Size3d(2, 2, 2));
      final align = Align3d(child: child);
      laidOut(align);
      expect(align.size, const Size3d(2, 2, 2));
    });

    test('a size factor is a multiple of the child', () {
      final child = TestBox(const Size3d(2, 2, 2));
      final align = Align3d(widthFactor: 2, heightFactor: 3, child: child);
      // A size factor only has room to act where the constraints are loose;
      // tight ones win, exactly as they do for Flutter's Align.
      laidOut(
        align,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
      );
      expect(align.size.width, 4);
      expect(align.size.height, 6);
      expect(child.offset.x, 1);
    });

    test('Center3d centres', () {
      final child = TestBox(const Size3d(2, 2, 2));
      laidOut(Center3d(child: child), constraints: tight10);
      expect(child.offset, const Offset3d(4, 4, 4));
    });
  });

  group('SizedBox3d', () {
    test('fixes only the axes it is given', () {
      final child = TestBox(const Size3d(9, 9, 9));
      final box = SizedBox3d(width: 2, depth: 1, child: child);
      laidOut(box, constraints: Constraints3d.loose(const Size3d(10, 10, 10)));
      expect(child.size, const Size3d(2, 9, 1));
      expect(box.size, const Size3d(2, 9, 1));
    });

    test('takes its own size with no child', () {
      final box = SizedBox3d(width: 2, height: 3, depth: 4);
      laidOut(box);
      expect(box.size, const Size3d(2, 3, 4));
    });

    test('never escapes the constraints it was given', () {
      final box = SizedBox3d.cube(20);
      laidOut(box, constraints: Constraints3d.loose(const Size3d(4, 4, 4)));
      expect(box.size, const Size3d(4, 4, 4));
    });
  });

  group('Container3d', () {
    test('margin, padding, and alignment stack up', () {
      final child = TestBox(const Size3d(1, 1, 1));
      final container = Container3d(
        margin: const EdgeInsets3d.all(1),
        padding: const EdgeInsets3d.all(0.5),
        alignment: Alignment3d.center,
        child: child,
      );
      laidOut(container, constraints: tight10);
      expect(container.size, const Size3d(10, 10, 10));
      expect(child.offset, const Offset3d(4.5, 4.5, 4.5));
    });

    test('shrink-wraps without an alignment', () {
      final child = TestBox(const Size3d(2, 2, 2));
      final container = Container3d(
        padding: const EdgeInsets3d.all(1),
        child: child,
      );
      laidOut(container);
      expect(container.size, const Size3d(4, 4, 4));
      expect(child.offset, const Offset3d(1, 1, 1));
    });

    test('width, height, and depth tighten the child', () {
      final child = TestBox(const Size3d(9, 9, 9));
      final container = Container3d(
        width: 4,
        height: 3,
        depth: 2,
        child: child,
      );
      // Like Flutter's Container, the asked-for size is enforced against the
      // incoming constraints, so it needs loose ones to be honoured.
      laidOut(
        container,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
      );
      expect(container.size, const Size3d(4, 3, 2));
      expect(child.size, const Size3d(4, 3, 2));
    });

    test('fills what it is given with no child', () {
      final container = Container3d();
      laidOut(container, constraints: tight10);
      expect(container.size, const Size3d(10, 10, 10));
    });

    test('a transform moves the node without moving the layout', () {
      final child = TestBox(const Size3d(2, 2, 2));
      final container = Container3d(
        alignment: Alignment3d.center,
        transform: Matrix4.translationValues(1, 0, 0),
        child: child,
      );
      laidOut(container, constraints: tight10);
      expect(container.size, const Size3d(10, 10, 10));
      expect(child.offset, const Offset3d(4, 4, 4));
      expect(translationOf(container).x, 1);
    });
  });

  group('Transform3d', () {
    test('pivots around the alignment point', () {
      final child = TestBox(const Size3d(4, 4, 4));
      final transform = Transform3d(
        transform: Matrix4.diagonal3(Vector3(2, 2, 2)),
        child: child,
      );
      laidOut(transform);
      expect(transform.size, const Size3d(4, 4, 4));
      // Scaling about the centre pulls the origin corner outward by half.
      final applied = transform.node.localTransform.getTranslation();
      expect(applied.x, -2);
      expect(applied.y, -2);
      expect(applied.z, -2);
    });
  });

  group('Stack3d', () {
    test('sizes to its largest child and aligns the rest', () {
      final big = TestBox(const Size3d(4, 4, 4));
      final small = TestBox(const Size3d(2, 2, 2));
      final stack = Stack3d(
        alignment: Alignment3d.center,
        children: [big, small],
      );
      laidOut(stack);
      expect(stack.size, const Size3d(4, 4, 4));
      expect(small.offset, const Offset3d(1, 1, 1));
      expect(big.offset, Offset3d.zero);
    });

    test('StackFit3d.expand forces children to fill', () {
      final child = TestBox(const Size3d(2, 2, 2));
      laidOut(
        Stack3d(fit: StackFit3d.expand, children: [child]),
        constraints: tight10,
      );
      expect(child.size, const Size3d(10, 10, 10));
    });

    test('Positioned3d pins to the faces', () {
      final child = TestBox(const Size3d(9, 9, 9));
      final positioned = Positioned3d(
        left: 1,
        top: 2,
        width: 3,
        height: 4,
        child: child,
      );
      laidOut(
        Stack3d(children: [TestBox(const Size3d(10, 10, 10)), positioned]),
        constraints: tight10,
      );
      expect(child.size.width, 3);
      expect(child.size.height, 4);
      expect(positioned.offset.x, 1);
      expect(positioned.offset.y, 2);
    });

    test('opposite insets stretch the child', () {
      final child = TestBox(const Size3d(9, 9, 9));
      final positioned = Positioned3d(left: 1, right: 2, child: child);
      laidOut(
        Stack3d(fit: StackFit3d.expand, children: [positioned]),
        constraints: tight10,
      );
      expect(child.size.width, 7);
      expect(positioned.offset.x, 1);
    });

    test('an unpinned axis is capped at the stack, not left unbounded', () {
      // Flutter leaves it unconstrained; in 3D that lets a positioned child
      // stand out of the plane by however deep its content happens to be,
      // which is a trap when the caller pins left/top/width/height out of
      // 2D habit and forgets depth entirely.
      final child = TestBox(const Size3d(9, 9, 9));
      laidOut(
        Stack3d(
          fit: StackFit3d.expand,
          children: [
            Positioned3d(left: 1, top: 1, width: 2, height: 2, child: child),
          ],
        ),
        constraints: Constraints3d.tight(const Size3d(10, 10, 0.5)),
      );
      expect(child.size, const Size3d(2, 2, 0.5));
    });

    test('depthStep pulls later children toward the viewer', () {
      final first = TestBox(const Size3d(2, 2, 0));
      final second = TestBox(const Size3d(2, 2, 0));
      laidOut(
        Stack3d(depthStep: 0.01, children: [first, second]),
        constraints: tight10,
      );
      expect(first.offset.z, 0);
      expect(second.offset.z, -0.01);
    });
  });
}
