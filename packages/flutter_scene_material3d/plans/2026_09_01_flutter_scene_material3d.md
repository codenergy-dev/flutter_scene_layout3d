---
status: in progress
reason: phases 0 to 8 are done — the six token families, the theme channel, initializeMaterial3d, Material3d, InkWell3d, Icon3d, the text styling, the seven buttons, the surfaces and rows, the structure, the overlays, the selection controls, and now the press ripple, on 488 headless tests and 75 render probes. Phase 8 is the first thing in the catalogue that writes a shader uniform every frame, and it stays on the repaint-only tier: a whole ripple — press, twenty frames of expansion, release, forty frames of fade — costs no build and no layout, and a press *held* costs nothing at all once the circle has grown, because the run settles and the ticker stops. It needed two shader parameters and a change of frame from the layout package, under a plan of its own there. Phase 9 is open: the gallery
created_at: 2026-09-01T19:15:00Z
updated_at: 2026-09-09T23:10:00Z
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
- **The unit contract.** `Layout3dMetrics.dp()`, `.sp()`, `.dpSize()` and
  `.dpInsets()`, so a spec figure written in logical pixels is correct at any
  surface scale — read inside `performLayout` as `Layout3d.metrics` and inside
  a `build` method as `Layout3dMetricsScope.of(context)` — plus
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

*Shipped as written, and phase 3 built the buttons on it.*
`ColorScheme3d.disabledContent` and `.disabledContainer` are the two figures,
`ButtonStyle3d.resolve` is the rule (disabled wins every other state, the
elevation goes to zero, and the outline dims to the *container* figure rather
than the label one), and `examples/render_probe`'s `button_disabled` scene is
where it stops being arithmetic. One correction from that scene, in *What
phase 3 found*: on the light theme this harness requires, a disabled button is
**paler** rather than dimmer, and the claim worth asserting is that it has
lost its contrast against the surface behind it.

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

*Shipped in phase 8, as written.* `ripple_origin` and `ripple` are the two
parameters, `Ripple3d` on `StateLayer3d` is the value, and the four `ripple_*`
probe scenes are the same run of the same animation sampled at four moments —
so the claim is an order between counts of lit points rather than a threshold.
One thing the paragraph above did not anticipate: the ripple **carries** the
press rather than being drawn over it. See *What phase 8 found*.

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

*Shipped as written, with three corrections.* Two are in *What phase 1
found*: `Elevation3d` and `Thickness3d` are two classes rather than one
family, and the density was already on `Layout3dMetrics`. The third is in
*What phase 2 found*: a sixth family, `StateLayerOpacity3d`, fell out of the
first interactive component, because Material's 8/10/10/16 wash figures are
tokens like any others and the "strongest state wins, never the sum" rule has
to live somewhere. `Theme3dData` holds six plus the density.

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

*Shipped, with the signature filled out — `bevel`, `surfaceTint`,
`contentColor`, `textStyle`, `padding` and `alignment` beside the six above —
and with `Material3d.decorationFor` exposed as a static, because the render
probe builds surfaces imperatively and a probe that reimplemented the token
resolution would be checking its own arithmetic. The ink does not travel down
the tree as a property: see* What phase 2 found *for the controller, and for
what the 48dp target turns out not to do.*

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

*Verified in phase 2, on a GPU: it works.* `examples/render_probe`'s
`icon_glyph` scene rasterizes a `MaterialIcons` code point through the atlas,
puts the ink inside the box layout gave it and tints it, beside a control with
no renderer that draws nothing. So `Icon3d` is a one-character `SceneText3d`,
and the unlit wrinkle above is real and documented rather than hypothetical.

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
      plan expected, and one of them was a gap in the layout package, since
      closed by a plan of its own there.
- [x] **Phase 2 — `Material3d`, `InkWell3d`, `Icon3d`, `Text3d` styling.**
      Done. `initializeMaterial3d()` is the one call a Material application
      makes; `Material3d` is the primitive, with the theme resolved into it,
      a dp padding, a thickness and a bevel; `InkWell3d` drives its state
      layer through an `InkController3d` without rebuilding anything;
      `Icon3d` is one code point of an icon font through the label atlas,
      which a render probe settled rather than a guess; `Typography3dToken`,
      `Theme3dData.textStyle` and `SceneTextStyle3d` are the styling; and
      `StateLayerOpacity3d` is the sixth token family, which this plan did
      not know it needed. **106 headless tests** (was 80) and **48 render
      probes** (was 40), including the three this phase names: three
      elevation levels are three colours, a hover washes a panel, and an
      icon-font glyph rasterizes. `dart analyze` clean across the workspace,
      the layout package's 902 still green. See *What phase 2 found*.
- [x] **Phase 3 — the buttons.** Done, and small: one `Button3d` and seven
      `ButtonStyle3d` token sets. `FilledButton3d`, `FilledTonalButton3d`,
      `OutlinedButton3d`, `TextButton3d`, `ElevatedButton3d`, `IconButton3d`
      and `FloatingActionButton3d` are each three lines of delegation over a
      variant, and the resolver is **public** rather than the `_ButtonStyle3d`
      this plan named — see *What phase 3 found* for why that was wrong.
      Disabled is a substitution, tested as a table against Flutter's own
      `ButtonStyleButton.defaultStyleOf`, so the suite is a drift alarm rather
      than a second transcription. The 48dp target that phase 2 recorded as
      broken is **closed**, under
      [its own plan in the layout package](../../flutter_scene_layout3d/plans/2026_09_02_a_tap_target_that_delivers_a_press.md):
      a press in the margin now lands, and the rule that makes it work — a
      target sits outside every box the size of the control — is what
      `Button3d`'s tree is arranged around. **175 headless tests** (was 106)
      and **52 render probes** (was 48), including the two this phase names:
      a disabled button is measurably paler and has lost its contrast against
      the surface, and an outlined button draws its outline at the rim with a
      transparent container in the middle. `dart analyze` clean across the
      workspace; the layout package is at 906 (was 902).
- [x] **Phase 4 — surfaces and rows.** Done. `Card3d` over `CardStyle3d` and
      three variants; `ListTile3d` with its slots, its three heights and the
      density; `Divider3d`, which had to decide what a 1dp line *is* here; and
      `Chip3d` over `ChipStyle3d` and four variants with a selected state, a
      leading slot and a delete affordance. `ListTile3d` is where `Semantics3d`
      and the 48dp target stopped being theoretical, and the answers are in
      *What phase 4 found* — a tile takes its title as a string so it can
      announce it, and a **chip** rather than a tile is where the 48dp reach
      turns out to be load-bearing. **271 headless tests** (was 175) and **56
      render probes** (was 52), including the two this phase names: a raised
      card inside a clipping, scrolling list, and a 1dp rule that actually
      draws. That first probe **failed**, which is the phase's largest
      finding: the clip contract's plane tier had never fired at all, and
      closing it is
      [a plan of its own in the layout package](../../flutter_scene_layout3d/plans/2026_09_03_a_clip_that_reaches_the_shader.md).
      `dart analyze` clean across the workspace; the layout package is at 909
      (was 906).
- [x] **Phase 5 — structure.** Done. `Scaffold3d` is the screen — a
      `CustomMultiChildLayout3d`, as Flutter's `Scaffold` is one — and it owns
      the **depths**: each slot one `thickness.depthStep` in front of the one
      behind it, in the order `Scaffold3dSlot` declares, with an assert that
      the step really separates a bar from a card. `AppBar3d` and
      `SliverAppBar3d` are one `AppBarStyle3d` in four variants;
      `NavigationBar3d` and `NavigationRail3d` are one `NavigationStyle3d` in
      two, with M3's selection pill turning out to be a `Material3d` with a
      `full` shape and nothing new at all. `VerticalDivider3d` is the rule
      phase 4 deferred to the rail. **333 headless tests** (was 271) and **60
      render probes** (was 56), including the two this phase names: a row
      passing under a pinned bar is genuinely cut at the bar's edge, and a bar
      is drawn in front of the row sliding beneath it. The first of those
      **failed** — as phase 4's had, in a second place — and closing it, with
      the two widget forms the declarative layer was missing, is
      [a plan of its own in the layout package](../../flutter_scene_layout3d/plans/2026_09_08_the_declarative_side_of_a_pinned_bar.md).
      `dart analyze` clean across the workspace; the layout package is at 917
      (was 909). See *What phase 5 found*.
- [x] **Phase 6 — the overlays.** Done. `Dialog3d` and `showDialog3d` over
      `Navigator3d.push`; `Menu3d`, `MenuItem3d`, `PopupMenuButton3d` and
      `showMenu3d`, with the anchoring problem solved rather than deferred;
      `SnackBar3d` behind a `ScaffoldMessenger3d` that queues, times and
      completes a future per message; `Tooltip3d`, whose whole design question
      is what a waiting timer is allowed to touch (nothing); and
      `BottomSheet3d` in both the forms Material has, modal and persistent,
      on any of four edges. Five public token sets — `DialogStyle3d`,
      `MenuStyle3d`, `SnackBarStyle3d`, `TooltipStyle3d`,
      `BottomSheetStyle3d` — and one number they all share:
      `Scaffold3d.overlayLift`, one depth step in front of the frontmost slot
      a screen declares, so a dialog and a scaffold agree **by construction**
      rather than by two figures that happen to match. **396 headless tests**
      (was 333) and **64 render probes** (was 60), including the one this plan
      named: a dialog occludes the scrim behind it rather than fighting it.
      The phase needed two things from the layout package — a widget subtree
      as an overlay entry's content, and any anchoring at all — and both are
      [a plan of their own there](../../flutter_scene_layout3d/plans/2026_09_08_a_widget_under_an_overlay_entry.md).
      `dart analyze` clean across the workspace; the layout package is at 932
      (was 917). See *What phase 6 found*.
- [x] **Phase 7 — selection controls.** Done. `Checkbox3d`, `Radio3d`,
      `Switch3d` and `Slider3d` over four public token sets, and the drag
      lane's first customer outside a list took the seam that was built for
      it: `PointerSequence3d.addArenaMember` and `HitTestTarget3d` needed no
      change at all, which makes this the first phase since phase 3 to ask
      nothing of the layout package. The three claims a picture had to settle
      all passed — an 18dp checkmark rasterizes, a switch draws its thumb at
      the end it is set to and in front of its track, and a slider mid-drag
      fills its track to where the finger left the thumb. Two things came out
      of it that outlive the components: `Thickness3d.stepOver`, because the
      "stand proud of what it is drawn on" arithmetic had been written by hand
      three times and this phase needed it four more; and `NodeShift3d` /
      `SceneNodeShift3d`, the declarative form of the node tier, whose *scale*
      channel is what lets a track fill without a relayout. **470 headless
      tests** (was 396) and **70 render probes** (was 64). `dart analyze` clean
      across the workspace; the layout package is unchanged at 932. See *What
      phase 7 found*.
- [x] **Phase 8 — the ripple.** Done, and it was two shader parameters as the
      design said it would be. `Ripple3d` rides on `StateLayer3d` in the layout
      package, `InkRipple3dRun` is the timeline with no ticker in it,
      `MutableInkController3d` drives one from a `Ticker` the `Material3d`
      provides, and `InkWell3d`'s only part is to say *where* — the pointer
      down's position, moved into the panel's frame by the layout package's new
      `Layout3d.localPointFrom`. The tier held: a whole ripple costs no build
      and no layout, and a held press stops asking for frames entirely. The
      probe passed — the lit fraction of a panel grows from nothing to all of
      it across four moments of one run, and the early circle is dark where the
      press landed and not at the far end. **488 headless tests** (was 470) and
      **75 render probes** (was 70). `dart analyze` clean across the workspace;
      the layout package is at 944 (was 932), under
      [where a press landed](../../flutter_scene_layout3d/plans/2026_09_09_where_a_press_landed.md).
      See *What phase 8 found*.
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

**The widget layer could not read the metrics at all, and a component needs
to — settled, in the layout package.** `Layout3dMetrics` lived only on
`Layout3dOwner`, so a widget's `build` could not turn 16dp into world units;
decoration figures were fine (the painter converts radii, bevel, border and
elevation at paint time), which is why the README's worked example can write
`theme.shape.medium` straight into a `BoxDecoration3d`, but a *padding* or a
*size* in a `build` method was in world units and there was no honest way
around it. That is now
[a plan of its own in `flutter_scene_layout3d`](../../flutter_scene_layout3d/plans/2026_09_02_the_metrics_a_build_method_can_read.md),
shipped: `SceneLayout3d` publishes a `Layout3dMetricsScope`, so
`Layout3dMetricsScope.of(context)` hands a build method the surface's contract
and `metrics.dpInsets(const EdgeInsets3d.all(16))` is the padding this
paragraph said could not be written. Two things a component author should take
from it. The inherited-widget shape won over dp-stated values because the
staleness argument against it does not hold here — a binding is applied in the
transient or post-frame phase, never during build or layout, so a dependent
rebuilds *before* the layout that consumes what it computed — and because one
scope makes every existing box dp-capable while dp-stated values would need a
dp twin of each. And it does not make a metrics change cheaper: writing the
contract still relayouts the whole subtree, because most boxes were never
rebuilt and read the number inside `performLayout`.

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

## What phase 2 found

Seven things. The first two changed shipped behaviour outside this package's
own code, and the third is a protocol gap a component author will hit.

**One material per panel, and the layout package's README one-liner cannot
give a catalogue one.** `BoxDecoration3dPainter` writes each box's parameters
into the material it was handed, so the documented
`createMaterial: () => material` gives a *screen* of panels one parameter
block and the last box painted wins it. A catalogue is exactly the case that
breaks: a screen, a card on it, a filled button on that, three colours, three
elevations, one picture. The painter's callback shape is right — it is called
once per box — but it is **synchronous** and `loadFmatMaterial` is not, so
there was no way to use it. The seam that closes the gap is
`loadFmatMaterial`'s own `factory` parameter, which hands the caller the
compiled fragment shader, the sidecar metadata and the vertex variants: one
asynchronous load captures those in a closure and any number of further
instances are built synchronously afterwards. `loadPanelMaterialFactory` is
that, and it is public, because anything writing its own `Decoration3dPainter`
needs it too.

Two details of it are worth keeping. The load's own instance is handed out
first, so nothing is wasted. And the radiance-cube variant the registry
attaches *after* construction — `box_decoration3d.fmat` is `shading_model:
lit`, so it has one — is threaded onto every later instance through the
constructor, because the setter that attaches it is `@internal`; without it an
instance falls back to the ordinary shader, which the engine's own comment
says can sample whatever texture the unit still held. The `material_elevation`
probe is what would catch all of this going wrong, and it says so in its
failure message.

**The application setup call is honest about the half it cannot do.**
`initializeMaterial3d()` awaits `Scene.initializeStaticResources()` and
installs the painter. It deliberately does *not* install the default text
renderer, and the reason is stronger than phase 1's: it is not that a theme
should not create resources, it is that **there is no global renderer to
install at all**. A `Text3dRenderer` is owned by one label and disposed with
it, so it reaches labels through the tree, one instance each. The second half
of setup is therefore a widget —
`SceneTheme3d(textRendererFactory: AtlasText3dRenderer.new)` — and both halves
are documented together, one line apart.

**`TapTarget3d`'s 48dp minimum does not deliver a press today, and
`InkWell3d` cannot fix it from here.** *The seams to keep an eye on* said the
target grows the ray region and not the box, which is true and is only half of
it. Out in the margin the only entry in the hit path is the target itself,
because `TapTarget3d` passes its children the *unmoved* ray by design; and a
target dispatches no gestures. A `GestureDetector3d` outside it fares worse,
since every box gates its children on its own extent and the ray is rejected a
level above the target. An ink well inside its own `Material3d` is gated by
the panel as well. So the minimum currently buys a ray that *finds* something
— which is what the nearest-acceptor rule for drops needs — and not a press
that lands. `test/ink_well_test.dart` states it in those terms, so that
closing it in the layout package (under a plan of its own there, as this plan
requires) is noticed rather than silent.

**The wash had to become a token family.** *The tokens* named four families
and phase 1 shipped five; a sixth, `StateLayerOpacity3d`, fell straight out of
the first interactive component. Material's 8/10/10/16 figures are tokens like
any others, every interactive component resolves them identically, and a
component in two states at once takes the **strongest** wash rather than their
sum — which is a rule that has to live somewhere. `Material3dState` is the
enum beside it, deliberately without `selected` or `disabled`: both are token
substitutions here, not washes.

**The ink channel is a controller, not a widget property, and the tier is
why.** `DecoratedBox3d.stateLayer` cannot be a `SceneDecoratedBox3d` property
on a `Material3d`, because reaching it would then mean rebuilding the
component on every hover. So `Material3d` publishes a `MutableInkController3d`
through an inherited widget whose value never changes, `InkWell3d` looks it up
once in `didChangeDependencies`, and every state change afterwards is a field
assignment on a box. The rebuild path re-applies whatever the controller holds
rather than clobbering it with a stale value, which is the one subtlety in the
implementation. The tests assert it by counting builds and layouts across a
hover, a focus and a press.

Two behaviours that surprised the tests before they surprised a user. A press
does not report itself until Flutter's tap recognizer wins the arena or its
`kPressTimeout` deadline expires — correct, since a press that becomes a
scroll should never flash a highlight, but it means a test that presses and
releases in the same instant sees nothing. And a press **focuses** the
control, so the focus wash outlives it; Flutter hides that behind
`FocusManager.highlightMode`, nothing here reads that yet, and `InkWell3d`
gained a `focusOnPointerDown` for the cases where it is wrong.

**The icon guess was right, and it took a frame to know.** *Icons are a font,
until proven otherwise* was the phase's one genuine unknown, and the answer is
yes: `AtlasText3dRenderer` rasterizes a `MaterialIcons` code point, puts the
ink inside the box layout gave it, and tints it, with the same-glyph-no-
renderer control drawing nothing. So `Icon3d` is a one-character
`SceneText3d`, an icon costs one quad, and a screen of icons and labels is one
texture. Two riders: it is drawn **unlit** like every label, so contrast has
to be chosen against the unlit glyph and the lit panel; and
`IconData.matchTextDirection` is not honoured, because a mirrored glyph needs
a negative scale on the quad and the atlas renderer does not express one.

**A dark theme is invisible to the render harness, which is why the probes are
light.** *The tests* asked for "three elevation levels are three
distinguishable colours" and the first attempt used `Theme3dData.dark`,
because a light tint on a dark surface is the textbook picture. It drew
nothing at all: `FrameProbe` decides what is geometry by distance from the
clear colour, the probe clears to `#101820`, and M3's dark surface is
`#141218` — inside the tolerance. The scenes use the light theme, so the
direction the probe asserts is *higher is darker* (a purple primary tinting a
near-white surface) and a hover reads as darker too. Same claim, opposite
sign, and both scenes say so in a comment. The other thing that first attempt
got wrong is more ordinary and just as invisible: a `Row3d` hands its children
loose cross-axis constraints, so a flexed `DecoratedBox3d` with no child
shrink-wraps to 1.12 × 0 × 0 and the frame is empty. Explicitly sized cells.

**A `Material3d` centred its child in depth, once.** `Alignment3d.center` is
centred on all three axes and `EdgeInsets3d.all` insets six faces, so the
obvious defaults put a label *inside* the slab it is drawn on, where the panel
wins the depth test and hides it with nothing to say why. `Material3d` aligns
to `Alignment3d.frontCenter` and the dartdoc tells a caller to state the two
in-plane axes of a padding. It is in `docs/traps.md` now.

## What phase 3 found

Twelve things. The first three changed the shipped design; the rest are the
kind that cost an hour each and are invisible from the code.

**`_ButtonStyle3d` should not have been private, and the plan's own reasoning
elsewhere says so.** *The work* named a private resolver; three arguments
against it, and none of them is a matter of taste. Flutter's `ButtonStyle` is
public because a catalogue whose buttons cannot be restyled is a
demonstration. `examples/render_probe` builds its scenes **imperatively** and
its two new button probes resolve real tokens — a probe that reimplemented the
table would be checking its own arithmetic, which is the exact argument that
made `Material3d.decorationFor` a static one phase earlier. And an eighth
variant is then someone else's `ButtonStyle3d` rather than a fork of this
package. So `ButtonStyle3d`, `ButtonVariant3d` and `ResolvedButtonStyle3d` are
public, and `Button3d` — the widget all seven delegate to — is public with
them.

**And it needs no `WidgetStateProperty`.** Flutter has one because in
principle any property may vary with any state. In Material 3's actual button
tables only four do — the container colour, the content colour, the elevation
and the outline — and each varies in exactly one way. Naming those four
(`disabledContainer`, `disabledContent`, `hoveredElevation`, `focusedOutline`)
makes `resolve(states, enabled:)` the whole table in one readable method, with
no allocation and no closure, and makes the *table* testable as a table.

**Buttons turn the surface tint off, and *Elevation is a height* was wrong to
say "keep the tint" without qualification.** Flutter's M3 buttons all resolve
`surfaceTintColor` to transparent, and the reason is arithmetic rather than
laziness: an elevated button's container token is `surfaceContainerLow`, which
**is** the level-1 tint already baked into a colour. Applying the tint again
double-counts it. The plan's advice holds for a *surface* whose colour is
`surface` and whose elevation is the only signal; it does not hold for a
component whose container token already encodes the elevation. `Button3d`
passes a transparent `surfaceTint`, and `test/button_defaults_test.dart` reads
Flutter's own figure rather than asserting ours.

**The 48dp target was two problems and the small one was the box.** The fix
inside `TapTarget3d` is nine lines: when the ordinary hit test misses and the
ray is in the margin, re-test the children with the ray aimed at the centre of
the control, which is exactly what Flutter's `_RenderInputPadding` does with
`MatrixUtils.forceToPoint`. The half that actually cost the time is
**placement**. A target reaches past its own extent and every *ancestor* gates
a ray on its own extent, so a target inside anything the size of the control
never sees the ray at all — and that is not only the panel. It is the
semantics box too: the first working `Button3d` had `SceneSemantics3d`
outermost, Flutter's own order, and a press 2dp above the button was rejected
by the semantics box. Flutter can afford that order because `_InputPadding`
grows the *layout* box; `TapTarget3d` deliberately does not. So the target is
outermost here, and `docs/traps.md` states the rule rather than the instance.

**`Semantics3d` gathers no label, and a component has to state its own.**
Flutter's `Semantics(container: true)` merges the labels of the widgets below
it, which is why a Flutter button wrapped around a `Text('Save')` announces
"Save" with nobody saying so. There is no such merge here — a
`SemanticsComponent` hangs off one scene node and there is no semantics tree
under it to fold up — so every button takes a `semanticLabel` and a button
without one announces itself as a button with no name. Written up in
`docs/traps.md` under a new *Semantics* section, because every component from
phase 4 on will meet it.

**Flutter's button defaults are reachable from a test, and that makes the
suite a drift alarm rather than a second copy.** `_FilledButtonDefaultsM3` and
its siblings are private, but `ButtonStyleButton.defaultStyleOf(context)` is
not: pump a real Flutter button and read the container colour, the padding,
the minimum size, the shape, the type and the per-state elevation off the
framework. Material 3's icon button is a `ButtonStyleButton` too, so it goes
the same way. Two riders. `defaultStyleOf` is `@protected`, so calling it from
outside a subclass needs one `// ignore:` — a small price, and it lives in
`test/` rather than in `lib/`. And `FloatingActionButton` is genuinely not a
`ButtonStyleButton`: its defaults have no public accessor at all, so that test
reads the `Material` widget a real FAB *renders* — its colour, elevation and
shape — plus the size it lays out at, and says in its own comment that it is
the weaker check.

**Comparing a `Color` across the framework boundary compares a float with a
byte.** Flutter's disabled figures come from the deprecated
`Color.withOpacity`, which rounds to an alpha byte:
`onSurface.withOpacity(0.38)` has alpha `97 / 255 = 0.380392…`.
`ColorScheme3d` uses `withValues`, which keeps `0.38` exactly. The two are not
`==` and are the same colour in every place it matters — the shader uniform,
the frame buffer, the probe. The first run of the drift test failed on
precisely this, and the comparison that means something is `toARGB32()`.

**A state costs a rebuild only when a token moved, and the way to know is to
compare the resolved style.** `InkWell3d`'s dartdoc already said a component
whose tokens change with a state "rebuilds, deliberately, and pays for it" —
but a button that called `setState` on *every* state change would pay for a
text button's hover too, where nothing moves. `_Button3dState` resolves the
style and compares it, so a text button's hover rebuilds nothing at all and a
filled button's rebuilds and still lays nothing out. Making that possible
needed one addition to `InkWell3d`: `onHighlightChanged`, Flutter's own
spelling, because Material's elevation rule is "hovered **and not pressed**"
and nothing was reporting the press upward.

**A gesture can arrive after the button has left the tree.** A pointer
sequence holds the path it captured at the press, so a tap cancelled by the
widget being replaced is delivered to boxes whose widgets are already defunct
— and the first run of the button tests died on `setState() called after
dispose()`. `InkWell3d` never met this because its teardown only touches a
controller. `_Button3dState._note` checks `mounted` first.

**An aligning container fills every bounded axis, so the first button was four
units wide.** `Container3d` with an alignment behaves like Flutter's
`Container`: it fills what it is given and shrink-wraps only an unbounded
axis. A `SceneCenter3d` hands down loose but *bounded* constraints, so a
button inside one came out the width of the surface. Flutter's own button
solves it with `Align(widthFactor: 1.0, heightFactor: 1.0)` inside the
padding, and so does this one — `Material3d(alignment: null)` with a
`SceneAlign3d` under the ink well — with the minimum size on a
`SceneConstrainedBox3d` outside the panel, which is where Flutter's
`ConstrainedBox` sits too.

**A 1dp outline cannot be probed at the default unit rate, and fattening the
token would have been the wrong fix.** At a hundred logical pixels to the unit
a Material outline is 0.01 units and a couple of pixels on screen; no probe
disc fits inside it. The scene turns the *surface's* `unitsPerLogicalPixel` up
to 0.06 instead, so the token stays at its published 1dp and the unit contract
is the dial — which is the dial a camera-bound surface turns anyway. It needs
a camera further back to match.

**"A disabled button is dimmer" is false on the light theme, and the claim
that carries the meaning is different.** On the theme this harness requires,
an enabled filled button is a mid purple and a disabled one is a pale grey, so
the direction is *paler* — the same sign inversion the elevation and hover
probes already document. The assertion worth making is the other one: the
disabled container is **closer to the surface behind it** than the enabled one
is, which is what losing contrast means, and which is two distances measured
the same way rather than a bare difference. The scene also needs that surface
to exist: M3's disabled container is `onSurface` at 12% alpha, a figure meant
to composite over something, and floating in front of the harness's `#101820`
clear colour it lands inside the clear tolerance and reads as nothing.

**A test that builds a fresh `Layout3dPointer` per access presses one pointer
and releases another.** The sequence between `down` and `up` is what holds the
captured path and the arena entry, so a `Layout3dPointer get pointer =>
Layout3dPointer(surface)` getter makes every tap count zero, silently and
without an error. It cost twenty minutes of suspecting the hit-test fix.

## What phase 4 found

Ten things. The first is the largest finding any phase has produced, and it is
not about this package at all.

**The clip contract's plane tier had never fired, and only a picture could
have said so.** This plan sent phase 4 to check that `Clip3dRegion.rect`'s
deliberate decision about depth held — "a raised card inside a scrolling list
should still stand proud of it" — and to make a picture of it, because nobody
had. The picture came back with the card the *same colour* above and below the
window's edge: nothing was being cut at all. Two causes, and both are
invisible from the code. A `DecoratedBox3d` publishes its clip block from
inside its own `performLayout`, and a `ClipBox3d` is a proxy that takes its
size **from its child** — so while the subtree lays out, the box imposing the
clip has no extent and imposes nothing, and every panel under a clip was born
with the unbounded block. And a scroll *places* its rows rather than relaying
them out, so nothing ever replaced it. `Layout3d.clipRegion` kept answering
correctly to anything that asked after layout, which is why nine hundred
headless tests never noticed. Closed in the layout package under
[a clip that reaches the shader](../../flutter_scene_layout3d/plans/2026_09_03_a_clip_that_reaches_the_shader.md),
and `docs/traps.md` — which claimed the tier was live — is corrected.

**The clip contract itself is right, and the scene now shows it.** With the
tier working, `card_in_clipped_list` draws an elevated card cut at the
window's edges in the plane and untouched in depth, standing in front of the
backing it sits on. The other half of the decision is worth writing down
because it is not obvious: **`clipDepth: true` would not have sliced the card
either.** The planes are expressed in the box's own frame, and an elevation
moves the slab's *node*, outside that frame — so a depth clip cuts a box's
layout depth and never its lift. Two ways of saying the same thing, and the
`rect`/`box` distinction is about the *box*, not about the geometry.

**A divider is a slab, not a decal, and the depth buffer is why.** The
tempting model for a 1dp rule is zero depth. It cannot be: `Material3d` aligns
its child to its **front face**, so a divider drawn on a card is exactly
coplanar with the card and z-fights it — the rule appears in patches,
differently on every frame and every driver. `Divider3d` is a
`Thickness3d.thin` slab, which is what that token's own documentation always
said it was for, and it stands its own half-thickness proud of what it is
drawn on. The cost is the ordinary one, and at 1dp against anything else on
the scale `Thickness3d.separates` clears it several times over.

**A divider has three figures called some version of "thickness", and they are
three different things.** The space it occupies in a column (16dp), the height
of the rule inside that space (1dp), and the depth of the slab (1dp, and a
different dial that happens to carry the same number). `Divider3d` keeps
Flutter's spelling for the in-plane figure — a caller migrating a `Divider`
writes what they already know — and names the depth `depth`. That collides
with `Material3d.thickness`, which is a depth, and the collision is
unavoidable: both spellings are right in their own frame.

**The 48dp target is load-bearing on a chip, not on a tile.** Phase 3 built
the reach for buttons and this plan expected `ListTile3d` to be where it
mattered. It is not: a tile is 56dp tall and never needs it. A **chip** is
32dp, sixteen short of Material's minimum, so the reach is eight logical
pixels of margin on each side that no box in the layout knows about — and
`test/chip_test.dart` presses 6dp above a chip and lands, then 14dp above and
does not.

**A tile is the first component that cannot state one label, so it takes
strings.** Phase 3 established that a `Semantics3d` gathers nothing and a
component states its own label. That is a formality for a button and a real
question for a row with a title *and* a subtitle: there is no single answer
that does not throw one of them away. `ListTile3d.text(title:, subtitle:)`
builds the labels **and** the announcement — `'Inbox, 12 unread'`, which is
what Flutter's merge would have produced — and the widget-taking constructor
is documented as announcing only what it is told. Doing by hand what a merge
does for free is the only place that work can go.

**And a divider announces nothing, deliberately.** Flutter's own publishes no
semantics either. A reader that said "divider" between every pair of rows
would be worse than one that skipped it. The decision is in the dartdoc and in
a test, because otherwise the next reader takes it for an omission.

**A card is the first component with no state-dependent token at all, and that
is a property worth having.** Material 3 gives a card no disabled appearance,
no hovered container and no focused outline — an interactive card is *washed*
and is otherwise unchanged. So a card's whole interaction is one uniform write
on the repaint-only tier and it never rebuilds, where a filled button has to
for its hovered elevation. The same turned out to be true of the baseline chip
table. Two of the four components in this phase cost nothing at all for a
hover.

**The surface tint is off on a card too, and Flutter is where the figure comes
from.** Phase 3 corrected *Elevation is a height*'s "keep the tint" for
buttons, on the argument that an elevated button's container token already
encodes the elevation. The same argument applies to an elevated card —
`surfaceContainerLow` **is** the level-1 tint baked into a colour — and
Flutter's `_CardDefaultsM3` and both its siblings resolve `surfaceTintColor`
to transparent, so `test/card_defaults_test.dart` reads that rather than
asserting ours. The plan's advice now holds only for a surface whose colour is
literally `surface` and whose elevation is the only signal.

**Flutter's list-tile heights are reachable, and its card defaults are not.**
The drift-alarm standard phase 3 set has three grades, and phase 4 hit all
three. `Divider.createBorderSide(context)` is **public**: the rule's colour
and width are read straight from Flutter. `ListTile`'s heights are private as
data and public as a *fact about a laid-out widget*, so the test pumps a real
one and reads `tester.getSize` — 56, 72, 88, and 48, 64, 76 dense, all of them
Flutter's arithmetic rather than a transcription. `Card`'s defaults have no
accessor at all, so that test reads the `Material` a real `Card` renders,
which is the weaker lane the floating action button already used. Two figures
are honest transcriptions and say so in their tests: a divider's 16dp of space
and a chip's 32dp height.

**Two smaller things a catalogue author will meet.** There is no
`SceneClipBox3d` — `ClipBox3d` is imperative-only, and a widget test that
wants a clipped subtree writes a four-line `SingleChildLayout3dWidget`
adapter, which `test/card_test.dart` does and phase 5's `Scaffold3d` will
want properly. And a `SceneListView3d.builder` **cannot be flushed from
outside a layout pass**: its children are created inside
`invokeLayoutCallback`, which asserts it is inside Flutter's own layout phase,
so `surface.flush()` from a test body dies with `_debugDoingLayout is not
true`. Drive it with `controller.jumpTo` and `await tester.pump()` instead.

## What phase 5 found

Ten things. The first is the same finding phase 4 made, in a second place,
found by pointing the same instrument at it — which is the part worth
remembering.

**A pinned header's clip had never reached a shader either.** This plan sent
phase 5 to "prove with a render probe that a row passing under the bar is cut
at the bar's edge", on the strength of two plans saying it was. It was not.
`CustomScrollView3d` clears its obstruction map at the top of every layout
pass and fills it in as each sliver is *placed* — which happens after the rows
inside that sliver have already been laid out, placed, and published their
clip blocks. Every row under the bar was told, correctly for that instant and
uselessly, that nothing covered it. `Layout3d.clipRegion` answered correctly
from the moment the pass ended, so
`test/persistent_header_test.dart`'s assertions about the band had passed
since the header landed and no frame had ever been cut. Closed in the layout
package under
[the declarative side of a pinned bar](../../flutter_scene_layout3d/plans/2026_09_08_the_declarative_side_of_a_pinned_bar.md),
along with the two widget forms phase 4 recorded as missing.

**And a full-width opaque bar makes that defect invisible, which is why it
lasted.** The bar covers exactly what the clip would cut. The clip is one
plane across the scroll axis, cross-axis-wide, so it only *shows* where the
bar does not cover — beside a narrow bar, through a translucent one. The
`sliver_app_bar_clip` probe is built around a half-width bar for that reason,
and a scene with a full-width bar would have photographed a working picture
over a dead tier.

**The layout package's default lift is wrong for Material, and the arithmetic
says by how much.** `SliverPersistentHeader3d.lift` defaults to one logical
pixel, which the class doc describes as "enough to separate them in the depth
buffer" — true for two things with no thickness, and false for two slabs. A
`Thickness3d.structural` bar (8dp) over a `Thickness3d.raised` card (4dp)
needs a step above the *mean*, 6dp, so the default is six times too small.
`SliverAppBar3d` therefore passes `thickness.depthStep` rather than
forwarding a null, and `test/app_bar_test.dart` asserts both directions —
that 12dp separates and that 1dp does not.

**The depth question has two answers, not one, because a sliver bar is not in
the scaffold.** This plan asked what a `Scaffold3d` "has to guarantee about
the depths of its slots". It turned out to be half the question. A
`SliverAppBar3d` is a sliver in the *body's* scroll view, so the scaffold
never sees it and its separation comes from the header's lift instead. The two
answers are the same number from the same scale — `thickness.depthStep` — and
saying so in both classes is what keeps them from drifting.

**`Scaffold3d` states the depths as positions, not as scene offsets.**
`Stack3d.depthStep` writes `ParentData3d.sceneOffset`, which layout and hit
testing never see; a `CustomMultiChildLayout3d` delegate positions children
with a full `Offset3d`, z included. The second is the honest one here: a bar
in front of the body really is in front of it, and a ray agrees. That also
made the guarantee testable as arithmetic — `Scaffold3d.liftFor` — rather than
as a property of one build method.

**A scaffold should not bind a surface, and the reason is the whole project.**
`Layout3dCameraBinding.screenFilling` is what makes a surface cover the view,
and a `Scaffold3d` that applied one could only ever *be* the view. Half the
reason this stack exists is that a Material screen here can be a panel on a
wall. So the scaffold is a box like any other and the binding stays where the
application mounts the surface — which also leaves phase 6 free, since an
overlay belongs to the *surface* rather than to the screen.

**The body has to be clipped, and that is what `SceneClipBox3d` was for.**
Phase 4 recorded the missing widget form as a convenience for a test. It is
not: a list in a scaffold's body is taller than the room it was given, and
without a window its rows draw over the bars. The window clips the face and
not the depth, so a raised card in the body still stands proud — which is the
decision `Clip3dRegion.rect` made and phase 4 photographed.

**Material's selection pill needed no new machinery at all.** A stadium is a
rounded rectangle whose radius clears half its shorter side, which
`ShapeScale3d.full` already is, so the indicator is one more `Material3d` —
64 by 32 in a bar, 56 by 32 in a rail. What it *did* need is a depth step: a
glyph drawn exactly on the pill's front face is coplanar with it and z-fights,
the same argument `Divider3d` made about a rule on a card. That step is a
token (`NavigationStyle3d.indicatorDepthStep`) rather than a constant, because
the pill's own depth is one.

**Every destination is its own surface, and a navigation bar is where that
stops being a footnote.** The trap `docs/traps.md` records for a chip's delete
icon — an `InkWell3d` finds the *enclosing* `Material3d` — would light a whole
bar up under one finger. A chip could live with a plain gesture detector; a
bar cannot, because the wash is the feedback. It can afford the second surface
that a chip could not: a bar is 8dp deep, so a `Thickness3d.thin` slab per
destination stands proud of it rather than fighting it.

**Flutter has two answers for a toolbar's height and they disagree.** The
drift-alarm standard has needed three grades so far; this is a fourth case.
`_AppBarDefaultsM3.toolbarHeight` is 64 and `AppBar.medium` and `.large`
collapse to 64, but `AppBar`'s own build resolves
`widget.toolbarHeight ?? appBarTheme.toolbarHeight ?? kToolbarHeight` and
never reaches its defaults object — so a real M3 `AppBar` lays out at 56. This
package takes 64, the M3 token, and `test/app_bar_defaults_test.dart` pins
**both** numbers with the reason, so a reader meets the discrepancy in the
test rather than against a ruler.

**And two smaller things a catalogue author will meet.** A flex reporting
*"overflowed the right by 0.000"* is a rounding artefact, not an overflow: an
`Expanded3d` child's extent is computed by subtraction and the sum comes back
a few ulps over. A Material app bar with a spacing and an expanded title is
exactly that layout, and `Layout3dOverflowReportingMixin.overflowTolerance` is
the fix Flutter has had all along. And a `const` constructor's asserts run at
compile time, where `List.length` is not a constant expression — so a
component refusing a one-element list either gives up `const` or moves the
check to `build`. `NavigationBar3d.tooFewDestinations` is the second.

## What phase 6 found

Ten things. The first two are gaps in the layout package that this phase could
not have been written around, and both got a plan of their own there.

**An overlay entry's content is a `Layout3d`, and a catalogue is widgets.**
The overlays plan wrote this down as the one thing
`flutter_scene_material3d` would probably want first, and it was right on both
counts. Nothing in the declarative layer could bridge it from outside the
package either: the mirroring that turns a render child list into a layout
child list lives on `Layout3dRenderBox`, which is not exported and should not
be. `WidgetOverlay3dEntry` and `WidgetPageRoute3d` close it, under
[a widget under an overlay entry](../../flutter_scene_layout3d/plans/2026_09_08_a_widget_under_an_overlay_entry.md),
and there is still no second reconciliation path — a host inside
`SceneOverlay3d` hands what the *first* path reconciled to the entry's slot,
which is twenty lines. The consequence a component author meets is the
**one-frame rule**: an entry is in the stack at once and its widgets arrive on
the next frame, exactly as Flutter's own `Overlay` behaves. A test pumps once.

**Nothing anchored anything, and a menu is the first component that needs to.**
`Overlay3dEntry` takes an alignment — where the entry sits *in the overlay* —
and there is no `CompositedTransformTarget` here. The arithmetic already
existed, privately, inside `Draggable3d._homeOver`: take the anchor's point
into the world through `worldTransform` and back out again in the follower's
own frame. It is public now as `Layout3d.anchorOffsetTo`, with two alignments
so a menu's top-left can sit on its button's bottom-left, and this package's
`Anchor3d` and `Follower3d` are what drive it. **It answers a `nodeOffset`**,
so anchoring is the node tier: one matrix, no relayout, and a menu may
re-anchor every frame without costing a thing.

**A menu follows its button, and it took three hooks to do it honestly.** The
plan asked for either following or closing, and not for leaving it undefined.
Following turned out to need more than one hook, because the ways a button can
move are not one kind of event. The follower re-anchors when *it* is placed,
which covers a resize and anything that relays the overlay out; when the
*anchor* is placed, which covers a row moving inside a list; and from a
post-frame callback while a menu is open, which is the backstop for the case
neither catches — an **ancestor** of the button moving, where `place` is called
on the ancestor and never on the boxes below it. That last one is a scroll, and
it is the case the first two hooks were written for and missed. A post-frame
callback schedules no frame of its own, so a menu over a screen where nothing
moves costs nothing at all. And the menu closes when its button leaves the
tree, because an anchor that no longer exists cannot be followed.

**`Overlay3dEntry.modal` cannot be used for a Material scrim, and the reason is
one line of `Stack3d`.** The entry builds its barrier and its content into a
stack with **no depth step**, so the two sit on the same plane. That is fine
for Flutter's barrier, which is a colour in a display list, and wrong here,
where a scrim is a slab: the two z-fight wherever the scrim shows. So every
modal in this package passes `modal: false` and builds its own frame —
`SceneModalBarrier3d` with the scrim as its child, the content one
`thickness.depthStep` in front, in one `SceneStack3d`. It costs six lines and
it is the only way to state the step.

**"A translucent scrim is not expressible" was false, and had been since the
shader landed.** `ModalBarrier3d`'s own dartdoc and the overlays plan both said
a translucent scrim had to wait for the opacity contract. `box_decoration3d
.fmat` declares `blending: alpha`, so a `BoxDecoration3d.color` carrying
Material's black-at-32% blends over what is behind it — the
`dialog_over_scrim` probe is the picture, and it is the fourth phase in five to
find a page describing behaviour the code does not have. What *does* still wait
on the opacity contract is **subtree** opacity, fading an arbitrary child, and
that was never what a scrim needed. Both pages are corrected.

**The overlay's depth is `Scaffold3d`'s arithmetic, extended by one step.** The
plan asked for a dialog that clears "all of" a screen rather than only its
body, and for the two to agree by construction. `Scaffold3d.overlayLift(step)`
is `liftFor(Scaffold3dSlot.values.last, step) + step` — one step in front of
the frontmost slot, whatever that slot turns out to be — so adding a value to
`Scaffold3dSlot` moves the overlays with it and nothing has to be kept in sync
by hand. It comes out at 60dp against `Overlay3d.defaultLift`'s 8, which is the
size of the mistake a component picking the default would have made.

**A snack bar's queue is one `Timer` and no animation at all, and saying so is
the honest version.** `Route3dTransition.none` is what the layout package
ships, this package has no motion tokens yet, and a messenger that pretended
otherwise would be a lie in the API. What the queue does have is the shape
Flutter's `ScaffoldMessenger` has: one bar at a time, a duration per bar, a
future per bar carrying **why** it went away, and a bar closed before its turn
dropped rather than shown. Four seconds of waiting rebuild nothing and lay out
nothing, and a test asserts exactly that.

**A tooltip's design question is what a *waiting* timer may touch, and the
answer is nothing.** A pointer entering starts a `Timer`; a pointer leaving
cancels it. Neither calls `setState`, marks anything dirty, or rebuilds the
control under the pointer — only the timer *firing* does anything, and what it
does is insert an entry. The test counts the builds and the layouts of the
child across four hundred milliseconds of hover that never matures, and both
are unmoved. One thing did have to differ from `InkWell3d`: its hover listener
is `deferToChild`, because a control is hovered exactly where it is pressable,
while a tooltip wraps things that answer no ray of their own — a bare label, an
icon. A tooltip's listener is **opaque**, and its own extent is the hover
region.

**Every item inside an overlay needs a slab of its own, and it needs to stand
*clear* rather than rest on the surface.** The trap `docs/traps.md` records for
a chip's delete icon — an `InkWell3d` washes the *enclosing* `Material3d` —
would light a whole menu up under one finger, and a menu can afford the answer
a navigation bar uses. What phase 5 did not have to work out is how far in
front: a transparent slab resting exactly on the menu's front face is coplanar
with it, and one lifted by exactly its own depth has its *back* face there
instead, which is the same fight from the other side. `MenuStyle3d
.itemDepthStep` is twice `itemThickness`, and the constructor asserts it.

**A sheet is `structural`, not `raised`, and the depth scale is where that is
said out loud.** A dialog is an object resting in front of a screen and a sheet
is a piece of the screen that has slid into view — the same distinction an app
bar and a card make, and the thickness token is the only place in the
catalogue where it can be stated rather than implied. `Sheet3dEdge` then makes
a side sheet the same class on another edge, which is the call `Divider3d` and
`VerticalDivider3d` deliberately did *not* make: a divider's indent runs along
its own axis and the two need different vocabulary, while a sheet's only
difference is where it is pinned.

## What phase 7 found

Eleven things. The first is the one three earlier phases each half-found, and
it is the reason this phase produced a token method rather than a fourth copy
of an argument.

**The "stand proud of it" arithmetic had been written by hand three times, and
this phase needed it four more times in one go.** A divider on a card (phase
4), a glyph on a navigation pill (phase 5), an item on a menu surface (phase
6) — and now a checkmark on a checkbox, a dot in a radio, a thumb on a switch
track, and a thumb *and* a fill on a slider track. Every one is one Material
surface drawn on another; every one needs a step above the **mean** of the two
thicknesses, because each slab is centred on its own plane; and resting the
front one on the back one's face makes the faces coplanar while lifting it by
exactly its own depth puts its *back* face there instead. Three components
deriving the same sentence is a habit; seven is a token.
`Thickness3d.stepOver(back, front)` is twice `minimumStepFor`, which is the
figure `MenuStyle3d.itemDepthStep` had already arrived at by hand for two equal
slabs, and every style in this phase takes its `depthStep` from it. The rule
underneath was never wrong — what was wrong was that it lived in four class
docs instead of in the scale that owns both numbers.

**A `Material3d` gives its child a *tight* depth, so a thicker child is
silently clamped — and that is what decides the shape of a two-part control.**
The obvious way to build a switch is a track with a thumb inside it. It does
not work: `Material3d`'s thickness is a tight depth constraint on its own
container, `Constraints3d.enforce` clamps a child's wish into it, and a 2dp
thumb inside a 1dp track comes out 1dp with nothing to say why — after which
the depth step computed from the token separates two slabs that are not the
thicknesses the token says. So a thumb has to be a **sibling** of its track in
a `Stack3d`, not a child of it, and the same goes for a checkbox's ink and its
wash. Nothing in the catalogue had met this before, because every earlier
nesting happened to use the same thickness at both levels — a navigation pill
and its destination are both `destinationThickness`.

**The node tier needed a name, and it turned out to have a second channel
nobody had used.** `NodeShift3d` and `SceneNodeShift3d` are the widget form of
`nodeOffset`, which the declarative layer did not have at all; phase 6 built
`Follower3d` for the same tier and stopped at anchoring. What is new is the
**scale**. The obvious way to fill a slider's track is to give a box a width
and change it, which is a relayout on every frame of a drag — and a
`nodeTransform` **pivots on the box's origin corner**, because the node carries
`T(offset + sceneOffset + nodeOffset) * nodeTransform * localTransform` and
`offset` *is* the corner. So the active track is the whole track scaled by the
value: its left end stays exactly where layout put it, its right end stops at
the thumb, and no box changes size. `test/slider_test.dart` drags across twenty
frames and asserts `needsFlush` is false after every one. This is the thing in
phase 7 that a two-dimensional framework has no equivalent for, and it was
found by asking "what would this cost per frame" rather than by drawing it.

**The checkmark question had a different answer from the one asked.** This plan
sent phase 7 to find out whether an 18dp glyph survives `glyphAtlasScaleFor`'s
32 buckets. It does, and the buckets were never the risk: the function rounds
**up**, so a bucket is never coarser than asked for. The real finding is one
step behind that. `AtlasText3dRenderer` asks for `unitsPerLogicalPixel *
logicalPixelsPerUnit * resolution`, and the first two are reciprocals — so the
rasterization scale is `resolution` and **nothing else**, independent of the
type size *and* of the surface's unit rate. An 18dp mark and phase 2's 220dp
heart are rasterized at the same texels per logical pixel. Small type here is
not a resolution problem, and `resolution` is the only dial that changes that,
at quadratic cost.

**And that made the probe's magnifying trick honest for a reason nobody would
have guessed.** `divider_rule` established turning the *surface's*
`unitsPerLogicalPixel` up rather than fattening a token, to make something too
small to probe big enough to probe. For a glyph that looks like cheating — a
bigger checkbox is not the checkbox under test. It is not cheating, because of
the paragraph above: raising the unit rate magnifies the drawn quad and leaves
the raster alone, so `checkbox_mark` is a magnifying glass held over the real
18dp rasterization. The probe passed: the marked box reads lighter in the
middle than an identical `primary` box beside it whose glyph has no renderer,
which is the `icon_glyph` pairing at the size a real control uses.

**A filter chip's checkmark and a checkbox's are opposite cases, and the
difference is what the substitution leaves behind.** Phase 4 declined the chip's
glyph because the container substitution already carried the signal. The same
test run on a checkbox gives the other answer: its substitution is an 18dp
square turning `primary`, and a filled swatch with nothing in it says nothing
at all. The rule is not "draw the glyph" or "do not" — it is *does the
substitution survive being looked at from across the room on its own*, and for
a chip it does because the chip still has its label.

**The arena did exactly what the drag plan promised, and phase 7 is the first
phase since phase 3 that needed nothing from the layout package.** Phases 4, 5
and 6 each found a gap there and each got a plan of its own. This one did not:
`PointerSequence3d.addArenaMember` and `HitTestTarget3d` were enough, and
`HitTestTarget3d`'s own dartdoc already named the customer in as many words —
"a knob that turns, a slider that tracks". `SliderGesture3d` is fifty lines
modelled on `_Drag3dGesture`, and `test/slider_test.dart`'s *arena* group
passed on the first run in both directions: a sideways drag moves the slider
and leaves the list at offset zero, a vertical drag scrolls the list and
reports no value at all. A seam designed for a customer that did not exist yet,
used two plans later without a change.

**A press that never moves is the arena's other half, and it claims at the
up.** Material's slider jumps to a tap on its track, which means the member has
to win without ever crossing a slop. The drag plan's own finding is what makes
it legal: what ends an arena is the **sweep** at the up, not the close, and
`Layout3dPointer.end` dispatches the up along the path *before* it sweeps. So
`_SliderPress3d.finish` resolves `accepted` from inside the up handler, which
rejects the scrolling view's member and lands the tap. A slider that waited to
be swept would work alone on a page and lose to a list.

**Flutter deprecated the spelling this component copies, while the component
was being written.** `Radio.groupValue` and `Radio.onChanged` are deprecated
after 3.32 in favour of a `RadioGroup` ancestor, which the defaults test found
by refusing to analyze clean. `Radio3d` keeps the older spelling deliberately —
a `RadioGroup3d` is an inherited widget plus a registry, and this catalogue's
radio is a leaf that states its own semantics — and the divergence is recorded
in the test rather than left for someone to trip over. It also cost the
drift-alarm standard a fifth grade: *the figure is reachable and the API around
it is going away*.

**A hand-picked threshold in a render probe is a distance wearing a
direction's clothes.** The harness's rule is to assert an order rather than a
difference, and phase 7 broke it in a way that reads like obeying it: "the
thumb is lighter than the track by more than 0.2" is a magnitude nobody can
justify, and it failed by a **thousandth** on a switch whose thumb was drawn
perfectly. What the question wanted was a channel order — `primary` is a purple
and reads with blue above red, `onPrimary` is near white and reads neutral, so
"the thumb carries less of the track's purple than the track does" compares two
quantities of the same kind and has no threshold in it. `docs/traps.md` records
it beside the rule it is a special case of.

**Flutter's control *is* its target, and this one's is not — which is the
48dp reach seen from the other side.** A real `Checkbox` and a real `Radio`
both lay out at 48 by 48, because a two-dimensional framework can pad a box
without moving anything in depth. Here the reach is invisible to layout by
design, so the control's own extent is Material's 40dp state layer and the
target is 48 — four logical pixels of margin on every side, and at a corner
four pixels is all a press has. That is the thinnest the reach has ever been in
this catalogue (a chip had eight), and `test/selection_test.dart` presses the
corner from both sides of the boundary.

## What phase 8 found

Nine things. The first changed the shipped meaning of a token, and the last is
the one that turns a per-frame animation into a free one.

**The ripple does not sit *over* the press wash, it *is* the press wash — and
that is a change to what a pressed control's `stateLayer.opacity` reads as.**
The obvious build is Flutter's: a pressed highlight everywhere plus a splash
on top, which is what `InkWell` does. Material 3 does not describe two things;
it describes the press state layer *arriving* with a ripple. Building it the
Flutter way gives a pressed, hovered control about 17% where the circle is —
the two composited — and this catalogue has a rule against exactly that, which
`test/ink_well_test.dart` states as *a press over a hover is one wash, the
stronger one*. So the controller splits one figure in two: the uniform half is
what the states *other than* the press resolve to, and the ripple carries
`(press - rest) / (1 - rest)`, the alpha that composites over that wash to
exactly the press figure. A hovered control still reads 8% outside the circle
and 10% inside it. The visible consequence for anyone reading the code is that
`layer.opacity` on a pressed control is now the *hover* figure, or zero, and
two assertions in `ink_well_test.dart` moved to say so.

**The press has to keep counting toward the peak after the finger has lifted,
and forgetting that makes the fade instantaneous.** `Material3dState.pressed`
leaves the set on the up; if the peak is resolved from the live states, it
drops to the uniform figure at that instant and the ripple's alpha goes to zero
in one frame — a fade-out that never fades. So while a run is alive the
controller resolves the peak with the press forced in, and what ends a ripple
is its own timeline rather than a state leaving a set. This was found by a
test, not by looking at a frame, which is the argument for having the timeline
be arithmetic in the first place.

**A held press stops asking for frames, and it falls out of the timeline
rather than being an optimization bolted on.** Once the circle has covered the
control and the wash has arrived, nothing about the picture changes until the
finger lifts — `InkRipple3dRun.isSettledAt` is that sentence — so the
controller stops its `Ticker` and holds the value. A button held down for a
minute schedules no frames at all after the first quarter second, and
`tester.pumpAndSettle()` therefore terminates on a *held* press, which it would
not if the ripple kept ticking. The run's clock and the ticker's clock part
company to make it work: the controller keeps a `_base` and adds the ticker's
own elapsed to it, because a `Ticker` restarted after a stop begins again at
zero. The minute of holding is simply not counted, which is correct, because
nothing in the run depends on it.

**A `Ticker`'s first tick is its own zero, and a test that does not know that
reads a ripple as not having started.** `tester.pump(const Duration(...))`
advances the clock, but the ticker's baseline is set *by* the first tick, so
the first frame after a press always reports elapsed zero — radius zero,
opacity zero. Three tests in `ink_ripple_test.dart` pump twice for this reason
and say so, and it is why the ink well's own press test settles rather than
pumping a fade duration. It is not a defect: `AnimationController` behaves
identically, and a ripple that jumped to its second frame's radius on its first
would be worse.

**A `Layout3dPointer` carries the live sequences, so a test that makes a new
one per statement never lets go of the press.** `Inset.pointer` was a getter
returning `Layout3dPointer(surface)` and four tests failed in four different
ways — a second press that kept the first one's origin, a cancel that lit
nothing, a ripple that never faded — all because `up()` went to an instance
that had never seen the `down()`. The existing `ink_well_test.dart` holds one
in a local for exactly this reason and never says why. It says why now, in
`docs/traps.md`, because the failure mode is a *plausible* wrong answer rather
than an error.

**A `Duration`'s comparisons are method calls, so a `const` constructor cannot
assert on one.** `InkRipple3dStyle` wanted `assert(expand > Duration.zero)` and
cannot have it: `>`, `isNegative` and `inMicroseconds` are all beyond a const
evaluator. This is the same trap phase 5 recorded for `List.length`, met from a
new direction, and the resolution is the same shape — keep `const`, handle the
degenerate value gracefully (a zero-length phase is instantaneous rather than an
infinity), and say in the class why the assert is missing.

**`setColor` does not premultiply, which is what lets the ripple borrow the
wash's colour.** The ripple carries an alpha and no colour of its own, so the
shader mixes toward `state_layer.rgb`. That only works because a state layer
whose *own* alpha is zero — a press with nothing else in force — still has its
colour in the block. `MaterialParameters.setColor` writes `[r, g, b, a]`
unpremultiplied, so it does. Had it premultiplied, the ripple would have needed
a fifth `vec4` and the two colours could have drifted apart.

**The probe's separation had to be designed, not discovered.** The first run of
`ripple_growth` failed at the second of three moments with 21 lit points out of
21 — the ripple had already covered the whole grid at 160ms, because
`Curves.ease` is 95% of the way home by then. The fix is not a looser
assertion: it is choosing the three moments and the grid together so that the
counts come out 15, 21 and 24 out of 24 with every reading at least eight
pixels clear of the circle's rim. That is the harness's rule about thresholds
seen from the other side — there is still no magnitude in the assertion, but
the *scene* has to be built so the ordering it asserts is a real question with
a comfortable answer.

**Turning the ripple on turned it on everywhere, and that is the phase's best
argument for where it was put.** Nothing in `Button3d`, `Chip3d`,
`ListTile3d`, `Card3d`, `Checkbox3d`, `Switch3d` or any of the overlays
changed by a line, and every one of them ripples, because all of them press
through `InkWell3d` and every `InkWell3d` writes through the one controller a
`Material3d` publishes. Two of the 470 existing tests moved, both in
`ink_well_test.dart`, and both because the *figure* moved rather than because
a component did.

## What phase 8 deliberately left out

Small on purpose, like every phase since the third, and these are the things a
reader will look for and not find:

- **Two ripples at once.** One box carries one pair of uniforms, so it carries
  one ripple; a second press replaces the first, origin, radius and clock.
  Material overlaps its splashes. Doing that here means an array in the uniform
  block and a loop in the fragment shader — a cost paid by every panel in the
  tree, for a case a reader meets when they drum their fingers on a button.
  `test/ink_ripple_test.dart` states the replacement as the behaviour rather
  than leaving it undefined.
- **An unbounded ripple.** M3's ripple on a small icon button escapes its
  container. It cannot here and it is not faked: the ripple is evaluated after
  the panel's own signed distance field has discarded everything outside the
  slab, which is what makes a *bounded* ripple free and an unbounded one
  impossible. There is no box outside the box.
- **Motion tokens.** `InkRipple3dStyle` holds Flutter's own `InkRipple`
  figures and is replaceable per controller, exactly as `ButtonStyle3d` is
  replaceable per button. It is not a seventh token family, and one animation
  is not a scale — the plan's *Out of scope* section says so and now says why
  the first animating component did not change its mind.
- **A ripple on a keyboard activation.** A press with no noted point ripples
  from the middle of the surface, which is what a space-bar activation would
  get if anything in this stack activated a control from the keyboard. Nothing
  does yet; the fallback exists so that a component driving the controller
  directly — an imperative scene, a component with its own gesture — is never
  handed a ripple at the origin corner.
- **`InkResponse3d`'s circular splash.** Flutter distinguishes a bounded ink
  well from an unbounded ink response with a circular splash. That distinction
  is about clipping to a container, which is the previous bullet, so there is
  one interactive primitive here and not two.

## What phase 7 deliberately left out

Small on purpose, as phases 3 to 6 were told to be, and these are the things a
reader will look for and not find:

- **A checkbox's tristate.** Material's third value is an `Icons.remove` in
  place of the tick and a `mixed` semantic flag. Neither is hard; it is simply
  a third state in every row of a four-state table, and phase 7's table was
  already the largest in the catalogue.
- **`RadioGroup3d`.** See the finding above: `Radio3d` keeps the spelling
  Flutter deprecated, because the replacement is an inherited widget and a
  registry, and the place that work belongs is beside a `FormField3d` rather
  than inside a leaf control.
- **A slider's tick marks and its value indicator.** Divisions *work* — the
  value snaps and the thumb draws at the step it snapped to — but the marks
  along the track and the label above the thumb are not drawn. Both are
  ornament on the component whose design question here was the drag, and the
  indicator wants the overlay lane as well.
- **A range slider.** Two thumbs competing for one pointer is a second arena
  problem rather than a second thumb, and it deserves its own answer.
- **A growing thumb, and animation generally.** Material's switch grows its
  thumb from 16dp to 24dp as it crosses. That is a motion token this package
  does not have, and a thumb that *jumped* between two sizes would put a size
  change on the interaction path where every other state in this catalogue is
  a colour. The thumb is one size; what moves is where it is. When the motion
  tokens land, the slide is already on the tier that can animate for free.
- **A slider that fills its parent.** `Slider3d` takes a `width` in logical
  pixels, defaulting to Material's narrowest 144dp, where Flutter's fills
  whatever room it is given. That is the price of the node tier: the thumb's
  position is written by the widget that builds it, so the width has to be
  known before layout rather than after it. A slider that sized itself from
  its constraints would have to move its thumb from inside `performLayout`,
  which is a different component and probably a `MultiChildLayout3d`.
- **The 2024 "expressive" slider.** Flutter now ships two M3 sliders: a 4dp
  track with a 20dp round thumb, and a 16dp track with a 4 by 44 bar handle.
  This package takes the first, and not by accident — a thumb standing proud
  of a track is exactly what this catalogue's third dimension is for, while a
  handle inset into a track of its own height is a picture that a 3D scene has
  nothing to add to.
- **A labelled control.** There is no `CheckboxListTile3d` or its siblings.
  `ListTile3d` already takes a `trailing` slot and a title string it can
  announce, so the composition is a caller's — and a component that put a
  checkbox in a tile would have to decide which of the two states its own
  announcement, which is the phase-4 two-labels problem with a worse answer.

## What phase 6 deliberately left out

Small on purpose, as phases 3 and 4 were told to be, and these are the things a
reader will look for and not find:

- **`AlertDialog3d`.** Material's dialog with a title, an icon, supporting text
  and a row of actions. It is a column and a row inside `Dialog3d`, and
  nothing about that arrangement is three-dimensional: it would be the first
  component in the catalogue that exists only to save a caller from writing a
  `SceneColumn3d`. `Dialog3d` is what Flutter's own `Dialog` is, and the
  arrangement is a caller's.
- **A menu that reflows to stay inside the panel.** Flutter's
  `PopupMenuButton` shifts its menu against the screen edges. Here the "screen"
  is a surface that may be at any angle in a room, and what "off the edge"
  should mean for it is a real design question rather than an oversight — the
  same question `docs/traps.md` records for M3's window size classes.
- **A tooltip on a long press.** Material shows one on a touch screen after a
  long press. That needs a gesture arena entry beside whatever the child
  already has, and the innermost recognizer wins the arena — so a tooltip
  around a button would take the button's own long press. Hover is the trigger
  that composes.
- **A snack bar's swipe-to-dismiss and its second line.** `Dismissible3d`
  exists and would do the first; both are ornament on a component whose design
  question here was the queue.
- **A sheet's drag handle, and a draggable sheet.** A sheet that can be dragged
  to a height is a scroll interaction wearing a sheet's clothes, and it wants
  the drag lane rather than the overlay lane. `showBottomSheet3d` also does
  **not** shorten the screen the way Flutter's `Scaffold.showBottomSheet` does:
  an overlay is not a scaffold slot, by design, and a sheet that has to make
  room for itself is a different component.
- **Animation, everywhere.** Nothing here slides, fades or grows.
  `Route3dTransition.none` is the layout package's honest default and this
  package has no motion tokens; a dialog appears and disappears. The seam is
  `Navigator3d.transition`, and it is one hook away whenever the motion tokens
  land.

## What phase 4 deliberately left out

Small on purpose, as phase 3 was told to be, and these are the things a reader
will look for and not find:

- **A filter chip's checkmark.** Material draws one in the leading slot of a
  selected filter chip. It is a second glyph competing with the container
  substitution for the same signal, and the container is the one that survives
  at a distance; a chip that wants one passes an `avatar`.
- ~~**`VerticalDivider3d`.**~~ Landed in phase 5, beside the navigation rail,
  and it was exactly what this entry said it would be: the same class with its
  axes swapped, with `indent` and `endIndent` running along the vertical axis
  instead.
- **A tile's `titleAlignment`.** Flutter has four; this one centres the
  leading and trailing slots against the text, which is `ListTileTitleAlignment
  .center` and right for one- and two-line tiles.
- **A card's `clipBehavior`.** Flutter's clips its child to its own shape.
  That needs a clip whose region is a rounded rectangle, and `Clip3dRegion` is
  an intersection of planes — convex, and a radius is not expressible that way.
  The panel shader carves its own radius; a *child* overflowing a rounded card
  is not clipped to it, and will not be until something carries a shape into
  the clip contract.
- **A chip's press elevation.** Material lifts an elevated chip to level 1
  under a press. This package ships flat chips, which is the `flat` variant
  Flutter itself defaults to.

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
- ~~**`TapTarget3d` grows the ray region and not the box**~~, which is still
  true and no longer the trap it was. Phase 2 found the reach delivered no
  press at all; phase 3 closed that in the layout package, under
  [a tap target that delivers a press](../../flutter_scene_layout3d/plans/2026_09_02_a_tap_target_that_delivers_a_press.md).
  What remains is the rule underneath it, and it is the one every component
  from phase 4 on has to obey: **a target reaches past its own extent and its
  parent does not**, so it sits outside every box the size of the control —
  the panel and the semantics box included. Layout, intrinsics,
  `ensureVisible3d` and semantics all still see the smaller rectangle, which
  is the design and is why a dense toolbar's targets can overlap.
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
  once enough components animate to know which ones are actually used. Phase 8
  is the first component that animates at all, and it deliberately did **not**
  open the family: `InkRipple3dStyle` is a component style like
  `ButtonStyle3d`, replaceable per controller, and it holds Flutter's own
  `InkRipple` figures. One animation is not a scale.
- **Adaptive layouts.** M3's window size classes assume a rectangular window;
  what a size class means for a surface floating in a scene is a genuine design
  question and not one this plan should answer in passing.
