---
status: completed
created_at: 2026-09-19T18:30:00Z
updated_at: 2026-09-20T12:00:00Z
commit: 41fbce3d63c2cb4ab1c1f1e5b9e4b46c2b6f2f0e
---

# The engine drops draw calls when its queue blocks

Six rounds of [a letter that comes back
wrong](2026_09_17_a_letter_that_comes_back_wrong.md) chased a text artifact
through this package's packing, counters, readback, sampler, materials and
geometry, and found nothing wrong with any of them. This round found the cause,
and it is not in this package and not about text.

**`flutter_scene` 0.23.0 blocks the calling thread on the GPU's backlog. While
it is blocked, draw calls that Flutter has already encoded into an offscreen
`Picture.toImage` are lost — the ones encoded first.** A glyph atlas bakes that
loss into a texture and keeps it, so the letters come out hollow and stay
hollow.

The fix is already upstream, unreleased. Nothing needs to be written.

## What the measurement was

The step that broke the six-round deadlock was to stop measuring *our* atlas
and measure the engine instead: draw a grid of items into an offscreen picture,
read it back, and report which **cells** came back empty rather than how much
ink came back. Then ask three questions that are separable only if you ask them
together.

At the gallery's `after_maximize`, on `flutter_scene` 0.23.0:

| what is drawn | empty cells |
| --- | --- |
| text, recorded first to last | `[0 … 9]` |
| text, recorded **last to first** | `[29 … 38]` |
| plain **rectangles**, first to last | `[0 … 8]` |

Reversing the order of the draw calls, without moving anything, moves the loss
to the other end of the image. Rectangles lose the same way text does.

So it is **not** a region of the image, **not** a glyph, **not** a font, and
not text at all: **the draw calls recorded first are the ones that go missing.**
Every hypothesis this package spent six rounds on was answering a question that
could not have been right.

## Why it starts at the window resize

A person could only reproduce this by maximizing the window, and that turned
out to be exactly right — for a reason nobody had reached. Maximizing to
2880x1694 on an Intel Iris Plus 655 makes the scene GPU-bound. From the
`flutter_scene` commit that fixes it:

> The Vulkan and Metal backends queue work from the calling thread, and once
> the GPU falls behind that queueing blocks for the backlog **because the queue
> is serialized with the raster thread's own submissions**, so a GPU-bound
> scene stalled the UI thread for the whole frame.

Flutter's own offscreen renders are submitted on that same serialized queue.
When it blocks, they come back short.

That also explains every negative result this round collected while trying to
build the defect up from nothing. None of these reproduce it, because none of
them makes the GPU fall behind: plain Flutter with no `flutter_scene`; an empty
scene; a scene with twelve lit meshes drawing for forty seconds; 200 GPU
textures allocated and dropped; `gpu.Texture.fromImage` in a loop; 160
offscreen renders at 160 distinct font sizes; three concurrent offscreen
renders; a window resized twelve times. The gallery reproduces it with **any
one** of its three surfaces — including the one made only of cubes and spheres,
with no text anywhere.

## The bisect

| `flutter_scene` | result after maximize |
| --- | --- |
| 0.23.0, as published | loses 9–10 cells, every run |
| `05d96e17`, just before the fix | loses 10 cells |
| `1b7b7a93` *Pace the GPU instead of blocking the calling thread on its backlog* | mostly clean, text still loses |
| `6ce121f1` *Default to one GPU frame in flight* | **clean** |
| `master` | **clean**, whole gallery, every step |

And the control that proves it is the pacing rather than anything else in the
200 commits between: on `master`, setting `Scene.maxGpuFramesInFlight = 2` —
the pre-fix default — **brings the defect back**, at the same step, losing the
same cells.

`Scene.maxGpuFramesInFlight` and its default of 1 are the fix. They are on
`master`, described in the `## 0.24.0` section of the engine's changelog, and
0.24.0 is not released yet: `packages/flutter_scene/pubspec.yaml` still reads
`version: 0.23.0`.

**So there is no pull request to open.** The work is done upstream; it is
waiting on a release.

What this workspace does in the meantime is pin it. The root `pubspec.yaml`
overrides `flutter_scene` — and `scene`, which is not optional, because the
engine's git version needs a newer one than pub.dev has — to
`25f133d90716348f76565362be597b33ebc6e4db`, a commit verified to have
`6ce121f1` as an ancestor. Pinned rather than tracking `master` because
`pubspec.lock` is not committed here, so a bare branch would hand every fresh
clone whatever upstream had that minute. The reasoning is written at the
override, in `docs/engine-rules.md` for a reader looking at the engine, and in
both packages' READMEs and changelogs for a consumer.

**Deleting the override when 0.24.0 lands is not the whole job.** On a 0.x
version `^0.23.0` means `>=0.23.0 <0.24.0`, so the four constraints — both
packages, both examples — would refuse the release that carries the fix, and
the defect would come straight back on the next `pub get`.

## What it looks like when it is fixed

The gallery's status line is a plain Flutter `Text`, with nothing from this
package near it. On 0.23.0 it reads `Pointing at: Sort` with `P`, `o`, `n` and
`S` as vertical stripes. On `master` it reads `Pointing at: Sort by`, cleanly.
That is the half of the defect this package could never have fixed, and it is
the proof the cause was never here.

## What this package keeps, and why

The previous round's change — a glyph is typeset once and blitted forward —
was written believing it *was* the fix. It is not, and its changelog entry and
trap page have been corrected to say so. It is kept on its merits:

- It cuts the draw calls in an atlas picture from one per glyph to one blit per
  glyph, which is what made a repack expensive.
- Fewer and cheaper draw calls is less exposure to anything of this shape.
- Its test pins a real invariant — a glyph is handed to the font engine once —
  which is worth holding whatever the engine does.

**What was wrong in the previous round's writeup**, and is now corrected: it
concluded that "drawing a grapheme into a second offscreen picture draws
nothing the second time". The observation was real — renders two and three of
the same glyph set came back with 0 ink — but the mechanism was not. Nothing
cares that it is the second render. Those renders happened while the queue was
blocked, and *any* draw calls encoded first would have been lost, text or not.

## Where the next reader starts

If text goes wrong in a `flutter_scene` application again, the order is:

1. **Check the engine version first.** Below 0.24.0, this is the likely answer.
2. Measure the engine, not the atlas:
   `examples/render_probe/lib/main_engine_probe.dart` drives the gallery and
   reports empty cells at every step, with the three-way discrimination above.
   A clean run there means the defect really is in this package.
3. Only then look at the packing.

The minimal negative controls are in
`examples/render_probe/lib/main_minimal_repro.dart`, switchable by
`--dart-define`, so the next reader does not have to rediscover that none of
them is it.
