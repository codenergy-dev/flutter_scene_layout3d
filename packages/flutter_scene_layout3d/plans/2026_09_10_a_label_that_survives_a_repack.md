---
status: in progress
reason: the repack invalidation is fixed and a panel's labels come back, but a second surface sharing the atlas still costs *some* labels — an app bar reading "nb" for "Inbox" and a stale black quad where a navigation label should be. The cause of the remainder is not yet identified and there is no probe pinning either half
created_at: 2026-09-10T13:55:00Z
updated_at: 2026-09-10T13:55:00Z
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

## What is fixed

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

## What is still wrong

Not all of it. On the same frame, after the fix:

- the upright screen's app bar still reads `nb` for `Inbox`, and only ever
  those two glyphs — which is what a mesh baked against a *very* early
  generation looks like, since the first glyphs into an atlas keep their slots
  across a repack;
- two of the three list tiles show a title but no subtitle;
- one navigation destination's label is a black rectangle rather than type,
  which is a quad sampling a region of the atlas that holds nothing.

The same screen drawn **alone**, on one surface, is perfect: the head-on
capture in this phase's notes shows every label, every icon and both
destinations. So whatever is left is still about two surfaces sharing one
atlas, and it is not the invalidation path above, because that path now
rebuilds.

Three things worth trying, in order:

1. **Reservation order.** `buildTextGlyphQuads` both reserves and bakes. A
   renderer that bakes while another renderer is mid-reservation may be
   reading slots that are about to move. The loop above handles the case where
   the generation changes; it does not handle a generation that stays the same
   while a slot moves, if that is possible.
2. **Whether every renderer is actually listening.** `render` adds the
   listener only when the atlas identity changes. A renderer that is created,
   renders once, and is then reparented may end up holding an atlas it is no
   longer subscribed to.
3. **`flush` ownership.** Only `render` calls `atlas.flush()`. A renderer that
   rebuilds outside `render` — which is now the common case — never uploads,
   and depends on some other renderer flushing for it. A panel that has
   settled has nothing left to call it.

## How to see it

There is no probe for this, and that is the gap. It cannot be covered
headlessly — `AtlasText3dRenderer._attach` calls `GeometryBuilder.build()`,
which is a GPU upload — so it belongs in `examples/render_probe`, as a scene
with **two** surfaces whose labels share a style: draw one, then add a second
whose text introduces glyphs the first did not use, and assert that the first
surface's label still covers the pixels it covered before. Every probe in that
harness today draws a single surface, which is why 75 of them passed over this.

Until then the reproduction is the gallery itself, and the way to look at it on
a machine with no screen-recording permission is a throwaway
`integration_test` in `examples/layout3d_gallery` that pumps
`Layout3dGalleryApp`'s content inside a `RepaintBoundary` over an opaque
`ColoredBox`, settles for a hundred frames with real delays between them, and
writes `boundary.toImage()` to `Directory.systemTemp`. Three notes, each of
which cost time: the backdrop has to be *inside* the boundary or every
alpha-blended panel composites over white and the whole scene reads as washed
out grey; the app is sandboxed, so `/tmp` is not writable and the file lands
under `~/Library/Containers/<bundle id>/Data/tmp`; and adding `integration_test`
to the example makes it a CocoaPods project, which `flutter create` does not
finish wiring — the generated `macos/Flutter/Flutter-*.xcconfig` needs
`#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.<config>.xcconfig"`
adding by hand. The harness is deliberately **not** committed, because that
last point breaks the plain `flutter create` / `flutter run` path the example
documents.
