---
status: pending
created_at: 2026-09-01T19:15:00Z
updated_at: 2026-09-01T19:15:00Z
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

### The four things that block the first component

None of these is deep. All four are in `flutter_scene_layout3d`, not here, and
**all four should land before this package has a `pubspec.yaml`**, because a
catalogue written around the absence of any of them would have to be unwritten
afterwards.

1. **The declarative layer cannot draw.** There is no `SceneDecoratedBox3d`,
   and `SceneContainer3d` has no `decoration` — so a Flutter developer building
   from `build()` can arrange boxes and cannot make one visible. The imperative
   `DecoratedBox3d` has been there since phase 1 of size-driven geometry; only
   the widget form is missing. Two dartdoc examples in
   `lib/src/widgets/drag.dart` (lines 24 and 217) already show
   `SceneDecoratedBox3d` as though it existed, which is the repository's rule
   about documenting what is not there, broken in the one place nobody looked.
2. **There is no default text renderer.** `Text3d.renderer` is null by default
   and a `Text3d` with no renderer draws nothing — deliberate, because the
   package cannot verify a renderer in `flutter test`. But it means every label
   in a catalogue has to be handed an `AtlasText3dRenderer` explicitly, and the
   renderer is owned per box. What is wanted is the shape `DefaultTextStyle`
   already has, and `SceneText3d` already merges: an inherited default the
   theme installs once. Call it `DefaultTextRenderer3d`, put it beside the
   style, and let `SceneText3d.renderer` override it.
3. **There is nowhere tree-wide to put a theme.** `Layout3dOwner` carries
   `basis`, `metrics`, `painters` and `focusScope` for one stated reason — it
   is state both layers need and the imperative one has no `BuildContext` to
   read an inherited widget with. A theme is exactly that shape, and *Material
   vocabulary must not go into the layout package*. The seam that resolves both
   is a typed slot on the owner:

   ```dart
   // In flutter_scene_layout3d.
   final T? value = owner.slot(themeSlot);
   owner.setSlot(themeSlot, Theme3dData.light());
   ```

   A `Layout3dSlot<T>` key, a map on the owner, no Material in the layout
   package and no `BuildContext` in the imperative one. The alternative —
   requiring every component constructor to take a theme — is what Flutter
   rejected when it made `ThemeData` inherited, and for the same reason.
4. **Compiling the shader is an application's job, and it should not be.**
   `assets/box_decoration3d.fmat` is compiled by `impellerc` in
   `examples/render_probe/hook/build.dart`, through a symlink, in the *app*.
   Nothing else in either repository compiles it, so a developer who adds this
   catalogue to their own app gets panels that draw nothing until they discover
   they must write a build hook naming a file inside somebody else's package.
   **Answer this before phase 1**: find out whether a package's own
   `hook/build.dart` runs when that package is a dependency rather than the
   root. If it does, `flutter_scene_layout3d` grows a hook, the problem
   disappears for every consumer, and this package inherits the fix. If it does
   not, this package ships the hook a consumer copies, and says so in the first
   paragraph of its README rather than in a footnote.

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

- [ ] **Phase 0 — the four blockers, in `flutter_scene_layout3d`.**
      `SceneDecoratedBox3d` (and `decoration` / `stateLayer` on
      `SceneContainer3d`, matching Flutter's `Container`);
      `DefaultTextRenderer3d` beside `DefaultTextStyle`; `Layout3dSlot<T>` and
      `Layout3dOwner.slot` / `setSlot`; the build-hook question answered and
      whichever fix it implies. Fix the two dartdoc examples that already
      reference `SceneDecoratedBox3d`. This phase ships as a commit against the
      layout package, with its own tests, before this package exists.
- [ ] **Phase 1 — the package and the tokens.**
      `packages/flutter_scene_material3d`, added to the workspace.
      `ColorScheme3d`, `Typography3d`, `ShapeScale3d`, `Elevation3d`,
      `Thickness3d`, `Theme3dData`, `SceneTheme3d`, `Theme3d.of`. All
      arithmetic, all headless, all `lerp`-able.
- [ ] **Phase 2 — `Material3d`, `InkWell3d`, `Icon3d`, `Text3d` styling.**
      The primitive and the interaction layer over it, plus the icon question
      settled. First render probe: a themed surface at three elevation levels
      is three distinguishable colours (the tint), and a hover lightens one.
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

- **Phase 0 is in another package**, and the layout package's plans are all
  `completed`. Whatever lands there needs its own plan or a documented
  amendment to an existing one; do not smuggle four new public classes into
  `flutter_scene_layout3d` under this plan's number.
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
