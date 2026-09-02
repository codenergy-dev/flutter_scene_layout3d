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

**What is here today is the token layer and the theme that carries it.** There
is no `Button3d`, no `Card3d`, no `Material3d` — those come next, and this
README will grow with them. What you can do today is state a theme, publish it
to a layout surface, and build a component of your own out of the tokens,
which is exactly what the catalogue will do.

## The five families, and why two of them are invented

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

/// A themed panel, which is roughly what `Material3d` will be.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final thickness = theme.thickness.raised;
    return SceneDecoratedBox3d(
      decoration: BoxDecoration3d(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: theme.shape.medium,
        bevel: theme.shape.bevelFor(thickness),
        elevation: theme.elevation.level1,
        surfaceTint: theme.colorScheme.surfaceTint,
      ),
      child: child,
    );
  }
}

Widget screen(Node parent) => SceneLayout3d(
  parent: parent,
  size: const Size3d(4, 3, 0.5),
  child: SceneTheme3d(
    data: Theme3dData.dark,
    textRendererFactory: AtlasText3dRenderer.new,
    child: ScenePadding3d(
      // World units, not logical pixels: 0.16 units is 16dp at the default
      // rate. See "Two units, side by side" below — this is the one figure
      // in the example the theme does not convert for you.
      padding: const EdgeInsets3d.all(0.16),
      child: Panel(
        child: SceneText3d(
          'Continue',
          style: Theme3dData.dark.typography.labelLarge.copyWith(
            color: Theme3dData.dark.colorScheme.onSurface,
          ),
        ),
      ),
    ),
  ),
);
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

A `Layout3d` of your own reads the theme with the `theme3d` extension:

```dart
class ThemedSlab extends Layout3d {
  @override
  void performLayout() {
    // The theme names a figure in logical pixels; the metrics says what a
    // logical pixel is worth here. Never the other way round.
    final depth = metrics.dp(theme3d.thickness.raised);
    size = constraints.constrain(Size3d(metrics.dp(120), metrics.dp(40), depth));
  }
}
```

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
and paddings are not: those are world units today, because the widget layer
has no way to read the surface's metrics. That is a real gap and the catalogue
will have to close it; until then, `metrics.dp(...)` inside a `performLayout`
is the conversion, and a figure written in a widget's `build` is in units.

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

## Nothing draws until an application installs a painter

This is inherited from the layout package and it surprises everyone once.
`BoxDecoration3d.painterFactory` is null until something sets it, and a
decorated box with no painter measures, lays out and draws nothing at all — no
error, no warning. It is null by default because building geometry needs a GPU
context that `flutter test` does not have.

```dart
final material = await loadFmatMaterial('assets/box_decoration3d.fmat');
BoxDecoration3d.painterFactory =
    (_) => BoxDecoration3dPainter(createMaterial: () => material);
```

**Compiling that shader is not your job.** `flutter_scene_layout3d`'s own
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

Honestly, and in the order it is planned: `Material3d` and `InkWell3d`, the
one primitive everything else is built from; `Icon3d`, which is very likely a
one-glyph `Text3d` through the same atlas as every label but has not been
verified on a GPU yet; the buttons; cards and list tiles; `Scaffold3d` and the
bars; the overlays; the selection controls; and a press ripple, which the
panel shader can express in two more uniforms and a `smoothstep`.

Text input is not planned at all: there is no `EditableText3d`, no selection,
no cursor and no keyboard plumbing anywhere in the stack, so a `TextField3d`
is a project of its own rather than a component.

The plan is
[`plans/2026_09_01_flutter_scene_material3d.md`](plans/2026_09_01_flutter_scene_material3d.md),
and it is kept up to date with what turned out to be wrong.
