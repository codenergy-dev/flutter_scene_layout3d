// The smallest thing that loses draw calls.
//
//   cd examples/render_probe
//   flutter run -d macos --enable-flutter-gpu -t lib/main_minimal_repro.dart \
//     --dart-define=scene=true --dart-define=wrap=true
//
// The probe draws a grid of plain white rectangles into an offscreen picture,
// reads it back, and reports which cells came back empty. Nothing is a glyph
// and nothing is text, because neither turned out to matter: reversing the
// draw order moves the loss to the other end of the image, so what is lost is
// **the draw calls made first**, not a region and not a letter.
//
// Two switches, so the cause can be bisected without the gallery:
//   scene  a flutter_scene scene with geometry, drawing every frame
//   wrap   gpu.Texture.fromImage over a rendered image, on a timer
//   resize the window is maximized and restored between probes
//   busy   a second offscreen `toImage` runs continuously alongside the probe
//   layout a flutter_scene_layout3d surface inside the scene view

import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:ui' as ui;

// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart'
    show
        CuboidGeometry,
        DirectionalLight,
        Mesh,
        Node,
        PerspectiveCamera,
        PhysicallyBasedMaterial,
        Scene,
        SceneView,
        SphereGeometry;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart' show Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show SceneLayout3d, SceneSizedBox3d;
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

const bool _withScene = bool.fromEnvironment('scene');
const bool _withWrap = bool.fromEnvironment('wrap');
const bool _withResize = bool.fromEnvironment('resize');
const bool _withBusy = bool.fromEnvironment('busy');
const bool _withLayout = bool.fromEnvironment('layout');

/// Keeps a second offscreen render in flight, the way a glyph atlas flushing
/// in the background does.
bool _busy = false;
Future<void> _keepBusy() async {
  while (_busy) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < 40; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * 10.0, i * 10.0, 8, 8),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(512, 512);
    picture.dispose();
    image.dispose();
  }
}

const MethodChannel _window = MethodChannel('render_probe/window');

const int _cell = 40;
const int _columns = 12;
const int _count = 39;

/// Draws [_count] rectangles on a grid, back to front when [reverse], and
/// returns the cells that came back empty.
Future<List<int>> _emptyCells({bool reverse = false}) async {
  final edge = _cell * _columns;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final order = <int>[for (var i = 0; i < _count; i++) i];
  for (final i in reverse ? order.reversed : order) {
    canvas.drawRect(
      Rect.fromLTWH(
        ((i % _columns) * _cell + 4).toDouble(),
        ((i ~/ _columns) * _cell + 4).toDouble(),
        20,
        20,
      ),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(edge, edge);
  picture.dispose();
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  final bytes = data!.buffer.asUint8List();
  final empty = <int>[];
  for (var i = 0; i < _count; i++) {
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

/// Renders a small image and wraps it as a GPU texture, the way a glyph atlas
/// does on every flush.
Future<void> _wrap() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 256, 256),
    Paint()..color = const Color(0xFF808080),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(512, 512);
  picture.dispose();
  try {
    gpu.Texture.fromImage(gpu.gpuContext, image);
  } catch (error) {
    debugPrint('MINIMAL could not wrap: $error');
    image.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Widget app = const ColoredBox(color: Color(0xFF101418));
  if (_withScene) {
    await Scene.initializeStaticResources();
    final scene = Scene()..directionalLight = DirectionalLight();
    for (var i = 0; i < 12; i++) {
      scene.add(
        Node(
            mesh: Mesh(
              i.isEven ? CuboidGeometry(Vector3(1, 1, 1)) : SphereGeometry(),
              PhysicallyBasedMaterial()
                ..baseColorFactor = Vector4(0.2 + i / 20, 0.6, 0.85, 1),
            ),
          )
          ..localTransform.setTranslation(
            Vector3((i % 4) * 1.6 - 2.4, (i ~/ 4) * 1.6 - 1.6, 0),
          ),
      );
    }
    app = SceneView(
      scene,
      camera: PerspectiveCamera(
        position: Vector3(0, 0, 6),
        target: Vector3.zero(),
      ),
      children: <Widget>[
        if (_withLayout)
          const SceneLayout3d(
            size: Size3d(2, 2, 0.4),
            child: SceneSizedBox3d.cube(1),
          ),
      ],
    );
  }
  runApp(app);
  await Future<void>.delayed(const Duration(seconds: 3));

  debugPrint(
    'MINIMAL scene=$_withScene wrap=$_withWrap resize=$_withResize '
    'busy=$_withBusy layout=$_withLayout',
  );
  if (_withBusy) {
    _busy = true;
    unawaited(_keepBusy());
    unawaited(_keepBusy());
    unawaited(_keepBusy());
  }
  for (var tick = 0; tick < 12; tick++) {
    if (_withResize) {
      // Alternate, so half the probes follow a grow and half follow a shrink.
      if (tick.isEven) {
        await _window.invokeMethod<void>('zoom');
      } else {
        await _window.invokeMethod<void>('restore', <String, double>{
          'width': 800.0,
          'height': 628.0,
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    if (_withWrap) {
      for (var i = 0; i < 8; i++) {
        await _wrap();
      }
    }
    final forward = await _emptyCells();
    final backward = await _emptyCells(reverse: true);
    debugPrint(
      'MINIMAL tick$tick: forward '
      '${forward.isEmpty ? 'clean' : forward.toString()} | reversed '
      '${backward.isEmpty ? 'clean' : backward.toString()}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  _busy = false;
  debugPrint('MINIMAL done');
  exit(0);
}
