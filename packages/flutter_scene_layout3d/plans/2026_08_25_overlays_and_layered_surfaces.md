---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-27T00:00:00Z
commit: 657eef80eb8dc8085c3b3a84a8069273495506be
---

# Overlays: dialogs, menus, and what "in front" means

`Scaffold3d`, `Dialog3d`, `Menu3d`, `SnackBar3d`, `Tooltip3d`, `Drawer3d` and
`BottomSheet3d` are all the same mechanism wearing different clothes: put
something above everything else, possibly outside its parent's bounds,
dismissible from outside. Flutter spells it `Overlay` plus `Navigator`. This
package has neither, and no way for a descendant to insert anything anywhere
but under its own parent.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).
Uses the dispatcher from
[pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md) and the scrim
from [size-driven geometry](2026_08_25_size_driven_geometry.md).

## The direction taken

**A dialog floats in front of the panel, offset along the depth axis.** That
is the decision, and it is the default. The alternative — a dialog on its own
surface in front, layers rather than depth — is not rejected: it is what a
menu needs when it must extend past the panel's edge, and what a dialog wants
when the panel is angled and the dialog should still face the viewer. So this
plan builds one API with the layer choice as a per-entry property, defaulting
to in-plane.

## The two shapes, honestly

### (A) In-plane, lifted toward the viewer

`Overlay3d` is a stack-like layout at the top of one surface. Entries are
inserted from anywhere through an inherited handle, positioned with
`Positioned3d`, and lifted toward the viewer.

The lift already has a mechanism: `ParentData3d.sceneOffset`, the offset that
moves a child's *geometry* without moving its box. `Stack3d.depthStep` is
built on it precisely so that later children stop fighting the depth buffer
without their boxes leaving the parent, a `Positioned3d` pin surviving intact
and a ray still finding the top child first. An overlay entry lifted this way
inherits all of that.

- Cheap: one surface, one layout pass, one plane node.
- Hit ordering is already correct — last child wins, ray-first.
- The barrier is a full-extent box that absorbs pointers, which
  `AbsorbPointer3d` already is.
- **But** the entry is bounded by the surface's box, so a menu cannot escape
  the panel edge, and the depth budget is whatever thickness the panel has —
  the trap the README names about geometry standing out through a plane.

### (B) A surface of its own, in front

Each entry gets its own `Layout3dSurface` with its own plane, parented to the
host plane (or to the camera).

- Unbounded by the host panel; a menu may overhang.
- Can be camera-bound independently
  ([camera-bound surfaces](2026_08_25_camera_bound_surfaces.md)), so a dialog
  faces the viewer while the panel behind it stays angled. Flutter has no
  analogue and users will want it.
- Its own basis, constraints and metrics.
- **But** hit testing must be routed across surfaces in a defined order, focus
  traversal crosses surfaces, and "what constrains this dialog" has to be
  answered explicitly — the host surface's size, or the camera's view.

### The API that carries both

```
Overlay3dEntry(
  builder: ...,
  layer: OverlayLayer3d.inPlane(lift: ...),   // default
  // or OverlayLayer3d.detached(binding: ...),
)
```

One `Overlay3d`, one insertion API, one route stack; the 3D question is
answered per dialog by the caller. Components in `flutter_scene_material3d`
pick a sensible default each (`Dialog3d` in-plane, `Menu3d` and `Tooltip3d`
detached) and let the app override.

## The pieces to build

**`Overlay3d` and `Overlay3dEntry`**, with `Overlay3d.of(context)` in the
declarative layer and a plain object in the imperative one. Entries are
ordered, insertable above or below a given entry, and removable.

**Cross-surface hit routing.** Required by (B), and useful anyway: a
`Layout3dPointerGroup` that tests surfaces front-to-back — by explicit
z-order, falling back to camera distance — and stops at the first that
absorbs. This is overlay-specific ordering built on the dispatcher from
[pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md), and it belongs
to this plan.

**The barrier.** A full-extent `AbsorbPointer3d` with a scrim decoration and
an `onTapOutside`. A scrim in a scene is a translucent slab, so it wants the
opacity contract from
[size-driven geometry](2026_08_25_size_driven_geometry.md); a dimming tint or
a darkened material is the fallback until that lands.

**`Navigator3d`**, a thin route stack over `Overlay3d`: push, pop, a result
future, and a transition hook for
[animation](2026_08_25_animation_and_scroll_physics.md) to fill in later.

Do **not** try to wire this into Flutter's own `Navigator`. Flutter's overlay
is a stack of `RenderBox`es and its routes build 2D widgets; the impedance
mismatch is total. Interop — a 3D dialog opened from a 2D route, or the system
back button popping a `Navigator3d` — is a real question and an explicit
non-goal for the first version. Write down that it is deferred so the next
reader does not assume it works.

**Focus across the stack.** A modal entry should trap focus. Flutter's
`FocusScope` does this and works in the declarative layer; wire an entry to
its own scope and restore focus on pop.

## The work

- [x] **Phase 1 — `Overlay3d` in-plane.** Entries, ordering, the lift through
      `sceneOffset`, `Overlay3d.of`, insertion from a descendant.
- [x] **Phase 2 — the barrier**, dismissal, and modal focus trapping.
- [x] **Phase 3 — detached entries.** A surface per entry, parented to the
      host plane, with its constraints derived from the host.
- [x] **Phase 4 — cross-surface hit routing** (`Layout3dPointerGroup`).
- [x] **Phase 5 — `Navigator3d`.** Push, pop, results, the transition hook.
- [x] **Phase 6 — README.** A section on what "in front" means here and why
      there are two answers.

## What was built

- `lib/src/overlay/overlay.dart` — `Overlay3d` (a `Stack3d` whose entries are
  appended after its base children), `Overlay3dEntry`, and the sealed
  `OverlayLayer3d` with `InPlaneOverlayLayer3d` and `DetachedOverlayLayer3d`.
- `lib/src/overlay/modal_barrier.dart` — `ModalBarrier3d`.
- `lib/src/overlay/navigator.dart` — `Navigator3d`, `Route3d`, `PageRoute3d`,
  `Route3dTransition`.
- `lib/src/input/pointer_group.dart` — `Layout3dPointerGroup`.
- `lib/src/input/focus.dart` — `FocusScope3d`, `Focus3d.enclosingScope`,
  `Focus3dTraversal.traversalRootFor`.
- `lib/src/widgets/overlay.dart` — `SceneOverlay3d`, `Overlay3dController`,
  `SceneModalBarrier3d`.
- `test/overlay_test.dart` — 40 tests, including every case listed below.

## What the original reasoning got wrong

**`Overlay3d.of(context)` is `SceneOverlay3d.of(context)`.** `Overlay3d` is a
layout in the core library, which has no `BuildContext` to be found through;
`Overlay3d.of(Layout3d)` is the imperative walk (and it crosses out of a
detached entry, which is on another surface, through an `Expando` the entry
registers). The declarative handle is on the widget, beside `SceneLayout3d`'s
`Layout3dController`.

**An entry's content is a `Layout3d`, not a widget subtree.** The plan wrote
`Overlay3dEntry(builder: ...)` without saying what a builder returns. It
returns a layout: giving entries widget subtrees means an `Overlay`-style
element with a child list of its own (Flutter's `_OverlayEntryWidget` plus
`_RenderTheatre`), which is a second reconciliation path through
`Layout3dLazyElement` and is not what this plan bought. The layout objects are
the same ones the widgets drive, so nothing is out of reach, and
`Overlay3dEntry.markNeedsBuild` disposes the old subtree and builds a new one
in place. **Widget-built entries are the obvious follow-up** and the one thing
`flutter_scene_material3d` may want early.

**The lift is written by the entry's host box, not by the overlay's
`performLayout`.** `Stack3d.performLayout` already writes
`ParentData3d.sceneOffset` for its depth step, so an overlay that wrote the
lift there would be fighting its own superclass. The entry's host overrides
`Layout3d.sceneOffset` to add the lift instead: same mechanism, different
writer, and the two compose. Everything the plan wanted from it holds — the
box does not move, a `Positioned3d` inside still pins, and `hitTestChild`
shifts by `offset` alone, so a ray finds the entry by its place in the stack.

**A detached entry needs two nodes, not one.** The plan said "parented to the
host plane", which is right until a camera binding is involved: a binding
writes a *world* transform onto the plane (`_planeTransform` builds it from
the inverted view matrix) and has no idea what it is hanging under. So each
detached entry has a frame node between the anchor and the plane. It is
identity while the entry follows the panel, and the inverse of the anchor's
world transform once a binding drives the plane, with the plane's translation
set to where the panel anchored the entry in world terms — so a billboarded
dialog keeps the position the panel gave it and takes only its facing from the
camera. That is what the "keeps facing the camera" test asserts.

**And the detached surface's basis depends on whether it is bound.** Unbound,
its plane hangs in the host's *layout* space (the host surface's basis has
already been applied above it), so it must add none of its own:
`DetachedOverlayLayer3d.hostBasis`, the identity. Bound, the binding's
world-space transform is built for `LayoutBasis3d.xy`, so that is the default
there. Getting this wrong applies the basis twice and mirrors the entry.

**The barrier is its own layout, not an `AbsorbPointer3d` with a decoration.**
It has to fill what it is given (an absorber is a proxy and takes its child's
size) and it has to see a down *and* an up to know a tap outside from a drag
that started on the dialog. `ModalBarrier3d` does both. The scrim is its
child, so a caller decorates it; a translucent one still waits on per-node
opacity in the engine, exactly as the plan said.

**Focus trapping needed a change to `Focus3d`.** `requestFocus` asked
`owner.focusScope` — the surface's — so a modal's own scope would never have
been consulted. It now asks `enclosingScope`, the nearest `FocusScope3d`
above it, falling back to the surface's. Restoring focus on pop also has an
ordering constraint the plan did not foresee: disposing a focus node that
still holds primary focus makes Flutter's manager pick a successor of its own,
and the last request wins, so the restore has to run *after* the entry's
subtree is disposed rather than before.

**Cross-surface absorption is "the surface answered".** A `Layout3dPointer`
returns an empty result when nothing on the surface took the hit, so
front-to-back with a stop at the first non-empty result is the whole rule.
`absorbs: false` per surface is the escape hatch for a HUD that must not block
the world, and a press captures every surface that answered it.

## Left open, deliberately

- **Widget-built entries** (see above).
- **Focus traversal across surfaces.** Trapping is done and
  `Focus3dTraversal.traversalRootFor` is the hook, but a `Tab` that walks from
  a detached entry into the panel behind it has no policy. It was named as a
  cost of shape (B) in this plan, not as a deliverable, and it is the same
  open item the pointer-dispatch plan left.
- **Transitions.** `Route3dTransition` is the seam and `none` is the only
  implementation; the animation plan fills it in. `reverse` is awaited before
  the entry is removed, so a leaving route is on screen for the whole of it.
- **Flutter `Navigator` interop and system back handling**, which this plan
  puts out of scope and which stay out of it.

## Tests

All of these are in `test/overlay_test.dart`, plus ordering and insertion
around a named entry, teardown (removing an entry disposes what it built, and
disposing the surface takes the entries with it), the unit contract reaching a
detached entry from the host, dirt inside a detached entry reaching the host's
flush, the route stack's results, and the declarative layer.

- [x] An entry inserted from a deep descendant appears above every sibling and
  is hit first.
- [x] The lift moves geometry and not boxes: the entry's box stays inside the
  surface, a `Positioned3d` pin inside it still lands where it was pinned.
- [x] A barrier absorbs a ray aimed at the content behind it; the dismissal
  callback fires (`onDismiss`, not `onTapOutside`); a tap inside the dialog
  does not dismiss.
- [x] Two surfaces, one in front of the other: the router finds the front one
  first, and the back one when the front is dismissed.
- [x] A detached entry survives the host panel being rotated, and (when bound)
  keeps facing the camera.
- [x] Pushing and popping restores focus.

## Out of scope

Flutter `Navigator` interop, system back handling, hero-style transitions
between surfaces, and the Material components themselves.
