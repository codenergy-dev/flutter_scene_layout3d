---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
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

- [ ] **Phase 1 — `Overlay3d` in-plane.** Entries, ordering, the lift through
      `sceneOffset`, `Overlay3d.of`, insertion from a descendant.
- [ ] **Phase 2 — the barrier**, dismissal, and modal focus trapping.
- [ ] **Phase 3 — detached entries.** A surface per entry, parented to the
      host plane, with its constraints derived from the host.
- [ ] **Phase 4 — cross-surface hit routing** (`Layout3dPointerGroup`).
- [ ] **Phase 5 — `Navigator3d`.** Push, pop, results, the transition hook.
- [ ] **Phase 6 — README.** A section on what "in front" means here and why
      there are two answers.

## Tests

- An entry inserted from a deep descendant appears above every sibling and is
  hit first.
- The lift moves geometry and not boxes: the entry's box stays inside the
  surface, a `Positioned3d` pin inside it still lands where it was pinned.
- A barrier absorbs a ray aimed at the content behind it; `onTapOutside`
  fires; a tap inside the dialog does not dismiss.
- Two surfaces, one in front of the other: the router finds the front one
  first, and the back one when the front is dismissed.
- A detached entry survives the host panel being rotated, and (when bound)
  keeps facing the camera.
- Pushing and popping restores focus.

## Out of scope

Flutter `Navigator` interop, system back handling, hero-style transitions
between surfaces, and the Material components themselves.
