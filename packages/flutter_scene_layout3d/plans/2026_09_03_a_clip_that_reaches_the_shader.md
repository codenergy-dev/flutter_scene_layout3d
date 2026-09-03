---
status: completed
created_at: 2026-09-03T21:40:00Z
updated_at: 2026-09-03T22:10:00Z
commit: ad827c4b62fdf360e47433bdf8444de9f43d5862
---

# A clip that reaches the shader

Written and closed inside `flutter_scene_material3d`'s phase 4, because that
phase is the first work that actually built the scene the clip contract was
designed for — a raised card inside a clipping, scrolling list — and the scene
came out wrong.

## What was broken

The clip contract has three tiers: whole-node culling, clip planes packed into
a material, and nothing. Tier 2 is the interesting one, because it is the only
one that can cut a box that is **half** in: `Layout3d.clipRegion` →
`Decoration3dPaintRequest.clip` → `toPlaneBlock()` → six `clip_plane_n`
uniforms the panel shader discards against.

**That tier never fired.** Not for a scrolling list, not for a pinned header,
not anywhere. Two separate reasons, and both are invisible from the code:

1. **A box publishes its clip too early.** `DecoratedBox3d` writes the block
   from `repaint()`, called at the end of its own `performLayout`. A
   `ClipBox3d` is a `ProxyLayout3d`: it takes its size **from its child**, so
   while the child subtree is laying out the clip box has no extent, and
   `ClipBox3d.ownRegion` returns `Clip3dRegion.none`. Every panel under a clip
   was therefore handed the *unbounded* block on the layout that created it.

2. **Nothing ever replaced it.** A scroll does not relayout its rows — their
   constraints do not change — it *places* them somewhere else. So the stale
   unbounded block stood for the life of the box.

The result is a tier that is dead while looking alive: `clipRegion` reports
the right planes to anything that asks after layout, so every arithmetic test
passes, and only a drawn frame shows a row drawing straight through the edge
of the window it is inside. `docs/traps.md` said the tier was "live: a row
half under a pinned `SliverPersistentHeader3d` is genuinely cut at the bar's
edge". It was not, and that page is corrected in the same commit.

It was found with a `Decoration3dPainter` that recorded the clip in every
paint request it was given — which is the only way to see a shader block from
a headless test, and is what `test/clip_test.dart`'s `ClipRecorder` now is.

## What was done

One new protocol hook and two callers.

- **`Layout3d.refreshClipRegion()`** — re-reads `clipRegion` and republishes
  whatever the box did with it. A no-op by default, because most boxes do
  nothing with a clip. `DecoratedBox3d` overrides it to `repaint()`.
- **`ClipBox3d.performLayout`** now sweeps its subtree whether or not it is
  culling, and calls the hook on every box it does not cull. The sweep already
  ran after `super.performLayout()`, which is exactly the point in the pass
  where the clip box finally has an extent. That closes reason 1.
- **`Layout3d.place`** calls the hook down the moved subtree, and closes
  reason 2 — a scrolled row is under a different part of the window and
  nothing else can notice.

The cost of the second one is gated so that a tree with no clip in it pays
almost nothing: `place` walks the subtree only when `clipRegion` is bounded,
which is one walk up the parent chain that returns immediately when nothing
above clips. Inside a clip you pay one virtual call per descendant per move,
and a `DecoratedBox3d` among them pays a uniform write — the repaint-only
tier, which is what it is for.

`test/clip_test.dart` gains a group of three: the block a panel is given on
the layout that made it is the real clip and not the unbounded one; scrolling
a row republishes it with different numbers; and a tree with no clip publishes
exactly one unbounded block and nothing more.

## What it changed elsewhere

`examples/render_probe`'s `card_in_clipped_list` scene is the picture. Before
the fix, the half-scrolled card read as the *same colour* above and below the
window's edge — the frame's way of saying nothing was cut. After it, the card
is near-white inside the window and the backing shows through above it. That
scene failed on its first run with a luminance of 0.7597 outside against
0.7514 inside, which is how the defect surfaced at all.

## Two things still true and worth knowing

- **The plane tier is per-material, so only a material that reads the block
  honours it.** `box_decoration3d.fmat` does; a leaf holding an application's
  own material ignores the planes entirely and draws through the window. That
  is the contract, not a defect, and the class doc says so.
- **A depth clip cuts the box's *layout* depth, not the drawn geometry.** The
  planes are in the box's own frame and `BoxDecoration3d.elevation` moves the
  slab's node, outside that frame — so `ClipBox3d(clipDepth: true)` cannot
  slice a raised card off at the surface either. Which is fine: the whole
  reason `Clip3dRegion.rect` leaves depth alone is that a raised card should
  stand proud of the list holding it.
