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
| `Viewport3d`, `ListView3d`, `GridView3d`, `Scroll3dController` | `SingleChildScrollView`, `ListView`, `GridView`, `ScrollController` |
| `Grid3dDelegate`, `Grid3dLayout` | `SliverGridDelegate`, `SliverGridLayout` |
| `CustomScrollView3d`, `Sliver3d` | `CustomScrollView` + `Viewport`, `RenderSliver` |
| `SliverList3d`, `SliverGrid3d`, `SliverToBoxAdapter3d` | `SliverList`, `SliverGrid`, `SliverToBoxAdapter` |
| `SliverConstraints3d`, `SliverGeometry3d` | `SliverConstraints`, `SliverGeometry` |
| `IntrinsicWidth3d`, `IntrinsicHeight3d`, `IntrinsicDepth3d` | `IntrinsicWidth`, `IntrinsicHeight` |
| `Baseline3d`, `CrossAxisAlignment3d.baseline` | `Baseline`, `CrossAxisAlignment.baseline` |
| `IgnorePointer3d`, `AbsorbPointer3d` | `IgnorePointer`, `AbsorbPointer` |
| `Ray3d`, `HitTestResult3d`, `Layout3dPointer` | `hitTest`, `BoxHitTestResult`, `Listener` |
| `NodeBox3d` | the leaf that holds content |

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

What this buys over `ListView3d` and `GridView3d` is the thing neither can do:
**several sections on one scroll position**. A header, a grid and a list scroll
together as one surface, each asked only about the part of the window it can
see. `SliverToBoxAdapter3d` is the glue — everything else in this package is a
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
than five hundred items says so rather than merely dropping a frame.

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
content it holds, which is a real measurement of real geometry; every box
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
ways to stand side by side — and nothing in a scene reports one on its own, so
`Baseline3d` is what states it:

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

### Dragging

`Layout3dPointer` turns rays into scrolling:

```dart
final pointer = Layout3dPointer(surface);

Listener(
  onPointerDown: (event) => pointer.down(rayFor(event)),
  onPointerMove: (event) => pointer.move(rayFor(event)),
  onPointerUp: (_) => pointer.up(),
  child: SceneView(scene, camera: camera),
)
```

It measures where the pointer lands *on the grabbed view's own plane*, not
how far it moved across the screen, so the content stays under the finger at
any viewing angle and perspective is accounted for by construction. A grabbed
view keeps the drag until release, so running off the end of a list does not
drop it. There is still no fling: a release stops the movement dead, and an
application that wants momentum can drive the controller from its own
animation.

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
  arithmetic. It needs no slivers to know how long it is.
* **A sliver has no growth direction and no centre child.** Slivers run one
  way from the start of the viewport; there is no reverse list and no
  `center` key yet.
* **No pinned or floating headers**, so `SliverConstraints3d` carries no
  `overlap` and `SliverGeometry3d` no `paintOrigin`. They are the fields those
  headers need, and they can arrive with them.
* **Hit testing walks with a ray, not a point**, so an entry reports where
  the ray *entered* the box, and a box bounds the stretch of ray its children
  can be found in.
* **No gesture arena.** `Layout3dPointer` is a plain object driven from
  whatever pointer events the application has; there is no recognizer team,
  no arena, and no fling.
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
and `Layout3dPointer` turns a drag into scrolling. See *Pointing at it* above.
What is left for later is hover and press state on the boxes themselves (the
groundwork any `Button3d` would need) and keyboard focus.

**2. More layouts.** ~~Done~~: `Wrap3d` breaks into runs, and `GridView3d`
lays cells out on a grid a `Grid3dDelegate` decides, with an exactly lazy
builder. What is left in this direction is the rest of Flutter's catalogue
(`Table`, `Flow`, aspect-ratio and fractionally-sized boxes), which is
breadth rather than new machinery.

**3. Slivers.** ~~Mostly done~~: `CustomScrollView3d` drives the protocol,
with `SliverList3d`, `SliverGrid3d` and `SliverToBoxAdapter3d` on top of it and
`scrollOffsetCorrection` honoured. See *Slivers* above. Two pieces are left.
Pinned and floating headers need `overlap` and `paintOrigin` threaded through
the protocol, which is what a `SliverAppBar3d` would be built on. And building
**widgets** lazily still has no answer: `SliverList3d.builder` is lazy on the
imperative side, but the declarative layer builds every child widget up front,
because doing better needs a `RenderObjectElement` of its own and a build scope
to create children during layout.

**4. Intrinsic sizing.** ~~Done~~: `Layout3d.getMinIntrinsicExtent` and
`getMaxIntrinsicExtent` ask the question one axis at a time,
`IntrinsicWidth3d` and its two siblings are the boxes built on it, and
`Baseline3d` with `CrossAxisAlignment3d.baseline` is the baseline half. See
*Measuring* above. What is left is a dry layout, the speculative *sizing* pass
that Flutter added on top of intrinsics; it is what would let a `Wrap3d`
report how thick it would be at a given width instead of the one-run lower
bound it reports now.

**What is next.** Nothing in this list depends on anything else in it any
more, so the order is a matter of what a caller reaches for first: the rest of
Flutter's layout catalogue (`Table`, `Flow`, aspect-ratio and
fractionally-sized boxes), pinned and floating sliver headers, lazily built
child *widgets* in the declarative layer, and hover and press state on the
boxes themselves, which is the groundwork any `Button3d` would need.

## License

MIT, the same as the rest of the repository.
