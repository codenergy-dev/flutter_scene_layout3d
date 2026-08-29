// Render tests for flutter_scene_layout3d.
//
// The package's own suite is 700-odd tests and all of it is arithmetic: it
// proves the protocol arranges correctly and proves nothing about whether a
// frame comes out. This is the other half. It draws real geometry through the
// layout boxes and then asks the frame whether the geometry is where layout
// said it would be — which needs a GPU, and so lives here rather than in
// `flutter test`.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/render_test.dart \
//     -d macos --enable-flutter-gpu
//
// Nothing here is a golden image. The question is "is the geometry where
// layout put it", not "is this pixel that colour"; goldens across backends and
// driver versions fail for reasons that have nothing to do with the package.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' show Scene;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:render_probe/frame_probe.dart';
import 'package:render_probe/probe_scene.dart';
import 'package:render_probe/probe_scenes.dart';

/// Draws [probe] and captures the frame.
///
/// The order matters and is not obvious. One ordinary Flutter frame goes up
/// first, because some backends race GPU context setup if the engine uploads
/// textures before the first frame has established a context. Then the engine
/// is awaited — geometry and material constructors touch the shader bundle,
/// so nothing may be built before it resolves. Only then is the scene pumped,
/// and it is given real settling time rather than a single pump.
Future<_Capture> _draw(WidgetTester tester, ProbeScene probe) async {
  await tester.pumpWidget(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(backgroundColor: kProbeClear, body: SizedBox.expand()),
    ),
  );
  await tester.pump();

  await Scene.initializeStaticResources();

  final key = GlobalKey<ProbeSceneViewState>();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: kProbeClear,
        body: ProbeSceneView(probe, key: key),
      ),
    ),
  );

  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  final boundary =
      probeBoundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final state = key.currentState!;
  return _Capture(
    await FrameProbe.fromImage(image),
    state,
    probe.viewSize ?? ProbeScene.defaultViewSize,
  );
}

class _Capture {
  _Capture(this.frame, this.state, this.viewSize);

  final FrameProbe frame;
  final ProbeSceneViewState state;
  final ui.Size viewSize;

  /// Where layout says the named box is, in pixels.
  ///
  /// This is the whole idea: the assertion below does not know a coordinate,
  /// it asks the layout tree. Null is a failure of the projection rather than
  /// of the render, and is reported as such.
  ui.Offset centerOf(String probe) {
    final box = state.content.probes[probe];
    if (box == null) {
      fail('scene has no probe named "$probe"');
    }
    final point = box.screenCenter(state.camera, viewSize);
    if (point == null) {
      fail('"$probe" does not project onto the view; is it behind the camera?');
    }
    return point;
  }

  /// A point offset from the named box, as a fraction of its own extent.
  ui.Offset pointOf(String probe, Offset3d fraction) {
    final box = state.content.probes[probe]!;
    final point = box.screenPointOf(fraction, state.camera, viewSize);
    if (point == null) fail('"$probe" $fraction does not project');
    return point;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('the floor: did a frame come out at all', () {
    for (final probe in kProbeScenes) {
      testWidgets('${probe.id} draws a sane frame', (tester) async {
        final capture = await _draw(tester, probe);
        final frame = capture.frame;

        // Reference-free sanity. These four catch "nothing drew", "the surface
        // never cleared" and "it drew but no light reached it" — the failures
        // that would otherwise make every layout assertion below fail for a
        // reason that has nothing to do with layout.
        expect(
          frame.cornersClear,
          isTrue,
          reason: 'the corners are not the clear colour; nothing cleared',
        );
        expect(
          frame.coverage,
          greaterThan(0.02),
          reason: 'almost nothing drew',
        );
        expect(
          frame.coverage,
          lessThan(0.9),
          reason: 'the frame is nearly full; the surface likely did not clear',
        );
        expect(
          frame.foregroundMeanLuma,
          greaterThan(20),
          reason: 'the geometry is ~black; lighting may have broken',
        );
        // Deliberately a very low bar. These scenes are flat-shaded
        // primitives on a flat clear, so a legitimate frame holds only a
        // handful of quantized colours — a single lit cube measured 5. This
        // is a backstop against a uniform fill, nothing more; coverage and
        // luma above are the real blank detectors.
        expect(
          frame.distinctColors(),
          greaterThan(3),
          reason: 'the frame looks uniform; possible blank render',
        );
      });
    }
  });

  group('the point: is the geometry where layout put it', () {
    testWidgets('a row puts its children side by side, in order', (
      tester,
    ) async {
      final capture = await _draw(tester, kProbeScenes.byId('row_of_cubes'));

      for (final name in ['left', 'middle', 'right']) {
        expect(
          capture.frame.coverageAt(capture.centerOf(name), radius: 10),
          greaterThan(0.8),
          reason: 'no geometry where layout put "$name"',
        );
      }

      final left = capture.centerOf('left');
      final middle = capture.centerOf('middle');
      final right = capture.centerOf('right');
      expect(left.dx, lessThan(middle.dx));
      expect(middle.dx, lessThan(right.dx));
      // Same row: they share a baseline on screen.
      expect(middle.dy, closeTo(left.dy, 2));

      // And the gaps a spaceBetween row leaves really are empty.
      final gap = ui.Offset((left.dx + middle.dx) / 2, left.dy);
      expect(
        capture.frame.isClearAt(gap, radius: 4),
        isTrue,
        reason: 'the gap between two cubes is not empty',
      );
    });

    testWidgets('a column stacks downward, and the spacing is really empty', (
      tester,
    ) async {
      final capture = await _draw(tester, kProbeScenes.byId('column_spacing'));

      final top = capture.centerOf('top');
      final bottom = capture.centerOf('bottom');
      expect(top.dy, lessThan(bottom.dy));
      expect(bottom.dx, closeTo(top.dx, 2));

      for (final point in [top, bottom]) {
        expect(capture.frame.coverageAt(point, radius: 10), greaterThan(0.8));
      }
      expect(
        capture.frame.isClearAt(
          ui.Offset(top.dx, (top.dy + bottom.dy) / 2),
          radius: 4,
        ),
        isTrue,
        reason: 'the space between the two cubes is not empty',
      );
    });

    testWidgets('on the ground plane, down the column comes toward the '
        'viewer', (tester) async {
      final capture = await _draw(tester, kProbeScenes.byId('ground_plane'));

      final near = capture.centerOf('near');
      final far = capture.centerOf('far');

      // Both drew.
      expect(capture.frame.coverageAt(near, radius: 8), greaterThan(0.7));
      expect(capture.frame.coverageAt(far, radius: 8), greaterThan(0.7));

      // The basis is real, not a relabelling of axes: `xz` maps layout y to
      // scene +z and the camera sits at +z, so the second child of the column
      // is *nearer*, which on a ground plane seen from above means lower on
      // screen. A nearer thing of the same size also projects larger.
      expect(
        near.dy,
        greaterThan(far.dy),
        reason: 'the far row should sit higher on screen',
      );

      final nearBox = capture.state.content.probes['near']!;
      final farBox = capture.state.content.probes['far']!;
      final nearBounds = nearBox.screenBounds(
        capture.state.camera,
        capture.viewSize,
      )!;
      final farBounds = farBox.screenBounds(
        capture.state.camera,
        capture.viewSize,
      )!;
      expect(
        nearBounds.width,
        greaterThan(farBounds.width),
        reason: 'perspective should make the nearer row larger',
      );
    });

    testWidgets('padding and alignment land the child where they claim', (
      tester,
    ) async {
      final capture = await _draw(
        tester,
        kProbeScenes.byId('padding_and_alignment'),
      );

      final child = capture.centerOf('child');
      expect(capture.frame.coverageAt(child, radius: 8), greaterThan(0.8));

      // The child is pushed right and down out of the surface's top-left
      // corner, so the corner it vacated is empty.
      expect(
        capture.frame.isClearAt(
          ui.Offset(child.dx - 60, child.dy - 50),
          radius: 5,
        ),
        isTrue,
        reason: 'the padded-away corner should be empty',
      );
    });

    testWidgets('a NodeBox3d measures the geometry it holds', (tester) async {
      final capture = await _draw(
        tester,
        kProbeScenes.byId('intrinsic_sizing'),
      );

      // A sphere of diameter 1 and a cube of side 1 both fit a 1-unit box, so
      // the two boxes project to the same size. What differs is coverage: a
      // circle fills less of its bounding square than a square does. That the
      // sphere covers *less* is the check that the box really measured the
      // sphere rather than assuming its slot.
      final ball = capture.centerOf('ball');
      final box = capture.centerOf('box');
      expect(capture.frame.coverageAt(ball, radius: 6), greaterThan(0.8));
      expect(capture.frame.coverageAt(box, radius: 6), greaterThan(0.8));

      final ballBounds = capture.state.content.probes['ball']!.screenBounds(
        capture.state.camera,
        capture.viewSize,
      )!;
      final boxBounds = capture.state.content.probes['box']!.screenBounds(
        capture.state.camera,
        capture.viewSize,
      )!;
      expect(ballBounds.width, closeTo(boxBounds.width, 2));

      // The sphere's corners are empty; the cube's are not.
      expect(
        capture.frame.coverageAt(ballBounds.topLeft, radius: 3),
        lessThan(capture.frame.coverageAt(boxBounds.topLeft, radius: 3)),
        reason: 'a sphere should not fill the corners of its bounding box',
      );
    });

    testWidgets('a stack puts its last child in front', (tester) async {
      final capture = await _draw(tester, kProbeScenes.byId('stack_depth'));

      // Both boxes are centred on the same spot; only depth separates them.
      // Sampling the centre reads the front child's colour, and the back
      // child is only visible around it.
      final centre = capture.centerOf('front');
      final centreColor = capture.frame.colorAt(
        centre.dx.round(),
        centre.dy.round(),
      )!;

      final back = capture.state.content.probes['back']!;
      final backBounds = back.screenBounds(
        capture.state.camera,
        capture.viewSize,
      )!;
      // A point inside the big back cube but outside the small front one.
      final ring = ui.Offset(backBounds.left + 8, centre.dy);
      final ringColor = capture.frame.colorAt(
        ring.dx.round(),
        ring.dy.round(),
      )!;

      expect(
        capture.frame.coverageAt(ring, radius: 3),
        greaterThan(0.8),
        reason: 'the back cube should be visible around the front one',
      );
      expect(
        centreColor.toARGB32(),
        isNot(ringColor.toARGB32()),
        reason: 'the front child should occlude the back one at the centre',
      );
    });
  });
}

extension on List<ProbeScene> {
  ProbeScene byId(String id) => firstWhere((scene) => scene.id == id);
}
