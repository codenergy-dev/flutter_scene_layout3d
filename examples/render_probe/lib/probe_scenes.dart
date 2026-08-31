import 'package:flutter_scene/scene.dart'
    show
        CuboidGeometry,
        Geometry,
        Mesh,
        Node,
        PerspectiveCamera,
        PhysicallyBasedMaterial,
        SphereGeometry,
        loadFmatMaterial;
import 'package:flutter/painting.dart'
    show Color, TextAlign, TextSpan, TextStyle;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

import 'probe_scene.dart';

/// Installs the panel painter, once.
///
/// `BoxDecoration3d` measures and lays out perfectly well with no painter and
/// draws nothing at all, which is how the package ships. This is the wiring an
/// application does at startup, and the only thing standing between a
/// decoration and a visible panel.
///
/// `assets/box_decoration3d.fmat` is a symlink to the package's own shader, so
/// what is compiled and loaded here is the shipped file rather than a copy of
/// it that could drift.
Future<void> installPanelPainter() async {
  if (BoxDecoration3d.painterFactory != null) return;
  final material = await loadFmatMaterial('assets/box_decoration3d.fmat');
  BoxDecoration3d.painterFactory = (_) =>
      BoxDecoration3dPainter(createMaterial: () => material);
}

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

/// Big, bright type: a glyph has to cover enough pixels for a coverage
/// fraction to mean something, and it has to differ from both the clear
/// colour and the panel it is drawn on.
const TextStyle _labelStyle = TextStyle(
  fontSize: 180,
  color: Color(0xFFEA9F26),
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
    //
    // The children are deliberately *thin*. A child thicker than the depth
    // step is not separated by it: a 1.6-deep back slab centred on the plane
    // reaches further toward the viewer than a 0.8-deep child stepped 0.35,
    // so the back one wins the depth test and the stack looks broken. The
    // first version of this scene did exactly that and passed once, on
    // z-fighting, before failing.
    // `fill`, not `contain`, and that distinction is the whole reason this
    // scene took three tries. `contain` scales uniformly to fit the *smallest*
    // bounded axis, so a cube in a 1.6 x 1.6 x 0.1 slot comes out a 0.1 cube —
    // a speck. `fill` scales each axis on its own and gives the slab the box
    // actually describes.
    final back = NodeBox3d(
      fit: BoxFit3d.fill,
      content: _solid(_cube, _amber),
      name: 'back',
    );
    final front = NodeBox3d(
      fit: BoxFit3d.fill,
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
              SizedBox3d(width: 1.6, height: 1.6, depth: 0.1, child: back),
              SizedBox3d(width: 0.8, height: 0.8, depth: 0.1, child: front),
            ],
          ),
        ),
      ],
      probes: {'back': back, 'front': front},
    );
  }),

  ProbeScene('clipped_row', () {
    // A row wider than the ClipBox3d around it. The clipping contract is
    // whole-node culling here: a child entirely outside the box is not drawn
    // at all, and one inside is. Three plans depend on this contract, and
    // until now nothing had ever looked at what it does to a frame.
    final inside = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _teal),
      name: 'inside',
    );
    final outside = NodeBox3d(
      fit: BoxFit3d.contain,
      content: _solid(_cube, _violet),
      name: 'outside',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(1.6, 1.4, 1)),
          child: ClipBox3d(
            child: OverflowBox3d(
              maxWidth: double.infinity,
              alignment: Alignment3d.centerLeft,
              child: Row3d(
                crossAxisAlignment: CrossAxisAlignment3d.center,
                spacing: 1.4,
                children: [
                  SizedBox3d.cube(1, child: inside),
                  SizedBox3d.cube(1, child: outside),
                ],
              ),
            ),
          ),
        ),
      ],
      probes: {'inside': inside, 'outside': outside},
    );
  }),

  ProbeScene('scrolled_list', () {
    // A list scrolled by a known offset. The item that was at the top is
    // gone; the one that took its place is drawn. Layout says where each one
    // landed, and the frame is asked to agree.
    final controller = Scroll3dController();
    final items = <NodeBox3d>[
      for (var i = 0; i < 6; i++)
        NodeBox3d(
          fit: BoxFit3d.contain,
          content: _solid(_cube, i.isEven ? _amber : _teal),
          name: 'item$i',
        ),
    ];
    final list = ListView3d(
      controller: controller,
      spacing: 0.25,
      children: [for (final item in items) SizedBox3d.cube(0.7, child: item)],
    );
    final surface = Layout3dSurface(
      constraints: Constraints3d.tight(const Size3d(1.2, 2.6, 1)),
      child: ClipBox3d(child: list),
    );
    // Lay out once so the viewport knows its extent, then scroll and let the
    // caller flush again.
    surface.flush();
    controller.jumpTo(1.9);
    return ProbeSceneContent(
      surfaces: [surface],
      probes: {for (var i = 0; i < items.length; i++) 'item$i': items[i]},
    );
  }),

  // ── Text: the other seam a unit test cannot reach ────────────────────
  //
  // Everything about text up to the quads is arithmetic and is covered by the
  // package's own suite. What is not is whether the quads are *visible*: an
  // atlas that never uploaded, a mesh wound away from the viewer, a label at
  // exactly the depth of the panel behind it. All three measure perfectly and
  // draw nothing at all, which is why they need a frame to catch them.
  // The surface is wider than the label needs on purpose. `Text3d` breaks a
  // word too wide for its line — Flutter's rule, not CSS's — so a label that
  // only just fits is a label that silently becomes two lines, and every
  // assertion about where its ink is goes with it.
  ProbeScene('text_label', () {
    final label = Text3d(
      'ABC',
      style: _labelStyle,
      renderer: AtlasText3dRenderer(),
      name: 'label',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.loose(const Size3d(6.0, 1.8, 0.2)),
          child: Center3d(child: label),
        ),
      ],
      probes: {'label': label},
    );
  }),

  ProbeScene('text_label_undrawn', () {
    // The control, and the reason the scene above means anything: the same
    // label with no renderer measures the same and draws nothing. Without it,
    // "there are pixels where the label is" could be any other geometry.
    final label = Text3d('ABC', style: _labelStyle, name: 'label');
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.loose(const Size3d(6.0, 1.8, 0.2)),
          child: Center3d(child: label),
        ),
      ],
      probes: {'label': label},
    );
  }, minCoverage: 0),

  ProbeScene('text_on_panel', () {
    // A label on the panel it labels. Both are drawn, and the glyphs have to
    // win the depth test against the surface they sit on — which they only do
    // because the renderer lifts them toward the viewer. Coplanar text is
    // text that vanishes, and nothing but a frame notices.
    final panel = DecoratedBox3d(
      decoration: const BoxDecoration3d(
        color: Color(0xFF26B3A8),
        borderRadius: BorderRadius3d.circular(40),
      ),
      name: 'panel',
      child: Center3d(
        child: Text3d(
          'OK',
          style: _labelStyle,
          renderer: AtlasText3dRenderer(),
          name: 'label',
        ),
      ),
    );
    final label = (panel.child! as Center3d).child! as Text3d;
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.6, 1.8, 0.2)),
          child: panel,
        ),
      ],
      probes: {'panel': panel, 'label': label},
    );
  }, preload: installPanelPainter),

  ProbeScene('rich_text', () {
    // The escape hatch: Flutter lays the paragraph out and rasterizes it, and
    // the capture lands on a quad this package built. Two styles in one span,
    // because that is the thing `Text3d` cannot do at all.
    final text = RichText3d(
      const TextSpan(
        children: <TextSpan>[
          TextSpan(text: 'Aa', style: TextStyle(fontSize: 150)),
          TextSpan(
            text: 'Bb',
            style: TextStyle(fontSize: 150, color: Color(0xFF7A59E6)),
          ),
        ],
        style: TextStyle(fontSize: 150, color: Color(0xFFEA9F26)),
      ),
      textAlign: TextAlign.center,
      name: 'paragraph',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.loose(const Size3d(3.6, 1.8, 0.2)),
          child: Center3d(child: text),
        ),
      ],
      probes: {'paragraph': text},
    );
  }),

  // ── The seam no unit test can reach: does the shader draw? ────────────
  ProbeScene('rounded_panel', () {
    // A panel with a corner radius of a third of its height. The corners
    // the SDF carves away are the assertion: geometry in the middle, clear
    // space where the radius took it.
    final panel = DecoratedBox3d(
      decoration: const BoxDecoration3d(
        color: Color(0xFFEA9F26),
        borderRadius: BorderRadius3d.circular(60),
      ),
      name: 'panel',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.6, 1.8, 0.2)),
          child: panel,
        ),
      ],
      probes: {'panel': panel},
    );
  }, preload: installPanelPainter),

  ProbeScene('square_panel', () {
    // The same panel with no radius, which is what makes the rounded one
    // meaningful: without a square control, "the corner is empty" could
    // just as well mean the panel never drew.
    final panel = DecoratedBox3d(
      decoration: const BoxDecoration3d(color: Color(0xFF26B3A8)),
      name: 'panel',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.6, 1.8, 0.2)),
          child: panel,
        ),
      ],
      probes: {'panel': panel},
    );
  }, preload: installPanelPainter),
];
