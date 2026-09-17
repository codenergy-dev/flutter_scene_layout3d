---
status: completed
created_at: 2026-09-17T19:40:00Z
updated_at: 2026-09-17T20:30:00Z
commit: 3c4519a97975f5e2af862bdcb22977c7eb94b304
---

# A scrim that dims evenly

Written after the experiment rather than before it, like
[a box that fades](../../flutter_scene_layout3d/plans/2026_09_16_a_box_that_fades.md)
and for the same reason: the question was which of four pictures is right, and
no amount of reasoning answers that. Four treatments of the same 32% dim were
built over the gallery's own screen and photographed.

## What was wrong

A person opened a dialog and looked: **the app bar's title was a bare outline
while the navigation bar's labels were untouched**, on the same screen, under
the same scrim. Not dimmed differently — one erased, one not dimmed at all.

The cause is that a scrim is composited, and in this stack that ordering is
decided twice over:

- `box_decoration3d.fmat` writes depth, because a blended panel that does not
  "punches a hole clean through the surface behind it" — its own header says
  so, and a navigation bar was the case.
- `text_glyph3d.fmat` writes depth, because without it "a screen of type on a
  panel that rotates loses a different half of its labels every few degrees,
  which is exactly what the gallery did".
- The translucent pass then sorts by **one number per draw**: the world-space
  centre of the geometry's bounds along the camera's forward.

So a 32%-alpha scrim standing in front of a Material screen does not dim what
the sort puts after it. It erases it.

`box_decoration3d.fmat` already named this exact case as open and named the
32% scrim in it, and prescribed the fix — *a decoration whose resolved colour
is not opaque does not write depth* — gated on a per-instance `depth_write`
that `flutter_scene 0.23.0` does not have. **That prescription is wrong**, and
the experiment is what showed it.

## The four, photographed

| | what it is | app bar | screen visible | even |
| --- | --- | --- | --- | --- |
| 1 | 32% alpha, as it was | **erased** | yes | no |
| 2 | opaque colour at 32% **coverage** | dimmed, legible | yes | **yes** |
| 3 | fully opaque | — | **no** | yes |
| 4 | `depth_write: false` | **not dimmed** | yes | no |

**Four is the one worth dwelling on, because it was the predicted answer.**
The argument for it was that the objection `box_decoration3d.fmat` records —
panels share a centre, so the sort ties — does not apply to a scrim, which is
a single full-screen slab, nearest the camera, with nothing standing on it.
The photograph says otherwise: with depth write off, the app bar is drawn
*over* the scrim and is not dimmed at all. The error inverts rather than
closing. The likely reason is that the barrier's box spans the surface's whole
depth, so its bounds centre lands near the middle of the panel and ties with
the app bar after all — **not confirmed**, and not worth confirming, because
the conclusion does not depend on it: *writing depth is not the problem on its
own. With it or without it the sort decides, and the sort is wrong either
way.*

## What ships

**A scrim's alpha is spent as coverage.** The slab draws in its colour at full
strength and keeps that fraction of its fragments, which is the screen-door
`Opacity3d` already fades a subtree with. `modalFrame3d` builds it, and
`scrimCoverage3d` is where the reasoning lives.

It is even because it does not depend on the order at all: a surviving
fragment is opaque, so it writes depth exactly as any opaque fragment does.
Drawn before the screen or after it, the same fraction of pixels is scrim and
the rest is screen.

`DialogStyle3d.scrimColor` and `BottomSheetStyle3d.scrimColor` keep Material's
`scrim` at 32%. What changed is how that number is spent, which their dartdoc
now says — and a scrim given an *opaque* colour now hides the screen rather
than dimming it, which is treatment 3 and is worth knowing before writing one.

**The cost is that the dim is dithered rather than smooth**, and that is the
whole reason this was photographed instead of argued. It was chosen by
looking at a window.

## What it leaves open

- **The general case is untouched.** Any *other* partly transparent slab
  standing in front of something still meets the ordering, and
  `box_decoration3d.fmat`'s note still describes it — except that its
  prescribed fix is now known not to work. The note is corrected to say so.
- **A smooth dim needs sorted-independent compositing**, which this stack does
  not have for translucency at all. Coverage is the way around it, not a way
  through it.
- Nothing here changes what a scrim *is* for a surface at an angle, or for a
  viewer standing behind it. Those remain the questions the catalogue plan
  defers.
