# flutter_scene_material3d

Material Design 3, built as real geometry on
[`flutter_scene_layout3d`](../flutter_scene_layout3d).

Material 3 is a specification for a flat surface, and this is not one. Every
token in it that stands in for depth has to be re-derived here, because here
the depth is real: an elevation is a painted shadow in Flutter and a distance
in a scene; a disabled control is 38% opacity in Flutter and there is no
opacity in this stack at all; a component has no thickness on a screen and
must have one when it is an object. Half the work of this package is answering
those honestly. The other half is a long, ordinary list of components.

**What is here today is the token layer, the theme that carries it, and the
primitive every component is made of.** `Material3d` is the surface;
`InkWell3d` makes it interactive; `Icon3d` draws a glyph; `SceneTextStyle3d`
styles a group of labels. There is no `Button3d` and no `Card3d` yet — those
come next, and this README will grow with them — but a button is a
`Material3d` with an `InkWell3d` in it and a set of tokens, so you can write
one today.

## The six families, and why two of them are invented

Four of the families are Material's, transcribed:

- **`ColorScheme3d`** — the colour roles, all forty-six of them, in a
  hand-written light and dark baseline. A role is a *job* rather than a
  colour: `primary` is "the most prominent thing on this screen",
  `onPrimary` is "what reads on top of that". Generating a scheme from a seed
  colour is out of scope; the baselines are enough to build every component
  against, and a generator can be added later without touching one.
- **`Typography3d`** — the fifteen-style type scale, as Flutter `TextStyle`s,
  which `Text3d` consumes directly. Sizes are in logical pixels and stay that
  way; `Text3d` multiplies by the metrics to reach world units.
- **`ShapeScale3d`** — the corner radii, `none` through `full`.
- **`Elevation3d`** — the six levels, 0 to 12dp.

The fifth has no Material counterpart at all:

- **`Thickness3d`** — how deep a component is. Material publishes nothing
  about thickness because on a screen there is none. A `Card3d` here is *how
  deep*? The scale answers once, in the theme, rather than component by
  component: 1dp for a divider or a chip, 2dp for a button or a list tile, 4dp
  for a card or a dialog, 8dp for an app bar or a sheet.

The sixth is Material's, and it needed a name because every interactive
component resolves it the same way:

- **`StateLayerOpacity3d`** — 8% for a hover, 10% for a focus or a press, 16%
  for a drag. Opacities rather than colours, because the colour is whatever
  the component is drawn on — `onSurface` over a surface, `onPrimary` inside a
  filled button. A component in more than one state at once gets the
  *strongest* wash and never their sum, which is what `forStates` says.

### Two rules come with a thickness, and they cost real time

**A thickness fights the depth ordering.** `Stack3d.depthStep` pulls each
successive child toward the viewer by a fixed amount, but a slab is centred on
its own plane and reaches half its thickness forward — so two stacked children
are genuinely separated only when the step exceeds the *mean* of their
thicknesses. Under that, the back child pokes through the front one, wins the
depth test where they overlap, and the stack looks inverted. A drop target
inherits the same failure: a drag picks the nearest acceptor along the ray, so
a slab that reaches too far forward takes a drop that visibly belonged to the
card drawn in front of it.

That is why the thickness scale carries the step it was designed against, and
a predicate that checks them together:

```dart
const thickness = Thickness3d.baseline;   // 1, 2, 4, 8 on a 12dp step
assert(thickness.separates(thickness.structural, thickness.raised));
```

The scale's own numbers clear its own step with half again to spare. A theme
that makes components deeper has to raise the step with them, and `separates`
is how a component says so out loud instead of discovering it as a stack that
draws backwards. Note that `Thickness3d.depthStep` is in logical pixels while
`Stack3d.depthStep` is in world units — convert at the point of use, with
`metrics.dp(...)`, the way every other Material figure crosses that boundary.

**A thickness is not free at the edges.** A 4dp-thick card with a 12dp corner
radius and no bevel has a knife edge where a real object would have a softened
one, and under a grazing light it reads as a cut-out rather than as a thing.
So the bevel is part of the shape scale, stated as a fraction of the
thickness rather than as a figure of its own — a 1dp divider and an 8dp app
bar want visibly different rims:

```dart
BoxDecoration3d(
  borderRadius: theme.shape.medium,                      // 12dp face radius
  bevel: theme.shape.bevelFor(theme.thickness.raised),   // 1dp rim
)
```

## The one call that makes anything draw

Nothing in this package draws until an application installs a panel painter,
and installing one means loading a compiled shader, which needs a GPU context.
That is one call, made once, before `runApp`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeMaterial3d();
  runApp(const MyApp());
}
```

It awaits `Scene.initializeStaticResources()` first — the engine prints
*"Flutter Scene is not ready to render. Skipping frame"* until that resolves,
and a `.fmat` cannot be loaded before it — and then points
`BoxDecoration3d.painterFactory` at the panel shader. It is idempotent, so
calling it beside an application that already awaits the engine costs nothing.

**The default text renderer is not in it, and cannot be.** A `Text3dRenderer`
is owned by the label that holds it and disposed with it, so there is no
global one to install; it reaches labels through the widget tree, one instance
each. The second half of setup is therefore a widget rather than a call, and
it goes in beside the theme:

```dart
SceneTheme3d(
  data: Theme3dData.light,
  textRendererFactory: AtlasText3dRenderer.new,   // the other half
  child: screen,
)
```

### Why it is not the two lines the layout package's README shows

That form installs one material and hands it to every box, which is right
while the panels on a surface look alike — `BoxDecoration3dPainter` writes
each box's parameters into the material it was given, so **the last box
painted wins the block**. A catalogue is the case that breaks it: a screen, a
card on it and a filled button on that, in three colours at three elevations,
all collapsing onto whichever painted last, with nothing anywhere saying why.

So `initializeMaterial3d` gives every decorated box a material of its own.
That needs a *synchronous* factory, since `createMaterial` is called during a
layout pass, while `loadFmatMaterial` is asynchronous — and the seam that
closes the gap is its `factory` parameter, which hands you the compiled
shader, the metadata and the vertex variants, so one asynchronous load
captures what it takes to build any number of instances afterwards.
`loadPanelMaterialFactory` is public for a caller writing a painter of its
own.

## Material3d, and everything that is one

`Material3d` is a `SceneDecoratedBox3d` with the theme resolved into it. It
owns the colour, the shape, the elevation, the state layer, and the token
Material does not have because a screen has none of it — the thickness. Every
property is nullable and falls back to the theme, so a bare one is a flat
surface at the theme's own colours:

```dart
Material3d(
  color: theme.colorScheme.primary,
  contentColor: theme.colorScheme.onPrimary,
  shape: theme.shape.full,
  elevation: theme.elevation.level1,
  thickness: theme.thickness.standard,
  padding: const EdgeInsets3d.symmetric(horizontal: 24, vertical: 10),
  child: InkWell3d(
    onTap: _submit,
    child: const SceneText3d('Continue'),
  ),
)
```

Everything it takes is in logical pixels, including the padding and the
thickness, which it converts through `Layout3dMetricsScope.of(context)` — so
**a `Material3d` has to be built inside a `SceneLayout3d`**, and asserts when
it is not.

`contentColor` does two jobs, which is why it is one property: it is the
colour of the state-layer wash (Material's own rule — a wash is the surface's
"on" colour at a low opacity) and it is the colour of the labels and icons
below, through a `DefaultTextStyle` the surface installs. That is what makes
`Icon3d(Icons.favorite)` inside a filled button come out `onPrimary` without
the button mentioning icons at all.

Two things about padding and depth that cost time once each. **An
`EdgeInsets3d` has six faces**, so `EdgeInsets3d.all(16)` insets the front as
well, pushing the child into the slab where the panel wins the depth test and
hides it; state the two in-plane axes. And **alignment defaults to
`Alignment3d.frontCenter`**, not `center`, for the same reason: a label
centred in depth sits inside a 4dp card rather than on it.

### A hover must not rebuild anything

`InkWell3d` drives the surface's state layer through an `InkController3d` that
the enclosing `Material3d` publishes, and never through `setState`. That is
not a micro-optimisation; it is the design of the whole decoration layer.
`DecoratedBox3d.stateLayer` is a setter that writes one shader uniform and
touches layout nowhere, so a pointer crossing a list of twenty tiles costs
twenty uniform writes and no layout at all. An ink well that rebuilt on every
hover would throw that away and take the repaint-only tier with it. The
package's own tests assert it by counting: a hover, a focus and a press each
change the wash while the build count and the layout count stand still.

A component whose *tokens* change with a state — a filled button really is a
different colour when pressed, not merely washed — cannot use that channel for
that half. It rebuilds, deliberately, and pays for it.

Two edges to know. A press **focuses** the control by default, and since
nothing here reads Flutter's `highlightMode` to tell a pointer focus from a
keyboard one, the focus wash outlives the press; pass
`focusOnPointerDown: false` where that is wrong. And Material's 48dp minimum
target, which `InkWell3d` asks for, currently grows the ray region without
delivering a press in the margin — see *Pointers* in
[docs/traps.md](../../docs/traps.md); it is a gap in the protocol below, not
in this package, and a test here pins it so that closing it is noticed.

## Icons are a font, and it was checked rather than assumed

`Icon3d` is one code point of an icon font drawn as a one-character
`SceneText3d`, out of the same glyph atlas as every label. The catalogue plan
guessed that would work; `examples/render_probe`'s `icon_glyph` scene proved
it on a GPU, next to a control with no renderer that draws nothing. So an icon
costs one quad, a screen of icons and labels is one texture, and everything
the label path already has — measurement off the relayout path, the unit
contract, the clip planes — applies unchanged.

```dart
Icon3d(Icons.favorite, size: 24)          // colour from the surface it is on
```

Two consequences of being text. It is drawn **unlit**, like every label, so it
keeps its colour as a surface turns away from a light while the panel under it
does not — which means contrast has to be chosen against the unlit glyph and
the lit panel. And `IconData.matchTextDirection` is not honoured: a mirrored
icon needs a negative scale on the glyph quad, which the atlas renderer does
not express.

## Naming a type style instead of building one

The type scale's fifteen fields are also a value, `Typography3dToken`, so a
component can be *handed* a role rather than hard-coding one. The theme is
where a role meets a colour:

```dart
theme.textStyle(Typography3dToken.labelLarge, color: theme.colorScheme.onPrimary)
```

For a group of labels that share a role — a list tile's supporting text, a
section of captions — `SceneTextStyle3d` installs it for a subtree and merges
rather than replaces, so an enclosing colour survives an inner style that does
not state one.

## Getting a theme in place

`SceneTheme3d` installs both halves of the theme channel at once, and both are
needed. The widget layer reads `Theme3d.of(context)`, like any inherited
widget. The imperative layer cannot: a `Layout3d` is not a widget and
`performLayout` is not a build, so there is no `BuildContext` anywhere near
the code that decides a size. That half reads the theme out of the layout
surface's owner slot, which is what `Layout3dSlot` was added to
`flutter_scene_layout3d` for.

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';

Widget screen(Node parent) => SceneLayout3d(
  parent: parent,
  size: const Size3d(4, 3, 0.5),
  child: SceneTheme3d(
    data: Theme3dData.dark,
    textRendererFactory: AtlasText3dRenderer.new,
    child: SceneCenter3d(
      child: Builder(
        builder: (context) {
          final theme = Theme3d.of(context);
          return Material3d(
            color: theme.colorScheme.primary,
            contentColor: theme.colorScheme.onPrimary,
            shape: theme.shape.full,
            elevation: theme.elevation.level1,
            padding: const EdgeInsets3d.symmetric(
              horizontal: 24,
              vertical: 10,
            ),
            textStyle: theme.textStyle(
              Typography3dToken.labelLarge,
              color: theme.colorScheme.onPrimary,
            ),
            child: InkWell3d(
              onTap: () => debugPrint('tapped'),
              child: const SceneText3d('Continue'),
            ),
          );
        },
      ),
    ),
  ),
);
```

That is a filled button, and phase 3 of the plan is mostly giving it a name.
Every figure in it is in logical pixels: `Material3d` converts the padding and
the thickness through the surface's unit contract, and the painter converts
the radius and the elevation at paint time.

A component of your own reads the theme the same way. `Theme3d.of(context)`
in the widget layer, and — because a `Layout3d` is not a widget and
`performLayout` is not a build — the `theme3d` extension in the imperative
one:

```dart
class ThemedSlab extends Layout3d {
  @override
  void performLayout() {
    // The theme names a figure in logical pixels; the metrics says what a
    // logical pixel is worth here. Never the other way round.
    final depth = metrics.dp(theme3d.thickness.raised);
    size = constraints.constrain(
      Size3d(metrics.dp(120), metrics.dp(40), depth),
    );
  }
}
```

`SceneTheme3d` is a layout widget, so it goes *inside* the surface, under a
`SceneLayout3d` and not above it — the slot is written by a box that has to
attach to an owner before it can write anything. To theme a subtree with no
layout in it, use `Theme3d` on its own; to theme a surface built imperatively,
hand the slot straight to the surface:

```dart
SceneLayout3d(
  slots: {Theme3dData.slot: Theme3dData.dark},   // not a const map, see below
  child: screen,
)
```

That form writes only the owner slot, so `Theme3d.of(context)` below it still
finds nothing. (The map cannot be `const`: a `Layout3dSlot` has value
equality, and a `const` map key needs primitive equality.)

With no theme published, both `Theme3d.of` and `theme3d` return
`Theme3dData.light` rather than throwing, for the same reason
`Layout3d.metrics` falls back to a standard unit contract: a component drawn
in the wrong-but-valid baseline is visible and diagnosable, while a layout
pass that threw over a missing default is neither. `Theme3d.maybeOf` and
`hasTheme3d` answer the question directly when the difference matters.

**A theme change relayouts the subtree**, and that is correct: the tokens
decide paddings, type sizes and thicknesses, so changing one changes sizes and
nothing else would tell the tree. It follows that nothing on a per-frame path
may write a theme. A hover, a focus or a press is a `stateLayer` and a
`decoration` on the box — the repaint-only tier — and marks nothing dirty at
all. Writing an *equal* theme is free, because every token family has value
equality.

## Two units, side by side

Everything in this package is in **logical pixels**. Everything in
`flutter_scene_layout3d` is in **world units**. The theme turns a name into a
dp figure; the metrics turns a dp figure into world units; and that arrow only
points one way. A component that reads a Material number off the metrics, or
that stores world units in a token, has mixed the two frames, and the failure
is silent — it looks right at the default rate of 0.01 units per logical pixel
and comes apart on a surface bound to a camera.

Everything on a `BoxDecoration3d` — the corner radii, the bevel, the border
width, the elevation — is converted for you at paint time, which is why the
example above writes `theme.shape.medium` straight into a decoration. Sizes
and paddings are not, and a `build` method reads the contract for those
through `Layout3dMetricsScope.of(context)`:

```dart
final metrics = Layout3dMetricsScope.of(context);
ScenePadding3d(padding: metrics.dpInsets(const EdgeInsets3d.all(16)), ...)
```

`Material3d` does that for you — its `padding` and `thickness` are in logical
pixels — which is why it has to be built inside a `SceneLayout3d`. A
`ScenePadding3d` or a `SceneSizedBox3d` you write yourself takes world units
and always will, and nothing warns you if you forget to convert.

## What a theme deliberately does not do

**It does not install a text renderer unless you ask.**
`SceneTheme3d.textRendererFactory` is null by default; pass one — a
constructor tear-off such as `AtlasText3dRenderer.new` — and the child is
wrapped in a `DefaultTextRenderer3d`, so an application says "here is my
theme, and here is how labels are drawn" in one call. It is not the default
because a renderer is not a token: it is a *resource*, owned by the label that
holds it and disposed with it, which is exactly why `DefaultTextRenderer3d`
carries a factory rather than an instance. Whatever you pass must be a stable
function; a closure written inline in `build` is a new function every build
and rebuilds every renderer in the tree.

**It does not write the surface's metrics.** `Layout3dMetrics` carries a
`VisualDensity3d` of its own and applies it in `effectiveConstraints`, and a
`Theme3dData` carries one too, because density is a theme decision in
Material. They can disagree, and the theme wins:
`theme.effectiveConstraints(constraints, metrics)` applies the theme's density
through the metrics' own arithmetic. A widget inside the tree quietly
rewriting the surface's unit contract would be a theme reaching well outside
its own vocabulary.

## Disabled is a colour, not a filter

Flutter draws a disabled control by compositing it at 38% opacity. There is no
subtree opacity in this stack and there cannot be until `flutter_scene` grows
a per-node opacity the materials honour — `Node` has `visible`, a
selection-outline colour, layer and light masks, and no opacity or tint of any
kind.

So a disabled control here is expressed by *substituting tokens*:
`colorScheme.disabledContent` (`onSurface` at 38%) for the label and the icon,
`colorScheme.disabledContainer` (`onSurface` at 12%) for the slab behind them.
Those are the figures Material's own specification states as the *result*, so
this is the more faithful spelling as well as the only available one. What it
cannot do is fade an arbitrary child subtree; a component does not need that,
and an application that does has to build it out of colours too.

## An elevation is a height, and it casts no shadow

`BoxDecoration3d.elevation` moves the panel's geometry toward the viewer by
`metrics.dp(elevation)`. That is the whole of it. The panel shader declares
`blending: alpha` — its antialiased outline *is* an alpha — and
`flutter_scene` drops every non-opaque material before the shadow pass reaches
a shadow map, so no amount of lighting will produce a contact shadow.

A raised card therefore reads as raised through parallax, occlusion and
**tint**, which is the half of Material's elevation model that transfers
intact and carries more weight here than it does in Flutter: it is what tells
a level-3 surface from a level-1 one when the camera is head-on and parallax
gives nothing. `Elevation3d.tintOpacityFor` is Material's published table, and
it delegates to the same function the shader's uniforms are resolved through,
so a component and the panel it draws on cannot disagree.

## Compiling the shader, and the build hook that does it

**It is not your job.** `flutter_scene_layout3d`'s own
build hook runs `impellerc` over it for every application that depends on the
package, so the source path above resolves through that package's generated
manifest and your hook needs nothing in it about panels. This package ships no
build hook at all, deliberately: the only thing it might call there is
`buildEngineAssets`, and a *library* must never call that — it would put a
second copy of the engine's shaders in every application that used it.

If you are migrating an application that used to compile the shader itself,
empty its `flutter_scene_generated/` directory once, keeping the `.gitignore`.
Two packages offering the same source path throws *"Multiple generated .fmat
materials"*, and a generated tree is not cleaned by removing the call that
filled it.

## What is not here yet

Honestly, and in the order it is planned: the seven buttons; cards and list
tiles; `Scaffold3d` and the bars; the overlays; the selection controls; and a
press ripple, which the panel shader can express in two more uniforms and a
`smoothstep` and which the uniform state layer stands in for until then.

Text input is not planned at all: there is no `EditableText3d`, no selection,
no cursor and no keyboard plumbing anywhere in the stack, so a `TextField3d`
is a project of its own rather than a component.

The plan is
[`plans/2026_09_01_flutter_scene_material3d.md`](plans/2026_09_01_flutter_scene_material3d.md),
and it is kept up to date with what turned out to be wrong.
