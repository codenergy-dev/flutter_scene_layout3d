---
status: completed
created_at: 2026-09-11T23:38:14Z
updated_at: 2026-09-12T00:05:00Z
commit: 5cd6dc0e51213479904537df038d703f3ccaa8ab
---

# An application that does not wire its own rays

The first plan off
[what a real application still needs](2026_09_11_what_a_real_application_still_needs.md),
and the one that map puts first because it is the item every other item is
consumed through. Porting a real screen is how that map is measured, and
before this the port began by copying ninety lines out of
`examples/layout3d_gallery` and getting the z-orders right.

## What is actually missing

There is no application layer. `examples/layout3d_gallery/lib/gallery.dart` is
the only worked example of an application wiring input, and what it has to
write before a single press lands is:

- a `LayoutBuilder` whose only job is to learn the view's size,
- a `Listener` for five pointer callbacks,
- a `_rayAt` that calls `camera.screenPointToRay` against that size,
- four handlers feeding `Layout3dPointerGroup.down` / `move` / `up` /
  `cancel` / `hover`,
- a `_syncPointers()` called from `onTick` **on every frame**, because a
  `SceneLayout3d`'s surface does not exist until the widget is mounted,
- inside it, `addSurface` with hand-authored `zOrder` values, and
  `syncDetachedEntries` for the overlay.

Three of those have silent failure modes, and *silent* is the word that makes
this a protocol gap rather than a boilerplate complaint. A z-order in the
wrong relative order routes a press to the panel behind, and nothing says so.
A surface registered before it exists is skipped — the `if (surface != null)`
in `_syncPointers` is exactly that hazard, and the reason the call is repeated
every frame instead of run once. A detached entry never synced is a dialog
nothing can press, which is a bug an author meets *after* shipping the dialog.

None of this is the author's problem to solve. Every fact the wiring needs —
which surfaces exist, which overlay hangs off which surface, when a surface
appears and disappears — is known to the widgets that own them.

## The decisions

### Who owns the ray

**A widget that wraps the `SceneView` rather than one that replaces it.**

The wrapping is forced: pointer events arrive at the Flutter widget layer, and
a `SceneView`'s declarative children are zero-sized hosts that never receive
one, so the `Listener` has to be an ancestor of the view. What is *not* forced
is whether the new widget builds the `SceneView` itself. It does not, and
deliberately:

- `SceneView` has more than twenty parameters, and a wrapper that forwards
  them is a list that rots every time the engine adds one. This repository is
  a consumer of `flutter_scene`, and a wrapper that has to track the engine's
  constructor is the kind of coupling that rule exists to avoid.
- The author keeps writing the `SceneView` they already know, with whatever
  `onTick`, `loading` or `viewsBuilder` they need. Nothing is taken away.
- It keeps the widget honest about its size. It owns input; it is not an app.

So:

```dart
SceneInput3d(
  camera: camera,
  child: SceneView(scene, camera: camera, children: [...]),
)
```

### How a surface gets into the group

**It announces itself on mount.** `SceneInput3d` publishes a scope; a
`SceneLayout3d` below it registers its surface in `didChangeDependencies` and
takes it out in `dispose`. That is the lifecycle change the map asked for, and
it is what retires `_syncPointers` entirely: there is no window between "the
widget is mounted" and "the surface is reachable", so nothing has to be
re-asserted every frame and nothing can be skipped forever because it was
asked for too early.

### The z-order is declared, not derived

The harder half of the design question, and the answer is the one the gallery
already reaches for by hand: **a property on `SceneLayout3d`.**

Geometry cannot answer "what is in front" for a surface turned away from the
camera — that is not an implementation gap, it is the question being
ill-posed. A panel at an angle is in front of another panel *for some pixels*,
and a pointer needs one answer for the whole surface. `Layout3dPointerGroup`
already took this position: it orders by `zOrder` first and breaks ties by
distance from the camera. This plan does not reopen it; it moves the statement
from the application's tick into the widget that owns the surface, where the
rest of that surface's configuration already lives.

`absorbsPointer` comes along for the same reason, since it is the other half
of what `addSurface` takes.

### An overlay's entries are synced at dispatch, not on a clock

A detached `Overlay3dEntry` is a surface of its own and has to be in the
group. Today that is `syncDetachedEntries` from `onTick`. Instead,
`SceneOverlay3d` registers its `Overlay3d` with the scope, and the scope syncs
the registered overlays' detached entries **immediately before each dispatch**.

The argument is that a per-frame sync is both too often and not often enough:
too often, because entries change when a dialog opens and not when a frame is
drawn; not often enough, because an entry inserted from a pointer callback is
unpressable until the next frame. Syncing at dispatch is exact — it is the
only moment the answer is consumed — and it costs a walk of a short list per
event, which is less than the hit test that follows it.

An entry's base z-order is the host surface's z-order plus one, so a dialog is
in front of the panel that opened it without the author restating the
relationship. The host is found through `Layout3d.owner`: every
`Layout3dSurface` attaches its tree to a private `Layout3dOwner`, so the scope
can keep an owner-to-surface map at registration and resolve `overlay.owner`
back to the surface it is laid out on.

**`Layout3dPointerGroup.syncDetachedEntries` has a defect this exposes.** It
tracks the surfaces it added in one flat `_entrySurfaces` set, shared across
every overlay it is called for, so with two overlays each call removes the
other's entries. One overlay is the only configuration that has ever been
tried. The fix is to key that bookkeeping by overlay, and it belongs here
because this plan is what makes two overlays ordinary.

### The camera is ambient

`SceneInput3d` knows the camera — it cannot turn a pointer position into a ray
without one — and `SceneLayout3d` and `SceneOverlay3d` both take one today
purely so a camera binding can run. Below a scope, both fall back to the
ambient camera, and an explicitly passed one still wins. This is wiring, which
is what this plan owns, and it removes the most-repeated argument in the
gallery.

### What the view's size is

Read from `SceneInput3d`'s own render box at dispatch time, rather than
through a `LayoutBuilder`. It is the same number, one widget cheaper, and it
does not rebuild the subtree on a window resize. `SceneLayout3d._resolveViewSize`
already sets this precedent. A `viewSize` property overrides it for the case
where the view renders into a sub-rectangle, matching `SceneLayout3d.viewSize`.

## The API

```dart
/// Owns the pointer group for every layout surface in a scene.
SceneInput3d({
  Camera? camera,              // ambient below here
  Input3dController? controller,
  Input3dHitCallback? onHit,   // after a press or a hover, what it found
  Size? viewSize,              // when the view is not this widget's box
  required Widget child,
})

/// Imperative access, the shape of Layout3dController and Overlay3dController.
///
/// One getter rather than a re-export of the host's surface: everything a
/// caller wants is on Input3dHost, and two ways to reach the same group is
/// two things to keep in step.
class Input3dController {
  Input3dHost? get host;   // null while unmounted
}

/// The seam the wheel, the navigator and the test library reach through.
abstract class Input3dHost {
  Layout3dPointerGroup get pointers;
  Camera? get camera;
  void registerSurface(Layout3dSurface surface, {double zOrder, bool absorbs});
  void unregisterSurface(Layout3dSurface surface);
  void registerOverlay(Overlay3d overlay);
  void unregisterOverlay(Overlay3d overlay);
}

// New on SceneLayout3d:
final double zOrder;          // what is in front of what, highest first
final bool absorbsPointer;    // whether a hit here ends the walk
```

`SceneInput3d.of(context)` / `maybeOf(context)` answer the scope, which is the
seam the three plans that consume this one reach through.

Two behaviours worth naming because they are not the obvious default:

- The `Listener` is `HitTestBehavior.translucent`, so the whole box reports
  pointers whether or not the scene painted anything there, and widgets behind
  the view still get their events. `SceneView`'s own internal `Listener` takes
  the same position for the same reason.
- A `MouseRegion` takes the pointer off every surface when the cursor leaves
  the widget, which is a hover state layer that today stays lit when the mouse
  leaves the window.
- `onHit` fires after `down` and `hover` and not after `move`, because those
  are exactly the two operations where the group recomputes `lastHit`. A
  captured move dispatches to the surfaces that already hold the press and
  does not ask what is under the ray, so reporting after it would report a
  stale answer.

## The boundary

This plan owns **wiring and ownership**. Specifically not here:

- **The events that exist.** A wheel, a trackpad and a key are
  [the next plan's](2026_09_11_what_a_real_application_still_needs.md#a-wheel-a-trackpad-and-a-key-that-reach-a-box),
  and they route through the scope this one publishes. `onPointerSignal` and
  `onPointerPanZoom*` are deliberately *not* wired here, because wiring them
  to nothing would be worse than leaving the seam visible.
- **Named routes and the back button**, which hang off this widget and are
  [their own item](2026_09_11_what_a_real_application_still_needs.md#an-application-with-more-than-one-screen).
- **Theming and localization.** This must not become a `MaterialApp3d`; each
  of those is an item of its own. What this plan owes them is a place to hang
  from, which is the scope.
- **A test library.** `SceneInput3d` has to be drivable from a widget test
  without a real window — and it is, because it takes a `child` rather than
  building the view — but the finders and matchers are
  [their own plan](2026_09_11_what_a_real_application_still_needs.md#a-way-to-test-a-screen-someone-else-built).

## The work

- [x] `Layout3dPointerGroup.syncDetachedEntries`: track added entry surfaces
      per overlay, so two overlays do not evict each other. Grew a
      `forgetDetachedEntries` as its counterpart.
- [x] `SceneInput3d`, `Input3dController`, `Input3dHitCallback` and the scope,
      in `lib/src/widgets/input.dart`; exported from `widgets.dart`.
- [x] `SceneLayout3d`: `zOrder` and `absorbsPointer`, registration on mount,
      re-registration when they change, removal on dispose, ambient camera.
- [x] `SceneOverlay3d`: registration on mount, removal on dispose, ambient
      camera.
- [x] Rewrite the gallery over it: 107 lines gone, 42 added, and most of the
      42 are the comments explaining what the z-orders mean.
- [x] Tests: fourteen, in `test/input_test.dart`. The suite is 1005.
- [x] The package README's input section, the gallery README, the layout
      package's changelog, `docs/README.md`, `AGENTS.md`'s package table and
      test count, and the map's row.

## Verification

`flutter test` in both packages and the gallery, `dart analyze` clean,
`dart format .`. The gallery is the real oracle for this one and it has to be
*looked at*: the three surfaces still press, the snack bar still takes a tap,
and the readout still names what is under the cursor.

## What the reasoning got wrong

**The design question this plan called the harder half was the easy half.**
Who owns the z-order took one property and one paragraph: the group already
ordered by a stated z-order with a camera-distance tie-break, so moving the
statement from the application's tick to the widget that owns the surface
changed nothing about the contract. What was actually hard was the thing this
plan mentioned in a subordinate clause — the overlay — because it is the only
part where the widget layer does not already know the answer. An overlay does
not know which surface it is laid out on, and the entries are not widgets, so
the host has to resolve `Layout3d.owner` back to a surface through a map it
keeps itself. That is the one piece of machinery here that is not obvious from
reading the widgets.

**And the map's claim that this lane was "surface, not debt" was not quite
right.** The audit found no markers and concluded the machinery underneath was
sound. It nearly was: `syncDetachedEntries` tracked the surfaces it had added
in one flat set shared across every overlay, so a second overlay would have
had its entries evicted by the first one's sync. Nothing had ever held two,
because one application had ever wired this by hand and it had one panel with
an overlay. **The defect was invisible precisely because the wiring was
manual** — a gap that only appears once the thing becomes ordinary is not
findable by grepping for `TODO`, and it is an argument for building the
application layer earlier rather than later.

**A smaller one:** the plan assumed the view size wanted a `LayoutBuilder`, as
the gallery had it. Reading the host's own render box at dispatch is the same
number, one widget cheaper, and it does not rebuild the subtree on a window
resize. The precedent was already in `SceneLayout3d._resolveViewSize` and the
plan had read that file without noticing it.

**What was deliberately not done, and stays open:** the wheel, the trackpad
and the key. `onPointerSignal` and `onPointerPanZoom*` are not wired, because
wiring them to nothing would hide that they are missing. That is the next
item on the map, and it lands on `Input3dHost`.
