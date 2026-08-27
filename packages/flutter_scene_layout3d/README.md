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
   +-------------+                            v  layout y runs away
        layout x runs right                      from the camera
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

### It does not draw

A `Text3d` with no `renderer` lays out, sizes itself, answers intrinsics and
states a baseline, and puts nothing in the scene. That is deliberate:
measurement is pure arithmetic and testable headless, rasterization is neither,
and there is more than one defensible way to do it (a glyph atlas of textured
quads, a captured widget on a quad, extruded outlines). `Text3dRenderer` is
the seam between them, and it is handed everything a renderer needs —
the box's node, the layout in logical pixels, the style, the basis, and both
directions of the unit conversion including the rasterization resolution. No
renderer ships yet.

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
viewer by `metrics.dp(elevation)` and the shadow is whatever the scene's own
lights cast. Material 3's other half, the surface tint, is a uniform on the
same shader and follows the published opacity table
(`BoxDecoration3d.surfaceTintOpacityFor`).

The lift moves the *geometry* and nothing else. The box keeps the size and
position layout gave it, and a ray still reaches it where the layout put it —
a raised button whose touch target drifted away from its layout box would be a
bug. It is the same distinction `ParentData3d.sceneOffset` draws.

### It does not draw on its own either

Like `Text3d`, a `DecoratedBox3d` with no painter lays out, sizes itself and
hit-tests exactly as it otherwise would, and puts nothing in the scene.
Producing geometry needs a GPU context, which a headless test does not have
and neither does a surface built before `Scene.initializeStaticResources()`
resolves. `Decoration3dPainter` is the seam.

The package ships the shader as `assets/box_decoration3d.fmat` and
`BoxDecoration3dPainter` as the painter that drives it. A library cannot
compile a `.fmat` from inside a dependency — the build hook runs in the app —
so copy the file into your app's `assets/`, add it to your hook's
`buildMaterials` list, and install the factory once:

```dart
final material = await loadFmatMaterial('assets/box_decoration3d.fmat');
BoxDecoration3d.painterFactory =
    (_) => BoxDecoration3dPainter(createMaterial: () => material);
```

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
| `Layout3dCameraBinding` | what `View` does for a Flutter tree: the thing that bounds it |
| `Layout3dMetrics`, `VisualDensity3d` | `MediaQuery`'s scale factors, `VisualDensity` |
| `Viewport3d`, `ListView3d`, `GridView3d`, `Scroll3dController` | `SingleChildScrollView`, `ListView`, `GridView`, `ScrollController` |
| `Grid3dDelegate`, `Grid3dLayout` | `SliverGridDelegate`, `SliverGridLayout` |
| `CustomScrollView3d`, `Sliver3d` | `CustomScrollView` + `Viewport`, `RenderSliver` |
| `SliverList3d`, `SliverGrid3d`, `SliverToBoxAdapter3d` | `SliverList`, `SliverGrid`, `SliverToBoxAdapter` |
| `BoxScrollView3d`, `SliverMultiBoxAdaptor3d` | `BoxScrollView`, `RenderSliverMultiBoxAdaptor` |
| `SliverConstraints3d`, `SliverGeometry3d` | `SliverConstraints`, `SliverGeometry` |
| `IntrinsicWidth3d`, `IntrinsicHeight3d`, `IntrinsicDepth3d` | `IntrinsicWidth`, `IntrinsicHeight` |
| `Baseline3d`, `CrossAxisAlignment3d.baseline` | `Baseline`, `CrossAxisAlignment.baseline` |
| `IgnorePointer3d`, `AbsorbPointer3d` | `IgnorePointer`, `AbsorbPointer` |
| `Ray3d`, `HitTestResult3d`, `Layout3dPointer` | `hitTest`, `BoxHitTestResult`, and `GestureBinding`'s dispatch |
| `Listener3d`, `HitTestTarget3d`, `HitTestBehavior3d` | `Listener` + `MouseRegion`, `HitTestTarget`, `HitTestBehavior` |
| `GestureDetector3d`, `HitTestArea3d`, `TapTarget3d` | `GestureDetector`, a bare hit-test region, Material's 48dp target |
| `Focus3d`, `Focus3dTraversal`, `FocusScope3d` | `Focus`, `FocusTraversalPolicy`, `FocusScope` |
| `Overlay3d`, `Overlay3dEntry`, `OverlayLayer3d` | `Overlay`, `OverlayEntry`, and the 3D question Flutter does not have |
| `ModalBarrier3d`, `Navigator3d`, `Route3d` | `ModalBarrier`, `Navigator`, `Route` |
| `Layout3dPointerGroup` | routing a ray across surfaces, which a screen does not need |
| `NodeBox3d` | the leaf that holds content |
| `Text3d`, `TextMeasurement3d` | `Text`, and the `TextPainter` behind it |
| `DecoratedBox3d`, `BoxDecoration3d`, `Border3d`, `BorderRadius3d` | `DecoratedBox`, `BoxDecoration`, `Border`, `BorderRadius` |
| `Decoration3dPainter`, `Decoration3dPainterCache`, `StateLayer3d` | `BoxPainter`, and Material's state layers |
| `ClipBox3d`, `Clip3dRegion`, `ClipPlane3d` | `ClipRect`, and the clip stack behind it |
| `Visibility3d`, `Offstage3d` | `Visibility`, `Offstage` |

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
`SceneText3d` is the one that gains something from being a widget: it has a
`BuildContext` to ask, so it picks up the ambient `DefaultTextStyle` and
`Directionality` the way a Flutter `Text` does — from the widget tree the
scene is hosted in, not from anything inside the scene.
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

There is no scroll physics here. `Scroll3dController` holds a position and
clamps it to what the content allows, and `Layout3dPointer` drives it from a
drag; anything else (a thumbstick, a wheel, an animation) drives
`Scroll3dController.offset` directly.

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
angle. There is still no fling: a release stops the movement dead.

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
* **No pinned or floating headers**, so `SliverConstraints3d` carries no
  `overlap` and `SliverGeometry3d` no `paintOrigin`. They are the fields those
  headers need, and they can arrive with them.
* **Hit testing walks with a ray, not a point**, so an entry reports where
  the ray *entered* the box, and a box bounds the stretch of ray its children
  can be found in.
* **The gesture arena is Flutter's, on a private pointer id.** Recognizers
  reach for `GestureBinding.instance` and cannot be given a router of their
  own, so the events a surface synthesizes go into the real arena under an id
  no device will ever use. That is what keeps a gesture on the plane from
  fighting the widget-level gesture the same finger is driving. There is still
  no fling.
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
* **A scrolling view on an unbounded depth axis has no depth.** It takes the
  depth it is given, and an unbounded axis gives it none, so items thicker
  than nothing stand out of the front of a view that is only as deep as a
  plane. They still draw, and a ray straight at them still finds them, but the
  view's own extent no longer contains them. Give the surface a real thickness
  — which a plane wants anyway, for content to stand in.

## Seeing it run

Five scenes in `examples/smoke_render` render a laid-out surface headlessly and
assert a sane frame, so a layout that stops producing geometry fails in CI
along with the rest of the render smoke matrix: `layout3d_panel` and
`layout3d_ground` for the two bases, then `layout3d_wrap_grid`,
`layout3d_slivers` and `layout3d_intrinsic`.

`examples/flutter_app` has a live `Layout` example with an upright panel that
turns on its axis, the same protocol on the ground plane, and a scrolling list
built with the declarative widgets. It is wired for input: the cursor names
what it is over, on all three surfaces and through the turning panel, and the
list scrolls by dragging. Wrapping, grids, slivers and intrinsics have headless
coverage but no interactive demo yet.

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
`Layout3dPointerGroup`, see *Overlays* — but moving focus across them is not,
and neither is a directional policy that is genuinely three-dimensional
rather than one that projects onto the plane first.

**2. More layouts.** ~~Done~~: `Wrap3d` breaks into runs, and `GridView3d`
lays cells out on a grid a `Grid3dDelegate` decides, with an exactly lazy
builder. What is left in this direction is the rest of Flutter's catalogue
(`Table`, `Flow`, aspect-ratio and fractionally-sized boxes), which is
breadth rather than new machinery.

**3. Slivers.** ~~Mostly done~~: `CustomScrollView3d` drives the protocol,
with `SliverList3d`, `SliverGrid3d` and `SliverToBoxAdapter3d` on top of it and
`scrollOffsetCorrection` honoured. `ListView3d` and `GridView3d` are views of
this kind over a single sliver, as Flutter's are, so placement is written
once. See *Slivers* above. Two pieces are left.
Pinned and floating headers need `overlap` and `paintOrigin` threaded through
the protocol, which is what a `SliverAppBar3d` would be built on. Building
**widgets** lazily is done: `SceneListView3d.builder` and its three siblings
inflate an item as the window reaches it, through a `Layout3dChildManager` the
view consults and a `RenderObjectElement` that implements it inside a build
scope, the way `SliverMultiBoxAdaptorElement` does. What is left of that is
keep-alive — an item that leaves the cache is disposed, with no counterpart to
Flutter's `KeepAlive` — and the key remapping that would let a keyed reorder
move an element instead of rebuilding it in place (a `GlobalKey` already
moves).

**4. Text.** ~~Measurement done~~: `Text3d` lays a string out as a box,
sizes itself, answers intrinsics and states a baseline, over a prepare/layout
split whose fast half consults no font. See *Text* above. What is left is the
half that draws — `Text3dRenderer` is the seam and nothing implements it yet.
A glyph atlas of textured quads is the intended default (one atlas per
font-and-size bucket, run meshes built with `GeometryBuilder`, a signed
distance field so a label stays sharp as the panel comes toward the camera),
with a `WidgetComponent` capture as the escape hatch for what an atlas cannot
do. Selection, editing and rich-text spans are further out still.

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
layout. See *Making a box visible* above. The shader ships as
`assets/box_decoration3d.fmat` and `BoxDecoration3dPainter` drives it, but no
lane in this repository compiles it yet, so the GLSL is checked for its
parameter contract and not for what it draws. Two things are known to be open:
the shadow a rounded panel casts is the slab's, because a shadow pass does not
run the surface shader that discards the corners; and clip planes are
published to every material through `Clip3dRegion` but only the shipped panel
shader reads them.

**7. Overlays.** ~~Done~~: `Overlay3d` holds entries in front of its base
content, each one either lifted toward the viewer on the host surface or on a
surface of its own, with `ModalBarrier3d` for the scrim, `FocusScope3d` for
the focus a modal traps, `Layout3dPointerGroup` for routing a ray across
surfaces, and `Navigator3d` for the route stack over the whole of it. See
*Overlays* above. What is left is an entry whose content is a *widget*
subtree rather than a built layout, focus traversal across surfaces, and the
transitions `Route3dTransition` is the hook for.

**What is next.** Nothing in this list depends on anything else in it any
more, so the order is a matter of what a caller reaches for first: a
`Text3dRenderer` that actually draws, the rest of Flutter's layout catalogue
(`Table`, `Flow`, aspect-ratio and fractionally-sized boxes), pinned and
floating sliver headers, keep-alive for a lazily built item, and a per-node
opacity in the engine, which is what an `Opacity3d` is waiting on.

## License

MIT, the same as the rest of the repository.
