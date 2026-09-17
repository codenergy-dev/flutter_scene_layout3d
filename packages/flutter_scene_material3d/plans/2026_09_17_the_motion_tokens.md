---
status: completed
created_at: 2026-09-17T12:12:00Z
updated_at: 2026-09-17T15:45:00Z
commit: 96da2ebad2559275e80cf602240b77215c53cefb
---

# The motion tokens

The seventh token family, and the thing that makes the catalogue move. Picked
up from
[what a real application still needs](../../flutter_scene_layout3d/plans/2026_09_11_what_a_real_application_still_needs.md),
whose entry for it says the event that makes it ripe has happened: the layout
package now has `TimedRoute3dTransition` and `Motion3d`, so every overlay here
is one duration and one curve away from arriving instead of appearing, and
**nothing in the catalogue moves until this plan says which**.

## Why it was closed until now, and why that is over

The catalogue plan refused this family three times and gave the same reason
each time: *one animation is not a scale*. Phase 8 shipped the press ripple
with `InkRipple3dStyle` — a component style like `ButtonStyle3d`, holding
Flutter's own `InkRipple` figures — rather than opening a family for a single
customer, and its *deliberately left out* section says so in as many words.

That reasoning was right and it has expired. There are now six customers at
once, they are the six overlays, and they are the case the refusal was
waiting for: several components needing the *same* curve, where a per-component
style would be six copies of one decision.

## The family

`MotionScheme3d`, in `lib/src/tokens/motion.dart`, beside `ColorScheme3d`,
`Typography3d`, `ShapeScale3d`, `Elevation3d`, `Thickness3d` and
`StateLayerOpacity3d`. Two sets:

- **Sixteen durations** — `short1`…`short4`, `medium1`…`medium4`,
  `long1`…`long4`, `extraLong1`…`extraLong4`, from 50ms to 1000ms in fifty
  millisecond steps.
- **Nine easings** — `emphasizedAccelerate`, `emphasizedDecelerate`,
  `standard`, `standardAccelerate`, `standardDecelerate`, `legacy`,
  `legacyAccelerate`, `legacyDecelerate` and `linear`.

Carried on `Theme3dData.motion`, with `copyWith`, `==`, `hashCode`, a `lerp`,
and a `MotionScheme3dTween` beside the other six in `theme/tweens.dart`.

**The name is `MotionScheme3d` and not `Motion3d`** because `Motion3d` is
taken, by the layout package, for the value that says where a subtree stands
before it has arrived. The two meet constantly in this plan — a theme's
`motion` says *how long and on what curve*, a `Motion3d` says *from where* —
and two things a line apart may not share a name.

### The drift lane is the strong one here

The four transcribed families are checked against Flutter's own figures, and
the lanes differ in strength: `ColorScheme3d` reads public constants, while
`DialogStyle3d` has to render a real `Dialog` and read the `Material` out of
it because `_DialogDefaultsM3` is private.

This family gets the strongest lane there is. Flutter's `Durations` and
`Easing` are **public, generated straight from the Material token database**,
and every figure here is one of them — so `test/motion_test.dart` compares
value to value with nothing rendered and no reflection, and a token that moves
upstream fails here on the next `flutter upgrade`.

### What `lerp` does with a curve, and why

A duration interpolates. **A curve does not**, and cannot: `Curve` is a
function, and there is no meaningful value half way between `standard` and
`emphasizedDecelerate` that is itself a curve. So the easings **snap at the
midpoint** — `t < 0.5` takes `a`'s, otherwise `b`'s — which is what
`TextStyle.lerp` does with every discrete field it carries, for the same
reason.

It is worth knowing rather than hiding: a theme cross-fade changes its curves
half way through, once, and since the durations underneath are interpolating
continuously nothing visible jumps.

## The six overlays, and the two ways they arrive

Every overlay in the catalogue moves, and they split into two mechanisms
because they were built on two mechanisms.

**Four are routes** — `Dialog3d`, `Menu3d` (and `PopupMenuButton3d`),
`showBottomSheet3d` and `showModalBottomSheet3d`. They get a
`TimedRoute3dTransition` on the route, which needs
[a route that carries its own clock](../../flutter_scene_layout3d/plans/2026_09_17_a_route_that_carries_its_own_clock.md)
— **this plan's phase 0**, and a layout-package plan rather than a line item
here, which is the rule phase 0 established. One field on a navigator cannot
give a dialog 150ms and a sheet 250ms, and writing it per push closes an
already-open sheet on the dialog's clock.

**Two are bare overlay entries** — `Tooltip3d` and `SnackBar3d`. Neither is a
route and neither should become one: a tooltip blocks nothing and a snack bar
is a queue, and both would gain a barrier, a focus trap and a result future
they have no use for. They get an `AnimationController` in their own `State`
and a `SceneMotionTransition3d` around what they insert.

That costs each of them a `TickerProviderStateMixin` and, more interestingly,
**a removal that waits**. Today `_hide()` and `_dismiss()` take the entry out
in the same turn. They now run the clock back and remove on completion, and
the snack bar's queue has to be taught the difference: `_present()` refuses to
put the next bar up while an entry is still there, so the reverse has to chain
into it rather than run beside it. A bar closed while it is still arriving
reverses from where it got to, which `AnimationController.reverse` does for
free.

### Where the motion goes, and the scrim

The route plan's split is load-bearing here and this plan is the first thing
to actually pay for it: **a transition winds a clock and the content decides
what moves.** A catalogue modal builds its own scrim, inside the route's
content, through `modalFrame3d` — so `PageRoute3d.motion`, which wraps the
*whole* of what the builder returned, would slide the dim in with the dialog
it dims. The motion therefore goes inside `modalFrame3d`, around the child
only.

The scrim does fade, separately and on its own widget: a dim that snaps to
full strength while the dialog is still growing is the thing that reads
wrong. `modalFrame3d` gains an optional `animation`, and wraps the scrim's
decorated box in a `SceneFadeTransition3d` when it is given one.

### The figures

Durations are Flutter's own, transcribed, and all but one of them lands
exactly on an M3 duration token — which is the fact that makes them
expressible in this family rather than as six loose numbers:

| Overlay | In | Out | Flutter's constant |
| --- | --- | --- | --- |
| Dialog | `short3`, 150ms | `short3` | 150ms, `showDialog`'s `transitionDuration` |
| Menu | `medium2`, 300ms | `medium2` | `_kMenuDuration` |
| Bottom sheet | `medium1`, 250ms | `short4`, 200ms | `_kBottomSheetEnterDuration` / `_kBottomSheetExitDuration` |
| Snack bar | `medium1`, 250ms | `medium1` | `_snackBarTransitionDuration` |
| Tooltip | `short3`, 150ms | **75ms** | `raw_tooltip.dart`'s `_kDefaultAnimationStyle` |

**The tooltip's exit is the one figure with no token behind it**, and it is
kept rather than rounded. M3's duration scale starts at 50ms and steps by 50,
so 75ms is not on it; Flutter picked it anyway, because a tooltip leaving is
the shortest motion in the catalogue and 100ms reads as a lag on something
that is only ever getting out of the way. That is worth stating plainly,
because it says what the family is: **a vocabulary, not a cage.**
`InkRipple3dStyle` already holds 75, 225 and 375 and none of those is a token
either. A style may carry any duration it can defend; the family is there so
that the ones which agree say so.

**The curves deliberately do not follow Flutter's**, and this is the one place
this plan diverges knowingly. Flutter opens a dialog on `Curves.easeOut` and a
sheet on `Easing.legacyDecelerate`, both of which predate the M3 motion tokens
— `legacyDecelerate` says so in its own name. An overlay arriving is M3's
worked example of an enter transition, so they arrive on
`emphasizedDecelerate` and leave on `emphasizedAccelerate`, which is the
family this plan exists to adopt. Every one of them is a field on a public
style, so an application that wants Flutter's own curve writes it.

What each one does, as a `Motion3d`:

- **Dialog** — `Motion3d(scale: 0.85, opacity: 0.0)`, Flutter's own growing
  fade.
- **Menu** — `Motion3d.grow(from: 0.8)` about the corner it hangs from, which
  is the alignment the anchor already resolved.
- **Bottom sheet** — `Motion3d.fromBelow`, one whole height below the edge it
  comes from. The sheet is the reason `fraction` exists.
- **Snack bar** — `Motion3d.fromBelow` as well, and it is the one that shows
  why a fraction beats a figure: a two-line bar is taller and still starts
  exactly off the edge.
- **Tooltip** — `Motion3d.fade()`, which is what Flutter's does and all it
  should do.

## What this plan deliberately leaves out

- **The switch's growing thumb.** Phase 7 deferred it to "when the motion
  tokens land", and landing them is not enough. Material grows the thumb from
  16dp to 24dp as it crosses, and a size that changes every frame is a
  relayout every frame — the one tier this catalogue has kept off the
  interaction path throughout. It wants the thumb drawn at one size and
  *scaled* on the node tier, which is a change to how `Switch3d` builds its
  thumb rather than a duration, so it belongs with
  [the components a screen still needs](../../flutter_scene_layout3d/plans/2026_09_11_what_a_real_application_still_needs.md#the-components-a-screen-still-needs).
  The tokens it will read now exist, which is what this plan owed it.
- **The chip that lifts under a press.** Same shape, smaller: an elevation is
  a distance here, so a lift is a node-tier animation on a component whose
  press path is currently a pure token substitution. It is a component change
  with a token in it, not a token change.
- **Progress indicators, and a tab indicator that slides.** Both are named on
  the map as wanting the motion lane, and both are new components.
- **A theme that cross-fades.** `Theme3dDataTween` has existed since the
  token layer and now interpolates a seventh family with it. Nothing in the
  catalogue drives one, and the reason is in `Theme3dData.lerp`'s own
  dartdoc: writing the slot relayouts the subtree every frame.

## Verification

- `test/motion_test.dart` — the family: the figures against `Durations` and
  `Easing`, the midpoint snap, `copyWith`, equality, and the theme channel
  carrying it to both layers.
- The five overlay suites gain the arrival cases: that the thing is still in
  the tree part way through its departure, that it is gone when the clock
  finishes, and that `pumpAndSettle` terminates — which is the `Ticker`
  discipline the seams list warns about and the failure mode a hung suite
  would show as a timeout rather than as a wrong number.
- The gallery: `flutter test` there, and **a person opening a dialog and a
  menu**, because whether an arrival reads right is the third lane's question
  and not a probe's.

## What shipped

The family, the theme channel, all six overlays, and
[a route that carries its own clock](../../flutter_scene_layout3d/plans/2026_09_17_a_route_that_carries_its_own_clock.md)
under it. Green at **1254** in the layout package, **566** here and **5** in
the gallery, `dart analyze` clean across the workspace.

The gallery now has an overflow menu that opens a dialog and a bottom sheet,
and a tooltip on its search button, because five of the six arrivals had
nowhere a person could see them — the gallery had only a snack bar. That was
not on the plan and it is the reason two of the findings below exist.

## What the reasoning got wrong

**The plan's own design held.** The family is the shape it described, the
figures are the ones it tabulated, the two mechanisms are the two it named,
and the phase-0 split was necessary exactly as argued. What it did not see was
anywhere near the tokens.

- **The tooltip's 75ms exit was written down as a token and is not one.** The
  first draft of the table claimed every overlay duration lands on M3's
  scale. Checking it — the house rule, *verify before you write it down* —
  found that M3's scale steps by 50ms and Flutter's tooltip fades out in 75.
  The correction is in the table and it turned into the better sentence: this
  family is a **vocabulary, not a cage**, which `InkRipple3dStyle`'s 75, 225
  and 375 had been saying since phase 8 without anyone noticing.

- **`pumpAndSettle` is now load-bearing in nineteen tests, and a blanket
  substitution breaks four of them.** Making the catalogue move made every
  test that opened an overlay and asserted a position wrong, which was
  expected. What was not: `await tester.pump()` is doing *two different jobs*
  in those suites — "let the entry's subtree build", which is the one-frame
  rule and must stay one frame, and "let the thing finish arriving". Replacing
  all of them mechanically made the tooltip's wait tests fail, because
  settling advances the clock past a `waitDuration` the test was counting in
  milliseconds. They had to be read one at a time.

- **A moving box is pressable where layout put it, and that reaches the test
  library.** The node tier's contract was known and documented; what nobody
  had said is that `tap3d` and `isReachable3d` aim at where a box is **drawn**,
  because that is where a person aims. The two agree at rest and disagree for
  the length of an arrival, so a press at a growing menu's drawn centre lands
  on the item above. It is in `docs/traps.md` now, under *When testing a
  component headlessly*, and it is the first time the two halves of the
  motion and testing lanes have met.

- **The item that was never going to be the work: `PopupMenuButton3d` could
  not be pressed at all.** Putting a menu in the gallery — done so a person
  could *see* a menu arrive — found a component that laid out, drew, announced
  itself to a screen reader and did nothing. Two defects at once, and both are
  instances of rules this repository had already written down:

  1. **It had no outer `TapTarget3d`.** `Button3d` has had one since phase 2,
     outermost, with a null minimum that resolves to Material's 48dp. This
     button had none, so its whole reach was its child — a 24dp icon. A 24dp
     slab at the corner of a panel is small enough that a ray from a camera
     looking at that panel straight on, which arrives at an angle everywhere
     except the middle, misses it and lands on the app bar behind.
  2. **Its align sat outside its ink well**, which handed the well the loose
     constraints an align passes down, so the well shrink-wrapped its child's
     depth — and its child is an `Icon3d`, which is a glyph and has none. A
     tap target with no thickness is a degenerate slab that no ray
     intersects.

  Both are now `docs/traps.md` entries and `test/menu_test.dart` cases. The
  reason neither had been caught is worth stating: the menu's own suite built
  its trigger out of a `SceneSizedBox3d` with a depth, so every existing test
  passed. **The defect needed an `Icon3d`, which is what every real caller
  passes.**

- **And a menu at the trailing edge opens off the panel**, where a ray finds
  no surface at all. That is the deferred *off the edge* design question, met
  head on for the first time rather than in the abstract. It is still
  deferred — nothing chooses a corner for you — but `PopupMenuButton3d` now
  forwards the `menuCorner` and `anchorCorner` that `showMenu3d` has always
  taken, so a caller can say which way it opens. Choosing is the open
  question; being *able* to say was an oversight.

## The three that are still waiting

Unchanged from *What this plan deliberately leaves out*, and now with their
tokens in hand: the switch's growing thumb, the chip that lifts under a press,
and the progress and tab indicators. Every one of them wants a node-tier
answer rather than a duration, so they belong with
[the components a screen still needs](../../flutter_scene_layout3d/plans/2026_09_11_what_a_real_application_still_needs.md#the-components-a-screen-still-needs).

One thing this plan did **not** do and could have: a route's animation runs on
a bare `Ticker`, because `navigatorOf3d` builds its `Navigator3d` with no
`vsync`. That means `TickerMode` cannot mute an arrival with the subtree it
belongs to. For a two-hundred-millisecond overlay it is a small thing, and
closing it means giving `SceneOverlay3d`'s state a `TickerProvider` to hand
over — a layout-package change, and one worth doing when something longer than
an overlay animates.
