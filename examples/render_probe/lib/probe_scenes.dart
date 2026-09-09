import 'package:flutter_scene/scene.dart'
    show
        CuboidGeometry,
        DirectionalLight,
        Geometry,
        Mesh,
        Node,
        PerspectiveCamera,
        PhysicallyBasedMaterial,
        SphereGeometry;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart'
    show Color, TextAlign, TextSpan, TextStyle;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:vector_math/vector_math.dart' show Ray, Vector3, Vector4;

import 'probe_scene.dart';

/// Installs the panel painter, once.
///
/// `BoxDecoration3d` measures and lays out perfectly well with no painter and
/// draws nothing at all, which is how the package ships. This is the wiring an
/// application does at startup, and the only thing standing between a
/// decoration and a visible panel.
///
/// It is `flutter_scene_material3d`'s own call rather than the two lines the
/// layout package's README shows, and running it here is the point: the
/// setup a Material application makes has no other verification lane, since
/// loading a compiled `.fmat` needs a GPU context that `flutter test` does
/// not have. It also does the thing the README's one-liner cannot — give
/// every decorated box a material of its own, so a row of panels in three
/// different colours draws in three different colours instead of collapsing
/// onto whichever painted last.
///
/// The shader itself is compiled by `flutter_scene_layout3d`'s own build
/// hook, not by this app's: the source path names the file in the package
/// that ships it, and `loadFmatMaterial` resolves it through that package's
/// generated manifest. This app used to compile it through a symlink, and no
/// longer has to.
Future<void> installPanelPainter() => initializeMaterial3d();

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
final Vector4 _paleGrey = Vector4(0.82, 0.82, 0.84, 1);

/// The panel scenes' fill and border colours.
///
/// Chosen so that *which* of them a pixel holds can be read off a single
/// channel comparison: the fill is blue-dominant and the border is
/// red-dominant, and no amount of lighting, exposure or tone mapping swaps
/// that order. A colour *distance* would not do — it is just as large when
/// the two are the wrong way round, which is exactly the bug the border probe
/// found.
const Color _panelFill = Color(0xFF1B3A6B);

/// A single icon glyph, big and bright, in Material's own icon font.
///
/// The family name is the one `uses-material-design: true` puts in the
/// bundle, and there is no `package:` on it: the font ships with the
/// application rather than with a package, which is the one spelling detail
/// that turns a drawn icon into a blank.
const TextStyle _iconStyle = TextStyle(
  fontFamily: 'MaterialIcons',
  fontSize: 220,
  color: Color(0xFFEA9F26),
);
const Color _panelBorder = Color(0xFFEA9F26);

/// One panel, alone on a surface, at a size a probe can name points inside.
///
/// Every decoration scene is this tree with a different decoration on it, so
/// that a pair of captures differs in exactly the thing under test and the
/// plain panel can be the control for all three.
ProbeSceneContent _panelScene(
  BoxDecoration3d decoration, {
  StateLayer3d stateLayer = StateLayer3d.none,
}) {
  final panel = DecoratedBox3d(
    decoration: decoration,
    stateLayer: stateLayer,
    name: 'panel',
  );
  return ProbeSceneContent(
    surfaces: [
      Layout3dSurface(
        constraints: Constraints3d.tight(const Size3d(3.6, 1.8, 0.1)),
        child: panel,
      ),
    ],
    probes: {'panel': panel},
  );
}

/// A camera far enough back for the metrics-scaled button scene.
///
/// That scene states its own `unitsPerLogicalPixel`, so its geometry is six
/// times the size the rest of these scenes work at and the default camera
/// clips straight through it.
PerspectiveCamera _wideCamera() =>
    PerspectiveCamera(position: Vector3(0, 0, 12), target: Vector3(0, 0, 0));

/// A camera raised above the ground, looking down at the origin.
///
/// A level camera sees the `xz` plane exactly edge-on: every point on it lands
/// on the horizon line, and near is indistinguishable from far. A ground-plane
/// scene is only legible from above it.
PerspectiveCamera _raisedCamera() =>
    PerspectiveCamera(position: Vector3(0, 3.4, 5.2), target: Vector3(0, 0, 0));

/// A world-space ray aimed straight at [point] on [surface]'s plane.
///
/// The same helper the package's own tests use, reproduced here because it is
/// test scaffolding rather than API: it starts well in front of the plane and
/// runs along the depth axis, so where it lands is exactly the layout-space
/// point named, whatever basis the surface has. That is what lets a scene
/// drive a real drag without a camera in the picture.
Ray _rayAt(Layout3dSurface surface, Offset3d point) {
  final toWorld = surface.node.globalTransform;
  final origin = toWorld.transformed3(
    Vector3(point.x, point.y, point.z - 10.0),
  );
  return Ray.originDirection(origin, toWorld.rotated3(Vector3(0, 0, 1)));
}

/// Picks a [Draggable3d] up at [from] and carries it to [to], leaving the drag
/// in flight for the frame to be captured.
///
/// Three steps, and the middle one is the one that is easy to leave out. The
/// press and the first move recognize the drag and put the feedback into the
/// overlay — but an overlay entry has no size on the frame it is inserted, so
/// [Draggable3d] cannot yet work out where the feedback has to sit to cover
/// the card. A flush gives it one, and the second move is what actually writes
/// the node offset the probe is here to look at.
void _dragAcross(
  Layout3dSurface surface, {
  required Offset3d from,
  required Offset3d to,
}) {
  final pointer = Layout3dPointer(surface);
  final midway = Offset3d.lerp(from, to, 0.25);
  pointer
    ..down(_rayAt(surface, from))
    ..move(_rayAt(surface, midway));
  surface.flush();
  pointer.move(_rayAt(surface, to));
  surface.flush();
}

/// The boxes `switch_thumb` builds, collected as it goes.
///
/// Two switches with four named parts between them, built by one closure —
/// so the names are registered where they are created rather than reassembled
/// afterwards, which is how a probe map goes stale.
final Map<String, Layout3d> _switchProbes = <String, Layout3d>{};

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

  // ── The rest of the panel: elevation, the border, the state layer ────
  //
  // Three uniforms the shader has always declared and the painter has always
  // written, and which nothing had ever looked at. Each is a pair, and
  // `plain_panel` is the control for all three, so a claim is always "this
  // capture differs from the identical one without the feature", never "there
  // are some pixels here".
  ProbeScene(
    'plain_panel',
    () => _panelScene(const BoxDecoration3d(color: _panelFill)),
    preload: installPanelPainter,
  ),

  ProbeScene(
    'elevated_panel',
    // 60dp, which at the default rate is 0.6 world units — a tenth of the way
    // to a camera six units back, so the panel projects about eleven per cent
    // larger than the identical flat one. Written in dp, like every figure on a
    // decoration: `elevation: 0.6` would ask for six thousandths of a unit.
    () => _panelScene(const BoxDecoration3d(color: _panelFill, elevation: 60)),
    preload: installPanelPainter,
  ),

  ProbeScene(
    'bordered_panel',
    // 40dp of border on a 1.8-unit-high panel: 0.4 units, a band nearly a
    // quarter of the height, so a probe disc fits inside it with room either
    // side.
    () => _panelScene(
      const BoxDecoration3d(
        color: _panelFill,
        border: Border3d(width: 40, color: _panelBorder),
      ),
    ),
    preload: installPanelPainter,
  ),

  ProbeScene(
    'state_layer_panel',
    () => _panelScene(
      const BoxDecoration3d(color: _panelFill),
      stateLayer: const StateLayer3d(color: Color(0xFFFFFFFF), opacity: 0.32),
    ),
    preload: installPanelPainter,
  ),

  ProbeScene(
    'panel_shadow',
    () {
      // What a panel casts onto the ground under it, which turns out to be
      // nothing. See the test: the cube is the control that proves the light,
      // the shadow pass and the receiving ground all work, and the panel
      // beside it — the same size, at the same height, under the same light —
      // leaves the ground unchanged.
      //
      // Both surfaces lie on the ground basis and are the same tree, so the
      // caster over each ground patch is exactly above its centre. The upper
      // one is lifted by moving its plane node, which is the surface's own
      // documented degree of freedom.
      NodeBox3d ground(String name) => NodeBox3d(
        fit: BoxFit3d.fill,
        content: _solid(_cube, _paleGrey),
        name: name,
      );
      final patches = <String, NodeBox3d>{
        for (final name in ['underCube', 'underPanel', 'underNothing'])
          name: ground(name),
      };
      final groundSurface = Layout3dSurface(
        basis: LayoutBasis3d.xz,
        constraints: Constraints3d.tight(const Size3d(4.2, 1.4, 0.1)),
        child: Row3d(
          children: <Layout3d>[
            for (final patch in patches.values)
              SizedBox3d(width: 1.4, height: 1.4, depth: 0.1, child: patch),
          ],
        ),
      );

      final cube = NodeBox3d(
        fit: BoxFit3d.fill,
        content: _solid(_cube, _teal),
        name: 'cube',
      );
      final panel = DecoratedBox3d(
        decoration: const BoxDecoration3d(color: _panelFill),
        name: 'panel',
      );
      Layout3d cell(Layout3d? child) => SizedBox3d(
        width: 1.4,
        height: 1.4,
        depth: 0.1,
        child: child == null
            ? null
            : Center3d(
                child: SizedBox3d(
                  width: 0.9,
                  height: 0.9,
                  depth: 0.12,
                  child: child,
                ),
              ),
      );
      final casterSurface = Layout3dSurface(
        basis: LayoutBasis3d.xz,
        constraints: Constraints3d.tight(const Size3d(4.2, 1.4, 0.1)),
        child: Row3d(children: <Layout3d>[cell(cube), cell(panel), cell(null)]),
      );
      casterSurface.plane.position = Vector3(0, 1.3, 0);

      return ProbeSceneContent(
        surfaces: [groundSurface, casterSurface],
        probes: {...patches, 'cube': cube, 'panel': panel},
      );
    },
    camera: PerspectiveCamera(
      position: Vector3(0, 3.9, 5.4),
      target: Vector3(0, 0.5, 0),
    ),
    configureScene: (scene) {
      // Straight down but for a nudge toward the viewer, so a caster's shadow
      // lands just in front of it on screen rather than under its own
      // silhouette. `castsShadow` is off by default, which is the first thing
      // to check if this scene ever reads as "nothing casts anything".
      scene.directionalLight = DirectionalLight(
        direction: Vector3(0.0, -1.0, 0.22),
        intensity: 5.0,
        castsShadow: true,
        shadowSoftness: 0.02,
      );
    },
    preload: installPanelPainter,
  ),

  // ── A drag in flight: the one thing arithmetic cannot check ──────────
  ProbeScene('drag_feedback_depth', () {
    // The claim no headless test can make: the lift that puts a picked-up
    // card in front of the list actually wins the depth test.
    //
    // Three identical teal rows, a card picked up from the first and carried
    // over the third. The feedback is violet, so the frame answers the
    // question by colour: the middle of row 2 must read violet, and the
    // middle of row 0 — which the drag has left behind — must still read
    // teal.
    //
    // Every slab here is 0.05 deep and the lift is 0.5, which is the trap in
    // docs/traps.md applied rather than described: a depth step does not
    // separate children thicker than itself, and the eight-dp default lift is
    // a depth-buffer separation, not a distance. Thin slabs and a generous
    // lift make the comparison decisive instead of a coin toss on z-fighting.
    NodeBox3d row(String name) => NodeBox3d(
      fit: BoxFit3d.fill,
      content: _solid(_cube, _teal),
      name: name,
    );
    final rows = <NodeBox3d>[row('row0'), row('row1'), row('row2')];
    late NodeBox3d feedback;
    final source = Draggable3d<String>(
      data: 'card',
      feedbackLayer: const OverlayLayer3d.inPlane(lift: 0.5),
      feedbackBuilder: (_) {
        feedback = NodeBox3d(
          fit: BoxFit3d.fill,
          content: _solid(_cube, _violet),
          name: 'feedback',
        );
        return SizedBox3d(
          width: 2.4,
          height: 0.8,
          depth: 0.05,
          child: feedback,
        );
      },
      child: SizedBox3d(width: 3, height: 1, depth: 0.05, child: rows[0]),
    );
    final surface = Layout3dSurface(
      constraints: Constraints3d.tight(const Size3d(3, 3, 1)),
      child: Overlay3d(
        children: <Layout3d>[
          Column3d(
            children: <Layout3d>[
              source,
              for (final box in rows.skip(1))
                SizedBox3d(width: 3, height: 1, depth: 0.05, child: box),
            ],
          ),
        ],
      ),
    );
    surface.flush();
    // From the middle of row 0 to the middle of row 2: two units of travel,
    // which puts the feedback's centre exactly on row 2's centre.
    _dragAcross(
      surface,
      from: const Offset3d(1.5, 0.5, 0),
      to: const Offset3d(1.5, 2.5, 0),
    );
    return ProbeSceneContent(
      surfaces: [surface],
      probes: {'row0': rows[0], 'row2': rows[2], 'feedback': feedback},
    );
  }),

  ProbeScene('drag_feedback_detached', () {
    // The visual difference between the two overlay layers, and the reason to
    // offer both: a detached entry owns a surface of its own, so it can draw
    // outside the panel the drag started on. An in-plane entry cannot.
    //
    // The card is carried past the right edge of a two-unit panel. What the
    // frame has to show is violet geometry out there, where no panel is.
    //
    // Sized to the default camera rather than pulled away from it. The first
    // version used a two-unit panel and a camera at z = 9 so the overhang
    // stayed in frame, and covered 1.8% of it — under the 2% floor every
    // scene has to clear. Bigger geometry at the ordinary distance clears it
    // with room to spare and keeps the whole drag inside a 640x480 view: the
    // panel spans x 162 to 478, and the feedback lands at 513.
    late NodeBox3d feedback;
    final card = NodeBox3d(
      fit: BoxFit3d.fill,
      content: _solid(_cube, _teal),
      name: 'card',
    );
    final source = Draggable3d<String>(
      data: 'card',
      feedbackLayer: const OverlayLayer3d.detached(lift: 0.5),
      feedbackBuilder: (_) {
        feedback = NodeBox3d(
          fit: BoxFit3d.fill,
          content: _solid(_cube, _violet),
          name: 'feedback',
        );
        return SizedBox3d(
          width: 1.4,
          height: 0.9,
          depth: 0.05,
          child: feedback,
        );
      },
      child: SizedBox3d(width: 1.8, height: 1.1, depth: 0.05, child: card),
    );
    final panel = Overlay3d(children: <Layout3d>[Center3d(child: source)]);
    final surface = Layout3dSurface(
      constraints: Constraints3d.tight(const Size3d(3, 3, 1)),
      child: panel,
    );
    surface.flush();
    _dragAcross(
      surface,
      from: const Offset3d(1.5, 1.5, 0),
      to: const Offset3d(3.5, 1.5, 0),
    );
    return ProbeSceneContent(
      surfaces: [surface],
      probes: {'panel': panel, 'card': card, 'feedback': feedback},
    );
  }),
  // ── The catalogue: does a token become a picture? ─────────────────────
  //
  // Everything below is built through flutter_scene_material3d's own
  // resolution — `Material3d.decorationFor` is the single place a token
  // becomes a `BoxDecoration3d`, and a probe that reimplemented it would be
  // checking its own arithmetic. The scenes are imperative because this
  // harness is: a `ProbeSceneContent` holds `Layout3dSurface`es, and the
  // widget layer's job (reading the metrics, installing the ink controller)
  // is what the headless suite covers.

  ProbeScene('material_elevation', () {
    // The first claim of the catalogue: three elevation levels are three
    // distinguishable colours. That is Material 3's surface *tint*, and here
    // it carries the whole elevation signal, because a panel casts no shadow
    // and a head-on camera gets nothing from the lift.
    //
    // The **light** theme, and not for looks. The dark theme's surface is
    // #141218 and this harness clears to #101820: a dark panel is inside the
    // probe's own clear tolerance, so every pixel of it reads as background
    // and the scene "draws nothing". The light surface is near white, its
    // tint is the theme's purple primary, and the assertion is therefore an
    // order — higher is *darker* — which lighting and tone mapping can scale
    // but cannot reorder.
    //
    // The levels are 0, 2 and 5 rather than 0, 3 and 5: Material's tint table
    // is 0%, 8% and 14% there, and the two gaps are the widest three levels
    // can give.
    const theme = Theme3dData.light;
    DecoratedBox3d panel(String name, double elevation) => DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        shape: theme.shape.medium,
        thickness: theme.thickness.raised,
        elevation: elevation,
      ),
      name: name,
    );
    final flat = panel('flat', theme.elevation.level0);
    final raised = panel('raised', theme.elevation.level2);
    final high = panel('high', theme.elevation.level5);
    // Explicitly sized cells rather than `Expanded3d`. A `Row3d` hands its
    // children loose cross-axis constraints, and a `DecoratedBox3d` with no
    // child shrink-wraps — so a flexed panel comes out 1.12 x 0 x 0 and the
    // scene draws nothing at all, which is exactly how this one first ran.
    // The depth is the thickness token in world units, which is what a
    // `Material3d` would have constrained it to.
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.6, 1.2, 0.2)),
          child: Row3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
            children: <Layout3d>[
              for (final box in <Layout3d>[flat, raised, high])
                SizedBox3d(width: 1.0, height: 1.0, depth: 0.04, child: box),
            ],
          ),
        ),
      ],
      probes: {'flat': flat, 'raised': raised, 'high': high},
    );
  }, preload: installPanelPainter),

  ProbeScene('material_hover', () {
    // The second claim: a hover changes a panel, in the direction of the
    // surface's own content colour. The wash is not written by hand — it is
    // what `StateLayerOpacity3d` resolves for the hovered state over the
    // content role, which is exactly what `InkWell3d` hands the panel through
    // the ink controller.
    //
    // On a dark theme that reads as "a hover lightens the panel", which is
    // how Material describes it. On the light baseline the content colour is
    // near black, so it reads as darker — and the light theme is what this
    // scene uses, for the reason the elevation scene above gives: a dark
    // panel is inside this harness's clear tolerance and reads as background.
    const theme = Theme3dData.light;
    final decoration = Material3d.decorationFor(
      theme,
      shape: theme.shape.medium,
      thickness: theme.thickness.standard,
    );
    final idle = DecoratedBox3d(decoration: decoration, name: 'idle');
    final hovered = DecoratedBox3d(
      decoration: decoration,
      stateLayer: theme.stateLayer.resolve(const {
        Material3dState.hovered,
      }, theme.colorScheme.onSurface),
      name: 'hovered',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.6, 1.2, 0.2)),
          child: Row3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
            children: <Layout3d>[
              for (final box in <Layout3d>[idle, hovered])
                SizedBox3d(width: 1.4, height: 1.0, depth: 0.02, child: box),
            ],
          ),
        ),
      ],
      probes: {'idle': idle, 'hovered': hovered},
    );
  }, preload: installPanelPainter),

  // ── The buttons ──────────────────────────────────────────────────────
  //
  // Two claims from phase 3, and both are claims only a picture settles. Each
  // builds its panels the way the catalogue does — `ButtonStyle3d.of` for the
  // variant's tokens, `resolve` for the state, `Material3d.decorationFor` for
  // the decoration — because a probe that resolved the tokens itself would be
  // checking its own arithmetic rather than this package's.
  ProbeScene('button_disabled', () {
    // Disabled is a **substitution**, not an opacity: there is no subtree
    // opacity anywhere in this stack, so a disabled button is drawn in
    // different colours. The frame is where that either happens or does not.
    //
    // The two buttons sit on a near-white slab, and they have to: M3's
    // disabled container is `onSurface` at *12% alpha*, a figure designed to
    // composite over the surface behind it. Floating in front of this
    // harness's `#101820` clear colour it would come out inside the clear
    // tolerance and read as nothing at all.
    //
    // The direction. On the **light** theme — which this harness requires,
    // since M3's dark surface is inside its clear tolerance — an enabled
    // filled button is a mid purple and a disabled one is a pale grey, so
    // "dimmer" reads as *lighter*. Same claim, opposite sign, exactly as the
    // elevation and hover scenes above. The assertion that carries the
    // meaning is the other one: the disabled container is **closer to the
    // surface behind it** than the enabled one is, which is what losing
    // contrast is, and which comparing two distances measured the same way
    // states as a direction rather than as a bare difference.
    const theme = Theme3dData.light;
    final style = ButtonStyle3d.of(theme, ButtonVariant3d.filled);
    DecoratedBox3d button(String name, {required bool enabled}) {
      final resolved = style.resolve(const {}, enabled: enabled);
      return DecoratedBox3d(
        decoration: Material3d.decorationFor(
          theme,
          color: resolved.container,
          shape: style.shape,
          elevation: resolved.elevation,
          thickness: style.thickness,
          border: resolved.border,
          surfaceTint: const Color(0x00000000),
        ),
        name: name,
      );
    }

    final backing = DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: theme.colorScheme.surfaceContainerLowest,
        thickness: theme.thickness.raised,
      ),
      name: 'backing',
    );
    final enabled = button('enabled', enabled: true);
    final disabled = button('disabled', enabled: false);
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.6, 1.6, 0.4)),
          child: Stack3d(
            alignment: Alignment3d.center,
            // 12dp, the theme's own step. The deepest pair here is the 4dp
            // backing against a 2dp button, mean 3dp, so it clears with room.
            depthStep: 0.12,
            children: <Layout3d>[
              SizedBox3d(width: 3.6, height: 1.6, depth: 0.04, child: backing),
              SizedBox3d(
                width: 3.2,
                height: 0.4,
                depth: 0.02,
                child: Row3d(
                  mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
                  children: <Layout3d>[
                    for (final box in <Layout3d>[enabled, disabled])
                      SizedBox3d(
                        width: 1.4,
                        height: 0.4,
                        depth: 0.02,
                        child: box,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      probes: {'backing': backing, 'enabled': enabled, 'disabled': disabled},
    );
  }, preload: installPanelPainter),

  ProbeScene(
    'button_outlined',
    () {
      // An outlined button draws its outline at the **rim** and its container
      // in the **middle** — the same shape of check that caught the panel
      // shader drawing its border inside out, applied to the one variant whose
      // whole appearance is a border.
      //
      // The metrics are turned up on purpose. A Material outline is 1dp, which
      // at the default hundred logical pixels to the unit is 0.01 units and a
      // couple of pixels on screen: a probe disc cannot fit inside it, and
      // fattening the token would mean testing a number Material never
      // published. `unitsPerLogicalPixel: 0.06` keeps the *token* at its real
      // 1dp and makes the surface's unit contract the dial instead — which is
      // exactly the dial a camera-bound surface turns.
      //
      // The filled button beside it is the control, and it is what makes "the
      // middle is clear" evidence: an outlined button's container is
      // transparent, so its middle *should* show the background, and a scene
      // that only said so could equally be a scene where nothing drew.
      const theme = Theme3dData.light;
      DecoratedBox3d button(String name, ButtonVariant3d variant) {
        final style = ButtonStyle3d.of(theme, variant);
        final resolved = style.resolve(const {}, enabled: true);
        return DecoratedBox3d(
          decoration: Material3d.decorationFor(
            theme,
            color: resolved.container,
            shape: style.shape,
            elevation: resolved.elevation,
            thickness: style.thickness,
            border: resolved.border,
            surfaceTint: const Color(0x00000000),
          ),
          name: name,
        );
      }

      final outlined = button('outlined', ButtonVariant3d.outlined);
      final filled = button('filled', ButtonVariant3d.filled);
      return ProbeSceneContent(
        surfaces: [
          Layout3dSurface(
            // Six hundredths of a unit to the logical pixel, so Material's 40dp
            // button height is 2.4 units and its 1dp outline is 0.06 — a band a
            // probe disc fits inside.
            metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.06),
            constraints: Constraints3d.tight(const Size3d(8.4, 2.6, 0.2)),
            child: Row3d(
              mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
              children: <Layout3d>[
                for (final box in <Layout3d>[outlined, filled])
                  SizedBox3d(width: 3.84, height: 2.4, depth: 0.12, child: box),
              ],
            ),
          ),
        ],
        probes: {'outlined': outlined, 'filled': filled},
      );
    },
    camera: _wideCamera(),
    preload: installPanelPainter,
  ),

  // ── Surfaces and rows ────────────────────────────────────────────────
  //
  // Two claims from phase 4, and both are claims only a picture settles.
  ProbeScene('card_in_clipped_list', () {
    // **The clip contract's deliberate decision about depth, as a scene.**
    //
    // `Clip3dRegion.rect` is four planes and leaves the thickness alone, and
    // `flutter_scene_layout3d/lib/src/clip.dart` says why in as many words:
    // "a raised card inside a scrolling list should still stand proud of it".
    // Phase 4 is the first work that actually builds that, and until now
    // nobody had looked at what it draws.
    //
    // A window over a scrolled list of elevated cards, on a `primary` backing
    // the whole thing sits in front of. The first card is scrolled half out
    // of the top, so the frame has to show three things at once: the card
    // draws, it is cut at the window's edge in the plane, and the part that
    // is cut shows the backing rather than the card. If the clip had depth
    // planes in it, or if the shader ignored them, exactly one of those three
    // would be wrong.
    //
    // The **light** theme, for the reason every catalogue scene here uses it:
    // M3's dark surface is inside this harness's clear tolerance. The
    // direction asserted is a luminance — a near-white card against a mid
    // purple backing — which lighting and tone mapping can scale and cannot
    // reorder.
    const theme = Theme3dData.light;
    final style = CardStyle3d.of(theme, CardVariant3d.elevated);

    DecoratedBox3d card(String name) => DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: style.container,
        shape: style.shape,
        elevation: style.elevation,
        thickness: style.thickness,
        surfaceTint: const Color(0x00000000),
      ),
      name: name,
    );

    final cards = <DecoratedBox3d>[for (var i = 0; i < 5; i++) card('card$i')];
    final backing = DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: theme.colorScheme.primary,
        thickness: theme.thickness.structural,
      ),
      name: 'backing',
    );

    // 0.5 of row and 0.1 of gap: a 0.6 pitch, so a 1.2-unit window holds two
    // rows and a scroll of 0.25 leaves the first one half out of the top.
    final controller = Scroll3dController();
    final list = ListView3d(
      controller: controller,
      spacing: 0.1,
      children: <Layout3d>[
        for (final box in cards)
          SizedBox3d(width: 2.2, height: 0.5, depth: 0.04, child: box),
      ],
    );

    final surface = Layout3dSurface(
      constraints: Constraints3d.tight(const Size3d(3.0, 2.4, 0.4)),
      child: Stack3d(
        alignment: Alignment3d.center,
        // 12dp, the theme's own step. The deepest pair here is an 8dp backing
        // against a 4dp card, mean 6dp, so it clears with half again to
        // spare — which is `Thickness3d.separates` as a picture.
        depthStep: 0.12,
        children: <Layout3d>[
          SizedBox3d(width: 3.0, height: 2.4, depth: 0.08, child: backing),
          SizedBox3d(
            width: 2.2,
            height: 1.2,
            depth: 0.04,
            child: ClipBox3d(child: list),
          ),
        ],
      ),
    );
    // Lay out once so the viewport knows its extent, then scroll; the harness
    // flushes again when it adds the surface.
    surface.flush();
    controller.jumpTo(0.25);
    return ProbeSceneContent(
      surfaces: [surface],
      probes: {
        'backing': backing,
        for (var i = 0; i < cards.length; i++) 'card$i': cards[i],
      },
    );
  }, preload: installPanelPainter),

  ProbeScene(
    'divider_rule',
    () {
      // **A 1dp line, actually drawn.**
      //
      // Phase 3 met this wall with a button's 1dp outline and answered it the
      // right way round: at the default hundred logical pixels to the unit a
      // Material rule is 0.01 units and a couple of pixels on screen, and no
      // probe disc fits inside it. Fattening the token would mean testing a
      // number Material never published, so the *surface's*
      // `unitsPerLogicalPixel` is the dial instead — which is the dial a
      // camera-bound surface turns anyway.
      //
      // The rule sits on a card, which is what makes the assertion a
      // direction rather than a distance: `outlineVariant` is a mid grey and
      // `surfaceContainerLow` is near white, so the rule is *darker* than the
      // surface it divides, and a scene where the two were swapped fails.
      const theme = Theme3dData.light;
      final rule = DecoratedBox3d(
        decoration: Material3d.decorationFor(
          theme,
          color: theme.colorScheme.outlineVariant,
          thickness: theme.thickness.thin,
          bevel: 0.0,
        ),
        name: 'rule',
      );
      final card = DecoratedBox3d(
        decoration: Material3d.decorationFor(
          theme,
          color: CardStyle3d.of(theme, CardVariant3d.elevated).container,
          shape: theme.shape.medium,
          thickness: theme.thickness.raised,
          surfaceTint: const Color(0x00000000),
        ),
        name: 'card',
      );
      return ProbeSceneContent(
        surfaces: [
          Layout3dSurface(
            // Six hundredths of a unit to the logical pixel: a 1dp rule is
            // 0.06 units, a band a probe disc fits inside, and the token
            // stays at its published 1dp.
            metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.06),
            constraints: Constraints3d.tight(const Size3d(8.4, 4.0, 0.6)),
            child: Stack3d(
              alignment: Alignment3d.center,
              // 12dp at this rate. A 4dp card against a 1dp rule is a mean of
              // 2.5dp, so the rule stands clear of the card it is drawn on —
              // which is the whole reason a divider has a depth at all.
              depthStep: 0.72,
              children: <Layout3d>[
                SizedBox3d(width: 7.2, height: 3.2, depth: 0.24, child: card),
                SizedBox3d(width: 6.0, height: 0.06, depth: 0.06, child: rule),
              ],
            ),
          ),
        ],
        probes: {'card': card, 'rule': rule},
      );
    },
    camera: _wideCamera(),
    preload: installPanelPainter,
  ),

  // ── Structure ────────────────────────────────────────────────────────
  //
  // Phase 5's two claims, and both of them are about a depth buffer.
  ProbeScene('sliver_app_bar_clip', () {
    // **A row passing under a pinned bar is genuinely cut at the bar's
    // edge.**
    //
    // Two plans had said so and nothing had ever looked. The scene that
    // finally did found the plane tier dead in a second place: a viewport
    // fills in what a pinned header is sitting on *after* the rows have been
    // laid out and placed, so every row published the unbounded block and
    // `Layout3d.clipRegion` went on answering correctly to anything that
    // asked afterwards. See
    // `plans/2026_09_08_the_declarative_side_of_a_pinned_bar.md`.
    //
    // **The bar is narrower than the list, and that is the whole design of
    // this scene.** For a full-width opaque bar the clip is invisible — the
    // bar covers exactly what the clip would cut, which is precisely why the
    // defect survived. The clip is a single plane across the scroll axis, so
    // it cuts the *band*, cross-axis-wide, including the margin beside a
    // narrow bar. That is the contract `CustomScrollView3d.clipRegionForChild`
    // states, and it is what this scene photographs: beside the bar, above
    // its trailing edge, the frame shows the backing rather than the row.
    const theme = Theme3dData.light;
    final cardStyle = CardStyle3d.of(theme, CardVariant3d.elevated);

    DecoratedBox3d panel(
      Color color,
      double thickness,
      String name, {
      BorderRadius3d? shape,
    }) => DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: color,
        shape: shape,
        thickness: thickness,
        surfaceTint: const Color(0x00000000),
      ),
      name: name,
    );

    final rows = <DecoratedBox3d>[
      for (var i = 0; i < 5; i++)
        panel(
          cardStyle.container,
          theme.thickness.raised,
          'row$i',
          shape: theme.shape.medium,
        ),
    ];
    final backing = panel(
      theme.colorScheme.primary,
      theme.thickness.structural,
      'backing',
    );
    final bar = panel(
      theme.colorScheme.secondary,
      theme.thickness.structural,
      'bar',
    );

    final controller = Scroll3dController();
    final header = SliverPersistentHeader3d(
      delegate: _BarHeader3dDelegate(
        // Centred and half the viewport's width, so there is a margin either
        // side where the row would still be visible if nothing cut it.
        Align3d(
          alignment: Alignment3d.frontCenter,
          child: SizedBox3d(width: 1.0, height: 0.4, depth: 0.08, child: bar),
        ),
        extent: 0.4,
      ),
      pinned: true,
      // The theme's own step, not the layout package's one logical pixel: an
      // 8dp bar over a 4dp card needs more than the 6dp mean of the two.
      lift: theme.thickness.depthStep * 0.01,
    );
    final list = SliverList3d(
      spacing: 0.1,
      children: <Layout3d>[
        for (final row in rows)
          SizedBox3d(width: 2.0, height: 0.4, depth: 0.04, child: row),
      ],
    );
    final view = CustomScrollView3d(
      controller: controller,
      slivers: <Sliver3d>[header, list],
    );

    final surface = Layout3dSurface(
      constraints: Constraints3d.tight(const Size3d(3.0, 2.4, 0.5)),
      child: Stack3d(
        alignment: Alignment3d.center,
        depthStep: 0.12,
        children: <Layout3d>[
          SizedBox3d(width: 3.0, height: 2.4, depth: 0.08, child: backing),
          SizedBox3d(width: 2.0, height: 1.6, depth: 0.04, child: view),
        ],
      ),
    );
    // Lay out once so the viewport knows its extent, then scroll. 0.65 puts
    // the bar at its full 0.4, row0 entirely under it, and row1 straddling
    // its trailing edge.
    surface.flush();
    controller.jumpTo(0.65);
    return ProbeSceneContent(
      surfaces: [surface],
      probes: {
        'backing': backing,
        'bar': bar,
        for (var i = 0; i < rows.length; i++) 'row$i': rows[i],
      },
    );
  }, preload: installPanelPainter),

  ProbeScene('scaffold_bar_depth', () {
    // **A bar is drawn in front of the row sliding beneath it.**
    //
    // The other half of the same question, and the one `Scaffold3d` encodes:
    // every slot sits one `thickness.depthStep` in front of the one behind
    // it, in the order `Scaffold3dSlot` declares. Without that a
    // `Thickness3d.structural` bar and a `Thickness3d.raised` card are only
    // separated where the step exceeds the mean of the two — 6dp — and a bar
    // resting on the same plane as its content loses the depth test to it in
    // patches, differently on every frame and every driver.
    //
    // The direction asserted is a luminance, which lighting and tone mapping
    // can scale and cannot reorder: the bar is `primary`, a dark purple, and
    // the card under it is `surfaceContainerLow`, near white. Where the bar
    // covers the card the frame must read *dark*. A scene with the two depths
    // swapped reads light there and fails.
    const theme = Theme3dData.light;
    final cardStyle = CardStyle3d.of(theme, CardVariant3d.elevated);

    DecoratedBox3d panel(Color color, double thickness, String name) =>
        DecoratedBox3d(
          decoration: Material3d.decorationFor(
            theme,
            color: color,
            thickness: thickness,
            surfaceTint: const Color(0x00000000),
          ),
          name: name,
        );

    final backing = panel(
      theme.colorScheme.surfaceContainerHighest,
      theme.thickness.thin,
      'backing',
    );
    final card = panel(cardStyle.container, theme.thickness.raised, 'card');
    final bar = panel(
      theme.colorScheme.primary,
      theme.thickness.structural,
      'bar',
    );

    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.0, 2.4, 0.6)),
          child: Stack3d(
            alignment: Alignment3d.topCenter,
            // `Thickness3d.depthStep`, in world units at the default rate —
            // the same number `Scaffold3d` puts between two slots.
            depthStep: 0.12,
            children: <Layout3d>[
              SizedBox3d(width: 3.0, height: 2.4, depth: 0.01, child: backing),
              // The body, one step in front of the backing.
              SizedBox3d(width: 2.0, height: 1.6, depth: 0.04, child: card),
              // The bar, a further step in front, and wider than the card so
              // that a probe can read the bar alone as well as the overlap.
              SizedBox3d(width: 2.8, height: 0.64, depth: 0.08, child: bar),
            ],
          ),
        ),
      ],
      probes: {'backing': backing, 'card': card, 'bar': bar},
    );
  }, preload: installPanelPainter),

  // ── The overlays ─────────────────────────────────────────────────────
  //
  // Phase 6's two claims. The first is the one the catalogue plan named
  // itself, and it is about a depth buffer as much as about a colour.
  ProbeScene('dialog_over_scrim', () {
    // **A dialog occludes the scrim behind it rather than fighting it.**
    //
    // Material's scrim is black at 32% over the content. Here it is
    // *geometry* — a slab in front of the screen and behind the dialog — so
    // every depth rule applies to it, and two things have to be true at once
    // that no headless test can see: the scrim actually darkens what it
    // covers, and the dialog drawn over it reads as a dialog everywhere
    // rather than in patches.
    //
    // The scene is built so both claims are **comparisons**. Phase 2 found
    // that a dark surface can fall inside this harness's clear tolerance, and
    // a scrim is the darkest thing in the catalogue: asking "is this pixel
    // dark" would be asking the harness a question it cannot answer. So the
    // scrim is deliberately **narrower than the backing**, exactly as
    // `sliver_app_bar_clip`'s bar is narrower than its rows, and the
    // assertion is scrimmed-against-unscrimmed rather than scrimmed-against-a
    // -threshold. A full-bleed scrim would photograph a working picture over
    // a scrim that never drew.
    //
    // The light theme, like every catalogue scene here.
    const theme = Theme3dData.light;
    final style = DialogStyle3d.of(theme);

    final backing = DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: theme.colorScheme.primary,
        thickness: theme.thickness.structural,
        surfaceTint: const Color(0x00000000),
      ),
      name: 'backing',
    );
    final scrim = DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: style.scrimColor,
        thickness: style.scrimThickness,
        surfaceTint: const Color(0x00000000),
      ),
      name: 'scrim',
    );
    final dialog = DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: style.container,
        shape: style.shape,
        elevation: style.elevation,
        thickness: style.thickness,
        surfaceTint: const Color(0x00000000),
      ),
      name: 'dialog',
    );

    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.0, 2.4, 0.6)),
          child: Stack3d(
            alignment: Alignment3d.center,
            // `Thickness3d.depthStep`, in world units at the default rate.
            // A 1dp scrim over an 8dp backing is a mean of 4.5dp and a 4dp
            // dialog over the scrim is 2.5dp, so one step clears both several
            // times over — which is what keeps the dialog from fighting the
            // slab it is carried on.
            depthStep: 0.12,
            children: <Layout3d>[
              SizedBox3d(width: 3.0, height: 2.4, depth: 0.08, child: backing),
              // Narrower than the backing on purpose: the strip either side is
              // where an unscrimmed reading comes from.
              SizedBox3d(width: 2.2, height: 2.4, depth: 0.01, child: scrim),
              SizedBox3d(width: 1.4, height: 0.9, depth: 0.04, child: dialog),
            ],
          ),
        ),
      ],
      probes: {'backing': backing, 'scrim': scrim, 'dialog': dialog},
    );
  }, preload: installPanelPainter),

  ProbeScene('menu_at_its_button', () {
    // **An anchored menu is drawn at its button, and not where layout put
    // it.**
    //
    // The anchoring is a `nodeOffset` — the node tier, one matrix, no
    // relayout — and that is precisely why a headless test cannot finish the
    // job. `Layout3d.worldTransform` *undoes* `nodeOffset` by design, so
    // `screenPointOf` on the menu reports where layout put it rather than
    // where it is drawn: the projection and the picture genuinely disagree
    // here, and only the picture is the truth.
    //
    // So the oracle is the **button**. The scene asks what is drawn a button's
    // height below the button, where an anchored menu is and an unanchored
    // one — centred by the overlay's own alignment — is not.
    const theme = Theme3dData.light;
    final menuStyle = MenuStyle3d.of(theme);

    final backing = DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: theme.colorScheme.primary,
        thickness: theme.thickness.structural,
        surfaceTint: const Color(0x00000000),
      ),
      name: 'backing',
    );
    final button = DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: theme.colorScheme.secondaryContainer,
        shape: theme.shape.full,
        thickness: theme.thickness.standard,
        surfaceTint: const Color(0x00000000),
      ),
      name: 'button',
    );
    final menu = DecoratedBox3d(
      decoration: Material3d.decorationFor(
        theme,
        color: menuStyle.container,
        shape: menuStyle.shape,
        elevation: menuStyle.elevation,
        thickness: menuStyle.thickness,
        surfaceTint: const Color(0x00000000),
      ),
      name: 'menu',
    );

    final anchor = Anchor3d()
      ..child = SizedBox3d(width: 0.5, height: 0.3, depth: 0.02, child: button);
    final follower = Follower3d(anchor: anchor)
      ..child = SizedBox3d(width: 1.0, height: 0.8, depth: 0.04, child: menu);

    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.tight(const Size3d(3.0, 2.4, 0.6)),
          child: Stack3d(
            alignment: Alignment3d.center,
            depthStep: 0.12,
            children: <Layout3d>[
              SizedBox3d(width: 3.0, height: 2.4, depth: 0.08, child: backing),
              // The button in the top-left corner, which is as far from the
              // stack's own centre as this surface allows.
              Positioned3d(left: 0.2, top: 0.2, child: anchor),
              // The menu, which the stack would centre and the follower moves
              // onto the button's bottom-left corner.
              follower,
            ],
          ),
        ),
      ],
      probes: {'backing': backing, 'button': anchor, 'menu': follower},
    );
  }, preload: installPanelPainter),

  // ── The selection controls ───────────────────────────────────────────
  //
  // Phase 7's three claims, and each of them is about something a headless
  // test cannot reach: a glyph small enough that its raster is in question, a
  // slab moved on the node tier, and a track whose fill is a scale rather
  // than a size.
  //
  // All three raise the *surface's* `unitsPerLogicalPixel` rather than
  // fattening a token, which is the dial `divider_rule` and `button_outlined`
  // both reach for. It is worth knowing exactly what that does to a glyph,
  // because it is not what it looks like: the atlas rasterizes at
  // `unitsPerLogicalPixel * logicalPixelsPerUnit * resolution`, and the first
  // two cancel — so the raster scale is `AtlasText3dRenderer.resolution` and
  // **nothing else**, whatever the surface's unit rate is. Turning the rate
  // up magnifies the quad and leaves the rasterization alone. These scenes
  // are therefore a magnifying glass held over the real 18dp raster rather
  // than a bigger checkbox.
  ProbeScene(
    'checkbox_mark',
    () {
      // **An 18dp checkmark actually rasterizes, and it is the mark that is
      // the signal.**
      //
      // Phase 4 declined to draw a checkmark on a filter chip, because the
      // container substitution already said "selected". A checkbox runs the
      // other way: the substitution is an 18dp square turning `primary`,
      // which without a mark is indistinguishable from a filled swatch. So
      // the glyph has to draw — and at 18dp it is the smallest thing this
      // catalogue has ever asked the label atlas for. `icon_glyph` settled
      // the question for a 220dp heart; this settles it at the size a real
      // control uses.
      //
      // Three boxes, and the middle pair is the whole experiment: two
      // identical `primary` boxes, one with a rendered mark and one whose
      // glyph has **no renderer at all**. That makes the assertion a
      // comparison between two boxes that differ in exactly one thing,
      // exactly as `icon_glyph` and its control do — and the direction is
      // `onPrimary` over `primary`, which on the light theme means the
      // marked box is *lighter* in the middle.
      const theme = Theme3dData.light;
      final style = CheckboxStyle3d.of(theme);
      const rate = 0.06;
      final extent = style.size * rate;
      final depth = style.thickness * rate;

      DecoratedBox3d filled(String name) => DecoratedBox3d(
        decoration: Material3d.decorationFor(
          theme,
          color: style.selectedContainer,
          shape: style.shape,
          thickness: style.thickness,
          surfaceTint: const Color(0x00000000),
        ),
        name: name,
      );
      Text3d glyph({required bool drawn}) => Text3d(
        String.fromCharCode(Checkbox3d.defaultIcon.codePoint),
        style: TextStyle(
          fontFamily: Checkbox3d.defaultIcon.fontFamily,
          fontSize: style.markSize,
          color: style.mark,
          height: 1.0,
        ),
        renderer: drawn ? AtlasText3dRenderer() : null,
      );

      final empty = DecoratedBox3d(
        decoration: Material3d.decorationFor(
          theme,
          color: style.container,
          shape: style.shape,
          thickness: style.thickness,
          border: Border3d(width: style.outlineWidth, color: style.outline),
          surfaceTint: const Color(0x00000000),
        ),
        name: 'empty',
      );
      final marked = filled('marked');
      final unmarked = filled('unmarked');
      final card = DecoratedBox3d(
        decoration: Material3d.decorationFor(
          theme,
          color: theme.colorScheme.surfaceContainerLow,
          shape: theme.shape.medium,
          thickness: theme.thickness.raised,
          surfaceTint: const Color(0x00000000),
        ),
        name: 'card',
      );

      Layout3d cell(DecoratedBox3d panel, Text3d? mark) => SizedBox3d(
        width: extent,
        height: extent,
        child: Stack3d(
          alignment: Alignment3d.center,
          // `Thickness3d.stepOver(thin, thin)` is 2dp, at this rate 0.12.
          depthStep: style.depthStep * rate,
          children: <Layout3d>[
            SizedBox3d(
              width: extent,
              height: extent,
              depth: depth,
              child: panel,
            ),
            if (mark != null) mark,
          ],
        ),
      );

      return ProbeSceneContent(
        surfaces: [
          Layout3dSurface(
            metrics: const Layout3dMetrics(unitsPerLogicalPixel: rate),
            constraints: Constraints3d.tight(const Size3d(6.0, 3.0, 0.6)),
            child: Stack3d(
              alignment: Alignment3d.center,
              depthStep: 0.36,
              children: <Layout3d>[
                SizedBox3d(width: 5.4, height: 2.4, depth: 0.24, child: card),
                Row3d(
                  mainAxisAlignment: MainAxisAlignment3d.center,
                  crossAxisAlignment: CrossAxisAlignment3d.center,
                  spacing: 0.6,
                  children: <Layout3d>[
                    cell(empty, null),
                    cell(marked, glyph(drawn: true)),
                    cell(unmarked, glyph(drawn: false)),
                  ],
                ),
              ],
            ),
          ),
        ],
        probes: {
          'card': card,
          'empty': empty,
          'marked': marked,
          'unmarked': unmarked,
        },
      );
    },
    camera: _wideCamera(),
    preload: installPanelPainter,
  ),

  ProbeScene(
    'switch_thumb',
    () {
      // **A switch's thumb is drawn where the switch is set, and it wins the
      // depth test against the track it sits on.**
      //
      // Two claims a headless test cannot make, and the first one for a
      // reason phase 6 wrote down: the slide is a `nodeOffset`, and
      // `worldTransform` **undoes** `nodeOffset` by design — so
      // `screenCenter` on the thumb reports the middle of the track whichever
      // way the switch is set. The projection and the picture genuinely
      // disagree, and only the picture is the truth.
      //
      // So the oracle is the **track**, exactly as `menu_at_its_button`'s is
      // the button. The scene asks what colour is drawn at two fifths across
      // each track, and the answer has to flip between the two switches.
      //
      // Both directions are asserted, and they have opposite signs, which is
      // what makes the pair evidence rather than a coincidence. On: the track
      // is `primary` (a mid purple) and the thumb `onPrimary` (near white),
      // so the thumb end is *lighter*. Off: the track is
      // `surfaceContainerHighest` (near white) and the thumb `outline` (a mid
      // grey), so the thumb end is *darker*.
      const theme = Theme3dData.light;
      final style = SwitchStyle3d.of(theme);
      const rate = 0.06;

      Layout3d aSwitch({
        required bool value,
        required String trackName,
        required String thumbName,
      }) {
        final resolved = style.resolve(
          const {},
          selected: value,
          enabled: true,
        );
        final track = DecoratedBox3d(
          decoration: Material3d.decorationFor(
            theme,
            color: resolved.track,
            shape: style.trackShape,
            thickness: style.trackThickness,
            border: resolved.border,
            surfaceTint: const Color(0x00000000),
          ),
          name: trackName,
        );
        final thumb = DecoratedBox3d(
          decoration: Material3d.decorationFor(
            theme,
            color: resolved.thumb,
            shape: theme.shape.full,
            thickness: style.thumbThickness,
            surfaceTint: const Color(0x00000000),
          ),
          name: thumbName,
        );
        _switchProbes[trackName] = track;
        _switchProbes[thumbName] = thumb;
        return SizedBox3d(
          width: style.trackWidth * rate,
          height: style.trackHeight * rate,
          child: Stack3d(
            alignment: Alignment3d.center,
            depthStep: style.depthStep * rate,
            children: <Layout3d>[
              SizedBox3d(
                width: style.trackWidth * rate,
                height: style.trackHeight * rate,
                depth: style.trackThickness * rate,
                child: track,
              ),
              // The node tier: layout centres the thumb and this carries it
              // half the travel. No box changes size, which is the whole
              // reason a switch may one day animate for free.
              NodeShift3d(
                  shift: Offset3d(
                    style.travel * rate / 2.0 * (value ? 1.0 : -1.0),
                    0.0,
                    0.0,
                  ),
                )
                ..child = SizedBox3d(
                  width: style.thumbSize * rate,
                  height: style.thumbSize * rate,
                  depth: style.thumbThickness * rate,
                  child: thumb,
                ),
            ],
          ),
        );
      }

      _switchProbes.clear();
      final on = aSwitch(
        value: true,
        trackName: 'onTrack',
        thumbName: 'onThumb',
      );
      final off = aSwitch(
        value: false,
        trackName: 'offTrack',
        thumbName: 'offThumb',
      );

      return ProbeSceneContent(
        surfaces: [
          Layout3dSurface(
            metrics: const Layout3dMetrics(unitsPerLogicalPixel: rate),
            // Tall enough for two 32dp tracks and the gap between them: at
            // this rate that is 1.92 each, and a surface's constraints are
            // tight, so a column that does not fit overflows rather than
            // growing.
            constraints: Constraints3d.tight(const Size3d(8.0, 5.4, 0.6)),
            child: Column3d(
              mainAxisAlignment: MainAxisAlignment3d.center,
              crossAxisAlignment: CrossAxisAlignment3d.center,
              spacing: 0.9,
              children: <Layout3d>[on, off],
            ),
          ),
        ],
        probes: Map<String, Layout3d>.of(_switchProbes),
      );
    },
    camera: _wideCamera(),
    preload: installPanelPainter,
  ),

  ProbeScene(
    'slider_drag',
    () {
      // **A slider's thumb tracks a finger, and the active track stops where
      // the thumb is.**
      //
      // The scene is mid-interaction, like `drag_feedback_depth`: it builds
      // the boxes, flushes, and drives a real `Layout3dPointer` across the
      // track inside `build()`, so the harness receives a static frame that
      // happens to have a live drag in it. What the pointer drives is the
      // component's own `SliderGesture3d` — the arena member the drag plan
      // named "a knob, a slider, a rotation handle" for — so the scene is a
      // picture of the real gesture rather than of a value set by hand.
      //
      // The second claim is the one that could not have been made any other
      // way. The active track is **not** a box that grows: it is the whole
      // track, scaled on its own node about its origin corner, which is why
      // a drag lays nothing out. Whether that scale lands where the thumb is
      // is a question about a matrix and a picture, and this is the picture.
      //
      // The oracle is the **body**, the 48dp box that does not move — the
      // thumb's own `screenCenter` reports the middle of the track whatever
      // the value is, for the reason `switch_thumb` explains.
      const theme = Theme3dData.light;
      final style = SliderStyle3d.of(theme);
      const rate = 0.06;
      const width = SliderStyle3d.defaultMinimumTrackWidth;
      final travel = (width - style.thumbSize) * rate;

      DecoratedBox3d track(Color color, String name) => DecoratedBox3d(
        decoration: Material3d.decorationFor(
          theme,
          color: color,
          shape: style.trackShape,
          thickness: style.trackThickness,
          surfaceTint: const Color(0x00000000),
        ),
        name: name,
      );

      final inactive = track(style.inactiveTrack, 'inactive');
      final active = track(style.activeTrack, 'active');
      final thumb = DecoratedBox3d(
        decoration: Material3d.decorationFor(
          theme,
          color: style.thumb,
          shape: theme.shape.full,
          thickness: style.thumbThickness,
          surfaceTint: const Color(0x00000000),
        ),
        name: 'thumb',
      );
      final card = DecoratedBox3d(
        decoration: Material3d.decorationFor(
          theme,
          color: theme.colorScheme.surfaceContainerLow,
          shape: theme.shape.medium,
          thickness: theme.thickness.raised,
          surfaceTint: const Color(0x00000000),
        ),
        name: 'card',
      );

      final fill = NodeShift3d(scaleX: 0.0)
        ..child = SizedBox3d(
          width: travel,
          height: style.trackHeight * rate,
          depth: style.trackThickness * rate,
          child: active,
        );
      final rider = NodeShift3d(shift: Offset3d(-travel / 2.0, 0.0, 0.0))
        ..child = SizedBox3d(
          width: style.thumbSize * rate,
          height: style.thumbSize * rate,
          depth: style.thumbThickness * rate,
          child: thumb,
        );

      final body = SizedBox3d(
        width: width * rate,
        height: style.stateLayerSize * rate,
        name: 'body',
      );
      final gesture = SliderGesture3d(padding: style.thumbSize / 2.0 * rate)
        ..onChanged = (value) {
          fill.scaleX = value;
          rider.shift = Offset3d(travel * (value - 0.5), 0.0, 0.0);
        };
      gesture.child = Stack3d(
        alignment: Alignment3d.center,
        depthStep: style.depthStep * rate,
        children: <Layout3d>[
          body,
          SizedBox3d(
            width: travel,
            height: style.trackHeight * rate,
            depth: style.trackThickness * rate,
            child: inactive,
          ),
          fill,
          rider,
        ],
      );

      final surface = Layout3dSurface(
        metrics: const Layout3dMetrics(unitsPerLogicalPixel: rate),
        constraints: Constraints3d.tight(const Size3d(10.0, 4.0, 0.6)),
        child: Stack3d(
          alignment: Alignment3d.center,
          depthStep: 0.36,
          children: <Layout3d>[
            SizedBox3d(width: 9.4, height: 3.0, depth: 0.24, child: card),
            gesture,
          ],
        ),
      );
      surface.flush();

      // A press at the track's left end and a drag three quarters of the way
      // across it. The first move is under the touch slop on purpose — a
      // slider that claimed the pointer before the finger committed would be
      // the bug the arena exists to prevent — and the second commits.
      final origin = Offset3d(
        (10.0 - width * rate) / 2.0 + style.thumbSize / 2.0 * rate,
        2.0,
        0.0,
      );
      final pointer = Layout3dPointer(surface);
      pointer.down(_rayAt(surface, origin));
      pointer.move(_rayAt(surface, origin + const Offset3d(0.05, 0, 0)));
      pointer.move(_rayAt(surface, origin + Offset3d(travel * 0.75, 0, 0)));

      return ProbeSceneContent(
        surfaces: [surface],
        probes: {
          'card': card,
          'body': body,
          'inactive': inactive,
          'active': active,
          'thumb': thumb,
        },
      );
    },
    camera: _wideCamera(),
    preload: installPanelPainter,
  ),

  // ── The icon question ────────────────────────────────────────────────
  //
  // The catalogue plan guesses that an icon is a one-glyph `Text3d` in the
  // MaterialIcons font, drawn through the same atlas as every label — which
  // would make `Icon3d` thirty lines and batch it with the labels for free.
  // Nothing but a drawn frame can answer that: `Text3d` measures an unknown
  // glyph perfectly happily and draws a blank, and the atlas rasterizes
  // through Flutter's own text engine, which resolves the family or silently
  // falls back. So the scene draws one, and its control draws the same glyph
  // with no renderer at all.
  ProbeScene('icon_glyph', () {
    final icon = Text3d(
      String.fromCharCode(Icons.favorite.codePoint),
      style: _iconStyle,
      renderer: AtlasText3dRenderer(),
      name: 'icon',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.loose(const Size3d(6.0, 1.8, 0.2)),
          child: Center3d(child: icon),
        ),
      ],
      probes: {'icon': icon},
    );
  }, minCoverage: 0.01),

  ProbeScene('icon_glyph_undrawn', () {
    final icon = Text3d(
      String.fromCharCode(Icons.favorite.codePoint),
      style: _iconStyle,
      name: 'icon',
    );
    return ProbeSceneContent(
      surfaces: [
        Layout3dSurface(
          constraints: Constraints3d.loose(const Size3d(6.0, 1.8, 0.2)),
          child: Center3d(child: icon),
        ),
      ],
      probes: {'icon': icon},
    );
  }, minCoverage: 0),
];

/// A persistent header over one subtree, for the scenes that need a pinned
/// bar without a widget tree to build one from.
///
/// The imperative twin of `HeldSliverPersistentHeader3dDelegate`: it hands
/// back the same instance every time, which is the shape
/// `SliverPersistentHeader3dDelegate`'s own doc asks for — a delegate that
/// built a fresh subtree would be building and disposing geometry at frame
/// rate.
class _BarHeader3dDelegate extends SliverPersistentHeader3dDelegate {
  const _BarHeader3dDelegate(this.content, {required this.extent});

  final Layout3d content;
  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Layout3d build(double shrinkOffset, {required bool overlapsContent}) =>
      content;

  @override
  bool shouldRebuild(_BarHeader3dDelegate oldDelegate) =>
      !identical(oldDelegate.content, content);
}
