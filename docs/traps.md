# The traps in this package

Things that cost real time and are not obvious from the code. Most of them are
deliberate design decisions rather than defects — which is exactly why reading
the code does not warn you.

If you are about to build a component, read the first three sections. If you
are about to make something appear on screen, read *Why nothing draws*.

## The unit contract: two units, side by side

**A box's size is in world units. A Material figure is in logical pixels.**
Both appear in the same constructors, and nothing stops you writing one where
the other belongs.

```dart
Layout3dSurface(
  // World units: this is what layout deals in.
  constraints: Constraints3d.tight(const Size3d(3.6, 1.8, 0.2)),
  child: DecoratedBox3d(
    decoration: const BoxDecoration3d(
      // Logical pixels: 60dp, which the metrics turn into 0.6 units.
      borderRadius: BorderRadius3d.circular(60),
    ),
  ),
);
```

`BorderRadius3d`, `bevel`, `border` and `elevation` on a `BoxDecoration3d` are
all written the way a Material shape token is written, and the metrics convert
them at paint time. At the default rate of `0.01` units per logical pixel,
`circular(60)` is 0.6 world units — a third of that panel's height.
**`circular(0.6)` asks for six thousandths of a unit** and renders as an
indistinguishably square corner. That mistake cost an hour of debugging a
shader that turned out to be working perfectly.

The rate itself is `Layout3dMetrics.unitsPerLogicalPixel`, carried on
`Layout3dOwner.metrics` beside the basis and read inside `performLayout` as
`Layout3d.metrics` — no `BuildContext`, no inherited widget, so the imperative
layer has it too. `metrics.dp(48)` converts a spec figure; `metrics.sp(14)` a
type size. Bind a surface to the camera and the rate stops being a guess: it is
derived from the frustum at the distance the surface sits.

## Staying off the relayout path

**Writing `Layout3dSurface.metrics` relayouts the whole subtree, by design.**
It belongs to a window resize. Nothing on a per-frame path may touch it.

Animation has three tiers, cheapest first, and picking the wrong one is how a
smooth interaction becomes a stutter:

1. **Repaint only.** `DecoratedBox3d.decoration` and `.stateLayer` are setters
   that never touch layout — they write shader uniforms. A colour, a corner, an
   elevation, a hover state: all of this.
2. **Node only.** `nodeOffset` and `nodeTransform` write one matrix a frame and
   never call `markNeedsLayout`. A slide, a lift, a press, a turn.
3. **Implicit**, and only when a size really changed.

Never put a new `Text3d.text`, a new `NodeBox3d.content`, or a rebuilt mesh on
a per-frame path. `test/animation_test.dart` asserts `debugTextParagraphCount`
does not move while a container resizes a label through a whole run; that test
fails first if text measurement gets back onto the layout path, which is the
regression the whole prepare/layout split exists to prevent.

## Four transform channels, and they are not interchangeable

A box's node carries
`T(offset + sceneOffset + nodeOffset) * nodeTransform * localTransform`.

- `ParentData3d.sceneOffset` **belongs to the parent.** `Stack3d.depthStep`
  rewrites it on every placement, so an animation stored there is silently
  erased on the next layout. This is the one that bites.
- `nodeOffset` and `nodeTransform` are yours, per box, and survive layout.
  Use these for animation.
- `localTransform` is the box's own, and `worldTransform` undoes it — which is
  what keeps hit testing finding a box where layout put it rather than where a
  transform moved it.

## Why nothing draws

**The package arranges; it draws only what you ask it to.** Two seams stand
between a laid-out tree and a picture, and both default to nothing, because
neither can be verified in `flutter test`, which has no GPU context.

**A decoration needs a painter.** `BoxDecoration3d.painterFactory` is null
until an application sets it, and a `DecoratedBox3d` with no painter measures,
lays out and draws nothing at all. `examples/render_probe` is the worked
example of filling it:

```dart
final material = await loadFmatMaterial('assets/box_decoration3d.fmat');
BoxDecoration3d.painterFactory =
    (_) => BoxDecoration3dPainter(createMaterial: () => material);
```

Compiling the shipped `.fmat` needs a build hook, which a package cannot run
from inside a dependency. `examples/render_probe/hook/build.dart` shows the
shape of it.

**A label needs a renderer.** `Text3d` takes one and has none by default:

```dart
Text3d('Save', style: labelStyle, renderer: AtlasText3dRenderer())
```

That one is per box and is owned by it — the box disposes it — while the
*atlas* behind it is shared through `GlyphAtlasCache3d.shared`, which is what
makes a screen of labels one texture. A `RichText3d` needs no renderer but
does need a `SceneView` to host its subtree; in a scene nobody is displaying
it measures correctly and draws nothing.

Both of those are one-frame-late by nature: an atlas glyph nobody has drawn
before is read back asynchronously, and a widget capture arrives on the frame
after the subtree is hosted. A test that draws a label and reads the frame in
the same pump reads an empty frame.

### Elevation is a lift, not a shadow

`BoxDecoration3d.elevation` moves the panel's geometry toward the viewer by
`metrics.dp(elevation)`. That is the whole of it, and it is worth knowing what
that does and does not buy:

- **It does not cast a shadow, and no amount of lighting will make it.** The
  panel shader declares `blending: alpha` — its anti-aliased outline *is* an
  alpha — and `flutter_scene` drops every non-opaque material before the
  shadow pass reaches a shadow map. A raised card reads as raised through
  parallax and occlusion. Grounding it on a surface is the caller's job; the
  engine's `ShadowCatcherMaterial` on a plane beneath it is the shape of that.
  (And were the material opaque, the shadow would be the whole rectangular
  slab: a shadow pass runs `DepthOnlyFragment`, never a material's own
  `Surface()`, so the corner radius is not in it.)
- **It moves the geometry and not the box.** Layout, intrinsics and what a ray
  reaches all stay where layout put them.
- **But a screen projection follows the geometry.** `worldTransform` undoes
  `hitTestTransform`, and `DecoratedBox3d` returns null from that, so
  `screenCenter`, `screenPointOf` and `screenBounds` on an elevated panel
  report where it is *drawn* — which is the right answer for a debug overlay,
  and a surprise if you expected them to agree with the hit test.

### Making geometry fill its box

`NodeBox3d` defaults to `BoxFit3d.none`: the content keeps its own size inside
whatever slot layout gave it. That is usually right for a model, and usually
wrong when you want the box and the geometry to be the same thing.

- **`none`** — content keeps its size. A box's screen bounds then enclose empty
  space, and anything reasoning about "where this box is" is approximate.
- **`contain`** — scales uniformly to fit the smallest bounded axis. Keeps a
  sphere spherical. **A cube in a 1.6 × 1.6 × 0.1 slot comes out a 0.1 cube**,
  because the depth axis is the smallest.
- **`fill`** — scales each axis on its own. What a thin slab wants.

### Depth ordering

`Stack3d.depthStep` steps each child toward the viewer, but **it does not
separate children thicker than the step**. A 1.6-deep slab centred on the plane
reaches further toward the viewer than a 0.8-deep child stepped 0.35, so the
back child wins the depth test and the stack looks inverted. Keep stacked
children thin relative to the step, or raise the step.

**`Dismissible3d`'s backgrounds are coplanar with the child.**
`backgroundDepthStep` defaults to zero, exactly as `Stack3d.depthStep` does,
so the background revealed by a swipe and the row sliding off it sit on the
same plane and z-fight where they overlap. That is the right default for a flat
Material row — the child covers the background until it moves, so there is
nothing to fight over — and the wrong one the moment either has depth. A small
positive step pushes the backgrounds away from the viewer and the fight stops.

## Pointers

- **`TapTarget3d` grows the ray region but not the box.** The Material 48dp
  minimum is invisible to layout, to intrinsics, to `ensureVisible3d` and to
  semantics, which announces the smaller rectangle. Deliberate — it keeps
  neighbours from moving when a target is padded — but sharp.
- **A `Text3d` answers hit tests on its own account**, so a label inside a
  button usually wants an `IgnorePointer3d` around it.
- **A drop lands where a tap would land, which is not always where it looks
  like it lands.** A `Drag3dSession` picks the *nearest acceptor along the
  ray* — hit order within a surface, front-to-back between them — for the same
  reason a press does: consistency is the only rule a viewer can predict from.
  So it inherits the depth-ordering trap above. A drop target thicker than the
  `Stack3d.depthStep` separating it from its neighbours can reach further
  toward the viewer than the card drawn in front of it, win the ray, and take a
  drop that visibly belonged to the other one. The drag machinery cannot fix
  this and does not try: **keep drop targets thin relative to the step.**
- **A picked-up card is only as far in front as its layer's lift.**
  `Draggable3d` corrects the feedback's position on the *plane* so it covers
  the box the drag started on, and deliberately leaves depth to
  `OverlayLayer3d.lift` — correcting depth too would land the feedback exactly
  on the source and cancel the lift. The default lift is
  `Overlay3d.defaultLift`, eight logical pixels, which is a depth-buffer
  separation rather than a distance: content thicker than that will still
  fight the feedback carried over it, exactly as the depth-ordering item above
  describes. Ask for a bigger lift when the rows have real thickness.
- **Feedback under the pointer must be wrapped in an `IgnorePointer3d`**, and
  `Draggable3d` does it for you. Hit testing ignores `nodeOffset`, so a piece
  of feedback moved on the node tier is invisible to the ray moving it — but
  its *laid-out* position is not, and a `Text3d` inside it would answer there
  and steal the drop.

## Clipping

**A corner radius is not a clip.** `Clip3dRegion` is an intersection of planes,
and a plane region is convex; a radius cannot be expressed that way. The panel
shader carves the radius out instead.

Clipping has three tiers: whole-node culling (free, exact for boxes entirely
outside), clip planes packed into a material (`toPlaneBlock`, for a child that
is *half* in — only the shipped panel shader reads them so far), and nothing.
The seam is `Layout3d.clipRegion` → `Decoration3dPaintRequest.clip` →
`toPlaneBlock()`, and it is live: a row half under a pinned
`SliverPersistentHeader3d` is genuinely cut at the bar's edge.

## When probing a rendered frame

Two more, specific to `examples/render_probe` and worth knowing before you
write a scene there.

- **`screenBounds` bounds all eight corners, including the depth extrusion.**
  On a slab with any depth its corners sit outside the front face, so probing a
  *face* wants `screenPointOf` with an explicit `z` fraction.
- **A level camera cannot see a ground plane.** `LayoutBasis3d.xz` viewed from
  `y = 0` is exactly edge-on: every point lands on the horizon line and near is
  indistinguishable from far. Raise the camera.
- **A difference is not a direction, and a shader test wants the direction.**
  "The rim of this panel is a different colour from its middle" is satisfied
  just as well when the two are swapped, which is exactly how the panel shader
  came to ship with its border drawn inside out — the fill as a thin rim
  around a panel entirely in the border colour, past sixty-two headless tests
  that all checked the parameters and never the picture. Ask which colour is
  where, by a comparison lighting and tone mapping cannot reorder: a channel
  order (`r > b`), a luminance, an occlusion. Not a distance.
