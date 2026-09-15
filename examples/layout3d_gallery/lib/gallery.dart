import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter_scene/scene.dart'
    show
        CuboidGeometry,
        Geometry,
        Mesh,
        Node,
        PerspectiveCamera,
        PhysicallyBasedMaterial,
        Scene,
        SceneView,
        SphereGeometry,
        TorusGeometry;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        AtlasText3dRenderer,
        Input3dHit,
        SceneInput3d,
        SceneLayout3d,
        SceneListView3d,
        SceneNodeBox3d,
        SceneOverlay3d,
        SceneSemantics3d,
        SceneSizedBox3d;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'screens.dart';

/// Three surfaces in one scene, all live at the same time and all
/// hit-testable.
///
/// **Left**, a Material screen standing upright on a panel that turns: the
/// layout does not re-run to make that happen, because turning is the plane
/// node's business and layout's is the arrangement on it.
///
/// **Middle**, the same catalogue lying flat on the ground, where
/// [LayoutBasis3d.xz] makes layout's "down" run away from the camera. This is
/// the case a 2D toolkit has no answer for, and the elevations on it are
/// heights rather than shadows.
///
/// **Right**, a scrolling list of real meshes, described declaratively. It is
/// deliberately *not* Material: the same protocol arranges an application's
/// own geometry, and having both in one frame is what says so.
class Layout3dGallery extends StatefulWidget {
  const Layout3dGallery({super.key});

  @override
  State<Layout3dGallery> createState() => _Layout3dGalleryState();
}

class _Layout3dGalleryState extends State<Layout3dGallery> {
  final Scene scene = Scene();

  /// Where the whole gallery is looked at from.
  ///
  /// **The engine's camera basis puts +x on the viewer's *left*.**
  /// `flutter_scene` builds its view matrix with `right = up × forward`, so a
  /// camera out on +z looking back at the origin has a right vector of `-x`.
  /// Every position below is authored with that in mind: the screen is at
  /// positive x and appears on the left.
  final PerspectiveCamera camera = PerspectiveCamera(
    position: vm.Vector3(0, 4.4, 10.4),
    target: vm.Vector3(0.1, 1.5, 0.9),
  );

  /// The node the upright screen hangs from, so it can be turned without the
  /// widget that declares the surface fighting the rotation for ownership.
  final Node _panelPivot = Node();

  // Geometry is shared between the pieces; only the nodes are per-item,
  // because a NodeBox3d owns the transform of the content it is given.
  final Geometry _unitCube = CuboidGeometry(vm.Vector3.all(1));
  final Geometry _ball = SphereGeometry(radius: 0.5);
  final Geometry _ring = TorusGeometry(radius: 0.4, tubeRadius: 0.14);

  final Scroll3dController _scroll = Scroll3dController();

  /// What the cursor is over, by semantic label or layout name.
  String? _under;

  /// Set once the list of meshes has been dragged, which retires the clock
  /// that scrolls it for show.
  bool _scrolledByHand = false;

  double _time = 0.0;

  @override
  void initState() {
    super.initState();
    scene.add(_panelPivot);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Node _piece(Geometry geometry, vm.Vector4 color, {double metallic = 0.0}) {
    return Node(
      mesh: Mesh(
        geometry,
        PhysicallyBasedMaterial()
          ..baseColorFactor = color
          ..metallicFactor = metallic
          ..roughnessFactor = 0.35
          ..vertexColorWeight = 0.0,
      ),
    );
  }

  // --- input -------------------------------------------------------------

  /// Reports what a press or a hover found.
  ///
  /// The whole of this gallery's input wiring. There is no `Listener`, no
  /// `camera.screenPointToRay`, no pointer group filled in from a tick and no
  /// z-orders restated every frame: `SceneInput3d` owns all of that, and each
  /// surface states where it stands on its own widget.
  void _handleHit(Input3dHit hit) {
    // A press that took hold of the mesh list retires the clock that scrolls
    // it for show, and hands the position to the drag for good.
    if (hit.grabbedScrollable) _scrolledByHand = true;
    _report(hit.result);
  }

  /// Names the thing under the cursor.
  ///
  /// A Material component states its own name through a `Semantics3d` — a
  /// tile announces its title, a button its label — so the readout walks the
  /// hit path for the first box that has something to say, and falls back to
  /// a layout's debug name for the raw meshes on the right.
  void _report(HitTestResult3d hit) {
    String? found;
    for (final entry in hit.path) {
      final layout = entry.layout;
      if (layout is Semantics3d) {
        final label = layout.properties.label;
        if (label != null && label.isNotEmpty) {
          found = label;
          break;
        }
      }
      found ??= layout.node.name;
    }
    if (found != _under) setState(() => _under = found);
  }

  // --- the scene ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Everything the pointers need, said once: the camera the rays are cast
    // from, and where to report what they found. Each surface below says
    // where it stands and nothing here repeats it.
    return SceneInput3d(
      camera: camera,
      onHit: _handleHit,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildScene(),
          Positioned(
            left: 16,
            bottom: 16,
            child: Text(
              _under == null
                  ? 'Tap the screen, throw a switch, drag the slider'
                  : 'Pointing at: $_under',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScene() {
    return SceneView(
      scene,
      camera: camera,
      children: [
        // The upright screen. It hangs from a pivot node this state owns and
        // turns, so the surface widget declares no rotation of its own: the
        // ownership rule is that whatever the widget declares, the next build
        // writes back over.
        //
        // The z-orders below say what is in front of what, which is a
        // statement geometry cannot make for a screen turned away from the
        // camera: the upright screen, then the table, then the meshes. The
        // snack bars this screen opens are detached surfaces of their own and
        // land a whole step in front of it, with nothing said here.
        SceneLayout3d(
          parent: _panelPivot,
          zOrder: 0.2,
          size: const Size3d(3.5, 4.8, 0.6),
          child: _themed(SceneOverlay3d(child: const MaterialScreen())),
        ),
        // The same catalogue on the ground. Only the basis changes.
        SceneLayout3d(
          zOrder: 0.1,
          basis: LayoutBasis3d.xz,
          size: const Size3d(4.6, 2.6, 0.6),
          // A screen on a table is a *smaller* screen, and the unit contract
          // is where that is said: at 12 world units per hundred logical
          // pixels this plane is 383 by 216dp rather than the 460 by 260 the
          // default rate would make it, so its type is legible from across
          // the room. Nothing below hears about it — every figure in
          // `TableScreen` is still in logical pixels.
          metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.012),
          position: vm.Vector3(-1.1, 0.0, 2.5),
          child: _themed(const TableScreen()),
        ),
        // Not Material at all: the same protocol arranging an application's
        // own meshes, scrolling, on a surface of its own.
        SceneLayout3d(
          size: const Size3d(1.2, 3.2, 0.4),
          position: vm.Vector3(-3.0, 2.4, 0),
          child: SceneListView3d(
            controller: _scroll,
            itemExtent: 0.5,
            spacing: 0.08,
            children: [
              for (var index = 0; index < 9; index++)
                SceneSemantics3d(
                  key: ValueKey(index),
                  properties: SemanticsProperties(
                    label: 'Piece ${index + 1}',
                    // A label with no reading direction is a framework
                    // assertion the moment semantics are switched on. The
                    // catalogue's components fall back to the enclosing
                    // Directionality; a hand-written Semantics3d states it.
                    textDirection: TextDirection.ltr,
                  ),
                  child: SceneSizedBox3d.cube(
                    0.42,
                    child: SceneNodeBox3d(
                      content: _piece(
                        switch (index % 3) {
                          0 => _unitCube,
                          1 => _ball,
                          _ => _ring,
                        },
                        vm.Vector4(0.85, 0.55 + (index % 3) * 0.12, 0.25, 1.0),
                        metallic: index % 3 == 2 ? 0.8 : 0.0,
                      ),
                      fit: BoxFit3d.contain,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      onTick: (elapsed, deltaSeconds) {
        _time = elapsed.inMicroseconds / 1e6;

        // Turning the pivot carries the whole screen laid out on it, and
        // relayouts nothing.
        _panelPivot
          ..position = vm.Vector3(1.4, 2.4, -0.3)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 1, 0),
            math.sin(_time * 0.35) * 0.13,
          );

        // The mesh list scrolls itself until someone takes hold of it, so
        // there is movement before anything is touched and the position is
        // handed to the drag for good afterwards.
        if (!_scrolledByHand) {
          final sweep = (math.sin(_time * 0.5) + 1) / 2;
          _scroll.jumpTo(_scroll.maxScrollExtent * sweep);
        }
      },
    );
  }

  /// The two halves of Material setup that are widgets rather than the one
  /// call in `main`: the tokens, and the renderer that turns a `Text3d` into
  /// glyph quads.
  ///
  /// The renderer is a *factory* rather than an instance because a
  /// `Text3dRenderer` is owned and disposed by the label that holds it, so
  /// there is no global one to install. Its `resolution` is the only thing
  /// that decides how sharp a glyph is — it has nothing to do with how big
  /// the type is on the panel.
  Widget _themed(Widget child) => SceneTheme3d(
    data: Theme3dData.light,
    textRendererFactory: () => AtlasText3dRenderer(resolution: 3.0),
    child: child,
  );
}
