// The protocol itself: constraints down, sizes up, the parent places the
// child, and the placement lands on the scene node.

import 'dart:ui' show Size;

import 'package:flutter_scene/scene.dart' show PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

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
      // away on each axis. Every axis flips on the way into the scene: the
      // engine's screen right is world -x (see LayoutBasis3d), and layout y
      // and z run opposite to the scene's.
      final corner = scenePositionOf(child.node);
      expect(corner.x, 2);
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

  group('screen direction', () {
    // The bug this pins: flutter_scene builds its view basis with
    // right = up x forward, so world +x is screen *left* for a camera in
    // front of a plane. A basis that paired layout x with world +x laid
    // every row out backwards on screen while every offset in the tree
    // looked correct, which no amount of layout-space assertion catches.
    PerspectiveCamera frontCamera() =>
        PerspectiveCamera(position: Vector3(0, 0, 6), target: Vector3(0, 0, 0));

    test('a row runs left to right on screen', () {
      final first = TestBox(const Size3d(1, 1, 1));
      final second = TestBox(const Size3d(1, 1, 1));
      laidOut(Row3d(children: [first, second]));

      const view = Size(512, 512);
      final camera = frontCamera();
      final firstScreen = camera.worldToScreen(
        scenePositionOf(first.node),
        view,
      )!;
      final secondScreen = camera.worldToScreen(
        scenePositionOf(second.node),
        view,
      )!;
      expect(firstScreen.dx, lessThan(secondScreen.dx));
    });

    test('a column runs top to bottom on screen', () {
      final first = TestBox(const Size3d(1, 1, 1));
      final second = TestBox(const Size3d(1, 1, 1));
      laidOut(Column3d(children: [first, second]));

      const view = Size(512, 512);
      final camera = frontCamera();
      final firstScreen = camera.worldToScreen(
        scenePositionOf(first.node),
        view,
      )!;
      final secondScreen = camera.worldToScreen(
        scenePositionOf(second.node),
        view,
      )!;
      expect(firstScreen.dy, lessThan(secondScreen.dy));
    });

    test('the front of a box is nearer the camera than its back', () {
      final child = TestBox(const Size3d(1, 1, 1));
      final surface = laidOut(
        Padding3d(padding: const EdgeInsets3d.only(front: 1), child: child),
        origin: Alignment3d.topLeftFront,
      );
      // Layout z grows away from the viewer, so a child pushed back by a
      // front inset must end up further from a camera in front of the plane.
      final camera = frontCamera();
      final planeDistance = camera.position.distanceTo(
        scenePositionOf(surface.node),
      );
      final childDistance = camera.position.distanceTo(
        scenePositionOf(child.node),
      );
      expect(childDistance, greaterThan(planeDistance));
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
      // Layout offsets add up: 1 + 2 on each axis, then the basis maps the
      // total into scene space.
      final position = scenePositionOf(child.node);
      expect(position.x, -3);
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
  group('disposal', () {
    test('a disposed layout says so, and refuses to be laid out again', () {
      final box = TestBox(const Size3d(1, 1, 1));
      final column = Column3d(children: [box]);
      laidOut(column);

      expect(column.debugDisposed, isFalse);
      column.dispose();
      expect(column.debugDisposed, isTrue);
      // Disposal reaches the whole subtree.
      expect(box.debugDisposed, isTrue);

      expect(
        () => column.layout(const Constraints3d()),
        throwsA(isA<AssertionError>()),
      );
      expect(column.dispose, throwsA(isA<AssertionError>()));
    });
  });
}
