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
`Layout3d.metrics` — no `BuildContext` in the way, so the imperative layer has
it too. `metrics.dp(48)` converts a spec figure; `metrics.sp(14)` a type size;
`metrics.dpSize(200, 48)` and `metrics.dpInsets(EdgeInsets3d.all(16))` are the
two shapes a component writes constantly. Bind a surface to the camera and the
rate stops being a guess: it is derived from the frustum at the distance the
surface sits.

**A `build` method reads the same contract through the surface**, which
publishes it as `Layout3dMetricsScope.of(context)`:

```dart
final metrics = Layout3dMetricsScope.of(context);

ScenePadding3d(
  padding: metrics.dpInsets(const EdgeInsets3d.all(16)),   // 16dp
  child: SceneSizedBox3d(height: metrics.dp(56), child: label),
)
```

Without it a figure in a `build` method is in world units, full stop — and
decorations hide that, because `BorderRadius3d`, `bevel`, `border` and
`elevation` are converted by the painter at paint time, so a
`SceneDecoratedBox3d` takes dp whether or not anything read the scope. A
padding and a size do not: **`ScenePadding3d` and `SceneSizedBox3d` take world
units and always will.** Convert, and nothing warns you if you forget.

Three things about the scope that are not obvious:

- **A dependent rebuilds *before* the layout that uses what it computed.** A
  camera-bound surface derives its contract during the frame, which sounds
  like a value read in `build` could be a frame behind the boxes below. It is
  not: a binding is applied from the enclosing view's per-frame clock (a
  `Ticker`, so the transient phase) or from a post-frame callback, never from
  build or layout, and Flutter's build phase precedes its layout phase. What
  *is* one frame behind on a window resize is the binding itself, which reads
  a view box that is only resized during layout — and the surface's
  constraints are one frame behind with it, derived by the same call from the
  same numbers, so the panel's size and its unit contract never disagree.
- **Reading the scope does not replace the relayout.** Writing the metrics
  relayouts the whole subtree by design (see below), because a box that sized
  itself `metrics.dp(48)` is a different box afterward and nobody hands it the
  number as a constraint. The scope adds a rebuild in front of that for the
  widgets that read it.
- **A contract written from inside a layout pass reaches the boxes and not the
  widgets, until the next frame.** `Overlay3d` does exactly that for a
  detached entry's surface. It is the one path where what `build` converted is
  stale, and it is another way of saying what the next section says: nothing on
  a per-frame path may write the metrics.

## Staying off the relayout path

**Writing `Layout3dSurface.metrics` relayouts the whole subtree, by design.**
It belongs to a window resize. Nothing on a per-frame path may touch it.

Animation has three tiers, cheapest first, and picking the wrong one is how a
smooth interaction becomes a stutter:

1. **Repaint only.** `DecoratedBox3d.decoration` and `.stateLayer` are setters
   that never touch layout — they write shader uniforms. A colour, a corner, an
   elevation, a hover state, **a press ripple**: all of this. The ripple is the
   one that runs on a `Ticker` — `flutter_scene_material3d`'s
   `MutableInkController3d` assigns `stateLayer` once a frame and nothing else
   — and `test/ink_ripple_test.dart` there counts the builds and the layouts
   across sixty frames of one to say so.
2. **Node only.** `nodeOffset` and `nodeTransform` write one matrix a frame and
   never call `markNeedsLayout`. A slide, a lift, a press, a turn.
3. **Implicit**, and only when a size really changed.

**An animation that has stopped changing should stop asking for frames**, and
saying when it has is the driver's job rather than the ticker's. A press
ripple's circle covers the control after a quarter of a second and then holds
until the finger lifts; `InkRipple3dRun.isSettledAt` is that sentence, and the
controller stops its `Ticker` on it. Two things follow that are easy to get
wrong. A `Ticker` restarted after a stop begins its clock again at **zero**, so
a driver that stops and resumes has to carry its own baseline and add the
ticker's elapsed to it. And a ticker that never stops makes
`tester.pumpAndSettle()` spin forever, so "the animation is finished" and "the
animation is *resting*" both have to end the ticking.

**A `Ticker`'s first tick is its own zero.** `tester.pump(someDuration)`
advances the clock, but the baseline is set *by* the first tick, so the first
frame after an animation starts always reports elapsed zero. A test that pumps
once and reads a radius reads nothing and concludes the animation never
started. Pump twice, or settle.

**A bar that fills is a scale, not a width**, and that is worth knowing before
you write the obvious thing. A slider's active track, a progress bar, a meter:
the natural implementation gives a box a width and changes it, which is a
relayout on every frame. A `nodeTransform` **pivots on the box's origin
corner** — `applyNodeTransform` composes `T(offset + sceneOffset + nodeOffset)
* nodeTransform * localTransform`, and `offset` is the corner — so a
full-length bar scaled on x keeps its left end exactly where layout put it and
stops wherever the value says. `flutter_scene_material3d`'s `NodeShift3d` is
that channel with a name on it, and `Slider3d` fills its track with it: twenty
frames of drag, `needsFlush` false after every one.

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
lays out and draws nothing at all. The two-line form is:

```dart
final material = await loadFmatMaterial('assets/box_decoration3d.fmat');
BoxDecoration3d.painterFactory =
    (_) => BoxDecoration3dPainter(createMaterial: () => material);
```

**And it is wrong the moment two panels differ.** `BoxDecoration3dPainter`
writes each box's parameters into the material it was handed, so one shared
material means **the last box painted wins the block** and a screen of panels
comes out in one colour, at one elevation, with one state layer. Nothing warns
you; it looks like a caching bug in the shader. `createMaterial` is called once
per box precisely so each box can have its own — but it is *synchronous* and
`loadFmatMaterial` is not, which is the whole difficulty.

The way through is `loadFmatMaterial`'s `factory` parameter, which hands you
the compiled fragment shader, the sidecar metadata and the vertex variants: one
asynchronous load captures those and a closure builds any number of further
instances synchronously afterwards. `flutter_scene_material3d`'s
`loadPanelMaterialFactory` is that, `initializeMaterial3d()` is the one call an
application makes, and `examples/render_probe` uses it — so an application
depending on the catalogue never has to write this at all. The
`material_elevation` probe is what would catch it going wrong: three panels at
three elevations that come out one colour.

**Compiling the shader is no longer your job.** The package's own
`hook/build.dart` runs `impellerc` over `assets/box_decoration3d.fmat` for
whatever application depends on it, so the source path above names a file
inside the package and resolves through the package's own generated manifest.
Your hook needs nothing in it about panels. Do not confuse this with
`buildEngineAssets`, which is a different thing: that is what makes
`Scene.initializeStaticResources()` resolve, `flutter_scene`'s own hook
already does it, and an app calls it only to put the engine's shaders in its
own bundle. See *Compiling a `.fmat`* in [engine-rules.md](engine-rules.md),
which
also covers the one migration hazard: an app that used to compile the shader
itself has a stale bundle in its `flutter_scene_generated/` and gets
*"Multiple generated .fmat materials"* until that directory is emptied once.

**A label needs a renderer, and it must not be a shared one.** `Text3d` takes
one and has none by default:

```dart
Text3d('Save', style: labelStyle, renderer: AtlasText3dRenderer())
```

**A renderer is owned by the box that holds it.** `Text3d` disposes it when a
different one is set and when the box itself is disposed, so handing the same
instance to two labels means whichever label goes first kills the other one's
renderer — it draws nothing from then on, and nothing says why. That is the
whole reason `DefaultTextRenderer3d` carries a
`Text3dRendererFactory` rather than a renderer: every label under it calls the
factory and owns what comes back. The expensive thing, the *atlas*, is shared
underneath through `GlyphAtlasCache3d.shared`, which is what makes a screen of
labels one texture; the renderer in front of it is cheap. From the widget
layer, install the default once and stop thinking about it:

```dart
DefaultTextRenderer3d(factory: AtlasText3dRenderer.new, child: app)
```

A `RichText3d` needs no renderer but does need a `SceneView` to host its
subtree; in a scene nobody is displaying it measures correctly and draws
nothing.

**A glyph's rasterization scale has nothing to do with how big the glyph is.**
`AtlasText3dRenderer` asks for `unitsPerLogicalPixel * logicalPixelsPerUnit *
resolution`, and the first two are reciprocals of each other — so the raster
scale is `resolution` (2.0 by default) and **nothing else**, whatever the type
size and whatever the surface's unit rate. Three consequences. An 18dp
checkmark and a 220dp heart are rasterized at the same texels per logical
pixel, so small type here is not a resolution problem. `glyphAtlasScaleFor`
rounds *up* to the next quarter, so a bucket is never coarser than asked for
and the 32-bucket ceiling costs nothing at a fixed `resolution`. And turning a
surface's `unitsPerLogicalPixel` up — the dial `divider_rule` and
`checkbox_mark` use to make a small component probeable — magnifies the drawn
quad and leaves the rasterization alone, which is exactly what a magnifying
glass should do and is not what it looks like it does. `resolution` is the only
dial that changes the raster, and its cost is quadratic.

Both of those are one-frame-late by nature: an atlas glyph nobody has drawn
before is read back asynchronously, and a widget capture arrives on the frame
after the subtree is hosted. A test that draws a label and reads the frame in
the same pump reads an empty frame.

**A widget leaving the tree does not dispose the layout under it.** Only a
lazily built child sets `Layout3dRenderBox.disposeLayoutOnUnmount`; every
other widget-owned layout is disposed by the surface's own teardown, and a
layout removed before that is never reached. So a `SceneText3d` taken out of a
live tree keeps its renderer, and with it whatever that renderer built, until
the surface goes. It is small, it predates the inherited default, and
`test/default_text_renderer_test.dart` pins it so that fixing it is noticed
rather than silent — but a screen that churns thousands of labels should know
about it.

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

### A padded box has six faces, and two of them are toward you

`EdgeInsets3d.all(16)` insets the front and the back as well as the four edges
you were thinking about. On a panel that is the difference between a label on
a card and a label *inside* it: the front inset pushes the child away from the
viewer, the slab it is drawn on wins the depth test, and the label vanishes
with nothing to say why. The same goes for alignment — `Alignment3d.center` is
centred *in depth*, so a label in a 4dp-thick surface sits 2dp inside it.

State the two in-plane axes and align to the face:
`EdgeInsets3d.symmetric(horizontal: 24, vertical: 10)`, and
`Alignment3d.frontCenter`. `Material3d` defaults to the latter for exactly
this reason.

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

**A flat-looking thing still needs a thickness.** A divider is a 1dp rule and
the tempting model is a decal — a slab with no depth at all. It cannot be one:
`Material3d` aligns its child to its **front face**, so a rule drawn on a card
sits exactly on the card's front plane, and two coplanar surfaces z-fight. The
rule appears in patches, differently on every frame and every driver, with
nothing to say why. `Thickness3d.thin` exists for this; `Divider3d` uses it,
and its `depth` is a separate dial from its `thickness`, which is the rule's
height *in the plane*.

**A pinned header's default lift does not separate two Material slabs.**
`SliverPersistentHeader3d.lift` defaults to one logical pixel, which is a
depth-buffer separation between two things with no thickness. A
`Thickness3d.structural` bar (8dp) over a `Thickness3d.raised` card (4dp)
needs a step above the *mean* of the two — 6dp — before the card stops poking
through the bar. `flutter_scene_material3d`'s `SliverAppBar3d` therefore sets
the lift from `Thickness3d.depthStep`, and `Scaffold3d` states the same number
once for a whole screen: each slot sits one step in front of the one behind
it, in the order `Scaffold3dSlot` declares. Anything stacking Material
components in depth should take its step from that scale rather than picking
a number.

**An overlay has to clear a whole screen, not the box it was opened from.**
`Overlay3d.defaultLift` is eight logical pixels, and its own documentation is
right that this is a depth-buffer separation rather than a distance — for two
things with no thickness. A Material screen is not two things with no
thickness: a `Scaffold3d` has already spent four `thickness.depthStep`s on its
own slots by the time anything is put in front of it, and the frontmost of them
is a slab. So a dialog at the default lift is *behind* the floating action
button it was meant to cover. `flutter_scene_material3d`'s
`Scaffold3d.overlayLift(step)` is the number — one step in front of
`Scaffold3dSlot.values.last`, 60dp at the baseline scale — and it is arithmetic
rather than a figure, so adding a slot moves the overlays with it. Anything
putting an entry in front of a Material screen should take its lift from there
rather than accepting the default.

**A scrim is a slab too, and `Overlay3dEntry.modal` does not step it.** The
entry builds its barrier and its content into a `Stack3d` with **no depth
step**, so a decorated scrim and the dialog over it sit on the same plane and
z-fight wherever the scrim shows. That is right for a barrier with no geometry
in it, which is what a menu wants, and wrong the moment the scrim is
decorated. The way through is to leave `modal` false and build the frame
yourself — a `SceneModalBarrier3d` with the scrim as its child and the content
one `depthStep` in front, in one `SceneStack3d` — which is what every modal in
`flutter_scene_material3d` does. And a scrim needs a **thickness**: a
zero-depth one is coplanar with whatever it covers, which is the same argument
`Divider3d` makes about a rule on a card.

**A panel with no ink in it draws nothing *and writes no depth*, and the
second half is the one that had to be arranged.** The panel shader declares
`blending: alpha` **and** `depth_write: true`, so a fragment with no alpha used
to occlude everything drawn after it: a fully transparent `Material3d` punched
a hole clean through the surface it was standing on, with the scene's backdrop
showing through. `examples/layout3d_gallery` showed one through its navigation
bar. The shader now discards where its own alpha is zero, which costs nothing —
such a fragment contributes no colour, and a state layer cannot rescue it
either, because the wash mixes into the *colour* and leaves the alpha alone.

**Do not "fix" this by turning `depth_write` off.** It is the engine's default
for an alpha-blended material and it is wrong here, which was established by
photographing it: with depth writing off, the whole catalogue is ordered by the
translucent pass's back-to-front sort and nothing else, and that sort is **one
number per draw** — the world-space centre of its bounds. A Material screen is
full of slabs that share a centre, because a `Material3d` hands its child a
tight depth, and a tie in that sort is not an ordering. The navigation bar came
back with no hole in it and no selection indicator either.

What is still true, and is an engine gap rather than a defect here: a
*partly* transparent slab — a 5% wash, a 32% scrim — in front of something the
sort puts after it has the same problem in a milder form. The rule that fixes
it is "a decoration whose resolved colour is not opaque does not write depth",
per instance, and `flutter_scene` 0.23.0 has no runtime flag for it —
`depth_write` is read once out of the compiled material's metadata. It is
written up in
[a transparent slab that does not erase](../packages/flutter_scene_layout3d/plans/2026_09_10_a_transparent_slab_that_does_not_erase.md)
as what to do when one lands.

**A translucent colour *is* expressible; a translucent subtree is not.** The
panel shader declares `blending: alpha`, so a `BoxDecoration3d.color` with an
alpha in it blends over what is behind — Material's black-at-32% scrim is one
colour and one slab. `ModalBarrier3d` used to say otherwise and was wrong.
What is still missing is per-node or subtree opacity: there is no way to fade
an arbitrary child, which is why a disabled control here is a token
substitution rather than a filter.

**A transparent slab standing on a surface has *two* faces to keep clear of
it.** A menu item, a snack bar's action, a navigation destination: each needs a
`Material3d` of its own so that its ink well washes itself rather than the
component around it, and each is a slab drawn on another slab's front face.
Resting it there makes its front face coplanar; lifting it by exactly its own
depth puts its *back* face there instead, which is the same fight seen from
behind. Lift it by more than its thickness — `MenuStyle3d.itemDepthStep` is
twice `itemThickness`, and asserts it.

**The rule has a name now, after the fourth component needed it.** A divider on
a card, a glyph on a navigation pill, an item on a menu surface, and then all
four selection controls at once — a checkmark on a checkbox, a dot in a radio,
a thumb on a switch track, a thumb and a fill on a slider track. Every one of
them is one Material surface drawn on another, every one of them needs a step
above the *mean* of the two thicknesses, and the first three each derived that
by hand. `Thickness3d.stepOver(back, front)` is it: twice
`minimumStepFor`, which is what `MenuStyle3d.itemDepthStep` had already chosen
by hand for two equal slabs. Reach for it rather than picking a figure, and
`Thickness3d.separates` is how a component says the figure still works.

**A flex inside a card centres its children in depth, and a label centred in a
card is *inside* it.** The other half of the tight-depth rule, and the one an
application meets rather than a component author. `Material3d` aligns its child
to its own **front face**, which is right; a `Column3d` or `Row3d` then aligns
*its* children on the depth axis by `depthAxisAlignment`, which defaults to
`center`, in the depth of its deepest child. Put a `SceneText3d` and a
`Chip3d` in a column inside a `Card3d` and the chip's 1dp makes the column 1dp
deep, the label is centred half a millimetre behind the card's own drawn face,
and it is simply not there. Two 24dp icons and a 2dp tile do it more
dramatically. `AppBar3d` says the same thing about its toolbar in its own
source — "a toolbar centred in an 8dp slab is 4dp inside it, where the surface
it is drawn on wins the depth test and the title vanishes with nothing to say
why" — and the general form is: **anything drawn on a surface states
`depthAxisAlignment: CrossAxisAlignment3d.start`, or sits inside a
`SceneAlign3d(alignment: Alignment3d.frontCenter)`.** Start is the front:
layout's z runs away from the viewer, so the axis begins at the face you are
looking at.

**A `Material3d` gives its child a *tight* depth, so a thicker child is
silently clamped to it.** This is the one that decides how a two-part control
has to be built. `Material3d`'s thickness is a tight depth constraint on its
own container, and `Constraints3d.enforce` clamps a child's wish into it — so a
`Thickness3d.standard` (2dp) thumb placed **inside** a `Thickness3d.thin` (1dp)
track comes out 1dp, with nothing to say why, and the "stand proud of it" step
is then computed from a thickness the slab does not have. Two surfaces of
different depths have to be **siblings** in a `Stack3d`, not one inside the
other. `Switch3d` and `Slider3d` are both built that way, and
`test/selection_test.dart` pins the thumb's 2dp with that reason in the test.

**A lift written into a child's *position* takes it out of reach of a ray, and
nothing says so.** This is the sharpest edge on this page, because everything
about the screen still looks right. Toward the viewer is **negative z**, so a
slot lifted that way sits outside its parent's own extent — and
`Layout3d.hitTest` clamps the ray to the stretch inside each box *before* it
asks that box's children, which is exactly what Flutter's
`size.contains(position)` gate does in two dimensions. The lifted child is
never reached. `ParentData3d.sceneOffset`'s own documentation has said this
from the start — "separating them in the layout would push them out of their
parent's box, break a `Positioned3d` pin, and take the topmost child out of
reach of a ray" — which is why `Stack3d.depthStep` is a scene offset rather
than a position.

`Scaffold3d` wrote its depth ordering into `positionChild` instead, and its own
dartdoc claimed that made layout, intrinsics and hit testing agree. The
opposite was true: **every slot of every Material screen was unpressable**, the
scaffold's own backing answered every hit, and 488 headless tests and 75 render
probes all passed, because nothing in either suite pressed a control that was
inside a `Scaffold3d`. Running the gallery is what found it. The fix is the
node tier — the slots are positioned at z zero and their *geometry* is moved by
a `NodeShift3d`, whose `worldTransform` undoes the shift so a ray still finds
the box where layout put it. **Depth separation belongs on the node tier. If
you find yourself writing a negative z into an offset, that is the bug.**

**`Dismissible3d`'s backgrounds are coplanar with the child.**
`backgroundDepthStep` defaults to zero, exactly as `Stack3d.depthStep` does,
so the background revealed by a swipe and the row sliding off it sit on the
same plane and z-fight where they overlap. That is the right default for a flat
Material row — the child covers the background until it moves, so there is
nothing to fight over — and the wrong one the moment either has depth. A small
positive step pushes the backgrounds away from the viewer and the fight stops.

### A shared glyph atlas repacks, and a panel that has stopped laying out
loses its labels

`GlyphAtlasCache3d.shared` is shared by every `AtlasText3dRenderer` in the
application, and reserving a glyph in it can repack the whole atlas — which
invalidates every texture coordinate already baked into every mesh drawn out of
it. `AtlasText3dRenderer` used to answer that by dropping its mesh and waiting
for the box to lay out again, on the reasoning that a repack only happens while
something is laying out. It does — but not necessarily *that* box. A second
surface added to the scene draws a letter the first did not have, the atlas
repacks, and a panel whose labels were laid out once and thereafter only
*turned* never rebuilds them.

It now bakes them again from what it already cached, without a layout.

**And the half that looked like a repack was not one at all.** A screen still
lost letters after that, and the cause was in `flush`: `rasterize` records its
picture of the atlas *synchronously* and then awaits `toImage`, so a glyph
reserved during that await is missing from the image — and a reservation that
finds free space **does not repack**, so the generation has not moved to say
the image is stale. Clearing `needsRaster` on it lost those glyphs for good.
`GlyphAtlas3d.revision` is the counter that says so: `generation` answers *are
my texture coordinates still valid*, `revision` answers *is my picture of the
atlas still complete*, and only the second one moves when a glyph is reserved.

The reason it took a gallery to find is worth keeping: one surface reserves its
whole alphabet in a single layout pass, which grows the atlas, and a repack
*does* move the generation — so the raster is discarded as stale and everything
is drawn again. **An atlas that grows hides this.** A second surface laying out
against an atlas that is already big enough is what exposes it, and until the
gallery every render probe drew one surface and every headless test measured
type rather than rasterizing it. `examples/render_probe`'s
`two_surfaces_of_type` is the scene that pins it now, and its atlas is built
with `initialSize` equal to `maxSize` for exactly that reason.

One more thing behind the same door: **a black rectangle where a label belongs
is a glyph mesh with no texture**, not a quad sampling empty atlas. An empty
atlas region has zero alpha and draws nothing; `UnlitMaterial` binds a 1x1
*white* placeholder when no texture is set, so the quads come out solid in the
label's own colour. The renderer zeroes its colour factor until the pixels
arrive.

## Pointers

- **`TapTarget3d` grows the ray region but not the box.** The Material 48dp
  minimum is invisible to layout, to intrinsics, to `ensureVisible3d` and to
  semantics, which announces the smaller rectangle. Deliberate — it keeps
  neighbours from moving when a target is padded — but sharp.
- **A press in the margin arrives at the control's centre.** When the ray
  misses the child's own extent but is inside the grown region, the target
  tests its children a second time with the ray aimed at the middle of the
  box, and whatever answers is reported there — Flutter's `_InputPadding`
  does the same thing with `MatrixUtils.forceToPoint`, and for the same
  reason: the centre is the one point every box below agrees is inside
  itself. Only the hit test that *captures* a path is affected, so a drag
  begun in the margin reports real positions from its second event onward
  and its first one jumps.
- **A target has to sit outside every box whose extent it is growing.** This
  is the rule that makes the reach usable, and it is the one that cost the
  time. A `TapTarget3d` reaches beyond its own extent and **its parent does
  not**: every box gates its children on its own size, so a target nested
  inside something no bigger — a Material panel around an ink well — is
  rejected a level above and never sees the ray. Nothing inside the target
  can reach past its own parent. Flutter puts the input padding outside the
  `Material` for exactly this reason, and so does
  `flutter_scene_material3d`'s button: `SceneSemantics3d` >
  `SceneTapTarget3d` > `Material3d` > `InkWell3d`, with the ink well's own
  `minimumSize: Size3d.zero` so there is one target rather than two nested
  ones disagreeing about where the control is.
- **A second affordance *inside* a component gets neither a reach nor a wash.**
  A chip's delete icon is the case: a `TapTarget3d` there is gated by the
  chip's own panel, so its 48dp would be silently inert, and an `InkWell3d`
  there would find the *enclosing* `Material3d`'s ink controller and light the
  whole chip up. What works is a plain `SceneGestureDetector3d` with its own
  `SceneSemantics3d` — the innermost recognizer wins the arena, exactly as in
  Flutter, so the inner affordance takes the tap and the component does not.
  What it costs is that the inner target is exactly its own extent. Anything
  better needs a second surface, and a second surface inside a 1dp slab is
  coplanar with it.
- **A navigation bar is the case where a second surface is worth it.** Five
  destinations sharing the bar's ink controller would light the whole bar up
  under one finger, and a bar is 8dp deep, so a `Thickness3d.thin` slab per
  destination has room to stand proud of it rather than fighting it. That is
  what `flutter_scene_material3d`'s `NavigationBar3d` does: each destination is
  a transparent `Material3d` of its own with its own `InkWell3d` inside it.
- **A `Text3d` answers hit tests on its own account**, so a label inside a
  button usually wants an `IgnorePointer3d` around it. Inside a control it is
  harmless — the gesture detector is on the path either way — and it matters
  for a label that has to let a ray through to something behind it.
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
- **Nothing anchors anything, and the arithmetic that does is public now.**
  An `Overlay3dEntry` is placed by the overlay's own `Stack3d.alignment`,
  which is nowhere near the box that asked for it, and there is no
  `CompositedTransformTarget` here. `Layout3d.anchorOffsetTo` is the answer:
  the anchor's point taken into the world through `worldTransform` and back out
  in the follower's own frame. It answers a **`nodeOffset`**, so anchoring is
  the node tier and costs one matrix — and it is a *position* rather than a
  delta, because `worldTransform` reports the frame layout put the box in with
  the node nudges undone. Assign it; do not add it.
- **And `screenPointOf` on an anchored box lies.** The same property that makes
  re-anchoring safe makes the projection disagree with the picture:
  `worldTransform` undoes `nodeOffset`, so `screenCenter` and `screenPointOf`
  report where layout put a follower rather than where it is drawn. A render
  probe of an anchored overlay has to use the **anchor** as its oracle.
  `examples/render_probe`'s `menu_at_its_button` does exactly that.
- **A follower needs more than one hook to follow.** `Layout3d.place` fires on
  a box that moves and **not** on the boxes below it, so a follower watching
  its anchor's `place` hears about a row moving inside a list and hears nothing
  at all about the *ancestor* of its anchor moving — which is what a scroll
  does, and is the case a first attempt will miss. Watch the follower's own
  `place`, the anchor's, and a post-frame callback for the rest. The last one
  schedules no frame of its own, so a still screen costs nothing.
- **A hover listener over an arbitrary child has to be opaque.**
  `InkWell3d`'s is `deferToChild`, correctly: a control is hovered exactly
  where it is pressable. A `Tooltip3d` wraps whatever it is given — a bare
  label, an icon, a `SizedBox3d` — and most of those answer no ray at all, so a
  deferring listener never sees a pointer. Its own extent has to be the hover
  region. The control inside still takes every tap, because children are tested
  before their parent.
- **Feedback under the pointer must be wrapped in an `IgnorePointer3d`**, and
  `Draggable3d` does it for you. Hit testing ignores `nodeOffset`, so a piece
  of feedback moved on the node tier is invisible to the ray moving it — but
  its *laid-out* position is not, and a `Text3d` inside it would answer there
  and steal the drop.

## Semantics

**A `Semantics3d` publishes what it is given and gathers nothing.** Flutter's
`Semantics(container: true)` merges the labels of the widgets below it, so a
button wrapped around a `Text('Save')` announces "Save" without anyone saying
so. There is no such merge here: a `SemanticsComponent` hangs off one scene
node and there is no semantics tree under it to fold up. **A component states
its own label** — `Button3d.semanticLabel`, `Icon3d.semanticLabel` — and one
that does not announces itself as a button with no name.

**A component with two labels has to decide which one it is.** A button
wrapping one word can say "state a `semanticLabel`" and be done. A row with a
title *and* a subtitle cannot: there is no answer that does not throw one of
them away, and the merge that would have joined them does not exist. The
catalogue's answer is to take the strings rather than the widgets where it
can — `ListTile3d.text(title: 'Inbox', subtitle: '12 unread')` builds both the
labels and the announcement, `'Inbox, 12 unread'` — and to be explicit that
the widget-taking constructor announces only what it is told. A component that
composes an announcement out of what it was handed is doing by hand exactly
what Flutter's merge does for free, and it is the only place the work can go.

**Announcing nothing is sometimes the right answer.** A divider publishes no
semantics at all, and Flutter's own does not either: a reader that said
"divider" between every pair of rows would be worse than one that skipped it.
State that decision out loud where a reader of the code will find it, or the
next person will read it as an omission and fix it.

**The rectangle the reader focuses is the box's own extent, not its tap
target.** `Semantics3d` overrides the component's projected bounds with its
`Layout3d.size`, which is the right answer — it is what layout produced — and
it means a 40dp button announces 40dp while answering a finger over 48dp.

## Clipping

**A corner radius is not a clip.** `Clip3dRegion` is an intersection of planes,
and a plane region is convex; a radius cannot be expressed that way. The panel
shader carves the radius out instead.

Clipping has three tiers: whole-node culling (free, exact for boxes entirely
outside), clip planes packed into a material (`toPlaneBlock`, for a child that
is *half* in — only the shipped panel shader reads them so far), and nothing.
The seam is `Layout3d.clipRegion` → `Decoration3dPaintRequest.clip` →
`toPlaneBlock()`, and it is live: a row half under a pinned
`SliverPersistentHeader3d`, or half out of a scrolling window, is genuinely
cut at the edge.

**It has been dead twice, in two places, and both times only a picture said
so.** This is the failure shape to remember, because any tier like it can fail
the same way and no arithmetic test can see it. A box publishes its clip block
from `repaint()`, at the end of its own `performLayout`, and
`Layout3d.clipRegion` goes on answering correctly to anything that asks after
the pass — so the block a shader is actually handed and the region the code
reports are two different things, and only the first one cuts anything.

- **A `ClipBox3d` has no extent while its subtree lays out** — it is a proxy
  that takes its size from its child — so every panel under it was born with
  the unbounded block, and a scroll (which *places* rows rather than relaying
  them out) never replaced it. Found in phase 4 of the Material catalogue.
- **A viewport does not know what a pinned header is sitting on until after
  it has laid the rows out.** `CustomScrollView3d` clears its obstruction map
  at the top of every pass and fills it in as each sliver is placed, so a row
  asking for its clip during the pass is told, correctly for that instant and
  uselessly, that nothing covers it. Found in phase 5, in the scene the
  contract was designed for.

The general rule underneath both: **a clip that is discovered after the boxes
under it have painted has to be republished, and nothing warns you.**
`Layout3d.refreshClipRegion` is the hook and `Layout3d.refreshClipSubtree` the
bulk form; `ClipBox3d` calls it once it has a size, `Layout3d.place` calls it
down whatever it just moved, and `CustomScrollView3d` calls it on every sliver
a header covers once the layout has settled. `test/clip_test.dart` and
`test/persistent_header_test.dart` pin all three with a painter that records
the clip it was handed, which is the only way to see a shader uniform without
a shader.

**And a full-width opaque bar makes the clip invisible**, which is why the
second failure lasted so long. The bar covers exactly what the clip would cut.
The clip is one plane across the scroll axis, cross-axis-wide, so it shows
where the bar does *not* cover — beside a narrow bar, through a translucent
one — and `examples/render_probe`'s `sliver_app_bar_clip` scene is built
around a half-width bar for that reason.

**A depth clip cuts the box's *layout* depth, not the drawn geometry.** The
planes are expressed in the box's own frame, and `BoxDecoration3d.elevation`
moves the slab's *node*, outside that frame. So `ClipBox3d(clipDepth: true)`
does not slice a raised card off flush with the list holding it, and
`Clip3dRegion.rect` leaving depth alone is the same decision stated twice:
a raised card inside a scrolling list stands proud of it.

## When testing a component headlessly

Three things that cost time in phase 5 and are invisible from the code.

- **A surface's constraints are tight, and `SceneSizedBox3d` enforces its
  parent's.** A bar pumped straight onto a `SceneLayout3d(size: …)` comes out
  the height of the whole surface, because `Constraints3d.enforce` clamps a
  child's wish into what the parent allows and the parent allows exactly one
  height. Every figure a test then measures is the surface's. Put the
  component in the shape a real screen has — a `SceneColumn3d` with
  `CrossAxisAlignment3d.stretch` and an expanded sibling — and the main axis
  is loose again.
- **A `const` constructor's asserts run at compile time, and `List.length` is
  not a constant expression there.** A component that wants to refuse a
  one-element list cannot do it in a `const` constructor without giving up
  `const`, which is what makes an unchanged rebuild free. Move the check to
  `build`, where it is just as loud, and say in the class why it is there;
  `NavigationBar3d.tooFewDestinations` is the shape. A test then asks
  `tester.takeException()` rather than `throwsA`.
- **A widget-built overlay entry's content arrives one frame late.** Inserting
  a `WidgetOverlay3dEntry` — which is what `showDialog3d` and every other
  overlay in the catalogue does — marks the widget that owns the overlay as
  needing to build, so the subtree exists on the *next* frame. Flutter's own
  `Overlay` behaves the same way. The entry, the route and its future all exist
  from the call; only the geometry waits. A test that opens something and
  asserts in the same turn sees an overlay with one entry and no boxes in it:
  `await tester.pump()` once.
- **A `Layout3dPointer` carries the live sequences, so make one and keep it.**
  A test helper that spells `pointer` as a getter returning
  `Layout3dPointer(surface)` hands out a fresh instance per statement, and the
  `up()` then lands nowhere: the press never ends, the state never leaves the
  set, and the next `down()` is swallowed as a state that is already in force.
  Every symptom is a plausible wrong answer rather than an error — a ripple
  that keeps the previous press's origin, a cancel that lights nothing up, a
  wash that never fades — which is what makes it expensive. Hold one in a
  field.
- **A component has two `TapTarget3d`s per control, not one.** The outer one
  carries the 48dp reach and the `InkWell3d`'s own sits inside it at
  `Size3d.zero` — one target rather than two nested ones disagreeing about
  where the control is. A test looking for "the target" wants the one with a
  non-zero minimum.

## When probing a rendered frame

Two more, specific to `examples/render_probe` and worth knowing before you
write a scene there.

- **`screenBounds` bounds all eight corners, including the depth extrusion.**
  On a slab with any depth its corners sit outside the front face, so probing a
  *face* wants `screenPointOf` with an explicit `z` fraction.
- **A level camera cannot see a ground plane.** `LayoutBasis3d.xz` viewed from
  `y = 0` is exactly edge-on: every point lands on the horizon line and near is
  indistinguishable from far. Raise the camera.
- **A lazily built list cannot be flushed from outside a layout pass.** A
  `SceneListView3d.builder`'s children are created inside
  `RenderObject.invokeLayoutCallback`, which asserts it is inside Flutter's
  own layout phase — so `surface.flush()` from a test body or a probe scene
  blows up with `_debugDoingLayout is not true`. Drive it through the pipeline
  instead: `controller.jumpTo(...)` and then `await tester.pump()`. A list
  given an explicit `children:` list has no such problem, and no laziness
  either: forty widgets in the tree are forty layouts whatever the window
  shows.
- **A dark theme is invisible to this harness.** The probe clears to
  `#101820`, and `FrameProbe` decides "is this pixel geometry" by distance
  from the clear colour. Material 3's dark surface is `#141218`, which is
  inside that tolerance — so a dark panel reads as background, every coverage
  comes out zero, and the scene looks like it never drew. The catalogue scenes
  use the light theme, whose near-white surface is unmistakable, and say so.
- **A hand-picked threshold is a distance wearing a direction's clothes.** The
  rule below says to assert an order rather than a difference, and the way it
  is broken in practice is subtler than a bare `!=`: an assertion like "the
  thumb is lighter than the track *by more than 0.2*" reads like a direction
  and is a magnitude nobody can justify. Phase 7's switch scene failed on
  exactly that, by a thousandth — the thumb was drawn perfectly and the number
  was invented. What the question actually wanted was a **channel order**: the
  track is a purple and reads with blue above red, the thumb is near white and
  reads neutral, so "the thumb carries less of the track's purple than the
  track does" compares two quantities of the same kind and has no threshold in
  it at all.
- **A scene has to be built so the order it asserts is a real question.** The
  rule below and the one above it say what *not* to assert. This is the other
  half, and phase 8's ripple scenes are the case: three moments of one
  animation, and the first attempt had the second and third both covering the
  whole sample grid, because `Curves.ease` is 95% of the way home two thirds of
  the way through. The fix is never a looser assertion — it is choosing the
  moments and the sample grid *together* so the counts come out well separated
  and every reading is several pixels clear of the edge the claim turns on.
- **A difference is not a direction, and a shader test wants the direction.**
  "The rim of this panel is a different colour from its middle" is satisfied
  just as well when the two are swapped, which is exactly how the panel shader
  came to ship with its border drawn inside out — the fill as a thin rim
  around a panel entirely in the border colour, past sixty-two headless tests
  that all checked the parameters and never the picture. Ask which colour is
  where, by a comparison lighting and tone mapping cannot reorder: a channel
  order (`r > b`), a luminance, an occlusion. Not a distance.
