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
  await probe.preload?.call();

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
        if (probe.minCoverage <= 0.0) {
          // A control scene: the claim is the opposite one, and it is what
          // its partner's coverage is measured against.
          expect(
            frame.coverage,
            lessThan(0.005),
            reason: 'a control scene is supposed to draw nothing',
          );
          return;
        }
        expect(
          frame.coverage,
          greaterThan(probe.minCoverage),
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
      final centreColor = capture.frame.meanColorAt(centre, radius: 5)!;

      // A point inside the big back cube but outside the small front one.
      // Taken as a fraction of the back box's own front face: the front cube
      // is half the back one's extent and centred, so it spans 0.25 to 0.75,
      // and a tenth of the way across is clear of it. screenBounds would be
      // the wrong tool here — it bounds all eight corners including the depth
      // extrusion, so its left edge is outside the face being probed.
      final ring = capture.pointOf('back', const Offset3d(0.1, 0.5, 0));
      final ringColor = capture.frame.colorAt(
        ring.dx.round(),
        ring.dy.round(),
      )!;

      expect(
        capture.frame.coverageAt(ring, radius: 3),
        greaterThan(0.8),
        reason: 'the back cube should be visible around the front one',
      );
      // A mean over a disc, and a margin — not two exact pixel values. The
      // first version compared ARGB words and was flaky for the reason this
      // whole harness is built to avoid.
      expect(
        FrameProbe.colorDistance(centreColor, ringColor),
        greaterThan(0.1),
        reason:
            'the front child should occlude the back one at the centre; '
            'read $centreColor in the middle and $ringColor around it',
      );
    });
    testWidgets('a clip box culls the child outside it', (tester) async {
      final capture = await _draw(tester, kProbeScenes.byId('clipped_row'));

      // Layout still places the overflowing child — the clip is about what is
      // drawn, not about where boxes go — so it still projects to a pixel.
      // That pixel is what must be empty.
      expect(
        capture.frame.coverageAt(capture.centerOf('inside'), radius: 8),
        greaterThan(0.8),
        reason: 'the child inside the clip should be drawn',
      );
      expect(
        capture.frame.coverageAt(capture.centerOf('outside'), radius: 8),
        lessThan(0.05),
        reason: 'the child outside the clip box was drawn anyway',
      );
    });

    testWidgets('scrolling brings later items in and culls earlier ones', (
      tester,
    ) async {
      final capture = await _draw(tester, kProbeScenes.byId('scrolled_list'));

      // Items are 0.7 with 0.25 spacing, so each step is 0.95 and the 1.9
      // jump is exactly two of them: item0 and item1 are above the viewport,
      // item2 onward are in it.
      //
      // An item scrolled out of the list is *not* off the view — the view is
      // larger than the surface — so "is it inside the frame" is the wrong
      // question and the first version of this test asked it. The right one
      // is whether the viewport still draws it.
      for (final gone in ['item0', 'item1']) {
        final box = capture.state.content.probes[gone]!;
        // A released item has no size at all, which is a stronger form of the
        // same claim; a retained one must at least not be drawn.
        final point = box.screenCenter(capture.state.camera, capture.viewSize);
        if (point == null) continue;
        expect(
          capture.frame.coverageAt(point, radius: 5),
          lessThan(0.05),
          reason: '$gone scrolled out of the viewport but was still drawn',
        );
      }

      for (final visible in ['item2', 'item3']) {
        expect(
          capture.frame.coverageAt(capture.centerOf(visible), radius: 5),
          greaterThan(0.7),
          reason: '$visible should be in the viewport after scrolling',
        );
      }

      // And they are in the order the list put them.
      expect(
        capture.centerOf('item2').dy,
        lessThan(capture.centerOf('item3').dy),
      );
    });
  });

  // The other seam a frame is the only witness to. A glyph atlas that never
  // uploaded, a quad wound away from the viewer, a label at exactly the depth
  // of its own panel: each of those measures perfectly and draws nothing, and
  // the package's 770-odd headless tests are blind to every one of them.
  group('text', () {
    testWidgets('the atlas renderer puts glyphs where layout put the label', (
      tester,
    ) async {
      // Paired with its own control, for the reason the decoration test is:
      // "there are pixels where the label is" means nothing on its own, and
      // means everything next to the same label with no renderer installed.
      final drawn = await _draw(tester, kProbeScenes.byId('text_label'));
      final undrawn = await _draw(
        tester,
        kProbeScenes.byId('text_label_undrawn'),
      );

      // A disc over the label. Not the 0.8 a solid cube gets: type is mostly
      // background, and a five-letter word covers something like a fifth of
      // its own box. The claim is that a real, glyph-shaped fraction of it is
      // covered — and that the same box with no renderer covers none of it.
      final drawnLabel = drawn.frame.coverageAt(
        drawn.centerOf('label'),
        radius: 40,
      );
      final undrawnLabel = undrawn.frame.coverageAt(
        undrawn.centerOf('label'),
        radius: 40,
      );
      expect(
        drawnLabel,
        greaterThan(0.1),
        reason:
            'nothing drew where the label is. Either the atlas never '
            'uploaded, or the quads are wound away from the viewer.',
      );
      expect(
        drawnLabel,
        lessThan(0.95),
        reason:
            'the label region is solid; the glyph quads are drawing their '
            'whole cell rather than the ink in it',
      );
      expect(
        undrawnLabel,
        lessThan(0.02),
        reason: 'a Text3d with no renderer drew something anyway',
      );

      // The glyphs are the colour the style asked for, not the white they
      // were rasterized in: the atlas is a mask and the material tints it.
      final ink = drawn.frame.meanColorAt(drawn.centerOf('label'), radius: 40)!;
      expect(
        ink.b,
        lessThan(ink.r),
        reason: 'the label should be amber, not white; read $ink',
      );

      // And well clear of the label there is nothing at all.
      final label = drawn.state.content.probes['label']!;
      final bounds = label.screenBounds(drawn.state.camera, drawn.viewSize)!;
      expect(
        drawn.frame.isClearAt(
          ui.Offset(bounds.center.dx, bounds.top - bounds.height),
          radius: 6,
        ),
        isTrue,
        reason: 'something drew above the label',
      );

      // A wrapped label would move the ink without moving the box, so the
      // oracle is asked what it did before the frame is asked where the ink
      // is. This is the layout tree keeping the assertion honest.
      expect(
        (label as Text3d).textLayout!.lineCount,
        1,
        reason: 'the label wrapped; the centroid below would mean nothing',
      );

      // The ink is where the *box* is, not merely somewhere on the frame: a
      // centred label's glyphs balance around the middle of its own bounds.
      // This is the assertion that would catch a mesh built in the wrong
      // frame, which a coverage disc over the middle would happily pass.
      final centroid = drawn.frame.centroidXIn(bounds);
      expect(centroid, isNotNull, reason: 'nothing covered the label\'s box');
      expect(
        centroid!,
        closeTo(bounds.center.dx, bounds.width * 0.1),
        reason:
            'the glyphs are off-centre in the box layout gave them: '
            'centroid $centroid against a box centred on ${bounds.center.dx}',
      );
    });

    testWidgets('a label on a panel wins the depth test against it', (
      tester,
    ) async {
      final capture = await _draw(tester, kProbeScenes.byId('text_on_panel'));

      // The panel drew.
      expect(
        capture.frame.coverageAt(capture.centerOf('panel'), radius: 20),
        greaterThan(0.95),
        reason: 'the panel behind the label did not draw',
      );

      // And the label is visible *on* it, which is a colour question rather
      // than a coverage one: coplanar text loses the depth test and leaves a
      // panel that is uniformly the panel's colour.
      final panelColor = capture.frame.meanColorAt(
        capture.pointOf('panel', const Offset3d(0.08, 0.5, 0)),
        radius: 6,
      )!;
      final labelColor = capture.frame.meanColorAt(
        capture.centerOf('label'),
        radius: 30,
      )!;
      expect(
        FrameProbe.colorDistance(panelColor, labelColor),
        greaterThan(0.05),
        reason:
            'the label is the same colour as the panel it sits on, so it '
            'either did not draw or sank into it: panel $panelColor, '
            'label $labelColor',
      );
    });

    testWidgets('a RichText3d captures its subtree onto its own box', (
      tester,
    ) async {
      final capture = await _draw(tester, kProbeScenes.byId('rich_text'));

      final paragraph = capture.state.content.probes['paragraph']!;
      final bounds = paragraph.screenBounds(
        capture.state.camera,
        capture.viewSize,
      )!;
      expect(
        capture.frame.coverageAt(capture.centerOf('paragraph'), radius: 40),
        greaterThan(0.1),
        reason:
            'the captured paragraph did not draw. Either no capture reached '
            'the material, or the quad faces away from the viewer.',
      );

      // Two styles in one span, which is the whole reason this box exists:
      // the halves are drawn in different colours, so the ink on the left is
      // not the ink on the right.
      final left = capture.frame.meanColorAt(
        ui.Offset(bounds.left + bounds.width * 0.25, bounds.center.dy),
        radius: 12,
      );
      final right = capture.frame.meanColorAt(
        ui.Offset(bounds.left + bounds.width * 0.75, bounds.center.dy),
        radius: 12,
      );
      expect(left, isNotNull, reason: 'the first run did not draw');
      expect(right, isNotNull, reason: 'the second run did not draw');
      expect(
        FrameProbe.colorDistance(left!, right!),
        greaterThan(0.05),
        reason:
            'both halves of the span came out the same colour, so the '
            'capture is not the paragraph Flutter laid out: $left, $right',
      );
    });
  });

  // The seam nothing could reach until now. `box_decoration3d.fmat` ships with
  // the package and, until this app's build hook compiled it, no lane in
  // either this repository or the engine's had ever run impellerc over it: a
  // unit test parses the file and checks that every parameter the Dart side
  // writes is declared, which catches a silent mismatch but not invalid GLSL.
  // These two tests are the first thing to ask the compiler, and then the
  // rasterizer, whether the shader is real.
  group('the decoration shader', () {
    testWidgets('the panel shader compiles, runs, and rounds its corners', (
      tester,
    ) async {
      // One test rather than two, because the square panel is the *control*.
      // "The rounded panel's corner is empty" on its own could equally mean
      // the panel never drew; the claim only means something next to a panel
      // that is identical but for the radius.
      //
      // Absolute coverage thresholds at a corner are a trap here: the probe
      // disc straddles the panel edge and reads somewhere in the middle
      // whatever the shader does. Comparing the two at the same relative spot
      // asks the real question and does not depend on where exactly the edge
      // lands.
      // A point on the panel's own front face, near the top-left corner.
      //
      // Taken as a fraction of the panel rather than off screenBounds, which
      // bounds all eight corners including the depth extrusion and so sits
      // outside the face. The panel is 3.6 x 1.8 with a 0.6 radius, so this
      // lands 0.108 units in on both axes: a diagonal of 0.153, comfortably
      // inside the 0.248 the arc carves away, and comfortably inside the body
      // of a panel that has no radius.
      double cornerCoverage(_Capture capture) => capture.frame.coverageAt(
        capture.pointOf('panel', const Offset3d(0.03, 0.06, 0)),
        radius: 4,
      );

      final square = await _draw(tester, kProbeScenes.byId('square_panel'));
      expect(
        square.frame.coverageAt(square.centerOf('panel'), radius: 20),
        greaterThan(0.95),
        reason:
            'the panel did not draw at all. Either the shader failed to '
            'compile, or the painter is not installed.',
      );
      final squareCorner = cornerCoverage(square);

      final rounded = await _draw(tester, kProbeScenes.byId('rounded_panel'));
      expect(
        rounded.frame.coverageAt(rounded.centerOf('panel'), radius: 20),
        greaterThan(0.95),
        reason: 'the rounded panel did not draw in the middle either',
      );
      final roundedCorner = cornerCoverage(rounded);

      // The control really is square there.
      expect(
        squareCorner,
        greaterThan(0.9),
        reason: 'a panel with no radius should be solid near its corner',
      );
      // And the radius really took the corner away.
      expect(
        roundedCorner,
        lessThan(squareCorner - 0.5),
        reason:
            'the corner radius did not carve the corner away: square read '
            '$squareCorner, rounded read $roundedCorner',
      );
    });
  });
}

extension on List<ProbeScene> {
  ProbeScene byId(String id) => firstWhere((scene) => scene.id == id);
}
