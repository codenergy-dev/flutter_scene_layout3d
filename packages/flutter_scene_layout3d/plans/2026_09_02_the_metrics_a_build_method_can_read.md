---
status: completed
created_at: 2026-09-02T14:45:00Z
updated_at: 2026-09-02T16:05:00Z
commit: 152016c041f7e5fff5c0e640619f93628eda131e
---

# The metrics a build method can read

This plan owns the one thing
[the Material catalogue plan](../../flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md)
put on phase 2's doorstep and asked to be settled *before* the first
component: **the widget layer cannot read the unit contract.**

It lands here, in `flutter_scene_layout3d`, for the reason phase 0's four
things did: every plan in this package is `completed`, and public API must not
arrive under another package's plan number.

## The gap

`Layout3dMetrics` — `dp()`, `sp()`, `unitsPerLogicalPixel`, the density —
lives on `Layout3dOwner` and nowhere else. A box reads it inside
`performLayout` as `Layout3d.metrics`, which is exactly right for the
imperative layer and useless to a `build` method: nothing publishes it through
a `BuildContext`.

The consequence is narrow and constant. Decoration figures escape it, because
`BoxDecoration3dPainter` converts radii, bevel, border and elevation at paint
time — which is why `SceneDecoratedBox3d(decoration: BoxDecoration3d(
borderRadius: BorderRadius3d.circular(12)))` is honest dp today. A *padding*
and a *size* do not escape it:

```dart
// Sixteen logical pixels, the way every Material spec figure is written.
Material3d(padding: EdgeInsets3d.all(16))
```

cannot be written, because `ScenePadding3d` takes world units and a build
method has no way to convert. The two shapes a catalogue writes constantly —
a padding and a fixed extent — are the two it cannot state in the units the
specification uses.

## The two shapes, and the argument that decides them

**An inherited metrics widget**, published by `SceneLayout3d`, so a build
method converts its own figures. Every existing box becomes dp-capable with no
new box API at all.

**Dp-stated values that convert inside `performLayout`** — a dp padding, a dp
size, a dp inset resolved where the metrics is known. More API, but the
conversion happens at the one place that cannot be wrong.

The argument that was supposed to decide this is staleness: a camera-bound
surface *derives* its metrics during the frame (`Layout3dCameraBinding`), so a
value read in `build` is the metrics as of the previous layout, and on the
frame a window resizes a padding computed in `build` is stale by exactly the
amount of the resize. **In this codebase that argument does not hold, and the
reason is worth writing down**, because it is not deducible from the metrics
class:

- `_SceneLayout3dState` never applies a binding during build or layout. It
  applies one from two places: `WidgetsBinding.addPostFrameCallback`, for the
  first application and whenever the binding, camera or view size changes; and
  the enclosing `SceneView`'s `elapsed` notifier, which is driven by a
  `Ticker` and therefore fires in the **transient callback** phase, before the
  build phase of that same frame.
- A metrics change is therefore always announced either in the transient phase
  of frame *N* (so a dependent rebuilds in frame *N*'s build phase) or after
  frame *N* (so it rebuilds in frame *N+1*'s build phase). Flutter's build
  phase precedes its layout phase, and the surface is laid out from
  `Layout3dRootRenderBox.performLayout` — inside the layout phase.
- So **the dependent rebuild lands before the layout that uses the value**,
  every time. A padding converted in `build` and the metrics the boxes below
  measure with are the same metrics, in the same frame.

What *is* one frame behind is the binding itself, and it always was: it reads
the enclosing view's box, whose new size is only written during the layout
phase, so on the frame a window resizes the binding derives from the previous
frame's view size. That lag applies to the surface's **constraints** exactly as
it applies to its metrics — they are written by the same call, from the same
numbers — so the panel's size and its unit contract never disagree with each
other. Correcting the metrics half alone would not fix the frame, it would
only make the two halves inconsistent.

That kills the staleness case for dp-stated values, and what is left is a
plain comparison:

- An inherited widget makes **every** box dp-capable: a padding, a size, a
  constraint, a spacing, a positioned offset, a stack's depth step, a list's
  item extent. Dp-stated values would need a dp twin of each — an unbounded
  API surface for a bounded problem, and two ways to spell every figure.
- The conversion-in-`performLayout` shape already exists and is already
  reachable: a `Layout3d` that reads `metrics` in its own `performLayout` is
  four lines (`test/support.dart`'s `DpBox` is exactly that), and a component
  that genuinely needs late binding writes one. Nothing is being closed off.
- A metrics change has to relayout the subtree either way. The inherited
  widget adds a rebuild of the dependents *in front of* that relayout; it does
  not replace it, and must not be allowed to look like it does.

**Ship the inherited widget.**

## What ships

**`Layout3dMetricsScope`**, an `InheritedWidget` in
`lib/src/widgets/surface.dart`, carrying a `Layout3dMetrics`:

```dart
final metrics = Layout3dMetricsScope.of(context);

ScenePadding3d(
  padding: metrics.dpInsets(const EdgeInsets3d.all(16)),
  child: SceneSizedBox3d(height: metrics.dp(56), child: label),
)
```

`of` asserts when there is no surface above; `maybeOf` returns null.
`updateShouldNotify` is value inequality, so an assignment that changes
nothing rebuilds nothing.

**The constructor is private.** The scope reports what the surface's owner
actually measures with, and a second one inserted by hand would change what
`of` says without changing what a single box measures — a divergence nothing
would report. `SceneLayout3d` publishes it around its `child` and is the only
thing that can.

The name is `Layout3dMetricsScope`, not `Layout3dMetrics.of`, for the reason
`MediaQuery` and `MediaQueryData` have two names: the data class is already
called `Layout3dMetrics`, and it is a value a `Layout3d` reads without any
widget in sight.

**`Layout3dSurface.metricsListenable`**, a `ValueListenable<Layout3dMetrics>`
that notifies when the contract changes — the seam the widget layer needs to
know that a binding derived a new one, since a binding writes the surface
directly and no rebuild is involved. It notifies only on a real change,
because the setter already early-outs on an equal value, so a still camera
costs nothing.

**`SceneLayout3d.metrics`**, the authored contract as a widget property.
Today the declarative layer cannot state a unit contract at all: it can only
get one from a binding, and `Layout3dCameraBinding.billboard`'s own dartdoc
tells the reader to pair it with "an authored `Layout3dSurface.metrics`" —
which is an imperative API a `SceneLayout3d` user does not have. The property
follows the ownership rule the constraints already follow: a binding that
`derivesMetrics` owns the contract and the property asserts against it, the
way a screen-filling binding asserts against a `size`.

**`Layout3dMetrics.dpInsets`**, the `EdgeInsets3d` counterpart of `dpSize`, so
the two shapes a catalogue writes constantly each have one named conversion.

**The rebuild is deferred when it cannot be legal.** A metrics write during
the persistent-callback phase — Flutter's build, layout and paint — cannot
mark this element dirty for a pass already running, and `Overlay3d` really
does write a detached entry's metrics from inside `performLayout`. So the
listener checks `SchedulerBinding.schedulerPhase` and takes the next frame in
that one case, and marks dirty immediately in every other. The immediate path
is the one every camera-bound surface takes.

## What this does not change

**Writing the metrics still relayouts the subtree, by design.** The scope adds
a rebuild in front of that relayout for the widgets that read it; it does not
replace it, and a box that never read the scope — every box in the imperative
layer, and every widget that writes world units — must still be laid out
again. That is what makes `metrics.dp(48)` correct for a box nobody rebuilt,
and a test states it in those terms.

**Nothing is added to the per-frame path.** The listenable notifies only on a
changed value; a still camera writes an equal metrics, the setter returns
early, and no listener runs.

## Tests

Headless, on top of the 891 that pass today:

- `dpInsets` scales all six faces, and agrees with `dp` face by face.
- A dp figure resolves to the right world units at two different rates,
  through `SceneLayout3d.metrics`.
- The same figure follows a metrics change: written imperatively through a
  `Layout3dController`, and derived by a binding, with the laid-out size
  changing in the pump that follows.
- **The staleness rule, in the direction claimed**: on the frame a
  screen-filling binding derives a new contract, the dependent's `build` runs
  *before* the surface's layout, and the box laid out in that frame has the
  size the new metrics implies. Recorded as an order of events, not inferred.
- A dependent rebuilds when the metrics changes, and does not when an equal
  metrics is assigned.
- A box that does not read the scope is still relaid out by a metrics change.
- `maybeOf` is null outside a surface; `of` asserts.
- A metrics write from inside the persistent-callback phase does not throw,
  and the rebuild lands on the next frame.
- `SceneLayout3d.metrics` beside a metrics-deriving binding asserts; beside a
  billboard binding it is honoured.

## The work

- [x] `Layout3dMetrics.dpInsets`.
- [x] `Layout3dSurface.metricsListenable`, notified from the setter and
      disposed with the surface.
- [x] `Layout3dMetricsScope`, published by `SceneLayout3d` around its child,
      exported from `lib/widgets.dart`.
- [x] `SceneLayout3d.metrics`, with the binding-ownership assert.
- [x] Tests: `test/metrics_scope_test.dart` (ten) and one more in
      `test/metrics_test.dart`.
- [x] `docs/traps.md`'s unit-contract section, `docs/README.md`, `AGENTS.md`,
      both READMEs, the package CHANGELOG, and the Material plan's *What phase
      1 found* and phase 2 checkbox.

**891 tests before, 902 after; `flutter_scene_material3d`'s 80 untouched and
green; `dart analyze` clean across the workspace; `dart format` clean.** No
render probe: nothing here draws.

## What the original reasoning got wrong

**The phase argument held, and the test that was supposed to prove the
deferral proved something else.** The plan meant to trigger a
persistent-callback-phase write with
`SchedulerBinding.addPersistentFrameCallback`. Two things went wrong with
that, and both are worth knowing before reaching for it again: a callback
registered mid-test runs *after* `RendererBinding`'s own drawFrame callback,
so the write lands after that frame's layout rather than before it; and a
persistent callback cannot be removed, so it went on firing into the next
tests in the file, wrote to a disposed surface, and surfaced as an unrelated
test failing with "Multiple exceptions (2)". The honest trigger was the real
one all along: a box that writes the contract from its own `performLayout`,
which is the shape `Overlay3d` has. `SceneWriter3d` in the test file is four
lines and needs no scheduler at all.

**The deferral guard is narrower than the plan claimed.** Marking an element
dirty from inside the *layout* phase is legal — it simply lands on the next
frame, which is what the guard arranges anyway. What the guard actually
prevents is a write from inside a build (`markNeedsBuild` during
`buildScope`), or from inside a lazily built child, where
`invokeLayoutCallback` has the state locked and Flutter throws. It is
belt-and-braces for the path that exists today, and the test states the
behaviour — no throw, and the rebuild lands on the next frame — rather than
the mechanism.

**A dp *size* is only observable under loose constraints, which cost the first
four test failures.** `SceneSizedBox3d(width: metrics.dp(120))` under a tight
surface comes out the surface's width: the constraint wins, exactly as it does
in Flutter. So a test that wants to see a converted size has to loosen the
surface, and on a screen-filling surface — tight by construction — the padding
is the only honest witness of what `build` computed. A component author will
meet the same thing.

**`SceneLayout3d.metrics` was scope creep that paid for itself twice.** It is
not needed to *read* the contract, which is what this plan is about. But the
declarative layer could not state one at all, so
`Layout3dCameraBinding.billboard` — whose dartdoc tells the reader to pair it
with an authored contract — had nothing to pair with; and it made the whole
test file expressible without a camera. It also subsumed the special case in
`didUpdateWidget` that reset the metrics when a deriving binding was dropped:
the general rule (a binding that derives owns it, otherwise the property does)
covers it, and the test that pinned the old behaviour still passes.

**A widget inside a detached overlay entry gets the right number, for a reason
worth writing down.** The scope reports the *host* surface's contract, while a
detached entry's boxes are laid out on a surface of their own — and
`Overlay3d._layoutDetachedEntries` pushes the host's contract onto that
surface on every pass, which `test/overlay_test.dart` already pins. So the two
agree. The corollary, read out of that method rather than tested here: an
entry whose own binding derives a contract has it overwritten by the host's on
the very next pass. That is what the comment there intends — the unit contract
is shared — but it is not obvious from the entry's side.
