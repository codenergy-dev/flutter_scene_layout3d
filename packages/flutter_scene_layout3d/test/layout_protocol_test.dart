// The protocol itself: constraints down, sizes up, the parent places the
// child, and the placement lands on the scene node.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('Layout3dSurface', () {
    test('shrink-wraps its child when unconstrained', () {
      final child = TestBox(const Size3d(2, 3, 4));
      final surface = laidOut(child);
      expect(surface.size, const Size3d(2, 3, 4));
      expect(child.lastConstraints, const Constraints3d());
    });

    test('passes its configuration down as the root constraints', () {
      final child = TestBox(const Size3d(20, 20, 20));
      final surface = laidOut(
        child,
        constraints: Constraints3d.tight(const Size3d(4, 3, 1)),
      );
      expect(surface.size, const Size3d(4, 3, 1));
      expect(child.size, const Size3d(4, 3, 1));
    });

    test('centres the layout box on the plane node by default', () {
      final child = TestBox(const Size3d(4, 2, 1));
      laidOut(child);
      // The origin corner of a 4 x 2 x 1 box, centred, sits half an extent
      // away on each axis; y and z flip on the way into the scene.
      final corner = scenePositionOf(child.node);
      expect(corner.x, -2);
      expect(corner.y, 1);
      expect(corner.z, 0.5);
    });

    test('origin: topLeftFront puts the corner on the plane node', () {
      final child = TestBox(const Size3d(4, 2, 1));
      laidOut(child, origin: Alignment3d.topLeftFront);
      final corner = scenePositionOf(child.node);
      expect(corner.x, 0);
      expect(corner.y, 0);
      expect(corner.z, 0);
    });

    test('the plane node carries the whole tree', () {
      final child = TestBox(const Size3d(2, 2, 2));
      final surface = laidOut(child);
      expect(surface.plane.children, contains(surface.node));
      expect(surface.node.children, contains(child.node));
    });

    test('lays out on the ground plane when asked', () {
      final child = TestBox(const Size3d(4, 2, 1));
      laidOut(child, basis: LayoutBasis3d.xz, origin: Alignment3d.topLeftFront);
      // Nothing moves for the corner itself, but the axes it grows along
      // differ: layout height is now scene z.
      final corner = scenePositionOf(child.node);
      expect(corner.x, 0);
      expect(corner.y, 0);
      expect(corner.z, 0);
    });
  });

  group('placement', () {
    test('a parent offset becomes a node translation', () {
      final child = TestBox(const Size3d(1, 1, 1));
      laidOut(
        Padding3d(
          padding: const EdgeInsets3d.only(left: 1, top: 2, front: 3),
          child: child,
        ),
      );
      expect(child.offset, const Offset3d(1, 2, 3));
      expect(translationOf(child), const Offset3d(1, 2, 3));
    });

    test('offsets compose down the node graph', () {
      final child = TestBox(const Size3d(1, 1, 1));
      laidOut(
        Padding3d(
          padding: const EdgeInsets3d.all(1),
          child: Padding3d(padding: const EdgeInsets3d.all(2), child: child),
        ),
        origin: Alignment3d.topLeftFront,
      );
      // Layout offsets add up: 1 + 2 on each axis, then y and z flip into
      // scene space.
      final position = scenePositionOf(child.node);
      expect(position.x, 3);
      expect(position.y, -3);
      expect(position.z, -3);
    });
  });

  group('dirty tracking', () {
    test('a size change relayouts the subtree that depends on it', () {
      final child = TestBox(const Size3d(1, 1, 1));
      final surface = laidOut(child);
      expect(child.layoutCount, 1);
      expect(surface.size, const Size3d(1, 1, 1));

      child.preferred = const Size3d(2, 2, 2);
      expect(surface.needsFlush, isTrue);
      surface.flush();
      expect(child.layoutCount, 2);
      expect(surface.size, const Size3d(2, 2, 2));
    });

    test('flushing with nothing dirty does no work', () {
      final child = TestBox(const Size3d(1, 1, 1));
      final surface = laidOut(child);
      surface.flush();
      surface.flush();
      expect(child.layoutCount, 1);
    });

    test('a tight ancestor absorbs a deep relayout', () {
      final left = TestBox(const Size3d(1, 1, 1));
      final right = TestBox(const Size3d(1, 1, 1));
      final surface = laidOut(
        Row3d(
          children: [
            SizedBox3d(
              width: 2,
              height: 2,
              depth: 2,
              child: Align3d(child: left),
            ),
            right,
          ],
        ),
        constraints: Constraints3d.tight(const Size3d(10, 10, 10)),
      );
      expect(left.layoutCount, 1);
      expect(right.layoutCount, 1);

      left.preferred = const Size3d(0.5, 0.5, 0.5);
      surface.flush();
      // The sibling outside the tightly constrained box is left alone.
      expect(left.layoutCount, 2);
      expect(right.layoutCount, 1);
    });

    test('changing the surface configuration relayouts', () {
      final child = TestBox(const Size3d(10, 10, 10));
      final surface = laidOut(child);
      expect(child.size, const Size3d(10, 10, 10));

      surface.configuration = Constraints3d.loose(const Size3d(4, 4, 4));
      surface.flush();
      expect(child.size, const Size3d(4, 4, 4));
    });
  });

  group('tree', () {
    test('adopting a child parents its node', () {
      final child = TestBox(const Size3d(1, 1, 1));
      final padding = Padding3d(child: child);
      expect(child.parent, padding);
      expect(padding.node.children, contains(child.node));

      padding.child = null;
      expect(child.parent, isNull);
      expect(padding.node.children, isEmpty);
    });

    test('syncChildren adopts, drops, and reorders', () {
      final a = TestBox(const Size3d(1, 1, 1));
      final b = TestBox(const Size3d(1, 1, 1));
      final c = TestBox(const Size3d(1, 1, 1));
      final row = Row3d(children: [a, b]);
      row.syncChildren([c, a]);
      expect(row.children, [c, a]);
      expect(b.parent, isNull);
      expect(c.parent, row);
    });
  });
}
