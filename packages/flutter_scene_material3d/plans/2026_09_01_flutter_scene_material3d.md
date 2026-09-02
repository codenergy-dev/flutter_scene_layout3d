---
status: in progress
reason: phases 0 and 1 are done — the package exists, with its token families, Theme3dData and SceneTheme3d, on 80 headless tests. Phases 2 to 9, every component in the catalogue, are open
created_at: 2026-09-01T19:15:00Z
updated_at: 2026-09-02T00:00:00Z
commit: 52a2ca7b6a176cf70b5bef6b6b92ff7e7cbf82bd
---

# Material, when a component has a thickness

This is the package the layout protocol was built for. `flutter_scene_layout3d`
arranges boxes on a plane in a real 3D scene and, with the readiness work
closed, it can also draw them: a panel with a corner radius, a label out of a
shared glyph atlas, a state layer, a lift toward the viewer. What it has no
opinion about is *what a button looks like*. That is this package.

The goal is a catalogue a Flutter developer can read without a manual —
`Button3d`, `Card3d`, `ListTile3d`, `Scaffold3d`, `AppBar3d`, `Dialog3d`,
`Switch3d` — spelled the way Flutter's Material library spells them, and built
as geometry rather than as a picture of geometry.

The thing to understand before writing a line of it: **Material 3 is a
specification for a flat surface, and every token in it that stands in for
depth has to be re-derived here, because here the depth is real.** An
elevation is a shadow in Flutter and a distance here. A ripple is an expanding
circle in Flutter and a uniform in this shader. A disabled control is 38%
opacity in Flutter and there is no opacity here at all. Half of this plan is
the design work of answering those honestly; the other half is a long, ordinary
list of components.

Read [the readiness overview](../../flutter_scene_layout3d/plans/2026_08_25_material3d_readiness_overview.md)
first — it is the map of the ten plans that built the protocol underneath, and
its *What is still missing* section is the list of things this package has to
work around rather than wait for.

## What exists today

### What the protocol already gives a catalogue

Everything a component is made of, with one exception per section below:

- **A panel.** `DecoratedBox3d` with a `BoxDecoration3d`: colour, per-corner
  `BorderRadius3d`, `Border3d`, `bevel`, `elevation`, `surfaceTint`, and a
  `StateLayer3d` carried on the box rather than on the decoration so a hover
  never touches layout. One SDF shader, `assets/box_decoration3d.fmat`, at any
  size, with `Decoration3dPainterCache` collapsing a screen of panels onto a
  handful of materials.
- **A label.** `Text3d` over Flutter's own `TextStyle`, measured through a
  prepare/layout split that keeps font work off the relayout path, drawn by
  `AtlasText3dRenderer` out of `GlyphAtlasCache3d.shared` — so a screen of
  labels is one texture — with `RichText3d` as the escape hatch for what an
  atlas cannot assemble.
- **The unit contract.** `Layout3dMetrics.dp()` and `.sp()`, so a spec figure
  written in logical pixels is correct at any surface scale, plus
  `VisualDensity3d` (standard, comfortable, compact) already sitting beside
  them, waiting for exactly this package.
- **Interaction.** `GestureDetector3d` over Flutter's own arena, `TapTarget3d`
  with `materialMinimum = 48.0` already named, `Focus3d` and `Focus3dTraversal`,
  `Layout3dPointerGroup` for a ray crossing surfaces, and the whole drag lane:
  `Draggable3d`, `DragTarget3d`, `Dismissible3d`, reorderable lists, autoscroll.
- **Structure.** `Overlay3d` with per-entry `OverlayLayer3d`, `ModalBarrier3d`,
  `FocusScope3d`, `Navigator3d` with `Route3d` and `Route3dTransition` — which
  is a dialog, a menu, a snack bar and a bottom sheet, once something knows
  what those look like.
- **Slivers and scrolling**, including `SliverPersistentHeader3d` that pins and
  genuinely clips the content sliding under it, which is `SliverAppBar3d`.
- **Accessibility.** `Semantics3d` takes Flutter's `SemanticsProperties`, so
  `button: true` and a label are already expressible.

### The four things that blocked the first component, and what they are now

All four landed in `flutter_scene_layout3d`, under
[its own plan](../../flutter_scene_layout3d/plans/2026_09_01_the_four_things_before_a_component.md),
before this package had a `pubspec.yaml` — which was the point: a catalogue
written around the absence of any of them would have had to be unwritten
afterwards. What exists now:

1. **The declarative layer can draw.** `SceneDecoratedBox3d` is the widget
   form of `DecoratedBox3d`, with `decoration` and `stateLayer`, and a test
   states the promise the class exists for: a rebuild that changes only the
   state layer marks nothing dirty for layout. `lib/widgets.dart` now exports
   the decoration types too — `BoxDecoration3d`, `Border3d`, `BorderRadius3d`,
   `StateLayer3d`, `BoxDecoration3dPainter` — which it did not, and which is
   why the gap was invisible from that side. The two `drag.dart` dartdoc
   examples compile now, and a test compiles them.

   **`SceneContainer3d` did *not* gain a `decoration`, deliberately**, and a
   `Material3d` should not expect one. Flutter's `Container` can afford one
   because it is a composition, with `DecoratedBox` still the single
   implementation; `Container3d` is one `Layout3d`, so a decoration on it
   would be a second copy of the painter lifecycle, and Flutter's own
   semantics (inside the margin, around the padding) names a rectangle that is
   not the box's own size and that `Decoration3dPaintRequest` cannot describe.
   `Material3d` is a `SceneDecoratedBox3d` with the theme resolved into it,
   exactly as *The design* below says, and a component that wants padding
   composes a `SceneContainer3d` inside it.

2. **There is a default text renderer.** `DefaultTextRenderer3d` sits beside
   `DefaultTextStyle`; every `SceneText3d` below it gets a renderer, and one
   that states its own overrides it. Install it once:

   ```dart
   DefaultTextRenderer3d(factory: AtlasText3dRenderer.new, child: app)
   ```

   **It carries a factory, not a renderer**, and a catalogue has to know why:
   a `Text3dRenderer` is *owned* by the box that holds it — `Text3d` disposes
   it — so one inherited instance would be disposed by whichever label left
   the tree first and every other label would silently stop drawing. Each
   label calls the factory and owns what comes back; the atlas underneath is
   what is shared. Keep the function stable (a tear-off, or a field on a
   `State`): a closure written inline in `build` is a new function every build
   and rebuilds every renderer in the tree. `Text3d.rendererFactory` is the
   same seam in the imperative layer.

3. **There is somewhere tree-wide to put a theme.** `Layout3dSlot<T>`,
   `owner.slot(key)` / `owner.setSlot(key, value)`, `Layout3d.slot(key)` for a
   box reading it inside `performLayout`, `Layout3dSurface.setSlot` for the
   write that relayouts, and two widget forms: `SceneLayout3d.slots` for a map
   on the surface, `SceneSlotProvider3d` for a provider *inside* the tree —
   which is where `SceneTheme3d` will want to sit, since it is also an
   `InheritedWidget` for the widget layer.

   Three things settled that a `Theme3dData` design has to honour. **A slot is
   its type and its name**, not an identity: Dart canonicalizes `const`
   instances, so identity keying would behave one way for a `const` slot and
   another for a `final` one. Name it `'material3d.theme'`. **Writing one
   relayouts the subtree** by default, as writing the metrics does, so a theme
   change is a relayout and nothing per-frame may touch it — which is right,
   since the tokens decide paddings and type sizes. **The surface stores the
   value and does not own it**: nothing is disposed when the surface goes.

4. **Compiling the panel shader is this package's job now, not an
   application's.** The question was answered by doing it: a package's own
   `hook/build.dart` *does* run when the package is a dependency.
   `flutter_scene_layout3d` has one, it runs `impellerc` over
   `assets/box_decoration3d.fmat`, and `examples/render_probe` passes all
   forty of its tests with its own `buildMaterials` call and its symlink
   deleted. A consumer writes nothing about panels in its hook.
   `buildEngineAssets` is a separate concern and stays one: it is what makes
   `Scene.initializeStaticResources()` resolve, `flutter_scene`'s own hook
   already does it, and an app calls it only to keep its own copy of the
   engine's shaders. **A library must never call it** — two copies in one
   bundle — which is a rule this package inherits the day it ships a hook.

   This package will need the same arrangement the day it ships an asset of
   its own — a hook, `flutter_scene_generated/` listed in its pubspec under
   `flutter: assets:`, and that directory present with the engine's
   `.gitignore` in it. It does not need one to compile a shader it does not
   own.

## What Material means when the depth is real

The four questions this package exists to answer. Each one has a Flutter answer
that does not survive the move, and getting them wrong produces a catalogue
that looks like a screenshot of Material rather than an object.

### Elevation is a height, and it casts no shadow

Material's elevation model is entirely shadows: level 0 to level 5, each a
published shadow recipe plus, in Material 3, a surface tint. Here
`BoxDecoration3d.elevation` lifts the geometry toward the viewer by
`metrics.dp(elevation)` and `surfaceTintOpacityFor` already implements M3's
tint table — but **there is no shadow, and the engine will not give one**:
`box_decoration3d.fmat` declares `blending: alpha` because its antialiased
outline *is* an alpha, and `flutter_scene`'s `ShadowEncoder` drops every
non-opaque material before the shadow pass. `examples/render_probe`'s
`panel_shadow` scene is the standing proof, and it fails the day that changes.

So a raised card here reads as raised through parallax, occlusion and tint, not
through a shadow, and the catalogue's job is to make that read *correctly*
rather than to pretend:

- Keep the tint. It is the half of M3's elevation model that transfers intact,
  it is already implemented, and it is what distinguishes a level-3 surface
  from a level-1 one when the camera is head-on and parallax gives nothing.
- Give `Material3d` an opt-in `shadowCatcher` — the engine's
  `ShadowCatcherMaterial` on a plane behind the component — for the one case
  that wants a contact shadow badly enough to pay for a second surface. Design
  it, do not build it in phase 1.
- Say the elevation levels in dp and let the metrics scale them.
  `Elevation3d.level1 = 1.0` through `level5 = 12.0`, M3's own figures.

### Disabled is an opacity, and there is no opacity

Material draws a disabled control at 38% opacity over the enabled one. There is
no subtree opacity in this stack and there cannot be until `flutter_scene`
grows a per-node opacity the materials honour — `Node` in 0.23.0 has `visible`,
a selection-outline `highlightColor`, layer and light masks and shadow flags,
and no opacity or tint of any kind. The size-driven geometry plan's own rule is
not to ship an `Opacity3d` that only works on `BoxDecoration3d`.

**Express disabled as token substitution, not as a filter.** A disabled state
resolves to different colours — `onSurface` at 38% alpha, `onSurface` at 12%
alpha for the container — which is what M3's own spec says the *result* is, and
both a `BoxDecoration3d.color` and a `TextStyle.color` take an alpha. It is
more faithful than a filter would be, it costs nothing, and the only thing it
cannot do is fade an arbitrary child subtree — which a catalogue does not need
and an application occasionally will. Write that down where an application
author will find it.

### A ripple has an origin, and the state layer does not

`StateLayer3d` is one colour and one opacity across the whole box: hover,
focus, press, drag. That is exactly M3's *state layer*, and for hover and focus
it is complete. What it cannot express is the press ripple expanding from where
the finger landed.

The shader can, and cheaply. Its whole trick is that the slab's vertex colours
are its own object-space coordinates, so the fragment shader already knows
where in the box it is — which is the hard half of a ripple. Two more
parameters (`ripple_origin` as a `vec2` in the box's own frame, `ripple` as
radius and alpha) and one `smoothstep` add it, with the animation driven by the
repaint-only tier that `DecoratedBox3d.stateLayer` already sits on.

**Phase it.** Ship uniform state layers first: they are honest M3 for hover,
focus and drag, and a press that fades in and out is not wrong, only plainer.
Add the ripple as its own phase with a render probe that watches the lit
fraction of the panel grow — which is a claim only a drawn frame can check, and
exactly the kind that the harness was built for.

### Every component needs a thickness, and Material has no token for it

This is the one with no Flutter answer at all. A `Card3d` is *how deep*? M3
publishes a shape scale (corner radii), a type scale and elevation levels; it
publishes nothing about thickness, because on a screen there is none.

The catalogue has to invent that scale, and it should invent it once, in the
theme, rather than component by component:

```
Thickness3d.thin        // 1dp — a divider, an outline, a chip
Thickness3d.standard    // 2dp — a button, a text field, a list tile
Thickness3d.raised      // 4dp — a card, a dialog, a menu surface
Thickness3d.structural  // 8dp — an app bar, a navigation bar, a sheet
```

Two rules that come out of the traps and that a component author will otherwise
learn the expensive way:

- **A thickness fights the depth ordering.** `Stack3d.depthStep` does not
  separate children thicker than the step, so a component thicker than the
  stack that holds it wins the depth test against something drawn in front of
  it. Keep the scale small relative to the steps the layout uses, and let the
  theme carry both numbers so they can be reasoned about together.
- **A thickness is not free at the edges.** `bevel` rounds the slab's rim along
  the depth axis; a 4dp-thick card with a 12dp radius and no bevel has a hard
  square edge where a real object would not. Give the shape tokens a bevel
  proportional to the thickness.

## The design

### The tokens, and where they live

Four token families, each a plain value type with `lerp` (so the implicit
animation tier works on them) and const constructors for M3's baselines:

- **`ColorScheme3d`** — M3's roles verbatim: `primary`, `onPrimary`,
  `primaryContainer`, `surface`, `surfaceContainerHighest`, `outline`,
  `error`, and the rest. Generated from a seed is out of scope; hand-written
  light and dark baselines are not.
- **`Typography3d`** — the M3 type scale (`displayLarge` … `labelSmall`) as
  Flutter `TextStyle`s in logical pixels, which `Text3d` already consumes and
  `metrics.sp()` already scales.
- **`ShapeScale3d`** — `none`, `extraSmall` (4dp) … `full`, as
  `BorderRadius3d`, with the bevel rule above folded in.
- **`Elevation3d`** and **`Thickness3d`** — the two depth scales, in dp.

`Theme3dData` holds the four plus a `VisualDensity3d`, and reaches the tree
through the owner slot from blocker 3, with a `SceneTheme3d` widget that writes
it and a `Theme3d.of(context)` for the widget layer. **A component reads the
theme; it does not read `metrics` directly** — the theme is what turns a token
into the dp figure that `metrics` then turns into world units, and keeping that
one-way makes a component's numbers auditable.

*Shipped as written, with two corrections recorded in* What phase 1 found:
`Elevation3d` and `Thickness3d` are two classes rather than one family, so
`Theme3dData` holds five plus the density; and the density was already on
`Layout3dMetrics`, which this section did not know.

### `Material3d`, the one primitive everything else is

Flutter has `Material`, and every component in its catalogue is one. Do the
same, for the same reason: it is the single place that owns the surface, the
shape, the elevation, the state layer and the ink.

```dart
Material3d({
  Color? color,               // defaults to theme.colorScheme.surface
  BorderRadius3d? shape,      // defaults to theme.shape.none
  double elevation = 0.0,     // dp, lifts and tints
  double thickness,           // dp, defaults to Thickness3d.standard
  Border3d border = Border3d.none,
  Widget child,
})
```

It is a `SceneDecoratedBox3d` with the theme resolved into it, and it is what
makes the catalogue consistent: if a component wants a different shape, it
passes a different token, and there is exactly one class that knows how a
token becomes a `BoxDecoration3d`.

`InkWell3d` sits on top: a `SceneGestureDetector3d` and a `SceneFocus3d` that
drive the `stateLayer` of the `Material3d` above them through the repaint-only
tier, plus a `SceneTapTarget3d` at `materialMinimum`. **Nothing in that path
may touch layout**, and `test/` proves it the way the animation plan does — by
asserting a hover marks nothing dirty.

### Icons are a font, until proven otherwise

`Icon3d` is very likely a one-glyph `Text3d` with
`TextStyle(fontFamily: 'MaterialIcons', package: null)` and an `IconData`'s
code point, drawn through the same atlas as every label — which would make it
nearly free and automatically batched. **Verify this in the first hour of phase
2**, with a render probe, because the whole `Icon3d` design depends on the
answer: if the atlas rasterizes an icon-font glyph, `Icon3d` is thirty lines;
if it does not, an icon is a mesh or a texture and it is a phase of its own.

The known wrinkle either way: `AtlasText3dRenderer` draws with an
`UnlitMaterial`, so a label and an icon do not respond to the scene's lights
while the panel under them does. That is defensible — text that dims as a
surface turns away from a light is unreadable, and Flutter's own text is
unlit by construction — but it means the colour tokens have to be chosen
against the *unlit* label and the *lit* panel, and a catalogue that ignores it
will have contrast that drifts as the surface turns.

## The work

- [x] **Phase 0 — the four blockers, in `flutter_scene_layout3d`.** Done, as
      [its own plan](../../flutter_scene_layout3d/plans/2026_09_01_the_four_things_before_a_component.md).
      `SceneDecoratedBox3d` and the decoration exports;
      `DefaultTextRenderer3d` and `Text3d.rendererFactory`; `Layout3dSlot<T>`,
      `Layout3dOwner.slot` / `setSlot`, `Layout3dSurface.setSlot`,
      `SceneLayout3d.slots` and `SceneSlotProvider3d`; and the layout package
      compiling its own panel shader from its own build hook. The two
      `drag.dart` dartdoc examples compile, and a test compiles them. 891
      headless tests, 40 render probes, `dart analyze` clean. Two of that
      plan's expectations turned out wrong and are worth reading before
      building on them: `SceneContainer3d` has *no* `decoration`, with reasons,
      and a slot is keyed by value rather than identity.
- [x] **Phase 1 — the package and the tokens.** Done.
      `packages/flutter_scene_material3d` is in the workspace, depends on the
      layout package by path, and ships no build hook. `ColorScheme3d` (46
      roles, light and dark), `Typography3d` (15 styles), `ShapeScale3d` (7
      steps plus `bevelFor`), `Elevation3d` and `Thickness3d` (with
      `depthStep`, `minimumStepFor` and `separates`), `Theme3dData` holding
      all five plus a `VisualDensity3d`, a `Tween` for each family,
      `SceneTheme3d` writing both halves of the channel, `Theme3d.of` /
      `maybeOf`, and a `theme3d` extension for a `Layout3d` reading the slot
      inside `performLayout`. **80 headless tests**, `dart analyze` clean
      across the workspace, and the layout package's 891 still green. See
      *What phase 1 found* below — four things came out differently than this
      plan expected, and one of them is a gap phase 2 has to close first.
- [ ] **Phase 2 — `Material3d`, `InkWell3d`, `Icon3d`, `Text3d` styling.**
      The primitive and the interaction layer over it, plus the icon question
      settled. First render probe: a themed surface at three elevation levels
      is three distinguishable colours (the tint), and a hover lightens one.
      **Start with the two things phase 1 left on the doorstep**: the widget
      layer cannot read `Layout3dMetrics`, so a `Material3d` cannot convert a
      dp padding in `build` (a change to the layout package, with its own plan
      there); and application setup — the one call that installs
      `BoxDecoration3d.painterFactory` — was deliberately deferred to sit
      beside `Material3d` rather than beside the theme.
- [ ] **Phase 3 — the buttons.** `FilledButton3d`, `FilledTonalButton3d`,
      `OutlinedButton3d`, `TextButton3d`, `ElevatedButton3d`, `IconButton3d`,
      `FloatingActionButton3d`. One `_ButtonStyle3d` resolving token sets by
      state, the way Flutter's `ButtonStyle` does; disabled by substitution.
      This is the phase that proves the design, and it should be small.
- [ ] **Phase 4 — surfaces and rows.** `Card3d`, `ListTile3d`, `Divider3d`,
      `Chip3d`. `ListTile3d` is where `Semantics3d` and the 48dp target stop
      being theoretical.
- [ ] **Phase 5 — structure.** `Scaffold3d`, `AppBar3d`, `SliverAppBar3d` over
      `SliverPersistentHeader3d`, `NavigationBar3d`, `NavigationRail3d`.
- [ ] **Phase 6 — the overlays.** `Dialog3d` and `showDialog3d`, `Menu3d` and
      `PopupMenuButton3d`, `SnackBar3d` with a messenger, `Tooltip3d`,
      `BottomSheet3d` — all over `Overlay3d` and `Navigator3d`, all with the
      lift and thickness rules applied so a dialog does not z-fight the screen
      behind it.
- [ ] **Phase 7 — selection controls.** `Switch3d`, `Checkbox3d`, `Radio3d`,
      `Slider3d`. The first three are shape and state; `Slider3d` is the drag
      lane's first non-list customer, and `PointerSequence3d.addArenaMember` is
      the seam it wants.
- [ ] **Phase 8 — the ripple.** Two shader parameters, the press animation on
      the repaint-only tier, and a probe that watches the lit fraction grow.
      Deliberately last: everything before it works without it.
- [ ] **Phase 9 — the gallery.** `examples/layout3d_gallery` currently installs
      no painter and therefore draws no decoration at all. A catalogue is
      pointless unseen; give it a screen of real components on the upright
      panel and on the ground plane.

## What phase 1 found

Nine things, in rough order of how much they changed the shipped design. The
first two are work phase 2 has to do before it can write a component.

**`VisualDensity3d` was already on `Layout3dMetrics`, and this plan did not
notice.** *The design* asked `Theme3dData` to carry a density; the layout
package has carried one since the metrics landed, and applies it in
`Layout3dMetrics.effectiveConstraints`. Two dials for one number is exactly
the drift the "a component reads the theme, not `metrics`" rule exists to
prevent. The resolution is an explicit winner rather than a removal:
`Theme3dData.density` is what a component obeys, and
`Theme3dData.effectiveConstraints(constraints, metrics)` applies it through
the metrics' own arithmetic, so there is one implementation and a stated
precedence. `SceneTheme3d` deliberately does *not* write the surface's
metrics to close the gap — the metrics is the surface's unit contract, and a
widget inside the tree rewriting it is a theme reaching outside its
vocabulary.

**The widget layer cannot read the metrics at all, and a component needs to.**
`Layout3dMetrics` lives only on `Layout3dOwner`; nothing exposes it through a
`BuildContext`. So a widget's `build` cannot turn 16dp into world units — it
can only write units directly. Decoration figures are fine (the painter
converts radii, bevel, border and elevation at paint time), which is why the
README's worked example can write `theme.shape.medium` straight into a
`BoxDecoration3d` — but a *padding* or a *size* in a `build` method is in
world units, and there is no honest way around it today.
`Material3d(padding: EdgeInsets3d.all(theme.spacing))` cannot be written. The
fix belongs to `flutter_scene_layout3d` and gets its own plan there, the way
phase 0's four did; the shapes worth weighing are an inherited metrics widget
beside the surface, or a dp-stated padding box that converts inside
`performLayout`. **Phase 2 should settle it before `Material3d`, not after.**

**Interpolating a token can crash, and the layer below says which ones.**
`BorderRadius3d` asserts on a negative radius and `BoxDecoration3d` asserts on
a negative elevation, while an overshooting curve — `Curves.easeInBack`, a
spring — evaluates its tween outside `[0, 1]` by construction. So
`ShapeScale3d.lerp`, `Elevation3d.lerp` and `Thickness3d.lerp` clamp at zero;
without it, animating a rounded scale to a square one crashes on some curves
and not others, which is the worst kind of bug to be handed. `Color.lerp`
clamps its own components, so `ColorScheme3d.lerp` needs nothing.
`Typography3d.lerp` is the exception and is documented as one: nothing asserts
on a negative font size, so an overshoot produces one and it surfaces later,
as a measurement failure.

**`TextStyle.lerp` is a merge as well as an interpolation, so it is not the
identity at its own ends.** Where one end states a property and the other
leaves it null, the stated value is carried across rather than dropped — so
`Typography3d.lerp(a, b, 1.0)` is not `b` when `b`'s styles are bare
`TextStyle(fontSize: …)` values. That is Flutter's behaviour and usually what
you want; the test states it, and the dartdoc tells a caller to state complete
styles when it matters. A first draft of the test asserted the ends outright
and failed, which is how this was found.

**Material's `full` shape cannot be `double.infinity`.** `BorderRadius3d` has
no stadium rule, but `resolve` already scales radii down to what a box can
fit, so an absurdly large radius *is* a stadium on any box. Infinity is not:
`resolve` scales by `extent / sum`, which is zero against an infinite sum, and
`infinity * 0` is `NaN` — which trips `BorderRadius3d`'s own `>= 0` assert in
debug and, in release, reaches a shader uniform as a `NaN` and draws nothing
with no error anywhere. `ShapeScale3d.fullRadius` is 1000 logical pixels, and
a test states why.

**A `const` map cannot hold a `Layout3dSlot` key.** Phase 0 gave the slot
value equality for good reasons, and a `const` map key needs *primitive*
equality — so `SceneLayout3d(slots: const {Theme3dData.slot: …})` is a compile
error. Harmless once known, a puzzle for a minute if not; the README says so.

**The depth-step rule is derivable, not a rule of thumb.** *Every component
needs a thickness* said to keep the scale small relative to the step. The
actual condition falls out of the geometry: `Stack3d` writes
`sceneOffset = -index * step` and each slab is centred on its own plane, so
child *i+1* clears child *i* everywhere they overlap exactly when
`step > (thickness_i + thickness_{i+1}) / 2` — the **mean**, not the maximum
and not the sum. `Thickness3d.minimumStepFor` and `separates` are that
sentence, and the baseline's 12dp step clears the worst pair the scale can
produce (two 8dp slabs, mean 8) with half again to spare.

**The token tables are checked against Flutter's generated tables, not against
a second transcription.** *The tokens* worried about transcription errors, and
the strongest available answer turned out to be that Flutter generates its own
M3 colour and typography tables from the Material token database: the suite
compares `ColorScheme3d.light` and `.dark` role by role against
`ThemeData(brightness: …).colorScheme`, and the type scale's sizes, weights
and tracking against `Typography.englishLike2021`. That makes the tests a
drift alarm as well as a check. One deliberate divergence: Material publishes
a **line height in logical pixels** (57dp type on a 64dp line) while Flutter's
`TextStyle.height` is a multiple and its generated table rounds (`1.12` for
`64 / 57`). These styles carry the exact ratio, which is under half a percent
different and in the direction of the spec; both facts are pinned.

**The two judgment calls, and the reasons.**

- **`SceneTheme3d` offers to install the default text renderer and never
  assumes it.** `textRendererFactory` is null by default; passing one wraps
  the child in a `DefaultTextRenderer3d`, so an application says "here is my
  theme, and here is how labels are drawn" in one call. Defaulting it was
  tempting and is wrong: a renderer is not a token, it is a *resource* with an
  ownership contract — owned by the label, disposed with it, which is the
  whole reason `DefaultTextRenderer3d` carries a factory rather than an
  instance — and a theme that silently created resources would be reaching
  past what a theme is. Refusing to carry it at all was the other option, and
  it only buys a second wrapper in every application for one concept.
- **Application setup is deferred to phase 2, beside `Material3d`.** The one
  obvious call a catalogue needs is `await loadFmatMaterial(...)` followed by
  `BoxDecoration3d.painterFactory = ...`. It needs a GPU context, so no
  headless test can exercise it, and phase 1 has no consumer for it — shipping
  it here would mean an untested function whose only verification lane is the
  one this phase was explicitly not supposed to need. Phase 2's first render
  probe is exactly the thing that will verify it, so it lands there. The
  package's `lib/` therefore touches no engine API at all in phase 1, and
  `flutter_scene` is a dev-dependency (a widget test needs a `Node` for the
  surface to hang its plane under) rather than a dependency.

## Tests

The split is the one the whole repository uses, and the reason to restate it
here is that a catalogue is unusually tempting to check by eye.

**Headless, in `flutter test`** — everything that is arithmetic or state, which
is most of it. Token resolution per state (enabled, hovered, focused, pressed,
disabled) is a table and should be tested as one. Every interactive component
gets the animation plan's guard: a hover, a focus and a press mark **nothing**
dirty for layout. Every component with a tap target asserts it is at least
48dp. Every component with a semantic role asserts it announces one.

**On a GPU, in `examples/render_probe`** — the claims that are about a picture.
Three elevation levels are three colours. A disabled button is measurably
dimmer than an enabled one at the same place. An outlined button draws its
outline at the rim and its container in the middle (the check that caught the
panel shader drawing its border inside out). A dialog occludes the scrim
behind it rather than fighting it. A ripple grows.

The rule the harness earned: **the laid-out tree is the oracle** — ask
`screenCenter` or `screenPointOf` where a box is, never a hard-coded pixel —
and a scene that cannot honestly assert its claim is removed, not weakened.

## The seams to keep an eye on

- ~~**Phase 0 is in another package**~~, and it got the plan it needed:
  [the four things before a component](../../flutter_scene_layout3d/plans/2026_09_01_the_four_things_before_a_component.md),
  in the layout package, `completed`. Anything else this catalogue turns out
  to need from the protocol goes the same way — its own plan there, not a line
  item here.
- **`Decoration3dPainterCache` is what makes this affordable.** A screen of
  Material components is a hundred boxes and a handful of shapes, and the cache
  keys on `Decoration3d.cacheKey`. A component that builds a decoration with a
  freshly computed colour every frame defeats it silently — the frame rate
  falls and nothing says why. Tokens are `const` for this reason; keep them
  that way.
- **`TapTarget3d` grows the ray region and not the box**, so a padded target is
  invisible to layout, to `ensureVisible3d` and to semantics, which announces
  the smaller rectangle. This is the sharpest edge in the protocol and a
  catalogue meets it in every button.
- **Keep-alive does not exist** in the lazily built children lane, so a long
  list of stateful components rebuilds items that scroll back into view. Fine
  for a catalogue, and worth knowing before someone builds a form on it.

## Out of scope

- **Text input.** There is no `EditableText3d`, no text selection, no cursor
  and no keyboard plumbing anywhere in the stack, so `TextField3d` — and with
  it `SearchBar3d`, `DropdownMenu3d`'s editable form and `DatePicker3d`'s text
  entry — is not a component but a plan of its own, and a large one.
- **A seed-generated colour scheme.** M3's tonal-palette algorithm is a
  package's worth of work; hand-written light and dark baselines are enough to
  build every component against, and a generator can be added later without
  changing a single component.
- **Motion tokens.** M3's easing and duration sets are worth adopting, but only
  once enough components animate to know which ones are actually used.
- **Adaptive layouts.** M3's window size classes assume a rectangular window;
  what a size class means for a surface floating in a scene is a genuine design
  question and not one this plan should answer in passing.
