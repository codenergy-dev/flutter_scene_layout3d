// The gallery, driven through the reproduction recipe, with one extra
// measurement at every step: an offscreen render of plain `dart:ui` text,
// done twice, with nothing from this repository's glyph atlas in it.
//
//   cd examples/render_probe
//   flutter run -d macos --enable-flutter-gpu -t lib/main_engine_probe.dart
//
// The point is to find *which action* breaks the engine's own text, rather
// than to look at what the breakage does to us. A round that prints two equal
// numbers is a healthy engine; a round that prints a smaller second number is
// the engine losing glyphs it has already drawn once.

import 'dart:async' show unawaited;
import 'dart:io' show exit;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show debugReportGlyphAtlasRepacks, debugVerifyGlyphAtlasInk;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart'
    show initializeMaterial3d;
import 'package:layout3d_gallery/main.dart' show Layout3dGalleryApp;

import 'self_drive.dart';

const String _alphabet = 'AdaLovelaceTheenginweavsbrcptofymSqRBkE';

/// One cell per item, on a fixed grid, so a missing item is a missing *cell*.
const int _cell = 40;
const int _columns = 12;

/// Draws [count] items on the grid and returns the indices that came back
/// empty.
///
/// [reverse] records the draw calls back to front without moving anything, so
/// the same cell is drawn at the opposite end of the display list. [glyphs]
/// picks between text and a plain filled rectangle. Between them the three
/// questions are separable: is it the *position* in the image, the *order* of
/// the draws, or *text* specifically.
Future<List<int>> _emptyCells({
  required bool reverse,
  required bool glyphs,
}) async {
  final items = _alphabet.split('');
  final edge = _cell * _columns;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final kept = <ui.Paragraph>[];
  final order = <int>[for (var i = 0; i < items.length; i++) i];
  for (final i in reverse ? order.reversed : order) {
    final left = ((i % _columns) * _cell + 4).toDouble();
    final top = ((i ~/ _columns) * _cell + 4).toDouble();
    if (!glyphs) {
      canvas.drawRect(
        Rect.fromLTWH(left, top, 20, 20),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      continue;
    }
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 16))
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
      ..addText(items[i]);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    canvas.drawParagraph(paragraph, Offset(left, top));
    kept.add(paragraph);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(edge, edge);
  picture.dispose();
  for (final paragraph in kept) {
    paragraph.dispose();
  }
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  final bytes = data!.buffer.asUint8List();
  final empty = <int>[];
  for (var i = 0; i < items.length; i++) {
    final left = (i % _columns) * _cell;
    final top = (i ~/ _columns) * _cell;
    var found = false;
    for (var y = top; y < top + _cell && !found; y++) {
      for (var x = left; x < left + _cell; x++) {
        if (bytes[(y * edge + x) * 4 + 3] > 8) {
          found = true;
          break;
        }
      }
    }
    if (!found) empty.add(i);
  }
  return empty;
}

String _say(List<int> empty) => empty.isEmpty ? 'clean' : 'empty cells $empty';

/// Asks the three separable questions, once.
Future<void> _probe(String at) async {
  final forward = await _emptyCells(reverse: false, glyphs: true);
  final backward = await _emptyCells(reverse: true, glyphs: true);
  final rects = await _emptyCells(reverse: false, glyphs: false);
  debugPrint(
    'ENGINE at $at: text ${_say(forward)} | text-reversed ${_say(backward)} '
    '| rects ${_say(rects)}',
  );
}

/// Whether the harness photographs between steps.
///
/// **This is a control, not a convenience.** A photograph is a
/// `RenderRepaintBoundary.toImage` of the whole window — at a maximized retina
/// window that is a 2880x1694 offscreen render — and the loss first appears
/// immediately after the first maximized photograph. So the harness has to be
/// able to take itself out of the measurement, or it cannot tell its own
/// artifact from the application's defect.
const bool _photograph = bool.fromEnvironment('photograph');

/// Stops right after the first maximize, which is where the loss appears.
///
/// The whole script takes minutes; bisecting an engine wants seconds.
const bool _fast = bool.fromEnvironment('fast');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugReportGlyphAtlasRepacks = false;
  debugVerifyGlyphAtlasInk = false;
  await initializeMaterial3d();
  runApp(selfDriveBoundary(const Layout3dGalleryApp()));
  unawaited(_run());
}

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> _step(
  String name,
  Future<void> Function()? act,
  int settle,
) async {
  await _probe(name);
  try {
    await act?.call();
  } catch (error) {
    debugPrint('ENGINE: $name could not be acted on: $error');
  }
  await _wait(settle);
  if (_photograph) await SelfDrive.photograph(name);
}

Future<void> _run() async {
  debugPrint('ENGINE photograph=$_photograph');
  await _wait(4000);
  await _step('small_settled', SelfDrive.restore, 4000);
  await _step('still_small', null, 2000);
  await _step('maximized', SelfDrive.zoom, 3000);
  await _step('after_maximize', null, 2000);
  if (_fast) {
    await _probe('fast_final');
    exit(0);
  }
  await _step('menu_open', () => SelfDrive.tap('More'), 700);
  await _step('dialog', () => SelfDrive.tap('About'), 700);
  await _step('dialog_settled', null, 1000);
  await _step('settings', () => SelfDrive.tap('Settings'), 700);
  await _step('settings_settled', null, 1000);
  await _step('inbox_again', () => SelfDrive.tap('Inbox'), 700);
  await _step(
    'scrolled',
    () => SelfDrive.scroll('Inbox', const Offset(0, 220)),
    700,
  );
  await _step('menu_again', () => SelfDrive.tap('More'), 700);
  await _step('sort', () => SelfDrive.tap('Sort by'), 700);
  await _step('sort_settled', null, 2000);
  await _step('idle_after', null, 3000);
  await _probe('final');
  exit(0);
}
