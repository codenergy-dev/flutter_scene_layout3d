# flutter_scene_layout3d

**Flutter's layout protocol, in a 3D scene.**

You already know how to lay out a Flutter UI: constraints go down, sizes come
up, and the parent decides where the child sits. This project takes those
rules — the actual rules, not an approximation of them — and spends them on
real geometry in a [flutter_scene](https://pub.dev/packages/flutter_scene)
scene.

A `Column3d` is a `Column`. It measures its children, distributes the free
space, and positions them. The difference is that a box has three extents
instead of two, a position is a point in space, and the output of layout is a
tree of scene `Node` transforms rather than a display list.

![Constraints go down, sizes come up, the parent positions the child — and the result is geometry on a plane](docs/protocol.svg)

> **Status: experimental.** The API moves between releases. The package draws
> nothing until an application installs a painter and a text renderer, both of
> which now ship in the box — see
> [What this does not do](#what-this-does-not-do-yet) before you plan around it.

## Installing

Neither package is on pub.dev yet, so depend on them from git. Take the
layout package on its own if you are arranging your own geometry, and add the
Material one if you want the component catalogue:

```yaml
dependencies:
  flutter_scene: ^0.23.0
  flutter_scene_layout3d:
    git:
      url: https://github.com/codenergy-dev/flutter_scene_layout3d.git
      path: packages/flutter_scene_layout3d
  flutter_scene_material3d:
    git:
      url: https://github.com/codenergy-dev/flutter_scene_layout3d.git
      path: packages/flutter_scene_material3d
```

Two things to know before the first run. **The app has to be launched with
`--enable-flutter-gpu`** — the engine draws through Flutter GPU and without
the flag nothing renders at all. And **the panel shader compiles itself**: the
layout package carries a build hook that runs `impellerc` over its own
`.fmat`, so there is nothing about panels to add to your app's build hook, and
usually no build hook to write at all.

Flutter 3.29 or newer. Everything here is developed and verified on macOS,
which is where the render probes run; the packages declare the platforms
`flutter_scene` supports, and this project has not tested the others.

## A screen, start to finish

This is a whole application. It draws a Material screen — an app bar and a
button — on a panel standing in a 3D scene, and the button can be pressed.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Awaits the engine's static resources, then installs the panel painter.
  // Nothing in the catalogue draws until this resolves.
  await initializeMaterial3d();
  runApp(const MaterialApp(home: Scaffold(body: FirstScreen())));
}

class FirstScreen extends StatefulWidget {
  const FirstScreen({super.key});

  @override
  State<FirstScreen> createState() => _FirstScreenState();
}

class _FirstScreenState extends State<FirstScreen> {
  final Scene scene = Scene();

  final PerspectiveCamera camera = PerspectiveCamera(
    position: Vector3(0, 0, 6),
    target: Vector3.zero(),
  );

  @override
  Widget build(BuildContext context) => SceneView(
    scene,
    camera: camera,
    children: [
      SceneLayout3d(
        size: const Size3d(3.5, 2.4, 0.6),
        child: SceneTheme3d(
          data: Theme3dData.dark,
          textRendererFactory: AtlasText3dRenderer.new,
          child: Scaffold3d(
            appBar: const AppBar3d(title: SceneText3d('Inbox')),
            body: SceneCenter3d(
              child: FilledButton3d(
                onPressed: () => debugPrint('pressed'),
                child: const SceneText3d('Continue'),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
```

Three lines in there are the whole setup. `initializeMaterial3d()` installs
the painter; `SceneLayout3d` is the surface, a plane in the scene that a
layout tree hangs below; and `SceneTheme3d` publishes the tokens and says
which renderer draws a label. Everything under it is ordinary Flutter: a
`Scaffold3d` with an app bar and a body, rebuilt with `setState` like any
other widget.

That example is compiled by this repository's own test suite, along with every
other worked example in these files, so it cannot rot quietly.

## Why

Building a panel in a 3D scene usually means one of two bad options. Either you
render a Flutter widget tree to a texture and paste it onto a quad — flat,
blurry when you get close, and unable to have anything stand out of it — or you
place every element by hand with hard-coded coordinates, and then do it again
the moment a label gets longer.

Neither is layout. Layout is the thing that lets a button be as wide as its
text, a row share space between three cards, and a list scroll a thousand items
without you computing a single offset. That machinery is very good, very well
understood, and there is no reason it has to stop being useful the moment the
surface it arranges is a plane in a scene rather than a rectangle on a screen.

So this is the machinery, ported faithfully, arranging cubes and meshes and
glTF models instead of paint operations.

## A first surface

Everything hangs off a `Layout3dSurface`. Give it constraints and a child tree,
add its `plane` to the scene, and flush:

```dart
final surface = Layout3dSurface(
  constraints: Constraints3d.tight(const Size3d(4, 3, 0.5)),
  child: Column3d(
    mainAxisAlignment: MainAxisAlignment3d.center,
    spacing: 0.2,
    children: [
      NodeBox3d(content: Node(mesh: Mesh(cubeGeometry, material))),
      NodeBox3d(content: await loadScene('assets/lamp.glb')),
    ],
  ),
);

scene.root.add(surface.plane);
surface.flush();
```

`NodeBox3d` is the bridge: it takes any scene `Node`, measures its actual
bounds, and hands that size up the tree like any other box. A model that is
0.8 units wide participates in a `Row3d` exactly the way a `Text` participates
in a `Row`.

Because everything laid out hangs below one node, moving that node carries the
whole arrangement:

```dart
surface.plane.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), 0.4);
```

The layout does not re-run. It does not need to — the arrangement is already
correct in its own space, and the plane is what puts that space in the world.

## Down is wherever you point it

A layout does its arithmetic in **layout space**: `x` right, `y` down, `z` away
from the viewer. The *basis* is what maps that onto the scene, and it is the
one genuinely 3D idea you have to hold.

![The same layout tree on an upright plane and on the ground plane](docs/basis.svg)

```dart
Layout3dSurface(basis: LayoutBasis3d.xy, ...);  // a panel facing the viewer
Layout3dSurface(basis: LayoutBasis3d.xz, ...);  // the same tree, on the ground
```

The arithmetic is identical. A `Column3d` still stacks along layout's `y`. What
changes is where `y` points: on the ground plane, "down the column" walks
toward the viewer, so the same code that builds a menu builds a row of tiles
laid out on a table. This is why the protocol was worth porting rather than
reinventing — the hard part was always the measuring and the space
distribution, and none of that cares which way is down.

## What a logical pixel is worth

Material says a touch target is 48dp and body text is 14sp. In a scene, those
numbers mean nothing until something says how many world units a logical pixel
is. Guessing a constant works until the camera moves.

Bind a surface to the camera and the number stops being a guess — it is
*derived* from the frustum at the distance the surface sits:

![A camera-bound surface derives the dp-to-world-unit rate from the frustum](docs/units.svg)

```dart
SceneLayout3d(
  camera: camera,
  binding: const Layout3dCameraBinding.screenFilling(distance: 6),
  child: ...,
);
```

From then on `metrics.dp(48)` and `metrics.sp(14)` are honest, and every box
reads them the same way — inside `performLayout`, with no `BuildContext`
needed, so the imperative layer has them too:

```dart
@override
void performLayout() {
  final minimum = metrics.dp(48);   // 48 logical pixels, in world units
  ...
}
```

A `build` method reads the same contract through the surface, which publishes
it as `Layout3dMetricsScope.of(context)` — so a component states its padding
and its size the way its specification does, in logical pixels, and converts
them once.

Writing metrics relayouts the whole subtree, deliberately. It belongs to a
window resize, never to a per-frame path.

## The declarative layer

There is a widget layer over all of it, so a surface can be described the way
you describe a Flutter screen, rebuilt with `setState`, and scrolled with a
controller:

```dart
SceneLayout3d(
  camera: camera,
  child: SceneListView3d.builder(
    itemCount: products.length,
    itemBuilder: (context, i) => SceneSizedBox3d(
      height: 0.6,
      child: SceneNodeBox3d(content: products[i].model),
    ),
  ),
)
```

Items are built on demand, exactly as `ListView.builder` does it: only what is
in the window and its cache extent exists, and scrolling flings with real
physics.

## What is in the box

The protocol is essentially complete. Constraints, intrinsics and baselines;
`Row3d`, `Column3d`, `Stack3d`, `Wrap3d`, `Table3d`, `Flow3d`,
`CustomMultiChildLayout3d` and `LayoutBuilder3d`; the full sliver protocol with
`CustomScrollView3d`, lazy lists and grids, and persistent headers that pin and
float; text measurement that matches Skia's line breaking exactly; decoration
with corners, borders, elevation, state layers and press ripples; plane
clipping; ray-based
hit testing with real gesture recognition, hover and focus traversal; overlays,
modal barriers and a route stack; tweens, implicit animation and scroll
physics; and a diagnostics layer with tree dumps, overflow reporting and debug
wireframes.

The [package README](packages/flutter_scene_layout3d/README.md) is the deep
reference for all of it — it goes box by box, and it is honest about where this
differs from Flutter and why. [docs/](docs/) maps everything else, and
[docs/traps.md](docs/traps.md) is the list of sharp edges worth reading before
you build a component.

## What this does not do yet

**It arranges, and it draws only what you ask it to.** Two seams stand between
a laid-out tree and a picture: `BoxDecoration3d.painterFactory` is null until
something sets it, and a `Text3d` takes a renderer and has none by default.
That is deliberate — a package cannot install either without loading a
compiled shader before it knows there is a GPU — and both now have an
implementation shipped behind them, `BoxDecoration3dPainter` over the panel
shader and `AtlasText3dRenderer` over a shared glyph atlas, with `RichText3d`
beside it for what an atlas cannot assemble. `initializeMaterial3d()` installs
them; two lines install them by hand. What stays yours is a painter or a
renderer of your *own*, which is what having a seam there is for.

Open, each for a stated reason rather than for lack of time:

- **Text input.** There is no editing layer anywhere in this stack — no
  cursor, no selection, no keyboard plumbing — so there is no `TextField3d`,
  and it is not planned.
- **Subtree opacity.** `flutter_scene` has no per-node opacity for a fade to
  multiply into, so a subtree cannot be faded as a whole. Disabled states are
  expressed as colours instead, which is what Material's specification asks
  for anyway.
- **Shadows for decorated panels.** The engine drops non-opaque materials
  before the shadow pass, and the panel shader blends its own anti-aliased
  outline. An elevation is a real height here rather than a painted shadow, so
  this costs less than it sounds, but it is a difference.
- **Keep-alive** for lazily built children, so a stateful item rebuilds when
  it scrolls back into view.

`docs/traps.md` is the rest of the honesty: the sharp edges that cost real
time, written down as they were found.

## Material, built as geometry

The reason the package exists is **`flutter_scene_material3d`**: a Material
catalogue — `Button3d`, `Card3d`, `Icon3d`, `ListTile3d`, `Scaffold3d`,
`AppBar3d` — built as real geometry on this protocol, with a button that is an
actual object you can light, tilt and press into the panel rather than a
picture of one. **It is here, and it draws.**

![A Material screen — an app bar, filter chips, and a scrolling list of cards
holding list tiles and checkboxes — drawn as geometry on a panel in a 3D
scene](docs/material-screen.png)

That is the upright panel of `examples/layout3d_gallery`, photographed from a
frame of the app running on macOS. Every panel in it is a slab with a thickness,
every letter and every icon is a slab too — extruded off a silhouette traced
out of a shared glyph atlas — and every one of them can be
pressed — a press is a camera ray walked down the layout tree. The gallery puts
the same screen on the ground plane beside it, where an elevation stops being a
distance toward the viewer and becomes a **height**.

### What you get

The catalogue is complete enough to build a screen out of, and every component
in it is the same shape underneath: a `Material3d` — the surface, its colour,
its corner, its elevation, its state layer — with a public token set resolved
by the state it is in.

| | |
| --- | --- |
| **Buttons** | `FilledButton3d`, `FilledTonalButton3d`, `OutlinedButton3d`, `TextButton3d`, `ElevatedButton3d`, `IconButton3d`, `FloatingActionButton3d` |
| **Surfaces and rows** | `Card3d`, `ListTile3d`, `Divider3d`, `Chip3d` |
| **Structure** | `Scaffold3d`, `AppBar3d`, `SliverAppBar3d`, `NavigationBar3d`, `NavigationRail3d` |
| **Overlays** | `Dialog3d`, `Menu3d`, `PopupMenuButton3d`, `SnackBar3d`, `Tooltip3d`, `BottomSheet3d` |
| **Selection** | `Checkbox3d`, `Radio3d`, `Switch3d`, `Slider3d` |
| **The rest** | `Material3d`, `InkWell3d`, `Icon3d`, `Theme3dData`, `SceneTheme3d` |

Theming is Material 3's, transcribed: forty-six colour roles, the fifteen-style
type scale, the shape and elevation scales, the state-layer opacities. The
token tables are tested against Flutter's own generated ones, so if the
framework's Material tables move, this package's suite says so.

### Three things Material does not have an answer for

These are where a component stops being a picture and starts being an object,
and they are the reason this is not a port.

**A component has a thickness.** Material publishes a shape scale, a type
scale and elevation levels, and nothing at all about depth, because on a
screen there is none. `Thickness3d` is that scale — 1dp for a divider, 8dp for
an app bar — and two rules come with it. Two slabs no further apart than the
mean of their thicknesses fight for the same pixels, so a screen's parts have
to be *ordered* in depth; `Scaffold3d` owns that ordering rather than leaving
each component to guess. And a thick slab wants its rim bevelled, or it has a
hard square edge where a real object would not.

**An elevation is a height, not a shadow.** Material's elevation model is
entirely shadows; here a raised card is genuinely nearer the viewer, and reads
as raised through parallax, occlusion and Material 3's surface tint. On the
ground plane it stops being a distance toward the viewer and becomes a height
above the table.

**Disabled is a colour, not a filter.** There is no subtree opacity in this
stack, so a disabled control resolves to different colours — `onSurface` at
38% for a label, 12% for a container — which is what Material's own
specification says the result should be anyway.

Interaction stays off the layout path by construction. A hover, a focus, a
press and the ripple that grows out of the point your finger landed on are all
shader uniforms; a slider's thumb and its filling track are one matrix a frame.
None of it rebuilds a widget or lays out a box, and the test suite asserts that
in those terms rather than trusting it.

The [package README](packages/flutter_scene_material3d/README.md) is the deep
reference, component by component, and it is honest at the end about what is
not there — text input above all, which needs an editing layer that does not
exist anywhere in this stack and is not planned.

## Seeing it run

`examples/layout3d_gallery` is the fastest way to see what any of this looks
like. It commits no platform scaffolding, so generate one first:

```sh
cd examples/layout3d_gallery
flutter create . --platforms=macos
flutter run -d macos --enable-flutter-gpu
```

Three surfaces at once, all live and all hit-testable: a Material screen
standing upright on a panel that turns, the same catalogue lying flat on the
ground plane at a unit rate of its own, and a scrolling list of raw meshes
beside them — the same protocol arranging an application's own geometry rather
than a component library's.

The suites are two, and both matter:

```sh
flutter pub get                                        # resolves the workspace
cd packages/flutter_scene_layout3d && flutter test      # 946, arithmetic
cd packages/flutter_scene_material3d && flutter test    # 505, arithmetic

cd examples/render_probe                                # 79, on a real GPU
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/render_test.dart -d macos --enable-flutter-gpu
```

The headless suites prove the protocol arranges correctly and prove nothing
about whether a frame comes out. `examples/render_probe` is the other half: it
draws real geometry and asks the frame whether the geometry is where layout
said it would be, taking its expected coordinates from the layout tree rather
than from a golden image. It has repeatedly caught things a thousand
arithmetic tests agreed with — a border drawn inside out, a clip that never
reached the shader, an overlay lift that did nothing.

## Relationship to flutter_scene

`flutter_scene` is the engine underneath, and a plain pub dependency. This
repository does not fork it and does not patch it. The package started life
inside a fork of the engine's monorepo, which is where its early history comes
from, and moved out once the scope made it clear this was its own project.

Contributions and conventions are documented in [AGENTS.md](AGENTS.md), which
is written for coding agents but is the most direct description of how work is
done here. [docs/README.md](docs/README.md) is the map of everything written
down in this repository, including where past decisions and their reasoning
are recorded.
