# flutter_scene_layout3d

Flutter's box layout protocol, in three dimensions, for
[flutter_scene](https://pub.dev/packages/flutter_scene).

Constraints go down, sizes come up, and the parent decides where the child
sits. The rules are the ones you already know; what changes is that a box has
three extents, a position is a point in space, and the output of layout is a
tree of scene `Node` transforms rather than a display list.

> **Status: experimental.** The API may change between releases.

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

Everything laid out hangs below `surface.plane`, so moving, turning, or
scaling that one node carries the whole arrangement with it:

```dart
surface.plane.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), 0.4);
```

## The coordinate model

Layouts do their arithmetic in **layout space**: `x` right, `y` **down**, `z`
**away from the viewer**, with a box occupying `[0, width] x [0, height] x
[0, depth]` from its origin corner. That is Flutter's coordinate system with a
third axis added, which is why `Column3d`, `Align3d`, and `Stack3d` behave
exactly like their Flutter counterparts.

The scene does not see those coordinates. A `LayoutBasis3d` on the surface
maps them into the plane node's space, once, at the root:

```
LayoutBasis3d.xy (default)           LayoutBasis3d.xz
an upright panel facing you          a plane on the ground

   +-------------+                       +---------+
   |  [A]        |  Column3d runs        | [A][B]  |   Row3d runs across
   |  [B]        |  down the plane       | [C][D]  |   the floor
   |  [C]        |                       +---------+
   +-------------+                            v  layout y runs toward
        layout x runs right                        the viewer
```

The axis signs are not the obvious ones, and this is worth knowing before you
write a basis of your own. flutter_scene builds its camera basis with
`right = up × forward`, so for a camera in front of a plane the direction that
appears to the **right** on screen is world `-x`, not `+x`. The built-in bases
map layout "right" to the direction that actually reads as right, which makes
them orientation-reversing. That never mirrors content: a `NodeBox3d` applies
the inverse basis to what it holds, so a model keeps the orientation it was
authored with and only its *placement* is mapped.

`LayoutBasis3d.fromMatrix` takes any invertible matrix if the plane should sit
at some other angle. `Layout3dSurface.origin` says which point of the
laid-out box sits at the plane node's origin, and defaults to the centre. The
plane node itself is an ordinary scene node: its `position` is in the
engine's coordinates, not in layout space.

## How the plane gets a screen, and what a logical pixel is worth

A surface is unbounded on all three axes until something bounds it, and a
scene, unlike a window, bounds nothing. That is why a `ListView3d` on a bare
surface asserts: nothing has told it how tall its window is. Flutter never has
this problem, because the screen bounds everything.

A **camera-bound** surface is the missing screen. Put the plane a fixed
distance in front of the camera, oriented to it, and the view frustum at that
distance has an exact world width and height, which are the surface's
constraints:

```dart
final surface = Layout3dSurface(child: panel);
const binding = Layout3dCameraBinding.screenFilling(distance: 2, depth: 0.2);

// Once a frame, before rendering.
binding.update(surface, camera: camera, viewSize: viewSize);
surface.flush();
```

Declaratively it is two arguments, and the widget runs itself off the enclosing
`SceneView`'s clock, so a moving camera is followed without the application
ticking anything:

```dart
SceneLayout3d(
  camera: camera,
  binding: const Layout3dCameraBinding.screenFilling(distance: 2, depth: 0.2),
  child: SceneColumn3d(children: [...]),
)
```

A panel so bound behaves like a Flutter window. It resizes when the view
resizes, its content reflows, and "how big is the screen" finally has an
answer. Do not also give it a `size`: the binding owns the constraints, and
the two would fight every frame.

### The unit contract

Once the plane covers the view, the conversion between logical pixels and
world units stops being a choice. The plane's world height spans exactly
`viewSize.height` logical pixels, so

```
unitsPerLogicalPixel = worldHeight / viewSize.height
```

and a Material 48dp touch target laid out `48 * unitsPerLogicalPixel` units
wide lands as 48dp on the screen. That number, with an accessibility text
scale and a visual density beside it, is `Layout3dMetrics`. It rides on the
surface, next to the basis, and every box in the tree reads the same one:

```dart
class Button3d extends SingleChildLayout3d {
  @override
  void performLayout() {
    // A 64 x 40 dp minimum, adjusted by the theme's density, inside whatever
    // the parent allows.
    final wanted = metrics.effectiveConstraints(
      Constraints3d(minWidth: metrics.dp(64), minHeight: metrics.dp(40)),
    );
    child!.layout(wanted.enforce(constraints), parentUsesSize: true);
    size = constraints.constrain(child!.size);
    child!.place(Offset3d.zero);
  }
}
```

`metrics.dp(x)` is logical pixels to world units, `metrics.sp(x)` is the same
scaled by the text scale, and `metrics.toLogicalPixels(u)` goes back the other
way — which is what a rasterizer wants when it has to decide how many real
pixels a glyph is worth. Changing the metrics relayouts the whole subtree,
because a box sized in dp is a different box afterwards and nothing else would
tell it so.

### Anything else the whole tree needs: slots

The metrics ride on the surface rather than in an `InheritedWidget` for one
reason: the imperative layer has no `BuildContext`, and a box has to be able
to read this inside `performLayout`. A component library's *theme* has exactly
that shape — every component reads it, nobody is handed it — and a theme
cannot be a field here, because Material vocabulary does not belong in a
layout package.

So the surface carries an open, typed map beside the metrics, and the library
that has an opinion declares the key:

```dart
// In the component library.
const themeSlot = Layout3dSlot<Theme3dData>('material3d.theme');

// In the application.
SceneLayout3d(
  size: const Size3d(4, 3, 0.2),
  slots: {themeSlot: Theme3dData.light()},
  child: screen,
)

// In a component, inside performLayout, with no BuildContext anywhere.
final theme = slot(themeSlot) ?? Theme3dData.light();
```

`SceneSlotProvider3d` writes the same value from *inside* the tree, which is
where a library's own theme widget will want to sit — it is usually an
`InheritedWidget` for the widget layer as well, and the two halves should be
one widget. `Layout3dSurface.setSlot` is the imperative form, and
`SlotProvider3d` the imperative box.

Three rules, each of which costs time to discover otherwise:

* **A slot is its type and its name.** `Layout3dSlot<Theme3dData>('theme')`
  written twice is one slot, wherever it was written and whether or not it was
  `const`. Identity keying was the first design and it is wrong here, because
  Dart canonicalizes `const` instances: the same code would key by value when
  declared `const` and by identity when declared `final`. Name a slot after
  the library that owns it and declare it once.
* **Writing one relayouts the subtree**, exactly as writing the metrics does,
  and for the same reason: a slot is read during layout and never arrives as a
  constraint, so nothing else would tell a box that the number it sized itself
  from moved. Pass `relayout: false` for a value nothing measures against, and
  keep slots off any per-frame path.
* **The surface stores the value and does not own it.** Disposing the surface
  clears the map and disposes nothing in it, the same rule it follows for the
  layouts it collects.

### Panels that are not screens

A panel hanging on a wall at some angle is not standing in for a screen, and
there is no frustum to derive its scale from. Say what it is drawn at instead:

```dart
Layout3dCameraBinding.fixedDensity(0.01).update(surface);   // 1 unit = 100 dp
```

Same contract, authored rather than derived, and nothing downstream can tell
the difference. `Layout3dCameraBinding.billboard()` is the third mode: the
application owns where the panel is and the camera owns which way it faces. It
writes the plane's transform only, so it touches no layout at all and is cheap
to run every frame on as many panels as the scene holds.

Three things are worth knowing before you reach for any of this:

* **Depth is not derivable.** A frustum has no thickness, so
  `screenFilling(depth: ...)` is an explicit property and defaults to zero. A
  flat plane is a fine screen, but content standing in it needs a real
  thickness — the same trap the *Traps* section names.
* **The metrics are not a promise about pixels** unless the surface really is
  camera-bound. A panel at an angle, or one the viewer can walk toward, covers
  a different number of real pixels every frame. The number says how the
  layout is *specified*; anything that rasterizes needs its own
  level-of-detail story on top.
* **A moving camera is cheap.** The derived extents carry a dead band
  (`extentEpsilon`, a ten-thousandth of a unit by default), so view-matrix
  jitter does not read as a size change; the plane's transform is compared
  before it is written; and a camera that pans, or walks along its own forward
  axis, re-derives the same frustum and relayouts nothing.

## Text

`Text3d` is a string laid out as a box. It is a leaf, like `NodeBox3d`, and it
is the first thing in this package that answers the measurement protocol with
something real: it reports intrinsic widths that mean what they say, and it
states a baseline.

```dart
Row3d(
  crossAxisAlignment: CrossAxisAlignment3d.baseline,
  children: [
    Text3d('Save', style: const TextStyle(fontSize: 14)),
    Text3d('⌘S', style: const TextStyle(fontSize: 11)),
  ],
)
```

Flutter's own `TextStyle`, `TextAlign`, `TextDirection` and `TextOverflow` are
what it takes, because a component author already knows them and the
measurement layer has to build a `ui.Paragraph` out of them anyway. Font sizes
are logical pixels, as everywhere in Flutter, and the unit contract above is
what turns them into world units: a 14sp label is `metrics.sp(14)` tall
whether the surface is bound to a camera or drawn at an authored scale. The
box has **no thickness** by default — glyphs are flat, and the slab behind a
label belongs to whatever draws the label's background.

### Prepare once, lay out often

The design is a two-phase split, and it is the reason text is usable here at
all. `prepare()` runs once per string: normalize the whitespace, split the
text at every place a line is allowed to end, and measure each of those pieces
with the platform's own font engine. `layout()` then fits those measured
pieces into a width, and for the default policy that is arithmetic and nothing
else — no shaping, no `Paragraph.layout`, no font.

That matters more here than it would in Flutter. A box in this package is
relaid out far more often than a `RenderParagraph` is: whenever a scroll
offset changes the room an item gets, whenever the surface resizes, on every
frame of an animation, and *twice more* whenever an `IntrinsicWidth3d` above
it asks its question, because answering an intrinsic walks the whole subtree
and then the subtree is laid out again for real. With shaping on that path, a
`Column3d(crossAxisAlignment: stretch)` of labels under an `IntrinsicWidth3d`
is unaffordable; without it, it costs a few additions.

The measurements are cached by (string, style), which pays because UI text
repeats: a list of labels shares its words, a column of numbers shares its
digits, and the single space between two words is measured once for a whole
application.

### The trade, and how to opt out of it

Adding per-segment widths is not the same as shaping a whole line. Kerning and
ligatures *across* a segment boundary are not modelled, and neither is the
joining behaviour of Arabic and Indic scripts, where a letter's width depends
on its neighbours. Segments are word-like — they are exactly the places a line
may end — so for Latin, Greek, Cyrillic and CJK the error is nil: the suite
checks every wrap against `TextPainter`, at every whole width from 10 to 210
logical pixels, and they agree exactly.

Where the trade does not hold, swap the policy rather than the box:

```dart
Text3d(arabic, style: style, measurement: const ParagraphTextMeasurement3d())
```

That hands every layout back to the platform — one `ui.Paragraph` per layout
call, with its line breaking, shaping and bidi. It costs the thing the split
exists to avoid, so reach for it per box rather than globally.

`TextBreakRules3d` is the third dial: whitespace preserved (Flutter's rule) or
collapsed (CSS's), `WordBreak3d.keepAll` for text that must not break between
ideographs, and `OverflowWrap3d.overflow` for a word that should hang outside
the box rather than be broken. The defaults are Flutter's, including breaking
a word too wide for its line — which Flutter does and CSS does not.

### Drawing it: the glyph atlas

Measurement and rasterization are separated on purpose, and the seam between
them is `Text3dRenderer`. A `Text3d` with no renderer lays out, sizes itself,
answers intrinsics and states a baseline, and puts nothing in the scene —
which is a useful object on its own, and is what every one of this package's
headless tests measures.

The renderer that ships is `AtlasText3dRenderer`, and it is the one a
component library wants:

```dart
Text3d('Save', style: labelStyle, renderer: AtlasText3dRenderer())
```

**A renderer is owned by the box that holds it**, and that is the rule to
carry away: `Text3d` disposes it when a different one is set and when the box
itself is disposed. So a screen of labels wants a renderer *each*, never one
instance passed around — the first label to leave the tree would dispose it
and every other label would quietly stop drawing. The thing worth sharing is
the atlas underneath, and that is shared already.

Writing `renderer:` on every label is not what an application should have to
do, so the widget layer inherits it, the way it inherits a `DefaultTextStyle`:

```dart
DefaultTextRenderer3d(
  factory: AtlasText3dRenderer.new,
  child: SceneView.declarative(children: [SceneLayout3d(child: screen)]),
)
```

Every `SceneText3d` below that calls the factory once and owns what comes
back; one that states its own `renderer` overrides it, exactly as one that
states its own `style` overrides the ambient style. The inherited value is a
*factory* and not a renderer for the ownership reason above — an inherited
instance would be a shared one — so keep the function stable: a tear-off like
`AtlasText3dRenderer.new`, or a field on a `State`. A closure written inline in
`build` is a new function every build, and every label in the tree would
rebuild its renderer. In the imperative layer the same seam is
`Text3d.rendererFactory`.

One texture holds every glyph a style has been asked to draw at one
resolution, and each label is one mesh of textured quads out of it. A screen
of buttons sharing a font shares the texture, so the hundredth label costs a
hundred vertices rather than a hundred captures. `dart:ui` exposes no glyph
rasters, so a glyph is obtained the only way there is — a single-grapheme
`ui.Paragraph` painted into a `PictureRecorder` — but the whole atlas is
redrawn and read back in one go, and only when a glyph nobody has drawn before
turns up. That readback is asynchronous, which is why a label containing a
brand-new glyph appears one frame late rather than blocking layout on a
texture upload.

Two dials matter. `resolution` is texels per logical pixel, on top of what the
metrics ask for: `logicalPixelsPerUnit` is a promise about screen pixels only
for a surface bound to the camera, and a panel the viewer can walk toward
covers more of them with every step. Two is right for a panel at arm's length
on a dense display; the memory cost is quadratic. `depthOffset` lifts the
glyphs toward the viewer, because text drawn exactly on the plane of the panel
behind it is text at the same depth as that panel, and the depth test does not
break ties.

What the atlas cannot do is assemble a script whose glyphs change shape
according to their neighbours. It holds one raster per grapheme cluster, so
Arabic, Devanagari and their relatives come out wrong; ligatures across a
cluster boundary are lost for the same reason. The *positions* do carry the
font's kerning — a run is shaped as a whole before it is cut into glyphs — so
Latin, Greek and Cyrillic are right. A style's `foreground` and `background`
paints are not honoured either: a glyph is rasterized white so that one atlas
serves every colour, and the colour is applied by the material.

### RichText3d, the escape hatch

When the atlas is the wrong tool, hand the whole problem back to Flutter:

```dart
RichText3d(
  TextSpan(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202020)),
    children: [
      const TextSpan(text: 'Signed in as '),
      TextSpan(text: user.name, style: bold),
    ],
  ),
)
```

A live `RichText` subtree is laid out and rasterized by the framework and the
result is sampled onto a quad this package builds. Everything Flutter can
draw, it draws: several styles in one paragraph, inline widgets, emoji, Arabic
and Devanagari with their joining and reordering intact. It costs a texture, a
widget subtree and — at the default update policy — a rasterization per frame
per box, so it is the paragraph with a link in it, not every label on a
screen.

Measurement is exact and headless all the same: the size, the intrinsics and
the baseline come from a `TextPainter`, the same object a Flutter `Text`
measures with, so a `RichText3d` participates in the layout protocol whether
or not there is a GPU to draw it on. What it does need in order to *draw* is a
`SceneView`: the hosted subtree lives inside the widget that displays the
scene, which is where its tickers run and where the capture happens. Pointer
input is not forwarded into that subtree — this package dispatches its own
pointers against the layout tree, and a hit on a `RichText3d` stops at the box
exactly as it stops at a `Text3d`.

## Sizing real 3D content

The hard part of a 3D layout is getting arbitrary content, primitives,
imported models, whole subtrees, to answer "how big are you?". `NodeBox3d`
answers it from the engine's own measurement, `Node.combinedLocalBounds`,
mapped out of scene space by the surface basis:

```dart
NodeBox3d(
  content: model,               // any Node, app-owned
  fit: BoxFit3d.contain,        // none, contain, fill, scaleDown
  alignment: Alignment3d.center,
)
```

* Content that cannot report bounds (skinned meshes, caller-managed geometry)
  measures as `fallbackSize`.
* `explicitSize` states the content's extent outright and skips measuring. It
  is a *measurement*, not a sizing request: to make a model occupy a
  particular size, put it in a `SizedBox3d` and let `fit` scale it.
* Override `readContentBounds` to measure content some other way.
* The box owns the content node's `localTransform`, centring the measured
  bounds in the box and undoing the surface basis so the model keeps the
  orientation it was authored with. Content that needs an offset of its own
  belongs inside a wrapper `Node`.

The fit rule is Flutter's, not a 3D invention. The box first takes the size
any leaf would (`constraints.constrain(measured)`), and `fit` then scales the
content *into* that box, exactly as `FittedBox` does. A loose parent therefore
never inflates the box: `contain` scales up only when something above has
fixed the size.

```dart
// A model, whatever its authored size, occupying 0.3 on a side.
SizedBox3d.cube(0.3, child: NodeBox3d(content: model, fit: BoxFit3d.contain))
```

`contentScale` reports what the fit actually did, for when a model comes out
larger or smaller than expected and the question is whether the fit or the
measurement is responsible.

## Making a box visible

`NodeBox3d` takes content that already exists and scales it into the room
available. A panel needs the opposite: geometry that is *told* the size and
produces the right shape at it, because scaling a rounded panel distorts its
corners and a card with a 12dp radius needs 12dp at every size.

`DecoratedBox3d` is that box. It lays its child out exactly as a pass-through
would and then hands its own size to a painter:

```dart
DecoratedBox3d(
  decoration: const BoxDecoration3d(
    color: Color(0xFF1B6EF3),
    borderRadius: BorderRadius3d.circular(12),
    border: Border3d(width: 1, color: Color(0x33000000)),
    elevation: 3,
    surfaceTint: Color(0xFF6750A4),
  ),
  child: Padding3d(
    padding: const EdgeInsets3d.all(0.12),
    child: Text3d('Continue'),
  ),
)
```

**Every figure on a `BoxDecoration3d` is in logical pixels**, not world units —
a 12dp corner, a 1dp outline, a 3dp elevation — and the metrics turn them into
units at paint time. That is the same bargain `Text3d` strikes with
`TextStyle.fontSize`, and it is what makes one decoration correct on a
camera-bound surface and on a wall panel whose scale the author picked.

### The bet: a shader, not regenerated meshes

There are three ways to make a rounded panel follow a size, and the choice
here shapes everything else. Regenerating the mesh is correct and the wrong
default, because a screen of components animating produces mesh churn every
frame. A 27-slice mesh avoids the churn but cannot express a border or a bevel
that changes with state. So the default is a **signed-distance field in the
fragment shader** over one shared slab, with the size, the radii, the border
and the state layer as uniforms: resolution-independent corners, no geometry
work at any size, one mesh and one material class for every panel in the
scene.

Everything downstream follows from that:

* A size change scales a shared slab and rewrites parameters. It never
  rebuilds geometry.
* A colour, radius, border or elevation change never relayouts — `DecoratedBox3d.decoration` marks nothing dirty for layout, because a decoration has no say in any extent.
* A **state layer** (hover, focus, press, drag) is one uniform.
  `DecoratedBox3d.stateLayer` writes it and asks for a frame; it does not
  even repaint through the layout pipeline.
* Panels **share a painter** through a per-surface cache keyed by
  `Decoration3d.cacheKey`. Every `BoxDecoration3d` returns the same key
  whatever its numbers, so a hundred cards are a hundred boxes, one mesh and
  one material class.

### Elevation is real here

Material's elevation is a painted shadow standing in for a height. In a scene
the height is real: `BoxDecoration3d.elevation` lifts the geometry toward the
viewer by `metrics.dp(elevation)`, so a raised card genuinely moves under the
camera and genuinely occludes what is behind it. Material 3's other half, the
surface tint, is a uniform on the same shader and follows the published
opacity table (`BoxDecoration3d.surfaceTintOpacityFor`).

The lift moves the *geometry* and nothing else. The box keeps the size and
position layout gave it, and a ray still reaches it where the layout put it —
a raised button whose touch target drifted away from its layout box would be a
bug. It is the same distinction `ParentData3d.sceneOffset` draws. The one
place the lift shows outside the picture is the screen projection:
`screenCenter` reads `worldTransform`, which undoes `hitTestTransform` and
finds it null here, so a projected elevated panel is where the panel is
*drawn*.

**A panel casts no shadow, and that is not a bug you can fix here.** The panel
shader declares `blending: alpha`, because its anti-aliased outline is an
alpha, and `flutter_scene` drops every non-opaque material before the shadow
pass. So elevation buys parallax and occlusion and not a contact shadow.
Grounding a card on a surface is the catalogue's job — the engine's
`ShadowCatcherMaterial` on a plane beneath it is the shape of it —
and `examples/render_probe`'s `panel_shadow` scene is the standing check that
this is still how the engine behaves.

### It does not draw on its own either

Like `Text3d`, a `DecoratedBox3d` with no painter lays out, sizes itself and
hit-tests exactly as it otherwise would, and puts nothing in the scene.
Producing geometry needs a GPU context, which a headless test does not have
and neither does a surface built before `Scene.initializeStaticResources()`
resolves. `Decoration3dPainter` is the seam.

The package ships the shader as `assets/box_decoration3d.fmat` and
`BoxDecoration3dPainter` as the painter that drives it, **and it compiles the
shader itself**: this package's `hook/build.dart` runs `impellerc` over that
file for whatever application depends on it, so there is nothing to copy and
nothing to add to your own hook. Install the factory once, at startup, after
`Scene.initializeStaticResources()` has resolved:

```dart
final material = await loadFmatMaterial('assets/box_decoration3d.fmat');
BoxDecoration3d.painterFactory =
    (_) => BoxDecoration3dPainter(createMaterial: () => material);
```

That source path names the file inside *this* package, not one in your app.
It resolves through the manifest this package's hook writes into its own
`flutter_scene_generated/` directory, which reaches the bundle keyed
`packages/flutter_scene_layout3d/…`. Nothing in your app's own hook mentions
panels.

Keep `buildEngineAssets` separate in your head from all of this. It is what
makes `Scene.initializeStaticResources()` resolve, without which nothing in a
scene renders at all — and `flutter_scene`'s own hook already builds those
shaders into its own package directory, so an app usually needs no hook for it
either. Call it from your own hook (`dart run flutter_scene:init` writes that
hook) when you want the engine's shaders in your app's bundle instead: a
locked-down pub cache is the case that forces it, and the engine says so in
the error. `examples/render_probe` does exactly that and nothing else:

```dart
void main(List<String> args) {
  build(args, (input, output) async {
    await buildEngineAssets(buildInput: input, buildOutput: output);
  });
}
```

One migration hazard, once. If your app used to compile
`box_decoration3d.fmat` itself, its old bundle is still sitting in its
`flutter_scene_generated/` — that directory is persistent by design and
survives `flutter clean`, and stale outputs are pruned only by the builder
that wrote them, on a run it no longer makes. Two packages then offer the same
source path and `loadFmatMaterial` throws *"Multiple generated .fmat
materials"*. Delete the contents of the app's `flutter_scene_generated/`,
keeping its `.gitignore`, and it does not come back.

The painter's own trick is worth knowing if you write a decoration of your
own. A `.fmat` fragment shader is handed a world position, a normal and a UV,
none of which say where in the *box* a fragment is. The shared slab is a unit
cube whose vertex colours are its own object-space coordinates, so the shader
recovers the position exactly with a subtract and a multiply. A caller with a
mesh of its own passes it as `createGeometry` and keeps the same convention;
a decoration a shader cannot express at all subclasses `Decoration3d` and
generates whatever it likes inside its painter.

### Clipping, and the contract for it

`ClipBox3d` clips its child to its own extent. Layout is untouched — it is a
pass-through — and two things happen, at different prices:

```dart
SizedBox3d(
  width: 2,
  height: 2,
  child: ClipBox3d(child: Column3d(children: rows)),
)
```

* Every descendant's `Layout3d.clipRegion` reports the clip, as a
  `Clip3dRegion`: an intersection of `ClipPlane3d` half-spaces expressed in
  that box's own layout frame, pulled back exactly through any transform on
  the way down. `toPlaneBlock()` packs it as the `vec4` uniforms a material
  reads, and the shipped panel shader discards where any plane reports
  negative. This is the tier that clips *part* of a child.
* With `cullNodes` (the default), descendants that fall entirely outside have
  their scene node hidden, which also puts them out of reach of a ray. Exact
  for whole boxes, useless for a box that is half in, and free.

`clipDepth` is off by default, so a raised card inside a scrolling list still
stands proud of it instead of being sliced off at the surface. Nesting
axis-aligned clips folds parallel planes together, so however deep they stack
a clip stays six planes — which is `Clip3dRegion.maxPlanes`, the number a
consumer is required to honour. A clip taken through a rotation can exceed it,
and `toPlaneBlock` throws rather than clipping less than it was asked to.

### Hiding without decorating

`Visibility3d` hides its child and keeps its space; `Offstage3d` hides it and
gives the space back, reporting zero size and no baseline. Both work by the
scene node's `visible` flag, which hit testing already honours, so an
invisible box is unpointable as well as unseen. Toggling a `Visibility3d` does
not relayout; toggling an `Offstage3d` does, because the size it reports
depends on it.

There is deliberately no `Opacity3d`. Flutter's is a `saveLayer`, and a scene
has no such thing; fading a subtree means multiplying an alpha into every
material under it, which needs an engine-side per-node opacity that does not
exist yet. A wrapper that silently only faded `BoxDecoration3d` would be worse
than none.

## What is in the box

| Layout | Flutter counterpart |
| --- | --- |
| `Layout3dSurface` | the root, plus `RenderView`'s job of starting layout |
| `Layout3d`, `SingleChildLayout3d`, `MultiChildLayout3d`, `ProxyLayout3d` | `RenderBox` and friends |
| `Constraints3d`, `Size3d`, `Offset3d`, `Alignment3d`, `EdgeInsets3d` | `BoxConstraints`, `Size`, `Offset`, `Alignment`, `EdgeInsets` |
| `Container3d`, `Padding3d`, `Align3d`, `Center3d` | `Container`, `Padding`, `Align`, `Center` |
| `SizedBox3d`, `ConstrainedBox3d`, `Transform3d` | `SizedBox`, `ConstrainedBox`, `Transform` |
| `Row3d`, `Column3d`, `Depth3d`, `Flexible3d`, `Expanded3d`, `Spacer3d` | `Row`, `Column`, `Flexible`, `Expanded`, `Spacer` |
| `Stack3d`, `Positioned3d` | `Stack`, `Positioned` |
| `Wrap3d` | `Wrap` |
| `LimitedBox3d`, `UnconstrainedBox3d`, `OverflowBox3d`, `FractionallySizedBox3d` | `LimitedBox`, `UnconstrainedBox`, `OverflowBox`, `FractionallySizedBox` |
| `AspectRatio3d`, `FittedBox3d`, `IndexedStack3d` | `AspectRatio`, `FittedBox`, `IndexedStack` |
| `Table3d`, `TableColumnWidth3d` and its four policies | `Table`, `TableColumnWidth` and its own |
| `LayoutBuilder3d` | `LayoutBuilder` |
| `CustomMultiChildLayout3d`, `MultiChildLayout3dDelegate`, `LayoutId3d` | `CustomMultiChildLayout`, `MultiChildLayoutDelegate`, `LayoutId` |
| `Flow3d`, `Flow3dDelegate` | `Flow`, `FlowDelegate`, at node-transform cost rather than repaint cost |
| `Layout3dCameraBinding` | what `View` does for a Flutter tree: the thing that bounds it |
| `Layout3dMetrics`, `VisualDensity3d` | `MediaQuery`'s scale factors, `VisualDensity` |
| `Viewport3d`, `ListView3d`, `GridView3d`, `Scroll3dController` | `SingleChildScrollView`, `ListView`, `GridView`, `ScrollController` |
| `Scroll3dPhysics`, `ClampingScroll3dPhysics`, `BouncingScroll3dPhysics` | `ScrollPhysics` and its two familiar shapes |
| `PageView3d`, `PageScroll3dPhysics` | `PageView`, `PageScrollPhysics` |
| `ensureVisible3d`, `offsetToReveal3d` | `Scrollable.ensureVisible`, `RenderAbstractViewport.getOffsetToReveal` |
| `Grid3dDelegate`, `Grid3dLayout` | `SliverGridDelegate`, `SliverGridLayout` |
| `CustomScrollView3d`, `Sliver3d` | `CustomScrollView` + `Viewport`, `RenderSliver` |
| `SliverList3d`, `SliverGrid3d`, `SliverToBoxAdapter3d` | `SliverList`, `SliverGrid`, `SliverToBoxAdapter` |
| `SliverPadding3d` | `SliverPadding` |
| `SliverPersistentHeader3d`, `SliverPersistentHeader3dDelegate` | `SliverPersistentHeader`, `SliverPersistentHeaderDelegate` |
| `BoxScrollView3d`, `SliverMultiBoxAdaptor3d` | `BoxScrollView`, `RenderSliverMultiBoxAdaptor` |
| `SliverConstraints3d`, `SliverGeometry3d` | `SliverConstraints`, `SliverGeometry` |
| `IntrinsicWidth3d`, `IntrinsicHeight3d`, `IntrinsicDepth3d` | `IntrinsicWidth`, `IntrinsicHeight` |
| `Baseline3d`, `CrossAxisAlignment3d.baseline` | `Baseline`, `CrossAxisAlignment.baseline` |
| `IgnorePointer3d`, `AbsorbPointer3d` | `IgnorePointer`, `AbsorbPointer` |
| `Ray3d`, `HitTestResult3d`, `Layout3dPointer` | `hitTest`, `BoxHitTestResult`, and `GestureBinding`'s dispatch |
| `Listener3d`, `HitTestTarget3d`, `HitTestBehavior3d` | `Listener` + `MouseRegion`, `HitTestTarget`, `HitTestBehavior` |
| `GestureDetector3d`, `HitTestArea3d`, `TapTarget3d` | `GestureDetector`, a bare hit-test region, Material's 48dp target |
| `Focus3d`, `Focus3dTraversal`, `FocusScope3d` | `Focus`, `FocusTraversalPolicy`, `FocusScope` |
| `Draggable3d`, `DragTarget3d` | `Draggable`, `DragTarget`, on a session of our own rather than `MultiDragGestureRecognizer` |
| `Drag3dSession`, `Drag3dTarget`, `Drag3dDetails`, `Drag3dEvent` | the drag machinery Flutter keeps inside `Draggable`, made a seam |
| `Drag3dStartMode`, `Drag3dAnchor`, `Drag3dAutoscroll` | `Draggable`'s long-press variants, `DragAnchorStrategy`, `EdgeDraggingAutoScroller` |
| `Dismissible3d`, `Dismiss3dDirection` | `Dismissible`, `DismissDirection` |
| `ReorderableList3d`, `SliverReorderableList3d`, `Reorder3dCallback` | `ReorderableListView`, `SliverReorderableList`, `ReorderCallback` — with `newIndex` meaning where the item ends up |
| `Overlay3d`, `Overlay3dEntry`, `OverlayLayer3d` | `Overlay`, `OverlayEntry`, and the 3D question Flutter does not have |
| `ModalBarrier3d`, `Navigator3d`, `Route3d` | `ModalBarrier`, `Navigator`, `Route` |
| `Layout3dPointerGroup` | routing a ray across surfaces, which a screen does not need |
| `NodeBox3d` | the leaf that holds content |
| `Text3d`, `TextMeasurement3d` | `Text`, and the `TextPainter` behind it |
| `AtlasText3dRenderer`, `RichText3d` | the two halves of `RenderParagraph.paint`: glyphs from an atlas, or Flutter's own raster |
| `DecoratedBox3d`, `BoxDecoration3d`, `Border3d`, `BorderRadius3d` | `DecoratedBox`, `BoxDecoration`, `Border`, `BorderRadius` |
| `Decoration3dPainter`, `Decoration3dPainterCache`, `StateLayer3d` | `BoxPainter`, and Material's state layers |
| `ClipBox3d`, `Clip3dRegion`, `ClipPlane3d` | `ClipRect`, and the clip stack behind it |
| `Visibility3d`, `Offstage3d` | `Visibility`, `Offstage` |
| `Size3dTween` and its siblings | `SizeTween`, `EdgeInsetsTween`, `AlignmentTween`, `DecorationTween` |
| `ImplicitlyAnimatedLayout3dWidget`, `SceneAnimatedContainer3d` | `ImplicitlyAnimatedWidget`, `AnimatedContainer` |
| `Layout3d.nodeOffset`, `NodeTransform3d`, `SceneAnimatedSlide3d` | geometry that moves with no layout behind it, which Flutter has no cheap answer for |

`Depth3d` is the axis Flutter does not have: a flex that stacks children away
from the viewer.

## The declarative layer

`package:flutter_scene_layout3d/widgets.dart` describes the same tree from a
`build` method. Each widget owns one layout object and applies property
changes to it on rebuild, so an unchanged rebuild writes nothing; the element
tree does the reconciling.

```dart
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_layout3d/widgets.dart';

SceneView.declarative(
  children: [
    SceneLayout3d(
      size: const Size3d(4, 3, 0.5),
      position: Vector3(0, 1, 0),
      child: SceneColumn3d(
        mainAxisAlignment: MainAxisAlignment3d.center,
        spacing: 0.2,
        children: [
          SceneNodeBox3d(content: cube),
          SceneExpanded3d(child: SceneNodeBox3d(content: banner)),
        ],
      ),
    ),
  ],
)
```

Every layout has a widget with the same name under a `Scene` prefix
(`SceneRow3d`, `SceneStack3d`, `ScenePositioned3d`, `SceneListView3d`, ...).
The scrolling ones carry the imperative layer's second constructor too:
`SceneListView3d.builder`, `SceneGridView3d.builder`,
`SceneSliverList3d.builder` and `SceneSliverGrid3d.builder` build a *widget*
per item as the window reaches it, so a long list costs the dozen rows on
screen. See *Scrolling* below for what a built item does and does not keep.
A handful of widgets have no imperative counterpart because they *are* the
widget layer: `SceneAnimatedContainer3d` and its siblings are stateful, and
`SceneAnimatedSlide3d` owns the controller behind a node-only animation. See
*Animation* below. `SceneText3d` is the one that gains something from being a widget: it has a
`BuildContext` to ask, so it picks up the ambient `DefaultTextStyle`,
`DefaultTextRenderer3d` and `Directionality` the way a Flutter `Text` does —
from the widget tree the scene is hosted in, not from anything inside the
scene.

`SceneDecoratedBox3d` is the one that makes a declarative tree *visible*, and
it is the widget form of `DecoratedBox3d` with the same two properties and
the same promise about them:

```dart
SceneDecoratedBox3d(
  decoration: const BoxDecoration3d(
    color: Color(0xFF1B6EF3),
    borderRadius: BorderRadius3d.circular(12),
    elevation: 3,
  ),
  stateLayer: hovered
      ? const StateLayer3d(color: Color(0xFFFFFFFF), opacity: 0.08)
      : StateLayer3d.none,
  child: const ScenePadding3d(
    padding: EdgeInsets3d.all(0.12),
    child: SceneText3d('Continue'),
  ),
)
```

Neither property touches layout, and a rebuild that changes only one of them
lays nothing out — it writes shader parameters and asks for a frame. That is
the whole reason the properties are setters on the box rather than
constructor arguments to a new one, and it is what makes hovering a screen of
controls free rather than a stutter.

There is deliberately no `decoration` on `SceneContainer3d`, though Flutter's
`Container` has one. Flutter's is a *composition* — it builds a small tree, and
`DecoratedBox` stays the single implementation of what a decoration is — while
`Container3d` is one box, so a decoration on it would be a second copy of the
painter lifecycle, and Flutter's own semantics (the decoration sits inside the
margin and around the padding) is a rectangle that is not the box's own size.
Composing the two says which rectangle is the panel:

```dart
// A panel with space inside it.
SceneDecoratedBox3d(decoration: d, child: SceneContainer3d(padding: p, child: c));
// A panel with space around it.
SceneContainer3d(margin: m, child: SceneDecoratedBox3d(decoration: d, child: c));
```

Attach a `Layout3dController` to reach the surface imperatively: it hands back
the `Layout3dSurface` and its plane `Node`, which is what a raycast or a
hand-written transform needs. Anything below the root — a measured size, a
scroll position — is reached by keeping a reference to the object itself (a
`Scroll3dController` you passed in, say), not through the controller.

### Why the names carry both a prefix and a suffix

`Column3d` and `SceneColumn3d` are not two names for one thing. They are the
two layers, and the two affixes answer different questions:

* **`3d`** says *this is the three-dimensional counterpart of the Flutter
  class with the same name*. `Column3d` is to `Column` what `Constraints3d` is
  to `BoxConstraints`.
* **`Scene`** says *this is the widget that mounts the object named after it*.

The second is flutter_scene's own convention, not one invented here: `Node` is
the object and `SceneNode` is the widget that mounts it, and the same holds for
`Mesh`/`SceneMesh` and `Model`/`SceneModel`. `SceneColumn3d` parses exactly
like `SceneNode` — the widget for a `Column3d`. (A handful of flutter_scene
types carry the prefix for a different reason: `ScenePointer` and
`SceneRaycastHit` are named for pointing *into a scene*, not for being
widgets.)

Dropping the suffix in the widget layer looks tidier until you write a line of
it. The value types cannot lose it — `Size3d`, `EdgeInsets3d`, `Alignment3d`
and `Axis3d` are the arguments both layers take — so the affix does not go
away, it only stops being regular:

```dart
ScenePadding3d(padding: EdgeInsets3d.all(0.2), child: SceneColumn3d(...))
ScenePadding(padding: EdgeInsets3d.all(0.2), child: SceneColumn(...))   // less
```

## Wrapping

`Wrap3d` is what a flex is not: given more children than fit, a `Row3d`
overflows, a wrap breaks. Children run along `direction` until the next one
would not fit and then a new run starts, offset across the first cross axis,
which is Flutter's algorithm unchanged.

The third axis is where 3D asks a question Flutter does not have to answer.
A wrap could break into layers as well as runs; this one does not. The second
cross axis is an *alignment* axis: every child sits in the depth the thickest
of them needs, placed by `depthAxisAlignment`. Runs stack on one axis only,
so a wrap of models stays a readable plane of them rather than a cloud.

```dart
Wrap3d(
  spacing: 0.1,
  runSpacing: 0.15,
  children: [for (final model in models) SizedBox3d.cube(0.4, child: ...)],
)
```

## Building from the room you got

Three boxes hand the decision back to you when the algebra of rows, stacks and
wraps does not have the shape you want.

`LayoutBuilder3d` builds a *different subtree* depending on the constraints it
was given, which is what a responsive component is made of: show the label
only if it fits, put the navigation at the side of a wide panel and along the
bottom of a narrow one.

```dart
SceneLayoutBuilder3d(
  builder: (context, constraints) => constraints.maxWidth > 6
      ? SceneRow3d(children: [rail, body])
      : SceneColumn3d(children: [body, bar]),
)
```

The builder runs *during* the layout pass, which is the same window a lazily
built list inflates its items in: the surface lays out inside a Flutter layout
callback, and inserting render objects below the box that opened one is
exactly what it permits. Two consequences follow. A builder must not have side
effects on the tree above it — no `setState` on an ancestor from inside one —
because the pass is already past that point. And an intrinsic query is
refused, because it asks how big this box would be under constraints it has
not been given, and answering would mean building a subtree nobody is going to
lay out. When the constraints change, the child is reconciled rather than
rebuilt from nothing, so state, focus nodes and painters below it survive a
resize.

`CustomMultiChildLayout3d` is the other escape hatch: children tagged with
`LayoutId3d`, and a `MultiChildLayout3dDelegate` that lays each one out and
positions it by name. It is what a `Scaffold3d` is — the body gets the room
the bar left over — and the delegate API is Flutter's, with `Size3d`,
`Offset3d` and `Constraints3d` substituted.

`Flow3d` is cheaper here than in Flutter. Its delegate places children by
writing *node* transforms rather than by laying anything out, so an
arrangement can animate every frame — a menu fanning out, a carousel curving
toward the back of the plane — without a box being measured again. It is the
one box where a node transform is taken account of by a ray, and deliberately
so: in a flow, layout put every child at the origin corner, and the
delegate's transform is the child's real position, so a ray that ignored it
would always find the last child.

## Scrolling

There is no clipping here, which is the first thing to know. A scene has no
scissor rectangle to hide content behind, so a scrolling view hides what leaves
its window by making the node invisible, one whole child at a time. `ListView3d`
and `GridView3d` do that; `Viewport3d`, which slides a single child, does not —
its child is one node, and half a node cannot be hidden. A tall child in a
`Viewport3d` therefore stands out through the ends of the window. Reach for it
when the content is a little longer than the plane, and for anything else reach
for a list.

`ListView3d` shows the window of its content at a `Scroll3dController`
offset. Built from an explicit list of children, every child is laid out and
the ones outside the window have their nodes hidden. `ListView3d.builder`
builds items on demand: with `itemExtent` nothing off-screen is ever built,
and without it items are measured once as they are first scrolled past, with
the total extent estimated from the average, the same approximation
`SliverList` makes.

The declarative layer has the same two shapes. `SceneListView3d(children: ...)`
builds every child when the enclosing widget builds; `SceneListView3d.builder`
builds an item when the window reaches it and lets it go when the window and
its cache have left it, and so do `SceneGridView3d.builder`,
`SceneSliverList3d.builder` and `SceneSliverGrid3d.builder`. A built item is an
ordinary widget in an ordinary element tree — it reads inherited state, keeps
its own `State`, and rebuilds on its own — which is the whole point: a long
list of stateful rows is not expressible with a `Layout3dItemBuilder`, because
that hands back a layout object rather than a widget.

```dart
SceneListView3d.builder(
  itemCount: rows.length,
  itemExtent: 0.6,
  itemBuilder: (context, index) => SceneContainer3d(
    padding: const EdgeInsets3d.all(0.05),
    child: SceneText3d(rows[index].label),
  ),
)
```

Two things to know about a built item. It is **not kept alive**: scrolling far
enough disposes it and its `State` goes with it, so anything that has to
survive that belongs outside the list (Flutter's `KeepAlive` has no
counterpart here yet). And each item has to resolve to a layout — a
`Scene*3d` widget, under as many builders, providers and stateful widgets as
you like — because what the list places is a box on the plane; a Flutter
`Text` in there is an error rather than a silently empty row. There is no
widget form of `prototypeItem`, either: a prototype is measured without being
mounted, and a widget cannot be laid out without being in the tree, so state
the `itemExtent` when you know it.

A list needs a bounded extent **across** its scroll axis, because that is what
it gives an item to span, and it says so rather than guessing. A camera-bound
surface bounds every axis for you, which is the easiest way to stop hearing
about it; see *How the plane gets a screen* above. Along the scroll
axis it needs nothing: with no window to fill it is as long as its content and
has nothing left to scroll. That matters here more than it does in Flutter,
where the screen bounds everything: a `Layout3dSurface` is unbounded on all
three axes unless you say otherwise, so a list on a bare surface has to be
given a size somewhere — `constraints:` on the surface, or a `SizedBox3d`
around the list.

```dart
Layout3dSurface(
  // Without this the list has no width to hand its items, and says so.
  constraints: Constraints3d.tight(const Size3d(0.8, 1.3, 0.3)),
  child: ListView3d(children: cards),
)
```

Neither view is a layout of its own kind. A `ListView3d` *is* a scrolling
window over a single `SliverList3d`, and a `GridView3d` over a single
`SliverGrid3d`, which is the shape Flutter's are: there is no `RenderListView`
in Flutter, and a `ListView`'s items are placed by a `RenderSliverList` inside
a `RenderViewport`. So where an item goes is decided in one place rather than
copied into two. It changes nothing a caller writes — `children`, `add`,
`remove`, `itemCount` and `refresh` still mean the items, and a hit still finds
the list itself as its `Scrollable3d` — and it shows only if you go looking, in
`list.sliver` and in the extra node a ray passes through on its way in.

One consequence is worth stating, because it is the one thing that changed with
it: `cacheExtent` decides what is *built and kept*, not what is drawn. An item
inside the cache but outside the window is ready for the scroll that reaches
it, and hidden until then, the same division Flutter makes between laying a
child out and painting it.

That estimate is worth avoiding, and `prototypeItem` is the way to avoid it
without knowing anything the content does not already tell you. The items of a
long list are usually all the same size, but that size often comes from the
model inside them rather than from a number you can write down. So write down
an item instead: the list builds one, lays it out, and uses its extent for
every item there is.

```dart
ListView3d.builder(
  itemCount: 5000,
  prototypeItem: () => NodeBox3d(content: sampleCard),
  itemBuilder: (index) => NodeBox3d(content: cards[index]),
)
```

Every offset is arithmetic again, exactly as it is with `itemExtent`. The two
are answers to the same question — how long is an item — so a list takes one of
them, never both. The prototype is measured and never shown: it is not one of
the items, its node never enters the scene, and it is measured again only when
the room an item gets changes. *Slivers*, below, spells out what all this
saves you from.

`GridView3d` lays cells out on a grid a `Grid3dDelegate` decides from the room
across the scroll axis — `Grid3dDelegateWithFixedCrossAxisCount` for "three
across", `Grid3dDelegateWithMaxCrossAxisExtent` for "as many as fit under this
size". Because every cell position is arithmetic, `GridView3d.builder` is
*exactly* lazy: it knows the total extent of ten thousand cells without
building one, where a list of free-sized items can only estimate.

```dart
GridView3d.builder(
  gridDelegate: const Grid3dDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    crossAxisSpacing: 0.08,
    mainAxisSpacing: 0.08,
  ),
  itemCount: models.length,
  itemBuilder: (index) => NodeBox3d(content: models[index], fit: BoxFit3d.contain),
)
```

Cells are tight across both grid axes and take the depth available, with
`depthAxisAlignment` placing a shallower child inside it — so models of
different thicknesses line up on whichever face you pick.

### Physics, flings, and going somewhere

`Scroll3dController` holds the position; **what happens at the ends and what a
release does with its speed** is `Scroll3dPhysics`. `ClampingScroll3dPhysics`
is the default and stops dead at the ends, Android-style;
`BouncingScroll3dPhysics` lets the position be pulled past them, damping the
drag further and further out, and springs back on release.

```dart
final scroll = Scroll3dController(physics: BouncingScroll3dPhysics());
```

`Layout3dPointer` tracks the pointer's speed on the grabbed view's own plane
and hands it to the physics when the press lifts, so **a release flings**. It
needs honest timestamps to do that: pass `timeStamp:` to `down`, `move` and
`up` if you have the platform's, and it falls back to a wall clock if you do
not. A whole drag inside one millisecond — which is what a synthesized one
looks like — releases at rest rather than throwing the list across the room.

The imperative half is `animateTo`, `fling` and `ensureVisible3d`. None of
them is a gesture, so none of them waits on the question of what a gesture
means in a scene:

```dart
await scroll.animateTo(0, duration: const Duration(milliseconds: 300));
await ensureVisible3d(focusedBox, duration: const Duration(milliseconds: 200));
```

`ensureVisible3d` finds the nearest enclosing view itself, and by default
scrolls **as little as it can**: a box already in the window does not move,
and one that is not is brought just inside the nearer edge. That is what focus
traversal wants. Pass `alignment:` — `0.0` leading, `1.0` trailing, `0.5`
centred — when you want it put somewhere specific instead.

Because a controller is a plain `ChangeNotifier` with no element behind it, it
has nowhere to get a `TickerProvider` from. Give it one (`vsync:` on the
constructor, on the property, or on the individual call) whenever there is a
`State` in the picture, so `TickerMode` can mute the animation with the route
it is on; without one it makes a bare `Ticker`, which works and simply cannot
be muted.

Two numbers on the controller are worth knowing about. `overscroll` is how far
past an end the position is, which under a bouncing physics is what an
overscroll *effect* should be driven from — and in a scene that need not be a
glow, because you can bend, tilt or compress the content instead, on the
node-only path described under *Animation*. `userScrollDirection` is which way
the viewer is moving it, idle for a programmatic jump; that is what stops a
floating header unrolling because a spring, rather than a finger, carried the
offset backwards.

Anything else — a thumbstick, a wheel, a scripted camera move — drives
`Scroll3dController.offset` directly, or `applyUserOffset` if it wants the
physics applied to it as though it were a finger.

A `PageView3d` is a list with two things decided for it: every item is exactly
as long as the window, and the release settles on an item boundary instead of
wherever friction left it. The snapping is `PageScroll3dPhysics`, which the
view puts on the position it creates for itself; hand it a controller of your
own and the physics is yours to choose. The stride is the window by default,
and stating one — `PageScroll3dPhysics(pageExtent: cardExtent + spacing)` —
snaps a plain `ListView3d` to something that is not a whole page, which is how
a carousel with peeking neighbours is built.

## Slivers

The box protocol cannot answer the question a long list asks. A box is handed
a size and gives one back; that is the wrong shape for "there are ten thousand
of these and you can see nine". So there is a second protocol, the same one
Flutter reaches for: a **sliver** is handed a *window* — how far it has already
scrolled past, how much of the viewport is still unfilled — and reports what it
filled.

```dart
CustomScrollView3d(
  controller: scroll,
  slivers: [
    SliverToBoxAdapter3d(child: NodeBox3d(content: title)),
    SliverGrid3d(gridDelegate: threeAcross, children: thumbnails),
    SliverList3d.builder(itemCount: 5000, itemExtent: 0.4, itemBuilder: row),
  ],
)
```

This is the protocol the list and the grid are built on — each is one of these
views holding one sliver — and what it buys over them is the thing neither can
do: **several sections on one scroll position**. A header, a grid and a list
scroll together as one surface, each asked only about the part of the window it
can see. `SliverToBoxAdapter3d` is the glue — everything else in this package is a
box, and that is how a box takes its turn.

`SliverConstraints3d` and `SliverGeometry3d` are the two halves. The names keep
Flutter's spelling, `paintExtent` included, even though nothing here paints:
the quantity is the same one, and porting sliver code is easier when the words
match. Read "paint" as "the part of the window the viewer can see".

A sliver is still a `Layout3d`. It owns a scene node, it is placed by the
viewport, and it is hit-tested like anything else; its box is the part of it
the viewer can actually see, derived from the geometry it reported. Writing one
means extending `Sliver3d` and setting `geometry` in `performSliverLayout`,
where `constraints.paintPortion` and `constraints.cachePortion` do the
arithmetic. `scrollOffsetCorrection` is honoured: a sliver that discovers
mid-layout that the content is not where the offset assumed can move the
viewport and have the pass run again.

That last one is a facility for slivers you write; none of the built-in ones
use it. They do not need to: a list here measures forward from its first item
and keeps the running total, so where an item sits is always exact and nothing
ever has to be walked back.

What that costs is worth knowing before you build a long list of unequal items.
`SliverList3d.builder` without an `itemExtent` knows the length of the part it
has measured and guesses the rest from the average, so the *reachable range*
moves as you scroll: the end recedes if the early items were short, and pulls
in — taking the position with it — if they were long. And because the running
total starts at the first item, scrolling straight to the middle of a long list
measures everything before it in one pass; in debug, a pass that measures more
than five hundred items only to throw them away again says so rather than
merely dropping a frame. (Measuring hundreds of items the window then *shows*
is not that, and passes quietly.)

Both symptoms come from one gap — the list cannot know how long an item is
without building it — so both close the moment you fill it. A `prototypeItem`
fills it from the content, an `itemExtent` fills it from a number you supply,
and either turns the length into arithmetic: the range stops moving and jumping
anywhere costs nothing. Both are on `SliverList3d` and `ListView3d` alike.

For a list whose items genuinely do differ, there is a smaller answer.
`contentExtentEstimator` is a callback taking the item count and returning the
total extent, for an application that knows the real total because it knows the
data. Offsets stay measured, and exact; what stops moving is the range:

```dart
SliverList3d.builder(
  itemCount: chapters.length,
  contentExtentEstimator: (count) => library.totalHeight,
  itemBuilder: (index) => chapterCard(chapters[index]),
)
```

### Persistent headers

A `SliverPersistentHeader3d` is a section that stays at the leading edge while
the rest scrolls past it, shrinking as it goes: the sliver a `SliverAppBar` is
built on. Its content comes from a delegate, which states how tall the header
is at rest and how far it may collapse, and builds the content for a given
*shrink offset*:

```dart
class _Bar extends SliverPersistentHeader3dDelegate {
  _Bar(this._panel, this._metrics);

  final DecoratedBox3d _panel;
  final Layout3dMetrics _metrics;

  // Both extents are along the scroll axis, in layout units, so a bar stated
  // in logical pixels converts through the tree's metrics.
  @override
  double get minExtent => _metrics.dp(64);

  @override
  double get maxExtent => _metrics.dp(180);

  @override
  Layout3d build(double shrinkOffset, {required bool overlapsContent}) {
    // One subtree, told what the scroll position did to it.
    _panel.decoration = overlapsContent ? _raised : _flat;
    return _panel;
  }

  @override
  bool shouldRebuild(_Bar old) => !identical(old._panel, _panel);
}

CustomScrollView3d(
  slivers: [
    SliverPersistentHeader3d(delegate: _Bar(panel, metrics), pinned: true),
    SliverList3d.builder(itemCount: 500, itemBuilder: row),
  ],
)
```

`pinned` keeps the header on the leading edge once it has collapsed, `floating`
brings it back as soon as the viewer scrolls the other way, and both together
do both. The protocol carries them the way Flutter's does: `overlap` on
`SliverConstraints3d` is how much of a sliver's leading edge an earlier sliver
is already sitting on, `paintOrigin` on `SliverGeometry3d` is where a sliver's
visible part sits relative to where it was laid out, and
`maxScrollObstructionExtent` is how much of the window a pinned bar will never
give back.

**Build is called on every layout**, which while scrolling is every frame. The
delegate is expected to keep one subtree and hand the same instance back — the
header adopts what it is given only when it is not what it already holds, and
disposes what it drops. A delegate that returns a fresh subtree per frame will
build and dispose geometry at frame rate.

The part that is not a port is what "under the bar" means. In two dimensions a
pinned bar paints over the rows and the viewport clips them, so a row half
under the bar shows its bottom half. Here the row is geometry in front of
nothing, and left alone it draws straight through the bar. Two mechanisms
answer that, and a pinned header wants both:

* **The header is lifted toward the viewer** by `lift`, one logical pixel by
  default, so content passes *behind* it. It is written to the scene node
  alone — `ParentData3d.sceneOffset`, the same trade `Stack3d.depthStep`
  makes — so the header's box does not move and hit testing is untouched. For
  an opaque bar spanning the cross axis this is already the 2D picture.
* **The viewport publishes a clip plane** at the trailing edge of whatever a
  pinned header is obstructing, which reaches the content through
  `Layout3d.clipRegion`. That is what cuts a row *in half* at the bar's edge:
  culling can only hide a whole row, and a clip box would also cut the row off
  at the far edge of the window, which is a different decision. A material
  that reads clip planes honours it — a `BoxDecoration3d` does — and one that
  does not is still behind the bar rather than through it.

A ray aimed at the bar finds the bar. The viewport hit-tests its slivers in
scroll order, first one first, because a viewport's leading children are in
front rather than beside; Flutter's orders them the same way and for the same
reason.

## Measuring

Layout answers one question: *given this much room, how big are you?* A box
sometimes needs the other one — *how much room would you like?* — and asking
it is a protocol of its own, Flutter's, with the axis moved into the argument
list:

```dart
column.getMaxIntrinsicExtent(Axis3d.horizontal);          // how wide it wants to be
column.getMinIntrinsicExtent(Axis3d.horizontal, limits);  // ... and the least it can live with
```

Flutter has four methods, one per axis and bound. Three axes would make six,
so the axis is a parameter instead, and the `Size3d` beside it carries what
the box would be offered on the *other two*. Its component along the queried
axis is the thing being asked about, and is ignored.

The answers come from the leaves. A `NodeBox3d` reports the extent of the
content it holds and a `Text3d` reports what its string needs (the widest
unbreakable word as the minimum, the whole string on one line as the maximum),
which are real measurements of real content; every box
above it either adds to that (`Padding3d` its insets, `Container3d` its
padding and margin) or holds it down (`SizedBox3d` its fixed extents, without
even asking the child), and a `Column3d` adds its children up along its axis
and overlaps them across it.

`IntrinsicWidth3d` — with `IntrinsicHeight3d` and `IntrinsicDepth3d` for the
other two axes — is what the question is usually for. It asks its child what
it wants and then hands it exactly that, tightly:

```dart
IntrinsicWidth3d(
  child: Column3d(
    crossAxisAlignment: CrossAxisAlignment3d.stretch,
    children: cards,   // every card as wide as the widest one
  ),
)
```

It is expensive, for the reason it is expensive in Flutter: answering walks
the whole subtree, and then the subtree is laid out again for real. The answer
is cached until the box next goes dirty, and a box whose answer was taken
pushes its dirt up *past its own relayout boundary*, because a parent decided
something from a number that has just gone stale. Scrolling views refuse the
question outright, as Flutter's viewport does: a list's content is whatever
length it is, and the list exists so that it need not grow to match.

### Baselines

A baseline is a line content declares so that its neighbours can line up on it
instead of on their edges. Flutter has one, running across a box at the foot
of its text. Here a box can declare one on any axis, because there are three
ways to stand side by side.

`Text3d` states a real one — the first line's alphabetic baseline, along the
vertical — so two labels of different sizes in a baseline-aligned row sit on
the same line without being told anything:

```dart
Row3d(
  crossAxisAlignment: CrossAxisAlignment3d.baseline,
  children: [
    Text3d('Title', style: const TextStyle(fontSize: 20)),
    Text3d('new', style: const TextStyle(fontSize: 11)),
  ],
)
```

Nothing else in a scene reports one, because a model has no notion of where
its text sits. `Baseline3d` is what states one by hand:

```dart
Row3d(
  crossAxisAlignment: CrossAxisAlignment3d.baseline,
  children: [
    Baseline3d(baseline: 0.4, child: NodeBox3d(content: title)),
    Baseline3d(baseline: 0.4, child: NodeBox3d(content: badge)),
  ],
)
```

Both children now hang from `y = 0.4` whatever their own extents, and the row
is as thick as the deepest baseline plus the most that hangs below one, which
is generally more than its thickest child. A child with no baseline sits at
the start of the line, exactly as in Flutter. Which cross axis the alignment
applies to is the usual rule — `crossAxisAlignment` is the first cross axis
and `depthAxisAlignment` the second — so a `Row3d` can carry a line on `y` and
another on `z` at the same time.

## Pointing at it

Hit testing is the other half of the protocol, and it is where three
dimensions change the shape of the question. Flutter walks the tree with a
point, because a screen is flat. Here the pointer is a direction from the
camera and the boxes stand at different depths, so what walks the tree is a
**ray**:

```dart
final ray = camera.screenPointToRay(event.localPosition, viewSize);
final hit = surface.hitTestRay(ray);

hit.target;                    // the deepest box the ray reached
hit.path;                      // it and its ancestors, out to the surface
hit.firstOf<Scrollable3d>();   // the list the finger landed in, if any
```

The surface's node already carries the basis, so inverting its world
transform lands the ray in layout space and everything below is plain layout
arithmetic. `hitTestAt` asks the same question with a point on the plane, for
when the pointer has already been resolved to a spot on it.

The rules are Flutter's, one axis richer. Children are tested last-to-first,
so the box on top wins. A ray that misses a box never reaches its children,
and **the stretch of the ray inside a box is all its children can be found
in** — the 3D form of the `size.contains(position)` gate, and what keeps a
list item scrolled out of the window unreachable. A box that only arranges
others is not itself a target; `NodeBox3d` and the scrolling views are.
`IgnorePointer3d` takes a subtree out of reach, `AbsorbPointer3d` stands in
front of it. A hidden node is never hit.

`Transform3d` is the deliberate exception: it neither answers hits itself nor
gates them on its own extent, because its size is measured in the frame
*before* the transform. Flutter's `RenderTransform` makes the same choice for
the same reason.

### From a hit test to an event

`Layout3dPointer` is what turns rays into events. Feed it the rays your host
makes and it hit-tests, captures the path, dispatches along it, recognizes
gestures, tracks hover, and drags whatever scrolling view it grabbed:

```dart
final pointer = Layout3dPointer(surface);

Listener(
  onPointerDown: (e) => pointer.down(rayFor(e), pointer: e.pointer),
  onPointerMove: (e) => pointer.move(rayFor(e), pointer: e.pointer),
  onPointerUp: (e) => pointer.up(pointer: e.pointer),
  onPointerHover: (e) => pointer.hover(rayFor(e), pointer: e.pointer),
  onPointerCancel: (e) => pointer.cancel(pointer: e.pointer),
  child: SceneView(scene, camera: camera),
)
```

Every state it keeps is keyed by that `pointer` id, so two fingers drive two
lists independently and a mouse and a controller can coexist.

A press hit-tests once and **captures the path**. Every later event of that
sequence goes to the boxes that path recorded, whether or not the pointer is
still over them — the ordinary capture rule, and the reason running off the end
of a list does not drop the drag. Each box on the path that implements
`HitTestTarget3d` is handed the event, deepest first.

`Listener3d` is the box that reports events as they come (`onPointerDown`,
`onPointerMove`, `onPointerUp`, `onPointerCancel`, `onPointerHover`, and —
folded in from `MouseRegion`, since hover here is a walk of the same path —
`onPointerEnter` and `onPointerExit`). What it hands you is a `PointerEvent3d`,
which carries two positions and means both:

* `localPosition`, in **world units** on the box's own plane, worked out by
  intersecting the ray with the plane the press landed on. It stays exact at
  any viewing angle, and it keeps tracking after the pointer has left the box.
* `event`, a real Flutter `PointerEvent` in **logical pixels**, through the
  tree's `Layout3dMetrics`.

The second is what makes the rest possible. Flutter's gesture recognizers are
tuned in logical pixels — `kTouchSlop` is 18 of them — so a synthesized event
measured in world units would put the slop most of a panel away. Measured in
dp on the plane, the constants mean what they say, and the recognizers can be
used exactly as they are.

### Claiming the target

By default a box that merely arranges others is not a target, so the padding
that gives a button its shape is a hole. `HitTestBehavior3d` closes it, on
`Listener3d`, on `GestureDetector3d`, or on a bare `HitTestArea3d`:

```dart
HitTestArea3d(                       // opaque: the whole face is the target
  child: Padding3d(
    padding: EdgeInsets3d.symmetric(horizontal: metrics.dp(24)),
    child: IgnorePointer3d(child: Text3d('Continue')),
  ),
)
```

The `IgnorePointer3d` is the usual companion: a `Text3d` answers hit tests on
its own account, and a component that wants to be one target takes its label
out of the way. `translucent` is the third setting — the box hears the pointer
and the ray carries on to whatever stands behind it.

`TapTarget3d` is the other direction: Material's rule that anything pressable
is at least 48dp across, without spending layout on it. The box stays its
child's size and its neighbours stay put; it simply answers a ray that passes
within half the shortfall. So a 24dp icon in a dense toolbar is a 48dp target
and the toolbar is still dense.

### Gestures, and the arena

`GestureDetector3d` owns Flutter's own recognizers and hands them the
synthesized events:

```dart
GestureDetector3d(
  onTapDown: (_) => panel.stateLayer = pressed,
  onTapCancel: () => panel.stateLayer = StateLayer3d.none,
  onTap: submit,
  child: panel,
)
```

The arena is Flutter's too, and it has to be: a `GestureRecognizer` reaches for
`GestureBinding.instance` itself and cannot be pointed at a private router.
What is private is the *pointer id* — each sequence is given one well above the
range the engine hands out, so a gesture on the plane cannot collide in the
arena with the real pointer that produced it, which the widget tree around the
`SceneView` is still handling. A tree with a `GestureDetector3d` in it
therefore needs the binding initialized: `runApp` has done it already, and a
test wants `TestWidgetsFlutterBinding.ensureInitialized()`.

Because the arena is the real one, a tap on a list item and a drag of the list
it sits in disambiguate exactly as they do on a screen. A scrolling view enters
the arena as a competitor **only when something else is competing for the same
press**: with nothing in the path but the list, the content moves from the
first move, as it always has; with a recognizer armed, the view waits out the
touch slop and then claims the pointer, which cancels the pending tap. Either
way the drag itself is still measured on the grabbed view's own plane rather
than across the screen, so the content stays under the finger at any viewing
angle. A release throws the list: the pointer tracks its speed on that plane
and hands it to the view's `Scroll3dPhysics`. See *Physics, flings, and going
somewhere* above.

`details.localPosition` on a recognizer's callbacks is in dp in the box's own
frame, exact for a box parallel to the surface, which every box is unless a
`Transform3d` turned one. A control that needs the exact point at any angle
reads `PointerEvent3d.localPosition` from a `Listener3d` instead.

### Hover, and state layers

`hover(ray)` walks a fresh hit test and diffs it against the path that pointer
was on last time, sending `onPointerExit` to what it left, deepest first, and
`onPointerEnter` to what it entered, outermost first — so a card knows before
its label does. `exit()` takes the pointer off the surface entirely.

That is what drives `DecoratedBox3d.stateLayer`, and neither end of it touches
layout: the enter and exit are a walk of a recorded path, and setting a state
layer writes one uniform and asks for a frame.

```dart
Listener3d(
  behavior: HitTestBehavior3d.opaque,
  onPointerEnter: (_) => panel.stateLayer = hovered,
  onPointerExit: (_) => panel.stateLayer = StateLayer3d.none,
  child: panel,
)
```

### Focus

`Focus3d` ties a Flutter `FocusNode` to a box. The node graph is Flutter's
unchanged — listen to the node, hand it to `Shortcuts` and `Actions`, ask it
for `hasPrimaryFocus` — and what the box adds is *which geometry* the focus
belongs to, so a highlight can be drawn on it and traversal can reason about
where it is. A press inside one focuses it, which on a plane nothing else
would do; a component that only wants a focus ring for keyboard use should
consult `FocusManager.instance.highlightMode` before drawing one, as Material
does.

The nodes hang under a scope of the surface's own, `Layout3dOwner.focusScope`,
created and parented under the application's root scope the first time
something on the surface asks for focus — a scene nobody has touched does not
take the keyboard from the widgets around it. That scope skips Flutter's
traversal deliberately, because Flutter's policies read a `Rect` off a
`RenderObject` and a box on a plane has neither.

A modal wants its own scope, and `FocusScope3d` is it: wrap a subtree in one
and everything inside asks *that* scope for focus rather than the surface's,
so a dialog cannot hand focus to the page behind it. `Focus3d.enclosingScope`
is the walk that finds it, and `Overlay3dEntry` puts one in for you when the
entry is modal.

Traversal inside a surface is `Focus3dTraversal`: `next` and `previous` walk
tree order, and `inDirection` projects every candidate onto the surface plane
and picks the way a reader would — a box sharing the source's band first, and
the nearest of those. Every method takes the root to search from, which is
where trapping lives: `Focus3dTraversal.traversalRootFor(box)` gives the
nearest enclosing `FocusScope3d`, or the root of the tree when there is none,
so a `Tab` handler written against it walks the dialog while a dialog is up
and the whole page when it is not. It is a first cut, and it is honest about
being one: it is right for a screen of controls on one plane, and it says
nothing about content facing different ways, or about traversal *between*
surfaces, which stays open now that detached overlay entries have made a
second surface a real thing.

All five of these boxes have widget forms, like every other layout here:
`SceneListener3d`, `SceneGestureDetector3d`, `SceneHitTestArea3d`,
`SceneTapTarget3d` and `SceneFocus3d`.

## Overlays: what "in front" means

A dialog, a menu, a snack bar and a tooltip are one mechanism wearing four
coats: put something above everything else, possibly outside the bounds of
whatever asked for it, dismissible from outside. `Overlay3d` is that
mechanism. It is a stack whose ordinary children are the base content and
whose *entries* are what has been put in front, last one nearest the viewer,
inserted from anywhere at any time — a dialog opened from a button's callback
is not part of that button's subtree, and outlives it.

```dart
final overlay = Overlay3d(children: [page]);
surface.child = overlay;

late final Overlay3dEntry entry;
entry = Overlay3dEntry(
  modal: true,
  onDismiss: () => entry.remove(),
  builder: (_) => Container3d(
    size: const Size3d(1.2, 0.8, 0.05),
    decoration: panelDecoration,
    child: Text3d('Delete this?', renderer: renderer),
  ),
);
overlay.insertEntry(entry);
```

A descendant finds it without being handed anything: `Overlay3d.of(box)` walks
up the layout tree, and `SceneOverlay3d.of(context)` does the same through the
element tree in the declarative layer.

In two dimensions "in front" needs no explanation — later paints over earlier.
On a plane it needs two, and which one is right depends on the dialog, so it
is chosen per entry through `Overlay3dEntry.layer`.

**In plane** is the default and the cheap one. The entry is a child of the
overlay, laid out against the overlay's own constraints, and its *geometry* is
pulled toward the viewer so it does not fight the panel for the depth buffer.
The lift is written to `ParentData3d.sceneOffset`, the same mechanism
`Stack3d.depthStep` uses, which is why it moves the geometry and nothing else:
the entry's box stays where the overlay put it, a `Positioned3d` inside it
still pins to the face it named, and a ray still finds the entry by its place
in the stack rather than by how far it was lifted. One surface, one layout
pass, hit ordering already correct. The limits are real: the entry cannot
escape the overlay's box, so a menu cannot overhang the panel's edge, and the
lift spends the panel's own thickness. It defaults to eight logical pixels
taken through the tree's metrics, because a separation stated in world units
is the wrong separation at another density.

**Detached** gives the entry a `Layout3dSurface` of its own, hung under the
overlay's node so it still follows the panel when the panel turns, and
bindable to a camera on its own account. That second half is the thing Flutter
has no analogue of: with `OverlayLayer3d.detached(binding:
Layout3dCameraBinding.billboard())` the dialog faces the viewer while the
panel behind it stays angled, and `Overlay3d.updateCameraBindings` — driven
per frame, or by `SceneOverlay3d` off the scene's own clock — is what keeps it
there. Its constraints are derived from the host by default: as wide and as
tall as the overlay, and *unbounded in depth*, because escaping the panel's
depth budget is half the reason to detach at all.

A detached entry is a second surface, and a ray only ever visits one surface
at a time. `Layout3dPointerGroup` is what routes across them: it tests
front to back — by an explicit z-order, ties broken by distance from the
camera when it has one — and stops at the first surface that answers. A
surface added with `absorbs: false` is dispatched to and the walk carries on,
which is what a HUD that must not block the world wants. A press captures the
surfaces that answered it, so sliding a drag off the dialog and onto the panel
behind does not hand the drag over. `group.syncDetachedEntries(overlay)`
keeps the group in step as dialogs open and close.

The barrier is `ModalBarrier3d`: it fills what it is given, answers every ray
itself — which is what stops one reaching the content behind — and calls
`onDismiss` when a tap both starts and ends on it, so a tap on the dialog does
not dismiss it. `Overlay3dEntry(modal: true)` puts one in. A scrim in a scene
is not an alpha wash over a display list, because there is no display list: it
is geometry, a slab you decorate, which is what the barrier's child is for.
Until a per-node opacity lands in the engine a genuinely translucent scrim is
not expressible, and a dark material or a dimming tint is the honest fallback.

A modal entry also traps focus, by wrapping its content in a `FocusScope3d`;
removing it hands focus back to whatever held it before.

`Navigator3d` is the thin route stack over all of it: `push` returns the
future the route's result arrives on, `pop` completes it, and
`Route3dTransition` is the seam an animation will fill — its `reverse` is
awaited before the entry is taken out, so a leaving route is on screen for the
whole of it. It is deliberately not wired into Flutter's own `Navigator`:
Flutter's overlay is a stack of `RenderBox`es and its routes build 2D widgets,
and there is no honest mapping. A 3D dialog opened from a 2D route, and the
system back button popping this stack, are not answered here — an application
that wants either pushes on this navigator from wherever it likes and calls
`pop` from its own `PopScope`.

One difference from Flutter's `Overlay` is worth stating plainly: an entry's
content is a `Layout3d` built by a callback, not a widget subtree. The layout
objects are the same ones the widgets drive, so nothing is out of reach; what
an entry does not get is reconciliation, so a component that changes its
dialog calls `Overlay3dEntry.markNeedsBuild`, which disposes the old subtree
and builds a new one in place.

## Dragging things around

Every drag so far has been a drag of the thing under the finger: a list moves
because the pointer grabbed it. A drag-and-drop is the other kind — it is
*defined* by moving away from what it started on and asking what is underneath
now — and that breaks the rule the rest of the pointer layer runs on, where a
press captures a path and every later event goes back along it.

So there is one piece of machinery, `Drag3dSession`, and four components over
it. The session is deliberately ignorant: it does not hit-test, does not own
the geometry under the finger, and never holds the box the drag started on.
What it keeps up to date is the answer to one question — *which drop targets
is this drag over, and which of them wants it* — and it dispatches the enter,
move, leave and drop that follow from a change to that answer.

```dart
Draggable3d<Photo>(
  data: photo,
  feedbackBuilder: (_) => Container3d(
    size: const Size3d(0.6, 0.4, 0.02),
    decoration: cardDecoration,
  ),
  child: thumbnail,
)

DragTarget3d<Photo>(
  onWillAccept: (photo, _) => photo.album != album,
  onEnter: (_, _) => panel.stateLayer = hovered,
  onLeave: (_, _) => panel.stateLayer = StateLayer3d.none,
  onAccept: (photo, _) {
    panel.stateLayer = StateLayer3d.none;
    album.add(photo);
  },
  child: panel,
)
```

The payload keeps its generic; the machinery does not see it. A drag is found
through a hit-test path of bare `Layout3d`s and may have to cross surfaces, so
the seam underneath is the non-generic `Drag3dTarget` — the same shape
`HitTestTarget3d` is under `Listener3d`. **The type test happens inside the
target**, where `DragTarget3d<T>` answers `willAcceptDrag3d` with
`details.data is T`, which is also where Flutter puts it. The practical value
is that a component can implement `Drag3dTarget` directly and be a drop zone
in four lines without inheriting a generic class it does not want. The
inherited cost is Flutter's too: a `DragTarget3d<Object>` accepts everything.

### It recognizes its own drag

Flutter's `Draggable` is built on `MultiDragGestureRecognizer`, and that is not
available here in any useful form: in this build `DragGestureRecognizer`
delivers `onStart` and nothing after it, and `LongPressGestureRecognizer` never
fires at all — both reproduced with no code from this package involved. So the
threshold is arithmetic and the delay is a plain `Timer`, and both compete in
the arena through `PointerSequence3d.addArenaMember`, which is a general seam
rather than a private one: anything that wants a pointer without a Flutter
recognizer — a knob, a slider, a rotation handle — reaches for it the same way.

`Drag3dStartMode.immediate()` claims on the first travel past the slop, which
is what a desktop drag and a dismissible row want;
`Drag3dStartMode.longPress()` starts a timer at the press, cancelled by travel
or by lifting. Give a draggable an `axis` and a row inside a list running the
other way stops fighting it: each claims on its own axis and the finger
decides.

One thing worth knowing before you build on the arena: **winning it is not
recognizing the gesture.** A member alone in the arena wins by default, in a
microtask, as soon as the pointer's arena closes — so a recognizer with a
threshold of its own has to keep the two apart, and this one does.

### The feedback is moved, never re-laid-out

At the moment a drag is recognized, the session builds
`Draggable3d.feedbackBuilder`'s subtree, wraps it in an `IgnorePointer3d`, and
puts it into the nearest `Overlay3d` above — in-plane by default, which is one
surface and one layout pass and already lifts the card toward the viewer;
`OverlayLayer3d.detached` is the opt-in for a drag that has to leave the panel
it started on.

After that, **every move writes one `Offset3d` onto the feedback's
`nodeOffset`.** Nothing is re-laid out, nothing is rebuilt, no uniform changes;
a drag at 120Hz costs one matrix write a frame. That is not an optimisation, it
is the rule [docs/traps.md](../../docs/traps.md) sets for anything on a
per-frame path, and a drag is the most per-frame path there is. A whole drag
touches the relayout path exactly twice — putting the feedback into the overlay
and taking it out — because an overlay entry is a child of a stack and adding a
child is a layout. There is no way around either, and the test suite asserts
`needsFlush` is false for every move in between.

Note *which* channel. `ParentData3d.sceneOffset` belongs to the parent, and
`Overlay3d` is a `Stack3d` whose `depthStep` rewrites it on every placement, so
an offset stored there is silently erased.

The correction that makes the feedback cover the card it came from is a
question about the **plane** only. Depth is the layer's business —
`OverlayLayer3d.lift` is what stands a picked-up card in front of what it is
carried over — and correcting depth as well would land the feedback exactly on
the source box and cancel it. The default lift is eight logical pixels, which
is a depth-buffer separation rather than a distance, so rows with real
thickness want a bigger one.

The `IgnorePointer3d` is mandatory rather than tidy. Hit testing deliberately
ignores `nodeOffset`, so feedback moved that way is invisible to the ray moving
it and cannot steal its own drop — but its *laid-out* position is still
hit-testable, and a `Text3d` inside it would answer there on its own account.

### Which target a drop lands on

The nearest acceptor along the ray: hit order within a surface, and the pointer
group's front-to-back walk between surfaces. The argument is consistency and
not much else, but consistency is enough — **a drop lands where a tap would
land**, and any other rule means the viewer cannot predict a drop from what
they already know about pressing.

Enter and leave go to *every* accepting target on the path, diffed against last
time, so a list and the row inside it both light up; only the drop is
exclusive. Across surfaces the search deliberately ignores capture: while a
session is live, `Layout3dPointerGroup` walks every member front to back rather
than only the ones that took the press, so a card picked up on a panel can be
dropped on a dialog in front of it. *Where events go* and *what the drag is
over* are two different questions, and conflating them is what makes a
drag-and-drop impossible.

Because a drop follows the ray, it inherits the depth-ordering trap: a drop
target thicker than the `Stack3d.depthStep` separating it from its neighbours
can win the ray while looking like it is behind. Keep drop targets thin
relative to the step. Feedback stays on the plane it was picked up from —
`Drag3dAnchor.targetPlane` is reserved and behaves as `originPlane`, and its
dartdoc says why the mechanism that was planned for it is the wrong one.

### Dismissible3d

The thinnest consumer, and the one that needs no drop target at all: an axis, a
fraction threshold, a fling threshold, a background, a secondary background,
and the resize-away that follows a confirmed dismiss.

The swipe itself is node-tier like every other drag here. The resize is the one
part that genuinely relayouts, because an extent really does change — but it
does not resize the child: the row has already been carried off the box and
hidden by then, so the child is laid out with the *same* constraints on every
tick (an identical layout call is one the child skips) and only the
dismissible's own extent shrinks. Nothing under the swiped row re-measures a
string.

Two shapes worth knowing. The three slots are one ordered child list
underneath — child, background, secondary background — because an ordered list
is what the declarative layer can mirror; the constructor asserts that a
background needs a child and a secondary background needs a background. And the
backgrounds are **coplanar** with the child: `backgroundDepthStep` defaults to
zero exactly as `Stack3d.depthStep` does, which is right for a flat Material
row and wrong the moment either has depth.

### Reorderable lists

`ReorderableList3d` is the viewport around a `SliverReorderableList3d`, exactly
as `ListView3d` is around a `SliverList3d`, so placement is not written twice.
Each item is wrapped in a `Draggable3d` of its own, which is how the whole of
the machinery above is bought rather than rebuilt.

```dart
ReorderableList3d(
  itemCount: photos.length,
  itemExtent: 0.4,
  itemBuilder: (index) => row(photos[index]),
  onReorder: (oldIndex, newIndex) {
    photos.insert(newIndex, photos.removeAt(oldIndex));
    list.refresh();
  },
)
```

**The child list is not reordered until the drop.** During the drag the dragged
item stays exactly where it is, hidden with `node.visible = false` — which
costs no layout — so its extent stays in the flow and *is* the gap, and every
other visible item is pushed aside by that extent with `nodeOffset`. That
answers two things at once: the lazy machinery is untouched, because the
index-to-child map never changes between the lift and the drop, and nothing
lands on the relayout path, because every visible change is a matrix write.

Two deliberate deviations from Flutter, both of which will bite a reader who
assumes otherwise:

- **`onReorder`'s `newIndex` is where the item ends up.** Flutter's
  `ReorderableListView` reports an index measured *before* the item is taken
  out, so a caller who moved something down the list has to decrement it
  first. That off-by-one is the most reported confusion about that widget and
  there was nothing to be gained by inheriting it.
- **There is no explicit-children constructor**, and **no
  `SceneReorderableList3d`.** `onReorder` hands back a pair of indices into the
  caller's data and expects the next build to reflect them, so the list has to
  be a function of that data to mean anything: `itemCount` and `itemBuilder`,
  and `refresh` when the data changes. The missing widget form is a harder
  story — the list wraps every item in a `Draggable3d`, and the declarative
  layer's contract is that `Layout3dChildManager.removeChild` is handed back
  the very layout `createChild` returned, which wrapping breaks. Closing it
  wants either a hook that lets a view adopt what the manager built or a
  recognizer on the list itself so items need no wrapper; both are more than a
  widget form deserves on its own, and neither has been built.

An item held at the edge of the window scrolls the list under it.
`Drag3dAutoscroll` says how deep the band is and how fast, in dp, and a
`ReorderableList3d` turns it on by default because a reorder is the case where
a drag has to be able to reach a slot that is not on screen; `Draggable3d`
leaves it off, as Flutter's `Draggable` does. It runs on a ticker rather than
on the move stream, because **a finger parked at the edge sends no move
events** — and the tick does not only scroll, it re-resolves the drag, because
the window moving under a stationary pointer changes which slot the item would
land in and nothing else would notice.

## Animation

Nothing in this package animates on its own, and everything in it is
animatable. The declarative layouts are ordinary Flutter widgets, so an
`AnimationController` driving `setState`, or an `AnimatedBuilder` around a
`SceneContainer3d`, works today; every value type — `Size3d`, `Offset3d`,
`EdgeInsets3d`, `Alignment3d`, `Constraints3d`, `BorderRadius3d`,
`BoxDecoration3d`, `StateLayer3d` — has a static `lerp`, and a `Tween` over
each of them (`Size3dTween` and friends) so the ordinary
`tween.animate(controller)` spelling works.

What matters here is *which* of three paths an animation takes, because they
differ by more than a constant factor. **Relayout cost compounds in three
dimensions**: a dirty box is measured again, and a box measured again may ask
a `Text3d` to shape a string or a decoration to rebuild geometry. Pick the
cheapest path the animation actually needs.

### Repaint only: a colour, a corner, an elevation

`DecoratedBox3d.decoration` and `.stateLayer` are setters that write shader
uniforms and **never touch layout**. A card whose colour crossfades, a button
whose elevation lifts, a control whose hover overlay fades in — all of that is
this path, and it costs nothing but the uniforms:

```dart
final tween = BoxDecoration3dTween(begin: resting, end: pressed);
controller.addListener(() => card.decoration = tween.evaluate(controller));
```

Note the `addListener`, not `setState`. Rebuilding the widget would put the
whole subtree back through layout to deliver a number the layout does not
read.

### Node only: a slide, a lift, a depression, a turn

Some animations move nothing in the layout. The box is exactly as big as it
was, its siblings are where they were, its children's offsets have not
changed — only where the geometry *is* has changed. Flutter has no cheap
answer for that; here it is one `Matrix4` on one scene node.

Every box has `Layout3d.nodeOffset` and `Layout3d.nodeTransform`: plain
setters that rewrite the node's transform and ask the host for a frame,
without calling `markNeedsLayout`. `NodeTransform3d` is the box that drives
them from an `Animation`, and `SceneAnimatedSlide3d` is its declarative
front:

```dart
SceneAnimatedSlide3d(
  duration: const Duration(milliseconds: 120),
  // Toward the viewer is negative depth.
  offset: pressed ? const Offset3d(0, 0, 0.01) : Offset3d.zero,
  child: button,
)
```

A target change costs one rebuild; the run costs one matrix a frame and
rebuilds nothing. Layout, intrinsics and hit testing never see it, which is
the point: a hover lift or a press depression should not move the thing you
are aiming at. `worldTransform` undoes the nudge for exactly that reason. If
the animation *should* carry the touch target with it, it is not this path —
animate a real inset with `SceneAnimatedPositioned3d` and pay for the
relayout.

This is the same distinction `ParentData3d.sceneOffset` draws for
`Stack3d.depthStep`, and the two compose. Use `nodeOffset` rather than
`sceneOffset` for an animation: `sceneOffset` belongs to the parent, and a
stack rewrites it on every placement.

### Implicit: a size, a padding, an alignment

When the layout really did change, `ImplicitlyAnimatedLayout3dWidget` is the
base and `SceneAnimatedContainer3d`, `SceneAnimatedAlign3d`,
`SceneAnimatedPositioned3d` and `SceneAnimatedSizedBox3d` are the widgets, all
with Flutter's `forEachTween` contract:

```dart
SceneAnimatedContainer3d(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  width: selected ? 2.0 : 1.0,
  padding: selected ? const EdgeInsets3d.all(0.2) : EdgeInsets3d.zero,
  child: label,
)
```

These dirty layout on every frame, and that is correct — the boxes really are
different sizes. It stays affordable because of two decisions made elsewhere
in this package: `Text3d` prepares a string once and refits it to any width
without consulting the font again, and `BoxDecoration3d` is a shader
parameterized by size rather than a mesh rebuilt at each one. **Both of those
guarantees are yours to lose.** Putting a new `Text3d.text`, a new
`NodeBox3d.content`, a rebuilt `GeometryBuilder` mesh, or a change to
`Layout3dSurface.metrics` on a per-frame path defeats them: the last one
relayouts the entire subtree by design, and belongs to a window resize, not
to a frame.

## Debugging what you cannot see

A layout on a plane produces no pixels of its own. Nothing draws a box, so a
wrong size, a padding applied to the wrong axis, or a child standing out
through the front of a panel are all invisible until the geometry looks odd,
and by then the symptom reads as a rendering artefact rather than as a layout
mistake. That is the reason this package carries a debugging story rather than
leaving it to the inspector: there is nothing on screen to inspect.

Every box is a `DiagnosticableTree`, so it dumps the way a render tree does:

```dart
surface.flush();
debugDumpLayout3dTree(surface);
```

```
Column3d#b0dd0
 │ constraints: Constraints3d(w: 4.0..4.0, h: 3.0..3.0, d: 1.0..1.0)
 │ size: Size3d(4.000, 3.000, 1.000)
 │ direction: vertical
 │ mainAxisAlignment: center
 │
 └─child: Padding3d#a16bc
   │ constraints: Constraints3d(w: 0.0..4.0, h: 0.0..Infinity, d: 0.0..1.0)
   │ size: Size3d(2.000, 2.000, 1.000)
   │ offset: Offset3d(1.000, 0.500, 0.000)
   │ padding: EdgeInsets3d(0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
   │
   └─child: SizedBox3d#dbb42
       constraints: Constraints3d(w: 0.0..3.0, h: 0.0..Infinity, d: 0.0..0.0)
       size: Size3d(1.000, 1.000, 0.000)
       offset: Offset3d(0.500, 0.500, 0.500)
```

Read it the way you read a render tree dump: constraints came down, sizes went
up, `offset` is where the parent put the box. A box that was never laid out
says `size: MISSING` and `NEEDS-LAYOUT` rather than printing a zero that looks
like an answer, which is the distinction a bare `Size3d` in a test failure
cannot make. `debugDescribeLayout3dTree` returns the same string without
printing it — a golden tree is a much better assertion than a size comparison,
because it says what went wrong — and `debugDescribeLayout3dAncestry` prints
the chain from one box up to the root, which is the list of suspects when a
box came out wrong.

Raising the level to `DiagnosticLevel.fine` adds the fields you only want when
something is not updating at all:

```dart
print(box.toStringShallow(minLevel: DiagnosticLevel.fine));
// … relayoutBoundary: "up2", sizedByParent, nodeOffset: …
```

`relayoutBoundary: "up2"` is the answer to *why did marking this box dirty lay
the whole plane out again*: dirt stops at the boundary, and this one is two
levels above. `nodeOffset` and `nodeTransform` show up here too, which is how
you tell a box the layout moved from a box an animation moved.

### The trap that used to be silent

The declarative layer mirrors the render tree onto the layout tree, and it
mirrors only the zero-sized hosts that carry a `Layout3d`. Most Flutter
widgets are transparent to that — a `StatelessWidget`, a `StatefulWidget`, an
`InheritedWidget`, a `Builder`, a `Consumer` create no render object, so their
children are still the host's children, and a component library depends on
that being true. But one ordinary `Padding`, `Opacity` or `SizedBox` reached
for out of habit *does* create a render object, and everything below it used
to vanish: no error, no layout, nothing in the scene.

It is now an error that names both ends of the problem:

```
A RenderPadding was placed between two 3D layout widgets.
The Padding widget creates a render object of its own, so everything below
it — starting with SizedBox3d — is not part of the layout tree at all.
Only widgets that create no render object may sit between two 3D layout
widgets … For layout, use the 3D widget with the same name —
ScenePadding3d for Padding, SceneSizedBox3d for SizedBox.
```

### Overflow, and why depth is the one that bites

A box whose content did not fit reports it. `Flex3d` reports the children it
could not fit on any of the three axes, and `UnconstrainedBox3d` reports a
child it measured without limits and then could not hold — the same two places
Flutter draws its yellow-and-black stripes, for the same reasons.

Depth is why this matters more here than in Flutter. A row 40 pixels too wide
is at least visibly clipped; a card whose content is a millimetre too deep is
a chip floating out of the front of it, and nothing about that looks like an
overflow. So the report names the edge the content came out of, `back`
included:

```
A Depth3d overflowed the back by 3.000.
```

Reports go through `FlutterError.reportError` by default, so an overflow fails
a `flutter_test` run like any other layout error. Point
`debugLayout3dOverflowReporter` somewhere else to collect them instead — a
test that means to overflow, a debug HUD that lists what did — and read
`Layout3dOverflowReportingMixin.debugOverflow` for the current amount on a
box. The same overflow is reported once rather than on every frame, so a list
flung past an overflowing row does not fill the console. Mix
`Layout3dOverflowReportingMixin` into a layout of your own and call
`debugReportOverflow` from `performLayout` to join in.

### Drawing the boxes

`debugPaintSize`, with real lines:

```dart
debugPaintLayout3dSize = true;
debugPaintLayout3dBaselines = true;  // baselines, and the offset from the parent
surface.flush();                     // the flush is what syncs the overlay
```

Every laid-out box hangs a wireframe of its own extent under its scene node,
in `LineSegmentsGeometry`, and the second flag adds the two things that are
otherwise entirely invisible: the baseline a `Baseline3d` or a
`CrossAxisAlignment3d.baseline` moved content by, and a line from the parent's
origin corner back to this box's, which is what tells a misplaced child from a
mis-sized one. Clearing the flag and flushing again takes every line back out
of the scene. A culled or hidden subtree draws nothing, so what a `ListView3d`
has scrolled out of its window has no lines either.

The overlay is one shared unit cube and one shared unit segment, scaled per
box, so a box that animates its size rebuilds nothing — the same economy
`BoxDecoration3d` runs on. It needs the engine to be ready
(`Scene.isReadyToRender`) because building line geometry allocates a device
buffer; before that, and in a headless test, the flag draws nothing rather
than throwing. Replace `debugLayout3dWireframeFactory` to draw the overlay
some other way, or with a recording `Layout3dWireframe` to assert on what a
test *would* have drawn.

### Accessibility

Scene content is opaque to a screen reader: a button built out of geometry is,
to the platform, a picture. `Semantics3d` is the way out, and what a component
author writes is Flutter's own `SemanticsProperties`, unchanged:

```dart
SceneSemantics3d(
  properties: const SemanticsProperties(
    label: 'Continue',
    button: true,
    textDirection: TextDirection.ltr,
  ),
  child: SceneGestureDetector3d(onTap: submit, child: continueButton),
)
```

It attaches a `SemanticsComponent` to the box's scene node, which `SceneView`
turns into a real Flutter semantics node whose focus rectangle is projected
through the camera — so the ring lands on the control, tracks it as the plane
turns, and disappears when the control is culled.

Two decisions in it are worth knowing. **The bounds come from layout, not from
the geometry.** Left alone, a `SemanticsComponent` projects whatever meshes
happen to hang under the node, which for a control is the icon and the label
rather than the target they sit in; `Semantics3d` overrides them with the
box's own `size`, so the rectangle is the padded control the layout protocol
produced. **Traversal order is layout order**, without anything being said:
reading order follows the scene graph, and here the scene graph *is* the
layout tree, so a `Column3d` of controls reads top to bottom for the same
reason it lays out that way. Set `sortOrder` only where that is wrong.

Focus and semantics have to be declared on the same boxes or the two trees
disagree — keyboard traversal visits five things and the reader announces
three. `debugFocusableBoxesWithoutSemantics` is the check:

```dart
expect(debugFocusableBoxesWithoutSemantics(surface), isEmpty);
```

One caveat while building controls: `TapTarget3d` grows the region a *ray*
reaches without growing the box, so a semantics rectangle taken from the box
is smaller than the touch target around it. Put the minimum size in the layout
(a `ConstrainedBox3d`, a `SizedBox3d`) as well when the target has to be
announced at its full size.

## How it differs from Flutter

* **Two cross axes.** A flex has one main axis and two cross axes, so
  `crossAxisAlignment` is joined by `depthAxisAlignment`. They follow
  canonical `x`, `y`, `z` order with the main axis removed.
* **`Flexible3d` and `Positioned3d` are layouts, not parent-data widgets.**
  They sit in the tree as real boxes, and the enclosing flex or stack reads
  their properties off them.
* **`Stack3d.depthStep`** pulls each successive child's geometry toward the
  viewer, which is how "later children paint on top" is spelled when the
  children are real geometry that would otherwise be coplanar. It moves the
  content in the scene and nothing in the layout: the boxes stay where the
  stack put them, a `Positioned3d` still lands on the face it pinned, and a
  ray still finds the last child first — the same answer the separated
  geometry gives the eye.
* **List items are not stretched by default.** `ListView3d` centres its items
  across the cross axes; ask for `CrossAxisAlignment3d.stretch` for the
  Flutter behaviour.
* **A wrap breaks into runs, never into layers.** The depth axis of a `Wrap3d`
  aligns children rather than wrapping them.
* **`GridView3d` is exactly lazy**, because a grid's cell positions are
  arithmetic. It knows how long ten thousand cells are without building one.
* **A sliver has no growth direction and no centre child.** Slivers run one
  way from the start of the viewport; there is no reverse list and no
  `center` key yet.
* **A pinned header stands in front of the content, it does not paint over
  it.** Nothing paints here, so a row scrolling under a bar is geometry that
  is really there. A `SliverPersistentHeader3d` answers with both a small
  push toward the viewer and a clip plane the viewport publishes; see
  *Persistent headers*.
* **Hit testing walks with a ray, not a point**, so an entry reports where
  the ray *entered* the box, and a box bounds the stretch of ray its children
  can be found in.
* **The gesture arena is Flutter's, on a private pointer id.** Recognizers
  reach for `GestureBinding.instance` and cannot be given a router of their
  own, so the events a surface synthesizes go into the real arena under an id
  no device will ever use. That is what keeps a gesture on the plane from
  fighting the widget-level gesture the same finger is driving.
* **A baseline belongs to an axis, and something has to declare it.**
  Flutter's runs across a box at the foot of its text, and text reports it;
  nothing in a scene does, so `Baseline3d` states one outright. There is no
  `TextBaseline`, because alphabetic against ideographic means nothing here.
* **A `Wrap3d` cannot say how thick it would be.** Its intrinsic extent across
  the runs is the one-run answer, which is a lower bound: knowing better means
  knowing how many runs it would break into, and Flutter answers that with a
  dry layout this package does not have.
* **No painting.** These layouts arrange content; they never draw. A visible
  panel is a mesh in a `NodeBox3d`.
* **A `Positioned3d` axis with nothing pinned is capped by the stack.** Flutter
  leaves it unconstrained, which in 2D means an over-large child merely
  overflows on screen; in 3D it means geometry standing out through the plane,
  and depth is exactly the axis a 2D habit forgets.

## Traps

* **`EdgeInsets3d.all` insets the front and back faces too.** On a plane
  thinner than the inset that leaves the content no depth at all. Panels
  usually want `EdgeInsets3d.symmetric(horizontal: ..., vertical: ...)`.
* **A plane needs depth for content to stand in.** Give the surface a real
  thickness and pin the backing slab to its back face (`Positioned3d(back: 0,
  depth: ...)`) rather than making the plane as thin as the slab.
* **The plane node moves in scene coordinates.** `surface.plane.position` is
  an ordinary engine transform; only what is *inside* the layout speaks layout
  space.
* **An aspect ratio is between two named axes, not all three.**
  `AspectRatio3d(aspectRatio: 16 / 9)` is width : height, the 2D habit, and
  the depth axis is passed through untouched. Say `axis:` and `relativeTo:`
  for any other pairing. Scaling a whole subtree into a shape is a different
  operation, and it is `FittedBox3d`.
* **A `Table3d` is a plane of cells.** Rows and columns, with depth as an
  alignment axis rather than a third index — the choice `Wrap3d` already made.
  Cells are given in row-major order, `columnCount` to a row.
* **A scrolling view on an unbounded depth axis has no depth.** It takes the
  depth it is given, and an unbounded axis gives it none, so items thicker
  than nothing stand out of the front of a view that is only as deep as a
  plane. They still draw, and a ray straight at them still finds them, but the
  view's own extent no longer contains them. Give the surface a real thickness
  — which a plane wants anyway, for content to stand in.

## Seeing it run

`examples/layout3d_gallery` has a live demo with an upright panel that turns on
its axis, the same protocol on the ground plane, and a scrolling list built
with the declarative widgets. It is wired for input: the cursor names what it
is over, on all three surfaces and through the turning panel, and the list
scrolls by dragging. Wrapping, grids, slivers and intrinsics have unit
coverage but no interactive demo yet.

`examples/render_probe` draws real geometry through the layout boxes on a GPU
and then checks the frame against the layout. It does not compare against a
stored image; it asks the layout tree where a box went, projects that to a
pixel with `Layout3d.screenCenter`, and asserts the frame has geometry there
and clear space in the gaps:

```dart
expect(frame.coverageAt(capture.centerOf('left'), radius: 10), greaterThan(0.8));
```

Sixteen scenes, over cuboids and spheres arranged by `Row3d`, `Column3d`,
`Stack3d`, `Padding3d`, `ListView3d`, `ClipBox3d` and the `xz` basis, plus two
that hold a drag in flight while the frame is captured — the only way to check
that a lifted card really does win the depth test, and that a detached feedback
entry really does draw outside the panel it came from. It is also the only
lane that *runs* the compiled `assets/box_decoration3d.fmat` — the package's
own build hook compiles it for every consumer, so a syntax error fails any
build, and a shader that compiles and draws the wrong thing fails only here.
That is not hypothetical: sixty-two headless tests passed over a border drawn
inside out, and a probe caught it.

```sh
cd examples/render_probe
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/render_test.dart -d macos --enable-flutter-gpu
```

The package's own `flutter test` suite remains arithmetic only, by necessity:
it has no Flutter GPU context.

## Roadmap

In the order the pieces depend on each other.

**1. Hit-testing and input.** ~~Done~~: `Layout3d.hitTest` walks the tree with
a `Ray3d`, `Layout3dSurface.hitTestRay` brings a camera ray into layout space,
and `Layout3dPointer` dispatches along the path it captured — raw events to
`Listener3d`, gestures to `GestureDetector3d` through Flutter's own arena,
enter and exit to whatever the pointer crossed, and a drag to the scrolling
view it grabbed. `Focus3d` is the focus half, with `Focus3dTraversal` moving
between boxes on the plane and `FocusScope3d` trapping it inside a modal. See
*Pointing at it* above. Routing a ray *across* surfaces is done —
`Layout3dPointerGroup`, see *Overlays* — and so is drag-and-drop across them,
which is the one search that deliberately ignores capture; see *Dragging things
around*. What is left is moving focus across surfaces, and a directional policy
that is genuinely three-dimensional rather than one that projects onto the
plane first.

**2. More layouts.** ~~Done~~: `Wrap3d` breaks into runs, `GridView3d` lays
cells out on a grid a `Grid3dDelegate` decides, and the rest of Flutter's
catalogue is here — `LimitedBox3d`, `UnconstrainedBox3d`, `OverflowBox3d`,
`FractionallySizedBox3d`, `AspectRatio3d`, `FittedBox3d`, `IndexedStack3d`,
`Table3d`, `CustomMultiChildLayout3d`, `Flow3d`, `PageView3d` and the
`LayoutBuilder3d` that lets any of them be chosen from the room available.
See *Building from the room you got* above. The family that needed
drag-and-drop is here too — `Draggable3d`, `DragTarget3d`, `Dismissible3d`,
`ReorderableList3d` and `SliverReorderableList3d` over a `Drag3dSession` that
searches across surfaces; see *Dragging things around*. What is left of it is a
widget form for the reorderable list, which wants a seam the declarative layer
does not have yet, and `Drag3dAnchor.targetPlane`, which is reserved and says
in its own dartdoc why the mechanism planned for it was the wrong one.

**3. Slivers.** ~~Mostly done~~: `CustomScrollView3d` drives the protocol,
with `SliverList3d`, `SliverGrid3d` and `SliverToBoxAdapter3d` on top of it and
`scrollOffsetCorrection` honoured, and `SliverPersistentHeader3d` pinning,
floating or scrolling away on top of `overlap` and `paintOrigin`, which is
what a `SliverAppBar3d` is built on. `ListView3d` and `GridView3d` are views
of this kind over a single sliver, as Flutter's are, so placement is written
once. See *Slivers* above. What is left of the protocol is small and
independent: `SliverFillRemaining3d`, a reverse growth direction and a
`center` sliver (`SliverPadding3d` is here). Building
**widgets** lazily is done: `SceneListView3d.builder` and its three siblings
inflate an item as the window reaches it, through a `Layout3dChildManager` the
view consults and a `RenderObjectElement` that implements it inside a build
scope, the way `SliverMultiBoxAdaptorElement` does. What is left of that is
keep-alive — an item that leaves the cache is disposed, with no counterpart to
Flutter's `KeepAlive` — and the key remapping that would let a keyed reorder
move an element instead of rebuilding it in place (a `GlobalKey` already
moves).

**4. Text.** ~~Done~~: `Text3d` lays a string out as a box, sizes itself,
answers intrinsics and states a baseline, over a prepare/layout split whose
fast half consults no font; `AtlasText3dRenderer` draws it out of a shared
glyph atlas, and `RichText3d` hands the paragraph back to Flutter for what an
atlas cannot assemble. See *Text* above. What is left is sharpness at
distance — the atlas holds ordinary coverage rasters, so a label rasterized
for arm's length softens as the panel comes toward the camera, and a signed
distance field or a second bucket is what would fix it — and selection and
editing, which are further out still.

**5. Intrinsic sizing.** ~~Done~~: `Layout3d.getMinIntrinsicExtent` and
`getMaxIntrinsicExtent` ask the question one axis at a time,
`IntrinsicWidth3d` and its two siblings are the boxes built on it, and
`Baseline3d` with `CrossAxisAlignment3d.baseline` is the baseline half. See
*Measuring* above. What is left is a dry layout, the speculative *sizing* pass
that Flutter added on top of intrinsics; it is what would let a `Wrap3d`
report how thick it would be at a given width instead of the one-run lower
bound it reports now.

**6. Geometry that follows a box.** ~~Done, bar the pixels~~:
`DecoratedBox3d` and `BoxDecoration3d` describe a panel, the painter cache
shares one mesh across every panel with the same shape, elevation lifts the
geometry toward the viewer, and a state layer is a uniform that never dirties
layout, and `SceneDecoratedBox3d` is the widget form of it. See *Making a box
visible* and *The declarative layer* above. The shader ships as
`assets/box_decoration3d.fmat` and is compiled by this package's own build
hook, so an application inherits it; `BoxDecoration3dPainter` drives it, and
`examples/render_probe` checks, on a GPU, that a rounded panel loses its
corners, that a lifted panel projects wider than a flat one, that a border
draws in its own colour at the rim and not in the middle, and that a state
layer lightens the panel it is on. Two things stay open, both of them the
engine's: a decorated panel casts no shadow
at all — `blending: alpha` keeps it out of the shadow pass, and an opaque one
would cast its whole rectangular slab because a shadow pass never runs the
surface shader — and clip planes are published to every material through
`Clip3dRegion` but only the shipped panel shader reads them.

**7. Overlays.** ~~Done~~: `Overlay3d` holds entries in front of its base
content, each one either lifted toward the viewer on the host surface or on a
surface of its own, with `ModalBarrier3d` for the scrim, `FocusScope3d` for
the focus a modal traps, `Layout3dPointerGroup` for routing a ray across
surfaces, and `Navigator3d` for the route stack over the whole of it. See
*Overlays* above. What is left is an entry whose content is a *widget*
subtree rather than a built layout, focus traversal across surfaces, and the
transitions `Route3dTransition` is the hook for.

**8. Animation and scroll physics.** ~~Done~~: three paths, cheapest first —
decoration setters that only repaint, `Layout3d.nodeOffset` and
`nodeTransform` for geometry that moves without any box changing size (with
`NodeTransform3d` and `SceneAnimatedSlide3d` over them), and
`ImplicitlyAnimatedLayout3dWidget` with `SceneAnimatedContainer3d` and its
siblings for the animations that really do relayout. On the scroll side,
`Scroll3dPhysics` with clamping and bouncing, a release that flings from a
velocity `Layout3dPointer` tracks on the grabbed view's plane, and
`animateTo`, `fling` and `ensureVisible3d` on the controller. See *Animation*
and *Physics, flings, and going somewhere* above. What is left is
`AnimatedOpacity3d`, which waits on a per-node opacity in the engine, and the
overscroll effects a scene could have instead of a glow — bending, tilting or
compressing the content — which `Scroll3dController.overscroll` exposes the
number for but nothing here builds.

**9. Diagnostics and accessibility.** ~~Done~~: every box is a
`DiagnosticableTree`, so `toStringDeep` and `debugDumpLayout3dTree` print what
came down and what went up; an ordinary Flutter render object interposed
between two `Scene*3d` widgets is now an error that names both ends of it
rather than a silently missing subtree; `Flex3d` and `UnconstrainedBox3d`
report an overflow with the axis and the amount; `debugPaintLayout3dSize`
hangs a wireframe of every box's extent under its node, with baselines and
placement offsets behind a second flag; and `Semantics3d` publishes a control
to assistive technology with the bounds layout gave it. See *Debugging what
you cannot see* above. What is left is a visual inspector, which belongs to
the Flutter Scene Editor rather than here.

**What is next.** Nothing in this list depends on anything else in it any
more, so the order is a matter of what a caller reaches for first: keep-alive
for a lazily built item, which the reorderable list currently works around
rather than fixes; a widget form for that list, and the child-manager seam it
needs; route transitions over `Route3dTransition`; focus traversal across
surfaces; a distance-field glyph atlas for type that stays sharp as a panel
approaches; and a per-node opacity in the engine, which is what an `Opacity3d`
is waiting on.

## License

MIT, the same as the rest of the repository.
