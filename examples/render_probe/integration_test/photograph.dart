import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' show WidgetTester;

import 'package:render_probe/frame_probe.dart';
import 'package:render_probe/probe_scene.dart' show kProbeClear;

/// A frame of an application, photographed from inside the process.
class Photograph {
  Photograph._(this.name, this.png, this.frame);

  /// What the photograph is of, which becomes its file name.
  final String name;

  /// The frame, encoded as a PNG.
  final Uint8List png;

  /// The same frame, for asking whether anything drew at all.
  final FrameProbe frame;

  /// The entry `integration_test`'s driver hands to its `onScreenshot`, which
  /// is how the bytes leave the application: the driver writes them on the
  /// host, where no app sandbox stands between the test and the file.
  Map<String, Object> get report => <String, Object>{
    'screenshotName': name,
    'bytes': png.toList(),
  };
}

final GlobalKey _boundary = GlobalKey(debugLabel: 'photograph');

/// Pumps [app] filling the window and photographs it once it has settled.
///
/// The recipe every capture in this repository's history was made with, and
/// the three things in it that cost time are built in rather than written
/// down: the frames are pumped with **real delays** between them, because the
/// engine's resources and a glyph atlas arrive on the platform's clock and not
/// on the test's; the backdrop is an opaque colour **inside** the boundary,
/// because a boundary photographs only what is under it and a scene draws
/// nothing where it has no geometry; and nothing is written from here, because
/// the macOS app sandbox makes the process's own temporary directory a
/// container nobody will look in.
///
/// Call [initialize] — `Scene.initializeStaticResources`, or the Material
/// package's `initializeMaterial3d` — before this, never after: geometry and
/// materials are built when [app] first builds. Call [photographAgain] to
/// photograph the same app at a later moment without pumping it again.
Future<Photograph> photograph(
  WidgetTester tester,
  Widget app, {
  required String name,
  int frames = 100,
  Future<void> Function()? initialize,
}) async {
  // One ordinary frame first: some backends race GPU context setup when the
  // engine uploads textures before a first frame has established a context.
  await tester.pumpWidget(const ColoredBox(color: kProbeClear));
  await tester.pump();
  await initialize?.call();

  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ColoredBox(color: kProbeClear, child: app),
    ),
  );
  return photographAgain(tester, name: name, frames: frames);
}

/// Lets the app already pumped by [photograph] run for [frames] more frames,
/// and photographs it again.
///
/// The way to ask a question about motion: the gallery's panel turns, and a
/// second photograph a few seconds later shows it from another angle.
/// Advances the clock by [frames] frames without taking a picture.
///
/// The same loop [photographAgain] runs, and it exists separately because
/// `pumpAndSettle` is not usable against this app: the binding has a real
/// clock and the gallery schedules a frame from its `onTick` for ever, so
/// there is no moment at which no further frame is coming.
Future<void> pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

Future<Photograph> photographAgain(
  WidgetTester tester, {
  required String name,
  int frames = 100,
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final view = tester.view;
  final image = await boundary.toImage(pixelRatio: view.devicePixelRatio);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final frame = await FrameProbe.fromImage(image);
  image.dispose();
  return Photograph._(name, png!.buffer.asUint8List(), frame);
}
