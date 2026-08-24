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
| `Viewport3d`, `ListView3d`, `Scroll3dController` | `SingleChildScrollView`, `ListView`, `ScrollController` |
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
Attach a `Layout3dController` to reach the surface imperatively, for measured
sizes, scroll positions, or the plane node.

## Scrolling

`ListView3d` shows the window of its content at a `Scroll3dController`
offset. Built from an explicit list of children, every child is laid out and
the ones outside the window have their nodes hidden. `ListView3d.builder`
builds items on demand: with `itemExtent` nothing off-screen is ever built,
and without it items are measured once as they are first scrolled past, with
the total extent estimated from the average, the same approximation
`SliverList` makes.

There is no scroll physics here. `Scroll3dController` holds a position and
clamps it to what the content allows, and `Layout3dPointer` drives it from a
drag; anything else (a thumbstick, a wheel, an animation) drives
`Scroll3dController.offset` directly.

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
* **`Stack3d.depthStep`** pulls each successive child toward the viewer, which
  is how "later children paint on top" is spelled when the children are real
  geometry that would otherwise be coplanar.
* **List items are not stretched by default.** `ListView3d` centres its items
  across the cross axes; ask for `CrossAxisAlignment3d.stretch` for the
  Flutter behaviour.
* **Hit testing walks with a ray, not a point**, so an entry reports where
  the ray *entered* the box, and a box bounds the stretch of ray its children
  can be found in.
* **No gesture arena.** `Layout3dPointer` is a plain object driven from
  whatever pointer events the application has; there is no recognizer team,
  no arena, and no fling.
* **No intrinsic sizing yet**, so no `IntrinsicWidth`/`IntrinsicHeight`
  equivalents and no baseline alignment.
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

Two scenes in `examples/smoke_render` (`layout3d_panel` and `layout3d_ground`)
render a laid-out surface headlessly and assert a sane frame, so a layout that
stops producing geometry fails in CI along with the rest of the render smoke
matrix. `examples/flutter_app` has a live `Layout` example with an upright
panel that turns on its axis, the same protocol on the ground plane, and a
scrolling list built with the declarative widgets. It is wired for input: the
cursor names what it is over, on all three surfaces and through the turning
panel, and the list scrolls by dragging.

## Roadmap

In the order the pieces depend on each other.

**1. Hit-testing and input.** ~~Done~~: `Layout3d.hitTest` walks the tree with
a `Ray3d`, `Layout3dSurface.hitTestRay` brings a camera ray into layout space,
and `Layout3dPointer` turns a drag into scrolling. See *Pointing at it* above.
What is left for later is hover and press state on the boxes themselves (the
groundwork any `Button3d` would need) and keyboard focus.

**2. More layouts.** `Wrap3d`, which is cheap and fits the existing flex
machinery, and `GridView3d` with a delegate that decides the cell size. This is
the breadth that makes real arrangements possible rather than demonstrations.

**3. Slivers.** A genuine `Viewport3d` protocol with `SliverConstraints3d` and
`SliverGeometry3d`, then `SliverList3d` and `SliverGrid3d` on top of it, and
only then lazy building in the declarative layer, which needs a
`RenderObjectElement` of its own and a build scope to create children during
layout. The largest piece, and the one that gains the most from the rest being
settled first.

**4. Intrinsic sizing.** `IntrinsicWidth3d`, `IntrinsicHeight3d`, and baseline
alignment. Last, because it is where layout cost multiplies and because its
value shows up mainly with content that sizes itself from its own contents,
text above all, which this package does not have yet.

## License

MIT, the same as the rest of the repository.
