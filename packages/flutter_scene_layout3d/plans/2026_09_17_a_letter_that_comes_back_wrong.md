---
status: pending
created_at: 2026-09-17T21:30:00Z
updated_at: 2026-09-17T21:30:00Z
commit: e1c4bc6c8f42eea060fb9f157ee6dc1deb21c1de
---

# A letter that comes back wrong

**Written for an implementer who has read only this plan.** It is a defect
report with an investigation attached, not a design. The symptom is
reproducible by a person and not yet by a test, and the first half of the work
is making it reproducible.

Read [docs/traps.md](../../../docs/traps.md)'s *A shared glyph atlas repacks,
and a panel that has stopped laying out loses its labels* before anything
else. This is the same family, and that page is most of the background.

## The symptom

A person running `examples/layout3d_gallery` sees individual glyphs come out
wrong — **intermittently**, on a screen that renders correctly a moment
earlier or later. Two kinds at once, photographed:

- **Letters missing.** `Ada Lovelace` drew as `Lovel ce`, `Grace Hopper` as
  `Gr ce Hopper`, `Unread` as `nread`.
- **Letters replaced by a dark speckled block** roughly the letter's size.
  `Notifications` drew as `Noti▓ications`, `Compact rows` as `Co▓pact rows`.

It survives the thing that caused it: the second pair was photographed on the
settings screen with **no overlay open at all**.

## What is established

Checked, not assumed.

1. **It is per glyph, not per label.** In the same photograph, `algebraic`
   keeps its `a` while `Lovelace` loses one. So it is not a missing font
   glyph and not a whole label failing.
2. **It is per *atlas*.** `glyphAtlasStyleOf` keys an atlas by the text style
   with its colours stripped, so a tile's title and its subtitle are drawn
   from two different atlases. The pairs above are always in the same style as
   each other. One atlas's picture of its alphabet is wrong; its neighbour's
   is fine.
3. **It is not the scrim, and not the overlay lift.** The settings photograph
   has no modal in it.
4. **Nothing in `lib/src/text/` has changed since `96da2eb`**, which is the
   commit that added the glyph **wall** — the extruded silhouette of a letter,
   traced off the raster, with its own shader. Every commit after it — the
   motion tokens, the overlay lift, the scrim's coverage — left the text layer
   alone. `git log 96da2eb..HEAD --name-only` over `src/text/` is empty.
5. **The three counters exist and are used.** `GlyphAtlas3d.generation`
   answers *are my texture coordinates still valid* and moves on a repack;
   `revision` answers *is my picture of the atlas still complete* and moves on
   every reservation; `outlineRevision` answers *have the silhouettes moved*.
   `_flush` compares generation **and** revision before clearing
   `_needsRaster`, which is the fix for the previously known half of this.
6. **`_attach` is not the bug.** It applies `_opacity` to both the glyph
   material and the wall material, so a label re-baked inside a fading subtree
   does not keep a stale fade. That was the first hypothesis and it is wrong.
7. **The photograph lane did not catch it.** `gallery_dialog.png` from the
   run at `e1c4bc6` — the gallery with a dialog open, which is the state the
   defect was reported in — has complete text. So one opening of one overlay
   is not enough to provoke it.

## The leading hypothesis, and it is not proven

**A settled label can end up with new-generation texture coordinates bound to
an old-generation texture, and draws garbage until the next raster lands.**

`AtlasText3dRenderer._onAtlasChanged` is the listener that re-bakes a label
whose box has stopped laying out. `GlyphAtlas3d._flush` notifies *after*
uploading, so at that moment the texture and the generation agree. But the
re-bake itself reserves glyphs, and the code says so in its own comment:

> Baking our glyphs can reserve one the atlas does not have, which repacks it
> again and invalidates what we have just baked — the same re-entrancy
> `render` guards against, and the reason this is a loop with a stop rather
> than one pass.

When that happens the loop re-bakes at the newer generation, and then:

```dart
_bindTexture(atlas.texture);   // the texture uploaded at the OLD generation
atlas.flush();                 // the new one is only now being rasterized
```

For every frame until that flush completes, the mesh samples the new layout
out of the old picture. A coordinate landing on another glyph's texels is a
**speckled block**; one landing on empty atlas is a **missing letter**. Both
symptoms, one cause, and intermittent by construction.

Two things to check that would confirm or kill it:

- The `do/while` has `++guard < 4`. **If it exits on the guard rather than on
  agreement, the mesh is left permanently stale** and only a later
  notification repairs it — which is a candidate for the settings screen
  keeping its bad letters with nothing open.
- Whether anything re-binds the texture when the flush *does* land. It should:
  the flush notifies, and the listener falls through to `_bindTexture`. Check
  that a renderer whose generation now matches actually reaches that line
  rather than returning early.

**A second hypothesis worth keeping alive**, because the speckled blocks are
its shape: the blocks are **wall geometry built from a bad outline**.
`_traceOutlines` caches by grapheme and never traces one twice —
`if (slot.isBlank || _outlines.containsKey(slot.grapheme)) continue;` — so an
outline traced once from the wrong pixels is wrong **for the life of the
atlas**, with no path that re-traces it. The guard on `_traceOutlines`'s
caller looks airtight (it runs only when the image's generation *and* revision
match the atlas's), so this may be nothing. It is listed because a permanently
cached wrong value explains persistence better than a transient window does,
and because the wall is the newest thing in this path.

## Why it started being seen now

The gallery gained an overflow menu, a dialog, a bottom sheet and a tooltip in
the motion-tokens work. Each introduces **new glyphs, late, in styles the
screen behind is already using** — which is precisely the case
`docs/traps.md` describes and the one the counters were added for. The trigger
is new; there is no evidence the cause is.

Do not assume it is a regression from the motion, lift or scrim work, and do
not assume it is not. Point 4 says only that no code in the text layer moved.

## The work

### 1. Reproduce it in a test, before changing anything

This is the half that matters, and it is possible: **the atlas is free of the
GPU.** Its own dartdoc says so — *"Free of the GPU and of `flutter_scene`,
which is what makes the atlas testable: a headless test rasterizes and reads
the texels back"* — and `GlyphAtlas3d.rasterize()` returns a
`GlyphAtlasImage3d` whose pixels a test can inspect.

Drive the cycle an overlay drives:

- one atlas, sized so it does **not** grow (`initialSize == maxSize`, the way
  `examples/render_probe`'s `two_surfaces_of_type` is built — an atlas that
  grows hides this whole family);
- a label laid out and flushed, so it has settled;
- then new graphemes reserved from a second label, *while a rasterization is
  in flight*, so the re-bake happens under a moving generation;
- assert every glyph's texture coordinates address that glyph's texels in the
  texture that is actually bound, and every outline matches its slot.

If that does not reproduce, the fault is on the renderer side rather than the
atlas, and `AtlasText3dRenderer` needs the same treatment with a fake atlas.

### 2. Then fix it

Nothing here prescribes the fix, because the mechanism is not proven. What the
fix must not do:

- **Do not go back to dropping the mesh and waiting for a layout.** That was
  the original answer and it is wrong for the documented reason: a repack
  happens while *something* is laying out, but not necessarily that box.
- **Do not remove a counter.** All three answer different questions and the
  page says which; a fix that collapses them will re-open a defect that is
  already closed.
- **Do not let an atlas grow to hide it.** A test whose atlas grows passes
  through this bug without touching it.

### 3. Make the lane catch it

`examples/render_probe`'s photograph lane photographs the gallery idle and
with a dialog open, and caught nothing — one opening is not enough for an
intermittent fault. Consider opening and closing an overlay several times
before the photograph, or a probe that asserts the texels under a known label
rather than asking a person to look.

## Boundary

- **The text layer only.** Nothing here should need to touch the overlay, the
  motion or the scrim work; if it does, that is a finding worth writing down
  rather than a licence.
- **Not the wall's design.** The wall exists and is correct in principle; this
  is about a letter that comes back wrong, whichever primitive draws it.
- **Not performance.** The counters cost what they cost.
