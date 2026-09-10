---
status: completed
created_at: 2026-09-10T13:55:00Z
updated_at: 2026-09-10T19:15:00Z
commit: a29484bca4b1b60ce78d58b061a88bab04de3a6c
---

# A label that survives a repack

## What happened

`examples/layout3d_gallery` is the first thing in this repository to put **two
lots of type in one scene**. Every render probe draws one surface; every
headless test measures rather than rasterizes. The gallery draws a Material
screen on an upright panel, a second one on the ground plane, and a scrolling
list of meshes beside them, and the first frame it produced had an app bar
reading `nb` where it should have read `Inbox`, three list tiles with no
titles, a navigation bar with one of its two labels missing, and a black
rectangle where the other one belonged.

The mechanism is one comment that was true when it was written and is not true
any more. `GlyphAtlasCache3d.shared` is shared by every renderer in the
application, and a glyph reserved in it can repack the whole atlas, which
invalidates every texture coordinate baked into every mesh drawn out of it.
`AtlasText3dRenderer` handled that in `_onAtlasChanged` by throwing its mesh
away:

```dart
// The atlas repacked under someone else's glyph: every UV in this mesh
// is stale. Drop it and let the next layout bake new ones — which the
// box will do, because a repack only happens while it is laying out.
```

A repack does only happen while *something* is laying out. It does not have to
be **this** box. A panel whose labels were laid out once and thereafter only
*turned* — which is exactly what the gallery's upright screen does, and what
this whole package is for — never lays out again, so the mesh it was told to
drop is never rebuilt and the label is gone for good.

## What the first pass fixed

`_onAtlasChanged` now bakes the glyphs again itself rather than waiting for a
layout. Everything it needs is already cached on the renderer for the identity
check `render` does — the `TextLayout3d`, the parent `Node`, the style and the
unit rate — so the rebuild costs one `buildTextGlyphQuads` and one geometry
upload, and no layout at all. It loops, with a stop at four passes, because
reserving *our* glyphs can repack the atlas again, and a `_rebuilding` flag
keeps that from re-entering.

The effect on the gallery is large and visible: the list tiles get their titles
and subtitles back, the navigation bar gets its selected label back, and the
table screen's chips all read correctly.

## What was still wrong, and what it turned out to be

None of the three things this plan proposed trying was the cause. The cause was
in `GlyphAtlas3d.flush`, one line, and it had nothing to do with texture
coordinates at all — **the glyphs were never rasterized in the first place.**

`flush` rasterizes like this: `rasterize()` records a `ui.Picture` of every
reserved glyph *synchronously*, then awaits `picture.toImage`. Anything
reserved during that await is missing from the image. `_flush` guarded against
that by comparing the image's `generation` with the atlas's — and a
**generation only moves when the atlas repacks**. A glyph reserved into free
space does not repack. So the image came back looking current, `needsRaster`
was cleared, the texture was uploaded a letter short, and nothing ever asked
for those glyphs again: their slots existed, their quads pointed at them, and
the texels behind them stayed empty for the life of the process.

That is the whole of the remainder, and it explains the shape of it exactly:

- **Why two surfaces and not one.** One surface reserves its whole alphabet in
  a single layout pass, which overflows a 128-texel atlas and grows it — and a
  repack *does* move the generation, so the in-flight image is discarded as
  stale and everything is drawn again. By the time a second surface lays out
  the atlas is already big enough, its reservations find free space, and
  nothing says the picture is out of date. The screen drawn alone was perfect
  for that reason and no other.
- **Why only some labels.** Whatever was reserved before the first `flush` of
  a style survived; everything reserved after its snapshot did not. `Inbox`
  losing three of five letters, a tile keeping its title and losing its
  subtitle, are the same sentence.

The fix is to count *contents* as well as repacks. `GlyphAtlas3d.revision`
moves whenever a glyph is reserved **and** whenever the atlas repacks;
`GlyphAtlasImage3d` carries the revision it was rasterized from; and `_flush`
keeps looping until it has an image of the atlas as it now stands. `generation`
keeps its old meaning — *are my texture coordinates still valid* — and is what
`AtlasText3dRenderer` still compares against.

Two smaller things came with it, both real:

- **The black quad was an `UnlitMaterial` with no texture.** It is not a quad
  sampling empty atlas — an empty region has zero alpha and draws nothing.
  `UnlitMaterial` binds a **1x1 white placeholder** when no texture is set, so
  a glyph mesh attached before the atlas has ever uploaded anything draws its
  quads as solid rectangles in the label's own colour. `_bindTexture` now
  zeroes the colour factor while there is no texture, so such a mesh draws
  nothing until the pixels arrive.
- **`flush` ownership**, the third thing this plan proposed and the only one
  that was worth doing anyway. `_onAtlasChanged` rebuilds outside `render`, and
  `render` used to be the only caller of `flush`; a panel that has settled has
  nothing left to call it. It now says `flush` itself, which is a no-op when
  the texture is current.

The other two candidates were checked and are not defects. Every renderer *is*
subscribed — `render` adds the listener whenever the atlas identity changes and
`_atlas` is only ever assigned there. And a slot cannot move inside a
generation: `_pack` only ever appends, and the one thing that moves a slot,
`_grow`, calls `_reset`, which bumps the generation.

## The probe

`examples/render_probe`'s `two_surfaces_of_type`, and it is the first scene in
that harness to draw **two** lots of type. Two surfaces side by side, each with
a two-letter label in the same style, sharing one `GlyphAtlasCache3d`; the
first reserves `A` and `B` and starts the raster, the second reserves `X` and
`Y` while it is in flight. The assertion asks for ink in each half of each
label's own screen bounds — two letters straddle the centre of their box, so a
disc there is the wrong question and was the first one tried.

The scene's atlas is built with `initialSize` equal to `maxSize`, and that is
load-bearing rather than tidy: it can never repack, so the generation can never
move, and the revision is the only thing left that can notice. An atlas that
grows hides this bug, which is the whole reason a Material screen drawn alone
did.

Verified both ways. Before the fix the second surface's label draws **nothing
at all** — `centroidXIn` over its box returns null; after it, both letters of
both labels are there.

## How it was actually looked at

Not with the throwaway harness this plan originally described. `examples/render_probe`
already has `integration_test` wired up and a macOS runner committed, so a
scratch test file in *that* app — one that builds a `Scaffold3d` with a real
`NavigationBar3d` on a `SceneLayout3d` and writes `boundary.toImage()` to
`Directory.systemTemp` — photographs a Material screen with no CocoaPods work
at all. The file lands under `~/Library/Containers/dev.codenergy.renderProbe/Data/tmp`,
because the runner is sandboxed. That is the cheaper recipe, and it is what
found the mechanism behind the other half of phase 9's findings too.
