---
status: completed
created_at: 2026-09-01T19:45:00Z
updated_at: 2026-09-01T21:40:00Z
commit: 603851d211137a6b42ad4ca71c9acc80f9938639
---

# The four things a first component cannot do without

This plan owns phase 0 of
[the Material catalogue plan](../../flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md).
That plan's own *seams* section says why this file exists: every plan in this
package is `completed`, and four new public classes must not be smuggled into
`flutter_scene_layout3d` under another package's plan number.

All four land here, in `flutter_scene_layout3d`. None of them is deep. Three
are seams the widget layer is missing and one is a build question that has to
be answered empirically rather than argued.

1. **The declarative layer cannot draw.** `DecoratedBox3d` has existed since
   phase 1 of size-driven geometry; there is no `SceneDecoratedBox3d`, so an
   application written from `build()` can arrange boxes and cannot make one
   visible.
2. **There is no default text renderer.** `Text3d.renderer` is null by
   default, so every label in a catalogue has to be handed an
   `AtlasText3dRenderer` by hand.
3. **There is nowhere tree-wide to put a theme.** `Layout3dOwner` carries
   `basis`, `metrics`, `painters` and `focusScope` because they are state both
   layers need and the imperative one has no `BuildContext`. A theme has that
   shape, and Material vocabulary must not enter this package.
4. **Compiling the panel shader is an application's job.**
   `examples/render_probe/hook/build.dart` is the only thing in either
   repository that runs `impellerc` over `assets/box_decoration3d.fmat`, and it
   does it from the app, through a symlink into this package.

## 1. `SceneDecoratedBox3d`

The widget form of `DecoratedBox3d`, in `lib/src/widgets/layouts.dart`,
exported from `lib/widgets.dart`, written the way its neighbours are:
`createLayout` builds the box, `updateLayout` writes the two properties.

```dart
SceneDecoratedBox3d(
  decoration: const BoxDecoration3d(
    color: Color(0xFF1B6EF3),
    borderRadius: BorderRadius3d.circular(12),
    elevation: 3,
  ),
  stateLayer: hovered
      ? const StateLayer3d(color: Color(0xFFFFFFFF), opacity: 0.08)
      : StateLayer3d.none,
  child: ScenePadding3d(
    padding: const EdgeInsets3d.all(0.12),
    child: const SceneText3d('Continue'),
  ),
)
```

The point of the class is that neither property touches layout, and the widget
form has to keep that promise: a rebuild that changed only the state layer
must mark nothing dirty. `DecoratedBox3d.decoration` and `.stateLayer` are
already setters that only repaint, so `updateLayout` writing them
unconditionally is correct — but it is a promise a test states rather than a
property a reader can see, so the test is part of the item.

`lib/widgets.dart` does not export a single decoration type today, which is
why the gap was invisible: there was nothing to build a decoration out of on
that side. The decoration types join the barrel — `Decoration3d`,
`BoxDecoration3d`, `Border3d`, `BorderRadius3d`, `StateLayer3d`,
`Decoration3dElevation`, `Decoration3dPainter`, `Decoration3dPainterCache`,
`Decoration3dPaintRequest`, `BoxDecoration3dUniforms` and
`BoxDecoration3dPainter` — and so does `AtlasText3dRenderer`, which item 2
needs there. The file's own doc says that import is "usually all a declarative
app needs", and installing the painter factory is part of getting a panel on
screen.

Two dartdoc examples in `lib/src/widgets/drag.dart` (lines 24 and 217) already
write `SceneDecoratedBox3d`. They get checked against the compiler once the
class exists, not just read.

### Should `Container3d` gain a `decoration`?

**No.** Reasons, because the expectation that it should is a reasonable one:

- **Flutter's `Container` is a composition; `Container3d` is one box.**
  `Container` builds a small tree — `Padding`, `DecoratedBox`, `ConstrainedBox`
  — so its `decoration` costs nothing conceptually: `DecoratedBox` stays the
  single implementation of what a decoration is. There is no composition in
  the imperative layer here. A `Container3d` is a single `Layout3d`, and
  giving it a decoration means a second implementation of the painter
  lifecycle — acquire from the owner's cache, release on `detach` and
  `dispose`, re-acquire when the cache key changes, fold the elevation lift
  into `localTransform` — or a mixin two classes share. Either way the rule
  that a decoration is *told* a size is owned in two places instead of one.
- **`Container3d`'s decoration would not be the box's own size.** Flutter
  paints a container's decoration inside the margin and around the padding, so
  it covers neither the whole box nor the child's box. `DecoratedBox3d` hands
  its own `size` to the painter and the slab is placed at `size.center` of the
  box's node; `Decoration3dPaintRequest` has no offset field. Being faithful
  would mean widening the painter contract — a public seam every painter
  implements — for a convenience wrapper. Not being faithful would mean a
  decoration that silently swallows the margin, which is worse than not having
  one.
- **The composition is one line and says which rectangle is the panel.**
  `SceneDecoratedBox3d(decoration: d, child: SceneContainer3d(padding: p, child: c))`
  is a panel with padding; `SceneContainer3d(margin: m, child: SceneDecoratedBox3d(...))`
  is a panel with space around it. Flutter's single widget makes those two
  read the same and be different, which is a thing people get wrong there.
- **The catalogue does not need it.** The Material plan's own design says
  `Material3d` "is a `SceneDecoratedBox3d` with the theme resolved into it".

So `Container3d`'s class doc keeps the sentence it has, updated only where it
was written before this package could draw: it says a decoration is
`DecoratedBox3d`'s job, and it should now name `SceneDecoratedBox3d` for the
declarative side rather than implying nothing here draws at all.

If a future component genuinely wants a decoration inset from a box's own
extent, the seam is an offset on `Decoration3dPaintRequest`, and it should be
added for that reason and not for this one.

## 2. `DefaultTextRenderer3d`

An inherited default beside `DefaultTextStyle`, which `SceneText3d` already
merges from, with `SceneText3d.renderer` overriding it.

**The inherited value is a factory, not a renderer, and the reason is
ownership.** `Text3d.renderer`'s setter disposes the old one, and
`Text3d.dispose` disposes the current one — verified in
`lib/src/text/text3d.dart`. So an inherited *instance* shared by a screen of
labels is disposed by whichever label is taken out of the tree first, and
every other label then holds a disposed renderer. The inherited value is
`Text3dRenderer Function()` and each label calls it once for a renderer of its
own; the glyph atlas behind them is what is actually shared, through
`GlyphAtlasCache3d.shared`, and that is already the design.

```dart
DefaultTextRenderer3d(
  factory: AtlasText3dRenderer.new,
  child: SceneLayout3d(...),
)
```

The wrinkle is that `updateLayout` runs on every rebuild, and calling the
factory there would build and dispose a renderer per rebuild — the churn the
whole prepare/layout split exists to avoid. So the box has to remember which
factory made its renderer, which is a property on `Text3d`:

```dart
typedef Text3dRendererFactory = Text3dRenderer Function();

Text3dRendererFactory? get rendererFactory;   // makes the box its own
Text3dRenderer? get renderer;                 // an explicit one, still owned
```

Setting `rendererFactory` to the same function is a no-op; setting it to a
different one disposes what the old one made. Setting `renderer` takes the box
off the factory. The invariant is one live renderer per box, always owned by
the box, whichever way it arrived.

The test is the one the ownership claim asks for: two labels under one
`DefaultTextRenderer3d`, one disposed, the other still rendering — which is a
claim about disposal, so a fake `Text3dRenderer` that counts `render` and
records `dispose` is the instrument.

## 3. `Layout3dSlot<T>` on the owner

A typed slot, as the Material plan proposes:

```dart
const themeSlot = Layout3dSlot<Theme3dData>('theme');

final Theme3dData? theme = owner.slot(themeSlot);
owner.setSlot(themeSlot, Theme3dData.light());
```

The key is an identity-keyed value object carrying a debug name; the owner
holds a map from key to value. No Material in this package, no `BuildContext`
in the imperative one. A box reads it with `Layout3d.slot(key)`, which returns
null while detached, the way `metrics` falls back to the standard value.

Two things a consumer hits immediately, and both are part of this item.

**Writing a slot has to be able to relayout.** A theme decides paddings and
type sizes, so changing one changes sizes, and nothing else would tell the
tree. `Layout3dOwner.setSlot` is the plain write and reports whether the value
changed; `Layout3dSurface.setSlot(key, value)` writes through and marks the
subtree dirty, exactly as the `metrics` setter does, with `relayout: false`
for a value nothing measures against.

**A widget writes one two ways.** `SceneLayout3d.slots` is a map on the
surface widget, reconciled on rebuild, for the app that knows its slots at the
root. `SceneSlotProvider3d<T>` is the widget for a provider that sits *inside*
the surface — which is where a `SceneTheme3d` will want to be, because it also
has to be an `InheritedWidget` for the widget layer. It owns a
`SlotProvider3d<T>`, a pass-through box that writes the slot when it attaches
and clears it when it detaches.

**A slot dies with the surface.** `Layout3dOwner.dispose` clears the map, and
the owner does not dispose the values: it collects state, it does not own it,
which is the same rule it already follows for the layouts themselves. A value
that needs disposing is disposed by whoever put it there. That is written in
the dartdoc, because the alternative — an owner that disposes anything
`Disposable` — is exactly the ownership trap item 2 is about.

## 4. Does a package's own build hook run when it is a dependency?

**Yes.** Answered by doing it, not by reading the docs.

The evidence that says it should: `flutter_scene` itself ships
`hook/build.dart`, and its pub-cache directory contains a populated
`flutter_scene_generated/` written while building an app that merely depends
on it. Its pubspec lists that directory under `flutter: assets:`, and
`GeneratedAssetSource.isPackageOwned` in the engine's runtime lookup exists
precisely to resolve a `packages/<name>/flutter_scene_generated/` manifest.
So the runtime half is supported outright; what is untested is a *third-party*
package doing it, which the engine's own source flags in a TODO as having "no
supported path yet".

The experiment:

1. `packages/flutter_scene_layout3d/hook/build.dart` calls `buildMaterials`
   over `assets/box_decoration3d.fmat` — and **only** that. `buildEngineAssets`
   is a separate concern: it is what makes `Scene.initializeStaticResources()`
   resolve, an app may still need to call it, and conflating the two would make
   the result unreadable.
2. The package's pubspec lists `flutter_scene_generated/`, and the directory
   is created with the engine's `.gitignore` so it survives a fresh clone.
3. `examples/render_probe`'s hook loses its `buildMaterials` call and its
   symlink, and the render lane runs. Forty tests pass there today.

### What came back

The hook ran, `impellerc` compiled the shader into
`packages/flutter_scene_layout3d/flutter_scene_generated/`, and
`examples/render_probe` passes **all forty** of its render tests with no
`buildMaterials` call and no symlink of its own. Every consumer inherits the
shader; the README says so, and the paragraph that told an application to copy
the file into its own `assets/` is gone.

Three things the experiment taught that the plan did not know:

- **The engine's TODO is about the build side only.** `generated_tree.dart`
  says a third-party package generating assets for its consumers "has no
  supported path yet", which reads like a prohibition and is not one: the
  runtime half was built for exactly this — `GeneratedAssetSource.isPackageOwned`
  resolves a `packages/<name>/flutter_scene_generated/` manifest, and
  `loadFmatMaterial` takes a `package:` argument to disambiguate. What is
  missing is packaging it as reusable API, not the capability.
- **The first run failed, and the failure is the migration note.** Taking
  `buildMaterials` out of `render_probe`'s hook does not remove what it wrote:
  `flutter_scene_generated/` is persistent by design, it survives `flutter
  clean`, and stale outputs are pruned only by the builder that wrote them, on
  a run it no longer makes. Two packages then offered
  `assets/box_decoration3d.fmat` and `loadFmatMaterial` threw *"Multiple
  generated .fmat materials"*. Emptying the app's directory once, keeping its
  `.gitignore`, fixed it for good. That is now in the README, in
  `docs/traps.md` and in `docs/engine-rules.md`, because every existing
  consumer hits it exactly once.
- **The package needs three things, not one.** The hook alone is not enough:
  the pubspec has to list `flutter_scene_generated/` under `flutter: assets:`
  (the build fails naming the missing entry if it does not), and the directory
  has to exist in the checkout with the engine's `.gitignore` inside it, so a
  fresh clone has the entry the pubspec promises. `flutter_scene` does the
  same three things for the engine's own shaders, which is the precedent that
  made this worth trying.

## Tests

Headless, in `flutter test`, on top of the 862 that pass today:

- `SceneDecoratedBox3d` builds a `DecoratedBox3d`, updates it in place on
  rebuild, and a rebuild that changes only `stateLayer` marks nothing dirty
  for layout.
- `DefaultTextRenderer3d` reaches a `SceneText3d`; an explicit `renderer`
  overrides it; a rebuild does not churn renderers; two labels under one
  default get two renderers, and disposing one leaves the other drawing.
- `Layout3dSlot` round-trips through the owner, is typed, returns null when
  unset and when detached, is cleared by `dispose`, and relayouts through
  `Layout3dSurface.setSlot`. `SceneLayout3d.slots` and `SceneSlotProvider3d`
  each write one from the widget layer.

On a GPU, in `examples/render_probe`: nothing new. Item 4 changes where the
shader is compiled and not what it draws, so the existing forty tests passing
unchanged *is* the assertion.

## The work

- [x] `SceneDecoratedBox3d`, the decoration exports, the `Container3d`
      decision recorded in its class doc, the two `drag.dart` examples checked
      against the compiler by `test/doc_examples_compile_test.dart`.
- [x] `DefaultTextRenderer3d` and `Text3d.rendererFactory`.
- [x] `Layout3dSlot<T>`, the owner map, `Layout3dSurface.setSlot`,
      `SceneLayout3d.slots`, `SceneSlotProvider3d<T>`.
- [x] The build-hook question, answered by running it: yes.
- [x] `docs/traps.md`, `docs/engine-rules.md`, `docs/README.md`, `AGENTS.md`,
      the CI comment, the package README and phase 0 of the Material plan,
      all updated to describe what exists rather than what is missing.

**862 tests before, 891 after; `dart analyze` clean across the workspace; 40
render probes green** with the shader compiled by this package rather than by
the app.

## What the original reasoning got wrong

Two things, both of which changed the shipped design.

**A slot cannot be keyed by identity.** The plan said "a slot is keyed by
identity, not by name … the way two `GlobalKey`s are", and a test written to
state that failed: Dart canonicalizes `const` instances, so two
`const Layout3dSlot<Palette>('palette')` written in different places are
already *one object*. Identity keying would therefore behave as value keying
for a `const` slot and as a unique key for a `final` one — the same code, two
behaviours, decided by a keyword nobody would think to look at, and silent
either way. `Layout3dSlot` has value equality on its type and its name
instead, which is a rule a reader can state; the cost is that two libraries
picking the same name for the same type collide, so a slot is named after the
library that owns it.

**`Container3d` was expected to gain a `decoration`, and should not.** The
Material plan asked for it outright, and a dartdoc example in `drag.dart` had
already written one by reflex, which is real evidence of the expectation. Two
things settle it against: this package has no composition in the imperative
layer, so a decoration on `Container3d` is a second implementation of the
painter lifecycle rather than a reuse of `DecoratedBox3d`; and Flutter's own
semantics puts the decoration inside the margin and around the padding, which
names a rectangle that is not the box's own size and that
`Decoration3dPaintRequest` — which carries a size and no offset — cannot
describe. Composing the two boxes says which rectangle is the panel, and the
class docs on both `Container3d` and `SceneContainer3d` now say so.

Two smaller findings that cost time and are written down where they will be
met:

- **`Text3d` had to grow a `rendererFactory`.** The plan assumed
  `SceneText3d.updateLayout` could resolve the inherited factory each rebuild.
  It cannot: `updateLayout` runs on every rebuild, so calling the factory
  there builds and disposes a renderer per rebuild. The box has to remember
  which factory made its renderer, which is a property on the box, and writing
  the same function again is a no-op.
- **A widget leaving the tree does not dispose the layout under it.** Only a
  lazily built child sets `Layout3dRenderBox.disposeLayoutOnUnmount`; every
  other widget-owned layout is disposed by the surface's teardown, and one
  removed before that is never reached — so a removed `SceneText3d` keeps its
  renderer until the surface goes. It predates this work and is not fixed
  here, because a render box disposing its own layout races the surface's
  recursive teardown and could double-dispose. It is pinned by a test and
  recorded in `docs/traps.md`, so fixing it will be noticed rather than
  silent.
