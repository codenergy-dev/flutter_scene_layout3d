---
status: completed
created_at: 2026-09-08T21:10:00Z
updated_at: 2026-09-08T23:40:00Z
commit: c16d46bf114f82298cc218537ef0128e49b9c1d6
---

# A widget under an overlay entry

The overlays plan shipped `Overlay3d`, `Overlay3dEntry` and `Navigator3d`, and
left one thing open with a note beside it:

> **Widget-built entries are the obvious follow-up** and the one thing
> `flutter_scene_material3d` may want early.

It did. Phase 6 of the Material catalogue is the overlays — `Dialog3d`,
`Menu3d`, `SnackBar3d`, `Tooltip3d`, `BottomSheet3d` — and every one of them is
a widget over `Material3d`, while an entry's content is a `Layout3d` returned
by a builder. Nothing in the declarative layer can bridge that from outside the
package: the mirroring that turns a render child list into a layout child list
lives on `Layout3dRenderBox`, which is not exported and should not be.

Two things, both small, and the second one is not about entries at all.

## 1. A widget subtree as an entry's content

The shape is Flutter's own, without its second reconciliation path. An entry's
content stays a `Layout3d`; what a `WidgetOverlay3dEntry` returns is an **empty
slot**, and the widget layer fills it in.

- `Overlay3dContentSlot3d` — a `ProxyLayout3d` with one settable child, built
  by the entry at insertion so the entry is complete (barrier up, focus scope
  in place) from the moment it goes in.
- `WidgetOverlay3dEntry` — an `Overlay3dEntry` whose `contentBuilder` returns
  a `Widget`. Everything else about an entry is inherited unchanged.
- `WidgetPageRoute3d` — the same for a route, so `Navigator3d.push` is usable
  from the declarative layer.
- `Overlay3d.entriesChanged` — a `Listenable`, fired on insert, remove and
  rearrange. `SceneOverlay3d` listens and rebuilds; nothing else has to.
- Inside `SceneOverlay3d`, one host per widget-built entry: a
  `Layout3dRenderBox` that **does not mirror**. It lays its render children
  out, hands the subtree to the entry's slot instead of adopting it, and
  leaves a zero-sized anchor among the overlay's base children so that every
  hosting box still carries a layout.

### Who owns what

The one question worth getting right. A widget owns the layout it created,
everywhere else in this package, and an entry disposing a widget-built subtree
would make two owners of one tree. So:

- Removing an entry **releases** the content: `Overlay3dContentSlot3d.dispose`
  sets `child = null` first, which unparents without disposing.
- The reparenting host disposes it when *it* leaves the element tree, which is
  the frame after. Between the two the subtree is an orphan with no parent and
  no owner, laid out by nobody, which is exactly what it should be.

### The one-frame rule

Inserting an entry marks the widget that owns the overlay as needing to build,
so the content exists on the next frame. Flutter's `Overlay` behaves the same
way. The barrier does **not** wait: it is built by the entry, so a modal is
modal from the instant it is inserted. A test pumps once after opening.

## 2. `Layout3d.anchorOffsetTo`

Nothing anchors anything. An entry is placed by the overlay's own
`Stack3d.alignment`, which is nowhere near the box that asked for it, and a
menu belongs at its button. Flutter's answer — `CompositedTransformTarget` and
`CompositedTransformFollower` — has no analogue here.

`Draggable3d` already solved it privately, in `_homeOver`: take the anchor's
point into the world through `worldTransform` and back out again in the
follower's frame. That arithmetic is now public as
`Layout3dAnchoring.anchorOffsetTo`, with two alignments so a menu's top-left
can sit on its button's bottom-left.

Three properties, all of them consequences rather than choices:

- **It answers a `nodeOffset`, not a `place`.** The node tier writes one
  matrix and never lays out, which is the only tier a follower may re-anchor
  on per frame.
- **It is a position, not a delta.** `worldTransform` reports the frame layout
  put the box in, with `nodeOffset`, `sceneOffset` and `nodeTransform`
  undone — so the answer is where to nudge to, and re-anchoring is another
  assignment rather than an accumulation that drifts.
- **It leaves depth alone by default**, keeping whatever lift the follower
  already has. `Draggable3d` learned that one from a render probe: correcting
  depth too lands the follower on the anchor's own plane and makes the depth
  test a coin toss.

## The work

- [x] `Overlay3dContentSlot3d`, `WidgetOverlay3dEntry`, `WidgetPageRoute3d`.
- [x] `Overlay3d.entriesChanged`, and `SceneOverlay3d` listening to it.
- [x] The reparenting host, its anchor, and the ownership rule above.
- [x] `Layout3dAnchoring.anchorOffsetTo`.
- [x] `test/overlay_widget_entry_test.dart` — 15 tests: the one-frame rule,
      the subtree hanging under the entry rather than beside it, state kept
      across a rebuild of the overlay, disposal happening exactly once, focus
      trapped around a widget subtree, an entry with no widgets in it costing
      no rebuild at all, a route pushed and popped with a result, a tap on the
      barrier popping it, the five anchoring cases, and the README's two new
      snippets compiled verbatim.

## What the original reasoning got wrong

**Nothing, but it under-sold the cost of the alternative.** The overlays plan
called widget-built entries "an `Overlay`-style element with a child list of
its own (Flutter's `_OverlayEntryWidget` plus `_RenderTheatre`) … a second
reconciliation path", and declined. That is still the right call and it is not
what this change does: there is no second path here, only a host that hands
what the *first* path reconciled to a different parent. Twenty lines, and the
element machinery keeps doing the work.

**`Draggable3d` is not refactored onto `anchorOffsetTo`, deliberately.**
`_homeOver` computes the same product and keeps a by-product — the rotation
between the two frames, which the drag needs to turn a pointer delta into
travel in the feedback's frame — so calling the public helper would compute
the inverse twice. The arithmetic is stated once in prose, in both places,
which is the honest version of sharing it.

**A zero-sized anchor is a real child of the overlay, and that is visible.**
`Overlay3d.children` reports it, so a test counting the overlay's children
sees one more box per widget-built entry. Cheaper than the alternatives (a
child list the stack skips, or a nullable layout on a hosting box) and it
costs nothing at layout: `constraints.smallest` in a stack is nothing, and a
zero-extent box answers no ray.
