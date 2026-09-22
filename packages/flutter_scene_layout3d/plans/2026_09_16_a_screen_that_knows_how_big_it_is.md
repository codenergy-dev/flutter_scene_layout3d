---
status: completed
created_at: 2026-09-16T16:12:00Z
updated_at: 2026-09-21T16:25:00Z
commit: 141b71dc2792e7ccf468cf887bee36e2a9bd2a5a
---

# A screen that knows how big it is

The seventh plan off
[what a real application still needs](2026_09_11_what_a_real_application_still_needs.md),
and the last of the four that map says the first real port will demand. Right
to left went first because another item waited on it, a picture second because
every screen has one, an item that keeps its state third because a form waits
on it. This one is what is left, and it is the odd one of the four: the other
three were absences, and this one is **a hole in the accessibility story with
a wire already run past it**.

Its entry on the map puts it in one sentence worth repeating: for a stack whose
semantics layer is as carefully built as this one's, *the screen reader finds
the control and the large-text setting does not*.

## What is actually missing

Checked at `141b71d`, against a green 1191/545/4.

- **`Layout3dMetrics.textScaleFactor` is a `double`.** Flutter moved to
  `TextScaler` precisely because accessibility scaling is not linear — a
  platform that grows 14dp body copy by 1.8 does not grow a 57dp display line
  by 1.8, and a single multiplier cannot say so.
- **Nothing reads the platform's setting.** `grep -rn "textScalerOf\|MediaQuery"
  packages/*/lib` returns nothing at all. The number is authored: a
  `Layout3dCameraBinding` takes a `textScaleFactor` and defaults it to 1, and
  every surface in the gallery and in both test suites is at 1 because nobody
  typed otherwise. **The reader's own font setting has never reached a 3D
  screen**, on any path, by any spelling.
- **There is no `MediaQuery3d` and no `SafeArea3d`.** A camera-bound surface
  covers the view exactly, notch and home indicator included, and nothing in
  either package knows those exist. A ported screen puts its app bar under the
  status bar.
- **And nothing says how big the screen is** to a `build` method. The widget
  layer can read the unit contract (`Layout3dMetricsScope.of`) and cannot ask
  the one question a responsive screen is written against.

## The three questions, and their answers

This plan is small in code and mostly a set of decisions. They are here, up
front, because each one is a fork where the obvious answer is the wrong one.

### 1. Where does the reader's font setting live?

**On the metrics, not in a `MediaQuery3d`** — because the layout *measures*
with it. A `Layout3d` reads `metrics` inside `performLayout` with no
`BuildContext` in the way, and that is the only channel a `Text3d` has. Putting
the scaler in the screen data as well would give one number two homes and no
mechanism to keep them equal.

This is Flutter's own arrangement seen from the other side. There, `MediaQuery`
carries the scaler and `Text` resolves it *in `build`* before handing a
`TextScaler` to the render object; here the surface resolves it once and the
owner carries it. Same value, same place in the pipeline, one less lookup.

So: `Layout3dMetrics.textScaleFactor` becomes `Layout3dMetrics.textScaler`,
and `MediaQuery3dData` deliberately does not carry one. The dartdoc on both
says why, because a reader coming from Flutter will look in the wrong one
first.

### 2. What is an inset for a surface that is not the window?

**Nothing. Zero. And that is the whole answer.** A notch is a property of the
*view* — a piece of the window the operating system has spent — and a panel
hanging on a wall in a room has no notch, no home indicator and no status bar.
It is not a screen that happens to be free of them; the question does not
apply to it.

What follows from that is the rule this plan implements:

> A surface inherits the view's safe area **exactly when it stands in for the
> view**, which is what `Layout3dCameraBinding.screenFilling` means and what no
> other binding means.

The binding says so with one new getter, `standsInForTheView`, beside the
`derivesConstraints`/`derivesMetrics` pair it already has. A screen-filling
surface's padding passes through **unconverted in dp**: it covers the view
exactly, so its own dp height *is* `viewSize.height` by the binding's own
arithmetic, and a 44dp inset is a 44dp inset. Everything else gets
`EdgeInsets3d.zero`, and an author who wants insets on a wall panel — a bezel,
a frame, a physical mount — states them by wrapping the subtree in a
`MediaQuery3d` of their own, exactly as they would in Flutter.

### 3. How much of a size class is answerable?

The catalogue plan deferred *what a window size class means for a surface
floating in a room*, and this plan does not settle it. What it leaves behind
is the thing an author branches on: **`MediaQuery3dData.size`, the surface's
own extent in logical pixels**, plus `orientation` derived from it. No
breakpoints, no `WindowSizeClass3d`, no adaptive anything — those are the
catalogue's to invent once there is a component that wants them, and inventing
them here would be inventing them without a customer.

A surface that shrink-wraps its content reports an infinite extent on the axes
it was given no bound on, which is honest: it has no screen size yet, and
`SceneLayoutBuilder3d` is the thing that answers a content-driven question.

## A scaler is not a number

The text half is the one with real work in it, because the whole measurement
design leans on the scale being a single multiplier. `docs/traps.md` and three
dartdocs say the same sentence: *font metrics are linear in the size, so
applying the accessibility scale as a multiplier is exactly the same as having
asked for a bigger font, and it costs no re-measurement.* A `TextScaler` breaks
the premise — not within one font size, but across them.

The two text boxes land on different sides of that, and the difference is not
an inconsistency but the shape of what each one holds:

- **`Text3d` has one style, so the scaler still resolves to one number.**
  `metrics.textScaleFor(fontSize)` — `scaler.scale(size) / size` — is the
  geometric factor for *that* run of type, and `logicalPixelScale` becomes
  `unitsPerLogicalPixel * textScaleFor(style.fontSize ?? 14)`. The prepared
  handle stays valid across a change of scale, the font is never re-consulted,
  and the cheap path the prepare/layout split exists for is untouched.
- **`RichText3d` has many styles, so it cannot.** Its painter takes the
  scaler — `TextPainter.textScaler`, which is what it was always for — and the
  captured `RichText` takes the same one, so each span is measured and
  rasterized at its own scaled size. `logicalPixelScale` drops to
  `unitsPerLogicalPixel`. The cost is that a change of scale re-measures the
  paragraph, which is correct: changing the metrics relayouts the whole subtree
  anyway, and a paragraph whose spans scale differently *is* a different
  paragraph.

The existing test that pins the cheap path — *the paragraph itself was never
re-measured* in `rich_text_test.dart` — changes its claim with the behaviour,
and the new claim is the interesting one: two spans of different sizes under a
non-linear scaler come out at different multiples.

## What the widget layer publishes

`MediaQuery3dData`, `MediaQuery3d` and `SceneSafeArea3d`, in
`lib/src/widgets/media_query.dart`, all three of them widget-layer only.

**That boundary is deliberate and it is Flutter's.** No `RenderObject` reads a
`MediaQuery`; a `Layout3d` reads no screen data here. An inset is consumed by
being *removed for the subtree below it*, which is a build-time contract with
no equivalent in a layout tree — the package's tree-wide channel,
`Layout3dSlot`, writes the whole surface at once and cannot scope to a subtree.
An imperative caller that wants a safe area has the view's insets in its hand
already and writes a `Padding3d`.

```dart
class MediaQuery3dData {
  const MediaQuery3dData({required this.size, this.padding = EdgeInsets3d.zero});
  final Size3d size;          // logical pixels, the surface's own extent
  final EdgeInsets3d padding; // logical pixels, the view's safe area or zero
  Orientation get orientation;
  MediaQuery3dData removePadding({bool removeLeft, /* … */});
}
```

`Orientation` is Flutter's own enum, and `EdgeInsets3d` is the package's, with
`front` and `back` at zero: the platform has no depth inset, and the type stays
uniform with every other inset a box takes.

`SceneSafeArea3d` is Flutter's `SafeArea` with the same four flags and the same
`minimum`: it reads the data and the metrics, emits a `ScenePadding3d` of
`metrics.dpInsets(…)`, and republishes the data with what it consumed removed,
so a nested one pads nothing. `minimum` is in dp like everything a build method
writes.

**Where the size comes from, exactly**, because there is one place it could go
stale and this is the reasoning that keeps it from doing so:

- A surface that stands in for the view reports **the view's logical size**
  (`SceneLayout3d.viewSize`, else `MediaQuery.sizeOf`), not the panel's derived
  constraints. The two agree by construction, and only the first is read from
  something that notifies: a window widened but not heightened changes the
  derived width without changing the derived metrics, so a value read off the
  surface would have nothing to rebuild it.
- Every other surface reports **its own configuration** — the widget's `size`
  or `constraints`, converted with `toLogicalPixels`. Authored, so never stale.
- The depth is the surface's configuration depth either way, and zero while it
  is still unbounded, which is the first build and nothing else.

## Where the ambient value is read

`SceneLayout3d`, through `MediaQuery.textScalerOf(context)` and
`MediaQuery.paddingOf(context)` — the aspect-scoped getters, so a surface
rebuilds when the *text scale* changes and not when anything else in the
`MediaQueryData` does.

The scaler reaches the surface's metrics by one of two routes, and both end in
the same place:

- **A binding that derives the metrics takes it from the view.**
  `Layout3dCameraBinding`'s `textScaleFactor` becomes a nullable
  `TextScaler? textScaler`, where null means *whatever the view reports*. The
  binding's `update` grows a `Layout3dView` — the platform view as much of it
  as a binding derives from, which today is its size and its text scale — in
  place of the bare `viewSize`, and `needsViewSize` becomes `needsView`.
- **Otherwise the widget writes it**, onto whatever `SceneLayout3d.metrics`
  states: `(widget.metrics ?? standard).copyWith(textScaler: ambient)`.

And a `metrics` argument that carries a scaler of its own **asserts**, naming
where to put it instead. That is the one piece of deliberate friction in this
plan, and it is there because the alternative is silent: the gallery's table
panel states a `metrics` to say it is a smaller screen, and under a
last-statement-wins rule it would have quietly opted every label on it out of
accessibility scaling. A surface that is not under a `MediaQuery` at all —
`runApp(SceneView(…))` with no `WidgetsApp` above it — gets `noScaling`, the
same fallback `MediaQuery.textScalerOf` gives every Flutter `Text`.

## What this plan does not do

- **No size classes and no breakpoints.** See question 3.
- **No `viewInsets`.** Flutter's keyboard inset has nothing to report until
  [a letter someone can type](2026_09_11_what_a_real_application_still_needs.md#a-letter-someone-can-type)
  exists, and a field that is always zero is a page that is wrong.
- **No `devicePixelRatio` on the screen data.** It would be a lie for every
  surface but a camera-bound one: a panel the viewer can walk toward covers a
  different number of real pixels every frame. `metrics.logicalPixelsPerUnit`
  is the number a rasterizer actually wants, and it already says what it
  promises.
- **`Scaffold3d` does not consume the safe area.** Flutter's does, and this
  one will want to, but it is a catalogue change with its own token questions
  (does an app bar extend *under* the status bar or stop at it) and it belongs
  to [the components a screen still needs](2026_09_11_what_a_real_application_still_needs.md#the-components-a-screen-still-needs).
  Until then a ported screen writes `SceneSafeArea3d` itself, which is what
  half of Flutter does anyway. *Since closed:* phase 2 of
  [the components a screen still needs](../../flutter_scene_material3d/plans/2026_09_21_the_components_a_screen_still_needs.md)
  did it, and the token question turned out to have Material's answer
  already — the bar is drawn *under* the status bar — so it was a
  transcription of Flutter's arithmetic rather than a decision.
- **No imperative `SafeArea3d` box.** See the boundary above.

## The work

- [x] **Phase 1 — the scaler in the contract.** `Layout3dMetrics.textScaler`
      and `textScaleFor`; `sp` through the scaler; `Text3d.logicalPixelScale`
      per style; `RichText3d` handing its painter and its captured `RichText`
      the scaler and dropping the factor from its own scale.
      `Layout3dCameraBinding` taking `TextScaler?` and a `Layout3dView`.
- [x] **Phase 2 — the ambient value.** `SceneLayout3d` reading
      `MediaQuery.textScalerOf`, composing the view for the binding, writing
      the scaler onto an authored contract, and asserting on a `metrics` that
      carries one.
- [x] **Phase 3 — the screen.** `MediaQuery3dData`, `MediaQuery3d`,
      `standsInForTheView`, the publication in `SceneLayout3d.build`, and
      `SceneSafeArea3d`. Exported from `widgets.dart` and, for the data type,
      `flutter_scene_layout3d.dart`.
- [x] **Phase 4 — tests.** The scaler: a non-linear scaler growing two
      different type sizes by two different factors, in both text boxes, with
      the prepared handle surviving in the single-style one. The route: an
      ambient scaler reaching a label three boxes deep, through a binding and
      without one; the assert. The screen: the data for an authored panel and
      for a screen-filling one; `SceneSafeArea3d` padding, removing, nesting,
      `minimum`, and each flag off.
- [x] **Phase 5 — the pages.** Both changelogs where they are owed; the layout
      README's unit-contract section and its roadmap entry, which names this
      exact item as what is next; `docs/traps.md`'s unit contract section and a
      new trap for the safe area that is not there; `docs/README.md`; the
      Material package's typography dartdoc, which spells the scale
      `metrics.textScaleFactor`; and the map entry, struck, with what this
      reasoning got wrong.

## What the reasoning got wrong

Four things. The first is the one to carry away, and it is the same shape as
the finding in the plan before this one: the decision that looked like the
work was the easy half.

- **The inset question had a one-word answer, and the boundary was the work.**
  This plan opened by asking "what *is* an inset for a surface that is not the
  window", expecting to design something. The answer is *nothing* — a plane in
  a room does not have a notch — and it took a paragraph. What actually needed
  deciding, and what this plan named only in passing, is **where a screen's
  data lives at all**: the package has a tree-wide channel (`Layout3dSlot`) and
  a per-surface one (`Layout3dMetricsScope`), and neither can express "this
  inset has been consumed for the subtree below", which is the whole of what a
  `SafeArea` does. That forced the honest answer — `MediaQuery3d` is a
  widget-layer widget, as Flutter's is, where no `RenderObject` reads one — and
  the honest answer is what makes `SceneSafeArea3d` fourteen lines instead of a
  new tier.
- **The `TextScaler` migration was not a migration.** It was filed as a type
  change, and a scaler that is not linear across sizes breaks the premise the
  whole text layer rests on — *font metrics are linear in the size, so the
  scale can be applied geometrically on the way to world units*, a sentence
  that appears in four dartdocs and in `docs/traps.md`. It is still true of one
  font size and false across two, which split the two text boxes onto different
  answers: a `Text3d` resolves the scaler at its own style's size and keeps the
  cheap path; a `RichText3d` hands its painter the scaler and re-measures. The
  plan predicted the split, but as a nicety. It is the design.
- **The defect this plan found is the one it invented the assert for.** A
  surface that *states* a `metrics` — which is how an author says "this panel
  is a smaller screen", and exactly what the gallery's table panel does —
  would, under any last-statement-wins rule, have silently opted every label on
  it out of the reader's font setting. There was no prior art to copy: this is
  the first ambient value in the package that an author can partly state, and
  the composition rule (`metrics` states the rate and the density, the platform
  states the scale, and stating the scale *there* is an error that names where
  to put it) had to be invented rather than inherited. A quiet accessibility
  hole in the one class of surface an author bothered to configure would have
  shipped otherwise.
- **The published screen size needed a second source, and the plan assumed
  one.** The first draft read the size off the surface for every case, which is
  stale in exactly one way that matters: a window widened but not heightened
  changes a screen-filling surface's derived *constraints* without changing its
  derived *metrics*, and the metrics listenable is the only thing that rebuilds
  the widget. So a surface standing in for the view publishes the *view's* size
  — equal by the binding's own arithmetic, and published by something that
  notifies — and every other surface publishes what the widget itself stated,
  which cannot go stale at all. Neither case reads a derived value.

What the plan got right and is worth keeping: the argument for where the two
channels live. "What the layout measures with" versus "what a `build` method
branches on" is a test that answers the next question of this kind without
re-deriving anything, and it is now written into the map's seams.
