import 'package:flutter_scene/scene.dart'
    show
        CuboidGeometry,
        Geometry,
        Mesh,
        Node,
        PerspectiveCamera,
        PhysicallyBasedMaterial,
        SphereGeometry;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

import 'probe_scene.dart';

// Every NodeBox3d here uses BoxFit3d.contain rather than the default
// BoxFit3d.none. It matters more than it looks: with `none` the content keeps
// its own size inside whatever slot layout gave it, so a box's screen bounds
// enclose empty space and a probe aimed at "the edge of this box" finds
// nothing. `contain` makes the box's extent and the geometry's extent the same
// thing, which is the premise the whole harness rests on.

/// Geometry is shared across scenes; only nodes are per-item, because a
/// [NodeBox3d] owns the transform of the content it holds.
Geometry get _cube => _cubeGeometry ??= CuboidGeometry(Vector3.all(1));
Geometry? _cubeGeometry;

Geometry get _sphere => _sphereGeometry ??= SphereGeometry(radius: 0.5);
Geometry? _sphereGeometry;

/// A lit, opaque node in a single flat colour.
///
/// Bright and saturated on purpose: the probe distinguishes geometry from the
/// clear colour by distance, so content that is nearly the background is
/// content the harness cannot see.
Node _solid(Geometry geometry, Vector4 color) => Node(
  mesh: Mesh(geometry, PhysicallyBasedMaterial()..baseColorFactor = color),
);

final Vector4 _amber = Vector4(0.95, 0.65, 0.15, 1);
final Vector4 _teal = Vector4(0.15, 0.75, 0.70, 1);
final Vector4 _violet = Vector4(0.55, 0.35, 0.90, 1);

/// A camera raised above the ground, looking down at the origin.
///
/// A level camera sees the `xz` plane exactly edge-on: every point on it lands
/// on the horizon line, and near is indistinguishable from far. A ground-plane
/// scene is only legible from above it.
PerspectiveCamera _raisedCamera() =>
    PerspectiveCamera(position: Vector3(0, 3.4, 5.2), target: Vector3(0, 0, 0));

/// Every scene the render test draws.
///
/// Each one is deterministic, uses primitives generated in code rather than
/// assets, and names the boxes its assertions care about. A scene that needs
/// an asset is a scene that can fail for a reason that has nothing to do with
/// layout.
final List<ProbeScene> kProbeScenes = <ProbeScene>[
  // ── Does the protocol place things where it says it does? ────────────

  ProbeScene('row_of_cubes', () {
    final left = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _amber),
      name: 'left',
    );
    final middle = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _teal),
      name: 'middle',
    );
    final right = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _violet),
      name: 'right',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(4.5, 1.4, 1)),
          child: Row3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment3d.center,
            children: [
              SizedBox3d.cube(1, child: left),
              SizedBox3d.cube(1, child: middle),
              SizedBox3d.cube(1, child: right),
            ],
          ),
        ),
      ],
      probes: {'left': left, 'middle': middle, 'right': right},
    );
  }),

  ProbeScene('column_spacing', () {
    final top = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _amber),
      name: 'top',
    );
    final bottom = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _teal),
      name: 'bottom',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(1.4, 3.4, 1)),
          child: Column3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment3d.center,
            children: [
              SizedBox3d.cube(1, child: top),
              SizedBox3d.cube(1, child: bottom),
            ],
          ),
        ),
      ],
      probes: {'top': top, 'bottom': bottom},
    );
  }),

  ProbeScene('ground_plane', () {
    final near = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _amber),
      name: 'near',
    );
    final far = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _teal),
      name: 'far',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          basis: LayoutBasis3d.xz,
          constraints: Constraints3d.tight(const Size3d(1.4, 3.4, 0.6)),
          child: Column3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment3d.center,
            children: [
              SizedBox3d.cube(0.8, child: far),
              SizedBox3d.cube(0.8, child: near),
            ],
          ),
        ),
      ],
      // The first child of a column on `xz` is the *far* one: the basis maps
      // layout y to scene +z, and the camera sits at +z, so walking down the
      // column walks toward the viewer.
      probes: {'far': far, 'near': near},
    );
  }, camera: _raisedCamera()),

  ProbeScene('padding_and_alignment', () {
    final child = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _violet),
      name: 'child',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(4, 3, 1)),
          child: Padding3d(
            padding: const EdgeInsets3d.only(left: 1.5, top: 1.0),
            child: Align3d(
              alignment: Alignment3d.topLeft,
              child: SizedBox3d.cube(0.9, child: child),
            ),
          ),
        ),
      ],
      probes: {'child': child},
    );
  }),

  ProbeScene('intrinsic_sizing', () {
    // A NodeBox3d measures the geometry it holds, so a row of a sphere and a
    // cube of the same nominal extent tracks the actual bounds rather than a
    // guess. If measurement broke, these two stop being the same size.
    final ball = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_sphere, _amber),
      name: 'ball',
    );
    final box = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _teal),
      name: 'box',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.4, 1.4, 1)),
          child: Row3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment3d.center,
            children: [
              SizedBox3d.cube(1, child: ball),
              SizedBox3d.cube(1, child: box),
            ],
          ),
        ),
      ],
      probes: {'ball': ball, 'box': box},
    );
  }),

  ProbeScene('stack_depth', () {
    // Stack3d steps each child toward the viewer, so the last child is in
    // front. Both are at the same place on the plane; only depth separates
    // them, and the front one must be what the frame shows.
    final back = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _amber),
      name: 'back',
    );
    final front = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _violet),
      name: 'front',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3, 3, 1.5)),
          child: Stack3d(
            alignment: Alignment3d.center,
            depthStep: 0.35,
            children: [
              SizedBox3d.cube(1.6, child: back),
              SizedBox3d.cube(0.8, child: front),
            ],
          ),
        ),
      ],
      probes: {'back': back, 'front': front},
    );
  }),
];
