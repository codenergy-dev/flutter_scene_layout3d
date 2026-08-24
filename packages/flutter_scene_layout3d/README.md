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

There is no scroll physics here. In a 3D scene the gesture that drives
scrolling is the application's to choose (a drag on the `SceneView`, a
raycast, a thumbstick), so drive `Scroll3dController.offset` from whatever
input you have.

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
scrolling list built with the declarative widgets.

## Roadmap

In the order the pieces depend on each other.

**1. Hit-testing and input.** The half of the protocol that is missing.
Flutter puts `hitTest` on `RenderBox` for a reason: it is what turns a laid-out
tree into something a pointer can address. Here it means `Layout3d.hitTest`
walking down the tree with the placement offsets, plus a pointer-to-plane
mapping, which the pieces already present nearly give away — the engine's
screen-to-ray, the inverse of the plane node's transform, and
`LayoutBasis3d.toLayoutMatrix`. `ListView3d` is the immediate payoff, since
today nothing drags it, but the same machinery is what any interactive layout
above this package would build on.

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
