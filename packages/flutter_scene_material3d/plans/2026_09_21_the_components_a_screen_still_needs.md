---
status: in progress
reason: phase 1 has landed — the alert dialog, the checkbox's third state and the three labelled tiles; phases 2 to 7 are open, and phase 1 was only tried headlessly, not in a window
created_at: 2026-09-21T15:46:07Z
updated_at: 2026-09-21T16:00:28Z
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
| 1 | nothing | `AlertDialog3d`, the checkbox's third state, `CheckboxListTile3d`, `SwitchListTile3d`, `RadioListTile3d` |
| 2 | the safe area, and type that grows | `Scaffold3d` consuming `MediaQuery3d.padding`; a control that grows with its label |
| 3 | the node tier, with a clock | `LinearProgressIndicator3d`, `CircularProgressIndicator3d`, the switch's growing thumb, the chip's press lift |
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

**It was not looked at in a window.** The gallery's settings rows and about
dialog changed, and the headless suite and `standsOnItsPanel3d` are green over
them; nobody has run the gallery or the photograph lane on these changes yet.
The render-probe lane has no scene for any of the new components either — the
arrangement is layout and is asserted headlessly, and nothing in this phase
draws in a new way, but the icon glyph centred above a title and a switch
drawn without its ink well are both new pictures.

## Phases 2 to 7

Written when each is picked up. What the map already knows about each, so
that writing it is an afternoon:

- **Phase 1's second finding moves `scrollable`** for `AlertDialog3d` out of
  phase 7 and into the next phase that touches a dialog.
- **Phase 2** owns what
  [a screen that knows how big it is](../../flutter_scene_layout3d/plans/2026_09_16_a_screen_that_knows_how_big_it_is.md)
  deliberately left: whether an app bar stops at the status bar or is drawn
  under it is a component decision with tokens attached. A ported screen
  writes `SceneSafeArea3d` itself until this is taken.
- **Phase 3**'s motion is all on tiers that exist. A thumb growing from 16dp
  to 24dp is drawn at one size and scaled on the node tier, which the hero now
  has a shipped example of; a chip's lift is a distance on the node tier; an
  indeterminate progress indicator is a timeline with no layout in it, the
  ripple's shape.
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
