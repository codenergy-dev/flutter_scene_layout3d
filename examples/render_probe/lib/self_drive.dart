// Driving the real window: a scripted run of an application, in a window a
// person could be looking at, photographed as it goes.
//
// **This is a third harness, and it exists because the other two cannot ask
// the question.** `flutter test` has no GPU. `flutter drive` has one, but it
// pumps frames on the test's clock — `await tester.pump()` runs a frame and
// then waits for the test, so every asynchronous arrival in the engine has
// landed by the time the next frame is built, and a defect that lives in the
// gap between a repack and its texture readback is never once open. Everything
// this repository has failed to reproduce under `flutter drive` failed for
// that reason, three separate rounds of it.
//
// What is different here: `flutter run`, a real window on the display's own
// clock, real vsync, a real resize — and the state changes *synthesized* rather
// than clicked, because driving a window through the operating system needs
// accessibility permissions an agent does not have and a person does not want
// to grant. A tap is a `PointerDownEvent` handed to `GestureBinding`, which is
// exactly what the platform hands it; nothing below that layer can tell the
// difference.
//
// See *Driving the real window* in `README.md`.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerDeviceKind,
        PointerDownEvent,
        PointerScrollEvent,
        PointerUpEvent;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show GlyphAtlasCache3d, Layout3d, Semantics3d;
// ignore: implementation_imports
import 'package:flutter_scene_layout3d/src/testing/scene.dart'
    show Reach3d, sceneSurfaces3d;

/// The window the run happens in, which Dart cannot resize on its own.
const MethodChannel _window = MethodChannel('render_probe/window');

/// Where the photographs go.
///
/// The app is sandboxed, so this is inside its container rather than anywhere
/// a person would guess — which is why [SelfDrive.start] prints it.
late final Directory _photographs;

final GlobalKey _boundary = GlobalKey(debugLabel: 'self drive');

/// Wraps [child] in the boundary [SelfDrive] photographs.
///
/// A boundary photographs only what is under it, and a scene draws nothing
/// where it has no geometry, so the backdrop has to be inside it.
Widget selfDriveBoundary(
  Widget child, {
  Color backdrop = const Color(0xFF101418),
}) => RepaintBoundary(
  key: _boundary,
  child: ColoredBox(color: backdrop, child: child),
);

/// One step of a script: what to do, and what to call the photograph of it.
class SelfDriveStep {
  const SelfDriveStep(
    this.name, {
    this.act,
    this.settle = const Duration(milliseconds: 700),
    this.dumpAtlases = false,
  });

  /// What the photograph after this step is called.
  final String name;

  /// What to do before photographing, or null to only wait and look.
  final Future<void> Function()? act;

  /// How long to let the application run before the photograph.
  ///
  /// **Real time, not pumped frames.** The whole point of this harness is that
  /// the clock is the display's.
  final Duration settle;

  /// Whether to write the atlases out beside this step's photograph.
  ///
  /// The pair is what settles a text artifact: the frame says a letter is
  /// wrong and the atlas says whether the picture it sampled was.
  final bool dumpAtlases;
}

/// Runs a script against a live application and photographs each step.
abstract final class SelfDrive {
  static int _sequence = 0;

  /// Starts a run, after [boot] to let the first frames and the engine's
  /// static resources land.
  static Future<void> start(
    List<SelfDriveStep> script, {
    Duration boot = const Duration(seconds: 4),
    bool quitWhenDone = true,
  }) async {
    _photographs = Directory('${Directory.systemTemp.path}/self_drive')
      ..createSync(recursive: true);
    debugPrint('SelfDrive: photographs land in ${_photographs.path}');
    await Future<void>.delayed(boot);
    for (final step in script) {
      try {
        await step.act?.call();
      } catch (error, stack) {
        debugPrint('SelfDrive: ${step.name} could not be acted on: $error');
        debugPrint('$stack');
      }
      await Future<void>.delayed(step.settle);
      await photograph(step.name);
      reportAtlases(step.name);
      if (step.dumpAtlases) await SelfDrive.dumpAtlases(prefix: step.name);
    }
    debugPrint(
      'SelfDrive: done, $_sequence photographs in '
      '${_photographs.path}',
    );
    if (quitWhenDone) exit(0);
  }

  /// Photographs the boundary and writes it as a PNG.
  static Future<void> photograph(String name) async {
    final context = _boundary.currentContext;
    if (context == null) {
      debugPrint('SelfDrive: nothing to photograph for $name');
      return;
    }
    final boundary = context.findRenderObject()! as RenderRepaintBoundary;
    final ratio = View.of(context).devicePixelRatio;
    final image = await boundary.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return;
    final index = (_sequence++).toString().padLeft(2, '0');
    final file = File('${_photographs.path}/${index}_$name.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    debugPrint('SelfDrive: photographed ${file.path}');
  }

  /// Prints what every glyph atlas is holding, beside the photograph of it.
  ///
  /// The half a picture cannot show: whether the letters in the frame were
  /// drawn from a picture of the packing they were measured against.
  static void reportAtlases(String name) {
    for (final atlas in GlyphAtlasCache3d.shared.atlases) {
      // **The invariant first**, because it is the one that should never fail
      // and the one a wall standing without its face would need to have
      // failed. A grapheme here is a letter whose mesh is pointing somewhere
      // the uploaded picture does not have it.
      final stale = atlas.debugStaleGlyphs().toList();
      if (stale.isNotEmpty) {
        debugPrint(
          'SelfDrive: at $name, $atlas is handing out slots the picture does '
          'not hold for ${stale.join()} '
          '(textureIsCurrent ${atlas.textureIsCurrent}).',
        );
      }
      if (atlas.textureIsCurrent && !atlas.needsRaster) continue;
      debugPrint(
        'SelfDrive: at $name, $atlas is handing out generation '
        '${atlas.generation} revision ${atlas.revision} while its picture is '
        'of generation ${atlas.textureGeneration} revision '
        '${atlas.textureRevision}'
        '${atlas.needsRaster ? ', and it still owes a raster' : ''}.',
      );
    }
  }

  /// Writes every glyph atlas out as a PNG, beside the photographs.
  ///
  /// The other half of a text artifact, and the half no photograph of the
  /// application can show: a letter drawn wrong is either a wrong coordinate
  /// or a wrong picture, and this is the picture. It rasterizes again rather
  /// than reading back what is on the GPU — same packing, same code path, and
  /// nothing else can be read out of a texture from Dart.
  static Future<void> dumpAtlases({String prefix = 'atlas'}) async {
    var index = 0;
    for (final atlas in GlyphAtlasCache3d.shared.atlases) {
      // **The picture on the GPU, not a fresh one.** Asking the atlas to draw
      // itself again answers what it would look like now; the artifact lives
      // in the difference between that and what was uploaded.
      final image = atlas.debugPicture ?? await atlas.rasterize();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        image.pixels,
        image.size,
        image.size,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final decoded = await completer.future;
      final bytes = await decoded.toByteData(format: ui.ImageByteFormat.png);
      decoded.dispose();
      if (bytes == null) continue;
      final size = atlas.style.fontSize?.round() ?? 0;
      final file = File(
        '${_photographs.path}/${prefix}_${index++}_${size}dp_'
        'gen${image.generation}_${image.size}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      debugPrint('SelfDrive: wrote ${file.path}');
    }
  }

  /// Maximizes the window, the way a person does.
  static Future<void> zoom() => _window.invokeMethod<void>('zoom');

  /// Puts the window back to [width] x [height] logical pixels.
  static Future<void> restore({double width = 800, double height = 628}) =>
      _window.invokeMethod<void>('restore', <String, double>{
        'width': width,
        'height': height,
      });

  /// Presses the box whose semantic label is [label], through the camera.
  ///
  /// The same aim `tap3d` takes in a headless test — the box's projected
  /// centre, found through the layout tree rather than hard-coded — and then a
  /// real pointer event, because there is no tester here to send one.
  static Future<void> tap(Pattern label) async {
    final at = pointOf(label);
    if (at == null) {
      debugPrint('SelfDrive: nothing labelled "$label" to press.');
      return;
    }
    await tapAt(at);
  }

  /// Presses the point [at], in global coordinates.
  static Future<void> tapAt(Offset at) async {
    final binding = GestureBinding.instance;
    const pointer = 7734;
    binding.handlePointerEvent(
      PointerDownEvent(pointer: pointer, position: at),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    binding.handlePointerEvent(PointerUpEvent(pointer: pointer, position: at));
  }

  /// Turns a mouse wheel by [delta] over the box labelled [label].
  static Future<void> scroll(Pattern label, Offset delta) async {
    final at = pointOf(label);
    if (at == null) {
      debugPrint('SelfDrive: nothing labelled "$label" to scroll.');
      return;
    }
    GestureBinding.instance.handlePointerEvent(
      PointerScrollEvent(
        position: at,
        scrollDelta: delta,
        kind: PointerDeviceKind.mouse,
      ),
    );
  }

  /// Where the box labelled [label] is on the screen, or null when nothing
  /// carries that label or it cannot be aimed at.
  static Offset? pointOf(Pattern label) {
    final box = _find(label);
    if (box == null) return null;
    return Reach3d.of(box, sceneSurfaces3d()).global;
  }

  /// The labelled box, searched the way `find3d.bySemanticsLabel` searches:
  /// every surface in the widget tree, in tree order, with each overlay's
  /// detached entries straight after the surface that holds the overlay —
  /// which is what `sceneSurfaces3d` already returns. So a dialog on a
  /// surface of its own is found without the script knowing where it is.
  static Layout3d? _find(Pattern label) {
    for (final record in sceneSurfaces3d()) {
      final found = _search(record.surface, label);
      if (found != null) return found;
    }
    return null;
  }

  static Layout3d? _search(Layout3d box, Pattern label) {
    if (box is Semantics3d) {
      final own = box.properties.label;
      if (own != null && _matches(own, label)) return box;
    }
    Layout3d? found;
    box.visitChildren((child) {
      found ??= _search(child, label);
    });
    return found;
  }

  static bool _matches(String value, Pattern label) =>
      label is String ? value == label : label.allMatches(value).isNotEmpty;
}
