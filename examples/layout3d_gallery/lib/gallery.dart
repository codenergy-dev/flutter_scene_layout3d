import 'dart:math' as math;

import 'package:flutter/material.dart';
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
        Layout3dController,
        SceneLayout3d,
        SceneListView3d,
        SceneNodeBox3d,
        SceneSizedBox3d;
import 'package:vector_math/vector_math.dart' as vm;

/// Three layout surfaces built with `flutter_scene_layout3d`: Flutter's box
/// protocol arranging real geometry in the scene.
///
/// Left, an upright panel driven imperatively, turning on its axis to show
/// that a laid-out tree follows the plane node it hangs from. Middle, the
/// same protocol on the ground plane, where the basis makes layout's "down"
/// run away from the camera. Right, a scrolling list described declaratively
/// with the widget layer.
///
/// All three are hit-testable: the pointer is turned into a camera ray and
/// walked down the layout tree, so hovering names what is under the cursor
/// and dragging the list scrolls it, even while the panel it sits beside is
/// turning.
class Layout3dGallery extends StatefulWidget {
  const Layout3dGallery({super.key});

  @override
  State<Layout3dGallery> createState() => _Layout3dGalleryState();
}

class _Layout3dGalleryState extends State<Layout3dGallery> {
  final Scene scene = Scene();
  final PerspectiveCamera camera = PerspectiveCamera(
    position: vm.Vector3(0, 1.9, 6.4),
    target: vm.Vector3(0, 1.0, 0),
  );

  // Geometry is shared between the pieces; only the nodes are per-item,
  // because a NodeBox3d owns the transform of the content it is given.
  final Geometry _unitCube = CuboidGeometry(vm.Vector3.all(1));
  final Geometry _ball = SphereGeometry(radius: 0.5);
  final Geometry _ring = TorusGeometry(radius: 0.4, tubeRadius: 0.14);

  late final Layout3dSurface _panel;
  late final Layout3dSurface _ground;
  final Scroll3dController _scroll = Scroll3dController();

  /// Reaches the surface the declarative list is laid out on, which the
  /// widget layer owns.
  final Layout3dController _listSurface = Layout3dController();

  Layout3dPointer? _listPointer;

  /// What the cursor is over, by layout name.
  String? _under;

  /// Set once the list has been dragged, which retires the clock that scrolls
  /// it for show.
  bool _scrolledByHand = false;

  double _time = 0.0;

  /// Content sized by the layout rather than by itself: the box is fixed and
  /// [BoxFit3d.contain] scales the model down into it.
  Layout3d _sized(double extent, Node content, {String? name}) =>
      SizedBox3d.cube(
        extent,
        child: NodeBox3d(content: content, fit: BoxFit3d.contain, name: name),
      );

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

  @override
  void initState() {
    super.initState();
    _panel = _buildPanel();
    _ground = _buildGround();
    scene.add(_panel.plane);
    scene.add(_ground.plane);
  }

  /// An upright panel: a backing slab pinned to the plane's back face,
  /// content standing in front of it, and a badge pinned to a corner.
  Layout3dSurface _buildPanel() {
    final surface = Layout3dSurface(
      constraints: Constraints3d.tight(const Size3d(2.6, 1.7, 0.4)),
      child: Stack3d(
        alignment: Alignment3d.center,
        fit: StackFit3d.expand,
        children: [
          // A unit cube stretched over the plane by BoxFit3d.fill: the
          // layout box made visible. Pinned to the back so everything else
          // has room to stand in front of it.
          Positioned3d(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            back: 0,
            depth: 0.08,
            child: NodeBox3d(
              content: _piece(_unitCube, vm.Vector4(0.10, 0.11, 0.14, 1.0)),
              fit: BoxFit3d.fill,
            ),
          ),
          Padding3d(
            // Symmetric on the two in-plane axes only: an all-round inset
            // would eat the plane's thickness as well.
            padding: const EdgeInsets3d.symmetric(
              horizontal: 0.2,
              vertical: 0.16,
            ),
            child: Column3d(
              mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
              children: [
                // A row of three pieces, spaced by the main axis alignment.
                Row3d(
                  mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
                  children: [
                    _sized(
                      0.36,
                      _piece(_unitCube, vm.Vector4(0.85, 0.35, 0.25, 1.0)),
                      name: 'cube',
                    ),
                    _sized(
                      0.36,
                      _piece(_ball, vm.Vector4(0.30, 0.62, 0.90, 1.0)),
                      name: 'sphere',
                    ),
                    _sized(
                      0.36,
                      _piece(
                        _ring,
                        vm.Vector4(0.95, 0.78, 0.30, 1.0),
                        metallic: 0.8,
                      ),
                      name: 'torus',
                    ),
                  ],
                ),
                // A bar split two-to-one, the flex protocol dividing the
                // room that is left over.
                SizedBox3d(
                  height: 0.24,
                  depth: 0.1,
                  child: Row3d(
                    crossAxisAlignment: CrossAxisAlignment3d.stretch,
                    depthAxisAlignment: CrossAxisAlignment3d.stretch,
                    spacing: 0.08,
                    children: [
                      Expanded3d(
                        flex: 2,
                        child: NodeBox3d(
                          content: _piece(
                            _unitCube,
                            vm.Vector4(0.30, 0.72, 0.55, 1.0),
                          ),
                          fit: BoxFit3d.fill,
                        ),
                      ),
                      Expanded3d(
                        child: NodeBox3d(
                          content: _piece(
                            _unitCube,
                            vm.Vector4(0.45, 0.45, 0.52, 1.0),
                          ),
                          fit: BoxFit3d.fill,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Pinned to the top right corner, sized on every axis so it stands
          // proud of the slab instead of sinking into it.
          Positioned3d(
            top: 0.08,
            right: 0.08,
            width: 0.26,
            height: 0.26,
            depth: 0.26,
            child: NodeBox3d(
              content: _piece(_ball, vm.Vector4(0.95, 0.30, 0.45, 1.0)),
              fit: BoxFit3d.contain,
              name: 'badge',
            ),
          ),
        ],
      ),
    );
    surface.plane.position = vm.Vector3(-2.1, 1.35, 0);
    return surface;
  }

  /// The same protocol on the floor. Only the basis changes: layout's "down"
  /// becomes the scene's +Z, so a Row3d runs across the ground and the
  /// pieces stand up out of it.
  Layout3dSurface _buildGround() {
    final surface = Layout3dSurface(
      basis: LayoutBasis3d.xz,
      constraints: Constraints3d.tight(const Size3d(3.0, 1.1, 0.8)),
      child: Padding3d(
        padding: const EdgeInsets3d.symmetric(horizontal: 0.1, vertical: 0.1),
        child: Row3d(
          mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
          // On the ground the first cross axis is layout y, which the xz
          // basis maps to scene z: this lines the pieces up along the far
          // edge of the plane.
          crossAxisAlignment: CrossAxisAlignment3d.end,
          children: [
            for (var index = 0; index < 4; index++)
              _sized(
                0.3 + index * 0.12,
                _piece(_ball, vm.Vector4(0.35 + index * 0.15, 0.55, 0.85, 1.0)),
                name: 'ground ${index + 1}',
              ),
          ],
        ),
      ),
    );
    surface.plane.position = vm.Vector3(0.2, 0.0, 1.9);
    return surface;
  }

  /// The pointer onto the list, made on first use: the declarative surface
  /// only exists once the widget layer has built it.
  Layout3dPointer? _listPointerFor(Layout3dSurface? surface) {
    if (surface == null) return null;
    final held = _listPointer;
    if (held != null && identical(held.surface, surface)) return held;
    return Layout3dPointer(surface);
  }

  vm.Ray _rayAt(Offset position, Size viewSize) =>
      camera.screenPointToRay(position, viewSize);

  void _handleDown(Offset position, Size viewSize) {
    _listPointer = _listPointerFor(_listSurface.surface);
    if (_listPointer?.down(_rayAt(position, viewSize)) ?? false) {
      _scrolledByHand = true;
    }
  }

  void _handleMove(Offset position, Size viewSize) {
    _listPointer?.move(_rayAt(position, viewSize));
    _reportHover(position, viewSize);
  }

  /// Names the deepest layout under the cursor, across all three surfaces.
  ///
  /// Each surface is asked in turn and the first answer wins; they stand well
  /// apart here, so there is nothing to sort by distance.
  void _reportHover(Offset position, Size viewSize) {
    final ray = _rayAt(position, viewSize);
    String? found;
    for (final surface in <Layout3dSurface?>[
      _panel,
      _ground,
      _listSurface.surface,
    ]) {
      final target = surface?.hitTestRay(ray).target;
      if (target != null) {
        found = target.node.name;
        break;
      }
    }
    if (found != _under) setState(() => _under = found);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = constraints.biggest;
        return Listener(
          onPointerDown: (event) => _handleDown(event.localPosition, viewSize),
          onPointerMove: (event) => _handleMove(event.localPosition, viewSize),
          onPointerUp: (_) => _listPointer?.up(),
          onPointerCancel: (_) => _listPointer?.up(),
          onPointerHover: (event) =>
              _reportHover(event.localPosition, viewSize),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildScene(),
              Positioned(
                left: 16,
                bottom: 16,
                child: Text(
                  _under == null
                      ? 'Drag the list to scroll it'
                      : 'Pointing at: $_under',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScene() {
    return SceneView(
      scene,
      camera: camera,
      children: [
        // The declarative layer: the same layout objects, described in a
        // build method and reconciled through the element tree.
        SceneLayout3d(
          controller: _listSurface,
          size: const Size3d(1.15, 1.7, 0.3),
          position: vm.Vector3(2.2, 1.35, 0),
          child: SceneListView3d(
            controller: _scroll,
            itemExtent: 0.38,
            spacing: 0.06,
            children: [
              for (var index = 0; index < 9; index++)
                SceneSizedBox3d.cube(
                  0.3,
                  key: ValueKey(index),
                  child: SceneNodeBox3d(
                    content: _piece(
                      index.isEven ? _unitCube : _ball,
                      vm.Vector4(0.85, 0.55 + (index % 3) * 0.12, 0.25, 1.0),
                    ),
                    fit: BoxFit3d.contain,
                  ),
                ),
            ],
          ),
        ),
      ],
      onTick: (elapsed, deltaSeconds) {
        _time = elapsed.inMicroseconds / 1e6;

        // Turning the plane node carries everything laid out on it.
        _panel.plane.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          math.sin(_time * 0.4) * 0.5,
        );

        // The list scrolls itself until someone takes hold of it, so the
        // example shows movement before it is touched and then hands the
        // position over to the drag for good.
        if (!_scrolledByHand) {
          final sweep = (math.sin(_time * 0.5) + 1) / 2;
          _scroll.jumpTo(_scroll.maxScrollExtent * sweep);
        }

        // Cheap when nothing is dirty, so the imperative surfaces are
        // simply flushed every frame.
        _panel.flush();
        _ground.flush();
      },
    );
  }
}
