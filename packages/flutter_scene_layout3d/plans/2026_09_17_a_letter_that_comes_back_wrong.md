---
status: completed
reason: >-
  Closed by its successor, 2026_09_19_the_engine_drops_draw_calls_under_a_
  blocked_queue.md: the cause is flutter_scene 0.23.0 blocking the calling
  thread on the GPU's backlog, not anything in this package. Everything in
  this plan below the front matter is six rounds of hypotheses, four real
  defects found on the way, and a long list of things ruled out by
  measurement. Read the successor first.
created_at: 2026-09-17T21:30:00Z
updated_at: 2026-09-19T21:30:00Z
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

---

## What was found, and what shipped

**The leading hypothesis was right about the mechanism and wrong about the
window**, and the correction is the whole of the fix.

A glyph mesh and the atlas texture it samples are a **pair**: texture
coordinates measured at one packing address the picture rasterized at that
packing and no other. That much the plan had. What it got wrong is where the
pair comes apart. It suspected the re-entrant bake — the `do/while` in
`_onAtlasChanged` reserving a glyph, repacking, and then binding a texture from
before the repack — and that is a real hole but a narrow one, a microtask wide
and self-repairing. The actual window is much larger and needs no re-entrancy
at all: **a repack renumbers every slot the instant it happens, and the picture
follows only when the readback lands.** Reading a 2048-texel atlas back off the
raster thread is frames of work, not microseconds. For every frame in between,
*any* renderer that bakes — on a notification, on a layout, on a scroll — is
measuring against a packing no picture exists for.

That is why the fault survived the thing that caused it, and why the settings
screen kept bad letters with no overlay open: nothing was persisting, the
window was simply wide enough to photograph.

It also explains the one piece of evidence the plan could not place. **"It is
per glyph, not per label"** is arithmetic rather than a second mechanism: the
atlas *doubles*, so every coordinate is roughly halved, and the letters packed
first still land on themselves in the old picture while the ones packed later
land on a neighbour — a speckled block — or past the used region — a missing
letter. One label comes out perfect and the one beside it loses a letter, in
the same frame, out of the same atlas. `text_atlas_test.dart` reproduces
exactly that, including the first glyph still being right.

### What shipped

- **`GlyphAtlas3d.textureGeneration`**, the packing the uploaded texture is a
  picture of, and **`textureIsCurrent`**, the question a renderer asks before
  it bakes. Deliberately *not* a fourth counter: the other three describe the
  atlas, these describe the picture. Also `GlyphAtlasCache3d.atlases`, for
  asking it of the whole set.
- **A renderer that has something correct to draw waits.** `_waitsForPicture`
  keeps a mesh whose coordinates and texture agree, in both `render` and the
  atlas listener, so a settled label does not flicker at all — it moves both
  halves forward together when the flush notifies. A label whose letters are
  new in that window binds nothing, which extends `bindAtlas`'s existing
  contract by one word: nothing until the pixels **match**.
- **`AtlasText3dRenderer.bakedGeneration`**, the other half of the pair, and
  the first thing to ask of a label that has quads and draws nothing.
- **`GlyphGeometryUpload3d`**, the seam `GlyphAtlasUpload3d` already was for
  the atlas. `GeometryBuilder.build` allocates a device buffer and nothing else
  in the renderer needs a GPU, so `render` had **never been called in a test at
  all** — the entire coordination this defect lived in was uncovered. It is
  covered now, in `test/atlas_text_renderer_test.dart`.

### Where the plan's instructions were wrong

- **"Do not let an atlas grow to hide it."** That rule belongs to the previous
  defect and is inverted here: a repack *is* the mechanism, and the
  `initialSize == maxSize` atlas the plan prescribed passes straight through
  this one without touching it. Both rules are true and they are opposites, so
  the trap page now says which family is which.
- **"Open and close an overlay several times before the photograph."** It does
  not help. After the first opening every letter is packed and no repack
  follows. What does help is photographing *early* — ten frames after the tap,
  which is after the menu closes and before anything settles.
- **The `++guard < 4` exit** was checked and is not reachable in practice: a
  settled label re-bakes the text it already had, so its reservations find
  existing slots and nothing repacks. It is left in place as the backstop it
  was written to be.
- **The second hypothesis — a silhouette traced off the wrong pixels and cached
  for the life of the atlas — is not the fault.** `_traceOutlines` runs only
  from an image whose generation *and* revision match, and the case that would
  have broken it (a repack arriving while the rasterization is in flight) is
  pinned now against a control atlas built cleanly.

### What is not closed

**The render probe cannot pin this, and it was tried.** With the fix
deliberately put back out, `gallery_dialog_arriving` came out *correct* — the
window is a race against a texture readback and it is not open on every run or
every machine. A scene that cannot honestly assert its claim is removed rather
than weakened, so what the photograph lane got is the *moment*, kept for a
person to look at, plus the one assertion that is deterministic: after
everything settles, every atlas in `GlyphAtlasCache3d.shared` has rasterized
the packing it is handing out. That is the invariant the waiting rests on, and
an atlas stuck behind it would leave a settled label holding its old letters
for ever — a worse defect than the one fixed here.

**The wait is a frame of latency for a genuinely new label.** A label whose
letters arrive inside the window draws nothing until the picture lands, rather
than drawing them wrong. That is the right trade and it is a visible one: an
overlay's own text can appear a frame or two after its panel. Closing it would
mean two packings live at once — the atlas keeping the old slot coordinates
valid until the new picture is uploaded — which is a real design and was not
needed to stop the defect.

---

## A second round, on the same defect: what a resize actually changes

**Reopened** by a person running the gallery, with a reproduction recipe sharp
enough to be a finding on its own:

- never resize the window → no artifacts, ever;
- explore every screen, menu, dialog and sheet **while small**, then maximize →
  no artifacts;
- open the app, let it load, then maximize **before touching anything** →
  artifacts on almost every text element drawn from then on.

The artifact photographed this time is a third one: **individual letters grey,
washed out or hatched while their neighbours in the same label are solid** —
`e`, `h`, `t` and `w` faint in every word of a paragraph whose `a`, `l`, `g`,
`b`, `r`, `i`, `c`, `s`, `p`, `n`, `o` and `d` are black.

### What was established, and it is not the root cause

**The root cause of that photograph was not found.** What follows is what the
round did establish, so the next reader does not pay for it twice.

- **A label has exactly one mesh and one material.** `Node.remove` *throws*
  when the child is not its own, so the orphaned-mesh hypothesis is not merely
  unlikely, it is impossible without an exception. Two renderers on one label
  would need two `Text3d` boxes. So a difference **between letters of one
  label** can only come from the texels a quad samples or from the wall built
  for that grapheme — and `buildGlyphWallSegments` skips a grapheme the atlas
  has not traced, which is the only per-grapheme fork in the whole path.
- **The bookkeeping is consistent once everything settles.** A fuzz harness
  drove real renderers and a real atlas through resize-shaped relayouts, new
  labels arriving mid-flight and repacks under twelve seeds, asserting after
  each run that every label's mesh is what a fresh bake would produce and that
  what is bound is a picture of the generation it was baked against. It never
  failed. (It is not kept: it asserts what
  `atlas_text_renderer_test.dart` already asserts case by case, more slowly.)
- **The photograph lane cannot open the window**, confirmed a second time from
  the other end: `flutter drive` was made to animate `tester.view.physicalSize`
  over 24 steps, cold and with the About dialog opening into the resize, and
  every atlas was current in every frame of both. Each `pump` costs enough real
  time for the readback to land. Do not spend another round on it.
- **The scale bucket does not move.** `unitsPerLogicalPixel * logicalPixelsPerUnit`
  cancels to 1.0 exactly over a thousand window heights in IEEE 754, so the
  suspicion that a resize splits a style across two atlases at a quarter-step
  boundary is arithmetic, and the arithmetic says no.

### What a resize actually does to this gallery, which is the correction

The first round wrote that a resize "makes every label lay out again". **That
is false for this application**, and being wrong about it is what sent this
round hunting in the layout path. Every surface in the gallery is authored with
a fixed `size` and a fixed unit rate; a window resize changes neither, so the
3D layout does not run. Only a surface bound to the camera with
`Layout3dCameraBinding.screenFilling` relayouts on a resize.

What a resize *does* do is rebuild the widget tree, many times over one drag —
and the gallery's `_themed` passed a **closure written in `build`** as
`SceneTheme3d.textRendererFactory`. That is compared by identity, so every one
of those rebuilds disposed and rebuilt the renderer, the mesh and the materials
of every label in the scene. Two things follow, and the second is why it is in
this plan:

1. It is the only route by which a window resize reaches the text layer at all
   in this app.
2. **A rebuilt renderer cannot take the wait this plan shipped.** Keeping a
   mesh that is drawing correctly is only possible for a renderer that has
   one. So the defence written in the first round — *a settled label keeps its
   consistent mesh until the new picture lands* — has never once applied in the
   application where the defect is seen.

Fixed in the gallery (`_textRenderer` is a method now), pinned headlessly as
*the wall around a glyph goes with the mesh when the renderer itself is
rebuilt*, and written up as a trap of its own, because nothing about the
failure points at the factory.

### The two defects this round did fix

- **The atlas texture was uploaded with a full mip chain.**
  `uploadGlyphAtlas`'s own dartdoc says mipmaps are deliberately off and
  explains why; the call took `Texture2D.fromPixels`'s default, which is
  `mipmaps: true`, trilinear, anisotropic. With two texels of gutter and an
  `alpha_cutoff` of 0.35, a minified glyph's coverage is averaged with its
  neighbour's and then thrown away — **per grapheme, by the letter's own
  shape**, which is the shape of the symptom. It is a real defect and it is
  fixed; it is *not* proven to be the photograph, and the direction argues
  against it, because the gallery's letters are minified when the window is
  **small** and magnified when it is maximized.
- **Two nothings compared equal in `_publish`.** A renderer handed a different
  atlas reports -1 for its bake and an atlas nothing has flushed reports -1 for
  its picture, and `-1 == -1` read as *the picture matches* — the face bound a
  texture that was not there while the wall was told to draw. The same hollow
  letter as the fix above, through the one door it left open. **It is a door
  closed rather than an artifact removed**: every path that reaches that state
  bakes again before the frame ends, so nothing was ever drawn from it. Said
  plainly because the opposite claim would be the easy one to make.

### The strongest remaining hypothesis

Not the layout path. Every per-grapheme fork in it has been walked and the
settled state is consistent under fuzzing. What has *not* been ruled out is
the GPU side of a resize: the atlas textures, the per-label device buffers
rebuilt on every one of those widget rebuilds, and what a macOS surface
reallocation does to either. The next round should start by asking whether the
gallery still does it now that the renderer churn is gone — that alone changes
the number of texture and buffer allocations during a resize by orders of
magnitude — and, if it does, instrument `Texture2D` identity rather than the
atlas's counters.


---

## A third round: the artifact, on demand

**The blocker for two rounds was not the diagnosis, it was the reproduction**,
and this round removed it. Everything below was produced by a script rather
than by a person clicking, and can be produced again with one command.

### The harness, because the other two lanes cannot ask the question

`flutter drive` pumps frames on the **test's** clock. `await tester.pump()`
runs a frame and then waits, so every asynchronous arrival in the engine has
landed by the time the next frame is built, and the window this plan is about —
**785–973ms** on the machine this was measured on — is never once open. Three
rounds read that as the defect not existing.

So there is a third harness now: `examples/render_probe/lib/self_drive.dart`,
run with `flutter run -t lib/main_self_drive.dart`. A real window on the
display's clock, and the state changes **synthesized** — `SelfDrive.tap` aims
the way `tap3d` aims, through the layout tree by semantic label, and hands a
`PointerDownEvent` to `GestureBinding`, which is what the platform hands it.
`SelfDrive.zoom` and `restore` go through a method channel to the macOS Runner,
because Dart cannot resize its own window and the resize is half the recipe.
It is written up in `examples/render_probe/README.md` under *Driving the real
window*.

Two things it needed that are worth keeping:

- **`restore` first.** macOS restores the frame the window last had, so a run
  after a maximized one starts maximized and the recipe's first half silently
  never happens. Two runs were wasted on that.
- **`dumpAtlases`**, which writes each atlas out as a PNG beside the
  photograph. A letter drawn wrong is either a wrong coordinate or a wrong
  picture, and nothing but the atlas settles which.

### What it reproduced, and what the artifact actually is

On the recipe — small window, settle, maximize, then open the overflow menu —
the gallery draws `About` as a speckled blob where `b`, `o` and `u` belong and
`Sort by` with `o` and `b` the same. **That is the photograph a person
reported, frame for frame**, and it is now one command away.

The console at that exact frame says the atlas *is* current by generation and
**still owes a raster** — the revision gap `textureIsCurrent` leaves open on
purpose.

Then the half that narrows it. The same run with the renderer's `depth` set to
`0` draws `A   t` and `S rt`: **clean gaps.** So the blob is not the front face
sampling something wrong — the front face is correctly drawing nothing, and the
blob is one of the two primitives a zero depth also removes: **the wall, or the
back face.** Not the wall alone; `depth: 0` takes both, and this round did not
separate them. That is the first thing the next round should do, and it is one
more run.

**And it is intermittent.** Four runs of the identical script produced the blob
twice and clean gaps twice, which is what a race looks like and is worth
knowing before anyone reads a single clean run as a fix. The benign form is the
same state seen earlier: a letter genuinely new to that atlas has no silhouette
either, so there is nothing to stand where its face cannot draw.

**The reasoning that has to be broken for the wall to be the culprit** is worth
writing down, because it is why the obvious fix was reverted:
`buildGlyphWallSegments` skips a grapheme with no outline; an outline is only
ever traced from an *accepted* image; every accepted image is uploaded and
draws every slot. So "has a silhouette but no ink where the mesh is looking"
should be unreachable, and it demonstrably is not. One of those three
statements is false in the running application, and finding out which is the
whole of the next round.

### What is still open, and what was ruled out

**The mechanism is not yet closed, and one attempt at closing it was reverted
rather than shipped.** The gate — withhold the wall while the picture
is behind the revision the mesh baked at — was written, and then the test
written to pin it would not fail: `buildGlyphWallSegments` already skips a
grapheme the atlas has no **outline** for, an outline is only ever traced from
an *accepted* picture, and every accepted picture draws every slot. So a letter
the picture lacks should have no wall either, and the gate has nothing to
catch. The code is out; `GlyphAtlas3d.textureRevision` stayed, because it is
the number the diagnosis needed and it is pinned on its own.

**So the open question is sharp**: what puts a glyph in a state where its
silhouette is known and its ink is not where the mesh is looking? Something
breaks the invariant `outlines.keys ⊆ what the uploaded picture holds`. The
next round should start by asserting exactly that inside `_flush`, in the
running application, where it can now be reproduced — not by reasoning about
it, which is what three rounds have spent themselves on.

### A trap found on the way, and it is not this one

The harness's first run wrapped the gallery's *screen* widget in a `MaterialApp`
of its own instead of running `Layout3dGalleryApp`, and **every glyph in every
atlas came back with a double rule through its descenders**. That is Flutter's
`_errorTextStyle` — what a `Text` resolves to with no `Material` above it —
whose `decoration` a `SceneText3d` inherits like any other field and the atlas
bakes into the texture, while `Material3d`'s `DefaultTextStyle.merge` corrects
the family, the size, the weight and the colour and leaves the decoration
alone. At small sizes it does not read as an underline; it reads as letters
that are eaten. It is a genuine trap for anyone building on this package and it
is written up in `docs/traps.md` as *An atlas bakes the decoration, and a
missing `Material` supplies one*. The gallery is under a `Scaffold` and is not
affected.

### One thing that is not a defect

The type on the surfaces **laid flat** — `On the table`, `Break / level 5`
reading as `level 8` — is the extrusion seen at a shallow angle, not a texture
artifact. A 14dp label extrudes 1.4dp, and at the camera's elevation the near
wall of a counter covers about 3dp of it, which closes the counter of every
`e`, `a` and `5`. It reproduces identically with and without a mip chain, and
it is a question for the wall's design rather than for this plan.


---

## What it actually was

**The picture of the atlas comes back without some of the letters in it.**

`rasterize` draws every glyph into one `ui.Picture` and asks for the pixels
with `toImage` and `toByteData`. On the machine this was found on — macOS,
Intel integrated GPU — that readback returns cells **blank** that were drawn,
and cells beside them full of regular vertical **stripes** that are not a raster
of anything. Nothing throws, and `toByteData` returns a full buffer.

It was photographed: the atlas dump at the frame the artifact is on shows
`[gap][gap][gap] n r e a d` on the first shelf and `S t b ▓ ▓ y` on the second
— the gaps are `A`, `l` and `U`, and the `▓` are the stripes. The same three
letters are the ones the screen draws wrong, and `debugStaleGlyphs` names them
from Dart at the same instant: **`AlU`, at every step of the script, never
healing.**

That is why three rounds could not place it:

- **per grapheme**, so it reads as the mesh pointing at the wrong texels rather
  than the texels being wrong;
- **permanent**, because the bad image passes every check and is kept for the
  life of the atlas — so it outlives the repack, the overlay and the resize it
  gets blamed on, and anything transient that is looked for is not there;
- **`textureIsCurrent` is true while it happens**, so every counter in the
  package agrees that the picture is fine.

### Ruled out by measurement, not by argument

- **Disposing each `ui.Paragraph` after `toImage` instead of before it.** The
  strongest remaining suspect, changed and run: no change at all, same glyphs.
- **Rasterizing again.** The obvious answer. Attempt two lost the same glyphs
  *and two more*, so `_maxLostGlyphAttempts` is zero and the atlas reports
  instead.
- **The wall, and the back face.** Turning each off separately leaves the
  artifact, which is what says the face is drawing the stripes rather than the
  wall standing without it. The earlier reading — *the blob is the wall* — was
  wrong, and the thing that made it look right is that `depth: 0` removes the
  face's own lift as well, which buries it in the panel.
- **The mip chain, and every counter.** Already ruled out in the round above.

### What shipped, and what did not

Shipped: **the detection**, and it is what named the defect. With
`debugVerifyGlyphAtlasInk` on, `_flush` checks that every glyph it drew arrived
with ink and names the ones that did not; `debugPicture` hands back the bytes
behind the texture rather than a fresh rasterization, and the difference
between those two is the whole defect. `debugStaleGlyphs` answers the other
half and should always be empty.

Shipped, and **it does not close this**: the texture no longer copies. The
readback was the prime suspect — `toByteData` of a 512-texel atlas costs
785–973ms and was assumed to be corrupting what it copied — so
`uploadGlyphAtlasPicture` now hands the `ui.Image` straight to
`gpu.Texture.fromImage` and nothing is copied on the drawing path.
**The artifact is identical, frame for frame.** The readback was reporting
faithfully; the picture is what is wrong. It is kept because it is right on its
own terms: a copy fewer, the `repeat` sampler addressing corrected to
`clampToEdge`, and the copy that remains is for silhouettes only and is skipped
entirely on a repack, which is the case it was most expensive in.

That import is a workaround and is written down as one: `flutter_scene` exposes
no way to make a `TextureSource` out of a `ui.Image` without copying it, so
`glyph_atlas.dart` reaches into the engine's own GPU shim. It reaches for the
shim rather than `package:flutter_gpu` on purpose — the shim is a re-export on
native and a WebGL2 backend on web, so it keeps working where a direct
dependency would not. **Upstream should expose it.**

### The per-glyph experiment, and why it is not in the tree

The round's last act was the fix the previous section prescribed: stop asking
for one picture of the whole alphabet, and rasterize each glyph into its own
image. It was built in full — a cached `ui.Image` per grapheme, the atlas
composed from them with `drawImage` so a repack draws no text at all,
silhouettes traced off each glyph's own cell so nothing reads the atlas back,
a per-glyph ink check, and a retry that was finally affordable because it cost
a cell rather than an alphabet.

**It is worse, and it is reverted.** On the same script: twenty distinct
letters came back blank where the batched picture had lost three, and the retry
never once succeeded — the same letter failed identically both times. The
rasterization also got slower, from ~900ms to ~2500ms for a first flush,
because each new glyph costs its own `toImage` and readback.

So the hypothesis it was built on — that this is the engine's glyph atlas not
having those letters resident, which one-at-a-time would fix — is **false**.
Smaller offscreen targets fail *more*.

### Where the next round started, and where it ended

Not in this package's bookkeeping. Five rounds had been spent there and the
counters were right every time.

Both leads above were taken, and the answer was behind neither of them.

**Lead 1, the cell geometry, is falsified.** A headless test loaded a real
font, packed the graphemes that had been measured to fail, and compared every
ink texel against the cell the packing reserved, at five sizes and two scales.
**No ink lands outside its own cell**, ever; the one glyph that comes close
(`j`, one texel) is absorbed by the padding gutter. The stripes are not
overflow and the per-glyph blanks were not clipping. The two symptoms are not
one bug in the way the lead proposed.

**Lead 2 was taken twice, and both forms failed.** `toImageSync` in place of
`toImage` produces the same artifact and additionally breaks the zero-copy
wrap: `Texture.fromImage` refuses an image that was not rendered
asynchronously. Serializing every atlas's flush process-wide — the resize used
to put half a dozen `toImage` calls in flight at once, which looked like an
excellent suspect — changes nothing at all.

## What the sixth round thought it was, and why that reading is wrong

**Read this section knowing its conclusion did not survive.** The numbers are
real and were measured; the mechanism drawn from them was not. The seventh
round showed that nothing cares whether a glyph has been drawn before — the
engine was losing whichever draw calls were encoded first, text or not, while
its queue was blocked. See the successor plan.

A probe that rendered the same glyph set three times in a row and reported
where the ink was, rather than which letter it belonged to:

```
16dp gen1 size256 glyphs6:   3021 ink  |     0  |     0
16dp gen2 size512 glyphs30: 12248 ink  |  9986  |  9986
24dp gen2 size512 glyphs13:  9340 ink  |  5372  |  5372
```

The reading at the time was: *drawing a grapheme into one offscreen picture and
then into a second one draws nothing the second time.* That is not what is
happening. Renders two and three ran while the engine's queue was blocked, and
what they lost was the draw calls they encoded first — which, in a picture that
draws the glyphs in reservation order, are the glyphs reserved earliest. Any
draw calls would have done.

Every flush typeset the whole alphabet into a fresh picture. So every repack
redrew glyphs an earlier picture had already drawn — and the oldest letters in
the atlas are precisely the ones the gallery showed hollow. The bug was not in
the packing, the counters, the readback, the sampler, the wall, the material or
the resize. It was in asking the font engine for the same letter twice.

### The fix, and why it is shaped this way

A glyph is typeset **once, ever**. Every later picture copies its cell out of
the previous one with `drawImageRect` at the address the new packing gave it.
The cells are identically sized in both pictures — same glyph, same scale — so
it is a texel-for-texel blit with nothing for the filter to do, and a blit is
not typesetting, so it does not trip the defect.

`GlyphAtlasPicture3d.slots` carries what a picture actually drew. That is
deliberately not "what the atlas has reserved": the two part company across the
`await` inside the rasterization, and since the next picture blits whatever
that map names, a grapheme listed there that the image does not hold would be
copied, empty, forever. It also closes a latent bug — `_pictured` was being
rebuilt from `_slots` *after* those awaits.

A repack became much cheaper as a side effect. That is not why it is there.

### What this round got right, and it is the thread the next one pulled

The gallery's status line is a plain Flutter `Text` widget, with nothing from
this package anywhere near it. Photographed early in a scripted run it reads
`Tap the screen, throw a switch, drag the slider`, cleanly. Photographed late
in the same run it reads `Pointing at: Sort` with `P`, `o`, `n` and `S` as
vertical stripes.

**So the defect is the engine's, and this package was a victim of it.** The
blit takes the glyph atlas out of its way; it cannot take the application's own
widgets out of its way. Anyone reading this after seeing corrupt text in a
Flutter window on an Intel Mac should suspect the engine's glyph handling
before suspecting anything here.

### What the original reasoning got wrong

- The plan opened by blaming the resize, then the repack window, then the
  counters, then the readback, then the copy, then residency. **All six were
  wrong**, and each was disproved only by measurement, never by argument.
- The per-glyph experiment (round five) was not merely useless, it was
  *backwards*: drawing every glyph again on every flush is the one thing that
  loses glyphs, so the experiment maximized the defect. Twenty letters lost
  against three. Its result was read at the time as falsifying residency; it
  was in fact the clearest evidence for the real cause, unread.
- Every round that reached for a **retry** made things worse, and now there is
  a reason rather than a superstition: a redraw is the cause. The comment in
  the code says not to add one.
- The detection shipped in round five (`debugVerifyGlyphAtlasInk`) is what made
  this round possible, and it has a limit worth stating: it asks whether a cell
  holds *any* ink, and stripes are ink. A clean report is not a clean picture.
  Both of the runs that reported zero loss still had a visibly broken frame.

### What is pinned, and what cannot be

`test/text_atlas_test.dart` counts `debugTextParagraphCount` across a repack
and asserts that only the *new* glyphs were typeset. It fails without the fix
(13 typesettings against 10) and passes with it. That is the part a headless
test can see; what actually came out of the font engine is not, and never will
be, so the self-driving harness and a person looking at the PNG remain the lane
for that half.
