// The opacity experiment: three ways of fading a subtree, photographed.
//
//   flutter drive --driver=test_driver/photograph.dart \
//     --target=integration_test/opacity_poc_test.dart \
//     -d macos --enable-flutter-gpu
//
// The PNGs land in `build/photographs/`, one per approach per opacity, and
// **they are the output**. The readings printed at the end are there to say
// which pictures to look at first and to make the failures nameable; they are
// not assertions, because this target exists to choose an approach rather than
// to defend one. See `lib/opacity_poc.dart` for what the three approaches are
// and why depth rather than alpha is the thing being compared.
//
// It is deliberately **not** in `render_test.dart`: that suite is a contract
// and every scene in it asserts something true. Nothing here asserts anything
// beyond "a frame came out", and two of the three approaches are expected to
// draw something wrong.

import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' show Camera, Scene;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:render_probe/frame_probe.dart';
import 'package:render_probe/opacity_poc.dart';
import 'package:render_probe/probe_scene.dart';

/// The opacities each approach is drawn at.
///
/// One at each end and two in between, because the interesting arithmetic is
/// not linear: a fade's error against true group opacity is zero at both ends
/// and largest in the middle, and `text_glyph3d.fmat`'s `alpha_cutoff` of 0.35
/// puts a cliff somewhere around the third of these.
const List<double> kFades = <double>[1.0, 0.6, 0.3, 0.12];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final rows = <_Reading>[];

  /// Draws one scene and captures it, exactly as `render_test.dart` does.
  ///
  /// The boundary captured is `ProbeSceneView`'s own, which wraps the sized
  /// box the scene is drawn into — so the image is exactly `viewSize` and a
  /// point from `screenCenter` indexes it directly. A boundary further out
  /// would capture the window, and every projected coordinate would be off by
  /// wherever the view had been centred.
  Future<_Shot> shoot(WidgetTester tester, ProbeScene probe) async {
    // One ordinary frame first: some backends race GPU context setup when the
    // engine uploads textures before a first frame has established a context.
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

    // Real delays, not just pumps: the engine's resources and the glyph
    // atlas's rasterization finish on the platform's clock.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    final boundary =
        probeBoundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final frame = await FrameProbe.fromImage(image);
    image.dispose();

    final state = key.currentState!;
    final size = probe.viewSize ?? ProbeScene.defaultViewSize;
    return _Shot(
      probe.id,
      frame,
      png!.buffer.asUint8List(),
      state.content,
      state.camera,
      size,
    );
  }

  /// The same capture, for the approach whose widget is not a `ProbeSceneView`.
  ///
  /// [FadeApproach.layer] needs a second `RenderView`, a `RenderTexture` and an
  /// `Opacity` around it, which is a different widget rather than a different
  /// scene — so it gets its own host and the same boundary key, and everything
  /// downstream of the capture is identical.
  Future<_Shot> shootLayer(
    WidgetTester tester,
    double fade, {
    required bool turned,
  }) async {
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: kProbeClear, body: SizedBox.expand()),
      ),
    );
    await tester.pump();

    await Scene.initializeStaticResources();
    await installApproach(FadeApproach.layer, fade);

    const size = Size(720, 420);
    final key = GlobalKey<LayerFadeViewState>();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: kProbeClear,
          body: LayerFadeView(
            key: key,
            fade: fade,
            turned: turned,
            viewSize: size,
          ),
        ),
      ),
    );

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    final boundary =
        probeBoundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final frame = await FrameProbe.fromImage(image);
    image.dispose();

    final state = key.currentState!;
    final name = 'fade_layer_${(fade * 100).round()}${turned ? '_turned' : ''}';
    return _Shot(
      name,
      frame,
      png!.buffer.asUint8List(),
      state.content,
      state.camera,
      size,
    );
  }

  void keep(_Shot shot) {
    final report = binding.reportData ??= <String, dynamic>{};
    ((report['screenshots'] ??= <dynamic>[]) as List<dynamic>).add(
      <String, Object>{'screenshotName': shot.name, 'bytes': shot.png.toList()},
    );
  }

  /// Everything one capture has to say, in numbers.
  void read(_Shot shot, FadeApproach approach, double fade, bool turned) {
    final frame = shot.frame;

    // The faded panel on the benign side, read **low on the card** where the
    // label cannot reach. The first version of this read the card's centre,
    // the label crossed it, and every "panel" number in the table was really
    // a number about the label.
    final lowOnCard = shot.pointOf('fadeLeft', const Offset3d(0.5, 0.85, 0.0));
    final left = frame.meanColorAt(lowOnCard, radius: 12);

    // The faded panel on the side whose ordering erases.
    final right = frame.meanColorAt(shot.centerOf('fadeRight'), radius: 12);

    // The backdrop where nothing covers it: the control. It is never faded,
    // so any capture in which this moves has a problem that is not about
    // opacity at all.
    final bare = frame.meanColorAt(
      shot.pointOf('backRight', const Offset3d(0.08, 0.08, 0.0)),
      radius: 6,
    );

    // **Is the label still there?** Coverage cannot answer it: the label sits
    // on a panel, so a disc over a vanished letter still reports the panel and
    // reads 1.0 whatever happened. The answer has to be a colour, and the
    // label is near-white on a dark blue card — so it is the luminance at the
    // letter against the luminance of the same card beside it.
    //
    // The letter, not the label: a disc at the centre of a two-letter label
    // lands in the gap between them, which `README.md` records as the first
    // version of `two_surfaces_of_type` failing on a correct frame.
    final onLetter = frame.meanColorAt(
      shot.pointOf('label', const Offset3d(0.25, 0.5, 0.0)),
      radius: 7,
    );
    final besideLetter = frame.meanColorAt(
      shot.pointOf('fadeLeft', const Offset3d(0.88, 0.25, 0.0)),
      radius: 7,
    );

    // **The pin**, which stands in front of the faded card and is not part of
    // the faded subtree. Every approach that leaves the depth buffer in charge
    // draws it over the card whatever the card's opacity. An approach that
    // composites the subtree as a flat image buries it.
    final pin = frame.meanColorAt(shot.centerOf('pin'), radius: 9);

    rows.add(
      _Reading(
        approach: approach,
        fade: fade,
        turned: turned,
        leftCoverage: frame.coverageAt(lowOnCard, radius: 12),
        rightCoverage: frame.coverageAt(shot.centerOf('fadeRight'), radius: 12),
        left: left,
        right: right,
        bare: bare,
        ink: _luma(onLetter) - _luma(besideLetter),
        // Green over red: the pin is the only green thing in the scene, so
        // this is positive where it drew and negative where the warm backdrop
        // or the cold card is showing instead.
        pin: pin == null ? 0.0 : pin.g - pin.r,
      ),
    );
  }

  testWidgets('three ways to fade a subtree', (tester) async {
    for (final approach in FadeApproach.values) {
      final isLayer = approach == FadeApproach.layer;
      for (final fade in kFades) {
        final shot = isLayer
            ? await shootLayer(tester, fade, turned: false)
            : await shoot(tester, fadeScene(approach, fade));
        keep(shot);
        read(shot, approach, fade, false);
      }
      // Turned, at one opacity. Turning is what separates a shader that
      // writes depth from one that merely happened to be drawn in the right
      // order, and it is the arrangement `type_on_a_turning_panel` proved can
      // lose a label off the panel it is written on.
      final turned = isLayer
          ? await shootLayer(tester, 0.5, turned: true)
          : await shoot(tester, fadeScene(approach, 0.5, turned: true));
      keep(turned);
      read(turned, approach, 0.5, true);
    }

    // The floor, and the only thing here that is allowed to fail: every
    // capture has to have produced a frame at all. An approach that draws the
    // wrong picture is a result; an approach that draws no picture is a bug in
    // the experiment.
    for (final row in rows) {
      expect(
        row.bare,
        isNotNull,
        reason: '${row.label}: the unfaded backdrop did not draw at all',
      );
    }

    _report(rows);
  });
}

class _Shot {
  _Shot(
    this.name,
    this.frame,
    this.png,
    this.content,
    this.camera,
    this.viewSize,
  );

  final String name;
  final FrameProbe frame;
  final Uint8List png;
  final ProbeSceneContent content;
  final Camera camera;
  final ui.Size viewSize;

  ui.Offset centerOf(String probe) {
    final box = content.probes[probe]!;
    final point = box.screenCenter(camera, viewSize);
    if (point == null) fail('"\$probe" does not project onto the view');
    return point;
  }

  ui.Offset pointOf(String probe, Offset3d fraction) {
    final box = content.probes[probe]!;
    final point = box.screenPointOf(fraction, camera, viewSize);
    if (point == null) fail('"\$probe" \$fraction does not project');
    return point;
  }
}

class _Reading {
  _Reading({
    required this.approach,
    required this.fade,
    required this.turned,
    required this.leftCoverage,
    required this.rightCoverage,
    required this.left,
    required this.right,
    required this.bare,
    required this.ink,
    required this.pin,
  });

  final FadeApproach approach;
  final double fade;
  final bool turned;
  final double leftCoverage;
  final double rightCoverage;
  final ui.Color? left;
  final ui.Color? right;
  final ui.Color? bare;
  final double ink;
  final double pin;

  String get label =>
      '${approach.id}@${fade.toStringAsFixed(2)}${turned ? ' turned' : ''}';
}

/// How far a colour leans to red over blue.
///
/// The backdrop is warm and the faded panel is cold, so this is positive where
/// the backdrop is showing and negative where the panel is. A **channel
/// order**, which is the one kind of colour claim this harness trusts: no
/// exposure or tone-mapping change can put more red than blue into a blue
/// panel.
double _rb(ui.Color? c) => c == null ? 0.0 : c.r - c.b;

double _luma(ui.Color? c) =>
    c == null ? 0.0 : 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

String _n(double v) => v.toStringAsFixed(3).padLeft(6);

void _report(List<_Reading> rows) {
  final out = StringBuffer()
    ..writeln('')
    ..writeln('== the opacity experiment ==================================')
    ..writeln('')
    ..writeln('r-b  : >0 the warm backdrop is showing, <0 the cold panel is')
    ..writeln('luma : how lit that spot is; a hole reads as the dark clear')
    ..writeln('cov  : how much of the disc is geometry at all')
    ..writeln('ink  : coverage on the first letter of the label')
    ..writeln('')
    ..writeln(
      'approach   fade  turn | '
      'LEFT  r-b   luma    cov | RIGHT r-b   luma    cov |    ink    pin',
    );
  for (final row in rows) {
    out.writeln(
      '${row.approach.id.padRight(8)} '
      '${row.fade.toStringAsFixed(2)}  '
      '${(row.turned ? 'yes' : ' no').padRight(4)} | '
      '     ${_n(_rb(row.left))} ${_n(_luma(row.left))} '
      '${_n(row.leftCoverage)} | '
      '      ${_n(_rb(row.right))} ${_n(_luma(row.right))} '
      '${_n(row.rightCoverage)} | ${_n(row.ink)} ${_n(row.pin)}',
    );
  }
  out
    ..writeln('')
    ..writeln('============================================================');
  // ignore: avoid_print
  print(out);
}
