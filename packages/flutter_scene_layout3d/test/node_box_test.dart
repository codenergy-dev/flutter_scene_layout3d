// NodeBox3d: how engine content reports a size, and where the box puts it.

import 'package:flutter_scene/scene.dart'
    show Mesh, Node, UnlitMaterial, UnskinnedGeometry;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Aabb3, Matrix4, Vector3;

import 'support.dart';

/// A node carrying real engine geometry whose bounds are stated outright.
///
/// Building a primitive would need a GPU context, but the measuring path this
/// package depends on, `Geometry.localBounds` to `Mesh.localBounds` to
/// `Node.combinedLocalBounds`, is the real one either way.
Node meshNode(Vector3 min, Vector3 max, {Matrix4? transform}) {
  final geometry = UnskinnedGeometry()
    ..setLocalBounds(Aabb3.minMax(min, max), null);
  return Node(mesh: Mesh(geometry, UnlitMaterial()), localTransform: transform);
}

/// A [NodeBox3d] whose content reports [bounds], standing in for real
/// geometry (which needs a GPU context to build).
class FakeContentBox extends NodeBox3d {
  FakeContentBox({
    required this.bounds,
    Node? content,
    super.fit,
    super.alignment,
    super.explicitSize,
    super.fallbackSize,
  }) : super(content: content ?? Node());

  final Aabb3? bounds;

  @override
  Aabb3? readContentBounds() => bounds;
}

Aabb3 boundsOf(Vector3 min, Vector3 max) => Aabb3.minMax(min, max);

void main() {
  group('measuring', () {
    test('takes its size from the content bounds', () {
      final box = FakeContentBox(
        bounds: boundsOf(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
      );
      laidOut(box);
      expect(box.size, const Size3d(2, 2, 2));
      expect(box.intrinsicSize, const Size3d(2, 2, 2));
    });

    test('maps the bounds through the surface basis', () {
      final box = FakeContentBox(
        bounds: boundsOf(Vector3(-1, -2, -3), Vector3(1, 2, 3)),
      );
      laidOut(box, basis: LayoutBasis3d.xz);
      // On the ground plane the scene z extent is the layout height.
      expect(box.size, const Size3d(2, 6, 4));
    });

    test('falls back when the content cannot report bounds', () {
      final box = FakeContentBox(
        bounds: null,
        fallbackSize: const Size3d(1, 2, 3),
      );
      laidOut(box);
      expect(box.size, const Size3d(1, 2, 3));
    });

    test('an explicit size skips measuring', () {
      final box = FakeContentBox(
        bounds: boundsOf(Vector3(-5, -5, -5), Vector3(5, 5, 5)),
        explicitSize: const Size3d(1, 1, 1),
      );
      laidOut(box);
      expect(box.size, const Size3d(1, 1, 1));
    });

    test('honours the constraints it is given', () {
      final box = FakeContentBox(
        bounds: boundsOf(Vector3.zero(), Vector3(8, 8, 8)),
      );
      laidOut(box, constraints: Constraints3d.loose(const Size3d(2, 2, 2)));
      expect(box.size, const Size3d(2, 2, 2));
    });
  });

  group('fit', () {
    final unitBounds = boundsOf(Vector3(-1, -1, -1), Vector3(1, 1, 1));

    test('a loose box is never inflated by a fit', () {
      // Like Flutter's FittedBox, the box takes the size of what it holds
      // when the parent leaves it a choice; a fit scales the content into
      // that box, it does not grow the box to fill the room on offer.
      for (final fit in BoxFit3d.values) {
        final box = FakeContentBox(bounds: unitBounds, fit: fit);
        laidOut(box, constraints: Constraints3d.loose(const Size3d(9, 9, 9)));
        expect(box.size, const Size3d(2, 2, 2), reason: '$fit');
        expect(box.contentScale, const Size3d.cube(1), reason: '$fit');
      }
    });

    test('contain scales the content into a tight box, uniformly', () {
      final box = FakeContentBox(bounds: unitBounds, fit: BoxFit3d.contain);
      laidOut(box, constraints: Constraints3d.tight(const Size3d(4, 8, 8)));
      // The box is what the parent demanded; the content is scaled by the
      // tightest axis, so it fits without distortion.
      expect(box.size, const Size3d(4, 8, 8));
      expect(box.contentScale, const Size3d.cube(2));
    });

    test('fill scales each axis on its own', () {
      final box = FakeContentBox(bounds: unitBounds, fit: BoxFit3d.fill);
      laidOut(box, constraints: Constraints3d.tight(const Size3d(4, 8, 2)));
      expect(box.size, const Size3d(4, 8, 2));
      expect(box.contentScale, const Size3d(2, 4, 1));
    });

    test('contain shrinks content that does not fit', () {
      final box = FakeContentBox(bounds: unitBounds, fit: BoxFit3d.contain);
      laidOut(box, constraints: Constraints3d.loose(const Size3d(1, 1, 1)));
      expect(box.size, const Size3d(1, 1, 1));
      expect(box.contentScale, const Size3d.cube(0.5));
    });

    test('scaleDown shrinks but never grows', () {
      final shrunk = FakeContentBox(
        bounds: unitBounds,
        fit: BoxFit3d.scaleDown,
      );
      laidOut(shrunk, constraints: Constraints3d.loose(const Size3d(1, 1, 1)));
      expect(shrunk.contentScale, const Size3d.cube(0.5));

      final kept = FakeContentBox(bounds: unitBounds, fit: BoxFit3d.scaleDown);
      laidOut(kept, constraints: Constraints3d.tight(const Size3d(9, 9, 9)));
      expect(kept.size, const Size3d(9, 9, 9));
      expect(kept.contentScale, const Size3d.cube(1));
    });

    test('none leaves the content alone, even when the box is smaller', () {
      final box = FakeContentBox(bounds: unitBounds);
      laidOut(box, constraints: Constraints3d.tight(const Size3d(1, 1, 1)));
      expect(box.size, const Size3d(1, 1, 1));
      expect(box.contentScale, const Size3d.cube(1));
    });

    test('an axis with no room does not collapse the content', () {
      // A panel whose padding ate its thickness leaves zero depth to fit
      // into. The content must stay visible and flat against the plane, not
      // be scaled out of existence, which is what a naive uniform fit does.
      for (final fit in BoxFit3d.values) {
        final box = FakeContentBox(bounds: unitBounds, fit: fit);
        laidOut(box, constraints: Constraints3d.tight(const Size3d(4, 4, 0)));
        expect(box.size, const Size3d(4, 4, 0), reason: '$fit');
        expect(box.contentScale.width, greaterThan(0.0), reason: '$fit');
        expect(box.contentScale.depth, greaterThan(0.0), reason: '$fit');
      }
    });
  });

  group('content placement', () {
    test('centres the content and undoes the basis', () {
      final box = FakeContentBox(
        bounds: boundsOf(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
      );
      laidOut(box, constraints: Constraints3d.tight(const Size3d(4, 4, 4)));

      final transform = box.content.localTransform;
      // The content's own origin lands at the centre of the box.
      final origin = transform.transformed3(Vector3.zero());
      expect(origin.x, closeTo(2, 1e-9));
      expect(origin.y, closeTo(2, 1e-9));
      expect(origin.z, closeTo(2, 1e-9));

      // A point that is up in scene space stays up: layout y grows downward,
      // so it lands at a smaller y.
      final up = transform.transformed3(Vector3(0, 1, 0));
      expect(up.y, closeTo(1, 1e-9));
    });

    test('content whose bounds are off its origin is still centred', () {
      final box = FakeContentBox(
        bounds: boundsOf(Vector3.zero(), Vector3(2, 2, 2)),
      );
      laidOut(box, constraints: Constraints3d.tight(const Size3d(2, 2, 2)));

      final transform = box.content.localTransform;
      // The centre of the content bounds lands at the centre of the box.
      final centre = transform.transformed3(Vector3(1, 1, 1));
      expect(centre.x, closeTo(1, 1e-9));
      expect(centre.y, closeTo(1, 1e-9));
      expect(centre.z, closeTo(1, 1e-9));
    });

    test('alignment moves the content within a larger box', () {
      final box = FakeContentBox(
        bounds: boundsOf(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
        alignment: Alignment3d.topLeftFront,
      );
      laidOut(box, constraints: Constraints3d.tight(const Size3d(4, 4, 4)));
      final origin = box.content.localTransform.transformed3(Vector3.zero());
      expect(origin.x, closeTo(1, 1e-9));
      expect(origin.y, closeTo(1, 1e-9));
      expect(origin.z, closeTo(1, 1e-9));
    });

    test('the content node hangs under the box node', () {
      final content = Node();
      final box = FakeContentBox(
        bounds: boundsOf(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
        content: content,
      );
      laidOut(box);
      expect(box.node.children, contains(content));
    });
  });

  group('real engine content', () {
    test('measures a node through combinedLocalBounds', () {
      final box = NodeBox3d(
        content: meshNode(Vector3(-1, -2, -3), Vector3(1, 2, 3)),
      );
      laidOut(box);
      expect(box.size, const Size3d(2, 4, 6));
    });

    test('measures a whole subtree, transforms and all', () {
      final content = Node()
        ..add(meshNode(Vector3(-1, -1, -1), Vector3(1, 1, 1)))
        ..add(
          meshNode(
            Vector3(-1, -1, -1),
            Vector3(1, 1, 1),
            transform: Matrix4.translationValues(4, 0, 0),
          ),
        );
      final box = NodeBox3d(content: content);
      laidOut(box);
      // The union spans x from -1 to 5.
      expect(box.size, const Size3d(6, 2, 2));

      // And the union's centre, not the content node's origin, is what lands
      // at the centre of the box.
      final centre = box.content.localTransform.transformed3(Vector3(2, 0, 0));
      expect(centre.x, closeTo(3, 1e-9));
      expect(centre.y, closeTo(1, 1e-9));
      expect(centre.z, closeTo(1, 1e-9));
    });

    test('scales real content to fit', () {
      final box = NodeBox3d(
        content: meshNode(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
        fit: BoxFit3d.contain,
      );
      laidOut(box, constraints: Constraints3d.tight(const Size3d(4, 8, 8)));
      expect(box.size, const Size3d(4, 8, 8));
      expect(box.contentScale, const Size3d.cube(2));
    });

    test('remeasure picks up geometry that changed size', () {
      final geometry = UnskinnedGeometry()
        ..setLocalBounds(Aabb3.minMax(Vector3.all(-1), Vector3.all(1)), null);
      final content = Node(mesh: Mesh(geometry, UnlitMaterial()));
      final box = NodeBox3d(content: content);
      final surface = laidOut(box);
      expect(box.size, const Size3d(2, 2, 2));

      geometry.setLocalBounds(
        Aabb3.minMax(Vector3.all(-2), Vector3.all(2)),
        null,
      );
      box.remeasure();
      surface.flush();
      expect(box.size, const Size3d(4, 4, 4));
    });

    test('a node with no geometry falls back', () {
      final box = NodeBox3d(
        content: Node(),
        fallbackSize: const Size3d(1, 1, 1),
      );
      laidOut(box);
      expect(box.size, const Size3d(1, 1, 1));
    });
  });

  test('a measured box takes part in a flex like any other', () {
    final first = FakeContentBox(
      bounds: boundsOf(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
    );
    final second = FakeContentBox(
      bounds: boundsOf(Vector3(-2, -0.5, -1), Vector3(2, 0.5, 1)),
    );
    final column = Column3d(
      mainAxisSize: MainAxisSize3d.min,
      children: [first, second],
    );
    laidOut(column);
    expect(first.size, const Size3d(2, 2, 2));
    expect(second.size, const Size3d(4, 1, 2));
    expect(column.size, const Size3d(4, 3, 2));
    expect(first.offset, const Offset3d(1, 0, 0));
    expect(second.offset, const Offset3d(0, 2, 0));
  });
}
