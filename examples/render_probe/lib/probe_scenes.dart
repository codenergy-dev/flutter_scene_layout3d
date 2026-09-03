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
