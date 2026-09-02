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

import 'dart:math' as math;
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
    testWidgets('a relayout that changes nothing rebuilds no geometry', (
      tester,
    ) async {
      // The constraint the whole text plan is arranged around: measurement and
      // geometry must not sit on the per-frame path, because animation dirties
      // layout every frame. `debugTextParagraphCount` guards the measurement
      // half headlessly. This is the geometry half, and it has to live here —
      // AtlasText3dRenderer.render builds a real Mesh, so a headless test
      // cannot reach it at all.
      final capture = await _draw(tester, kProbeScenes.byId('text_label'));
      final label = capture.state.content.probes['label']! as Text3d;
      final renderer = label.renderer! as AtlasText3dRenderer;

      final mesh = renderer.meshNode;
      final quads = renderer.quadCount;
      expect(mesh, isNotNull, reason: 'the label drew no glyphs at all');
      expect(quads, greaterThan(0));

      // Lay out again with everything unchanged. Text3d hands back the same
      // cached TextLayout3d, so the renderer's guard should recognise it and
      // keep the mesh it already built.
      label.markNeedsLayout();
      capture.state.content.surfaces.single.flush();

      expect(
        identical(renderer.meshNode, mesh),
        isTrue,
        reason:
            'a no-op relayout rebuilt the glyph mesh; geometry is back on '
            'the per-frame path',
      );
      // Same glyphs, not an empty mesh kept by accident.
      expect(
        renderer.quadCount,
        quads,
        reason: 'the guard held the mesh but the quad count moved',
      );

      // Deliberately no pixel check here. That the label draws where layout
      // put it is the next test's whole job, and repeating it against a frame
      // captured before this relayout would only add a second threshold to
      // keep calibrated.
    });

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

  // The seam nothing could reach until this lane existed.
  // `box_decoration3d.fmat` ships with the package and is compiled by the
  // package's own build hook, so invalid GLSL now fails any build; what still
  // fails nowhere else is a shader that compiles and draws the wrong thing.
  // A unit test parses the file and checks that every parameter the Dart side
  // writes is declared, which catches a silent mismatch and nothing about the
  // picture. These tests are the only thing that asks the rasterizer whether
  // the shader is real.
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

    testWidgets('elevation lifts the panel toward the viewer', (tester) async {
      // Material's elevation is a painted shadow standing in for a height.
      // Here the height is real, and "real" has a consequence a frame can
      // check: a panel six tenths of a unit nearer a camera six units back
      // projects about eleven per cent larger. So the claim is not "the panel
      // drew" but "the panel drew *outside where the unlifted one ends*".
      final flat = await _draw(tester, kProbeScenes.byId('plain_panel'));
      final raised = await _draw(tester, kProbeScenes.byId('elevated_panel'));

      for (final capture in [flat, raised]) {
        expect(
          capture.frame.coverageAt(capture.centerOf('panel'), radius: 20),
          greaterThan(0.95),
          reason: 'the panel did not draw at all',
        );
      }

      // The oracle. `DecoratedBox3d` puts the lift in `localTransform` and
      // returns null from `hitTestTransform`, so `worldTransform` does *not*
      // undo it: the projection of an elevated panel follows the geometry,
      // while a ray still reaches the box where layout put it. That asymmetry
      // is the whole design of elevation, and it is what makes these two
      // numbers different.
      final flatEdge = flat.pointOf('panel', const Offset3d(1, 0.5, 0));
      final raisedEdge = raised.pointOf('panel', const Offset3d(1, 0.5, 0));
      expect(
        raisedEdge.dx - flatEdge.dx,
        greaterThan(8),
        reason:
            'the lifted panel should project wider than the flat one; the '
            'projection says its right edge moved only '
            '${raisedEdge.dx - flatEdge.dx} px, so nothing was lifted',
      );

      // And the frame agrees. Halfway between the two projected edges is
      // inside the lifted panel and outside the flat one, and neither number
      // is written down here: both come from layout.
      final between = ui.Offset((flatEdge.dx + raisedEdge.dx) / 2, flatEdge.dy);
      expect(
        raised.frame.coverageAt(between, radius: 3),
        greaterThan(0.9),
        reason:
            'the lifted panel does not cover $between, which is inside its '
            'own projected outline: the geometry did not move',
      );
      expect(
        flat.frame.coverageAt(between, radius: 3),
        lessThan(0.05),
        reason:
            'the *unlifted* panel covers $between too, so the two captures '
            'are not actually different and the comparison means nothing',
      );
    });

    testWidgets(
      'a border draws its own colour, at the edge and not in the middle',
      (tester) async {
        // The assertion that matters is a *direction*, not a distance. A
        // colour distance between the rim and the middle is just as large
        // when the two are the wrong way round, and the wrong way round is
        // exactly what the shader did: a stray `1.0 -` painted the border
        // colour over the whole interior and left the fill as a thin rim. So
        // each point is asked which colour it holds, by the one channel
        // comparison that survives lighting and tone mapping: the fill is
        // blue-dominant, the border is red-dominant.
        const band = Offset3d(0.5, 0.06, 0);
        const middle = Offset3d(0.5, 0.5, 0);

        final bordered = await _draw(
          tester,
          kProbeScenes.byId('bordered_panel'),
        );
        // 0.06 of a 1.8-unit height is 0.108 units in from the top edge:
        // inside the 0.4-unit band with room either side, and clear of the
        // outline's anti-aliasing.
        final borderInk = bordered.frame.meanColorAt(
          bordered.pointOf('panel', band),
          radius: 4,
        );
        final fillInk = bordered.frame.meanColorAt(
          bordered.pointOf('panel', middle),
          radius: 8,
        );
        expect(borderInk, isNotNull, reason: "nothing drew at the panel's rim");
        expect(
          fillInk,
          isNotNull,
          reason: "nothing drew in the panel's middle",
        );
        expect(
          borderInk!.r,
          greaterThan(borderInk.b),
          reason:
              'the rim of a bordered panel is not the border colour: read '
              '$borderInk where the amber border should be',
        );
        expect(
          fillInk!.b,
          greaterThan(fillInk.r),
          reason:
              'the middle of a bordered panel is not the fill colour: read '
              '$fillInk, so the border is inside out',
        );

        // The control. Without a border those two points are the same colour,
        // which is what says the difference above is the border and not a
        // lighting gradient across the slab.
        final plain = await _draw(tester, kProbeScenes.byId('plain_panel'));
        final plainBand = plain.frame.meanColorAt(
          plain.pointOf('panel', band),
          radius: 4,
        )!;
        final plainMiddle = plain.frame.meanColorAt(
          plain.pointOf('panel', middle),
          radius: 8,
        )!;
        expect(
          plainBand.b,
          greaterThan(plainBand.r),
          reason: 'a panel given no border drew one anyway: $plainBand',
        );
        expect(
          FrameProbe.colorDistance(plainBand, plainMiddle),
          lessThan(0.06),
          reason:
              'an undecorated panel is not one flat colour across its face, '
              'so the bordered comparison above could be a gradient: rim '
              '$plainBand, middle $plainMiddle',
        );
      },
    );

    testWidgets('a state layer lightens the panel it is on', (tester) async {
      // Hover, focus, press and drag are all this: one colour blended over
      // the same decoration, one uniform, no second mesh and no relayout. The
      // frame's job is to say the uniform reaches the picture, and the honest
      // way to ask is a pair — the same panel with the layer on and off.
      final plain = await _draw(tester, kProbeScenes.byId('plain_panel'));
      final washed = await _draw(
        tester,
        kProbeScenes.byId('state_layer_panel'),
      );

      final plainInk = plain.frame.meanColorAt(
        plain.centerOf('panel'),
        radius: 20,
      )!;
      final washedInk = washed.frame.meanColorAt(
        washed.centerOf('panel'),
        radius: 20,
      )!;

      // A state layer is a colour, not a shape: the panel is still the same
      // panel underneath it.
      expect(
        washed.frame.coverageAt(washed.centerOf('panel'), radius: 20),
        greaterThan(0.95),
        reason: 'the panel with a state layer on it did not draw',
      );
      expect(
        washedInk.computeLuminance(),
        greaterThan(plainInk.computeLuminance() + 0.03),
        reason:
            'a 32% white state layer left the panel no lighter, so the '
            'uniform is not reaching the shader: plain $plainInk, '
            'with the layer $washedInk',
      );
    });

    // What a panel casts onto the ground under it, which is nothing at all.
    //
    // This test asserts a **defect**, deliberately, because the alternative
    // is a plan that says "not done" forever. `box_decoration3d.fmat`
    // declares `blending: alpha`, and `ShadowEncoder._submit` drops any item
    // whose `material.isOpaque()` is false before it reaches the shadow map,
    // so a decorated panel is not a shadow caster in this engine at all. The
    // silhouette question the plan wanted answered — does the SDF's discard
    // reach the shadow? — cannot even be posed here: there is no shadow to
    // look at. The second half of the answer is in the plan's *What the plan
    // got wrong*: a shadow pass runs `DepthOnlyFragment` and never the
    // material's own `Surface()`, so an opaque panel would cast the shadow of
    // its whole rectangular slab.
    //
    // If the last expectation below ever fails, that is good news and the
    // engine has grown something: go and read the plan.
    testWidgets('a decorated panel casts no shadow, and an opaque cube does', (
      tester,
    ) async {
      final capture = await _draw(tester, kProbeScenes.byId('panel_shadow'));

      double groundLuma(String patch) {
        final point = capture.centerOf(patch);
        expect(
          capture.frame.coverageAt(point, radius: 6),
          greaterThan(0.9),
          reason: 'the ground patch "$patch" is not drawn where layout put it',
        );
        return capture.frame.meanColorAt(point, radius: 6)!.computeLuminance();
      }

      final lit = groundLuma('underNothing');
      final underCube = groundLuma('underCube');
      final underPanel = groundLuma('underPanel');

      // The control, and it has to pass first: without it, "the ground under
      // the panel is not darkened" would be satisfied by a scene with no
      // shadows in it at all.
      expect(
        underCube,
        lessThan(lit * 0.85),
        reason:
            'the opaque cube cast no shadow either, so this scene says '
            'nothing about the panel. Lit ground $lit, under the cube '
            '$underCube — check that the light still has castsShadow set.',
      );
      expect(
        underPanel,
        closeTo(lit, lit * 0.08),
        reason:
            'the decorated panel cast a shadow, which flutter_scene 0.23.0 '
            'cannot do for a material declaring `blending: alpha`. Lit '
            'ground $lit, under the panel $underPanel. If the engine has '
            'changed, the size-driven-geometry plan needs rereading: the '
            'silhouette-versus-shadow question is live again.',
      );
    });
  });

  group('a drag in flight', () {
    // Two claims the package's own suite cannot make. Everything about a drag
    // is arithmetic except what it looks like, and what it looks like is
    // exactly what these two ask.

    testWidgets('the lifted feedback wins the depth test', (tester) async {
      final capture = await _draw(
        tester,
        kProbeScenes.byId('drag_feedback_depth'),
      );

      // Three identical teal rows; a card picked up from the first and
      // carried over the third. Row 2 is under the feedback, row 0 is not.
      final covered = capture.frame.meanColorAt(
        capture.centerOf('row2'),
        radius: 6,
      )!;
      final bare = capture.frame.meanColorAt(
        capture.centerOf('row0'),
        radius: 6,
      )!;

      expect(
        capture.frame.coverageAt(capture.centerOf('row2'), radius: 6),
        greaterThan(0.8),
        reason: 'nothing drew where the feedback should be',
      );
      // A mean over a disc and a margin, never two exact words: the rest of
      // this file learned that the hard way.
      expect(
        FrameProbe.colorDistance(covered, bare),
        greaterThan(0.1),
        reason:
            'the feedback did not occlude the row it was carried over; read '
            '$covered over row 2 and $bare over row 0, which are the same '
            'colour underneath',
      );
    });

    testWidgets('detached feedback draws outside the panel it came from', (
      tester,
    ) async {
      final capture = await _draw(
        tester,
        kProbeScenes.byId('drag_feedback_detached'),
      );

      // `screenCenter` already follows the drag. The box that carries the
      // node offset is the `IgnorePointer3d` `Draggable3d` wraps the feedback
      // in — an *ancestor* of anything a caller can name — and
      // `worldTransform` undoes only a box's own nudges, so an ancestor's
      // stays in the projection. Reconstructing the offset by hand would read
      // this box's own, which is zero.
      final drawn = capture.centerOf('feedback');
      final card = capture.centerOf('card');
      expect(
        (drawn - card).distance,
        greaterThan(20.0),
        reason:
            'the feedback was never carried anywhere: it is still on the '
            'card at $card',
      );

      // Carried clean off the panel, which is the one thing an in-plane entry
      // could not do. Compared against both edges rather than the right one:
      // the basis mirrors x on its way to the screen, so which edge a drag
      // toward larger layout x ends up beyond is not something to assume.
      final left = capture.pointOf('panel', const Offset3d(0, 0.5, 0)).dx;
      final right = capture.pointOf('panel', const Offset3d(1, 0.5, 0)).dx;
      expect(
        drawn.dx < math.min(left, right) || drawn.dx > math.max(left, right),
        isTrue,
        reason:
            'the feedback did not overhang the panel: it drew at ${drawn.dx} '
            'and the panel spans $left to $right',
      );
      expect(
        capture.frame.coverageAt(drawn, radius: 6),
        greaterThan(0.8),
        reason:
            'no geometry drew where the detached feedback was carried to; a '
            'detached entry that is not in the scene graph draws nothing',
      );

      // And it really is the feedback out there rather than the card, which
      // stayed on the panel.
      final outside = capture.frame.meanColorAt(drawn, radius: 5)!;
      final onPanel = capture.frame.meanColorAt(card, radius: 5)!;
      expect(
        FrameProbe.colorDistance(outside, onPanel),
        greaterThan(0.1),
        reason: 'read $outside off the panel and $onPanel on it',
      );
    });
  });

  // ── The catalogue ────────────────────────────────────────────────────
  //
  // Three claims that only a frame can settle, and the first two are the
  // whole of Material's elevation model once the shadow is gone.
  group('the Material catalogue', () {
    testWidgets('three elevation levels are three distinguishable colours', (
      tester,
    ) async {
      // Material 3's elevation is a height and a tint. The height is real
      // here and buys nothing head-on; the tint is what is left, and it is
      // the reason `Elevation3d` carries the published table at all.
      //
      // The scene is the light theme — see its comment for why a dark one is
      // invisible to this harness — so its near-white surface is tinted with
      // the theme's purple primary and the order is *higher is darker*. An
      // order rather than a distance, because a distance is satisfied just as
      // well by the three coming out in the wrong sequence, which is exactly
      // how the panel shader once shipped with its border inside out.
      final capture = await _draw(
        tester,
        kProbeScenes.byId('material_elevation'),
      );

      double lumaOf(String name) {
        final color = capture.frame.meanColorAt(
          capture.centerOf(name),
          radius: 12,
        );
        expect(color, isNotNull, reason: 'the $name panel did not draw');
        return 0.2126 * color!.r + 0.7152 * color.g + 0.0722 * color.b;
      }

      final flat = lumaOf('flat');
      final raised = lumaOf('raised');
      final high = lumaOf('high');

      expect(
        raised,
        lessThan(flat),
        reason:
            'a level-2 surface is not more tinted than a level-0 one: read '
            '$flat flat, $raised raised. Either the surface tint is not '
            'reaching the shader, or every panel is sharing one material '
            'and the last one painted won the parameter block.',
      );
      expect(
        high,
        lessThan(raised),
        reason:
            'a level-5 surface is not more tinted than a level-2 one: read '
            '$raised raised, $high high',
      );
    });

    testWidgets('a hover washes a panel toward its content colour', (
      tester,
    ) async {
      // The state layer as a component actually resolves it: the opacity out
      // of `StateLayerOpacity3d`, the colour out of the surface's own content
      // role. The idle panel beside it is the control, and the two are the
      // same decoration in the same scene, so the only difference between
      // them is the wash.
      //
      // "A hover lightens a panel" is the dark-theme phrasing. The scene is
      // the light theme, whose content colour is near black, so the direction
      // asserted is darker — which is the same claim about the same wash.
      final capture = await _draw(tester, kProbeScenes.byId('material_hover'));

      final idle = capture.frame.meanColorAt(
        capture.centerOf('idle'),
        radius: 12,
      );
      final hovered = capture.frame.meanColorAt(
        capture.centerOf('hovered'),
        radius: 12,
      );
      expect(idle, isNotNull, reason: 'the idle panel did not draw');
      expect(hovered, isNotNull, reason: 'the hovered panel did not draw');

      double luma(ui.Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
      expect(
        luma(hovered!),
        lessThan(luma(idle!)),
        reason:
            'the hovered panel is no darker than the idle one, so the state '
            'layer never reached the shader: read $idle idle, $hovered '
            'hovered',
      );
    });

    testWidgets('an icon-font glyph rasterizes through the label atlas', (
      tester,
    ) async {
      // The question the whole `Icon3d` design hangs on, and it cannot be
      // reasoned out: `Text3d` measures an unknown glyph happily and draws a
      // blank, and Flutter's text engine either resolves `MaterialIcons` or
      // silently falls back to something that has no such code point. Paired
      // with its own control, like every other text scene here, so that "ink
      // where the icon is" is evidence rather than a coincidence.
      final drawn = await _draw(tester, kProbeScenes.byId('icon_glyph'));
      final undrawn = await _draw(
        tester,
        kProbeScenes.byId('icon_glyph_undrawn'),
      );

      final drawnIcon = drawn.frame.coverageAt(
        drawn.centerOf('icon'),
        radius: 30,
      );
      final undrawnIcon = undrawn.frame.coverageAt(
        undrawn.centerOf('icon'),
        radius: 30,
      );
      expect(
        drawnIcon,
        greaterThan(0.25),
        reason:
            'nothing drew where the icon is. Either MaterialIcons did not '
            'resolve, or the atlas cannot rasterize an icon-font glyph — '
            'and Icon3d is a phase of its own rather than thirty lines.',
      );
      expect(
        undrawnIcon,
        lessThan(0.02),
        reason: 'a Text3d with no renderer drew an icon anyway',
      );

      // And it is bounded by the box layout gave it: an atlas that uploaded
      // an empty mask, or a quad drawing its whole cell, would spill past it.
      // A solidity check at the centre does not say this — a 220-pixel heart
      // is solid for thirty pixels around its middle and should be.
      final bounds = drawn.state.content.probes['icon']!.screenBounds(
        drawn.state.camera,
        drawn.viewSize,
      )!;
      expect(
        drawn.frame.isClearAt(
          ui.Offset(bounds.center.dx, bounds.top - bounds.height),
          radius: 6,
        ),
        isTrue,
        reason: 'something drew a whole box above the icon',
      );

      // The tint reaches it, exactly as it reaches a label: the atlas is a
      // mask and the material colours it.
      final ink = drawn.frame.meanColorAt(drawn.centerOf('icon'), radius: 30)!;
      expect(
        ink.b,
        lessThan(ink.r),
        reason: 'the icon should be amber, not white; read $ink',
      );
    });
  });
}

extension on List<ProbeScene> {
  ProbeScene byId(String id) => firstWhere((scene) => scene.id == id);
}
