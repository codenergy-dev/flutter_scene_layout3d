import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart' show Alignment, SizedBox, Stack, Widget;
import 'package:flutter_scene/scene.dart' show Camera, Node, PerspectiveCamera;
import 'package:flutter_test/flutter_test.dart'
    show FinderBase, Plurality, TestFailure, TestPointer, WidgetTester;
import 'package:vector_math/vector_math.dart' show Vector3;

import '../geometry/basis3d.dart';
import '../geometry/size3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import '../metrics.dart';
import '../surface.dart';
import '../widgets/input.dart';
import '../widgets/surface.dart';
import 'scene.dart';

/// A camera looking straight at [surface]'s front face and framing all of it
/// in a view of [viewSize].
///
/// Straight at means down the surface's own depth axis, from the side the
/// viewer is on, with layout's "up" at the top of the view — whatever the
/// surface's basis, so a panel on the ground is looked at from above. The
/// distance fits the face's width and height into the view with [margin] to
/// spare.
///
/// The surface has to be laid out and mounted: its size and its place in the
/// world are what the camera is placed from.
PerspectiveCamera cameraFacing3d(
  Layout3dSurface surface, {
  Size viewSize = const Size(800, 600),
  double margin = 1.1,
  double fovRadiansY = math.pi / 4,
}) {
  final camera = PerspectiveCamera(fovRadiansY: fovRadiansY);
  _frame(camera, surface, viewSize: viewSize, margin: margin);
  return camera;
}

void _frame(
  PerspectiveCamera camera,
  Layout3dSurface surface, {
  required Size viewSize,
  double margin = 1.1,
}) {
  final size = surface.hasSize ? surface.size : Size3d.zero;
  final halfTan = math.tan(camera.fovRadiansY / 2);
  final aspect = viewSize.height == 0 ? 1.0 : viewSize.width / viewSize.height;
  final fitHeight = (size.height / 2) / halfTan;
  final fitWidth = (size.width / 2) / (halfTan * aspect);
  final distance = math.max(math.max(fitHeight, fitWidth), 1e-3) * margin;

  // Layout space runs x right, y down and z away from the viewer, from the
  // surface's front, top, left corner; the surface's node takes it into the
  // world.
  final toWorld = surface.node.globalTransform;
  final center = toWorld.transformed3(
    Vector3(size.width / 2, size.height / 2, 0),
  );
  final eye = toWorld.transformed3(
    Vector3(size.width / 2, size.height / 2, -distance),
  );
  final up = toWorld.rotated3(Vector3(0, -1, 0))..normalize();
  camera.position.setFrom(eye);
  camera.target.setFrom(center);
  camera.up.setFrom(up);
}

/// Pumping a 3D screen, finding what is on it, and pressing it the way a
/// person would.
///
/// A press here is a tap on the **screen**: the box's centre is projected
/// through the camera of the [SceneInput3d] above it, and Flutter's own
/// `tapAt` taps that point. Everything between the platform and the box runs
/// — the ray, the order of the surfaces, absorption, the overlay's entries,
/// the gesture arena — which is the path an application runs and the one a
/// ray aimed down a surface's own depth axis skips.
extension Layout3dWidgetTester on WidgetTester {
  /// Mounts [child] on one surface under a [SceneInput3d] whose camera looks
  /// straight at it, and returns the surface.
  ///
  /// The default [size] is an 800 × 600 dp screen at the standard metrics —
  /// the test view's own size — and a whole world unit deep, which is room
  /// for a Material screen to stack its slots and put an overlay in front of
  /// them. A theme, an overlay, anything [child] needs from above goes inside
  /// [child]: the surface is the root of the layout tree.
  ///
  /// Nothing here draws. A `SceneView` needs a GPU, so its place is taken by
  /// a box that fills the view, which is all the host reads.
  Future<Layout3dSurface> pumpSurface3d(
    Widget child, {
    Size3d size = const Size3d(8, 6, 1),
    LayoutBasis3d? basis,
    Layout3dMetrics? metrics,
  }) async {
    final controller = Layout3dController();
    await pumpScene3d(<Widget>[
      SceneLayout3d(
        parent: Node(),
        controller: controller,
        size: size,
        basis: basis,
        metrics: metrics,
        child: child,
      ),
    ]);
    return controller.surface!;
  }

  /// Mounts [surfaces] — `SceneLayout3d`s, or widgets that build them —
  /// under a [SceneInput3d].
  ///
  /// With no [camera], the host's camera is placed by [cameraFacing3d] to
  /// look straight at the first surface. Give one to ask about a scene the
  /// way the application frames it: a panel turned away, two surfaces one in
  /// front of the other.
  ///
  /// A screen that builds its own [SceneInput3d] needs none of this: pump it
  /// with `pumpWidget`, and everything else here finds the host it is under.
  Future<void> pumpScene3d(List<Widget> surfaces, {Camera? camera}) async {
    final framed = camera == null ? PerspectiveCamera() : null;
    await pumpWidget(
      SceneInput3d(
        camera: camera ?? framed,
        child: SizedBox.expand(
          // Non-directional: a surface takes no space, and a Directionality
          // is the screen's to provide, not the harness's.
          child: Stack(alignment: Alignment.topLeft, children: surfaces),
        ),
      ),
    );
    if (framed != null) {
      final records = sceneSurfaces3d();
      if (records.isNotEmpty) {
        final host = records.first.host;
        _frame(
          framed,
          records.first.surface,
          viewSize: host?.size ?? view.physicalSize / view.devicePixelRatio,
        );
      }
    }
  }

  /// Every surface in the widget tree, in tree order, each overlay's detached
  /// entries straight after the surface the overlay is on.
  List<Layout3dSurface> get surfaces3d => <Layout3dSurface>[
    for (final record in sceneSurfaces3d()) record.surface,
  ];

  /// The one box [finder] finds, as a [T].
  ///
  /// Fails the test when it finds none or more than one, the way
  /// `tester.widget` does.
  T layout3d<T extends Layout3d>(FinderBase<Layout3d> finder) {
    final found = finder.evaluate().toList();
    if (found.length != 1) {
      throw TestFailure(
        'Expected exactly one ${finder.describeMatch(Plurality.one)}, and '
        '${found.isEmpty ? 'found none' : 'found ${found.length}'}.',
      );
    }
    final box = found.single;
    if (box is! T) {
      throw TestFailure(
        'Expected the ${finder.describeMatch(Plurality.one)} to be a $T, and '
        'it is ${describeBox3d(box)}.',
      );
    }
    return box;
  }

  /// Every box [finder] finds that is a [T].
  Iterable<T> layouts3d<T extends Layout3d>(FinderBase<Layout3d> finder) =>
      finder.evaluate().whereType<T>();

  /// Where the one box [finder] finds is on the screen, in global
  /// coordinates: its centre, projected through the camera of the host above
  /// it.
  ///
  /// The point [tap3d] presses, and the one to move a mouse `TestGesture` to
  /// for a hover.
  Offset getCenter3d(FinderBase<Layout3d> finder) {
    final reach = Reach3d.of(layout3d<Layout3d>(finder), sceneSurfaces3d());
    final global = reach.global;
    if (global == null) {
      throw TestFailure(
        'Cannot say where the ${finder.describeMatch(Plurality.one)} is on '
        'the screen: ${reach.describeMiss()}',
      );
    }
    return global;
  }

  /// Every path a press at [position], in global coordinates, would be
  /// dispatched to, front to back.
  ///
  /// Asked of the host whose view holds [position]; empty when none does.
  /// See [Input3dHost.hitTestAt].
  List<HitTestResult3d> hitTest3d(Offset position) {
    SceneHost3d? found;
    for (final record in sceneSurfaces3d()) {
      final host = record.host;
      if (host != null && host.contains(position)) found = host;
    }
    if (found == null) return <HitTestResult3d>[];
    return found.host.hitTestAt(found.toLocal(position));
  }

  /// Presses the one box [finder] finds, at its centre on the screen.
  ///
  /// **Fails the test when a press there would not reach the box**, and says
  /// what it would reach instead. Flutter's own `tap` only warns; this is
  /// stricter on purpose, because a control a person cannot press is the
  /// defect this stack has actually shipped, and a warning in a green run is
  /// read by nobody. Pass [checkReachable] false to press whatever is there.
  ///
  /// Like `tap`, it does not pump.
  Future<void> tap3d(
    FinderBase<Layout3d> finder, {
    bool checkReachable = true,
    int? pointer,
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final at = _aim(finder, 'tap3d', checkReachable: checkReachable);
    await tapAt(at, pointer: pointer, kind: kind);
  }

  /// Drags the one box [finder] finds by [offset], in logical pixels on the
  /// screen, starting at its centre.
  ///
  /// The same reachability check as [tap3d]. Like `drag`, it does not pump.
  Future<void> drag3d(
    FinderBase<Layout3d> finder,
    Offset offset, {
    bool checkReachable = true,
    int? pointer,
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final at = _aim(finder, 'drag3d', checkReachable: checkReachable);
    await dragFrom(at, offset, pointer: pointer, kind: kind);
  }

  /// Turns a mouse wheel by [delta] over the one box [finder] finds.
  ///
  /// [delta] is the platform's scroll delta: positive `dy` is the wheel
  /// turned towards the viewer, which scrolls a list down. The same
  /// reachability check as [tap3d]; it does not pump.
  Future<void> scroll3d(
    FinderBase<Layout3d> finder,
    Offset delta, {
    bool checkReachable = true,
  }) async {
    final at = _aim(finder, 'scroll3d', checkReachable: checkReachable);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await sendEventToBinding(mouse.hover(at));
    await sendEventToBinding(mouse.scroll(delta));
  }

  Offset _aim(
    FinderBase<Layout3d> finder,
    String callee, {
    required bool checkReachable,
  }) {
    final reach = Reach3d.of(layout3d<Layout3d>(finder), sceneSurfaces3d());
    final global = reach.global;
    if (global == null || (checkReachable && !reach.reaches)) {
      throw TestFailure(
        '$callee() cannot press the ${finder.describeMatch(Plurality.one)}: '
        '${reach.describeMiss()}'
        '${global == null ? '' : '\nPass checkReachable: false to press what '
                  'is there anyway.'}',
      );
    }
    return global;
  }
}
