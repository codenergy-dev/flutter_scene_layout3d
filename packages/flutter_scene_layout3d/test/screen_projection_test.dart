// Where a laid-out box lands on screen.
//
// This is the arithmetic behind the render probes in `examples/render_probe`:
// a test there asserts the frame has geometry at the pixel these functions
// name. That makes the projection load-bearing for every render assertion, so
// it is pinned down here, headlessly, where a failure is legible — rather than
// only ever failing as "the probe found nothing" on a machine with a GPU.

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:flutter_scene/scene.dart' show Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support.dart';

const Size _view = Size(800, 600);

PerspectiveCamera _camera({double distance = 6}) => PerspectiveCamera(
  fovRadiansY: math.pi / 4,
  position: Vector3(0, 0, distance),
  target: Vector3(0, 0, 0),
);

/// A camera raised above the ground and looking down at it.
///
/// A level camera sees the xz plane exactly edge-on, so every point on it
/// projects onto the horizon line and "further away" is indistinguishable
/// from "nearer". A ground plane is only legible from above it.
PerspectiveCamera _raisedCamera() => PerspectiveCamera(
  fovRadiansY: math.pi / 4,
  position: Vector3(0, 4, 6),
  target: Vector3(0, 0, 0),
);

/// A surface mounted under a root node and laid out, the way a real scene has
/// it: [Layout3d.worldTransform] reads the node's global transform, so nothing
/// here means anything until the surface hangs off something.
Layout3dSurface _mounted(Layout3d child, {LayoutBasis3d? basis, Size3d? size}) {
  final surface = Layout3dSurface(
    basis: basis,
    constraints: Constraints3d.tight(size ?? const Size3d(4, 3, 1)),
    child: child,
  );
  Node().add(surface.plane);
  surface.flush();
  return surface;
}

void main() {
  group('screenCenter', () {
    test('a box centred on the origin projects to the centre of the view', () {
      final box = TestBox(const Size3d(2, 2, 0));
      _mounted(Center3d(child: box), size: const Size3d(4, 4, 0));

      final centre = box.screenCenter(_camera(), _view);
      expect(centre, isNotNull);
      expect(centre!.dx, closeTo(_view.width / 2, 0.5));
      expect(centre.dy, closeTo(_view.height / 2, 0.5));
    });

    test('layout down is screen down, and layout right is screen right', () {
      final leading = TestBox(const Size3d(1, 1, 0));
      final trailing = TestBox(const Size3d(1, 1, 0));
      _mounted(
        Column3d(children: [leading, trailing]),
        size: const Size3d(4, 4, 0),
      );

      final top = leading.screenCenter(_camera(), _view)!;
      final bottom = trailing.screenCenter(_camera(), _view)!;
      // y grows downward in layout space and downward on screen, so the
      // second child of a column is lower on screen. Getting this backwards
      // is the classic sign error, and it would make every probe check the
      // wrong half of the frame.
      expect(bottom.dy, greaterThan(top.dy));
      expect(bottom.dx, closeTo(top.dx, 0.5));
    });

    test('a row runs left to right on screen', () {
      final first = TestBox(const Size3d(1, 1, 0));
      final second = TestBox(const Size3d(1, 1, 0));
      _mounted(Row3d(children: [first, second]), size: const Size3d(4, 2, 0));

      final left = first.screenCenter(_camera(), _view)!;
      final right = second.screenCenter(_camera(), _view)!;
      expect(right.dx, greaterThan(left.dx));
      expect(right.dy, closeTo(left.dy, 0.5));
    });

    test('null before layout, because there is nowhere to be yet', () {
      final box = TestBox(const Size3d(1, 1, 1));
      expect(box.screenCenter(_camera(), _view), isNull);
    });

    test('null when the box sits behind the camera', () {
      final box = TestBox(const Size3d(1, 1, 0));
      final surface = _mounted(Center3d(child: box));
      // Put the plane well behind the lens.
      surface.plane.position = Vector3(0, 0, 20);
      surface.flush();

      expect(box.screenCenter(_camera(), _view), isNull);
    });
  });

  group('the ground plane', () {
    test('on xz, a column advances toward the viewer', () {
      final first = TestBox(const Size3d(1, 1, 0));
      final second = TestBox(const Size3d(1, 1, 0));
      _mounted(
        Column3d(children: [first, second]),
        basis: LayoutBasis3d.xz,
        size: const Size3d(4, 4, 0),
      );

      // `xz` maps layout y to scene +z, and the camera sits at +z, so going
      // "down" a column on the floor walks *toward* the viewer — the second
      // child is nearer, and a nearer thing on a ground plane projects lower
      // on screen. The prose in both READMEs used to claim the opposite; this
      // test is what caught it. See LayoutBasis3d.xz's own dartdoc, which had
      // it right all along.
      final firstPoint = first.screenCenter(_raisedCamera(), _view)!;
      final secondPoint = second.screenCenter(_raisedCamera(), _view)!;
      expect(secondPoint.dy, greaterThan(firstPoint.dy));
    });

    test('the same tree projects differently on xy and xz', () {
      Offset centreOf(LayoutBasis3d basis) {
        final box = TestBox(const Size3d(1, 1, 0));
        _mounted(
          Column3d(children: [TestBox(const Size3d(1, 1, 0)), box]),
          basis: basis,
          size: const Size3d(4, 4, 0),
        );
        return box.screenCenter(_raisedCamera(), _view)!;
      }

      expect(
        centreOf(LayoutBasis3d.xy).dy,
        isNot(closeTo(centreOf(LayoutBasis3d.xz).dy, 1.0)),
      );
    });
  });

  group('screenPointOf', () {
    test('the origin corner is the top left of an upright box', () {
      final box = TestBox(const Size3d(2, 2, 0));
      _mounted(Center3d(child: box), size: const Size3d(4, 4, 0));

      final origin = box.screenPointOf(Offset3d.zero, _camera(), _view)!;
      final far = box.screenPointOf(const Offset3d(1, 1, 0), _camera(), _view)!;
      expect(origin.dx, lessThan(far.dx));
      expect(origin.dy, lessThan(far.dy));
    });

    test('a fraction outside the box projects the space around it, which is '
        'how a probe checks a gap is empty', () {
      final box = TestBox(const Size3d(1, 1, 0));
      _mounted(Center3d(child: box), size: const Size3d(4, 4, 0));

      final centre = box.screenCenter(_camera(), _view)!;
      final beyond = box.screenPointOf(
        const Offset3d(3, 0.5, 0.5),
        _camera(),
        _view,
      )!;
      expect(beyond.dx, greaterThan(centre.dx));
    });
  });

  group('screenBounds', () {
    test('contains the centre, and grows with the box', () {
      Rect boundsFor(double extent) {
        final box = TestBox(Size3d(extent, extent, 0));
        _mounted(Center3d(child: box), size: const Size3d(8, 8, 0));
        return box.screenBounds(_camera(), _view)!;
      }

      final small = boundsFor(1);
      final large = boundsFor(3);
      expect(small.contains(Offset(_view.width / 2, _view.height / 2)), isTrue);
      expect(large.width, greaterThan(small.width));
      expect(large.height, greaterThan(small.height));
    });

    test('a nearer surface projects larger, which is perspective working', () {
      Rect boundsAt(double distance) {
        final box = TestBox(const Size3d(1, 1, 0));
        _mounted(Center3d(child: box), size: const Size3d(4, 4, 0));
        return box.screenBounds(_camera(distance: distance), _view)!;
      }

      expect(boundsAt(3).width, greaterThan(boundsAt(9).width));
    });

    test('null before layout', () {
      expect(
        TestBox(const Size3d(1, 1, 1)).screenBounds(_camera(), _view),
        isNull,
      );
    });
  });
}
