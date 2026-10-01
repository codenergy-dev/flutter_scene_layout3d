---
status: in progress
reason: phases 1 to 5 have landed — the last the segmented button, the tabs and the radio group; phases 6 and 7 are open, and phase 2's safe area has no lane that draws it
created_at: 2026-09-21T15:46:07Z
updated_at: 2026-10-01T22:55:00Z
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
| 4 | nothing, but more of it | `Badge3d`, `MaterialBanner3d`, `BottomAppBar3d`, `NavigationDrawer3d`, `ExpansionTile3d`, a snack bar's second line — **landed** |
| 5 | one choice over many options | `SegmentedButton3d`, `TabBar3d` and `TabBarView3d`, `RadioGroup3d` — **landed** |
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

## Phase 4: nothing new underneath, and more of it

*Written when the phase was picked up, against `e1f2931`.*

Six things, and the table's claim about them is that none needs anything the
catalogue does not already have: each is a `Material3d` with a token set, a
row or a column, and — for two of them — a clock. That claim is checked
below rather than assumed, because the last time this plan said "nothing
new", phase 3's ring needed a border painted by a gradient. **Every figure
is Flutter's**, read off `flutter/lib/src/material` at 3.47.1, and each
style's dartdoc says which grade it is — read off a laid-out Flutter widget,
read off a public API, or transcribed from a private constant — because
phase 1 found two token sets described as drift-checked that never were.

### `Badge3d`

A stadium at the top-end corner of whatever it decorates: 6dp and no label,
or 16dp tall with a `labelSmall` count in it, `error` on `onError`.
`Badge3d.count` caps at `maxCount` and writes `999+`, as Flutter's does.

It is **not** a `Stack3d` with a `Positioned3d` in it, which is the first
thing to write and the wrong one. A stack caps a positioned child's unpinned
axes at its own size, so a three-digit badge on a 24dp icon would be squeezed
to 24dp wide — and an icon is a glyph with no depth, so the badge's slab would
be squeezed to none. Flutter meets the first half of that with a render
object of its own, `_RenderBadge`, which fills the stack and lays the badge
out unconstrained; this does the same, with a private box under a
`Positioned3d` that fills the stack and places the badge by Flutter's
arithmetic — `alignment.alongOffset(size − widthOffset)` plus `(4, 4)` mirrored,
minus half the badge's height for a labelled one.

The depth is the part with no Flutter equivalent. A badge is drawn **over**
its child, and here that is a distance: the icon under it is a glyph whose
wall grows toward the viewer by a tenth of its size, so a badge resting on
the icon's plane would have the icon's corner standing through it.
`BadgeStyle3d.depthStep` puts the badge's back face clear of a 24dp icon's
wall, on the node tier, through the stack's own step.

The label grows with type, as Flutter's does, and stays a stadium: at a
large setting a one-digit badge is taller than it is wide, and Flutter's
`_IntrinsicHorizontalStadium` widens it to a circle. Here that is a minimum
width equal to the height, which a box that knows the label's laid-out height
can state and a `build` method cannot.

It announces nothing unless told, which is `Icon3d`'s rule and for the same
reason: a `Semantics3d` gathers nothing, and a badge does not know what it is
counting. `semanticLabel` puts one on it.

### `MaterialBanner3d`

Flutter's banner, static: a `surfaceContainerLow` strip with an optional
leading widget, `bodyMedium` content clamped to 1.5× type, and its actions
either beside the content — one action, `start: 16, top: 2` — or in a 52dp bar
below it, at the trailing edge, `start: 16, top: 24, end: 16, bottom: 4`. A
divider under it only at elevation zero, and Flutter's 10dp bottom margin at
any other elevation, which is room for a shadow Flutter draws and this does
not; it is kept because it is space a ported screen already lays out around.

**Static, and that is a boundary rather than an omission.** Flutter shows an
animated banner through `ScaffoldMessenger.showMaterialBanner`, which puts it
in a scaffold slot under the app bar. A `Scaffold3d` has no such slot and a
`ScaffoldMessenger3d` has no way to reach one; both are a change to the
scaffold rather than a component, and a banner written into a body's column
is what Flutter's own documentation calls the "static banner for backwards
compatibility". The messenger half is left out, and the dartdoc says so.

`MaterialBanner3d.text` takes the content as a string and announces it, for
`ListTile3d.text`'s reason.

### `BottomAppBar3d`

An 80dp `surfaceContainer` bar at elevation level 2, with 12dp by 16dp of
padding, grown by the bottom inset the way `NavigationBar3d` is — Flutter's
`SafeArea` inside a `SizedBox(height: 80)`. It goes in
`Scaffold3d.bottomNavigationBar`, which is where Flutter puts it, and it is
`thickness.structural` for the reason every bar is.

**No notch.** Flutter's M3 default shape is an `AutomaticNotchedShape` around
a plain rectangle with no guest, which draws no notch at all; a notch is a
hole cut out of a panel, and a hole is not a convex clip or a corner radius,
so there is nothing here that could draw one. The `shape` parameter is not
taken. Nor is `FloatingActionButtonLocation.endContained`, which is how
Flutter's own sample sits a button *inside* the bar: `Scaffold3d` has one
location, Flutter's default `endFloat`, and a second is a scaffold change.

### `NavigationDrawer3d`, and the drawer it is made of

Three exported things, because Flutter's are three:

- **`Drawer3d`**, the surface: 304dp wide (Flutter's `_kWidth`; M3's spec
  says 360, and a ported screen lays out at 304), `surfaceContainerLow`,
  level 1, the two corners away from its edge rounded 16dp — `shape.large` —
  and full height. It is `thickness.structural`, for the reason a sheet is.
- **`NavigationDrawer3d`**, which is a `Drawer3d` holding an optional header,
  a scrolling list and an optional footer, with Flutter's own API: `children`
  is a list of widgets, and the ones that are a
  `NavigationDrawerDestination3d` are numbered and selected by
  `selectedIndex` — so a ported drawer keeps its section headings and
  dividers between destinations exactly where they were.
- **`showDrawer3d`**, which slides either one in from an edge over a scrim and
  returns what it is popped with.

The destination is a 56dp stadium-shaped tile with 12dp of padding either
side, an icon 16dp in and a `labelLarge` label 12dp after it — and **its
indicator is its own colour**. Flutter's indicator is a 336 by 56 pill in a
tile only 280 wide, so it fills the tile; here that is the destination's own
`Material3d` taking `secondaryContainer` when selected, and no second slab,
which is the navigation bar's pill without the depth step it needed. The
label is a string, for the reason the bar's is.

**A drawer is an overlay here, and a scaffold slot in Flutter**, and that is
a decision this package made before this phase:
`Scaffold3d`'s own dartdoc says sheets, dialogs and menus are not slots,
because an overlay belongs to the surface so that it can outlive the screen.
So there is no `Scaffold3d.drawer` and no `openDrawer`; there is
`showDrawer3d`, which is `showModalBottomSheet3d` on the leading edge with
the drawer's own figures — and the leading edge is the right one in right to
left, which a sheet's `Sheet3dEdge.left` is not. `DrawerAlignment3d` says
start or end, as Flutter's `DrawerAlignment` does.

The scrim is **black at 54%**, Flutter's `Colors.black54`, not Material's
32% — a drawer dims more than a dialog in Flutter and a port should not
notice the difference. The 246ms of Flutter's `_kBaseSettleDuration` is
`medium1` here; Flutter opens with a critically damped spring rather than a
curve, and the emphasized curves are the catalogue's nearest word for it.

What is not here: the edge swipe that opens a drawer, which is a drag lane
item like a sheet's handle; and the drawer's announcement, Flutter's
localized "Navigation menu", which is a string the catalogue would invent and
[the language item](../../flutter_scene_layout3d/plans/2026_09_11_what_a_real_application_still_needs.md#a-catalogue-that-speaks-more-than-one-language)
owns. `semanticLabel` names the route, as a dialog's does.

### `ExpansionTile3d`

A `ListTile3d` whose trailing chevron turns half a turn and whose children
are revealed under it, over Flutter's 200ms on `Curves.easeIn`: the title
stays `onSurface`, the chevron goes from `onSurfaceVariant` to `primary`,
and an expanded tile has a rule of `outlineVariant` above and below it —
Flutter's border in `dividerColor`, which in M3 is that role.

**This is the first component in the catalogue whose animation is a size
that really changes**, and that is the design question. Every motion so far
has been kept off the relayout tier, because none of them changed a size. A
reveal does: the tile grows, and every row under it moves, and only layout
can move them. Flutter relayouts too. So the reveal is tier 3, honestly, and
the phase's claim for it is the narrower one that still matters — **it lays
out on every frame and builds on none**: a private box listens to the
controller and writes an `Align3d`'s `heightFactor` inside a `ClipBox3d`, and
no label is measured again. The chevron's half turn is the node tier, a
rotation about its own centre. The tile rebuilds once when it starts and once
when a collapse finishes, which is when the children leave the tree, as
Flutter's do unless `maintainState`.

Two things a reader should know. **A label straddling the reveal's edge draws
whole** for the frames it straddles: the panel shader cuts at a clip plane
and the glyph shader does not, so a half-revealed row has its panel cut and
its text culled only once it is wholly outside — the same thing a scrolling
list here does at its edge. And it announces `expanded` on the tile's node,
which Flutter publishes as a localized hint string; the flag says the same
thing without inventing one.

It does not take Flutter's `ExpansibleController`, which postdates this
package's Flutter floor of 3.29; `initiallyExpanded` and
`onExpansionChanged` are the API until the floor moves, and moving it is the
user's call rather than this phase's.

### A snack bar's second line

`SnackBar3d` lays its message out in a row that shrink-wraps, so a message
longer than the bar is one line that overflows rather than two that wrap. The
fix is Flutter's arrangement: the message is flexible and wraps, and an
action wider than **a quarter of the bar** — Flutter's
`actionOverflowThreshold`, measured with a `TextPainter` in `build` exactly as
Flutter measures it — goes on its own line under the message, at the trailing
edge, with the message wrapping in 60% of the width above it. The action's
label is `labelLarge`, which is what Flutter's `TextButton` draws it in; it
was `bodyMedium` here, in the message's style.

The swipe that dismisses a bar stays out, as the catalogue plan left it.

### What it does not do

**`AlertDialog3d.scrollable` stays where phase 1 put it**, in the next phase
that touches a dialog: a drawer is a modal route and not a dialog. The
`DialogStyle3d` and `MenuStyle3d` drift test phase 1 found missing is a
different matter — this phase touches two overlays, the snack bar and the
drawer, and phase 1 said that was the phase to write it in. It is written.

### Tests

- Each style against Flutter's figures, by the best grade available, in a
  `phase_4_defaults_test.dart` beside the existing drift tests — and the
  dialog's and the menu's, read off a real `Dialog` and a real popup menu.
- The badge: the corner it sits at in both directions, the 6dp dot, a label
  wider than the icon it is on, `999+`, a stadium at twice the type, the
  depth step clearing a default icon's wall, `isLabelVisible`.
- The banner: both arrangements, the divider at elevation zero only, the
  margin, the announcement.
- The bottom app bar: the height, the role, the safe area, and a slot in a
  `Scaffold3d` whose buttons can be pressed.
- The drawer: the width and shape at each edge in both directions, the
  destinations numbered past a heading, the selected one's colour, a press
  calling back with the right index, the route's arrival from the leading
  edge, the scrim, and Escape and a tap outside closing it.
- The expansion tile: collapsed and expanded heights, the reveal part way,
  **nothing built across the run and the paragraph count unmoved**, the
  chevron's turn, the rules, the children leaving the tree after a collapse,
  `maintainState`, `expanded` in its semantics, and right to left.
- The snack bar: a long message wrapping to a second line, a wide action
  moving under it, a narrow one staying beside it.

### The gallery

The inbox's navigation destination carries a badge counting the messages
nobody has opened, which goes down as they are opened. The app bar's leading
slot opens a navigation drawer with the same two destinations. The settings
screen shows a banner while notifications are off, and an expansion tile at
its foot. The table screen gets a bottom app bar whose buttons lift the
cards, lying flat on the ground with everything else. And composing a
message says so in two lines.

## What phase 4 found

All six shipped, and the claim the table makes for them held: **nothing in
the layout package changed**. What each needed underneath it was a private box
or two in the catalogue — the badge's placement and its stadium, the reveal
and the chevron's turn. The Material suite is **799**, up from 714; the layout
suite **1311**, unchanged; the gallery **12**, up from 8; and the photograph
lane takes four more frames. Seven findings, and the first is larger than the
phase.

### 1. A press on a control's padding went nowhere, everywhere

The bottom app bar's test pressed its leading icon button through the camera
and the press did nothing, though `isReachable3d` said the button was there.
The same was true of an app bar's leading button and its actions, and not of
a button in the body. The hit path said why: the ray reached the button's
**panel** and nothing inside it. A `DecoratedBox3d` answers a hit on its own
account, and every button, chip and list tile in the catalogue put its ink
well *inside* `Material3d.padding` — so the padding was a rim that took a
press and did nothing with it. Measured across every interactive component's
face, the floating action button answered only at its middle, a 72dp filled
button not 14dp from its centre, a list tile and every labelled tile not in
their 16dp and 24dp margins, a navigation destination not beside its pill.
Cards, the selection controls, menu items and the new drawer were whole.

**It had been true for nine phases, and nothing could have said so**, because
every press in every suite was aimed at a control's centre. The corner of a
lifted bar is where it surfaced, because there a press through the camera
lands off-centre: a slot is drawn its lift in front of where it is pressed,
which `docs/traps.md` records for overlays, and an elevated bar adds its own.
That drift is still there and is not this phase's to close; with the whole
face answering, it no longer lands on a dead rim.

The fix is Flutter's arrangement: the padding goes inside the well, and a
destination's well fills the destination. `test/the_whole_face_test.dart`
presses ten kinds of control a few logical pixels inside each edge of its
face. The README's own example of `Material3d` had the rim and teaches the
other way now; `docs/traps.md` has the rule under *Pointers*.

### 2. Flutter's banner does not read its own token table

The plan read `_BannerDefaultsM3`'s elevation of 1 as a banner's default,
and so expected a margin under it rather than a rule. The defaults do pass
1.0 — and `MaterialBanner.build` reads
`widget.elevation ?? bannerTheme.elevation ?? 0.0`, never the defaults' figure.
A Material 3 banner in Flutter is flat, with its rule and no margin, and the
drift test found it by reading the `Material` a real one builds.
`MaterialBannerStyle3d.elevation` is zero, and says why.

### 3. An open expansion tile's rules are `outline`

The plan said `outlineVariant`, which is a `Divider`'s colour. Flutter's tile
draws its border in `ThemeData.dividerColor`, and Material 3 sets that to
`outline`. The drift test read both. A third, smaller one of the same kind:
`Colors.black54` is `0x8A` alpha, a hair over the 0.54 written first.

### 4. A drawer's destinations were inside the drawer

The first photograph of the open drawer showed its header, an inbox badge,
and nothing else. A list centres its items in depth unless it is told
otherwise — `ListView3d`'s deliberate default, for lists of objects — and the
drawer is an 8dp slab, so every destination sat 3.5dp behind the face that
hid it. The badge showed only because a badge is lifted clear of its icon.
**Every headless test of the drawer passed**, because none asked whether the
rows stood on it; one does now, with `standsOnItsPanel3d`, and failed before
the fix. That is the third lane doing the thing `AGENTS.md` says it is for,
and `docs/traps.md` has the list's default beside the flex's.

### 5. The table cannot hold two bars

The gallery's table is 217dp from front to back. An app bar and Flutter's
80dp bottom bar leave its cards too little room for their three lines, and a
floating action button at `endFloat` above the bar stands over the third
card. So the bottom app bar replaced the table's app bar, with the button
inside it at the trailing end — Material 3's contained arrangement, which
Flutter calls `endContained` and `Scaffold3d` does not have, written out by
hand in the bar's row. The plan said the table "gets a bottom app bar"; it
got one instead of its other bar.

### 6. The reveal is the first relayout on purpose, and it costs what it should

The expansion tile lays out on every frame of its 200ms, which is the first
motion in the catalogue to do so and the honest tier for it. The test watches
at the source, with `watchFrames`: frames on which something was laid out —
not empty, and it should not be — no widget rebuilt, and
`debugTextParagraphCount` unmoved. The reveal opens from its middle, because
Flutter's is an `Align` at its default centre.

### 7. The drift test phase 1 owed found nothing wrong with the dialog or menu

`test/phase_4_defaults_test.dart` reads `DialogStyle3d` and `MenuStyle3d`
off the `Material`s a real `Dialog` and a real popup menu build — colour,
elevation, corner, minimum width, item height — and every figure agreed. Their
dartdoc no longer has to apologise for a test that did not exist.

### What phase 4 did not do

- **No render probe asks a question of any of the six.** The badge standing in
  front of its icon and the drawer's destinations on its face are photographed
  and asserted headlessly, not probed; a probe that the badge's colour wins at
  its centre over a turned icon would be the sharp form of the first.
- **The expansion tile is not photographed open.** It is at the foot of the
  settings list, below the fold of the panel, and the lane does not scroll.
- **The banner through the messenger**, the drawer's **edge swipe**,
  `ExpansibleController`, the bottom app bar's **notch** and
  **`endContained`**: each is in its dartdoc with its reason.
- **`AlertDialog3d.scrollable`** is still waiting for a phase that touches a
  dialog.
- Nobody has run the gallery in a window on this phase; the photographs are
  the lane that looked.

## Phase 5: one choice over many options

*Written when the phase was picked up, against `9e78206`.*

Three components and one shape between them: a set of options of which the
screen holds one — or, for a segmented button, a few — and a row that shows
which. **Every figure is Flutter's**, read off `flutter/lib/src/material` and
`flutter/lib/src/widgets` at 3.47.1, and each style's dartdoc says which grade
it is, as phase 4's do. The table says this phase needs nothing underneath it;
that is checked below rather than assumed, for the reason phase 4 gave.

### `SegmentedButton3d`, and where the rounded clip actually is

A stadium outlined in `outline`, cut into equal segments by 1dp rules, the
chosen ones filled `secondaryContainer` with a check in front of their label.
`ButtonSegment3d` carries a value, a label **string** — for
`NavigationDestination3d`'s reason — an optional icon, a tooltip and an
`enabled` flag; `selected` is a `Set<T>` and `onSelectionChanged` gets the
next one, with Flutter's `multiSelectionEnabled` and `emptySelectionAllowed`
deciding what a press may do, transcribed from `_handleOnPressed`.

**This is where the rounded clip is, and the map put it on the tab bar.**
Flutter draws every segment as a *square* `TextButton` and clips it to the
inner path of the stadium, so the first and last fills follow the outline's
curve. There is no rounded clip here. The picture's answer reaches it anyway:
a segment is a `Material3d` of its own — it needs one for its wash — so the
end segments are carved with the stadium's radius on their **outer** corners
and square on the inner ones, which is the clip expressed in the panel's own
signed distance field. Start and end follow the reading direction, so in
right to left the first segment is rounded on its right.

The outline and its rules are one transparent slab **in front** of the
segments, ignoring the pointer — Flutter paints the border after its
children, and a fill drawn to the stadium's own edge is then covered by the
outline's band exactly where Flutter's clip would have stopped it.

**The reach is in the layout, as Flutter's is**, and that is new in the
catalogue. Every other control here is laid out at its visible size and
answers a finger 48dp tall through a `TapTarget3d` outside it, and a press in
that margin arrives at the control's centre. For a button of three segments
the centre is the *middle* segment, so a press 4dp above the first would pick
the second. Flutter's `SegmentedButton` lays itself out 48dp tall with the
outline in the middle 40 — `tapTargetVerticalPadding` — and so does this: each
segment's target is inside a 48dp slot, and is re-aimed at its own centre.

Equal widths are Flutter's arithmetic: every segment as wide as the widest,
which is a row of flexible children inside an intrinsic width, unless
`expandedInsets` asks the button to fill its width.

### `TabBar3d`, `Tab3d` and `TabBarView3d`

**The controller is Flutter's own `TabController`**, and `DefaultTabController`
works unchanged. Neither has a render object in it — a `ChangeNotifier`
around an `AnimationController`, and an inherited widget that hands one down
— so nothing about a plane stands in the way, and a ported screen keeps the
controller it already has. Phase 4 refused `ExpansibleController` because it
postdates this package's Flutter floor; `TabController` does not.

The bar is Flutter's primary and secondary variants: 46dp tabs plus the 2dp
Flutter reserves under them, `titleSmall` labels, `primary` or `onSurface`
for the chosen one and `onSurfaceVariant` for the rest, a 1dp
`outlineVariant` rule across the foot, and an indicator in `primary` — 3dp
and as wide as the label with its top corners rounded, or 2dp and as wide as
the tab. A tab with an icon and a label is 72dp, and the others in its bar
are padded to match.

**The indicator slides on the node tier.** Its position and width are facts
about layout — where each tab ended up, how wide each label measured — so a
private box laid out after the row reads the tabs' boxes and writes a
translation and a stretch, from its own `performLayout` and then from the
controller's animation on every tick: `docs/traps.md`'s answer for a bar that
fills its parent, applied to a bar that moves. The primary indicator stretches
the way Flutter's elastic one does, transcribed from `_applyElasticEffect`;
the secondary one is linear. It is laid out at the chosen tab's width, so at
rest it is exact and only its 3dp corners stretch in flight, the price
`Switch3d`'s thumb pays.

**The labels change colour at once**, where Flutter cross-fades them over the
slide — the same decision the switch made: a colour is a token, and fading
one is a rebuild a frame.

`TabBarView3d` is a `ScenePageView3d` and Flutter's synchronisation: a press
on a tab animates the pages with the controller's duration on `Curves.ease`,
and a swipe writes the controller's `offset` as it goes and its `index` when
it settles. **Right to left reads the pages backwards** — page one at the far
end of the view — which is what Flutter's reversed axis amounts to for a view
whose length is known.

What it does not do, each in its dartdoc: **`isScrollable`**, which is a
horizontal scroll view that has to start at the right in right to left and so
belongs to phase 6 with `reverse`; the tab's localized "Tab 1 of 3", which
the language item owns; and Flutter's swap of the page between two
non-adjacent tabs, which is a nicety over a straight slide.

### `RadioGroup3d`

Flutter's `RadioGroup`, which since 3.35 is how a set of radios is written:
the group holds `groupValue` and `onChanged`, and every `Radio3d` and
`RadioListTile3d` of the same type below it takes them from there. **Their own
`groupValue` and `onChanged` become optional**, as Flutter's are deprecated —
inside a group the group wins, as `_effectiveRegistry` decides in Flutter —
and both gain Flutter's `enabled`, which is how one option in a group is
switched off.

The keys are the point of it. **An arrow moves the choice and the focus
together**, to the next enabled radio in tree order and round the end — left
and up are previous, right and down next, whatever the reading direction,
because that is Flutter's map. It is a `SceneShortcuts3d` around the group,
for the reason `docs/traps.md` gives about bindings for a surface, with an
action that is enabled only while a radio of the group holds the focus, so
an arrow on anything else in the group goes on up the walk. Space is already
the radio's own activation.

Flutter's group also makes only the chosen radio a Tab stop. **That needs
`Focus3dTraversal` to skip a box, and it cannot**; Tab stops on every radio
here, and the dartdoc says so.

### Tests

- Each style against Flutter's figures, read off a laid-out widget where one
  exists, in a `phase_5_defaults_test.dart`: the segmented button's 48dp
  height and equal segments, its colours on the `Material` each segment
  builds; the tab bar's 48dp and 74dp heights, the label colours and the
  indicator's thickness and width at rest.
- The segmented button: one fill on the chosen segment, the outer corners
  carved and the inner ones square in both directions, the outline in front
  and ignoring the pointer, single and multiple selection, an empty selection
  refused or allowed, a press 4dp above a segment choosing *that* segment,
  disabled colours, and what it announces.
- The tab bar: a press animating the controller, the indicator at rest under
  the chosen label and part way between two in flight, **nothing laid out
  between the frames a change starts and ends, and nothing built**, the
  elastic stretch, right to left, the 72dp tab, and the announcements.
- The view: a press on a tab turning the page, a swipe moving the
  controller's offset and settling its index, and right to left.
- The group: a radio and a tile taking their value from it, an arrow moving
  the choice and the focus and wrapping, a disabled radio skipped, and an
  arrow outside the group's radios going on up the walk.
- `the_whole_face_test.dart` grows a segment and a tab.

### The gallery

The settings screen gets the three of them. Tabs across its top — the
controls on one page and the appearance on the other — the dark theme as a
segmented choice between light and dark, and a group of three radio rows
choosing the order the inbox is sorted in, which the sort sheet in the
overflow menu now sets too.

## What phase 5 found

All three shipped. The table said this phase needed nothing underneath it,
and that held for the components — a private box for the tab bar and a
private scroll position for its pages — and **not for what a page view
showed**: one change to the layout package, planned as
[a label wholly outside its window](../../flutter_scene_layout3d/plans/2026_10_01_a_label_wholly_outside_its_window.md).
The Material suite is **852**, up from 799; the layout suite **1318**, up
from 1311; the gallery **13**, up from 12; and the photograph lane takes two
more frames, the settings' first tab and a tab change half way. Nine findings, and two of them were found by the window and
nothing else.

### 1. The rounded clip was the segmented button's, and the picture's answer reached it

The map put the clip that does not exist on the tab bar. The tab bar never
meets it: its indicator is a slab of its own with its own top corners, and
nothing in it is cut by anything else. The segmented button is where it was —
Flutter draws square segments and clips them to the inside of the stadium —
and the answer a picture on a panel found reached it without a change: a
segment needs a `Material3d` of its own for its wash anyway, so the end ones
carry the stadium's radius on their outer corners and the fill comes out the
shape Flutter's clip leaves. The photograph shows the chosen end following the
outline's curve.

### 2. A reach that arrives at the centre picks the middle segment

Every control in the catalogue is laid out at its visible size and answers a
finger in a 48dp reach, and a press in the margin is re-aimed at the
control's centre. For a control of three choices the centre is the middle
one. The segmented button lays out 48dp tall, as Flutter's does, with each
segment's target inside a slot of that height — the first control here whose
reach is in its layout. The test that presses 4dp above the first segment
fails with the slot at 40dp, which was checked. `docs/traps.md` has it under
*Pointers*.

### 3. Flutter's controller needed nothing

`TabController` and `DefaultTabController` are used as they are. The plan
reasoned that neither has a render object and so nothing about a plane stood
in their way, and that is all it took; a `DefaultTabController` sits above
the gallery's settings inside the surface.

### 4. A tab bar cannot wear its role here, and only the window could say so

The first build had the bar publish Flutter's `tabBar` role and the radio
group its `radioGroup`, as Flutter's do, and every headless test passed. The photograph lane ran the gallery with semantics on and the
frame would not build: **"a TabBar cannot be empty"**. Flutter checks that a
tab bar's semantics children are tabs, and a `Semantics3d` has no children in
that tree — each one is a node on its own scene node, which is
`docs/traps.md`'s *Semantics* section from another side. No headless test
reaches it, not `pumpComponent` and not the screen harness's `pumpSurface3d`
with `ensureSemantics()`: both were tried. The bar publishes nothing now, the
group likewise — a `radioGroup` node passes the check only because it is
empty, which is the same absence — and the tabs keep `tab`, which asks
nothing of its parent. This is the third time a frame that would not build
with semantics on was found by running the gallery.

### 5. A page half across its window drew its labels outside the panel

The photograph of a tab change half way showed the page leaving the window
with its cards cut cleanly at the edge and its labels — "Notifications",
"Volume", "Reset", "About" — floating in the room beside the screen. A
panel is cut at a clip plane by its shader and a glyph reads none, which
`docs/traps.md` already said; a list hides an item once the item is wholly
outside, and the item here is a page. So a label could be drawn up to a
page's width outside the window for every frame of every turn. The change is
in the layout package, because it is a fact about labels and windows rather
than about tabs: a `Text3d` or a `RichText3d` wholly outside its clip hides
itself, from the `refreshClipRegion` that `place` already calls down a moved
subtree, testing where its letters are rather than its box, because the
second photograph still had "Volume" outside — a stretched label whose box
was half in. And `TabBarView3d` clips its pages to its own window now, as
Flutter's does by default: a scroll view here does not clip on its own,
which the first layout test found by leaving a bare page view's label
visible.

### 6. A drag takes the nearest scroll view, whatever its axis

A page of a `TabBarView3d` that is a list does not swipe: a drag grabs the
innermost `Scrollable3d` on its path and moves it along that view's own axis,
where Flutter's recognizers compete by direction. The gallery's two settings
pages are both lists, so they turn only from their tabs. It is a change to
`Layout3dPointer` and not this phase's; the dartdoc, the README and
`docs/traps.md` say so.

### 7. A page view of known length can be read backwards

The plan said right to left reads the pages backwards, and the arithmetic was
a renumbering: page one laid out last, the view opened at its far end. That
needs the view to open on a page it has not measured yet, and a private
scroll position does it by moving the offset when the window first gets an
extent — the sliver viewport lays the pass out again when the metrics move
the offset, so the first frame is already on the right page. **Phase 6 still
needs `reverse`**: a scrollable tab bar and a carousel are scroll views whose
content is not a set of equal pages.

### 8. The indicator is laid out by its parent, at its resting width

A positioned child of a `Stack3d` was the first arrangement, and it was
wrong before it ran: a box whose constraints have not changed is not laid
out again, and the indicator's width depends on the row beside it rather than
on anything in its constraints. So the bar is a private box of its own that
lays the row out, then hands the indicator **tight** constraints at the
chosen tab's width — the parent decides, which is the protocol's own answer.
The plan said a change lays out on the frame it starts and the frame it
ends; it lays out on the first only. The end notifies, and the index it
names is the one already laid out. The bar rebuilds on both, for its labels.

### 9. `Radio3d.enabled` changed shape

It was a getter answering whether `onChanged` was given; it is Flutter's
`bool?` constructor argument now, which is how one option of a group is
switched off. The changelog says so, because a caller reading it gets a
different answer.

### And two things seen that are not this phase's

The tab bar's rule runs the body's full width, and with the panel turned it
hangs past the scaffold's backing at one side. It is not the rule: the body
slot stands steps in front of the backing, and anything edge to edge in the
body does the same — the inbox's gradient header shows it too, inset by its
padding. A thin full-width line is just the first thing that makes it easy to
see.

And mid-turn, the volume card's progress bar left a short stroke of its fill
outside the window while its track was cut. The fill is a full-length bar
scaled on the node tier, and a clip plane is expressed in the box's layout
frame, which the node tier is outside of — the same thing `docs/traps.md`
says about a depth clip and an elevation. A slider's fill would do the same.

### What phase 5 did not do

- **`isScrollable`**, which needs `reverse`; the tab's localized **"Tab 1
  of 3"**; and Flutter's **swap** of the page between two tabs a press jumps
  across. Each is in the dartdoc with its reason.
- **Tab stops on every radio** in a group, where Flutter's stops on the
  chosen one: `Focus3dTraversal` cannot skip a focusable box.
- **No vertical segmented button**, and a disabled segment's stretch of
  outline is drawn in the enabled colour.
- **No render probe** asks a question of the carved segment, the indicator
  or a culled label; all three are photographed and asserted headlessly.
- **A label straddling a window's edge still draws whole**, which needs the
  glyph material to read clip planes.
- Nobody has run the gallery in a window and *used* the tabs; the photographs
  are the lane that looked.

## Phases 6 and 7

Written when each is picked up. What the map already knows about each, so
that writing it is an afternoon:

- **Phase 1's second finding moves `scrollable`** for `AlertDialog3d` out of
  phase 7 and into the next phase that touches a dialog. Phase 4 did not, and
  neither did phase 5.
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
