---
status: completed
created_at: 2026-09-17T17:10:00Z
updated_at: 2026-09-17T18:30:00Z
commit: d65b6135345440420bac108eb711a78892cd597d
---

# An overlay that clears the screen

A defect found the way this repository's worst defects are always found: a
person started the gallery, opened a dialog, and looked at the window. It was
invisible to **1825 headless tests and 108 render probes**, all of which
passed over it, and it had been in the package since overlays landed.

## What is wrong

**A dialog's scrim sits behind half the screen it is supposed to dim.**
Measured on the gallery's own upright screen, with the depth axis growing
*away* from the viewer, so more negative is nearer:

| | front face |
| --- | --- |
| body, the list | `+0.15` |
| the gradient header | `−0.12` |
| the navigation bar | `−0.27` |
| **a dialog's scrim** | **`−0.305`** |
| **a sheet's scrim** | **`−0.340`** |
| the app bar | `−0.36` |
| the dialog itself | `−0.50` |
| **the floating action button** | **`−0.54`** |

So the app bar and the floating action button are **in front of the scrim**
and are not dimmed at all, and the button is drawn over the dialog. A person
sees a screen that is half dimmed and half not, and — because the two modals
land at different depths — sees it differently for each one.

## Why, and it is one line of arithmetic

`Scaffold3d.overlayLift` computes 60dp and its dartdoc says that clears the
whole screen "**by construction**". The number is right and the claim is
false, for a reason `docs/traps.md` already records and the snack bar already
avoids:

1. `Overlay3d` is a `Stack3d`, and `SceneOverlay3d` gives it
   `Alignment3d.center`.
2. **An `Alignment3d` centres in *depth* too.** A thin entry in a panel
   0.6 deep is therefore placed at layout `z ≈ 0.26`, in the middle of the
   slab.
3. The lift is applied from there — `_Overlay3dEntryHost.sceneOffset` adds
   `−lift` to wherever the stack put the box — so 60dp of lift lands the
   entry 30dp short of where every caller thinks it is.
4. Half the lift is spent before it starts.

It also explains the two different answers. The dialog's frame is 0.04 deep
and the sheet's is 0.08, so centring divides different remainders:
**−0.305 against −0.340.** Two modals, two depths, neither one correct.

`snack_bar.dart` names the trap in its own comment — *"`Alignment3d.bottomCenter`
centres in depth as well, which would put the bar inside the lift that was
meant to carry it in front of the screen"* — and uses `Alignment3d(0, 1, -1)`.
Whoever wrote the snack bar knew. `showDialog3d` did not.

## What ships

**A lift is a distance from a face, so the entry is pinned to one.** An
in-plane host is a `Positioned3d` with `front: 0` and nothing else, so the
overlay's alignment still places it across and no longer places it in depth.
The lift is then applied to a box that starts at the overlay's front face, and
60dp of lift means 60dp.

```dart
class _Overlay3dEntryHost extends Positioned3d {
  _Overlay3dEntryHost(this.entry)
    : super(
        front: entry.layer is DetachedOverlayLayer3d ? null : 0.0,
        name: 'Overlay3dEntry',
      );
  ...
}
```

`modalFrame3d` in the catalogue gets the same treatment one level down: its
stack takes the caller's alignment across and the **front** face in depth,
whatever the caller said. A scrim is the backmost thing in that frame and
still has to be in front of the whole screen; centred in the frame's own depth
it sat a fraction of a slab behind the frame's face, which is where the last
15dp of the dialog-against-sheet difference came from.

Measured on the gallery afterwards, both modals land at **−0.60** and the
frontmost thing on the screen is at −0.54.

It also repairs `Overlay3d.defaultLift`, which nobody had noticed was
meaningless: eight logical pixels described as "a depth-buffer separation"
put an entry 8dp in front of the *middle* of the panel, which on any panel
thicker than 16dp is still inside it.

### Pinned in layout, and not cancelled in the node offset

The first attempt did it the other way — leave the entry centred and have the
node offset subtract the centring as well as add the lift. It draws the same
picture and it is worse, for a reason worth keeping: **a lift is invisible to
hit testing by design**, so the gap between where an entry is drawn and where
it answers a ray would have grown from 60dp to 86dp. Pinning moves the box
itself, so the gap stays exactly the lift.

### The two things it deliberately does not change

- **The alignment's depth component still does what it says** for everything
  else, including the `Stack3d` an entry builds when `modal: true`, and
  including a detached entry's anchor. Only the *lift's reference face* moves.
- **A detached entry is untouched.** Its plane is placed from the anchor the
  overlay gives it, and `DetachedOverlayLayer3d.offset` exists precisely so a
  caller can move it; its dartdoc already says the anchor sits where the
  overlay's alignment puts it. A detached entry has a surface of its own and
  is not competing with the panel's depth buffer in the same way.

### The margin that is left, stated rather than closed

With the lift measured from the front face, the gallery's scrim lands at
`−0.60` and the frontmost thing on the screen — the floating action button —
at `−0.54`. The clearance is 6dp, and it is `depthStep − elevation`: the
scaffold's slot arithmetic spends one step of slack, and a slot's *own*
elevation eats into it. Material's scale tops out at `elevation.level5`,
12dp, which is exactly `thickness.depthStep`, so a slot at level 5 would tie.

`Scaffold3d.overlayLift` takes only a depth step and cannot see an
elevation, and widening its signature is a public API change for a case
nothing in the catalogue has. So this ships as a **drift alarm instead of an
arithmetic**: a test asserts that a real screen's scrim clears every opaque
panel on it, and fails the day someone raises a slot's elevation.

## Verification

Three lanes, and the third is the one that found this.

1. **Headless, in the layout package.** An in-plane entry's drawn front face
   is exactly `lift` in front of the overlay's, for a thin entry and a thick
   one and under a centred alignment and a front one — the case that proves
   the alignment no longer decides it. A detached entry is unmoved.
2. **Headless, in the catalogue.** `test/overlays_support.dart`'s screen with
   a dialog on it: the scrim's front face is in front of every opaque panel
   in the tree. That is the drift alarm for the margin above, and it is the
   test that would have caught this in the first place.
3. **A photograph with a dialog open.** The render probe photographs the
   gallery on every CI run and photographs only the *idle* screen, which is
   why five of the six arrivals and all of this had nowhere to be seen.
   `photograph_test.dart` gains a third frame: open the overflow menu, open
   the dialog, photograph that. A frame is the only thing that answers
   whether the dimming reads right.

## What this found, and what it leaves open

**The reasoning held for the defect and missed what fixing it would cost.**
The diagnosis was right to the millimetre and the fix is three lines. What the
plan did not see is that applying a lift for the first time exposes a second
defect underneath it, which it then makes more visible.

### An overlay is pressed where it was laid out, not where it is drawn

A lift is on the node tier, and `Layout3d.worldTransform` discards a
`sceneOffset` on purpose — the node tier moves geometry and nothing else. So
an entry answers rays at its **layout** depth while a person presses it where
they can see it. The two are the same point in the middle of the view and
drift apart toward the edges, in proportion to the lift.

Before this change the lift was half-spent, so an entry was drawn about 10dp
in front of the panel and the drift was negligible. Now it is drawn where the
lift says — 60dp and more — and a menu hung in the *far corner* of a panel
draws in one place and is pressed in another. The gallery's own overflow menu,
at the end of an app bar, still presses correctly and its suite proves it;
`test/menu_test.dart`'s corner case no longer asserts reachability and says
why.

**Two ways to close it were tried and neither works**, which is why it is
written down rather than fixed here:

- **Shift the ray by the lift in the host's `hitTest`**, the pattern
  `Layout3dAnchoring.anchorOffsetTo` prescribes and `Follower3d` follows.
  `Layout3d.hitTest` gates on the box's own extent and hands children only the
  stretch of the ray *inside* it, both in the frame the box was laid out in; a
  ray moved into the drawn frame is in neither, and four barrier tests fail
  at once.
- **Skip the gate too**, the way the `hitTestTransform` branch does for a
  transforming box. That fails one level up: `Layout3dSurface.hitTest` clamps
  every ray to the surface's own box before its children see it, so
  **geometry drawn in front of the surface can never be reached by a ray at
  all.** An overlay lifted out of its panel is exactly that geometry.

So the real shape of it is bigger than a lift: *an overlay is drawn outside
the surface it belongs to, and rays are clamped to that surface.* Closing it
means either laying an entry out in front — which changes what the overlay's
box contains, and meets clipping — or letting a surface answer rays outside
its own depth. Both are protocol decisions and belong to a plan of their own.

### The margin held, and is now guarded

`Scaffold3d.overlayLift`'s slack is one depth step, and a slot's own elevation
eats into it: the floating action button is at `−0.54` against a scrim at
`−0.60`, so 6dp of 12dp is left. `test/dialog_test.dart`'s new group asserts a
real scaffold's scrim clears every opaque panel on it, which fails the day
someone raises a slot's elevation past `thickness.depthStep`.

### What nothing was testing

The most useful number in this plan: **1825 headless tests and 108 render
probes passed over this**, and the one-line experiment that front-aligned the
overlay broke none of them. Two of the tests that existed *asserted the defect
as the contract* — `overlay_test.dart` said in a comment "the box is where a
centred stack child goes, inside the overlay" and checked `z: 0.25`, the
middle of the panel. A test that pins the wrong answer is worse than no test,
and it is the same failure this repository keeps meeting: the suites measured
the arithmetic and nobody had asked what the arithmetic was *for*.
