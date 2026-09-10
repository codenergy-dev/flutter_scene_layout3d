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

**The catalogue is here.** The token layer and the theme that carries it; the
primitive every component is made of — `Material3d` is the surface, `InkWell3d`
makes it interactive, `Icon3d` draws a glyph, `SceneTextStyle3d` styles a group
of labels; Material's seven buttons over one `ButtonStyle3d`; the surfaces and
rows (`Card3d`, `ListTile3d`, `Divider3d`, `Chip3d`); the structure
(`Scaffold3d`, `AppBar3d`, `SliverAppBar3d`, `NavigationBar3d`,
`NavigationRail3d`); the overlays (`Dialog3d`, `Menu3d`, `SnackBar3d`,
`Tooltip3d`, `BottomSheet3d`); the selection controls (`Checkbox3d`,
`Radio3d`, `Switch3d`, `Slider3d`); and the press ripple. What is *not* here
is listed honestly at the end of this file, and text input is not planned at
all.

`examples/layout3d_gallery` draws all of it, on a panel and on a table, and is
the shortest way to see what any of this looks like.

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

### The press ripple, on the same tier

A press does not wash the whole control at once: it grows a circle out of the
point the finger landed on, which is Material 3's own description of how a
press state layer arrives. That is the one thing in this package that writes a
shader uniform **every frame**, and it stays exactly where the hover is:

```dart
Material3d(                     // creates the ticker the ripple runs on
  child: InkWell3d(             // says where the press landed
    onTap: submit,
    child: const SceneText3d('Continue'),
  ),
)
```

Nothing above needs writing, because every component in the catalogue already
presses through an `InkWell3d`. What is worth knowing about it:

* **The ripple carries the press.** While one is running, the uniform half of
  the state layer is what the *other* states resolve to and the ripple carries
  what the press adds over them, so a hovered control still reads 8% outside
  the circle and 10% inside it. Material resolves one state layer, not a sum,
  and that rule survives the figure being split in two.
* **A held press costs nothing.** Once the circle has covered the control the
  run has settled, the ticker stops, and the picture holds — which is, pixel
  for pixel, the uniform press wash this package drew before there was a
  ripple.
* **One box carries one ripple**, because one box carries one pair of
  uniforms. A second press replaces the first, origin and clock together.
* **The timings are `InkRipple3dStyle`**, Flutter's own `InkRipple` figures,
  and `InkRipple3dRun` is the whole animation as arithmetic — no ticker, no
  widget, no box in it. Hand a `MutableInkController3d` a different style if
  you want a slower ripple; it is a component style like `ButtonStyle3d`, not a
  theme token.
* **A press that becomes a scroll never ripples.** The run starts on the
  *reported* press, which Flutter's tap recognizer withholds until it has won
  the arena or its deadline has passed — so there is no unconfirmed phase to
  animate, unlike Flutter's.

The claim that it stays on the repaint-only tier is a test, not a promise:
`test/ink_ripple_test.dart` presses, runs sixty frames of expansion and fade,
and asserts the build count, the layout count and `needsFlush` are all
unmoved.

Two edges to know. A press **focuses** the control by default, and since
nothing here reads Flutter's `highlightMode` to tell a pointer focus from a
keyboard one, the focus wash outlives the press; pass
`focusOnPointerDown: false` where that is wrong. And Material's 48dp minimum
target, which `InkWell3d` asks for, only delivers a press in the margin when
the target sits **outside** every box the size of the control — the panel
included. An ink well's own target is inside its `Material3d`, so it buys
nothing there; `Button3d` puts the target outside the panel and asks the ink
well for `minimumSize: Size3d.zero`. See *Pointers* in
[docs/traps.md](../../docs/traps.md), and the next section.

## The seven buttons

Every Material button is here, and they are all the same widget:

```dart
FilledButton3d(onPressed: _save, semanticLabel: 'Save',
    child: const SceneText3d('Save')),
FilledTonalButton3d(onPressed: _share, semanticLabel: 'Share',
    child: const SceneText3d('Share')),
OutlinedButton3d(onPressed: _cancel, semanticLabel: 'Cancel',
    child: const SceneText3d('Cancel')),
TextButton3d(onPressed: _more, semanticLabel: 'More',
    child: const SceneText3d('More')),
ElevatedButton3d(onPressed: _open, semanticLabel: 'Open',
    child: const SceneText3d('Open')),
IconButton3d(icon: Icons.close, onPressed: _dismiss, semanticLabel: 'Close'),
FloatingActionButton3d(onPressed: _compose, semanticLabel: 'Compose',
    child: const Icon3d(Icons.edit)),
```

**`onPressed: null` is disabled**, Flutter's spelling, and the only one — there
is no second `enabled` flag to disagree with it.

A worked example, in the order a caller writes it. It compiles —
`test/doc_examples_compile_test.dart` holds it verbatim — and it is the same
shape of tree the package's own tests pump.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeMaterial3d();          // nothing draws without this
  runApp(const ButtonDemo());
}

class ButtonDemo extends StatefulWidget {
  const ButtonDemo({super.key, required this.parent});

  /// The scene node the surface hangs its plane under.
  final Node parent;

  @override
  State<ButtonDemo> createState() => _ButtonDemoState();
}

class _ButtonDemoState extends State<ButtonDemo> {
  var _saved = false;

  @override
  Widget build(BuildContext context) => SceneLayout3d(
    parent: widget.parent,
    size: const Size3d(4, 3, 0.5),
    child: SceneTheme3d(
      data: Theme3dData.light,
      textRendererFactory: AtlasText3dRenderer.new,
      child: SceneCenter3d(
        child: SceneRow3d(
          mainAxisSize: MainAxisSize3d.min,
          spacing: 0.16,
          children: <Widget>[
            FilledButton3d(
              onPressed: () => setState(() => _saved = true),
              semanticLabel: 'Save',
              child: const SceneText3d('Save'),
            ),
            // Disabled once it has been saved. There is no opacity anywhere
            // in this stack, so it is drawn in different colours instead:
            // `onSurface` at 38%, and a container that stays transparent.
            TextButton3d(
              onPressed: _saved ? null : () {},
              semanticLabel: 'Discard',
              child: const SceneText3d('Discard'),
            ),
          ],
        ),
      ),
    ),
  );
}
```

The `spacing` is in **world units**, not logical pixels, and that is the unit
contract rather than an oversight: `SceneRow3d` belongs to the layout package,
where every extent is a world unit. Convert a specification figure with
`Layout3dMetricsScope.of(context).dp(16)` — the buttons' own figures are dp
because a `ButtonStyle3d` is a token set and `Button3d` converts them.

### One widget, seven token sets

`ButtonStyle3d` is the whole of the difference between the variants: the
container and content colours, the elevation at rest and under a pointer, the
outline, the shape, the thickness, the padding, the minimum size, the type
token and the icon size. `ButtonStyle3d.of(theme, variant)` is the table, and
`Button3d` is the widget every named button delegates to. It is public for the
reason Flutter's `ButtonStyle` is — a catalogue whose buttons cannot be
restyled is a demonstration — so restyling is a `copyWith`:

```dart
FilledButton3d(
  style: ButtonStyle3d.of(Theme3d.of(context), ButtonVariant3d.filled)
      .copyWith(shape: theme.shape.small),
  onPressed: _save,
  child: const SceneText3d('Save'),
)
```

There is no `WidgetStateProperty` here and there does not need to be. Only
four things vary with a state — the container colour, the content colour, the
elevation and the outline — and each varies in exactly one way, so they are
named out loud (`disabledContainer`, `disabledContent`, `hoveredElevation`,
`focusedOutline`) and `resolve(states, enabled:)` is the whole table in one
readable method.

The figures are checked against Flutter rather than against a second
transcription: `test/button_defaults_test.dart` pumps real Flutter buttons and
compares against `ButtonStyleButton.defaultStyleOf(context)`, so the suite is
a drift alarm. The floating action button is the exception and says so — its
defaults are a private class with no public accessor, so that test reads the
`Material` a real FAB renders instead.

### The 48dp target, and where it has to sit

A Material button is 40dp tall and answers a finger over 48dp. Those are not
in conflict: the extra reach is in the **hit test** rather than in the extent,
so a row of buttons stays 40dp tall and nothing moves apart to make room.

The rule that makes it work is the one to remember. A `TapTarget3d` reaches
past its own extent and **every ancestor gates a ray on its own extent**, so
anything wrapped around the target at the button's own size rejects a press in
the margin before the target ever sees it. `Button3d` therefore puts the
target outermost — outside the panel *and* outside the semantics box — and
asks the ink well inside for `minimumSize: Size3d.zero`, so there is one
target rather than two nested ones disagreeing about where the control is.

### What a state costs

A hover, a focus and a press write the wash through the ink controller and
rebuild nothing. Two of them also move a **token**: a hover raises a filled or
elevated button, and the focus moves an outlined button's border to `primary`.
Those cannot go through the wash channel, so the button rebuilds — but only
when the resolved style actually changed, which it checks by comparing the
resolved value rather than the state set. A text button's hover rebuilds
nothing at all, and a filled button's rebuilds and still lays nothing out,
because an elevation is a shader uniform on a box that is already the right
size.

### Announcing itself

Every button publishes `button: true`, its enabled state and its `onTap`
through `Semantics3d`. **State the `semanticLabel`.** `Semantics3d` publishes
what it is given and does not gather a label from the labels below it the way
Flutter's `Semantics(container: true)` merge does — there is no semantics tree
under a scene node to fold up — so a button without one announces itself as a
button with no name.

**The `textDirection` beside it is not optional, and you do not have to supply
it.** `SemanticsData` asserts that a non-empty label carries a reading
direction, and the assert fires inside `PipelineOwner.flushSemantics` — which a
headless `flutter test` never runs and a screen reader runs on every frame. So
every component here resolves null to the enclosing `Directionality`, exactly
as Flutter's own `Semantics` widget does, and falls back to `ltr` when a
surface is mounted with nothing above it to ask. Pass `textDirection`
explicitly only when a particular string reads the other way. A `Semantics3d`
you write **yourself**, in the imperative layer, has no `BuildContext` and must
state its own.

## Surfaces and rows: cards, tiles, dividers and chips

Everything above is a control. This is what a screen is made of.

```dart
ElevatedCard3d(
  onTap: _open,
  semanticLabel: 'Yesterday',
  child: SceneColumn3d(
    mainAxisSize: MainAxisSize3d.min,
    children: <Widget>[
      ListTile3d.text(
        title: 'Inbox',
        subtitle: '12 unread',
        leading: const Icon3d(Icons.inbox),
        onTap: _openInbox,
      ),
      const Divider3d(),
      ListTile3d.text(title: 'Archive', leading: const Icon3d(Icons.archive)),
    ],
  ),
)
```

`Card3d` comes in Material's three kinds — `ElevatedCard3d`, `FilledCard3d`,
`OutlinedCard3d` — and they are one widget with three `CardStyle3d` token
sets, exactly as the buttons are. A card is `thickness.raised`, 4dp, with its
rim bevelled in proportion; an elevated one rests 1dp toward the viewer on top
of that. Nothing casts a shadow and nothing can, so a raised card reads as
raised through parallax and occlusion.

**A card's whole interaction is free.** Material 3 gives a card no disabled
appearance, no hovered container and no focused outline, so every state goes
through the ink controller — one shader uniform, no rebuild, no layout. A
filled button cannot say that, because its elevation moves with a hover.

### A card inside a scrolling list keeps its depth

This is the one place the clip contract's design shows. `Clip3dRegion.rect` is
**four** planes — two in `x`, two in `y`, none in `z` — so a scrolling window
cuts its rows at its own edges and says nothing about how far forward they
reach. A raised card inside one is cut where it slides out of the window and
stands proud of the list everywhere else, which is what a card in a scroll
view should do and is not what a naive box clip would give you.
`examples/render_probe`'s `card_in_clipped_list` is the picture of it.

`ClipBox3d(clipDepth: true)` bounds the thickness as well — and it still will
not slice a raised card off flush with the list, because the planes are in the
box's own frame and an elevation moves the slab's *node*, outside that frame.
A depth clip cuts a box's layout depth, never its lift.

### The tile, the heights, and the density

`ListTile3d` is a leading slot, one or two lines of text, and a trailing slot,
at Material's published heights: **56dp** for a title alone, **72dp** with a
subtitle, **88dp** for `isThreeLine`, and 48/64/76 when `dense`. They are
minimums — a tile whose text wraps is taller — and they go through
`Theme3dData.effectiveConstraints`, so `VisualDensity3d` moves them by 4dp a
step. The theme's density is the authority, not the metrics'; see *What a
theme deliberately does not do* below.

The figures are checked against Flutter rather than transcribed: the tests
pump a real `ListTile` and read the height it lays out at.

**It takes its title as a string, and that is the interesting part.** A
`Semantics3d` publishes what it is given and gathers nothing, so a component
states its own label — which is a formality for a button and a real question
for a row with a title *and* a subtitle. `ListTile3d.text(title:, subtitle:)`
builds the labels **and** the announcement, `'Inbox, 12 unread'`, which is
what Flutter's semantics merge would have produced. The general constructor
takes widgets and a `semanticLabel`, and a tile written that way with no label
announces a row with no name.

### A 1dp line, and why it has a thickness

A `Divider3d` has three figures that all sound like "thickness" and are three
different things:

- **`space`** — how much room it takes in the column: 16dp, Material's figure.
- **`thickness`** — how tall the rule is *in the plane*: 1dp. Flutter's
  spelling, so a caller migrating a `Divider` writes what they already know.
- **`depth`** — how deep the slab is: `Thickness3d.thin`, also 1dp, and a
  different dial that happens to carry the same number.

The depth is the one worth explaining. A rule looks flat, so zero depth is the
tempting answer — and it z-fights. `Material3d` aligns its child to its
**front face**, so a divider drawn on a card sits exactly on the card's front
plane; two coplanar surfaces appear in patches, differently on every frame and
every driver, with nothing to say why. A real slab stands its own
half-thickness proud instead.

The other thing a 1dp line teaches is about *seeing* it. At the default
hundred logical pixels to the unit a rule is 0.01 world units and a couple of
pixels on screen — too thin for a render probe to aim at. The fix is not to
fatten the token, it is to turn the surface's `unitsPerLogicalPixel` up, which
is the dial a camera-bound surface turns anyway.

**A divider announces nothing**, deliberately, exactly as Flutter's does: a
reader that said "divider" between every pair of rows would be worse than one
that skipped it. Pass a `semanticLabel` for a rule that really is a named
section break.

### Chips, and where the 48dp target earns its keep

`AssistChip3d`, `FilterChip3d`, `InputChip3d` and `SuggestionChip3d` are one
`Chip3d` over four `ChipStyle3d` token sets:

```dart
FilterChip3d(
  label: const SceneText3d('Unread'),
  selected: _unreadOnly,
  onSelected: (value) => setState(() => _unreadOnly = value),
  semanticLabel: 'Unread only',
)
```

A chip is **32dp tall** — the smallest control in the catalogue and sixteen
short of Material's minimum touch target — which is where the `TapTarget3d`
reach stops being a formality and starts doing real work. A chip answers a
finger 8dp above and below itself while a row of chips stays 32dp tall and
nothing moves apart to make room.

Selection is a **token substitution**, not a wash: a selected chip is a filled
`secondaryContainer` with no outline, an unselected one transparent inside an
`outlineVariant`. That is why `Material3dState` has no `selected`, and it means
toggling a chip rebuilds it while hovering one does not. An assist chip is not
selectable at all, and the *token table* says so rather than the widget, so the
two cannot disagree.

`onDeleted` puts a delete affordance in the trailing slot. It is a plain
gesture with its own semantics rather than a nested `InkWell3d`, and the
reason is a rule worth knowing before you try to improve it: a second
`TapTarget3d` inside the chip's panel would be gated by the panel — a target
reaches past its own extent, its ancestors do not — so its reach would be
silently inert; and an ink well there would find the *enclosing* surface's ink
controller and light the whole chip up. What works is the innermost recognizer
winning the arena, which it does, exactly as in Flutter.

## Structure: a screen, its bars, and the depths between them

`Scaffold3d` is the screen. It owns three things and merely positions
everything else: the backing every screen has, the arrangement — a
`CustomMultiChildLayout3d`, exactly as Flutter's `Scaffold` is one, with the
body given whatever the bars left over — and the **depths**.

```dart
Scaffold3d(
  appBar: AppBar3d.text(title: 'Inbox'),
  body: SceneListView3d(children: rows),
  bottomNavigationBar: NavigationBar3d(
    selectedIndex: _index,
    destinations: const <NavigationDestination3d>[
      NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
      NavigationDestination3d(icon: Icon3d(Icons.send), label: 'Sent'),
    ],
    onDestinationSelected: (index) => setState(() => _index = index),
  ),
  floatingActionButton: FloatingActionButton3d(
    onPressed: _compose,
    semanticLabel: 'Compose',
    child: const Icon3d(Icons.edit),
  ),
)
```

**It does not bind a surface, and that is a decision rather than an
omission.** A `Layout3dCameraBinding` is what makes a surface cover the view,
and a scaffold that did that for you could only ever *be* the view — where
half the reason this stack exists is that a Material screen here can be a
panel on a wall in a room. So a scaffold is a box like any other, and an
application that wants a full-view screen says so once, where it mounts the
surface:

```dart
SceneLayout3d(
  camera: camera,
  binding: const Layout3dCameraBinding.screenFilling(distance: 2),
  child: SceneTheme3d(
    data: Theme3dData.light,
    textRendererFactory: AtlasText3dRenderer.new,
    child: Scaffold3d(appBar: bar, body: body),
  ),
)
```

### The depths are the part with no Flutter equivalent

An app bar sits over content that scrolls under it and a navigation bar sits
over the same content at the other end. In two dimensions that is paint order
and it costs nothing. Here every slot is a **slab** — the bars are
`Thickness3d.structural`, 8dp — and two slabs are separated only where the
step between them exceeds the *mean* of their thicknesses. An 8dp bar over a
4dp card needs more than 6dp, and a bar no nearer the viewer than the rows
beneath it loses the depth test to them somewhere, in patches, differently on
every frame and every driver.

So the scaffold does not leave that to the components. Each slot sits one
`depthStep` in front of the one behind it, in the order `Scaffold3dSlot`
declares — body, bottom bar, app bar, floating action button — and it asserts
that the step it was given actually separates a bar from a card. The default
is the theme's own `thickness.depthStep`, 12dp, which clears the 6dp minimum
with half again to spare. `Scaffold3d.liftFor` is that arrangement as
arithmetic, so anything mounted over a screen can state its own lift against
it rather than guessing.

The body is inside a `SceneClipBox3d`, and it has to be: a list is taller than
the room it was given, and without a window its rows draw over the bars rather
than ending at them. The window clips the **face and not the depth**, so a
raised card in the body still stands proud of the screen.

**Where that lift is written matters more than the figure.** It goes on the
node tier — each slot is *positioned* at z zero and its geometry is moved
forward by a `NodeShift3d` — and not into the position the arrangement gives
the slot, which is what it used to be. Toward the viewer is negative z, so a
slot lifted by its position sits outside its parent's own extent, and
`Layout3d.hitTest` clamps the ray to the stretch inside each box before it asks
that box's children. A screen lifted that way drew perfectly and **could not be
pressed anywhere**: the scaffold's own backing answered every hit. The node
tier draws identically and keeps the boxes where layout put them, which is what
a ray looks for. `Stack3d.depthStep` has always separated its children that
way, for the same reason, and `ParentData3d.sceneOffset` says so in as many
words.

The backing is a **sibling** of the arrangement rather than its parent, for the
other half of the same story: a `Material3d`'s thickness is a *tight* depth
constraint on everything below it, and a screen backed by a `thickness.thin`
slab used to hand every slot a 1dp depth budget — an 8dp app bar came out 1dp,
its title ended up coplanar with the bar it was drawn on, and it vanished.

One consequence worth planning around: four steps of 12dp is 48dp of parallax
between a screen's backing and its floating action button, and on a 340dp phone
that is a seventh of the width. Seen off-axis the bars stand visibly proud; on
the ground plane those 48dp are 48dp of *height*. The number is a depth-buffer
figure rather than a visual one, and a screen that cares says so:
`Scaffold3d(depthStep: 8)` still clears the 6dp a bar over a card needs.

### The bars

`AppBar3d` is the fixed one. `SliverAppBar3d` is the one content scrolls
under, and it is a sliver — so it goes in the body's own scroll view, never in
the `appBar` slot:

```dart
SceneCustomScrollView3d(
  controller: _scroll,
  slivers: <Widget>[
    SliverAppBar3d.text(title: 'Inbox', pinned: true),
    SceneSliverList3d(children: rows),
  ],
)
```

Four variants, differing only in how tall they are expanded and what type role
the title takes there: `small` and `centerAligned` at 64dp, `medium` at 112 and
`large` at 152, all collapsing to the same 64dp toolbar. Everything else is
`AppBarStyle3d`.

**Two mechanisms keep a row out of a sliver bar, and neither is enough alone.**
The bar's geometry is pulled toward the viewer by `lift`, so content passes
behind it; and `CustomScrollView3d` publishes a clip plane at the bar's
trailing edge, which is what cuts a row *in half* there. `SliverAppBar3d`
defaults the lift to the theme's `thickness.depthStep` rather than to
`SliverPersistentHeader3d`'s one logical pixel, for the arithmetic above: one
pixel separates two decals, not two slabs.

That clip is the claim this package's plans had made twice and nobody had
photographed. When phase 5 finally did, it was **not happening** — a viewport
works out what a pinned header is sitting on after its rows have been laid out,
so every row published an unbounded clip block while `Layout3d.clipRegion` went
on answering correctly to anything that asked afterwards. It is fixed in the
layout package under
[its own plan](../flutter_scene_layout3d/plans/2026_09_08_the_declarative_side_of_a_pinned_bar.md),
and `examples/render_probe`'s `sliver_app_bar_clip` scene is the picture.

Two things Flutter's `SliverAppBar` does that this one deliberately does not.
The title does not grow from `titleLarge` to `headlineSmall` partway through a
collapse, and the bar does not raise itself to `scrolledUnderElevation` when
content goes beneath it. Both are rebuilds, a collapse happens inside a layout
pass, and a bar that rebuilt every frame of a scroll would be putting text
measurement back on the relayout path. The collapse that *does* happen is
expressed through the constraints the header hands its child: the surface
fills what it is offered and the toolbar stays at the bottom.

### Navigation, and the pill

`NavigationBar3d` and `NavigationRail3d` are the same component with its axes
turned, over one `NavigationStyle3d` in two variants — 80dp either way, a bar
raised to level 2 on `surfaceContainer` and a rail flat on `surface`.

A destination takes its label as a **`String`**, not a widget, and that is the
phase-4 rule applied rather than a shortcut: a `Semantics3d` gathers nothing
from below, so a destination that took a widget would have to be told its own
name twice. One string builds the visible label and the announcement, and they
cannot disagree.

Material's selection indicator — the pill behind the selected icon — needed no
new machinery. A stadium is a rounded rectangle whose radius clears half its
shorter side, which `ShapeScale3d.full` already is, so the indicator is one
more `Material3d`: 64 by 32 in a bar, 56 by 32 in a rail,
`secondaryContainer`, `shape.full`. What it *did* need is a depth step, because
a glyph drawn exactly on the pill's front face is coplanar with it and
z-fights.

Every destination is its own `Material3d` too, transparent, one thickness step
proud of the bar. An `InkWell3d` finds the **enclosing** surface, so a well
placed straight inside the bar would light the whole bar up under one finger.

A rail wants a rule beside it, and that is why `VerticalDivider3d` exists at
all — the horizontal one is what a list needs, and until there was a rail
nothing had two things to separate:

```dart
SceneRow3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    NavigationRail3d(selectedIndex: _index, destinations: destinations),
    const VerticalDivider3d(),
    SceneExpanded3d(child: body),
  ],
)
```

## The overlays: dialogs, menus, snack bars, tooltips and sheets

Everything that goes *in front* of a screen goes through `Overlay3d`, which
belongs to the surface rather than to the `Scaffold3d` — so a dialog can outlive
the screen that opened it and a barrier can cover the whole panel. What an
application has to do is put one there, and hang a messenger inside it:

```dart
SceneLayout3d(
  camera: camera,
  binding: const Layout3dCameraBinding.screenFilling(distance: 2),
  child: SceneTheme3d(
    data: Theme3dData.light,
    textRendererFactory: AtlasText3dRenderer.new,
    child: SceneOverlay3d(
      camera: camera,
      child: ScaffoldMessenger3d(
        child: Scaffold3d(appBar: bar, body: body),
      ),
    ),
  ),
)
```

The order matters and it is Flutter's own: the overlay outside, the messenger
inside it, the screen inside that. The theme is outermost of the three, because
an overlay's content is built inside the overlay and has to be able to read it.

A dialog is then a call that returns a future:

```dart
Future<void> _confirmDelete(BuildContext context) async {
  final deleted = await showDialog3d<bool>(
    context: context,
    builder: (context) => Dialog3d(
      semanticLabel: 'Delete this file?',
      child: SceneColumn3d(
        mainAxisSize: MainAxisSize3d.min,
        crossAxisAlignment: CrossAxisAlignment3d.start,
        spacing: Layout3dMetricsScope.of(context).dp(24),
        children: <Widget>[
          const SceneText3d('Delete this file?'),
          SceneRow3d(
            mainAxisAlignment: MainAxisAlignment3d.end,
            spacing: Layout3dMetricsScope.of(context).dp(8),
            children: <Widget>[
              TextButton3d(
                semanticLabel: 'Cancel',
                onPressed: () =>
                    Navigator3d.of(SceneOverlay3d.of(context))?.pop(false),
                child: const SceneText3d('Cancel'),
              ),
              FilledButton3d(
                semanticLabel: 'Delete',
                onPressed: () =>
                    Navigator3d.of(SceneOverlay3d.of(context))?.pop(true),
                child: const SceneText3d('Delete'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (deleted ?? false) {
    ScaffoldMessenger3d.of(context).show(
      const SnackBar3d(message: 'File deleted'),
    );
  }
}
```

`showModalBottomSheet3d` and `showBottomSheet3d` are the same shape for a
sheet — the first over a scrim and returning a value, the second part of the
screen and blocking nothing. `PopupMenuButton3d` opens a menu at a button and
`Tooltip3d` wraps any control at all:

```dart
Tooltip3d(
  message: 'More actions',
  child: PopupMenuButton3d<String>(
    semanticLabel: 'More actions',
    itemBuilder: (context) => const <MenuItem3dEntry<String>>[
      MenuItem3dEntry(value: 'rename', label: 'Rename'),
      MenuItem3dEntry(value: 'delete', label: 'Delete'),
    ],
    onSelected: _act,
    child: const Icon3d(Icons.more_vert),
  ),
)
```

### The content arrives one frame after the call

`showDialog3d` returns immediately and the dialog — barrier, scrim and all — is
in the tree on the **next** frame. Flutter's own `showDialog` behaves the same
way: inserting an overlay entry marks the overlay for a rebuild rather than
editing the tree in place. A test pumps once after opening. What is *not*
deferred is the route: the future exists from the call, and popping it works
whether or not a frame has run.

### A scrim is a slab, and a dialog has to clear a whole screen

Material's scrim is black at 32% over the content. Here it is geometry — a
`thickness.thin` slab in front of the screen and behind the dialog — and every
depth rule applies to it. The 32% is real: the panel shader blends, so a
translucent colour is a translucent slab. What a scrim must not be is
zero-depth, which would make it coplanar with whatever it covers, and what must
not sit on its plane is the dialog, which needs a real `thickness.depthStep`
between them.

The lift is the other half. A `Scaffold3d` has already spent four depth steps
on its own slots by the time anything is put in front of it, and the frontmost
of them is a slab in its own right, so `Overlay3d.defaultLift` — eight logical
pixels, a depth-buffer separation between two things with no thickness — is
about a seventh of what is needed. Every overlay here takes its lift from
`Scaffold3d.overlayLift(theme.thickness.depthStep)`, which is one step in front
of `Scaffold3dSlot.values.last`. That is 60dp at the baseline scale, and it is
arithmetic rather than a figure: adding a slot to the scaffold moves the
overlays with it.

### A menu is anchored, and it follows

An overlay entry is placed by the overlay's own alignment, which is in the
middle of the panel and nowhere near the button that asked for a menu. There is
no `CompositedTransformTarget` here; there is `Layout3d.anchorOffsetTo`, which
this package drives through `Anchor3d` (around the trigger) and `Follower3d`
(around the menu). It answers a `nodeOffset`, so anchoring is the node tier:
one matrix, no relayout, and re-anchoring every frame costs nothing.

It **follows** rather than closing. Three hooks, because the ways a button can
move are not one kind of event: the follower re-anchors when it is placed, when
the anchor is placed, and from a post-frame callback while the menu is open —
the last of which is the case that actually catches a scroll, since a scrolling
ancestor is placed and the boxes below it are not. A post-frame callback
schedules no frame of its own, so a menu over a still screen costs nothing at
all. The menu does close when its button leaves the tree, because an anchor
that no longer exists cannot be followed.

What it does not do is reflow to stay inside the panel. Flutter shifts a menu
against the screen edges; what that should mean for a surface hanging at an
angle in a room is a real design question rather than an oversight.

### The messenger queues, and waiting costs nothing

`ScaffoldMessenger3d` is Flutter's, in the shape a catalogue over `Overlay3d`
can have it: one bar at a time, a duration per bar, and a future per bar
carrying **why** it went away.

```dart
final shown = ScaffoldMessenger3d.of(context).show(
  SnackBar3d(message: 'Deleted', actionLabel: 'Undo', onAction: _undo),
);
if (await shown.closed == SnackBar3dClosedReason.timeout) _commit();
```

A second `show` while one is up queues rather than replacing, and a queued bar
closed before its turn is dropped without ever being shown — its future
completes all the same, as does every bar still waiting when the messenger
leaves the tree. Nothing animates: `Route3dTransition.none` is what the layout
package ships and this package has no motion tokens yet, so a bar appears,
waits and goes. The waiting is one `Timer` and it touches no layout at all.

`Tooltip3d` keeps the same promise where it matters most, because a hover is a
per-pointer path: a pointer entering starts a `Timer` and a pointer leaving
cancels it, and neither calls `setState`, marks anything dirty, or rebuilds the
control underneath. Only the timer firing does anything. Its label absorbs no
ray either — a tooltip that took the pointer would dismiss itself the instant
it appeared.

### A sheet is structure, and it has an edge

`BottomSheet3d` is `thickness.structural`, 8dp, like an app bar and unlike a
card: a sheet is a piece of the screen that has slid into view rather than an
object resting on it, and the depth scale is the only place that distinction
can be stated rather than implied. `Sheet3dEdge` makes Material's side sheet
the same class on another edge — the corners away from the edge are the rounded
ones — which is the call `Divider3d` and `VerticalDivider3d` deliberately did
not make, because a divider's indent runs along its own axis and the two need
different vocabulary.

## The selection controls: a box, a ring, a thumb and a track

`Checkbox3d`, `Radio3d`, `Switch3d` and `Slider3d`, over `CheckboxStyle3d`,
`RadioStyle3d`, `SwitchStyle3d` and `SliderStyle3d`. The first three are shape
and state; the fourth is the first thing in this catalogue that is **dragged**.

```dart
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  bool _notify = true;
  bool _wifi = false;
  String _delivery = 'standard';
  double _volume = 0.4;

  @override
  Widget build(BuildContext context) => SceneColumn3d(
    crossAxisAlignment: CrossAxisAlignment3d.start,
    children: <Widget>[
      Checkbox3d(
        value: _notify,
        onChanged: (value) => setState(() => _notify = value),
        semanticLabel: 'Notify me',
      ),
      Switch3d(
        value: _wifi,
        onChanged: (value) => setState(() => _wifi = value),
        semanticLabel: 'Wi-Fi',
      ),
      Radio3d<String>(
        value: 'standard',
        groupValue: _delivery,
        onChanged: (value) => setState(() => _delivery = value ?? _delivery),
        semanticLabel: 'Standard delivery',
      ),
      Slider3d(
        value: _volume,
        onChanged: (value) => setState(() => _volume = value),
        semanticLabel: 'Volume',
      ),
    ],
  );
}
```

Each one **states its own name**, for the reason every component here does: a
`Semantics3d` publishes what it is given and gathers nothing from the label
beside it. What it does not need to be told is the state — a checkbox and a
radio publish `checked`, a switch publishes `toggled`, and a slider publishes
`slider` with a formatted `value`. Flutter draws that distinction and it is
worth keeping: a reader says "ticked" for one and "on" for the other.

### Three rectangles for one control, and why they are three

A checkbox is **18dp of ink inside a 40dp wash inside a 48dp touch target**.
That is Material's own arrangement, and here it has to be three separate boxes
rather than one padded one, because a `TapTarget3d` reaches past its own extent
and its parent does not. So the reach sits outside the wash, the wash is the
control's own extent, and the ink is a slab on top of it.

The consequence is the one this catalogue keeps meeting, at its sharpest here:
a row of checkboxes is **40dp tall** and answers a finger over 48dp, so there
are four logical pixels of margin on every side that no box in the layout knows
about — and at a corner, four pixels is all a press has. `test/selection_test
.dart` presses exactly there.

### The mark is the signal, and an 18dp glyph had to be checked

Phase 4 declined to draw a checkmark on a selected filter chip: the container
substitution already said "selected" and a glyph would have been a second voice
saying the same thing. A checkbox runs the other way. Its substitution is an
18dp square turning `primary`, which without a mark is a filled swatch — so the
mark carries the whole signal, and Material draws one.

It is one glyph of the icon font, like every `Icon3d`, and at 18dp it is the
smallest thing this package has asked the label atlas for.
`examples/render_probe`'s `checkbox_mark` scene settled that it draws, beside
an identical box whose glyph has no renderer — the same pairing `icon_glyph`
used, at the size a real control uses. What it turned up is worth knowing
before you tune a glyph size: **the atlas's rasterization scale does not depend
on the glyph's size, or on the surface's unit rate.** It is
`AtlasText3dRenderer.resolution` and nothing else, because the two metrics
factors in `unitsPerLogicalPixel * logicalPixelsPerUnit` cancel. An 18dp mark
and a 220dp heart are rasterized at the same texels-per-logical-pixel, and
`glyphAtlasScaleFor` rounds **up**, so a bucket is never coarser than asked
for. Small type here is not a resolution problem.

### The thumb slides on the node tier, and stands proud of its track

`docs/traps.md` lists three tiers of change — repaint only, node only, and a
real relayout — and a thumb moving along a track is squarely the second. So the
slide is a `nodeOffset` and the slider's *fill* is a `nodeTransform`, both
written by `SceneNodeShift3d`, and neither calls `markNeedsLayout`. Layout
centres the thumb on the track; the shift carries it half the travel either
way.

The fill is the part worth pausing on. The obvious way to fill a track is to
give a box a width and change it, which is a relayout on every frame of a drag.
A node transform pivots on the box's **origin corner**, so the active track is
the *whole* track scaled by the value: its left end stays exactly where layout
put it and its right end stops at the thumb, and no box changes size at all.
`test/slider_test.dart` drags across twenty frames and asserts `needsFlush` is
false after every one.

Two things follow that will otherwise cost you time. **`worldTransform` undoes
both channels**, deliberately, so hit testing keeps finding a box where layout
put it — which means `screenCenter` on a thumb reports the middle of the track
whichever way the switch is set. A picture of one has to take its oracle from
the track, exactly as phase 6's anchored menu takes its from the button. And a
thumb resting on the track's front face would be **coplanar** with it and
z-fight; every one of these controls stands its ink one `Thickness3d.stepOver`
clear of what it is drawn on.

### The slider is the drag lane's first customer outside a list

A slider inside a scrolling list has to take a sideways drag while the list
keeps a vertical one, and the only thing that can arbitrate that is the gesture
arena. Two of Flutter's four recognizers do not fire in this build, which is
why `PointerSequence3d.addArenaMember` exists — the drag plan named "a knob, a
slider, a rotation handle" as its customers, and this is the first of them.

`SliderGesture3d` is that member, and it is exported on its own because it is
the reusable half: it enters the arena on the press so a view underneath waits
for the touch slop rather than scrolling out from under the gesture, claims the
pointer when the finger crosses the slop along the slider's own axis, and gives
it up quietly when the list claims first. A press that never moves is a **tap**,
and it claims at the up — which is legal because what ends an arena is the
sweep, not the close.

`Slider3d` takes an explicit `width` in logical pixels, defaulting to
Material's narrowest 144dp, where Flutter's fills whatever room it is given.
That is a real difference and it is the price of the node tier: the thumb's
position is written by the widget that builds it, so the width has to be known
before layout rather than after it.

### What the tables say

Every figure is `ColorScheme3d` roles and Material's own dp, and
`test/selection_defaults_test.dart` is the drift alarm. Five of them are read
straight out of Flutter — `Checkbox.width`, `kRadialReactionRadius`,
`kMinInteractiveDimension`, `RoundSliderThumbShape.enabledThumbRadius` and
`RoundSliderOverlayShape.overlayRadius` are all public — two are measured off a
real Flutter control with `tester.getSize`, and the rest are transcriptions
that say so in the test.

Two deliberate departures. A switch's thumb is **one size**, Material's
selected 24dp, where Material grows it from 16dp as it crosses: that growth is
an animation and this package has no motion tokens, and a thumb that jumped
between two sizes would put a size change on the interaction path where every
other state here is a colour. And the slider is Material's **round-thumb** one
(a 4dp track and a 20dp thumb) rather than the 2024 bar-handle one, because a
thumb standing proud of a track is what this catalogue's third dimension is
for, while a handle inset into a track of its own height is a picture a 3D
scene has nothing to add to.

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

That is a filled button written out by hand, which is what `FilledButton3d`
now is with a token set in front of it — the section above shows the named
form. Every figure in it is in logical pixels: `Material3d` converts the padding and
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

`ButtonStyle3d.resolve` is where the rule is implemented for the buttons —
disabled wins every other state, the elevation goes to zero, and the outline
dims to the container figure rather than the label one — and
`examples/render_probe`'s `button_disabled` scene is where it is checked as a
picture rather than as arithmetic: two filled buttons on one near-white slab,
the disabled one measurably closer to the surface behind it than the enabled
one is.

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

The press ripple has landed; what it deliberately does not do is overlap two
splashes the way Material does, or escape its own container. Both are the same
limit seen twice: the ripple is two uniforms on the panel's own shader, so
there is one of it and it is bounded by the slab the shader draws.

Three things the surfaces and rows left, each for a reason. A filter chip draws
no **checkmark**: it is a second glyph competing with the container
substitution for the same signal, and the container is the one that survives at
a distance — pass an `avatar` if you want one. A tile has one **title
alignment**, the centred one, where Flutter has four. And a card has no
**`clipBehavior`**: that needs a clip whose region is a rounded rectangle, and
`Clip3dRegion` is an intersection of planes, which is convex — the panel shader
carves its own radius, but a *child* overflowing a rounded card is not clipped
to it.

Four the structure left. A scaffold has no **drawer** and no `endDrawer` —
which is now a smaller gap than it was, since `showModalBottomSheet3d` on
`Sheet3dEdge.left` is most of one. There is
no **`FloatingActionButtonLocation`** — the button sits at the trailing bottom
corner, above the navigation bar, and a screen wanting it elsewhere positions
its own. A `SliverAppBar3d` has no **`flexibleSpace`** and no `bottom`, so a
tab bar under a title is not expressible yet. And a navigation bar has one
**label behaviour**, always-show, where Flutter has three: the other two hide
labels on unselected destinations, which changes a destination's height as the
selection moves and so relayouts the bar on every tap.

Two smaller gaps the buttons left. There is no `FilledButton3d.icon` pairing
an icon with a label, because Material's icon-and-label padding is a third set
of figures and a `SceneRow3d` inside a button wants its cross-axis constraints
stated; put a row in the `child` in the meantime. And there is no `IconTheme`
to carry an icon size down a subtree — `Material3d` carries the content
*colour* through a `DefaultTextStyle`, so an icon is the right colour without
being told, and `IconButton3d` and `FloatingActionButton3d` state their own
24dp size.

Six the overlays left, each with a reason in the plan's *What phase 6
deliberately left out*: there is no **`AlertDialog3d`** (a column and a row
inside a `Dialog3d`, and nothing about that arrangement is three-dimensional);
a menu does not **reflow** to stay inside the panel; a tooltip has no
**long-press** trigger, because the innermost recognizer wins the arena and a
tooltip around a button would take the button's own long press; a snack bar has
no **swipe to dismiss** and no second line; a sheet has no **drag handle** and
cannot be dragged to a height, and `showBottomSheet3d` does not shorten the
screen the way Flutter's `Scaffold.showBottomSheet` does — an overlay is not a
scaffold slot, by design. And **nothing animates**: `Navigator3d.transition` is
the seam, one hook away, whenever the motion tokens land.

Five the selection controls left. A checkbox has no **tristate**: Material's
third value is an `Icons.remove` in place of the tick and a `mixed` semantic
flag, and neither is hard — it is simply not what phase 7 was for. There is no
**`RadioGroup3d`**, so `Radio3d` keeps the `value` / `groupValue` / `onChanged`
spelling that Flutter deprecated after 3.32 in favour of a group ancestor; that
migration is an inherited widget plus a registry, and it belongs beside a
`FormField3d` rather than inside a leaf control. A slider has no **tick marks**
for its divisions and no **value indicator** above the thumb, both of which are
ornament on the component whose design question here was the drag. A switch has
no **growing thumb** and nothing else animates either, for the reason the whole
catalogue does not. And a slider takes an explicit **width** rather than
filling its parent, because the thumb's position is written before layout
rather than after it.

Text input is not planned at all: there is no `EditableText3d`, no selection,
no cursor and no keyboard plumbing anywhere in the stack, so a `TextField3d`
is a project of its own rather than a component.

The plan is
[`plans/2026_09_01_flutter_scene_material3d.md`](plans/2026_09_01_flutter_scene_material3d.md),
and it is kept up to date with what turned out to be wrong.
