// The value types: constraints, insets, alignment, and the basis that maps
// layout space into the scene.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Aabb3, Vector3;

void main() {
  group('Constraints3d', () {
    test('constrain clamps every axis', () {
      const constraints = Constraints3d(
        minWidth: 1,
        maxWidth: 3,
        minHeight: 0,
        maxHeight: 2,
        minDepth: 0.5,
        maxDepth: 0.5,
      );
      expect(
        constraints.constrain(const Size3d(10, 1, 0)),
        const Size3d(3, 1, 0.5),
      );
      expect(
        constraints.constrain(const Size3d(0, 5, 9)),
        const Size3d(1, 2, 0.5),
      );
    });

    test('tight constraints admit exactly one size', () {
      final tight = Constraints3d.tight(const Size3d(2, 3, 4));
      expect(tight.isTight, isTrue);
      expect(tight.biggest, const Size3d(2, 3, 4));
      expect(tight.smallest, const Size3d(2, 3, 4));
    });

    test('deflate shrinks the maxima and never goes negative', () {
      final deflated = Constraints3d.tight(
        const Size3d(4, 4, 4),
      ).deflate(const EdgeInsets3d.all(1));
      expect(deflated.maxWidth, 2);
      expect(deflated.maxHeight, 2);
      expect(deflated.maxDepth, 2);

      final overflowed = Constraints3d.tight(
        const Size3d(1, 1, 1),
      ).deflate(const EdgeInsets3d.all(4));
      expect(overflowed.maxWidth, 0);
      expect(overflowed.minWidth, 0);
    });

    test('deflate leaves unbounded axes unbounded', () {
      final deflated = const Constraints3d().deflate(const EdgeInsets3d.all(1));
      expect(deflated.maxWidth, double.infinity);
      expect(deflated.minWidth, 0);
    });

    test('enforce clamps into the outer constraints', () {
      final inner = Constraints3d.tight(const Size3d(10, 10, 10));
      final outer = Constraints3d.loose(const Size3d(4, 4, 4));
      final enforced = inner.enforce(outer);
      expect(enforced.maxWidth, 4);
      expect(enforced.minWidth, 4);
    });

    test('withAxis and the axis accessors agree', () {
      final constraints = const Constraints3d().withAxis(
        Axis3d.depth,
        min: 1,
        max: 2,
      );
      expect(constraints.minAlong(Axis3d.depth), 1);
      expect(constraints.maxAlong(Axis3d.depth), 2);
      expect(constraints.hasBoundedAlong(Axis3d.horizontal), isFalse);
    });
  });

  group('EdgeInsets3d', () {
    test('deflateSize clamps at zero', () {
      const insets = EdgeInsets3d.symmetric(horizontal: 1, vertical: 2);
      expect(insets.deflateSize(const Size3d(4, 6, 1)), const Size3d(2, 2, 1));
      expect(insets.deflateSize(const Size3d(1, 1, 1)), const Size3d(0, 0, 1));
    });

    test('the origin corner is left, top, front', () {
      const insets = EdgeInsets3d.only(left: 1, top: 2, front: 3);
      expect(insets.topLeftFront, const Offset3d(1, 2, 3));
    });
  });

  group('Alignment3d', () {
    test('inscribe centres a child', () {
      expect(
        Alignment3d.center.inscribe(
          const Size3d(2, 2, 2),
          const Size3d(6, 6, 6),
        ),
        const Offset3d(2, 2, 2),
      );
    });

    test('the low corner is the origin corner', () {
      expect(
        Alignment3d.topLeftFront.inscribe(
          const Size3d(2, 2, 2),
          const Size3d(6, 6, 6),
        ),
        Offset3d.zero,
      );
      expect(
        Alignment3d.bottomRightBack.inscribe(
          const Size3d(2, 2, 2),
          const Size3d(6, 6, 6),
        ),
        const Offset3d(4, 4, 4),
      );
    });
  });

  group('LayoutBasis3d', () {
    test('xy stands the plane up, and layout right reads as right', () {
      final scene = LayoutBasis3d.xy.offsetToScene(const Offset3d(1, 2, 3));
      // Screen right is world -x for a camera in front of the plane, because
      // the engine builds its view basis with right = up x forward.
      expect(scene.x, -1);
      expect(scene.y, -2);
      expect(scene.z, -3);
    });

    test('xz lays the plane on the ground', () {
      final scene = LayoutBasis3d.xz.offsetToScene(const Offset3d(1, 2, 3));
      expect(scene.x, -1);
      expect(scene.y, -3);
      expect(scene.z, 2);
    });

    test('round trips through scene space', () {
      const offset = Offset3d(1.5, -2.25, 0.5);
      for (final basis in <LayoutBasis3d>[LayoutBasis3d.xy, LayoutBasis3d.xz]) {
        final roundTripped = basis.offsetToLayout(basis.offsetToScene(offset));
        expect(roundTripped.x, closeTo(offset.x, 1e-9));
        expect(roundTripped.y, closeTo(offset.y, 1e-9));
        expect(roundTripped.z, closeTo(offset.z, 1e-9));
      }
    });

    test('measures scene bounds in layout axes', () {
      final bounds = Aabb3.minMax(Vector3(-1, -2, -3), Vector3(1, 2, 3));
      expect(LayoutBasis3d.xy.sizeOfBounds(bounds), const Size3d(2, 4, 6));
      // On the ground plane, the scene's z extent is the layout height and
      // the scene's y extent is the layout depth.
      expect(LayoutBasis3d.xz.sizeOfBounds(bounds), const Size3d(2, 6, 4));
    });
  });
}
