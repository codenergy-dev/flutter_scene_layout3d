---
status: completed
created_at: 2026-09-15T16:23:05Z
updated_at: 2026-09-15T17:45:46Z
commit: 2a7c4dc3bece8cd29c02efe5603457feafa5f84a
---

# A way to test a screen someone else built

The third plan off
[what a real application still needs](2026_09_11_what_a_real_application_still_needs.md),
taken early and out of order for the reason that map gives: a wave of
real-application ports is about to produce the class of defect this repository
has only ever found by looking at a window, and there is no committed
instrument for it. Build the instrument before the wave.

Two audiences, and they want different instruments.

## What is actually missing

**An application author has nothing.** The package exports no test library.
Every test in this repository reaches the layout tree through helpers private to
its own `test/` directory, and the evidence that those helpers are the library
nobody wrote is that they have been written *four times*:

- `boxesOf<T>` — in the gallery's `screens_test.dart` and in the Material
  package's `overlays_support.dart` and `surfaces_support.dart`, identically.
- `oneOf<T>`, `decoratedBoxIn`, `focusIn` — the same walk with a count on it,
  three more times.
- `rayAt` — in both packages' `support.dart`, in `overlays_support.dart` and in
  the gallery, each with a comment saying it is a copy because a test cannot
  import another package's `test/` directory.
- `offsetInSurface` — in the gallery, `overlays_support.dart` and
  `surfaces_support.dart`, and **the copies disagree**: the overlay one sums
  `sceneOffset`, the other two do not. Nothing has failed because of it, which
  is the point — a helper that gives two answers to "where is this box" is a
  test that can pass on the wrong one.

And every one of those helpers is below the level a person works at. They aim
a ray straight down a surface's own depth axis, with no camera, no z-order
between surfaces and no `SceneInput3d`. That is the right tool for testing the
protocol, and it is blind to exactly the defects that reached a person: *a
screen nothing could press* was a slot a straight-on ray at its own centre
reached perfectly well in its own surface, and was unreachable through the
host the application actually used.

**And the lane that found the worst defects is not reproducible.** The captures
that settled the atlas and slab findings came from a throwaway
`integration_test` in the gallery, deliberately not committed because it turns
the example into a CocoaPods project, and the gallery README tells the next
person to rebuild it from a recipe in a plan. `examples/render_probe` already
commits all of that wiring.

**And the gallery's tests do not run in CI.** No job enters
`examples/layout3d_gallery`. Its four tests include the regressions for two of
the ten defects, so both could come back on `main` unnoticed.

## What each of the ten defects needed

The map lists the ten defects a person found by looking. The honest measure of
this plan is which of them each instrument would have caught, so this is
written down before the design rather than after it.

| Defect | Visible to layout? | Caught by |
| --- | --- | --- |
| A screen nothing could press (every `Scaffold3d` slot unreachable) | yes | `isReachable3d`, and `tap3d` refusing to tap what it cannot reach |
| A screen one logical pixel deep | yes | `hasSizeDp(depth: …)` |
| A frame that would not build with semantics on | yes | already `testWidgets`' default — `semanticsEnabled` is true |
| A slider hidden 12dp behind the face of its card | yes | `standsOnItsPanel3d` |
| A label sunk into the slab it belongs to | partly — the slab was wound inside out | `standsOnItsPanel3d` for the layout half; the photograph for the rest |
| Every panel drawn from its back face | no | the photograph |
| A hole punched through a navigation bar | no | the photograph |
| A label lost when the atlas repacked | no | the photograph |
| A glyph that wrote no depth and was erased by the sort | no | the photograph |
| A pinned bar's clip that never reached the shader | no | the photograph, and a render probe |

So the headless library is worth building for four or five of them, and the
photograph is not optional for the rest. Neither instrument is the other's
substitute, which is also what `AGENTS.md` says about the three verification
lanes.

## The decisions

### A library in the package, not a package of its own

`package:flutter_scene_layout3d/testing.dart`, with `flutter_test` moved from
`dev_dependencies` to `dependencies`.

The ecosystem precedent points the other way — `flame_test`, `bloc_test` — and
the reason it does is that a test library drags `flutter_test`'s pins into
every consumer. That cost is real and small here: `flutter_test` is an SDK
package, every Flutter application already has it in `dev_dependencies`, and
pub resolves an application's dev dependencies together with its regular ones,
so the pins are already in force for everyone who would use this. Nothing is
compiled into an application that does not import `testing.dart`.

What a separate package would cost is a second pubspec, changelog, README and
CI step now, and a second *publishing* decision later — and publishing is
exactly what the map defers until the real-application ports have answered
whether it is worth doing. Moving the library out later is an export and a
dependency, so this is the reversible choice, and it is taken for that reason.

### Finders are Flutter's, over the layout tree

`find3d` is to layout boxes what `find` is to widgets, and it is built on
`FinderBase<Layout3d>` — the generic base `flutter_test` already uses for its
semantics finders. That means `findsOne`, `findsNothing`, `findsExactly`,
`.first`, `.at(i)` and a finder's own failure description all work unchanged.
The second vocabulary this package refuses elsewhere (keys are Flutter's
`Intent`s, semantics are Flutter's `SemanticsProperties`) is refused here too.

What is searched is **every box on every surface mounted in the widget tree**,
in tree order, with each overlay's detached entries straight after the panel
that opened them — so a dialog is found without the test knowing it is on a
surface of its own. The surfaces are found through the render tree, by the
`Layout3dRootRenderBox` every `SceneLayout3d` mounts, which needs nothing
private.

The finders are the ones an author reaches for: by semantic label (what a
Material component publishes, and what a person reads), by the text of a
`Text3d` or `RichText3d`, by type and subtype, by node name, by predicate, by
the box holding the keyboard focus, and descendant and ancestor.

### A press goes through the screen, not down the depth axis

`tester.tap3d(finder)` projects the box's centre through the camera of the
`SceneInput3d` it is under, and taps **that point of the view** with Flutter's
own `tapAt`. Everything between the platform and the box runs: the ray, the
z-order between surfaces, absorption, detached entries, the arena. That is the
path an application runs and the one the ray-down-the-axis helpers skip, and it
is what makes "a screen nothing could press" a test failure.

Before tapping it asks the host what a press at that point would reach, and
**fails the test** if the box is not on the path — naming what is in front
instead. Flutter's `tap` only warns (`warnIfMissed`), and that is the one place
this library is stricter than Flutter on purpose: a missed tap is the defect
this repository has actually shipped, and a warning in a green run is a warning
nobody reads. `checkReachable: false` opts out, for a test that means to press
something covered.

That needs one addition to the input seam: **`Input3dHost.hitTestAt(Offset)`**
— every path a press at this point of the view would be dispatched to, front
to back, without dispatching anything. It is a list because the group's walk
carries on past a surface that does not absorb, and a box on a HUD in front is
reached by a press as surely as the panel behind it. It is useful beyond tests (a tooltip, an editor's pick, a debugging
readout), which is why it goes on the host rather than into the test library.

`drag3d` and `scroll3d` do the same for a drag and a wheel. There is no
`hover3d`, because Flutter has no `hover` either: the pattern is a mouse
`TestGesture` moved to `getCenter3d`, which the README shows.

### Pumping gives a test the host it would otherwise have to write

`tester.pumpSurface3d(child)` mounts one `SceneLayout3d` under a `SceneInput3d`
with a camera looking straight at its front face, framing it in the test view.
`tester.pumpScene3d(scene)` mounts the author's own surfaces the same way, and
frames the first one unless the test gives its own camera — which is how a test
asks about a panel turned the way the application turns it. A test that already
builds its own `SceneInput3d` pumps with `pumpWidget` as usual; everything else
here finds the host it is under.

The stand-in for the `SceneView` is `SizedBox.expand`, which is what
`test/input_test.dart` established: a `SceneView` needs a GPU, and the host
reads its own box for the view's size.

### Matchers for what layout can see, and nothing it cannot

- **`isReachable3d`** — a press at the box's projected centre reaches it.
- **`hasSize3d`** and **`hasSizeDp`** — the size in world units, and in logical
  pixels through the box's own metrics, per axis, each a number or a matcher.
  An author thinks in dp; a box is measured in world units, and that trap is in
  `docs/traps.md`.
- **`standsOnItsPanel3d`** — the box is not laid out behind the front face of
  the nearest `DecoratedBox3d` above it. It measures both boxes in the surface's
  frame with `Layout3d.localPointFrom`, which is the frame the shader draws in,
  so there is one answer to "where is this box" and not three.

Each applies to **every** box the finder found and fails on none, so
`expect(find3d.bySubtype<Text3d>(), standsOnItsPanel3d)` is a lint over a whole
screen. None of them is a golden: this repository's position that the laid-out
tree is the oracle holds for an author's screens as much as for its own.

### A photograph is a committed test, and CI keeps the pictures

`examples/render_probe` gets a second target, `integration_test/photograph_test.dart`,
that pumps **the gallery** — the application every one of the ten defects was
found in — inside a `RepaintBoundary`, lets it settle on real frames, and hands
the PNG to the driver. The driver writes it on the *host* side, into
`build/photographs/`, through `integration_test`'s own `onScreenshot` channel:
no app sandbox between the test and the file, and no CocoaPods work, because the
probe already committed it.

The photograph asserts the floor the probes assert — a frame came out, the
corners cleared, something lit drew — and nothing more, because the question it
exists for is *is anything obviously wrong*, which is a person's. CI runs it on
the render runner and uploads the pictures as an artifact, so every push to
`main` leaves a photograph of the gallery behind for someone to open.

`render_probe` depends on the gallery by path to do this. That is an example
depending on an example, and it is deliberate: a copy of the gallery's screens
in the probe would photograph the copy.

## The API

```dart
// package:flutter_scene_layout3d/testing.dart
const CommonLayout3dFinders find3d;
find3d.bySemanticsLabel(Pattern label)
find3d.text(String text) / find3d.textContaining(Pattern pattern)
find3d.byType(Type type) / find3d.bySubtype<T extends Layout3d>()
find3d.byName(String name) / find3d.byLayout(Layout3d layout)
find3d.byPredicate(bool Function(Layout3d) predicate, {String? description})
find3d.focused()
find3d.descendant(of: …, matching: …) / find3d.ancestor(of: …, matching: …)
abstract class Layout3dFinder extends FinderBase<Layout3d>

extension Layout3dWidgetTester on WidgetTester {
  Future<Layout3dSurface> pumpSurface3d(Widget child, {Size3d size, LayoutBasis3d? basis, Layout3dMetrics? metrics});
  Future<void> pumpScene3d(Widget scene, {Camera? camera});
  List<Layout3dSurface> get surfaces3d;
  T layout3d<T extends Layout3d>(FinderBase<Layout3d> finder);
  Iterable<T> layouts3d<T extends Layout3d>(FinderBase<Layout3d> finder);
  Offset getCenter3d(FinderBase<Layout3d> finder);
  List<HitTestResult3d> hitTest3d(Offset position);
  Future<void> tap3d(FinderBase<Layout3d> finder, {bool checkReachable = true});
  Future<void> drag3d(FinderBase<Layout3d> finder, Offset offset, {bool checkReachable = true});
  Future<void> scroll3d(FinderBase<Layout3d> finder, Offset delta, {bool checkReachable = true});
}

PerspectiveCamera cameraFacing3d(Layout3dSurface surface, {Size viewSize, double margin});

const Matcher isReachable3d;
Matcher hasSize3d(Size3d size, {double epsilon});
Matcher hasSizeDp({Object? width, Object? height, Object? depth});
const Matcher standsOnItsPanel3d;

// package:flutter_scene_layout3d/widgets.dart
Input3dHost.hitTestAt(Offset position) -> List<HitTestResult3d>
Layout3dPointerGroup.hitTestAll(Ray worldRay) -> List<HitTestResult3d>
```

## The boundary

- **Not the Material package's helpers.** Its suites test components below the
  host, with the imperative helpers that suit that, and moving five hundred
  tests onto a screen-level library is churn with no defect behind it. What
  it would want on top of this — a finder for a component by its role — waits
  for a customer.
- **Not the layout package's own suite**, for the same reason.
- **Not goldens.** See *Matchers*.
- **Not a photograph an author can take of their own application** without the
  probe's scaffolding. That is a packaging question — an `integration_test`
  helper in a published package drags in more than `flutter_test` does — and
  it belongs with the publishing plan the map defers. The probe's
  `integration_test/photograph.dart` is written so that it is the piece that
  would move.

## The work

- [x] `Input3dHost.hitTestAt`, on `SceneInput3d`, over a new
      `Layout3dPointerGroup.hitTestAll`.
- [x] `lib/testing.dart`: finders, the tester extension, the camera, the
      matchers; `flutter_test` moved to `dependencies`.
- [x] Tests for all of it, including the refusals and their messages: 25 in
      `test/testing_test.dart`. The suite is 1079.
- [x] The gallery's `screens_test.dart` rewritten on the library as the worked
      example, and checked to fail on the defects it pins — see
      *Verification*.
- [x] `render_probe`: `integration_test/photograph.dart`, the photograph
      target and its driver, the gallery dependency; run on this machine.
- [x] CI: the gallery's tests; the photograph, with the pictures uploaded.
- [x] The layout README (*Testing a screen*, and *Seeing it run*, whose
      "sixteen scenes" had been forty-four for a while), the gallery and probe
      READMEs, `docs/traps.md`, the changelog, `docs/README.md`, `AGENTS.md`,
      the map's row, entry and seams, and the catalogue plan's note that
      there was no committed way to photograph the gallery.

## Verification

`flutter test` is green in both packages and the gallery — 1079, 525 and 4 —
`dart analyze` is clean across the workspace, and `dart format .` has been run.
The photograph target was run with `flutter drive` on macOS: both photographs
came out, showed the whole gallery, and showed the upright panel and the mesh
list moved between them. The render probe suite — 91 tests now, where the
map's audit counted 75 — was run again after `render_probe` took the gallery as
a dependency, because that changes the probe's build, and passed. The CI steps
themselves have not run yet: they are written to match the commands run here,
and the first push will say whether the runner agrees.

The oracle the plan set for the library was the defects themselves, and both
were put back by hand and taken out again:

- **The slider card's padding back to `EdgeInsets3d.all(12)`** fails the
  gallery's third test on `standsOnItsPanel3d`: *"Semantics3d "Volume": its
  front is 11.80 dp behind the front face of DecoratedBox3d, which hides it. Is
  something between them insetting the front — an EdgeInsets3d.all where
  EdgeInsets3d.symmetric was meant?"* Not 12: the figure is measured where the
  content is drawn, and `Material3d` lifts its content a fifth of a logical
  pixel off its face.
- **The navigation bar lifted by its position** rather than by
  `SceneNodeShift3d` — the original scaffold defect, on one slot — fails the
  second and third tests on `tap3d`: *"a press at (500.7, 541.2) reaches
  DecoratedBox3d first, on the same surface, and the press never gets to the
  box"*, which is the scaffold's backing, exactly as the defect was first
  described.

Both files were restored and the suite re-run green.

## What the photograph found on its first run

**The app bar's title sits flush against the bar's leading edge.**
`AppBar3d` spends `titleSpacing` as the gap *between* the row's children, so a
bar with no `leading` widget puts its title at the bar's own 4dp padding and no
further; Flutter's `NavigationToolbar` insets the middle by `kMiddleSpacing`,
16dp, whether or not there is a leading widget. No suite and no probe asks
that, and the gallery's inbox bar has shown it in every frame since phase 9.

**Fixed, in a change of its own** after this plan closed. Writing the test for
it found the other half, which no photograph would have shown on the gallery:
Flutter reserves the same 16dp before the trailing slot too, so a bar with no
actions let a long title run to 4dp of its trailing edge. `AppBar3d` now keeps
the title `titleSpacing` off each edge that has nothing on it, measured from
the edge with the bar's padding counted toward it, for the small bar and the
headline of a medium or large `SliverAppBar3d`. Three tests in
`app_bar_test.dart` pin it — the two edges with nothing on them failed at 4dp
before the change — and a second photograph shows the title inset. Two
differences from Flutter were left for commits of their own. **With a leading
widget**, Flutter's leading slot is 56dp wide and the title starts at 72dp,
where this bar's 4dp padding and a 48dp button put it at 68dp — fixed with
`AppBarStyle3d.leadingWidth`, a slot measured from the bar's edge. A third
turned up while checking that one against Flutter and is **not** fixed:
Flutter's M3 bar has no padding before its actions (`actionsPadding` is zero),
so its last action is flush with the bar's trailing edge, and this bar's 4dp
`padding` holds its actions 4dp in.

**Nor was a centred title clamped** clear of the leading widget and the
actions, as Flutter's is — fixed in a commit of its own, and the test written
for it found the larger half. The centred toolbar was a stack, a stack
shrink-wraps its largest child, and its largest child was the title: the row of
controls positioned edge to edge was squeezed into the title's width and
overflowed, so any centred bar *with* controls drew them bunched around its
title. The gallery's only centred bar has none, which is why no photograph
showed it. The toolbar is Flutter's `NavigationToolbar` arithmetic now, in a
layout delegate. One of the new tests was wrong on its first run in a way
worth remembering: it called 'Inbox' short enough to centre beside three
actions, and at the test font's 22dp a letter it ends 3dp inside them, so the
clamp was right and the claim was not.

## What the library found once its helpers replaced the old ones

**A menu could not be pressed where it was drawn.** Replacing the Material
suite's two `offsetInSurface` copies with one definition of where a box is
drawn turned `PopupMenuButton3d`'s own test red: it had been aiming at where
the overlay laid the menu out — the empty middle of the panel — and a follower
answered hit tests there, because a node offset moves geometry and not the box.
Aimed where the item is drawn, through the camera with `tap3d`, the press
reached the barrier and closed the menu with nothing chosen. It is the hazard
this plan's opening section described, two helpers giving two answers to
"where is this box", and one of them was hiding a defect a person would have
met on the first menu they opened. `Follower3d` now shifts its hit test by its
node offset, the anchoring recipe in the layout README and `docs/traps.md` say
so, and the test presses through the camera. Fixed in a commit of its own,
before the helpers were replaced.

**The helpers themselves were replaced in the commit after it.** `testing.dart`
exports `drawnOffsetInSurface`, whose name says which frame it answers in, and
the Material suite's two copies of `offsetInSurface` are gone; the gallery's
copy had already gone when its test moved onto the library. Two things that
move taught. A handful of assertions compared the old sums with a tolerance of `1e-9`,
which a sum of doubles meets and a point carried through the nodes'
single-precision transforms does not; they compare to `1e-6` or `1e-4` now,
with the reason beside them. And the internal suites keep aiming rays straight
down the depth axis with `rayAt` — that is the right tool below the host, and
this plan's boundary still holds for it.

## What the reasoning got wrong

**The map treated the ten defects as one class wanting one instrument.** It
said they were invisible to the suites and the probes alike and asked for
"the instrument". Written out one by one, they are two classes: about half are
wrong *in the layout* — unreachable, too thin, sunk behind a face — and a
headless library catches them as soon as it presses through the camera instead
of down the depth axis; the rest are right in the layout and wrong in the frame,
and nothing but a picture sees them. The opening table is the plan's most
useful part for that reason, and it is why this plan built two things.

**The photograph route the map gave would have worked and hidden its output.**
`boundary.toImage()` written to `Directory.systemTemp` does land a file — in the
sandbox container, `~/Library/Containers/…/Data/tmp`, which is where the
catalogue plan found it and where a CI artifact step would never look. The
bytes go back through `integration_test`'s screenshot channel instead, and the
driver writes them on the host.

**The helper for the photograph could not live in the probe's `lib/`**, as this
plan first put it: the probe has `flutter_test` as a dev dependency, and a
library under `lib/` that imports it is an analyzer finding. It lives beside
the test, in `integration_test/`.

**`hitTest3d` was listed returning one path.** It returns every path, for the
same reason `hitTestAt` does.

**Two test mistakes, each of which read as a library bug for a minute.**
`find3d.byName('Column3d')` found nothing, because `SceneColumn3d` builds a
`Flex3d`; that is now a trap in `docs/traps.md`, because a person writing
`find3d.byType(Column3d)` will hit it too. And the first version of the miss
message named the deepest box on the path — a `GestureDetector3d#9a7a7` — which
tells a reader nothing about *which* control is in the way; it now names the
nearest semantic label on the path as well.

**And one thing found, first described wrongly, and then fixed.**
`Layout3dPointerGroup.hitTest` was documented as the front-most answering
surface's path, and in a walk that carries on past a surface that does not
absorb it returned the *last* answering surface's. This plan first said that
`SceneInput3d.onHit` reported that value too, so a HUD in front of a panel
would report the panel. **It did not**, and the claim was written without
reading the group's other walks: `down`, `hover`, `resolveScroll` and
`panZoomStart` each keep the first answering path, so `onHit` was right all
along. `hitTest` was the one walk out of step with its own dartdoc and with the
rest of the group, and nothing in either package called it. It was fixed in a
commit of its own after this plan closed: it keeps the first path now, and a
test in `overlay_test.dart` — written first, and failing on the old walk —
pins it beside the group's other tests.
