---
status: completed
created_at: 2026-09-20T10:00:00Z
updated_at: 2026-09-20T16:00:00Z
commit: e2006db9b33a9f65d728bd07bd13b5c777186412
---

# A hero that flies between two routes

The last row of the motion lane. [A route that arrives instead of
appearing](2026_09_16_a_route_that_arrives_instead_of_appearing.md) shipped
the clock, the transitions and the box that moves a subtree, and deferred this
one with the reasoning written down: a flight has to draw the thing that is
flying, **this stack does not reparent a subtree to do that**, and a hero
inherits that constraint whole, adds a tag registry across two surfaces to it,
and wants to know what curve a flight follows. That deferral is the brief, and
this plan answers its three parts in order.

When this lands, [the map](2026_09_11_what_a_real_application_still_needs.md)'s
row for *a route that arrives* closes, and with it the whole motion lane.

## The three constraints, and what each one forces

**One: nothing is reparented.** `Draggable3d` learned it first and builds what
it carries from a `Drag3dFeedbackBuilder` rather than lifting the child out of
the tree; [an item that keeps its
state](2026_09_16_an_item_that_keeps_its_state.md) found the same wall from
the other side, where a drag could not carry a second copy of a widget item
because building one lays a render box out and a drag begins during a pointer
event. So **a hero is a builder too**, and the shape is the drag lane's shape
rather than Flutter's: `Hero3d` takes a `flightBuilder`, the flight it returns
belongs to an overlay entry, and the entry is disposed when the flight ends,
whatever ended it.

That is a real cost and it should be said plainly rather than dressed up: an
author writes the flying thing twice, once as the hero's `child` and once as
what the builder returns. The idiom that makes it cheap is the one the drag
lane already documents — a small function called from both places — and it is
the only idiom available, not a preference.

**Two: two ends, and they may be on different surfaces.** A route's entry may
be `OverlayLayer3d.detached`, which puts its content on a surface of its own.
The arithmetic is unbothered by that: `Layout3d.worldTransform` is genuine
world space, which is why a cross-surface drag already lands correctly, and
`Draggable3d._homeOver` is the exact walk a flight needs — a box's centre
taken into the world and back out in another box's frame.

**Three: the curve.** The deferral called this the motion tokens' answer and
not this package's, and the answer that falls out of the design below is
better than a field: **a flight rides the route's own clock.** `Route3d.animation`
already exists, is already wound by the route's `Route3dTransition`, and
already means exactly "how far this route has arrived". A flight driven by it
has the route's duration and the route's curve for free, with **no ticker of
its own** — which also means none of the ticker discipline that has cost this
repository time twice, because there is no second ticker to stop, restart or
leave spinning.

It also makes one flight definition serve both directions. A push of B winds
`B.animation` from 0 to 1; a pop of B winds it back. Define the flight as
*the A-side at 0, the B-side at 1* and both directions are the same object
read from different ends. Nothing needs to know which way it is going.

## The geometry, and the channel each part goes on

Every part of a flight is the node tier. Nothing relayouts per frame, which is
the rule `docs/traps.md` sets for anything on a per-frame path.

**Position is `nodeOffset`**, lerped between "over the A-side" and "over the
B-side", using the drag lane's `_homeOver` arithmetic generalized into a
shared helper. The two plane axes only: **the depth axis is left to the
overlay's lift**, which is the lesson `drag_feedback_depth` in
`examples/render_probe` taught by z-fighting on one run and passing on the
next. `anchorOffsetTo` states the same default for the same reason.

**Size is `nodeTransform`**, a scale about the flight's own centre. This is
the decision the map already reached for the switch's growing thumb from the
other direction: a size that changes every frame is a relayout every frame,
and the answer is a thing drawn at one size and *scaled* on the node tier.

`nodeTransform` is a pure origin-relative matrix here, conjugated by the
flight's own pivot, and that is deliberate. The composition is
`T(offset + sceneOffset + nodeOffset) * nodeTransform * localTransform`, and
`ParentData3d.sceneOffset` belongs to the parent: `Stack3d.depthStep` rewrites
it on every placement, so an overlay entry inserted mid-flight would change it
under us. A flight that cancelled `sceneOffset` inside its own matrix would go
silently stale the first time a snack bar appeared during a transition. It
does not touch that channel at all.

**The flight is laid out once, at the A-side's size.** The A-side is always
already on screen when a flight starts — on a push it is the route below, on a
pop it is the route leaving — so its size is known at the moment the flight is
built, and the flight is *exact* at t=0 with a scale of 1. The far end is
reached by scale, and the B-side's size does not have to be known until the
animation has moved, which it is not on the frame a route is inserted.

That last point is the ordering hazard this stack keeps producing, and here it
is disarmed rather than worked around: `anchorOffsetTo` returns null on the
frame an entry was inserted because the entry has no size until the surface is
flushed, so **the flight recomputes its far end on every tick until it
resolves**, and parks on the A-side until then. Recomputing every tick is also
what makes a flight self-correcting under a scroll or a resize, and it is what
the drag lane pays per move already.

**Two fits, and the default is the one that matches both ends.**
`Hero3dFit.stretch` scales each axis on its own, so both endpoints are exact
even when the two boxes have different aspect ratios — which is what Flutter's
`RectTween` achieves visually, by a means not available here.
`Hero3dFit.uniform` takes one factor and never distorts, for a flight carrying
type, where a stretched letter is worse than a size that does not quite land.
**When the two aspect ratios agree the two are identical**, which is the
common case — an avatar to an avatar, a card to a card — so `stretch` is a
strict improvement there and a deliberate trade only where the shapes differ.

## The ends: hiding them, and finding them

**Both ends hide while the flight is up**, or a viewer sees three copies of
one thing. The flag is the one `Visibility3d` writes and the culling views
already write, `node.visible`, and hit testing honours it — so a hero mid-flight
is unpointable as well as unseen, which is right and matches Flutter.

**They hide when the flight has measured, not when it starts.** A flight that
hid its ends and then could not place itself for a frame would leave a frame
with nothing in it at all, which is the most visible defect a motion can have.

**Finding them is a downward walk, not a registry.** The deferral predicted a
tag registry and the codebase does not need one: registration has a lifetime,
a lifetime has a disposal path, and this repository has already paid for one
of those — [an item that keeps its
state](2026_09_16_an_item_that_keeps_its_state.md) found every declarative
list disposing children its elements had already disposed. A walk has no
bookkeeping to get wrong and is paid twice per transition rather than per
mount.

- The **B-side** walks down from `route.entry.content`, which is public and is
  the root of what the entry built, for an in-plane and a detached entry
  alike.
- The **A-side** walks down from the route below's `entry.content`, or — when
  the pushed route is the bottom of the stack — from the `Overlay3d` itself,
  pruned at every entry's content so the page is searched and the entries
  standing on it are not. A detached entry's content is not a descendant of
  the overlay at all, so it is excluded without being pruned.

A tag with no partner on the other side does not fly, silently, which is
Flutter's behaviour and the only sane one: a screen whose heroes do not all
match is the normal case, not an error.

## What this does not build, and why

**Rotation between the two frames.** A flight between surfaces at different
angles lands in the right place and does not turn to match, exactly as a
cross-surface drag carries its feedback on the plane it was picked up from.
The machinery is within reach — the frame-to-frame matrix is already computed
to get the position — but slerping an orientation is a second decision about
what a flight *looks* like, and it wants a frame to be judged in rather than a
headless assertion. Named here so the next reader knows it was seen and left,
not missed.

**A route motion that moves the destination fights its own heroes.** A hero
lands where *layout* put the B-side, because `worldTransform` undoes the node
tier — which is what makes it stable to recompute — and a route whose content
is sliding in has its heroes at their resting places while the content is
drawn elsewhere. The two are answers to the same question and the flight is
the better one; a route carrying heroes wants `Motion3d.fade()` or no motion
at all. This goes in `docs/traps.md` rather than being defended in code,
because it is a composition a caller chooses, not a state the package can
detect.

**And nothing in the gallery flies yet**, for the reason the route plan
already recorded about itself: the routes the gallery pushes carry
`Route3dTransition.none`, and a flight on a clock that never ticks is
correctly no flight at all. The gallery gets a hero in the same pass so that
this one *can* be looked at, which is the lesson the motion tokens paid for —
the lane was not missing, it was pointed at a screen with nothing on it.

## The work

- [x] `Hero3dFlight`, the value handed to a builder: the tag, the size it is
      laid out at, the direction, and the animation.
- [x] `Hero3dFlightBuilder`, and `Hero3dFit` with its two members.
- [x] `Hero3d`: a `ProxyLayout3d` carrying a `tag`, a `flightBuilder`, a
      `fit`, and the visibility it surrenders while flying.
- [x] ~~The shared `homeOver` arithmetic, lifted out of `Draggable3d`~~ — **not
      needed; it already exists.** See below.
- [x] `Hero3dFlightBox`: node-tier position and scale, recomputed per tick
      from the route's animation, resolving its far end lazily.
- [x] `Navigator3d`: collect the two sides on push and on pop, start the
      flights, and end them — through `_clearFlights`, which every ending
      reaches.
- [x] `SceneHero3d`, the declarative form.
- [x] Exports from `flutter_scene_layout3d.dart` and `widgets.dart`.
- [x] Tests: twelve in `test/hero_test.dart` — the match, the miss, the route
      with no clock, both fits, both directions, the depth axis, the
      deferred second attempt, the interrupted push, and the endings.
- [x] A hero in the gallery: every inbox row's avatar flies into the dialog
      the row opens, with a sixth test in `test/screens_test.dart`.
- [x] `CHANGELOG.md`, the README's *A hero that flies between two routes*,
      and the trap page.
- [x] Close the map's row and reread its seams.

## What this plan's reasoning got wrong

**The shared arithmetic it asked for already existed, under another name.**
The work list had lifting `Draggable3d._homeOver` into a shared helper, and
`Layout3d.anchorOffsetTo` *is* that helper: with both alignments left at
centre it computes exactly the same change of frame, and it already leaves the
depth axis alone for the same render-probe reason. The flight calls it and no
arithmetic was written at all. The lesson is the one this repository keeps
paying for — **grep before writing it down, and before writing it**.

**And the ordering hazard was worse than the plan allowed for.** The plan knew
that the far end has no *size* on the frame its entry was inserted, and
disarmed that with the lazy resolution. What it did not see is that a
**widget-built route has no subtree at all** in the turn that pushed it — its
content reaches the element tree on the build `Overlay3d.entriesChanged` asks
for — so the arriving side could not even be *collected* there, and every
hero in the gallery silently failed to fly. The route plan had written this
down about itself, in as many words, and it was read as being about sizes.
`Navigator3d` now asks once at push and, finding nothing, once more after that
build, guarded by an attempt token so a pop that interrupts a push cannot have
the stale attempt put a flight up behind it. **The gallery is what caught
it**, which is the third verification lane doing exactly what `AGENTS.md`
says it is for: both halves were green and the feature did not work.

**The third constraint dissolved rather than being answered.** The deferral
asked what curve a flight follows and called it the motion tokens' answer.
The flight rides `Route3d.animation`, so it has the route's duration and the
route's curve without a field, a token or a ticker — and the ticker discipline
that has cost this repository time twice does not apply, because there is no
second clock. One flight definition serves both directions too: define it as
*the covered side at 0, the covering side at 1* and a pop is the same object
read from the other end.

**The tag registry the deferral predicted is not there**, and the entry above
argued it should not be: registration has a lifetime, a lifetime has a
disposal path, and this repository has already paid for one of those. A
downward walk from `Overlay3dEntry.content` has no bookkeeping to get wrong.
That held.

## What is left

**Rotation between two frames**, as the section above says: a flight between
surfaces at different angles lands in the right place and does not turn to
match. It is a decision about what a flight *looks* like and wants a frame to
be judged in.

**And one ergonomic wart worth naming.** A flight builder returns a
`Layout3d`, so an application that otherwise lives entirely in
`widgets.dart` has to import `flutter_scene_layout3d.dart` as well to have the
boxes to build one out of. The gallery does, with a comment saying why.
`Draggable3d.feedbackBuilder` has had the same seam since it shipped and
nobody has minded yet; if a second builder-shaped API appears, the three
together are worth a look.
