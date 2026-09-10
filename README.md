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

**It arranges, and it draws only once you have asked it to.** This is the one
thing to understand before planning around the package.

Both halves of the drawing are *seams* — `BoxDecoration3d.painterFactory` is
null until something sets it, and a `Text3d` takes a renderer and has none by
default — and that is deliberate, because a package that installed them would
also have to load a compiled shader before it knew there was a GPU. What has
changed since that was the whole story is that both seams now have an
implementation behind them, in this repository, verified on a real GPU:
`BoxDecoration3dPainter` over the shipped `assets/box_decoration3d.fmat`, and
`AtlasText3dRenderer` over a shared glyph atlas, with `RichText3d` beside it
for what an atlas cannot assemble. `examples/render_probe` draws them and
checks the frame against the layout, 79 probes of it.

**So the two lines that install them are the whole of it**, and a Material
application does not even write those: `initializeMaterial3d()` is one call
that awaits the engine and installs a painter that gives every box a material
of its own. What is still your side of the seam is a renderer or a painter of
your *own* — a different glyph strategy, a different panel shader — which is
what having a seam there is for.

Also open, each for a stated reason: keep-alive for lazily built children,
subtree opacity — `flutter_scene` has no per-node opacity for a fade to
multiply into — and shadows for decorated panels, which the engine will not
cast at all while the panel shader blends its own anti-aliased outline.

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
every label is a quad out of a shared glyph atlas, and every one of them can be
pressed — a press is a camera ray walked down the layout tree. The gallery puts
the same screen on the ground plane beside it, where an elevation stops being a
distance toward the viewer and becomes a **height**.

Its
[plan](packages/flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md)
opened with four things missing from *this* package that a first component
could not do without: the declarative layer could not draw, a label had no
default renderer, there was nowhere tree-wide to put a theme, and compiling
the panel shader was an application's job. All four
[have landed](packages/flutter_scene_layout3d/plans/2026_09_01_the_four_things_before_a_component.md)
— `SceneDecoratedBox3d`, `DefaultTextRenderer3d`, `Layout3dSlot`, and a build
hook on this package that compiles its own shader for every consumer.

What exists in
[`packages/flutter_scene_material3d`](packages/flutter_scene_material3d/) today
starts with the token layer and the primitive built on it. The tokens are Material 3's
colour roles, type scale, shape and elevation scales, its state-layer
opacities, and the one scale Material does not publish at all — **how deep a
component is**, because on a screen there is none. A `Theme3dData` carries
them and a `SceneTheme3d` publishes it to both layers at once: an inherited
widget for `build`, and a layout-owner slot for `performLayout`, which has no
`BuildContext` to read an inherited widget with.

On top of that: `initializeMaterial3d()`, the one call an application makes
before anything draws; `Material3d`, a decorated box with the theme resolved
into it, which owns the surface, the shape, the elevation, the state layer and
the thickness; `InkWell3d`, which lights it up for a hover, a focus or a press
**without rebuilding a thing**; and `Icon3d`, one code point of an icon font
drawn through the same glyph atlas as every label.

The components are on top of that, and every one of them is the same shape: a
`Material3d` with a public token set resolved by state. The seven buttons are
one `Button3d` over seven `ButtonStyle3d`s; the surfaces and rows are `Card3d`,
`ListTile3d`, `Divider3d` and `Chip3d`; the structure is `Scaffold3d`,
`AppBar3d`, `SliverAppBar3d`, `NavigationBar3d` and `NavigationRail3d`; and the
overlays are `Dialog3d`, `Menu3d` and `PopupMenuButton3d`, `SnackBar3d` behind
a queueing `ScaffoldMessenger3d`, `Tooltip3d` and `BottomSheet3d`; and the
selection controls are `Checkbox3d`, `Radio3d`, `Switch3d` and `Slider3d`. A
press grows a **ripple** out of the point the finger landed on, which is two
more uniforms on the same panel shader and one `smoothstep` — and which runs on
a ticker without rebuilding or laying out a thing.

The gallery is what closed it, and it was worth more than the code in it. Four
of the defects it found had a full green suite standing behind them: the
example app had **no build hook**, so the committed version could never have
drawn its own cubes; every slot of every `Scaffold3d` was **unreachable by a
ray**, because a lift written into a child's *position* puts it outside its
parent's extent and a hit test clamps there; a `semanticLabel` with no reading
direction **crashed the frame** the moment anything switched semantics on; and
a shared glyph atlas repacking under a second surface's letters **took a
settled panel's labels away for good**. None of that is arithmetic, and none of
it was going to be found by more of it.

The selection controls are where two of this project's rules meet at once. A
thumb sliding along a track is a `nodeOffset` and a track filling to it is a
`nodeTransform` — one matrix a frame and no relayout, which is what lets a
slider be dragged across twenty frames without laying a single box out — and a
thumb has to stand *proud* of the track rather than resting on it, because two
coplanar surfaces fight for the depth buffer. That second rule had been written
out by hand for a divider on a card, a glyph on a navigation pill and an item
on a menu surface before it became `Thickness3d.stepOver`.

The structure is where the depth stops being decoration. A screen's slots have
to be *ordered* in depth, because an app bar is over content that scrolls under
it and two slabs no further apart than the mean of their thicknesses fight for
the same pixels. `Scaffold3d` owns that ordering rather than leaving each
component to guess, and the render probes photograph both halves of it: a row
passing under a pinned bar is genuinely cut at the bar's edge, and the bar is
drawn in front of the row sliding beneath it. Getting there found the same
defect twice — a clip that never reached the shader — and both times only a
drawn frame said so.

The overlays are where it stops being about one screen. A dialog is a slab in
front of a stack of slabs, so its lift has to clear *all* of them —
`Scaffold3d.overlayLift` is that number, one step in front of the frontmost
slot the scaffold declares, so the two agree by construction rather than by
matching figures. A scrim is geometry too, dark and translucent and a
millimetre thick, and the probe that settles it asks a comparison rather than
an absolute. And a menu has to be *at* its button: `Layout3d.anchorOffsetTo`
is the arithmetic, written on the node tier so a menu can follow a scrolling
button without laying anything out.

## Running it

```sh
flutter pub get                                       # resolves the workspace
cd packages/flutter_scene_layout3d && flutter test     # the layout suite
cd packages/flutter_scene_material3d && flutter test   # the Material suite
```

Both suites are arithmetic and run headless. To check that a frame actually
comes out, `examples/render_probe` draws the layout on a GPU and probes the result at
the pixels layout says to check:

```sh
cd examples/render_probe
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/render_test.dart -d macos --enable-flutter-gpu
```

The example app commits no platform scaffolding, so generate a platform first:

```sh
cd examples/layout3d_gallery
flutter create . --platforms=macos
flutter run -d macos --enable-flutter-gpu
```

It shows three surfaces at once, all live and all hit-testable: a Material
screen standing upright on a panel that turns, the same catalogue lying flat on
the ground plane, and a scrolling list of raw meshes beside them — the same
protocol arranging an application's own geometry rather than a component
library's.

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
