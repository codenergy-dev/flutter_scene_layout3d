---
status: in progress
reason: eight of the seventeen items are open; the record of what shipped, the application widget, the wheel and the key, the test library, right to left, the picture, the item that keeps its state, the screen that knows how big it is and the box that fades are closed, and the route is closed but for its Hero3d
created_at: 2026-09-11T21:20:18Z
updated_at: 2026-09-17T11:50:00Z
commit: abc2469ce5c4ec4c41e2738fc5acf55bcf40640a
---

# What a real application still needs

A map, not a work item — the second one this repository has. The first,
[what a component library needs from this package](2026_08_25_material3d_readiness_overview.md),
asked whether the layout protocol could carry a Material catalogue and then
built the ten plans that made it true. This one asks the question after that:
**can a person build an application people use on top of both packages**, and
it is drawn from an audit of the whole stack at `abc2469`.

Each item below becomes a plan of its own, in the package it belongs to,
written to be handed to an implementer who has read only that plan and this
document's entry for it. They are not written yet, deliberately: a plan
written six items ahead of the work reasons against a codebase that will have
moved, and this repository has already learned that
[closing a plan can invalidate another one](../../../AGENTS.md). **The plan is
written when the item is picked up.** What this document owes each of them is
the boundary, the design question, and the evidence the audit turned up — so
that writing it is an afternoon and not a re-investigation.

## What the audit found, and what it did not

The baseline is genuinely sound, and that is the finding that shapes
everything below. At `abc2469`: **991** headless tests green in the layout
package, **517** in the Material package, **75** render probes, `dart analyze`
clean across the workspace, a clean working tree, and — the number worth
dwelling on — **eight** matches in the two packages for
`TODO|FIXME|XXX|HACK|unimplemented`, every one of them an explanatory comment
rather than a marker. CI runs the formatter, the analyzer, both suites and the
render probes on a runner with a real GPU.

So **what stands between this and a production application is not debt and not
architecture. It is surface** — the layer the application author's hands
actually touch. The layout algebra, the node tiers, the unit contract, the
semantics tree, the clip contract and ray dispatch are all in place and
faithful, and every item on this map lands on them without reopening a
decision. That is the good news and it is load-bearing: it means this map is
additive, and it means the items can be taken in almost any order without one
of them invalidating another's design.

The bad news is the shape of what is missing. It is not exotic. It is the
mouse wheel, a photograph on a panel, a row that reads right to left, a
keyboard, and a widget that spares every application ninety lines of ray
plumbing. **The promise is "the Flutter everyone knows, in three dimensions",
and the gaps are concentrated exactly where a person's expectations are
strongest**, which is the worst place for them to be: a developer forgives a
missing `Stepper3d` and does not forgive a `ListView3d` that ignores the
trackpad.

## How this is measured, and what is deliberately downstream

The test of this map is not that every row is ticked. It is that
**the packages, consumed by path from this machine, can carry screens from
applications that already exist** — real ones, already shipped in two
dimensions, re-laid on this stack to find out where it bends. That is the
acceptance criterion, it is a better oracle than any checklist, and it is the
reason for the exclusion below.

**Publishing to pub.dev is out of scope here, and on purpose.** The question
"is this worth publishing" is answered by the exercise above, not before it,
so the packaging work it would need — a hosted dependency in place of
`flutter_scene_material3d`'s `path:` reference to this package, version
numbers, and a decision about the `web` platform the two `pubspec.yaml` files
declare but no lane has ever verified — belongs to a plan written *after*
those ports have been done and have said yes. Nothing on this map depends on
it, and one thing on it ([the record of what shipped](#the-record-of-what-shipped))
is the part of that work worth doing now anyway, because it is already wrong
rather than merely absent.

Two things outside this map's scope for the older reason — they are genuine
design questions rather than absences, and the Material catalogue plan
[says so in its own words](../../flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md):
what a **window size class** means for a surface floating in a room, and what
**"off the edge"** means for a menu on a panel that may be at any angle. Both
are touched by items here — the first by
[a screen that knows how big it is](#a-screen-that-knows-how-big-it-is), which
is **done** and deliberately stopped short of it: it publishes the extent a
screen would branch on, `MediaQuery3d.of(context).size`, and leaves the
breakpoints to whoever builds a component that needs them — and neither is
settled by them.

## The plans

Seventeen, in five lanes. The package column matters: a change to the protocol
that the catalogue needs gets its plan **here**, not a line item in a Material
plan, which is the rule phase 0 established and every phase since has obeyed.

| Plan | Package | What it unblocks |
| --- | --- | --- |
| ~~[An application that does not wire its own rays](#an-application-that-does-not-wire-its-own-rays)~~ | layout3d | **done** — every application, ninety lines each |
| ~~[A wheel, a trackpad and a key that reach a box](#a-wheel-a-trackpad-and-a-key-that-reach-a-box)~~ | layout3d | **done** — scrolling on desktop and web; a keyboard that gets into a scene, across it, and out |
| ~~[A row that reads right to left](#a-row-that-reads-right-to-left)~~ | layout3d | **done** — every non-LTR locale, and the catalogue mirroring with it |
| ~~[A picture on a panel](#a-picture-on-a-panel)~~ | layout3d | **done** — avatars, photographs, gradients, logos |
| ~~[A box that fades](#a-box-that-fades)~~ | layout3d | **done** — `Opacity3d`, and every fade in the motion lane |
| [A letter someone can type](#a-letter-someone-can-type) | layout3d | text fields, forms, search, pickers |
| ~~[An item that keeps its state](#an-item-that-keeps-its-state)~~ | layout3d | **done** — forms in lists, and the declarative layer complete |
| ~~[A screen that knows how big it is](#a-screen-that-knows-how-big-it-is)~~ | layout3d | **done** — the reader's font setting, the safe area, and something to branch on |
| [A route that arrives instead of appearing](#a-route-that-arrives-instead-of-appearing) | layout3d | **the transitions are done**; `Hero3d` is what the row is still open for |
| [An application with more than one screen](#an-application-with-more-than-one-screen) | layout3d | named routes, deep links, the system back button |
| ~~[A way to test a screen someone else built](#a-way-to-test-a-screen-someone-else-built)~~ | layout3d | **done** — anyone building on this, including us |
| [The motion tokens](#the-motion-tokens) | material3d | every animating component |
| [The components a screen still needs](#the-components-a-screen-still-needs) | material3d | the two thirds of M3 not yet here |
| [A scheme from one colour](#a-scheme-from-one-colour) | material3d | any application with a brand |
| [The controls that wait on a keyboard](#the-controls-that-wait-on-a-keyboard) | material3d | search, dropdowns, date and time entry |
| [A catalogue that speaks more than one language](#a-catalogue-that-speaks-more-than-one-language) | material3d | every locale, and the strings the catalogue invents |
| ~~[The record of what shipped](#the-record-of-what-shipped)~~ | both | **done** — the next reader trusting what they read |

## The order, and why

~~**[An application that does not wire its own rays](#an-application-that-does-not-wire-its-own-rays)
leads**~~ — **done, and it led** for the same reason camera-bound surfaces led
the first map: it is the item every other item is consumed through. Porting a
real screen no longer begins by copying ninety lines out of
`examples/layout3d_gallery` and getting the z-orders right; it begins with a
`SceneInput3d` around the view. Every subsequent item is now evaluated in a
real application instead of in a scene. See
[its plan](2026_09_11_an_application_that_does_not_wire_its_own_rays.md).

~~**[The wheel and the key](#a-wheel-a-trackpad-and-a-key-that-reach-a-box)
immediately after**~~ — **done**, see
[its plan](2026_09_15_a_wheel_a_trackpad_and_a_key_that_reach_a_box.md), tried
on a desktop, and extended to a slider on the arrows and Tab across and out of
the scene. The reasoning here said the
controller side was built and only routing was missing; a wheel turned out to
want an operation of its own, and the key turned out not to route through the
host at all.

~~**[A way to test a screen someone else built](#a-way-to-test-a-screen-someone-else-built)
early, out of order.**~~ **Done**, third, see
[its plan](2026_09_15_a_way_to_test_a_screen_someone_else_built.md): a test
library in the package, a photograph of the gallery on every CI run, and the
gallery's tests in CI. It found a defect on its first run. The audit's
sharpest evidence is that ten of this
repository's worst defects — a screen nothing could press, a screen one
logical pixel deep, every panel drawn from its back face, a label sunk into
its own slab, a hole punched through a navigation bar — were invisible to the
suites and the probes alike, and were found by a person looking at a window.
A wave of real-application ports is about to generate that class of defect in
quantity, and there is currently **no committed instrument** for it: the
captures that settled those findings came from throwaway files, and the
package exports no test helper an application author could use at all. Build
the instrument before the wave, not after.

~~**[The record of what shipped](#the-record-of-what-shipped) whenever there is
an hour**~~ — **done, first of the seventeen**, because it turned out to be
the same work as restructuring `AGENTS.md`: the history that belonged in the
changelogs was sitting in the file every agent loads. See its entry.

Then the four the first real port will demand, in whatever order the ported
screens demand them:
~~[right to left](#a-row-that-reads-right-to-left)~~ — **done**, first of the
four because the language item waits on it, see
[its plan](2026_09_15_a_row_that_reads_right_to_left.md) —
~~[a picture](#a-picture-on-a-panel)~~ — **done**, second, see
[its plan](2026_09_15_a_picture_on_a_panel.md) —
~~[an item that keeps its state](#an-item-that-keeps-its-state)~~ — **done**,
third, see [its plan](2026_09_16_an_item_that_keeps_its_state.md) — and
~~[a screen that knows how big it is](#a-screen-that-knows-how-big-it-is)~~ —
**done**, fourth and last of them, see
[its plan](2026_09_16_a_screen_that_knows_how_big_it_is.md). **The four the
first real port would demand are all closed**, which makes the port itself the
next thing worth doing: it is the oracle this whole map is measured against,
and everything below it is now a choice rather than a queue.

Then motion, as a pair:
[a route that arrives](#a-route-that-arrives-instead-of-appearing) here and
[the motion tokens](#the-motion-tokens) in the catalogue. **The layout half
has landed** — see
[its plan](2026_09_16_a_route_that_arrives_instead_of_appearing.md) — which
makes the catalogue half the ripe one: a route now carries a clock and a
`Motion3d` says what an arrival looks like, and what is missing is the
duration and the curve each component should use, which is what the token
family is. Nothing in the catalogue moves until it is taken, so **this is the
first item on the map whose result cannot be seen by running the gallery**.
~~[A box that fades](#a-box-that-fades) belongs with them~~ — **done**, see
[its plan](2026_09_16_a_box_that_fades.md), and it was the reversal it looked
like: the engine still has no per-node opacity at `flutter_scene 0.23.0`, and
that was never the gate. `Opacity3d` fades a panel, a label and the wall
around that label's letters by screen-door coverage, and `Motion3d.opacity`
is what finishes an arrival. **That leaves the motion lane's remaining work
entirely in the catalogue**: the layout half is finished but for `Hero3d`, and
nothing in the catalogue moves until the token family says with what duration
and what curve.

Then [the catalogue batch](#the-components-a-screen-still-needs), which is
broad and shallow, and
[a scheme from one colour](#a-scheme-from-one-colour), which is narrow and
deep and independent of everything.

**[A letter someone can type](#a-letter-someone-can-type) last of the large
items, and it is much larger than anything above it.** It gates
[the controls that wait on a keyboard](#the-controls-that-wait-on-a-keyboard),
and it is the one item on this map that is a research project rather than an
afternoon's reasoning plus a week's work.
[An application with more than one screen](#an-application-with-more-than-one-screen)
and
[more than one language](#a-catalogue-that-speaks-more-than-one-language)
can be taken any time after their gates.

## The seams to keep an eye on

The couplings between these plans, named here so that both ends know. These
are where a first implementer's decision becomes someone else's constraint.

- **Whoever builds the application widget owns the input contract**, and three
  other plans consume it: the wheel and the key route through it, navigation
  hangs off it, and the test library has to be able to drive it without a real
  window. Design it as the seam it is, not as a convenience wrapper around
  the gallery's code. **Settled:** the seam is `Input3dHost`, reached with
  `SceneInput3d.of(context)` or through an `Input3dController`, and it carries
  the group and the camera. `SceneInput3d` takes a `child` rather than
  building the `SceneView`, which is what makes it drivable from a widget test
  with no window. **Confirmed by the test library, with one addition:** a test
  asking whether a press *would* reach a box needs the host to answer without
  dispatching, which is `Input3dHost.hitTestAt` — the group's own `hitTest`
  reports the path behind a surface that does not absorb. **Corrected by the wheel and
  the key:** the wheel and the trackpad do route through it, and the key does
  not — a key goes to the focus, and the focus manager never consults the
  widget that owns the rays. What the host owns for the keyboard is the way
  *in*, `requestSceneFocus`. Navigation's back button is a key of that kind
  too, so whoever builds it should expect the focus tree, not the host, to be
  where it arrives. **And traversal between surfaces is the host's too**, for
  the reason everything cross-surface is: only the host knows which surfaces
  exist. It walks them in mount order through
  `Layout3dOwner.onFocusTraversalEdge`; whoever builds navigation should not
  build a second answer.
- **Keys are Flutter's vocabulary walked over the layout tree**, by
  `Shortcuts3d` and `Actions3d`. Two plans consume this:
  [the controls that wait on a keyboard](#the-controls-that-wait-on-a-keyboard)
  binds intents on components — the slider's arrows are the worked example,
  in `Slider3d`, and [a letter someone can type](#a-letter-someone-can-type) will
  meet it where text editing's own shortcuts live. A Flutter `Shortcuts` widget
  above the `SceneView` reaches nothing on a plane; that is in
  [docs/traps.md](../../../docs/traps.md).
- **Two plans want an asynchronous texture, and one already has the trap.** A
  glyph's wall arrives with the atlas rather than with the layout, which is
  `GlyphAtlas3d.outlineRevision` and is written up in
  [docs/traps.md](../../../docs/traps.md). An image on a panel arrives the same
  way. Whoever builds [a picture on a panel](#a-picture-on-a-panel) should read
  that trap first and generalize the counter rather than invent a fourth one.
  **Settled, and the advice was half wrong:** the picture needs no counter at
  all. An atlas has three because it is one texture whose contents keep
  changing under meshes already baked from it; a picture's arrival is a value —
  a texture that was null and now is not — that a consumer can simply compare.
  What generalized instead is Flutter's own `onChanged`, now
  `Decoration3dPaintRequest.onChanged`: the way anything that arrives late asks
  to be drawn again without a relayout. The next asynchronous resource — a
  video frame, a remote icon — uses that and adds no counter either.
- **The screen's two channels, and which one a thing belongs on.**
  [A screen that knows how big it is](#a-screen-that-knows-how-big-it-is)
  settled it: what the *layout measures with* goes on `Layout3dMetrics` — the
  reader's `TextScaler` is there, read inside `performLayout` where there is no
  `BuildContext` — and what a *`build` method branches on* goes on
  `MediaQuery3d`, which is a widget-layer widget exactly as Flutter's is.
  Anything ambient that a later plan adds has to pick one, and the test is that
  question and not convenience. Two plans consume it already:
  [a letter someone can type](#a-letter-someone-can-type), whose caret and
  selection geometry are type and therefore scale with the scaler rather than
  with the density, and
  [the components a screen still needs](#the-components-a-screen-still-needs),
  which owns the two things that plan deliberately left: a `Scaffold3d` that
  consumes the safe area the way Flutter's does, and whatever a breakpoint
  turns out to mean for a panel in a room.
- **Motion and the relayout path.** The animation tiers exist and are the whole
  reason a ripple is affordable: repaint-only, node-only, and implicit for when
  a size really changed. Every item in the motion lane must land on the first
  two. The specific hazard is documented and has already cost time: **an
  animation that has stopped changing must stop asking for frames**, or
  `pumpAndSettle` spins forever, and a `Ticker` restarted after a stop begins
  its clock at zero. **Settled for the route half, and it added one rule:** an
  arrival is `MotionTransition3d` on the node tier, driven by
  `Route3d.animation`, and a box whose motion is stated as a fraction of its
  own size has to re-apply from `performLayout` — the first tick lands before
  the layout that would give it a size, and a widget-built entry has no subtree
  at all until the build after the insertion. Anything else that arrives late
  and moves meets the same ordering. **And [a box that
  fades](#a-box-that-fades) added a third tier to the two**: an opacity is
  neither a repaint of one box nor a node transform, it is an *inherited
  value*, republished down a subtree as one uniform per box that draws. It
  lays nothing out and rebuilds no geometry, so it belongs beside the other
  two rather than above them — but a box that draws with a material this
  package does not own cannot be reached by it at all, which is why
  `NodeBox3d` takes an `onFade` and asserts without one. Anything that later
  wants to publish a second ambient *drawing* value should copy that shape
  rather than pushing it down.
- **`Decoration3dPainterCache` is what makes a screen of panels affordable**,
  and it keys on `Decoration3d.cacheKey`. Two plans here compute colours that
  did not exist before — [a scheme from one colour](#a-scheme-from-one-colour)
  and the motion lane, which interpolates them per frame. A decoration built
  with a freshly computed colour every frame defeats the cache silently: the
  frame rate falls and nothing says why.
- **A rounded clip still does not exist.** `Clip3dRegion` is an intersection of
  planes, so it is convex, and a corner radius is carved by the panel shader
  rather than clipped. Anything on this map that wants to cut a child to a
  rounded container — a card's `clipBehavior`, a tab indicator inside a rounded
  bar — meets that wall. The first plan that genuinely needs it owns carrying a
  *shape* into the clip contract, and it is a real piece of work rather than a
  parameter. **One of the three cases listed here went around it instead:** an
  image filling a rounded panel is drawn *by* the panel shader, inside the same
  signed distance field that carves the corners, which is why
  [a picture](#a-picture-on-a-panel) is a decoration rather than a quad. That
  is the shape of the workaround for anything else that can be expressed as a
  parameter of the surface it sits on — and it does nothing for a child
  overflowing a rounded card, which is still the wall.
- **A target reaches past its own extent and its parent does not.** Every new
  interactive component in the catalogue lane obeys the placement rule from
  [a tap target that delivers a press](2026_09_02_a_tap_target_that_delivers_a_press.md):
  the target sits outside every box the size of the control, the panel and the
  semantics box included.
- **The depth axis is not symmetric with the other two**, and two of the
  gallery's four visual defects came from forgetting it. A lift written into a
  child's *position* takes that child out of reach of a ray; depth separation
  belongs on the node tier. A line's depth cross axis starts at the front while
  its other one centres. A surface has to lift what is drawn on it off its own
  face. All three are in [docs/traps.md](../../../docs/traps.md), and every
  new component in this map's catalogue lane can reproduce all three. Two of
  them now fail a headless test, through `testing.dart`: a child lifted out of
  reach fails `tap3d` and `isReachable3d`, and content sunk *behind* its
  surface's face fails `standsOnItsPanel3d`. Content left coplanar with the
  face does not — that one z-fights, and only a frame shows it.

---

## An application that does not wire its own rays

**Package:** `flutter_scene_layout3d`.
**Slug:** `an_application_that_does_not_wire_its_own_rays`.
**Closed** by
[its own plan](2026_09_11_an_application_that_does_not_wire_its_own_rays.md).
The entry below is what it was reasoned from; what the reasoning got wrong is
recorded there, and the short version is that the design question this entry
called the harder half — who owns the z-order — was the easy half, while the
overlay's entries, which this entry mentions in a clause, held the only actual
defect in the existing machinery.

The gap, in one sentence: **there is no application layer.** Read
`examples/layout3d_gallery/lib/gallery.dart` and count what an author must
write before a single press lands — a `Listener` for five pointer callbacks,
`camera.screenPointToRay` against a `LayoutBuilder`'s size, a
`Layout3dPointerGroup` fed `down`/`move`/`up`/`cancel`/`hover`, and a
`_syncPointers()` called from `onTick` on **every frame** because a
`SceneLayout3d`'s surface does not exist until the widget is mounted — which
in turn calls `addSurface` with hand-authored `zOrder` values and
`syncDetachedEntries` for the overlay. That is roughly ninety lines, per
application, with several silent failure modes: a z-order in the wrong
relative order routes a press to the panel behind, a surface added before it
exists is skipped forever, a detached entry never synced is unpressable.

The design question this plan must settle is **who owns the ray**. The
candidate answer is a widget that wraps `SceneView` and owns the group, with a
surface announcing itself on mount rather than being registered from a tick —
which is a lifecycle change in `Layout3dController`/`SceneLayout3d`, not just
a wrapper. The z-order question is the harder half: geometry cannot answer
"what is in front" for a surface turned away from the camera, which is
*why* the gallery states it by hand, so the plan has to decide whether the
ordering is declared (a property on `SceneLayout3d`) or derived (and from
what).

Boundary: this plan owns wiring and ownership. The *events that exist* are the
next plan's, and named routes are
[a later one's](#an-application-with-more-than-one-screen). It should not
become a `MaterialApp3d` — theming, localization and navigation each have
their own item — but it should be the thing those items hang from, so name
that seam.

## A wheel, a trackpad and a key that reach a box

**Package:** `flutter_scene_layout3d`.
**Slug:** `a_wheel_a_trackpad_and_a_key_that_reach_a_box`.
**Closed** by
[its own plan](2026_09_15_a_wheel_a_trackpad_and_a_key_that_reach_a_box.md). The entry
below is what it was reasoned from. What that reasoning got wrong, in short:
Tab was not wired either, so "traversal moves focus correctly" described a
policy nothing called; the key does not route through the application widget;
and the defect underneath was in the overlay again — a trapping entry did not
take the focus, which activation would have turned into a dialog opened twice
by one Enter.

Two absences that are one plan, because both are "an input Flutter has and
this stack does not route".

**The wheel and the trackpad.** `PointerScrollEvent`, `PointerPanZoomEvent`
and `onPointerSignal` appear **nowhere** in either package. A `ListView3d`
scrolls by drag alone, which means scrolling does not work by the usual
gesture on macOS, Windows, Linux and web — four of the six platforms both
`pubspec.yaml` files declare. The mechanism is already there:
`Scroll3dController` has `jumpBy`, `applyUserOffset` and `fling`. What is
missing is the routing, and the design question is *which* scrollable receives
a signal that has no drag to own it — the one under the ray, found by the same
hit test a press uses, which also answers what happens when two surfaces
overlap under the cursor. Trackpad pan-zoom carries a scale as well, and a
scene where the surface can be moved has an obvious temptation there; resist
it or decide it deliberately, because a pinch that zooms the *camera* and a
pinch that zooms the *layout* are different products.

**The key.** Today the only keyboard contact in the stack is
`Focus3d(onKeyEvent:)`. `Focus3dTraversal` moves focus correctly and then
nothing happens when it arrives: no Space or Enter activating a focused
control, no Escape dismissing a modal, no `Shortcuts`/`Actions`/`Intent`
layer. The ripple work already anticipated this and left the landing pad —
its plan notes that a press with no noted point ripples from the middle of the
surface, "which is what a space-bar activation would get if anything in this
stack activated a control from the keyboard. Nothing does yet." This plan is
what makes that sentence false.

Boundary: this is activation and dismissal, not text entry.
[A letter someone can type](#a-letter-someone-can-type) owns anything that
composes characters.

## A row that reads right to left

**Package:** `flutter_scene_layout3d`.
**Slug:** `a_row_that_reads_right_to_left`.
**Closed** by
[its own plan](2026_09_15_a_row_that_reads_right_to_left.md). The entry below
is what it was reasoned from. What that reasoning got wrong, in short: it was
filed as a layout item and the real hazard was in the catalogue, where every
physical padding and every hand-computed position was left on the wrong side
the moment the rows mirrored; the missing directions were a third of what was
missing; `readingDirection3d` is about what a component announces, not how it
is laid out; and the design question below had already been answered by the
wheel. A horizontal scroll view that starts at the right is not a direction
but an absence — no view here has `reverse` — and is recorded under
[the components a screen still needs](#the-components-a-screen-still-needs).

**Reading direction reaches the text and stops there.** `Text3d`,
`RichText3d` and the catalogue's `readingDirection3d` all handle it properly.
But `Flex3d` takes **no `textDirection` and no `verticalDirection`**, and
there is no `EdgeInsetsDirectional3d` and no `AlignmentDirectional3d`. The
consequence in an Arabic or Hebrew locale is a `Row3d` that arranges left to
right around text that runs right to left, with no `start`/`end` padding
available to fix it by hand. This is not a missing feature so much as a
**divergence from Flutter's own contract** — the strongest kind of gap for a
package whose promise is that the protocol is the one people know — and it
blocks localization entirely. The missing `verticalDirection` is the same
absence on the other axis: there is no reversed `Column3d`.

The plan's genuine design question, and it is a good one: **what does `start`
mean on a plane the viewer can walk behind?** A mirrored or back-facing
surface has a leading edge that is on the other side of the screen from the
one layout computed. Flutter never has to answer this. The likely answer is
that direction is a property of the layout and not of the view — a row reads
the same way whichever side you stand on, exactly as printed text does — but
it should be *decided* and written down rather than inherited by accident,
because a reader will ask.

Consumed by
[a catalogue that speaks more than one language](#a-catalogue-that-speaks-more-than-one-language).

## A picture on a panel

**Package:** `flutter_scene_layout3d`.
**Slug:** `a_picture_on_a_panel`.
**Closed** by
[its own plan](2026_09_15_a_picture_on_a_panel.md). The entry below is what it
was reasoned from. What that reasoning got wrong, in short: the first of its
three decisions was already settled by a wall this map names elsewhere — with
no rounded clip, only the shader that carves a card's corners can carve a
photograph's, so a picture had to be a decoration; the counter it asked for
should not exist, because a picture's arrival is a value rather than a change
inside a shared resource, and what generalized was Flutter's `onChanged`; and
the gradient's real question was not the shader's cost but uniforms against a
baked ramp, which turns on animation and on the fact that Skia interpolates in
sRGB. The defect it found was in neither half: a slab with no thickness has a
singular transform and no normal, so **every zero-depth panel has always been
drawn black**, and a box that sizes itself to a picture is the first thing that
ever had one.

**There is no way to put an image in a layout.** No `Image3d`, no
`ImageProvider` path anywhere, and `BoxDecoration3d` carries `color`,
`borderRadius`, `bevel`, `border`, `elevation` and `surfaceTint` and nothing
else — no `image`, no `gradient`, no `boxShadow`, no per-side border. Every
application has a photograph, an avatar, a logo or a gradient in it, and today
the only route is dropping out of the layout into a hand-built `NodeBox3d`
with a textured material of one's own.

Three decisions the plan owns:

- **Is an image a decoration or a box?** Flutter has both
  (`DecorationImage` and `Image`), and here they are different mechanisms: a
  decoration is one shader with a parameter block, so an image in it means a
  sampler on the panel material and a second texture bound per box; a
  `NodeBox3d`-shaped answer is a textured quad that is told its size. `BoxFit`
  semantics have to work in either.
- **The asynchronous clock.** An `ImageProvider` resolves late, like the glyph
  atlas does, and the trap is already documented for glyph walls: the thing
  arrives with the texture rather than with the layout, and needs a revision
  counter the frame can compare against. Generalize
  `GlyphAtlas3d.outlineRevision`'s answer rather than inventing another.
- **What a gradient and a shadow cost.** A gradient is cheap in the panel
  shader and probably belongs there. A shadow is not available at all: the
  render probes established that `box_decoration3d.fmat` declares
  `blending: alpha` and `ShadowEncoder` drops every non-opaque material before
  the shadow map, so a decorated panel is not a caster. Do not re-litigate
  that; `examples/render_probe`'s `panel_shadow` scene demonstrates it and
  fails if the engine changes.

## A box that fades

**Package:** `flutter_scene_layout3d`.
**Slug:** `a_box_that_fades`.
**Closed** by
[its own plan](2026_09_16_a_box_that_fades.md) — which was written *after* an
experiment rather than before one, because this entry had sent two
investigations to ask the wrong question.

**The entry below is what it was reasoned from, and its premise is wrong.**
There is no per-node opacity in the engine, and it does not matter: this
package draws with materials it owns, and both of them already multiply alpha.
What stands in the way is `depth_write`, which makes this the *partly*
transparent case that
[a transparent slab that does not erase](2026_09_10_a_transparent_slab_that_does_not_erase.md)
left open — and screen-door coverage goes around it for the cost of one
uniform. Five approaches were built and photographed; two of them fail at
opacity 1.0, where nothing is supposed to be happening.

What shipped: `Opacity3d` and `FadeTransition3d` over an inherited
`Layout3d.inheritedOpacity`, `Motion3d.opacity`, a `fade` uniform on both
shipped shaders and **a third shader** — `assets/text_glyph_wall3d.fmat` —
because a glyph's wall is an opaque material coloured by its own vertices and
nothing a uniform could say would fade it. The cost of the approach is group
opacity: a label on a faded card is about half again as strong as Flutter
would draw it at 30%, and exactly right at either end. The two approaches
that get that right both fail at 1.0, which is a worse place to be wrong.

**There is no `Opacity3d`, and it may not be buildable here.** This is the one
item on the map with an upstream gate, and it was already investigated once:
the readiness overview records that subtree opacity needs a per-node opacity in
`flutter_scene` that the materials honour, and that there is none. That still
holds at the version resolved in `pubspec.lock` — `flutter_scene 0.23.0`,
whose `Node` carries `visible`, a selection-outline `highlightColor`, layer
and light masks and shadow flags, and no opacity or tint of any kind.

So **this plan's first step is not code, it is checking whether the engine has
moved**, and if it has not, choosing between the two answers `AGENTS.md`
allows: work around it on this side, or open an issue upstream — and write
down which. **Checked again on 2026-09-16**, by
[a route that arrives](#a-route-that-arrives-instead-of-appearing), because
the fades were its to ship if they existed: `pubspec.lock` still resolves
`flutter_scene 0.23.0`, and a grep for `opacity` over the engine's `lib/`
finds fog, splats and a glTF extras codec and nothing on `Node`. The gate has
not moved, and `Motion3d` ships with no opacity field rather than one that
fades a panel and leaves its label. The working-around options are all partial and one of them is
explicitly forbidden by the earlier plan: shipping an `Opacity3d` that faded
only `BoxDecoration3d` is the thing that plan told its implementer not to do,
because a box whose panel fades and whose label does not is worse than no
opacity at all.

Why it matters enough to be on the map: the whole motion lane wants it. A
dialog that fades in, a snack bar that fades out, an `AnimatedOpacity3d`, a
`FadeTransition3d`, `Hero3d`, and Material's own disabled treatment — which
this catalogue substitutes a colour for precisely *because* there is no
opacity, a re-derivation the catalogue plan documents and defends. If the
engine gains node opacity, revisit that decision too.

## A letter someone can type

**Package:** `flutter_scene_layout3d`.
**Slug:** `a_letter_someone_can_type`.

**The largest item on this map by a wide margin**, and the Material catalogue
plan already declares it out of its own scope in as many words: there is no
`EditableText3d`, no text selection, no cursor, no clipboard and no
text-input client anywhere in the stack. (Keys do reach a focused box now,
through `Shortcuts3d` and `Actions3d` — which is where an editor's own
shortcuts will want to live — but nothing composes a character.) What it gates: `TextField3d`, and through it
`SearchBar3d`, `DropdownMenu3d`'s editable form, `DatePicker3d`'s text entry,
`Autocomplete3d` — and `Form3d`/`FormField3d`/validation, which do not exist
in any form and which nearly every real application has.

This entry deliberately does not sketch a design; a plan this size earns its
own investigation. What it should carry in from the audit is where the stack
already helps and where it does not:

- **Measurement is not the problem.** `PreparedText3d`, the two measurement
  policies and `TextLayout3d`/`TextLine3d`/`TextRun3d` already give
  per-run and per-line geometry, and the prepare/layout split exists precisely
  so that re-fitting a string does not re-consult the font.
  `debugTextParagraphCount` is the guard that catches measurement getting back
  onto the layout path, and a caret that moves on every keystroke is exactly
  the customer that would put it there.
- **A caret is a slab, not a line**, for the same reason a 1dp divider is: a
  zero-depth rectangle is coplanar with the surface it is drawn on and
  z-fights it. And it blinks, which makes it the second thing in the stack
  that animates forever — read the `Ticker` trap before writing it.
- **Selection is a set of rectangles over runs**, and highlighting them is a
  decoration problem the panel shader can probably serve, but a selection that
  spans a wrapped line is several boxes and the anchor/extent arithmetic is in
  world space on a plane that may be turned.
- **`TextInputClient` assumes a 2D window.** The platform wants a caret rect
  and a composing region in logical pixels to place the IME candidate window;
  `Layout3dScreenProjection` is the existing arithmetic for projecting a box
  to the screen, and it is the likely bridge.

## An item that keeps its state

**Package:** `flutter_scene_layout3d`.
**Slug:** `an_item_that_keeps_its_state`.
**Closed** by
[its own plan](2026_09_16_an_item_that_keeps_its_state.md). The entry below is
what it was reasoned from. What that reasoning got wrong, in short: the shared
seam was real and was two hooks, exactly as this entry and the prior plan
predicted, so the *design* held — and the work was somewhere else entirely, in
the disposal bookkeeping a dropped child breaks. The defect it found is that
a view asking `childManager` at teardown asks the wrong question, because the
element clears itself on the way out while the children it built are still on
the books; every declarative list was disposing children its elements had
already disposed. And the reorderable widget turned out to have a question
nobody had asked: what a drag carries cannot be a second copy of a widget
item, because building one lays a render box out and a drag begins during a
pointer event.

Two gaps that are one plan because they are the same seam.

**Keep-alive does not exist.** `cacheExtent` does, throughout the lazily built
children lane, but nothing keeps a scrolled-away item alive, so a stateful item
loses its state when it leaves the window. The Material catalogue plan flags
this and then says the thing that makes it belong on *this* map: "Fine for a
catalogue, and worth knowing before someone builds a form on it." A form is
what a real application is.

**And the declarative layer is missing forms the imperative layer has** — the
audit found six: `SceneRichText3d`, `SceneVisibility3d`, `SceneOffstage3d`,
`SceneReorderableList3d`, `SceneSliverReorderableList3d` and
`SceneIntrinsicExtent3d`. Four are mechanical. The reorderable pair is not,
and it is why the two halves share a plan: the readiness overview records that
there cannot be a `SceneReorderableList3d` until
`Layout3dBuiltChildrenMixin` grows a seam that lets a view adopt what the
child manager built, because the list wraps every item in a `Draggable3d` of
its own while the declarative contract is that `removeChild` is handed back
the very layout `createChild` returned. **That is the same seam keep-alive
needs**, for the same reason — both are a view wanting a say in the lifetime
of a built child. **Settled:** it is `wrapBuiltChild` and `builtChildOf` on
`Layout3dBuiltChildrenMixin`, and it cost two hooks.

`SceneRichText3d`'s absence is worth calling out separately as the cheapest
inconsistency on the whole map: `RichText3d` has just absorbed two phases of
work — a paragraph with a side to it, its own CPU rasterization, per-span
wall colours — and **a `build` method cannot reach any of it.** It was twenty
lines of property forwarding, and it was the best value on this map per line
written.

## A screen that knows how big it is

**Package:** `flutter_scene_layout3d`.
**Slug:** `a_screen_that_knows_how_big_it_is`.
**Closed** by
[its own plan](2026_09_16_a_screen_that_knows_how_big_it_is.md). The entry
below is what it was reasoned from. What that reasoning got wrong, in short:
it filed the `TextScaler` migration as a *migration*, and a scaler that is not
linear across sizes broke the premise the whole text layer leans on, which
split the two text boxes onto different answers; the inset question turned out
to have a one-word answer (nothing, for any surface that is not standing in
for the view) and the real work was deciding that `MediaQuery3d` is a widget
layer thing, as it is in Flutter, where no render object reads one; and the
piece it did not see at all is that a surface which *states* a metrics — which
is how an author says "this panel is a smaller screen" — would have silently
opted every label on it out of the reader's font setting, so the friction
shipped as an assert.

There is no `MediaQuery3d` and no `SafeArea3d`, and the piece of `MediaQuery`
that does exist is wired the wrong way round. `Layout3dMetrics.textScaleFactor`
is a **`double`**, set by hand on a `Layout3dCameraBinding`, where Flutter has
moved to `TextScaler` precisely because accessibility scaling is not linear —
and because nothing reads `MediaQuery.textScalerOf`, **the reader's own font
setting never reaches a 3D screen at all.** For a stack whose semantics layer
is as carefully built as this one's, that is an odd hole: the screen reader
finds the control and the large-text setting does not.

What the plan owns: the `TextScaler` migration and where the ambient value is
read (remembering that writing `metrics` relayouts the subtree, so it is a
settings change and never a per-frame one); what an inset *is* for a surface
that is not the window; and how much of a size class is answerable without
settling the design question the catalogue plan deferred. It is legitimate for
this plan to stop short of adaptive breakpoints and say so — but a real
application ported onto this stack will have a phone layout and a tablet
layout, so it has to leave something behind for an author to branch on.

## A route that arrives instead of appearing

**Package:** `flutter_scene_layout3d`.
**Slug:** `a_route_that_arrives_instead_of_appearing`.
**Mostly closed** by
[its own plan](2026_09_16_a_route_that_arrives_instead_of_appearing.md): the
clock, the transitions and the box that moves a subtree have shipped, and
**the row stays open for `Hero3d` alone**, which that plan defers to one of
its own with the reasoning for it written down. The entry below is what it was
reasoned from. What that reasoning got wrong, in short: it said the seam was
one hook wide and it was two — a transition can only wind a clock, because
*what* moves has to be chosen by whoever built the route's content, since a
catalogue route carries its own scrim and a dim must not slide in with the
dialog it dims. The tier was right, and so was the warning about the ticker;
what the entry did not see is that a motion stated as a fraction of a size
needs a size the box does not have when the first tick arrives, so the box
re-applies from `performLayout` as well.

**Nothing in either package animates except the press ripple.**
`Route3dTransition.none` is the only implementation that ships, so a dialog, a
menu, a bottom sheet and a snack bar each appear and disappear between two
frames. There is no `Hero3d`, and the implicit lane covers exactly four
widgets — `SceneAnimatedContainer3d`, `SceneAnimatedAlign3d`,
`SceneAnimatedPositioned3d`, `SceneAnimatedSizedBox3d`. For a product this
reads as broken rather than as plain, and the third dimension makes it worse
rather than better: **movement is most of what a scene has to offer over a
picture**, and a catalogue that does not move is spending the cost of 3D
without collecting the benefit.

The good news is that the seam was left on purpose and is one hook wide:
`Navigator3d.transition` already exists, takes a `Route3dTransition` with
`forward` and `reverse`, and the catalogue plan calls the deferral out as
phase 6's. And the tier that should carry it is the cheap one — an entry
sliding, turning or scaling toward the viewer is `nodeOffset`/`nodeTransform`
and `NodeShift3d`, one matrix a frame, nothing laid out again.

What the plan owns: the transitions themselves; the fades, which were gated on
[a box that fades](#a-box-that-fades) and did ship without them — that item is
now closed and `Motion3d.opacity` is where they landed; a
`Hero3d`, which is `Layout3d.anchorOffsetTo` plus a route's clock and is
genuinely interesting in three dimensions because the flight can go *through*
the scene; and above all the `Ticker` discipline — an animation that has
stopped changing must stop asking for frames or `pumpAndSettle` spins forever,
and one restarted after a stop begins its clock at zero, so a driver that
pauses carries its own baseline.

## An application with more than one screen

**Package:** `flutter_scene_layout3d`.
**Slug:** `an_application_with_more_than_one_screen`.

`Navigator3d` does what it was built for — it pushes and pops routes over an
overlay, and `showDialog3d`, `showMenu3d` and the sheets all ride on it
correctly. What it is not yet is the Navigator people know: no named routes or
route table, no `RouteObserver`, no `PopScope`/`WillPopScope`, **no
integration with the Android system back button or predictive back**, no deep
links, and no seam a `Router`/`go_router`-shaped package could plug into.

An application with three screens and a back button is the most ordinary thing
there is, and today the author writes the stack themselves. Gated on
[the application widget](#an-application-that-does-not-wire-its-own-rays),
because that is what would own the `WidgetsBindingObserver` a back button
arrives through. Pairs naturally with
[route transitions](#a-route-that-arrives-instead-of-appearing) but does not
depend on them.

## A way to test a screen someone else built

**Package:** `flutter_scene_layout3d`.
**Slug:** `a_way_to_test_a_screen_someone_else_built`.
**Closed** by
[its own plan](2026_09_15_a_way_to_test_a_screen_someone_else_built.md). The
entry below is what it was reasoned from. What that reasoning got wrong, in
short: it treated the ten defects as one class wanting one instrument, and
they are two — about half are visible to the layout, and a headless library
catches those; the rest exist only in a frame. The route it gave for the
photograph would have written the file into the app sandbox's container, and
the gallery had four tests, not three.

Two audiences, one plan.

**An application author has nothing.** The packages export no test library at
all — no `pumpLayout3d`, no finders over the layout tree, no matchers for a
size, a position or a hit. The 991 tests in this package are written against
private infrastructure. A team that adopts this stack can test its business
logic and cannot test its screens, which for a UI toolkit is close to
disqualifying.

**And the most productive verification lane in this repository's history is
not reproducible.** The audit's headline finding bears repeating: ten of the
worst defects ever found here were invisible to the headless suites and the
render probes alike, and every one was found by starting the gallery and
looking at the window. There is no committed way to photograph a frame — the
captures that settled the atlas and slab findings came from a throwaway
`integration_test` that was deliberately not committed (adding one turns the
example into a CocoaPods project and breaks the plain `flutter create` path
the example documents), and the scratch probe files that produced the panel
findings are untracked. The cheaper route is already known and written down:
`examples/render_probe` has all of that wiring committed, so a scene there
that builds a real Material screen and writes `boundary.toImage()` to
`Directory.systemTemp` photographs one with no CocoaPods work at all.

Smaller, and worth folding in: **the gallery's three tests do not run in CI** —
no job enters `examples/layout3d_gallery`.

## The motion tokens

**Package:** `flutter_scene_material3d`.
**Slug:** `the_motion_tokens`.

M3's easing and duration sets, as a seventh token family beside
`ColorScheme3d`, `Typography3d`, `ShapeScale3d`, `Elevation3d`,
`Thickness3d` and `StateLayerOpacity3d` — with `lerp`, with the drift tests
against Flutter's own figures that the other four transcribed families have,
and carried on `Theme3dData` so both layers read it.

The catalogue plan has been careful about this and the plan should honour the
reasoning: the family stays closed until enough components animate to know
which tokens are actually used, which is why the ripple shipped with
`InkRipple3dStyle` — a component style like `ButtonStyle3d`, replaceable per
controller, holding Flutter's own `InkRipple` figures — rather than opening a
family for one animation. **[A route that arrives](#a-route-that-arrives-instead-of-appearing)
is the event that makes this plan ripe**, because it is the first time several
components need the same curve — and **that event has happened**: the layout
package now has `TimedRoute3dTransition` and `Motion3d`, so every overlay in
the catalogue is one duration and one curve away from arriving instead of
appearing, and nothing in the catalogue moves until this plan says which.

Its first customers, all currently deferred for want of it: the switch thumb
that should grow from 16dp to 24dp as it crosses, the chip that lifts under a
press, and every overlay that should arrive rather than appear.

## The components a screen still needs

**Package:** `flutter_scene_material3d`.
**Slug:** `the_components_a_screen_still_needs`.

The catalogue is broad and it is not the catalogue. Missing entirely, from the
audit: `ProgressIndicator3d` in both forms, `TabBar3d`/`TabBarView3d`,
`SegmentedButton3d`, `Badge3d`, `NavigationDrawer3d`, `BottomAppBar3d`,
`ExpansionTile3d`, `MaterialBanner3d`, `CircleAvatar3d`, `Stepper3d`,
`AlertDialog3d`, `RangeSlider3d`, `DataTable3d`, `Carousel3d`,
`RefreshIndicator3d`, `Scrollbar3d`, the `CheckboxListTile3d` family and
`RadioGroup3d`. Missing in part, each for a reason its phase wrote down: the
checkbox's tristate, the slider's tick marks and value indicator, the filter
chip's checkmark, the card's `clipBehavior`, a tooltip on long press, a snack
bar's second line and its swipe, a draggable sheet.

**Phase it, the way the catalogue plan phased ten.** Most of this list is
composition over `Material3d` plus a public token set resolved by state, which
is the one mechanism the whole catalogue uses and the reason this work is
broad rather than deep. The ones that are *not* mere composition, and which
should be grouped by what they actually need:

- `ProgressIndicator3d` and `RefreshIndicator3d` want the motion lane.
- `TabBar3d` wants an indicator that slides (node tier, free) and a rounded
  clip it cannot have (see the seams).
- `Carousel3d`, and any horizontal list in a right-to-left application, want a
  scroll view with `reverse`, which none here has: Flutter starts a
  horizontal `ListView` at the right in right to left by reversing its axis.
  [Right to left](2026_09_15_a_row_that_reads_right_to_left.md) found it and
  left it, because there was no direction to thread.
- `Scrollbar3d` wants
  [the wheel plan](#a-wheel-a-trackpad-and-a-key-that-reach-a-box) and, more
  interestingly, a design answer: what *is* a scrollbar beside a surface in a
  room, when the thing it measures is a plane the viewer may be looking at
  edge-on.
- `CircleAvatar3d` and `DataTable3d` wanted
  [a picture on a panel](#a-picture-on-a-panel), which is **done**: a circular
  avatar is an `Image3d` with a radius on it, and the gallery's inbox has five
  of them.
- `RangeSlider3d` is a second arena problem rather than a second thumb — two
  thumbs competing for one pointer — and phase 7 said so.
- **`Scaffold3d` does not consume the safe area**, and Flutter's does.
  [A screen that knows how big it is](#a-screen-that-knows-how-big-it-is)
  built `MediaQuery3d.padding` and `SceneSafeArea3d` and left the catalogue
  side alone on purpose, because whether an app bar stops at the status bar or
  is drawn *under* it is a component decision with tokens attached. A ported
  screen writes `SceneSafeArea3d` itself until this is taken. The same entry
  owns a control that grows with its label: a 48dp row of 14sp type at a large
  accessibility setting is a row the text overflows, here as in Flutter.
- `AlertDialog3d` is a column and a row inside `Dialog3d` and phase 6
  deliberately refused it as the first component that exists only to save a
  caller writing a `SceneColumn3d`. **Revisit that judgement with an
  application's eyes rather than a catalogue's**: the calculus changes when
  the caller is porting fifty dialogs rather than demonstrating one.

## A scheme from one colour

**Package:** `flutter_scene_material3d`.
**Slug:** `a_scheme_from_one_colour`.

`ColorScheme3d` carries all of M3's roles, complete and pinned against
Flutter's defaults, in exactly two instances: a hand-written `light` and a
hand-written `dark`. There is no `fromSeed`, and **no real application uses
the Material baseline** — every one of them starts from a brand colour. The
catalogue plan puts this out of its own scope with a good reason attached
("a package's worth of work… a generator can be added later without changing
a single component"), and the second half of that sentence is why this is a
narrow, self-contained, low-risk item that can be taken at any time by anyone.

The work is M3's tonal palettes: HCT, the tone stops, and the role-to-tone
mapping for light and dark. The existing hand-written schemes become the
test oracle — a generator seeded with Material's own baseline primary should
reproduce them within tolerance, and if it does not, one of the two is wrong.

## The controls that wait on a keyboard

**Package:** `flutter_scene_material3d`.
**Slug:** `the_controls_that_wait_on_a_keyboard`.

`TextField3d` and everything downstream of it: `SearchBar3d`/`SearchAnchor3d`,
`DropdownMenu3d` in its editable form, `DatePicker3d` and `TimePicker3d` with
text entry, `Autocomplete3d`, and the `Form3d` composition an application
actually writes. **Entirely gated on
[a letter someone can type](#a-letter-someone-can-type)** and listed
separately from it so the boundary is clear: that plan builds the mechanism in
the layout package, this one builds the M3 components over it — the filled and
outlined field variants, the label that floats, the supporting and error text,
the character counter, and the token sets for each.

One thing it can do before its gate opens: the **non-editable** halves. A
`DropdownMenu3d` that is a `Menu3d` on a button, a date picker that is a
calendar grid of `TapTarget3d`s, a time picker that is a dial — all three are
buildable today, and Flutter's own pickers are usable without ever typing.
Taking those first is a real option and would shrink this plan considerably.

## A catalogue that speaks more than one language

**Package:** `flutter_scene_material3d`.
**Slug:** `a_catalogue_that_speaks_more_than_one_language`.

There is no equivalent of `MaterialLocalizations`. The catalogue does invent
user-visible strings — an overlay's dismiss affordances, the labels a
component publishes to a screen reader through its own `Semantics3d` — and
they exist in one language. An application cannot translate them, and an
application in a locale it cannot translate is not shippable in that locale.

Depended on [a row that reads right to left](#a-row-that-reads-right-to-left)
for the arrangement half, which is **done**: the catalogue's rows, paddings,
toolbar, slider, switch and menu corners mirror under the ambient
`Directionality`, so what is left here is the words. The plan should also decide how much of Flutter's delegate
machinery to adopt versus a simpler table, given that this package deliberately
avoids a second vocabulary for anything the platform already spells — the
`Semantics3d` precedent, where a component author writes Flutter's own
`SemanticsProperties` unchanged, is the pattern to follow if it can be.

## The record of what shipped

**Package:** both.
**Slug:** `the_record_of_what_shipped`.

The cheapest item on this map, and the only one that is actively wrong rather
than absent — which by this repository's own rule makes it worse than the
others, because the next reader trusts it.

- **[docs/README.md](../../../docs/README.md) describes a state that has not
  existed for a week.** Its *Know what is being built next* row and its
  closing paragraph both name
  [a label that survives a repack](2026_09_10_a_label_that_survives_a_repack.md)
  and
  [a transparent slab that does not erase](2026_09_10_a_transparent_slab_that_does_not_erase.md)
  as "the only plans in either package that are not finished" — **both are
  `completed`** — and the three newest plans
  ([a letter with a side to it](2026_09_11_a_letter_with_a_side_to_it.md),
  [a paragraph with a side to it](2026_09_11_a_paragraph_with_a_side_to_it.md),
  [a letter on a slab](2026_09_10_a_letter_on_a_slab.md)) are absent from the
  map altogether.
- **Both `CHANGELOG.md` files are silent about most of what exists.** This
  package's `## Unreleased` stops at the metrics work of 2026-09-02: it records
  nothing of the clip tier reaching the shader, the overlay and anchoring
  additions, `Layout3d.localPointFrom`, the glyph walls, the shipped
  `assets/text_glyph3d.fmat`, or the atlas reservation fix — a grep for
  `ripple|glyph wall|outlineRevision|localPointFrom|anchorOffsetTo` in it
  returns nothing. The Material package's is 88 lines that end by calling the
  buttons, cards and bars "the next phase", with nine phases shipped since; a
  grep for `Scaffold3d|Dialog3d|Checkbox3d|Ripple3d|NavigationBar3d` returns
  nothing.

Both are backlog created by commits that did not carry their documentation,
against a convention that says documentation is part of the change. Clearing
it is an hour or two. **Doing it also front-loads the only part of the
publication work worth doing before the real-application ports**, since a
changelog is what a consumer of these packages reads first.

**Closed, and it did not get a plan of its own** — it was small enough to do
directly, and it arrived attached to something larger. Asked to review whether
`AGENTS.md` carried the right instructions, the answer turned out to explain
this item rather than sit beside it: **half of that file was a changelog
written in prose.** 185 of its 399 lines were a phase-by-phase narrative of
what had shipped, it had been touched in 22 of the repository's 70 commits to
keep that narrative current, and `grep -i changelog` over it and over `docs/`
returned nothing at all. The discipline was never missing; it was pointed at
the wrong file, and the changelog habit died in the same commit the catalogue
phases began.

So the two were done together:

- `AGENTS.md` is 317 lines and is a process contract. The narrative is gone,
  the compressed restatement of `docs/traps.md` is gone, and in their place are
  a *Before you call it done* checklist whose fourth item is the changelog
  entry, a *Versions and the changelog* convention that says what earns an
  entry and forbids bumping a version, a **verify before you write it down**
  rule, and a section saying why this file deliberately diverges from
  `flutter_scene`'s own — so the next reader does not shorten it back.
- Both changelogs now carry what shipped, newest first, in the house voice.
- `docs/README.md`'s reasoning section is current: the two 09-10 plans are
  recorded as closed rather than open, the three newest plans have their
  paragraph, and *what is being built next* points here.

**What this item's own reasoning got wrong:** it was filed as hygiene, worth
an hour, and it was really a diagnosis. The changelog did not drift because
someone forgot — it drifted because the instruction did not exist, and the
place the instinct went instead was the one file with no mechanism to stop it
growing. Writing the missing rule mattered more than filling in the missing
entries.

## Keeping this document true

This is a living index and it has two obligations beyond the usual ones.

**Each entry above becomes a real plan when it is picked up**, named
`YYYY_MM_DD_<slug>.md` in the package its row names, dated the day it is
written and carrying the `commit:` it was reasoned against. When it lands, come
back here: strike the row, link the plan, and say in a line what its reasoning
got wrong — the same shape the
[readiness overview](2026_08_25_material3d_readiness_overview.md) uses, whose
*How the seams resolved* and *What is still missing* sections are the most
re-read parts of it.

**And reread the seams whenever one closes.** This map's items touch each
other in eight places, all named above, and this repository has already been
bitten by the failure mode: closing a plan made three statements in other
plans false, and nothing warned anyone.
