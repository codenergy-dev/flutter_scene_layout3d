---
status: completed
created_at: 2026-09-16T19:40:00Z
updated_at: 2026-09-20T16:00:00Z
commit: 503dbae1329ae1e73f0f31304a6720ae0a56ae15
---

# A route that arrives instead of appearing

The eighth plan off
[what a real application still needs](2026_09_11_what_a_real_application_still_needs.md),
and the first of the motion lane. The four items the map says the first real
port will demand are closed; this is the one the map pairs with
[the motion tokens](../../flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md)
in the catalogue, and it is the half that has to exist first, because a token
is a duration and a curve and there is nothing here for either to drive.

The map's sentence for it is the one worth keeping in view while building it:
**movement is most of what a scene has to offer over a picture**, and a
catalogue that does not move is spending the cost of 3D without collecting
the benefit.

## What is actually missing

Checked at `503dbae`, against a green 1212/545/4.

- **`Route3dTransition.none` is the only implementation that ships.** The seam
  was left on purpose and is documented as a seam: `Navigator3d.transition`
  takes one, `push` calls `forward` without awaiting it, and `pop` awaits
  `reverse` *before* the entry is taken out — so a leaving route is on screen
  for the whole of its animation. Everything about the plumbing is right and
  nothing fills it. A dialog, a menu, a bottom sheet and a snack bar each
  appear and disappear between two frames.
- **A route has no clock.** `Route3d` carries a completer, a navigator, an
  entry and a `_popping` flag, and nothing that a piece of content could read
  to know how far in it is. Flutter's `ModalRoute.animation` is the thing a
  transition builder is written against; there is no analogue here.
- **And there is no box that moves a subtree by a stated amount.**
  `NodeTransform3d` drives `nodeOffset`/`nodeTransform` from an
  `Animation<Offset3d>`/`Animation<Matrix4>`, which is the right tier and the
  wrong altitude for this: a caller who wants "come up from your own height"
  or "grow from 85% about your centre" has to know the box's size, and the
  size is not known until the box has been laid out — which for a
  widget-built entry is the frame *after* the push.

## The shape, and the three decisions in it

### 1. The route owns the clock; the transition only winds it

`Route3d` gains `animation`, an `Animation<double>` that reads 0 while the
route is away and 1 once it has arrived, backed by an `AnimationController`
the route creates on first use and disposes when it finishes. A
`Route3dTransition` is then a very small thing — a duration, a curve, and
which way to wind — and every piece of content that wants to move reads the
same value.

That is Flutter's arrangement, and the reason to copy it here is stronger than
the precedent. The transition object is held on the *navigator* and shared by
every route on it, so it cannot hold per-run state without keying it on
something; the route is the object with exactly the right lifetime, and it
already disposes itself in `_finish`.

**The controller rests at 1, not 0**, which is the one counter-intuitive
choice. A route pushed with `Route3dTransition.none` — the default, and what
every existing caller has — never has its animation wound at all, and a
content box reading 0 would place itself wherever the motion says "away" and
stay there. Resting at 1 means *arrived*: a route with no transition is at
rest from the first layout, which is what it looks like today, and a timed
transition sets the value to 0 inside `forward` before the frame's layout runs.

**The vsync is the package's own convention**, not a new one:
`Navigator3d.vsync` is a `TickerProvider?`, null means a bare `Ticker`
scheduling through the same `SchedulerBinding`, and a caller with a `State`
gives one so `TickerMode` can mute it. That is what `Scroll3dController`,
`Draggable3d` and `Dismissible3d` all already say.

### 2. What moves is a box the content places, not the entry's whole subtree

The obvious design — the transition walks to `Overlay3dEntry.content` and
writes `nodeOffset` on it — is wrong, and the catalogue is what proves it.
`showDialog3d` pushes with `modal: false` and builds its **own** barrier and
scrim inside the route's content, because the entry's own modal stack has no
depth step between the scrim and what stands on it. So the root of a route's
content is, in the catalogue's case, the scrim as well as the dialog, and
moving it would slide the dim over the screen.

So the moving box is placed *inside* the content by whoever built it, exactly
as Flutter's `SlideTransition` is placed inside a route's page:

```dart
MotionTransition3d(
  animation: route.animation,
  motion: Motion3d.fromBelow(),
  child: sheet,
)
```

and `PageRoute3d`/`WidgetPageRoute3d` take a `motion:` that wraps their own
content in one, so the common case is a named argument rather than a box.

### 3. A motion is a value, and it is resolved against the size at layout

`Motion3d` says where the content stands *before* it has arrived: an offset in
logical pixels, an offset as a fraction of the content's own size, a scale, a
turn about an axis, and the pivot both of the last two use. `Motion3d.none` is
arrival itself, and the box interpolates from the stated motion to none as the
animation runs.

Two of those five need the box's size — the fraction and the pivot — and this
is where the frame-ordering trap lives. A ticker's first tick lands in the
animation phase, *before* the layout that would give the box a size, and a
widget-built entry's subtree does not exist until the build after the
insertion. A transition that only wrote on ticks would put the content at rest
for one frame and then jump.

**So `MotionTransition3d` re-applies on every layout as well as on every
tick**, out of its own `performLayout`, where the size has just been settled.
Writing `nodeOffset` there is free of consequence by construction: it is the
node tier, it does not dirty layout, and `worldTransform` undoes it.

## What this plan does not build, and why

**Fades.** Checked again today rather than assumed: `flutter_scene 0.23.0` is
what `pubspec.lock` resolves, and `grep -rn "opacity" lib/` over the engine
finds fog, splats and a glTF extras codec — `Node` carries `visible`,
`castsShadows`, layer and light masks, and nothing that fades a subtree. So
[a box that fades](2026_09_11_what_a_real_application_still_needs.md#a-box-that-fades)
is still gated where its entry says it is, and `Motion3d` deliberately has no
`opacity` field: adding one that faded only the decoration is the thing the
earlier plan told its implementer not to do, because a dialog whose panel
fades and whose label does not is worse than a dialog that does not fade.

> **Superseded on 2026-09-17, and the grep above is the reason it was.**
> [A box that fades](2026_09_16_a_box_that_fades.md) has shipped, and the gate
> this paragraph checked was never the gate: the engine's missing node opacity
> does not matter, because this package draws with materials it owns. What
> stood in the way was `depth_write`, and screen-door coverage goes around it.
> `Motion3d.opacity` exists now, it fades the panel, the label *and* the wall
> around the label's letters, and `Motion3d.fade()` is the arrival this
> paragraph said could not be built. The second half of the reasoning held
> exactly — a fade that reached only the decoration would have been worse than
> none — and it is what made the third seam worth finding.

**`Hero3d`.** Deferred to a plan of its own, and the reason is a design
question rather than an afternoon's work. A hero flight has to draw the thing
that is flying, and **this stack does not reparent a subtree to do that**:
`Draggable3d` learned it first and builds its feedback from a
`Drag3dFeedbackBuilder` rather than carrying the child, and
[an item that keeps its state](2026_09_16_an_item_that_keeps_its_state.md)
found the same wall from the other side — what a drag carries cannot be a
second copy of a widget item, because building one lays a render box out and a
drag begins during a pointer event. A `Hero3d` inherits that constraint
whole, adds a tag registry across two surfaces to it, and wants to know what
curve a flight follows, which is the motion tokens' answer and not this
package's. It is a plan, not a paragraph.

## The work

- [x] `Motion3d`: the value, its `lerp`, `none`, the four named forms — two
      constants (`fromBelow`, `fromBehind`) and two constructors (`grow`,
      `turn`) — and the two resolvers a box calls: `offsetIn(size, metrics)`
      and `transformFor(size)`.
- [x] `MotionTransition3d`: a `ProxyLayout3d` that listens to an
      `Animation<double>`, writes the node tier, and re-applies from
      `performLayout`. Rest is `nodeOffset` zero and `nodeTransform` **null**,
      so a box at rest carries no extra multiply, which is `NodeShift3d`'s own
      rule.
- [x] `SceneMotionTransition3d`: the declarative form.
- [x] `Route3d.animation`, created on demand, disposed in `_finish`.
- [x] `TimedRoute3dTransition`, with `duration`, `reverseDuration`, `curve`
      and `reverseCurve`; a zero duration short-circuits to a
      `SynchronousFuture` so `Navigator3d.removeRoute`'s synchronous path
      still applies.
- [x] `Navigator3d.vsync`.
- [x] `PageRoute3d.motion` and `WidgetPageRoute3d.motion`.
- [x] Exports from both libraries.
- [x] Tests: `test/route_transition_test.dart`.
- [x] The changelog entry, the README's overlay and animation sections, and
      the map.

## The traps this one has to respect

- **A ticker that has stopped changing must stop asking for frames**, or
  `pumpAndSettle` spins forever. An `AnimationController` already does that;
  the thing to get right is disposal — a route that finishes while its
  controller is still running has to take the controller with it.
- **A restarted ticker begins at zero**, which is why the reverse asks the
  controller to animate *to* a target rather than replaying a duration: a pop
  one frame after a push takes the remaining distance, scaled, and not a full
  reverse from 1.
- **The depth axis is not symmetric**, and a motion in z is the reason this
  box is on the node tier at all. Toward the viewer is negative, and a lift
  written into a *position* takes the content out of reach of a ray —
  `docs/traps.md` says it twice and `Scaffold3d` paid for it once.
- **A moving box is still hit where layout put it.** That is the node tier's
  contract, not an oversight: a press during the 200ms a dialog is arriving
  lands where the dialog will be. A route already leaving cannot be popped
  twice — `removeRoute` returns false for a route that is popping — so the
  accident this could cause is the harmless one.

## What the reasoning got wrong

Three things, none of them structural — the shape above is what shipped, and
the 17 tests in `test/route_transition_test.dart` are written against it.

**A `const` constructor cannot build a value out of its own parameter**, and
two of the four named motions wanted exactly that. `Motion3d.fromBelow({double
fraction})` has to write `Offset3d(0, fraction, 0)` in a redirecting
initializer, which is not a potentially constant expression, so it does not
compile. The choice was a non-const constructor next to three const ones — a
trap for the next reader, who will write `const Motion3d.fromBelow()` and be
told no for a reason that has nothing to do with motion — or a constant with
no knob. They are constants: `Motion3d.fromBelow` and `Motion3d.fromBehind`,
with the main constructor right there for a caller who wants half a height or
forty dp. `grow` and `turn` stayed constructors, because their parameters go
straight onto fields.

**The reverse of a route that never moved is not a reverse.** The plan said a
zero duration short-circuits, and it does; what it did not see is that the
same short-circuit fires whenever the *distance* is zero, which is what a pop
finds when it interrupts a push before a single frame has been drawn. That is
right — there is nothing to unwind — but it means a route can be pushed and
popped in one turn and never tick at all, and the test that tried to watch a
barrier stay still had to pump a frame first to have anything to watch.

**And the trap the package already documents caught this plan too**: a
ticker's first frame reports elapsed zero, so a test that pops and then pumps
the remaining duration in one call watches nothing happen. Both tests that
drive a reverse pump once before pumping time. The documentation was right and
being able to quote it did not stop it costing a run.

## What is left, and where it goes

`Hero3d`, for the reason in *What this plan does not build*, and the fades,
which are gated on the engine. Neither is an open item here; both are named in
[the map](2026_09_11_what_a_real_application_still_needs.md), whose row for
this item stays open until the hero lands.

> **Both have since landed, and this section is kept as it was written.** The
> fades came first, from
> [a box that fades](2026_09_16_a_box_that_fades.md), whose note is already
> above. The hero came on 2026-09-20, in
> [a hero that flies between two routes](2026_09_20_a_hero_that_flies_between_two_routes.md),
> **so the map's row for this item is closed and the motion lane with it.**
> Two things in the paragraph this section points at are worth correcting
> from here. The curve a flight follows was called the motion tokens'
> question, and it turned out not to be a question at all: a flight rides
> `Route3d.animation`, so it has the route's own duration and curve and no
> ticker of its own. And the tag registry it predicted was not built —
> a downward walk from `Overlay3dEntry.content` has no lifetime to get wrong.
> What *did* bite is something this plan had already written down about
> itself, one paragraph away: **a widget-built entry has no subtree at all
> until the build after the insertion.** The hero read that as being about
> sizes, and it is also about whether the content can be searched at all.

**Nothing in the catalogue moves yet, by design.** `showDialog3d`,
`showMenu3d` and the sheets push with `Route3dTransition.none` and build their
own scrims, so giving them a motion means deciding *which* motion and over
what duration — which is
[the motion tokens](../../flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md)'
work and the map's own pairing. A consequence worth stating plainly: **this
change cannot be seen in the gallery**, because no route the gallery pushes
carries a motion. It is verified headlessly — node offsets, the clock, what a
ray still finds, and that a barrier stays put — and the first time anyone
watches a dialog arrive will be when the catalogue plan gives it a token.
