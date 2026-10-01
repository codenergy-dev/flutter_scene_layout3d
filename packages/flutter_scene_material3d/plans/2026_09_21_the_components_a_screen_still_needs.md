---
status: in progress
reason: phases 1 to 3 have landed — the alert dialog and the labelled tiles, the safe area and type that grows, the switch's thumb, the chip's lift and both progress indicators; phases 4 to 7 are open, and phase 2's safe area has no lane that draws it
created_at: 2026-09-21T15:46:07Z
updated_at: 2026-09-30T21:30:00Z
commit: 763e3dff41a1c75ac35997cf9244e101bb7250bf
---

# The components a screen still needs

The catalogue is broad and it is not the catalogue. This plan is the batch
[what a real application still needs](../../flutter_scene_layout3d/plans/2026_09_11_what_a_real_application_still_needs.md#the-components-a-screen-still-needs)
files as broad and shallow, and it is the last item in the middle of that
map's queue: the motion lane is closed, the scheme generator is closed, and
what stands between a ported screen and this catalogue is now mostly
components that are simply not here.

The map's entry asks for it to be phased the way the catalogue plan phased
ten, and it names the mechanism that makes that possible: **nearly all of this
is composition over `Material3d` plus a public token set resolved by state**,
which is the one mechanism the whole catalogue uses. So the phases below are
grouped by what each component *needs underneath it*, not by where it sits in
Material's own documentation — a group that needs nothing new goes first, and
a group that needs a change in the layout package gets that change as its own
plan there, which is the rule phase 0 of the catalogue established.

## The order, and the test it answers to

The map's acceptance criterion is a real screen from an application that
already exists, re-laid on this stack. That is what orders these phases: **the
first ones are the components a ported screen reaches for first**, and those
are not the interesting ones. A settings page, a confirmation, a form with a
"remember me" row — every application has them, and every one of them is
written by hand here today.

| Phase | What it needs underneath | Components |
| --- | --- | --- |
| 1 | nothing | `AlertDialog3d`, the checkbox's third state, `CheckboxListTile3d`, `SwitchListTile3d`, `RadioListTile3d` — **landed** |
| 2 | the safe area, and type that grows | `Scaffold3d` consuming `MediaQuery3d.padding`; a control that grows with its label — **landed** |
| 3 | the node tier, with a clock | `LinearProgressIndicator3d`, `CircularProgressIndicator3d`, the switch's growing thumb, the chip's press lift — **landed** |
| 4 | nothing, but more of it | `Badge3d`, `MaterialBanner3d`, `BottomAppBar3d`, `NavigationDrawer3d`, `ExpansionTile3d`, a snack bar's second line |
| 5 | one choice over many options | `SegmentedButton3d`, `TabBar3d` and `TabBarView3d`, `RadioGroup3d` |
| 6 | a scroll view that runs backwards | `reverse` in the layout package, `Carousel3d`, `Scrollbar3d`, `RefreshIndicator3d` |
| 7 | a second arena, or a design answer | `RangeSlider3d`, `DataTable3d`, `Stepper3d`, the slider's ticks and value indicator, a tooltip on long press, a draggable sheet |

Each phase is written in full when it is picked up, below its predecessor's
findings, for the reason the map gives about its own entries: a phase written
six ahead reasons against a codebase that will have moved.

## Phase 1: what a form screen writes by hand

### `AlertDialog3d`, and why the judgement changes

Phase 6 of the catalogue refused this component, and its reason was a good
one for a catalogue: an alert dialog is a column of a title, some text and a
row of buttons, nothing about that arrangement is three-dimensional, and it
would be the first component that exists only to save a caller writing a
`SceneColumn3d`. The map asks for that to be reread **with an application's
eyes**, and from there it reads differently. A caller porting fifty dialogs
writes the same forty lines fifty times, and the forty lines have three
things in them that a caller gets wrong:

- **The type roles.** A title is `headlineSmall` in `onSurface` and the body is
  `bodyMedium` in `onSurfaceVariant`, and the gallery's own two dialogs write
  both by hand. A dialog that omits the second role draws its body in the
  title's colour and nothing says so.
- **The spacing.** 16dp from an icon to the title, 16dp from the title to the
  body, 24dp from the body to the actions, 8dp between the actions — Flutter's
  `AlertDialog` figures, and M3's.
- **The width.** Flutter's `AlertDialog` is an `IntrinsicWidth` around a
  stretched column, so the actions row can sit at the trailing edge of a
  dialog that is only as wide as its widest line. A caller who writes a column
  with `CrossAxisAlignment3d.start` gets the actions at the *leading* edge, and
  one who writes `stretch` without the intrinsic gets a dialog the width of
  the screen — which is the phase-3 trap `Dialog3d` already documents about
  itself.

That third one is the argument. **A component that exists to save a caller a
column is not worth having; one that exists to save a caller the one
arrangement of that column that is right, is.** It stays a composition over
`Dialog3d` and adds no token family: its figures go in a small
`AlertDialogStyle3d` beside `DialogStyle3d`, whose surface it does not repeat.

`AlertDialog3d.text` takes strings and composes the announcement out of the
title, which is the same answer `ListTile3d.text` gives to the same problem —
a `Semantics3d` gathers nothing, so a dialog built out of widgets announces a
route with no name unless it is told one.

What it leaves out, and says so in its dartdoc: Flutter's `OverflowBar`, which
stacks the actions vertically when they do not fit in a row, and `scrollable`,
which puts the title and the body in a scroll view. The layout package has
neither an overflow bar nor a reason yet to build one; both are the second
dialog a port asks for, not the first.

### The checkbox's third state

Phase 7 deferred it as "a third state in every row of a four-state table",
which is true of the *table* and turns out not to be true of the *style*: a
mixed box is drawn exactly as a checked one is — filled, no outline, a mark in
it — with `Icons.remove` in place of `Icons.check`. So `CheckboxStyle3d` does
not change at all, and the third state is a glyph choice and a semantic flag.

- `Checkbox3d.value` becomes `bool?`, and `tristate` says whether null is
  allowed. `onChanged` becomes `ValueChanged<bool?>`, which is **Flutter's own
  signature** and the one a ported screen already has; a caller of the
  two-state box writes `value!`, exactly as in Flutter.
- A press walks Flutter's cycle: unchecked to checked, checked to mixed when
  tristate (otherwise to unchecked), mixed to unchecked.
- It publishes `mixed: true` and `checked: false` for the third state, which
  is what Flutter's `Checkbox` publishes.

### The labelled tiles, and the two-labels problem

Phase 7 declined these for a reason that was real: a checkbox in a tile has
two things that could announce, and "a component that put a checkbox in a
tile would have to decide which of the two states its own announcement".
Flutter decides by *merging*: `CheckboxListTile` is a `MergeSemantics` around
a `ListTile`, and it wraps the checkbox in `ExcludeFocus`. There is no merge
here, and there is no exclusion either — `Semantics3d(enabled: false)` takes
one component off one node and leaves every node under it published.

So the answer here is not to merge two announcements but to **have only one
control**. Inside a labelled tile the checkbox, the switch or the radio is
*drawn*, not operated: the tile is the target, the focus, the wash and the
announcement, and the control inside it publishes no semantics, takes no
focus, installs no ink well and answers no ray. That is what a person means
by "the whole row is the checkbox", and it is the same arrangement Flutter
ends up with after the merge — one node, the row's rectangle, `checked` and
the title as its label.

The mechanism is a scope the tiles put above their control and that the three
controls read, and **it is not exported**: a caller who wants a control that
draws and does not act has never asked for one, and the scope is a promise
between the tiles and the controls rather than a public switch. The tiles
reuse the whole of `ListTile3d` through a builder that takes the semantics
properties from the caller, rather than wrapping a `ListTile3d` and publishing
a second node over its first — which is `buildNavigationDestination3d`'s shape
for the bar and the rail.

`ListTileControlAffinity3d` says which end the control goes at, with
Flutter's three values and Flutter's per-component meaning of `platform`:
trailing for a checkbox and a switch, leading for a radio.

### Tests

- The dialog: the roles, the gaps, the icon centring the title, the actions at
  the trailing edge of a dialog narrower than the screen, and the actions
  mirroring in right to left; its announcement from `.text`.
- The checkbox: the cycle with and without `tristate`, the mixed glyph, the
  mixed semantics, and an assert on `null` without `tristate`.
- The tiles: one `Semantics3d` for the whole row with the control's state on
  it; one `Focus3d`; one reaching `TapTarget3d`; a press anywhere on the row
  changes the value; a hover washes the row and not the control; the control
  at the end its affinity says, in both reading directions.

### The gallery

The settings card's two switch rows become `SwitchListTile3d`s — which makes
the *row* pressable where it used to be only the 52dp switch at its end — and
the about dialog becomes an `AlertDialog3d` with an icon and a close action,
so that a person running the gallery can see the arrangement this phase is
for.

## What phase 1 found

All of it shipped as described above: `AlertDialog3d` and
`AlertDialogStyle3d`, `Checkbox3d.tristate`, the three labelled tiles and
`ListTileControlAffinity3d`, and the gallery's two switch rows and about
dialog moved onto them. The Material suite is **633** tests, up from 585.
Five things came out of doing it that the reasoning above did not predict.

### 1. `Dialog3d` centres a narrow arrangement, and Flutter's does not

The first version of `AlertDialog3d` was the intrinsic width around a
stretched column exactly as written above, and the test that asked where a
short dialog's only action was found it **in the middle**. `Dialog3d` holds
its child in an align with a width factor of one, which loosens the width —
so a column narrower than the 280dp minimum is laid out at its own width and
centred in the dialog, and its actions stop short of the trailing edge. In
Flutter the minimum reaches `IntrinsicWidth` directly, and the question never
comes up. The arrangement now carries the minimum inside the padding itself,
and the test asserts the action's edge rather than only the dialog's width.

That is the *one arrangement a caller gets wrong* argument, met by the
component written to make it: a hand-written dialog in this package already
had this defect, because `Dialog3d` has always behaved this way.

### 2. The missing scrolling body was met on first use

The gallery's about dialog, moved onto `AlertDialog3d` with an icon and an
action, **overflowed its 480dp screen by 12dp in the headless suite** — which
lays text out in the test font, whose glyphs are as wide as they are tall and
much wider than real type. In a window it fits. The overflow is a layout
error here, not a clipped paragraph, so the gallery's copy was shortened and
says why. The finding for the plan is that `scrollable`, filed above as "the
second dialog a port asks for", is closer than that: **any dialog whose body
is a paragraph is one font size away from needing it**, and it belongs in the
earliest phase that touches dialogs again rather than in phase 7.

### 3. The two-labels problem was never about labels

Phase 7 said a component putting a checkbox in a tile "would have to decide
which of the two states its own announcement". Reading `Semantics3d` settled
that the choice is not available at all: `enabled: false` takes one
component off one node, so there is no way to silence a subtree after it has
been built. What was available was to not build the second control. The
unexported `ControlInTile3d` is that, and it is small — each of the three
controls asks one question and skips its well, its semantics and its target
— and the tile tests assert the result directly: one enabled `Semantics3d`,
one `Focus3d`, one reaching target, and a hover over the control washing the
row and not the control.

### 4. The third state was not a third column

Phase 7 deferred tristate as "a third state in every row of a four-state
table". Material draws a mixed box exactly as a checked one, so
`CheckboxStyle3d` did not change at all: the third state is which glyph goes
on the box and which flag goes on the node. The cost was elsewhere —
`onChanged` became a `ValueChanged<bool?>`, which is Flutter's signature and
the one breaking change in this phase. Two callers in the repository wrote
`value` where they now write `value!`.

### 5. A page describing a test that never existed

`DialogStyle3d` and `MenuStyle3d` both cited a
`test/overlay_defaults_test.dart` that read their figures off a real Flutter
`Dialog` and `PopupMenuButton`. **No such file has existed at any commit in
this repository**, so two token sets were described as drift-checked against
Flutter and are in fact transcriptions pinned only against themselves. The
dartdoc now says so. Writing that drift test is small, and it is the obvious
thing for whichever phase next touches an overlay.

### What phase 1 did not do

*Since done, for the photograph lane:* phase 2 began by running it over the
committed phase 1, and the dialog and the switch rows draw as laid out. The
gallery itself has still not been run by a person.

**It was not looked at in a window.** The gallery's settings rows and about
dialog changed, and the headless suite and `standsOnItsPanel3d` are green over
them; nobody has run the gallery or the photograph lane on these changes yet.
The render-probe lane has no scene for any of the new components either — the
arrangement is layout and is asserted headlessly, and nothing in this phase
draws in a new way, but the icon glyph centred above a title and a switch
drawn without its ink well are both new pictures.

## Phase 2: the safe area, and type that grows

*Written when the phase was picked up, after phase 1 was photographed: the
photograph lane ran over the committed phase 1, and the alert dialog and the
two switch rows draw as the tests say they are laid out.*

Two things
[a screen that knows how big it is](../../flutter_scene_layout3d/plans/2026_09_16_a_screen_that_knows_how_big_it_is.md)
left to this plan by name.

**The safe area.** That plan published `MediaQuery3d.padding` and
`SceneSafeArea3d` and left the catalogue alone, because "whether an app bar
stops at the status bar or is drawn under it is a component decision with
tokens attached". It is not, in the end, a decision: Material's answer is
*under*, and Flutter's `Scaffold` has the arithmetic. So this phase transcribes
it rather than inventing one. `AppBar3d` and `SliverAppBar3d` take `primary`
and grow by the top inset with the toolbar below it; `NavigationBar3d` grows by
the bottom inset; `NavigationRail3d` clears its leading side; `Scaffold3d`
takes away from each slot what the other slots consumed, and puts the floating
action button `endFloat`'s distance from the bottom and trailing insets.

**A control that grows with its label.** The map's entry said "a 48dp row of
14sp type at a large accessibility setting is a row the text overflows, here as
in Flutter", and named no component. So the phase began with a measurement: a
screen's worth of the catalogue laid out at 1.0, 1.3 and 2.0, reporting which
overflowed. **The sentence was wrong** — no row did, because every height in
the catalogue that holds a label is a minimum — and one component overflowed
that the sentence did not predict: `NavigationBar3d`, already at 1.3. Flutter's
does not, and the reasons were in Flutter's source: icons never grow with type,
and a navigation bar clamps its labels to 1.3 and an app bar its title to 1.34.
Neither was expressible in the layout package, so it got
[a plan of its own there](../../flutter_scene_layout3d/plans/2026_09_21_a_label_that_says_how_far_it_grows.md):
a per-label `textScaler`, and `SceneTextScaling3d.clamped` for a subtree.

The measurement is now `test/type_that_grows_test.dart`, and the safe area is
`test/safe_area_test.dart`.

## What phase 2 found

The Material suite is **667**, the layout suite **1299**. Four findings.

### 1. The overflow was two defects that each looked like enough

With `Icon3d` no longer growing, the bar still overflowed at 1.3 — by 0.8dp.
The second cause was its **12dp of vertical padding**. Flutter's bar has none:
its 52dp of pill, gap and label are *centred* in 80, which at 1.0 puts the pill
14dp down, exactly where 12dp of padding plus centring put it here. The two
arrangements are indistinguishable until the label grows, and then one has
28dp to spare and the other 4. The bar's vertical padding is gone and a test
pins the pill at 14dp; the rail keeps its 12, because a rail starts at its top
rather than centring.

### 2. The floating action button had never mirrored

`Scaffold3d` put the button at the right whatever the reading direction.
Flutter's `endFloat` is the trailing corner, and
[the right-to-left plan](../../flutter_scene_layout3d/plans/2026_09_15_a_row_that_reads_right_to_left.md)
had not reached it — it went through the catalogue's rows, paddings and
corners, and the button is a delegate's arithmetic rather than any of those.
It was found because the trailing *inset* needed a side, and asking which side
asked the older question too.

### 3. The safe area has no lane that draws it

Nothing in `examples/` binds a surface with
`Layout3dCameraBinding.screenFilling`, so `MediaQuery3d.padding` is zero in
every window this repository opens, and the whole of this half is proven
headlessly and nowhere else. The tests state their own insets through
`MediaQuery3d`, which is honest about what they prove — the arithmetic — and
silent about whether a status bar's worth of app bar looks right on a phone.
**That wants a mobile run of the gallery on a screen-filling surface**, which
is a gallery change and a device, and neither was in this phase.

### 4. What was left, and why

- **`extendBody` and `extendBodyBehindAppBar`** tell a body that runs behind a
  bar about the platform's inset and not about the bar. Flutter adds the bar's
  height to the padding; nothing here uses either flag with a safe area, and
  the arithmetic wants a real screen to check against.
- **A control that grows with its label** turned out to need nothing from
  this plan beyond the navigation bar, because the catalogue's heights were
  already minimums. What it does leave is the rail: at twice the size the
  test font wraps 'Inbox' onto three lines in an 80dp rail, and so, less
  dramatically, would a real one. Flutter's rail does the same.

## Phase 3: the node tier, with a clock

*Written when the phase was picked up, against `2f227ef`.*

Four things, and what they share is that each one moves every frame for a
while and none of them changes a size. That is the node tier —
`docs/traps.md`'s second of three — and the phase's claim is that all four
can live there: **no box is laid out again from the first frame of any of
them to the last.** Each suite asserts it.

### The switch's thumb, which slides, grows and swells

`Switch3d` does not animate at all today: it is a stateless widget whose
thumb jumps from one end to the other on a toggle. Flutter's M3 switch does
three things over 300ms, and they are all transcribed from `_SwitchConfigM3`
and `_MaterialSwitchPainter`:

- **The slide**, on `Curves.easeOutBack` forward and its flip backward, so the
  thumb overshoots the end a little and settles.
- **The growth.** An off thumb is 16dp, an on one 24dp, and in between the
  thumb passes through a **34 by 22** stretch on a three-part sequence —
  11% of the run to the stretch, 72% to the far size, 17% held. A thumb with
  an icon is 24dp in both states, and does not grow.
- **The press.** A held thumb is 28dp, whichever way the switch is set.

The switch keeps its colours as a token substitution, as it does today, so
the track and the thumb change colour on the first frame and the geometry
takes the 300ms. Flutter cross-fades the colours as well; here a cross-fade is
either a rebuild every frame or a decoration channel `Material3d` does not
have, and the phase would rather ship the motion on the cheap tier and name
the difference.

**The thumb is drawn at 24dp and scaled.** A node-tier scale about the thumb's
centre is `T(c)·S·T(−c)` on a proxy above it, written by a private box that
listens to two controllers — the toggle's and the press's — so the switch
builds once for a toggle and not at all while it moves. The scale stretches a
circle into an **ellipse** at 34 by 22, where Flutter's stretch is a stadium,
because the corner radius scales with the box. At its widest that is a
millimetre of difference for a thirtieth of a second, mid-flight.

The figures go into `SwitchStyle3d` beside the existing `thumbSize`:
`unselectedThumbSize`, `pressedThumbSize`, and the transitional width and
height. The run's duration is `theme.motion.medium2`, which is Flutter's
300ms, and the press takes `short2`, Flutter's `kRadialReactionDuration`.

Inside a labelled tile the switch still slides — Flutter's does — and does not
swell, because the row is the control and the switch installs no well.

### The chip that lifts under a press

Flutter's M3 action, filter and choice chips rest at 0 and rise to **1dp**
while pressed, over `RawChip.pressedAnimationDuration` — 75ms — on
`Curves.fastOutSlowIn`, which is `Material`'s own animation curve. Its input
chip does not rise at all. In Flutter that 1dp is a shadow with a transparent
colour, which is to say nothing; here an elevation is a distance, so the lift
is real.

It goes on the node tier as a `SceneAnimatedSlide3d` around the chip's
`Material3d`, which is Flutter's `AnimatedPhysicalModel` without the rebuild:
the chip rebuilds once when the press starts and once when it ends, and the
75ms in between are a matrix. `ChipStyle3d.pressElevation` carries the figure
per variant. Two of these are public in Flutter — `RawChip`'s duration and,
through a real pressed chip's `Material`, the elevation itself — so the drift
test reads both rather than transcribing them.

### `LinearProgressIndicator3d`

Flutter's default is the one it calls `year2023`: a 4dp bar, `primary` on a
`secondaryContainer` track, square ends, and neither the 2024 gap nor its stop
dot. That is what a ported screen already draws, so that is what this draws.

**A bar that fills is a scale, not a width** — `docs/traps.md` says it, and
`Slider3d` is the precedent. The difference is that a slider has a fixed width
and a progress bar fills its parent, so the span's position in world units is
not known until layout. A private box holds a span as two fractions and writes
`T(x₀·w)·S(x₁−x₀)` from its own `performLayout` and from its setters, which is
`MotionTransition3d`'s answer to an animation that needs a size. In right to
left the span is mirrored inside the box, as Flutter's painter mirrors it.

**Indeterminate** is Flutter's two lines on Flutter's four intervals over
1800ms, repeating, each line one span box listening to the controller. The
track is drawn whole behind them rather than in the pieces Flutter paints
between them, because the track is a slab and the lines stand one
`stepOver` in front of it.

### `CircularProgressIndicator3d`

The one component in the phase the layout package could not draw, and it got
[a plan there](../../flutter_scene_layout3d/plans/2026_09_30_a_border_painted_by_a_gradient.md):
**a border painted by a gradient**. A transparent circle with a 4dp border is
a ring, and a `SweepGradient` border with a hard stop is the arc of it. The
arc always starts at three o'clock in the panel's own frame; the component
turns the panel on the node tier to where the arc should start — twelve
o'clock for a determinate one, and wherever Flutter's head and tail have got
to for an indeterminate one. The determinate value's track, when a
`backgroundColor` is given, is the rest of the same ramp, so the track and the
value are one slab rather than two that could z-fight.

Flutter's default geometry is kept, down to its one oddity: the box is 36dp
and the stroke is centred on its circle, so the ring's outside is 40dp and
overhangs the box by half a stroke. A ported screen lays out against the 36.
An indeterminate arc's square caps are the arc extended by half a stroke at
each end, which is what a square cap on a circle nearly is.

An indeterminate spinner is a decoration written every frame, which is the
repaint tier — cheaper still than the node tier — plus the turn.

### One style for both indicators

`ProgressIndicatorStyle3d` is Flutter's `ProgressIndicatorThemeData`
resolved: the colour, the two tracks, the bar's height, the circle's size and
stroke, and the slab thickness and step the catalogue adds. Both widgets take
Flutter's own parameters — `value`, `color`, `backgroundColor`, `minHeight`,
`strokeWidth`, `semanticsLabel`, `semanticsValue` — and publish Flutter's
semantics: a progress bar with a value between 0 and 100 when determinate, a
loading spinner when not.

### Tests

- The switch: the thumb at each end at rest and its size there; the overshoot
  past the end on the way; the stretch part way; the icon thumb not growing;
  the press swelling it and letting it go; right to left; **nothing laid out
  and nothing built** across the run; and the tile's switch sliding without
  swelling.
- The chip: the lift while pressed and the return, per variant, with the
  input chip not moving; nothing laid out; the drift test against Flutter's
  pressed chips and `RawChip.pressedAnimationDuration`.
- The indicators: the determinate span at a value and mirrored; the
  indeterminate lines at known points of Flutter's timeline; the arc's
  gradient and turn; the overhang; the semantics; the defaults against
  Flutter's; and nothing laid out across a second of either spinner.

### The gallery

The settings screen's Save button shows a spinner for a moment before the snack
bar, the way an application that talks to a server does, and a determinate bar
follows the volume, so that a person running the gallery can see both.

## What phase 3 found

All of it shipped as described above, and the phase's claim holds: from the
first frame of any of the four motions to the last, **nothing is laid out and
nothing is built**. The Material suite is **714**, up from 667; the layout
suite **1311**; the render probe **112**, with two new scenes; the gallery **8**.
Seven findings, and the last is the one that mattered most.

### 1. The check every "nothing laid out" test made could not fail

The first draft of this phase's tests did what the suites here have always
done: pump a frame, then assert `needsFlush` is false. **That is false after
any pump whatever happened**, because the frame the pump drew has already laid
the surface out. The first replacement watched from a ticker scheduled after
the component's — which catches dirt raised by a tick — and a control test
written to prove the watcher worked found it **blind to a relayout that
arrives through a rebuild**, which is how an implicit animation relayouts. The
instrument that works listens where every piece of dirt passes: a box marked
for layout asks its surface for an update, and at that moment the surface
needs a flush. `watchFrames` in `test/surfaces_support.dart` is that, with
Flutter's `debugOnRebuildDirtyWidget` counting the builds beside it and two
control tests — a tick that resizes a box, and a rebuild that does — proving
it sees both.

The older claims were rechecked with it rather than assumed. The slider's
twenty frames of drag and the ripple's whole run both lay nothing out, as their
documentation says; the slider's test now watches at the source, since
`docs/traps.md` cites it as the evidence.

### 2. A box cannot keep a layout child the widget layer did not build

The ring was first a box that made its own `DecoratedBox3d` and adopted it, so
that it could write the panel's border and turn every frame. It laid out at
the right size and drew nothing, and the tree had no panel in it: the layout
tree under a `SceneLayout3d` is **mirrored** from the render tree, so every
pass handed the ring the widget layer's child list — empty — in place of its
own. It is now a frame box with a real widget child, and a leaf panel that
*is* a `DecoratedBox3d` and writes its own decoration. `docs/traps.md` has it,
because the imperative version of the same box works and nothing says why the
declarative one does not.

### 3. The drift tests found a transcription error the arithmetic tests could not

Flutter's head, tail and turn are private, so the plan transcribed them, and
the headless tests checked the ring against the transcription. The drift test
that reads `drawArc`'s arguments off a real `CircularProgressIndicator` found
the turn written as `rotation × 4π` where Flutter's is `× 2π` — an arc turning
twice as fast as Flutter's, and every other test agreeing with it. The bar's
lines are checked the same way, against the rectangles a real
`LinearProgressIndicator` draws, and were right first time.

### 4. `pressedAnimationDuration` is not public

The plan said two of the chip's figures were public in Flutter. Neither is:
the 75ms is a constant on the private `_RawChipState`, and the 1dp is
`_FilterChipDefaultsM3`'s. Both are still facts about a real chip — they are
what Flutter hands the `Material` inside a held one — so the drift test reads
them off that, which is the grade `DialogStyle3d` claimed and never had.

### 5. Flutter's thumb sequence is not a mirror image

The plan's reading of `_MaterialSwitchPainter` said the thumb holds its on size
for the first part of a run toward off. It does not: both directions stretch
**early** and hold **late** — the reverse sequence is traversed from its end
as the controller runs down — and the first version of the test asserted the
wrong one. And a `Cubic` is solved to a thousandth, so a thumb at rest read
through the curves came out a hair off its size and never lost its transform;
the size function pins its two ends exactly.

### 6. A switch told a new value animates to it

Tests that pumped a component twice — an off switch, then an on one — found
the thumb at the start of a run, because the second pump updates the same
`Switch3d` and it runs rather than jumps. That is the feature, and those tests
settle now; it is worth knowing for any test that re-pumps a switch.

### 7. The window found a defect in the layout package

Driving the gallery in a real window — scroll the settings to Save, press it,
photograph the spinner — produced a photograph of the settings list **back at
its top**, Save under the navigation bar and the spinner out of sight. The list
had lost its scroll position when the screen rebuilt. The cause was the
controller ownership rule: `controller = null` made a fresh position, and a
widget with no controller writes null on every update, so any `setState` above
a `SceneListView3d` without a controller sent it to the top. The layout
package's rule is corrected — null when a view already owns its position is no
change — with tests on all four views and one through a rebuild, and
[the plan that set the rule](../../flutter_scene_layout3d/plans/2026_08_25_scroll_controller_ownership.md)
says so. No headless test had scrolled a list and then rebuilt above it, and
the gallery's own rebuilds — starring a row — happen at the top of a list. The
headless gallery test for this phase pressed Save and passed; it never looked
where the list had gone. That is the third lane doing what `AGENTS.md` says it
is for.

### What phase 3 did not do

- **The colours do not cross-fade**, as planned: they change on the toggle's
  first frame. Doing it on the repaint tier wants a decoration channel into
  `Material3d` that nothing else needs yet.
- **Flutter's 2024 indicators**, with a gap, a stop dot and round caps, are not
  here. The arc's ends are a hard stop and are not anti-aliased; at the
  gallery's 20dp spinner nothing showed, and nobody has looked at a large one.
- **The chip's lift was not photographed.** `SelfDrive.tap` presses and lets
  go in one turn, and a press that short reports no highlight at all, so there
  is nothing to see; a held press is a harness change.
- Phase 2's safe area still has no lane that draws it.

## Phases 4 to 7

Written when each is picked up. What the map already knows about each, so
that writing it is an afternoon:

- **Phase 1's second finding moves `scrollable`** for `AlertDialog3d` out of
  phase 7 and into the next phase that touches a dialog.
- **Phase 5**'s `TabBar3d` meets the rounded clip that does not exist — an
  indicator inside a rounded bar — and should check whether the picture's
  answer, carving it in the panel's own signed distance field, reaches it.
- **Phase 6** needs a plan in the layout package first: no scroll view here
  has `reverse`, and Flutter starts a horizontal list at the right in right to
  left by reversing its axis. `Scrollbar3d` also owes a design answer — what a
  scrollbar is beside a plane the viewer may be looking at edge-on.
- **Phase 7**'s `RangeSlider3d` is two thumbs competing for one pointer, which
  is an arena problem rather than a second thumb.

Two things on the map's list are **not** phases here, and on purpose.
`CircleAvatar3d` was closed by the picture: a circular avatar is an
`SceneImage3d` with a radius, and the gallery has five. And
`PopupMenuButton3d` putting its menu back on the panel is the *off the edge*
question the map excludes by name; this plan does not answer it either.
