import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart'
    show Camera, PerspectiveCamera, Scene, SceneView;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// The colour the probe clears to.
///
/// Deliberately not black: "the frame is entirely the clear colour" and "the
/// frame is entirely unlit geometry" are different failures, and a black clear
/// makes them look identical.
const Color kProbeClear = Color(0xFF101820);

/// The key on the [RepaintBoundary] the test captures.
final GlobalKey probeBoundaryKey = GlobalKey(debugLabel: 'probeBoundary');

/// What a scene hands back to the harness.
///
/// [probes] is the whole point: it names the boxes a test wants to ask about,
/// so the assertion can say "where did layout put `left`?" rather than
/// hard-coding a pixel. The surface's own tree is the oracle, and this map is
/// how a test reaches into it without walking it.
class ProbeSceneContent {
  ProbeSceneContent({
    required this.surfaces,
    this.probes = const <String, Layout3d>{},
  });

  /// The laid-out surfaces, in the order they are added to the scene.
  final List<Layout3dSurface> surfaces;

  /// Boxes this scene wants its test to be able to locate on screen.
  final Map<String, Layout3d> probes;
}

/// A named, deterministic scene the render test can draw and probe.
class ProbeScene {
  const ProbeScene(this.id, this.build, {this.camera, this.viewSize});

  /// Stable identifier, used in the test name and the capture filename.
  final String id;

  /// Builds the surfaces. Called once the engine is ready, never before:
  /// geometry and material constructors touch the shader bundle.
  final ProbeSceneContent Function() build;

  /// The camera to view it from. Defaults to [defaultCamera].
  final Camera? camera;

  /// The size the view is given. Fixed so a probe's arithmetic does not depend
  /// on the window the test happens to run in.
  final Size? viewSize;

  static const Size defaultViewSize = Size(640, 480);

  /// A camera far enough back to see a surface a few units across, looking at
  /// the origin down the negative z axis.
  static Camera defaultCamera() =>
      PerspectiveCamera(position: Vector3(0, 0, 6), target: Vector3(0, 0, 0));
}

/// Hosts one [ProbeScene] inside the boundary the test captures.
///
/// The scene is built in [initState] rather than in `build`, because building
/// it allocates geometry and a rebuild must not allocate it again.
class ProbeSceneView extends StatefulWidget {
  const ProbeSceneView(this.probe, {super.key});

  final ProbeScene probe;

  @override
  State<ProbeSceneView> createState() => ProbeSceneViewState();
}

class ProbeSceneViewState extends State<ProbeSceneView> {
  final Scene scene = Scene();
  late final Camera camera;
  late final ProbeSceneContent content;

  @override
  void initState() {
    super.initState();
    camera = widget.probe.camera ?? ProbeScene.defaultCamera();
    content = widget.probe.build();
    for (final surface in content.surfaces) {
      scene.add(surface.plane);
      surface.flush();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.probe.viewSize ?? ProbeScene.defaultViewSize;
    return Center(
      child: RepaintBoundary(
        key: probeBoundaryKey,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ColoredBox(
            color: kProbeClear,
            child: SceneView(scene, camera: camera),
          ),
        ),
      ),
    );
  }
}
