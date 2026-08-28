// Camera-bound surfaces: the frustum arithmetic that gives a plane a screen's
// worth of constraints, and the unit contract that falls out of it.

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene/scene.dart'
    show Camera, CameraProjection, Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart'
    show Layout3dController, SceneLayout3d, SceneSizedBox3d;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector2, Vector3;

import 'support.dart';

/// A camera in front of the plane, at [distance] on the `+z` side, which is
/// the side [LayoutBasis3d.xy] puts the viewer on.
PerspectiveCamera frontCamera({
  double distance = 5,
  double fovRadiansY = math.pi / 4,
}) => PerspectiveCamera(
  fovRadiansY: fovRadiansY,
  position: Vector3(0, 0, distance),
  target: Vector3(0, 0, 0),
);

/// An orthographic lens, which `flutter_scene` does not ship yet.
///
/// The binding reads the projection matrix rather than a
/// `PerspectiveProjection`'s field of view, so it needs no branch for this
/// case and none when the engine grows one: `m32` is zero and `m33` is one,
/// so the derived extents drop their dependence on distance by themselves.
class TestOrthographicProjection extends CameraProjection {
  TestOrthographicProjection({required this.height});

  /// The world-space height the lens covers, at any distance.
  final double height;

  // `jitter` is the engine's temporal-antialiasing offset. An orthographic
  // test lens has no use for it, but the override has to carry it.
  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) {
    final halfHeight = height / 2;
    final halfWidth = halfHeight * aspectRatio;
    return Matrix4(
      1 / halfWidth,
      0,
      0,
      0, //
      0,
      1 / halfHeight,
      0,
      0, //
      0,
      0,
      0.01,
      0, //
      0,
      0,
      0,
      1, //
    );
  }
}

/// A camera that borrows a [PerspectiveCamera]'s view and swaps its lens.
class TestLensCamera extends Camera {
  TestLensCamera(this._view, this.projection);

  final PerspectiveCamera _view;

  @override
  final CameraProjection projection;

  @override
  Vector3 get position => _view.position;

  @override
  Vector3 get forward => _view.forward;

  @override
  Vector3 get up => _view.up;

  @override
  Matrix4 getViewMatrix() => _view.getViewMatrix();
}

/// Where a layout-space point on [surface] lands in the world.
Vector3 worldOf(Layout3dSurface surface, Offset3d point) => surface
    .node
    .globalTransform
    .transformed3(Vector3(point.x, point.y, point.z));

void main() {
  const view = Size(800, 600);

  group('screenFilling', () {
    test('derives the frustum extents at the plane\'s distance', () {
      final surface = Layout3dSurface();
      const binding = Layout3dCameraBinding.screenFilling(distance: 2);
      binding.update(surface, camera: frontCamera(), viewSize: view);

      // height = 2 * distance * tan(fov / 2), width = height * aspect.
      final height = 2 * 2 * math.tan(math.pi / 8);
      final width = height * 800 / 600;
      expect(surface.configuration.isTight, isTrue);
      expect(surface.configuration.maxHeight, closeTo(height, 1e-4));
      expect(surface.configuration.maxWidth, closeTo(width, 1e-4));
      expect(surface.configuration.maxDepth, 0);

      surface.flush();
      expect(surface.size.height, closeTo(height, 1e-4));
    });

    test('scales with distance for a perspective lens', () {
      final near = Layout3dSurface();
      final far = Layout3dSurface();
      const nearBinding = Layout3dCameraBinding.screenFilling(distance: 2);
      const farBinding = Layout3dCameraBinding.screenFilling(distance: 6);
      nearBinding.update(near, camera: frontCamera(), viewSize: view);
      farBinding.update(far, camera: frontCamera(), viewSize: view);
      expect(
        far.configuration.maxHeight,
        closeTo(near.configuration.maxHeight * 3, 1e-3),
      );
    });

    test('takes depth from the caller, since no frustum supplies it', () {
      final surface = Layout3dSurface();
      const binding = Layout3dCameraBinding.screenFilling(
        distance: 2,
        depth: 0.5,
      );
      binding.update(surface, camera: frontCamera(), viewSize: view);
      expect(surface.configuration.minDepth, 0.5);
      expect(surface.configuration.maxDepth, 0.5);
    });

    test('the plane covers the view exactly, corner to corner', () {
      final surface = Layout3dSurface(child: TestBox(const Size3d(1, 1, 0)));
      const binding = Layout3dCameraBinding.screenFilling(distance: 2);
      final camera = frontCamera();
      binding.update(surface, camera: camera, viewSize: view);
      surface.flush();

      final size = surface.size;
      final topLeft = camera.worldToScreen(
        worldOf(surface, Offset3d.zero),
        view,
      )!;
      final bottomRight = camera.worldToScreen(
        worldOf(surface, Offset3d(size.width, size.height, 0)),
        view,
      )!;
      expect(topLeft.dx, closeTo(0, 0.05));
      expect(topLeft.dy, closeTo(0, 0.05));
      expect(bottomRight.dx, closeTo(800, 0.05));
      expect(bottomRight.dy, closeTo(600, 0.05));
    });

    test('a box of n logical pixels measures n pixels on screen', () {
      final surface = Layout3dSurface(child: TestBox(const Size3d(1, 1, 0)));
      const binding = Layout3dCameraBinding.screenFilling(distance: 3);
      final camera = frontCamera();
      binding.update(surface, camera: camera, viewSize: view);
      surface.flush();

      // The inversion this whole plan exists for: a component asks for 48dp
      // in world units and gets 48 logical pixels on the screen.
      final extent = surface.metrics.dp(48);
      final left = camera.worldToScreen(
        worldOf(surface, const Offset3d(0.4, 0.4, 0)),
        view,
      )!;
      final right = camera.worldToScreen(
        worldOf(surface, Offset3d(0.4 + extent, 0.4, 0)),
        view,
      )!;
      final down = camera.worldToScreen(
        worldOf(surface, Offset3d(0.4, 0.4 + extent, 0)),
        view,
      )!;
      expect(right.dx - left.dx, closeTo(48, 0.01));
      expect(down.dy - left.dy, closeTo(48, 0.01));
    });

    test('the metrics follow the view height, not the view width', () {
      final surface = Layout3dSurface();
      const binding = Layout3dCameraBinding.screenFilling(distance: 2);
      binding.update(surface, camera: frontCamera(), viewSize: view);
      final tall = surface.metrics.unitsPerLogicalPixel;
      expect(tall, closeTo(surface.configuration.maxHeight / 600, 1e-12));

      // A wider view at the same height covers more world horizontally and
      // leaves the scale alone.
      binding.update(
        surface,
        camera: frontCamera(),
        viewSize: const Size(1200, 600),
      );
      expect(surface.metrics.unitsPerLogicalPixel, closeTo(tall, 1e-9));
      expect(
        surface.configuration.maxWidth,
        closeTo(2 * 2 * math.tan(math.pi / 8) * 2, 1e-4),
      );
    });

    test('passes the dials it cannot derive through to the metrics', () {
      final surface = Layout3dSurface();
      const binding = Layout3dCameraBinding.screenFilling(
        distance: 2,
        textScaleFactor: 1.4,
        density: VisualDensity3d.compact,
      );
      binding.update(surface, camera: frontCamera(), viewSize: view);
      expect(surface.metrics.textScaleFactor, 1.4);
      expect(surface.metrics.density, VisualDensity3d.compact);
    });

    test('a degenerate view is a no-op rather than an error', () {
      final surface = Layout3dSurface();
      const binding = Layout3dCameraBinding.screenFilling(distance: 2);
      binding.update(surface, camera: frontCamera(), viewSize: Size.zero);
      expect(surface.configuration, const Constraints3d());
      expect(surface.metrics, Layout3dMetrics.standard);
    });
  });

  group('the cost of a moving camera', () {
    Layout3dSurface bound(
      Camera camera, {
      Layout3dCameraBinding binding = const Layout3dCameraBinding.screenFilling(
        distance: 2,
      ),
      Size viewSize = const Size(800, 600),
    }) {
      final surface = Layout3dSurface(child: TestBox(const Size3d(1, 1, 0)));
      binding.update(surface, camera: camera, viewSize: viewSize);
      surface.flush();
      return surface;
    }

    test('a camera panning at a fixed distance relayouts nothing', () {
      final camera = frontCamera();
      final surface = bound(camera);
      const binding = Layout3dCameraBinding.screenFilling(distance: 2);

      // Turn the camera in place. The frustum at the plane's distance is the
      // same frustum, so the constraints are the same constraints.
      camera.target = Vector3(1, 0.5, 0);
      binding.update(surface, camera: camera, viewSize: const Size(800, 600));
      expect(surface.needsFlush, isFalse);
    });

    test('a camera translating along its forward axis relayouts nothing', () {
      // The plan predicted the opposite, and the plan was wrong: the plane is
      // pinned a fixed distance in front of the eye, so walking forward
      // carries it along and the frustum at that distance never changes. What
      // re-derives is a change of view size, field of view, or distance.
      final camera = frontCamera();
      final surface = bound(camera);
      const binding = Layout3dCameraBinding.screenFilling(distance: 2);
      final before = surface.plane.localTransform.getTranslation();

      camera.position = Vector3(0, 0, 9);
      camera.target = Vector3(0, 0, 4);
      binding.update(surface, camera: camera, viewSize: const Size(800, 600));
      expect(surface.needsFlush, isFalse);

      // The plane followed, though: it stays two units in front of the eye.
      final after = surface.plane.localTransform.getTranslation();
      expect(after.z - before.z, closeTo(4, 1e-6));
      expect(after.z, closeTo(7, 1e-6));
    });

    test('a change of view size re-derives and relayouts', () {
      final camera = frontCamera();
      final surface = bound(camera);
      const binding = Layout3dCameraBinding.screenFilling(distance: 2);
      binding.update(surface, camera: camera, viewSize: const Size(400, 600));
      expect(surface.needsFlush, isTrue);
      surface.flush();
      expect(
        surface.size.width,
        closeTo(surface.size.height * 400 / 600, 1e-4),
      );
    });

    test('a still camera writes nothing at all, not even a transform', () {
      final camera = frontCamera();
      final surface = bound(camera);
      const binding = Layout3dCameraBinding.screenFilling(distance: 2);
      final transform = surface.plane.localTransform;
      binding.update(surface, camera: camera, viewSize: const Size(800, 600));
      expect(surface.needsFlush, isFalse);
      // The same matrix object: the setter was never reached, so the node's
      // cached world transforms were never invalidated.
      expect(identical(surface.plane.localTransform, transform), isTrue);
    });

    test('the epsilon swallows a change smaller than a ten-thousandth', () {
      // dHeight/dFov at this distance is about 2.34, so a 1e-5 radian nudge
      // moves the derived height by ~2.3e-5 — inside the default 1e-4 dead
      // band, and therefore not a size change.
      final camera = frontCamera();
      final surface = bound(camera);
      const binding = Layout3dCameraBinding.screenFilling(distance: 2);

      camera.fovRadiansY += 1e-5;
      binding.update(surface, camera: camera, viewSize: const Size(800, 600));
      expect(surface.needsFlush, isFalse);

      // A hundred times more is a real change, and does relayout.
      camera.fovRadiansY += 1e-3;
      binding.update(surface, camera: camera, viewSize: const Size(800, 600));
      expect(surface.needsFlush, isTrue);
    });

    test('turning the epsilon off lets the same nudge through', () {
      final camera = frontCamera();
      const binding = Layout3dCameraBinding.screenFilling(
        distance: 2,
        extentEpsilon: 0,
      );
      final surface = bound(camera, binding: binding);

      camera.fovRadiansY += 1e-5;
      binding.update(surface, camera: camera, viewSize: const Size(800, 600));
      expect(surface.needsFlush, isTrue);
    });

    test('the epsilon is the stated one, and is a dead band', () {
      expect(Layout3dCameraBinding.defaultExtentEpsilon, 1e-4);
      // A dead band keeps the extent it already had, rather than snapping to
      // a grid: the extents stay exactly what the frustum said the first time
      // they were assigned, so the surface really does cover the view.
      final camera = frontCamera();
      final surface = bound(camera);
      final exact = 2 * 2 * math.tan(math.pi / 8);
      final settled = surface.size.height;
      expect(settled, closeTo(exact, 1e-6));

      camera.fovRadiansY += 1e-5;
      const Layout3dCameraBinding.screenFilling(
        distance: 2,
      ).update(surface, camera: camera, viewSize: const Size(800, 600));
      expect(surface.configuration.maxHeight, settled);
    });
  });

  group('billboard', () {
    test('writes no constraints, no metrics, and marks no layout dirty', () {
      final surface = Layout3dSurface(
        constraints: Constraints3d.tight(const Size3d(4, 3, 0.5)),
        child: TestBox(const Size3d(1, 1, 1)),
      );
      surface.plane.localTransform = Matrix4.translationValues(1, 2, -3);
      surface.flush();
      expect(surface.needsFlush, isFalse);

      const binding = Layout3dCameraBinding.billboard();
      binding.update(surface, camera: frontCamera());

      expect(surface.needsFlush, isFalse);
      expect(
        surface.configuration,
        Constraints3d.tight(const Size3d(4, 3, 0.5)),
      );
      expect(surface.metrics, Layout3dMetrics.standard);
    });

    test(
      'keeps the position the application set and takes only the facing',
      () {
        final surface = Layout3dSurface(child: TestBox(const Size3d(1, 1, 1)));
        surface.plane.localTransform = Matrix4.translationValues(1, 2, -3);
        surface.flush();

        const binding = Layout3dCameraBinding.billboard();
        binding.update(surface, camera: frontCamera());

        final transform = surface.plane.localTransform;
        expect(transform.getTranslation(), Vector3(1, 2, -3));
        // A camera on the +z side looking at the origin leaves the plane
        // upright and unturned, which is the basis the layout already assumes.
        expect(transform.getColumn(0).xyz.x, closeTo(1, 1e-9));
        expect(transform.getColumn(1).xyz.y, closeTo(1, 1e-9));
        expect(transform.getColumn(2).xyz.z, closeTo(1, 1e-9));
      },
    );

    test('turns to a camera that moved around the plane', () {
      final surface = Layout3dSurface(child: TestBox(const Size3d(1, 1, 1)));
      surface.flush();
      const binding = Layout3dCameraBinding.billboard();
      binding.update(
        surface,
        camera: PerspectiveCamera(
          position: Vector3(5, 0, 0),
          target: Vector3(0, 0, 0),
        ),
      );
      // The plane's local +z, which the basis puts toward the viewer, now
      // points at the camera's side of the world.
      final toward = surface.plane.localTransform.getColumn(2).xyz;
      expect(toward.x, closeTo(1, 1e-9));
      expect(toward.z.abs(), closeTo(0, 1e-9));
    });
  });

  group('fixedDensity', () {
    test('writes the metrics, needs no camera, and touches nothing else', () {
      final box = DpBox(100, 40);
      final surface = laidOut(Center3d(child: box));
      const binding = Layout3dCameraBinding.fixedDensity(0.005);

      binding.update(surface);
      expect(surface.needsFlush, isTrue);
      surface.flush();

      expect(surface.metrics.unitsPerLogicalPixel, 0.005);
      expect(surface.configuration, const Constraints3d());
      expect(box.size.width, closeTo(0.5, 1e-12));
    });

    test('carries the dials it is given', () {
      final surface = Layout3dSurface();
      const binding = Layout3dCameraBinding.fixedDensity(
        0.005,
        textScaleFactor: 1.2,
        density: VisualDensity3d.comfortable,
      );
      binding.update(surface);
      expect(surface.metrics.textScaleFactor, 1.2);
      expect(surface.metrics.density, VisualDensity3d.comfortable);
    });

    test('an authored scale lays a box out exactly as a derived one does', () {
      // The point of the contract: nothing downstream can tell where the
      // number came from.
      final derivedBox = DpBox(120, 44);
      final derived = Layout3dSurface(child: Center3d(child: derivedBox));
      const screen = Layout3dCameraBinding.screenFilling(distance: 3);
      screen.update(derived, camera: frontCamera(), viewSize: view);
      derived.flush();

      final authoredBox = DpBox(120, 44);
      final authored = Layout3dSurface(child: Center3d(child: authoredBox));
      Layout3dCameraBinding.fixedDensity(
        derived.metrics.unitsPerLogicalPixel,
      ).update(authored);
      authored.flush();

      expect(authoredBox.size, derivedBox.size);
    });
  });

  group('an orthographic lens', () {
    test('covers the same extents whatever the distance', () {
      final camera = TestLensCamera(
        frontCamera(),
        TestOrthographicProjection(height: 3),
      );
      final near = Layout3dSurface();
      final far = Layout3dSurface();
      const Layout3dCameraBinding.screenFilling(
        distance: 1,
      ).update(near, camera: camera, viewSize: view);
      const Layout3dCameraBinding.screenFilling(
        distance: 8,
      ).update(far, camera: camera, viewSize: view);

      expect(near.configuration.maxHeight, closeTo(3, 1e-6));
      expect(near.configuration.maxWidth, closeTo(4, 1e-6));
      expect(far.configuration.maxHeight, closeTo(3, 1e-6));
      expect(far.configuration.maxWidth, closeTo(4, 1e-6));
      expect(
        near.metrics.unitsPerLogicalPixel,
        closeTo(far.metrics.unitsPerLogicalPixel, 1e-12),
      );
    });
  });

  group('the declarative wiring', () {
    testWidgets('a bound SceneLayout3d sizes itself from the view', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          controller: controller,
          camera: frontCamera(),
          viewSize: view,
          binding: const Layout3dCameraBinding.screenFilling(
            distance: 2,
            depth: 0.5,
          ),
          child: const SceneSizedBox3d.cube(0.2),
        ),
      );
      // The binding runs after the frame, because it reads the enclosing
      // view's box and a box's size is only legible during its own parent's
      // layout. The relayout it asks for lands on the next one.
      await tester.pump();

      final surface = controller.surface!;
      final height = 2 * 2 * math.tan(math.pi / 8);
      expect(surface.size.height, closeTo(height, 1e-4));
      expect(surface.size.depth, 0.5);
      expect(surface.metrics.unitsPerLogicalPixel, closeTo(height / 600, 1e-6));
    });

    testWidgets('an authored density reaches the boxes below', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          controller: controller,
          size: const Size3d(4, 3, 0.5),
          binding: const Layout3dCameraBinding.fixedDensity(0.005),
          child: const SceneSizedBox3d.cube(0.2),
        ),
      );
      await tester.pump();
      expect(controller.surface!.metrics.unitsPerLogicalPixel, 0.005);
      // The authored binding leaves the widget's own size alone.
      expect(controller.surface!.size, const Size3d(4, 3, 0.5));
    });

    testWidgets('dropping the binding hands the contract back', (tester) async {
      final controller = Layout3dController();
      Widget frame({Layout3dCameraBinding? binding}) => SceneLayout3d(
        parent: Node(),
        controller: controller,
        size: const Size3d(4, 3, 0.5),
        binding: binding,
        child: const SceneSizedBox3d.cube(0.2),
      );

      await tester.pumpWidget(
        frame(binding: const Layout3dCameraBinding.fixedDensity(0.005)),
      );
      await tester.pump();
      expect(controller.surface!.metrics.unitsPerLogicalPixel, 0.005);

      await tester.pumpWidget(frame());
      await tester.pump();
      expect(controller.surface!.metrics, Layout3dMetrics.standard);
    });

    testWidgets('a screen-filling binding refuses a size of its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          camera: frontCamera(),
          viewSize: view,
          size: const Size3d(4, 3, 0.5),
          binding: const Layout3dCameraBinding.screenFilling(distance: 2),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });
  });
}
