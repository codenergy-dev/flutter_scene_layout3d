import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/scene.dart' show Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Ray, Vector3;

import 'support.dart';

void main() {
  group('Ray3d against a box', () {
    test('reports the stretch it spends inside', () {
      final ray = const Ray3d(Offset3d(1, 1, -5), Offset3d(0, 0, 1));
      final range = ray.intersectBox(const Size3d(4, 4, 2));

      expect(range, isNotNull);
      expect(range!.near, closeTo(5.0, 1e-9));
      expect(range.far, closeTo(7.0, 1e-9));
    });

    test('misses a box it passes beside', () {
      final ray = const Ray3d(Offset3d(9, 1, -5), Offset3d(0, 0, 1));

      expect(ray.intersectBox(const Size3d(4, 4, 2)), isNull);
    });

    test('still hits a box with no depth at all', () {
      final ray = const Ray3d(Offset3d(1, 1, -5), Offset3d(0, 0, 1));
      final range = ray.intersectBox(const Size3d(4, 4, 0));

      expect(range, isNotNull);
      expect(range!.near, closeTo(5.0, 1e-9));
      expect(range.far, closeTo(5.0, 1e-9));
    });

    test('running parallel to a face is inside it or nowhere', () {
      const along = Offset3d(1, 0, 0);
      const size = Size3d(4, 4, 2);

      expect(
        const Ray3d(Offset3d(-5, 1, 1), along).intersectBox(size),
        isNotNull,
      );
      expect(const Ray3d(Offset3d(-5, 9, 1), along).intersectBox(size), isNull);
    });

    test('never reaches behind its own start', () {
      // The box sits behind the origin, along -z.
      final ray = const Ray3d(Offset3d(1, 1, 5), Offset3d(0, 0, 1));

      expect(ray.intersectBox(const Size3d(4, 4, 2)), isNull);
    });

    test('a line through a point looks both ways', () {
      final ray = Ray3d.through(const Offset3d(1, 1, 5));

      expect(ray.intersectBox(const Size3d(4, 4, 2)), isNotNull);
    });
  });

  group('walking the tree', () {
    test('finds the item under the point, ancestors behind it', () {
      final first = TestBox(const Size3d(1, 1, 1), pointable: true);
      final second = TestBox(const Size3d(1, 1, 1), pointable: true);
      final column = Column3d(children: [first, second]);
      final surface = laidOut(
        column,
        constraints: Constraints3d.tight(const Size3d(1, 2, 1)),
      );

      final hit = surface.hitTestAt(const Offset3d(0.5, 1.5, 0.5));

      expect(hit.target, same(second));
      expect(hit.path.map((entry) => entry.layout).toList(), [
        second,
        column,
        surface,
      ]);
      // The second item starts half way down the column, so the local
      // position is measured from its own origin corner, not the surface's.
      // The depth is zero because a hit reports where the ray *entered* the
      // box, and a line looked at head on enters through the front face.
      expect(
        rounded(hit.path.first.localPosition),
        const Offset3d(0.5, 0.5, 0.0),
      );
    });

    test('a box that only arranges others is not itself a target', () {
      final column = Column3d(
        mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
        children: [
          TestBox(const Size3d(1, 0.5, 1), pointable: true),
          TestBox(const Size3d(1, 0.5, 1), pointable: true),
        ],
      );
      final surface = laidOut(
        column,
        constraints: Constraints3d.tight(const Size3d(1, 3, 1)),
      );

      // Straight through the gap the alignment opened between the two items.
      expect(surface.hitTestAt(const Offset3d(0.5, 1.5, 0.5)).isEmpty, isTrue);
    });

    test('the last child of a stack is the one on top', () {
      final under = TestBox(const Size3d(1, 1, 1), pointable: true);
      final over = TestBox(const Size3d(1, 1, 1), pointable: true);
      final surface = laidOut(
        Stack3d(children: [under, over]),
        constraints: Constraints3d.tight(const Size3d(1, 1, 1)),
      );

      expect(
        surface.hitTestAt(const Offset3d(0.5, 0.5, 0.5)).target,
        same(over),
      );
    });

    test('a box clips the ray to itself, so overflow is out of reach', () {
      final badge = TestBox(const Size3d(0.4, 0.4, 0.4), pointable: true);
      final surface = laidOut(
        Stack3d(
          children: [
            // Hung off the top right corner, half outside the stack, the way
            // the panel example hangs a badge.
            Positioned3d(right: -0.2, top: -0.2, child: badge),
          ],
        ),
        constraints: Constraints3d.tight(const Size3d(2, 2, 1)),
      );

      // Inside the badge and inside the stack: a hit.
      expect(
        surface.hitTestAt(const Offset3d(1.9, 0.1, 0.5)).target,
        same(badge),
      );
      // Inside the badge but outside the stack: nothing, exactly as a
      // Flutter child overflowing its parent is unreachable through it.
      expect(surface.hitTestAt(const Offset3d(2.1, -0.1, 0.5)).isEmpty, isTrue);
    });

    test('a transform moves what the ray finds, not what layout measured', () {
      final box = TestBox(const Size3d(1, 4, 1), pointable: true);
      final surface = laidOut(
        Center3d(
          child: Transform3d.rotate(
            axis: Vector3(0, 0, 1),
            angle: 1.5707963267948966,
            child: box,
          ),
        ),
        constraints: Constraints3d.tight(const Size3d(6, 6, 1)),
      );

      // The box is 1 wide and 4 tall, turned a quarter turn about the depth
      // axis around its centre: it now lies across the middle of the plane,
      // reaching well outside the extent layout measured for it.
      // Turned, it lies across the plane from x 1 to x 5, y 2.5 to 3.5.
      expect(
        surface.hitTestAt(const Offset3d(1.5, 3.0, 0.5)).target,
        same(box),
      );
      expect(
        surface.hitTestAt(const Offset3d(4.5, 3.0, 0.5)).target,
        same(box),
      );
      // Where the box stood before it was turned, there is nothing left.
      expect(surface.hitTestAt(const Offset3d(3.0, 1.5, 0.5)).isEmpty, isTrue);
    });

    test('a ray going nowhere is a miss rather than a NaN', () {
      // Every box starts at its origin corner, so a real ray always has a
      // finite near face to enter through. A ray with no direction at all
      // has none, and must not hand NaN coordinates down the tree.
      final surface = laidOut(TestBox(Size3d.infinite, pointable: true));
      final result = HitTestResult3d();

      surface.hitTest(
        result,
        ray: const Ray3d(
          Offset3d(1, 1, 1),
          Offset3d.zero,
          tMin: double.negativeInfinity,
        ),
      );

      expect(result.isEmpty, isTrue);
    });

    test('nothing is hittable before the surface is laid out', () {
      final surface = Layout3dSurface(
        child: TestBox(const Size3d(1, 1, 1), pointable: true),
      );

      expect(surface.hitTestAt(Offset3d.zero).isEmpty, isTrue);
    });
  });

  group('taking a subtree out of reach', () {
    test('IgnorePointer3d lets the ray carry on to what is behind', () {
      final behind = TestBox(const Size3d(1, 1, 1), pointable: true);
      final front = TestBox(const Size3d(1, 1, 1), pointable: true);
      final surface = laidOut(
        Stack3d(
          children: [
            behind,
            IgnorePointer3d(child: front),
          ],
        ),
        constraints: Constraints3d.tight(const Size3d(1, 1, 1)),
      );

      expect(
        surface.hitTestAt(const Offset3d(0.5, 0.5, 0.5)).target,
        same(behind),
      );
    });

    test('AbsorbPointer3d stops it instead', () {
      final behind = TestBox(const Size3d(1, 1, 1), pointable: true);
      final front = TestBox(const Size3d(1, 1, 1), pointable: true);
      final absorber = AbsorbPointer3d(child: front);
      final surface = laidOut(
        Stack3d(children: [behind, absorber]),
        constraints: Constraints3d.tight(const Size3d(1, 1, 1)),
      );

      expect(
        surface.hitTestAt(const Offset3d(0.5, 0.5, 0.5)).target,
        same(absorber),
      );
    });

    test('a flag flipped after layout takes effect without a relayout', () {
      final box = TestBox(const Size3d(1, 1, 1), pointable: true);
      final ignore = IgnorePointer3d(ignoring: false, child: box);
      final surface = laidOut(
        ignore,
        constraints: Constraints3d.tight(const Size3d(1, 1, 1)),
      );

      expect(
        surface.hitTestAt(const Offset3d(0.5, 0.5, 0.5)).target,
        same(box),
      );

      ignore.ignoring = true;

      expect(surface.needsFlush, isFalse);
      expect(surface.hitTestAt(const Offset3d(0.5, 0.5, 0.5)).isEmpty, isTrue);
    });
  });

  group('scrolling views', () {
    test('take the hit over the gaps between their items', () {
      final list = ListView3d(
        spacing: 1.0,
        children: [
          TestBox(const Size3d(1, 1, 1), pointable: true),
          TestBox(const Size3d(1, 1, 1), pointable: true),
        ],
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(1, 3, 1)),
      );

      // Between the two items: the list answers, so a drag starting on empty
      // space still scrolls.
      expect(
        surface.hitTestAt(const Offset3d(0.5, 1.5, 0.5)).target,
        same(list),
      );
    });

    test('what is culled out of the window is out of reach', () {
      final visible = TestBox(const Size3d(1, 1, 1), pointable: true);
      final offScreen = TestBox(const Size3d(1, 1, 1), pointable: true);
      final list = ListView3d(children: [visible, offScreen]);
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(1, 1, 1)),
      );

      expect(offScreen.node.visible, isFalse);
      final hit = surface.hitTestAt(const Offset3d(0.5, 0.5, 0.5));
      expect(hit.target, same(visible));
      expect(hit.path.map((entry) => entry.layout), isNot(contains(offScreen)));
    });

    test('the list is found from a hit on one of its items', () {
      final item = TestBox(const Size3d(1, 1, 1), pointable: true);
      final list = ListView3d(children: [item]);
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(1, 2, 1)),
      );

      final hit = surface.hitTestAt(const Offset3d(0.5, 0.5, 0.5));

      expect(hit.target, same(item));
      expect(hit.firstOf<Scrollable3d>(), same(list));
    });
  });

  group('from the camera', () {
    // A camera in front of an upright panel, the arrangement the default
    // basis is built for. These pin the same screen convention the layout
    // tests pin with worldToScreen, from the other direction.
    const viewSize = Size(800, 600);

    PerspectiveCamera cameraFacingPlane() =>
        PerspectiveCamera(position: Vector3(0, 0, 5), target: Vector3.zero());

    test('the centre of the screen lands on the centre of the plane', () {
      final box = TestBox(const Size3d(2, 2, 0.2), pointable: true);
      final surface = laidOut(
        box,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0.2)),
      );
      final camera = cameraFacingPlane();

      final hit = surface.hitTestRay(
        camera.screenPointToRay(const Offset(400, 300), viewSize),
      );

      expect(hit.target, same(box));
      final position = hit.path.first.localPosition;
      expect(position.x, closeTo(1.0, 1e-3));
      expect(position.y, closeTo(1.0, 1e-3));
    });

    test('pointing right of centre lands right of centre in layout space', () {
      final box = TestBox(const Size3d(4, 4, 0.2), pointable: true);
      final surface = laidOut(
        box,
        constraints: Constraints3d.tight(const Size3d(4, 4, 0.2)),
      );
      final camera = cameraFacingPlane();

      final right = surface.hitTestRay(
        camera.screenPointToRay(const Offset(600, 300), viewSize),
      );
      final lower = surface.hitTestRay(
        camera.screenPointToRay(const Offset(400, 450), viewSize),
      );

      // Layout x grows to the right on screen and layout y grows downward,
      // which is the whole point of the basis being signed the way it is.
      expect(right.path.first.localPosition.x, greaterThan(2.0));
      expect(right.path.first.localPosition.y, closeTo(2.0, 1e-3));
      expect(lower.path.first.localPosition.y, greaterThan(2.0));
      expect(lower.path.first.localPosition.x, closeTo(2.0, 1e-3));
    });

    test('a ray that misses the plane hits nothing', () {
      final surface = laidOut(
        TestBox(const Size3d(1, 1, 0.2), pointable: true),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0.2)),
      );
      final camera = cameraFacingPlane();

      final hit = surface.hitTestRay(
        camera.screenPointToRay(const Offset(10, 10), viewSize),
      );

      expect(hit.isEmpty, isTrue);
    });

    test('the plane can be moved and turned and still be pointed at', () {
      final box = TestBox(const Size3d(2, 2, 0.2), pointable: true);
      final surface = laidOut(
        box,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0.2)),
      );
      surface.plane.position = Vector3(0, 3, 0);
      final camera = PerspectiveCamera(
        position: Vector3(0, 3, 5),
        target: Vector3(0, 3, 0),
      );

      final hit = surface.hitTestRay(
        camera.screenPointToRay(const Offset(400, 300), viewSize),
      );

      expect(hit.target, same(box));
    });
  });

  group('Layout3dPointer', () {
    const viewSize = Size(800, 600);

    ({Layout3dSurface surface, ListView3d list, PerspectiveCamera camera})
    scrollingPanel() {
      final list = ListView3d(
        children: List.generate(
          8,
          (index) => TestBox(const Size3d(2, 1, 0.1), pointable: true),
        ),
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0.2)),
      );
      return (
        surface: surface,
        list: list,
        camera: PerspectiveCamera(
          position: Vector3(0, 0, 6),
          target: Vector3.zero(),
        ),
      );
    }

    Ray rayAt(PerspectiveCamera camera, Offset screenPosition) =>
        camera.screenPointToRay(screenPosition, viewSize);

    test('grabs the list under the press', () {
      final panel = scrollingPanel();
      final pointer = Layout3dPointer(panel.surface);

      expect(pointer.down(rayAt(panel.camera, const Offset(400, 300))), isTrue);
      expect(pointer.draggedScrollable, same(panel.list));
      expect(pointer.isDragging, isTrue);

      pointer.up();

      expect(pointer.isDragging, isFalse);
    });

    test('dragging up scrolls forward, dragging down scrolls back', () {
      final panel = scrollingPanel();
      final pointer = Layout3dPointer(panel.surface);

      pointer.down(rayAt(panel.camera, const Offset(400, 300)));
      pointer.move(rayAt(panel.camera, const Offset(400, 200)));
      panel.surface.flush();
      final afterDragUp = panel.list.controller.offset;

      expect(afterDragUp, greaterThan(0.0));

      pointer.move(rayAt(panel.camera, const Offset(400, 350)));
      panel.surface.flush();

      expect(panel.list.controller.offset, lessThan(afterDragUp));
    });

    test('the content keeps up with the pointer', () {
      final panel = scrollingPanel();
      final pointer = Layout3dPointer(panel.surface);

      // Where the two screen points land in the list's own frame, which is
      // the frame the drag is measured in.
      final start = panel.surface
          .hitTestRay(rayAt(panel.camera, const Offset(400, 320)))
          .entryOf<Scrollable3d>()!
          .localPosition;
      final end = panel.surface
          .hitTestRay(rayAt(panel.camera, const Offset(400, 220)))
          .entryOf<Scrollable3d>()!
          .localPosition;

      pointer.down(rayAt(panel.camera, const Offset(400, 320)));
      pointer.move(rayAt(panel.camera, const Offset(400, 220)));

      // The list moved by exactly the distance the pointer travelled across
      // the plane, which is what "the content stays under the finger" means.
      expect(panel.list.controller.offset, closeTo(start.y - end.y, 1e-6));
    });

    test('keeps the drag after the pointer leaves the list', () {
      final panel = scrollingPanel();
      final pointer = Layout3dPointer(panel.surface);

      pointer.down(rayAt(panel.camera, const Offset(400, 300)));
      // Far above the panel: a fresh hit test would find nothing here.
      expect(
        panel.surface
            .hitTestRay(rayAt(panel.camera, const Offset(400, 20)))
            .isEmpty,
        isTrue,
      );

      expect(pointer.move(rayAt(panel.camera, const Offset(400, 20))), isTrue);
      expect(panel.list.controller.offset, greaterThan(0.0));
    });

    test('a press on nothing grabs nothing, and moves do not throw', () {
      final panel = scrollingPanel();
      final pointer = Layout3dPointer(panel.surface);

      expect(pointer.down(rayAt(panel.camera, const Offset(20, 20))), isFalse);
      expect(pointer.isDragging, isFalse);
      expect(pointer.move(rayAt(panel.camera, const Offset(30, 30))), isFalse);
      expect(panel.list.controller.offset, 0.0);
    });

    test('a press on content outside any scrolling view grabs nothing', () {
      final surface = laidOut(
        NodeBox3d(content: Node(), fallbackSize: const Size3d(2, 2, 0.2)),
        constraints: Constraints3d.tight(const Size3d(2, 2, 0.2)),
      );
      final camera = PerspectiveCamera(
        position: Vector3(0, 0, 5),
        target: Vector3.zero(),
      );
      final pointer = Layout3dPointer(surface);

      expect(
        pointer.down(camera.screenPointToRay(const Offset(400, 300), viewSize)),
        isFalse,
      );
      // It still reports what it found, which is the leaf holding content.
      expect(pointer.lastHit.target, isA<NodeBox3d>());
    });
  });
}
