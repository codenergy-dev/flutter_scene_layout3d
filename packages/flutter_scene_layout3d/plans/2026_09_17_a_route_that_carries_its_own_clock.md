---
status: completed
created_at: 2026-09-17T12:10:00Z
updated_at: 2026-09-17T15:40:00Z
commit: 96da2ebad2559275e80cf602240b77215c53cefb
---

# A route that carries its own clock

Phase 0 for [the motion tokens](../../flutter_scene_material3d/plans/2026_09_17_the_motion_tokens.md),
and the same shape as the phase 0 before it: a change to the layout protocol
that the catalogue needs, planned **here** rather than as a line item in a
Material plan.

## The defect

[A route that arrives instead of appearing](2026_09_16_a_route_that_arrives_instead_of_appearing.md)
shipped `TimedRoute3dTransition` and hung it on `Navigator3d.transition` — one
mutable field, shared by every route on the stack. That was right for what
that plan was proving, and it does not survive first contact with a
catalogue, for two reasons that compound.

**The overlays disagree about the clock.** Material gives each of them its
own figures, and they are not close: 150ms for a dialog, 250ms in and 200ms
out for a bottom sheet, 300ms for a menu. A dialog and a sheet open on the
same navigator — `navigatorOf3d` deliberately returns the same object — so
one field cannot serve both.

**And setting the field per push is not merely ugly, it is wrong.** The
navigator reads `transition` twice for each route, and the second read is
`removeRoute`, at pop time:

```dart
// push
unawaited(transition.forward(route));
// removeRoute, arbitrarily later
final reverse = transition.reverse(route);
```

So a dialog opened over an open sheet rewrites the field, and the sheet then
closes on the dialog's clock — or, if the dialog closed first and something
restored the field, on whatever was last written. The bug is a timing that
comes out wrong only when two overlays overlap, which is exactly the case
nobody tests by hand.

## What ships

A transition is a property of *what is arriving*, not of the stack it arrives
on, so it moves onto the route, with the navigator's own kept as the default
for a route that does not care.

- `Route3d.transition`, a nullable, mutable field on the base class, settable
  through `Route3d({this.transition})`.
- `Navigator3d` consults `route.transition ?? transition` — in `push` and in
  `removeRoute` both, and through one private helper so the two reads cannot
  drift apart.
- `PageRoute3d` and `WidgetPageRoute3d` take it as a constructor argument and
  forward it with `super.transition`.

That is the whole change. It is additive: every route built today has a null
`transition` and is driven by the navigator's, which is the behaviour that
exists.

**The synchronous path is preserved by construction.** `removeRoute` finishes
in the same turn when the reverse returns a `SynchronousFuture`, and that
test is on the future rather than on the transition, so a route carrying
`Route3dTransition.none` on a navigator that animates still comes out at
once.

## What this plan does not do

- **A route does not get a `Motion3d` it did not already have.** The split
  the route plan settled stands: a transition winds the clock and a
  `MotionTransition3d` inside the content decides what moves. A catalogue
  dialog carries its own scrim and puts the motion *inside* it by hand,
  which is why `PageRoute3d.motion` is not the answer for one.
- **No per-route ticker.** `Navigator3d.vsync` stays where it is; a route's
  controller already falls back to a bare `Ticker` and nothing about a
  per-route clock changes which ticker winds it.

## Verification

`test/route_transition_test.dart` gains the cases that state the contract:

1. A route's own transition runs instead of the navigator's, forward and
   reverse.
2. **Two routes on one navigator, each with its own duration**, popped in the
   order that reproduces the defect — the sheet-under-the-dialog case above.
3. A null `transition` still gets the navigator's.
4. A route with `Route3dTransition.none` on an animating navigator still
   leaves synchronously.

## What shipped, and what the reasoning got wrong

All four verification cases are in `test/route_transition_test.dart`, under
*a route that carries its own clock*, and the suite is 1254 green.

**The reasoning held.** This is the smallest plan in either package and it
found nothing it had not predicted: the field, one private lookup so the two
reads cannot drift, two constructor arguments, and the synchronous path
preserved because the test is on the future rather than on the transition.

Two things it did not see, both found by the catalogue that asked for it:

- **Opting *out* is as useful as opting in, and nothing here anticipated it.**
  The plan framed this as "each overlay wants its own duration". The first
  real use was the opposite: a `PopupMenuButton3d` whose button leaves the
  tree sets `Route3dTransition.none` before popping, because a menu shrinking
  away over three hundred milliseconds would be shrinking away from an anchor
  that no longer exists, on a tree that is already leaving, with a ticker that
  outlives both. A per-route field is what makes that a line rather than a
  special case in the navigator.
- **A test that leaves a route open now leaks a ticker.** Nothing about this
  change caused it — it is the price of the catalogue animating at all — but
  it is where the cost landed: `An animation is still running even after the
  widget tree was disposed` is what a suite says when it opens an overlay and
  ends without settling. Nineteen tests in `flutter_scene_material3d` had to
  learn `pumpAndSettle`.
