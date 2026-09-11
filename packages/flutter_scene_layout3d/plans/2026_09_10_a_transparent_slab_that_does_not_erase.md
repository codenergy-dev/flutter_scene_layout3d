---
status: completed
created_at: 2026-09-10T14:20:00Z
updated_at: 2026-09-11T00:00:00Z
commit: a29484bca4b1b60ce78d58b061a88bab04de3a6c
---

# A transparent slab that does not erase what is behind it

## What it looks like

Run `examples/layout3d_gallery` and look at the navigation bar. The selected
destination is fine. The **unselected** one has a pill-shaped hole punched
clean through the bar: not a dark panel drawn over it, a hole — the scene's
backdrop shows through a stadium exactly the size and shape of the
destination's own surface, with the label reading through it.

## What is happening

Every interactive part of a Material component gets a `Material3d` of its own,
so that its ink well washes itself rather than the component around it —
`docs/traps.md` says so under *Depth ordering*, and a navigation destination is
one of the three examples it gives. That surface is **transparent** when
nothing is selected and nothing is hovered.

`assets/box_decoration3d.fmat` declares `blending: alpha`, and a blended draw
that still **writes depth** occludes whatever is drawn after it. The
destination's slab stands one step in front of the bar, so it writes its depth
first; the bar draws afterwards, fails the depth test across the whole pill,
and is simply not there. A fully transparent panel therefore erases what is
behind it rather than showing it.

**One sentence above turned out to be wrong**, and it cost the first probe:
the destination's slab does not stand one step in front of the bar. It is a
*child* of the bar's `Material3d`, which hands its child a tight depth, so the
two are **co-centred** — measured off a photographed frame at world z 0.53
apiece, the bar 0.08 deep and the destination 0.01. Their sort keys are
therefore equal, and a tie in the translucent pass's back-to-front sort is not
an ordering: the transparent slab is drawn first, writes its depth, and the bar
never draws. Everything else here is right, including the conclusion.

The selected destination does not hide the bug, which is the other correction:
its pill is opaque `secondaryContainer` and fills part of the hole, but the
destination's own transparent surface is larger than the pill, so the stadium
around it is still a hole. The photograph that settled this has the hole around
the *selected* destination.

## Why nothing caught it

Every render probe of a state layer draws a wash over a panel with an opaque
colour under it. The one shape this needs — a *fully transparent* slab on a
surface, drawn in front of it — is what `OutlinedButton3d` and `TextButton3d`
also are, and their probes ask about the outline and the label rather than
about the pixels of the surface behind. Headlessly there is nothing to see:
the arithmetic places the slab correctly, which it does.

## Where the fix went, and why not the other two places

**The shader**, and the judgement is worth recording because the obvious answer
is the wrong one.

The plan's first candidate was to stop the material writing depth. `flutter_scene`
exposes exactly that — `depth_write` is a `.fmat` key, this shader has declared
it `true` since its first commit, and the engine's default for an alpha-blended
material is `false` with a comment saying most of them leave it off. Turning it
off does fix the hole. **It was photographed doing something worse.**

With `depth_write` off, the whole catalogue is ordered by the translucent
pass's back-to-front sort and by nothing else, and that sort is one number per
draw: the world-space centre of the draw's bounds along the camera's forward. A
Material screen is full of slabs that share a centre, because `Material3d` hands
its child a **tight depth** — a navigation destination's surface and the bar it
lives in come out co-centred, and a tie in that sort is not an ordering. The
frame that came back had no hole in the bar and no selection indicator either:
the pill was drawn and the bar painted over it. That is a worse defect than the
one being fixed, and it is not local to one component.

So the depth buffer keeps ordering these panels, and the shader takes
responsibility for not writing depth where it draws nothing:

```
base.a *= coverage;
if (base.a <= 0.0) discard;
```

Two things make that the whole fix rather than half of one. A fragment with no
alpha contributes no colour either way, so nothing that used to be visible
stops being visible. And a state layer **cannot** rescue such a fragment: the
wash mixes into `base.rgb` and leaves `base.a` alone, so a hover on a
colourless surface has nothing to be seen against — the fragments this
discards were never going to be drawn at any state.

It fixes the class rather than the component, which was the point:
`OutlinedButton3d`'s interior and `TextButton3d`'s whole surface are the same
shape of thing and stop writing depth with it.

**Not the painter.** `BoxDecoration3dPainter` skipping a decoration with no ink
would fix the same case and save a draw call, and it would leave the shader
still able to erase a surface when anything else reaches it — a caller with a
`BoxDecoration3d` of its own, a decoration that becomes invisible between
frames without the painter noticing. The shader is the one place that cannot be
routed around.

**Not the catalogue.** A component that avoids the case is not the same as a
package that cannot express it, and a transparent `Material3d` on a surface is
how the whole catalogue builds an ink well. Making `NavigationBar3d` not build
one would have left the next component to rediscover this.

## What is still open, and it is upstream

A *partly* transparent slab — a 5% wash, Material's 32% scrim — standing in
front of something the sort puts after it has the same problem in a milder
form, and this does not fix it. The correct rule is per instance rather than
per material: **a decoration whose resolved colour is not opaque should not
write depth**, and the sort should be the only thing ordering it.

`flutter_scene` 0.23.0 cannot express that. `depth_write` is read once out of a
compiled material's metadata into `PreprocessedMaterial._depthWrite`, and there
is no setter; `Material.translucentDepthWrite` is `@internal` and a getter. The
fork's master does not add one either — what it adds in this area is a
`depth_test` key (a comparison function, `always` among them) and a third
`blending: additive` mode, neither of which is this. **When 0.24 lands with a
runtime depth-write flag, that is the rule to encode**, and this plan is where
it is written down. It is a genuine engine gap rather than a workaround this
side, which is what `docs/engine-rules.md` asks be said.

## The probe

`examples/render_probe`'s `transparent_slab`, and the scene is where the work
went rather than the assertion.

The recipe this plan proposed — an opaque panel and a transparent `Material3d`
one depth step in front of it — **passes whether the bug is there or not**, and
that was the first thing built. A blended draw only erases what comes after it,
and a slab plainly in front of a panel is sorted second and hides nothing.

What reproduces it is the arrangement the component actually makes, measured
off a photographed navigation bar rather than guessed: the destination's
surface is a *child* of the bar's, `Material3d` hands its child a tight depth,
and the two slabs come out **centred on the same plane** with the destination
the thinner. The scene is that — a `Stack3d` with `depthStep` zero, a 0.08-deep
bar and a 0.01-deep transparent slab co-centred inside it.

The assertion carries no colour and no magnitude, because a hole is *clear
pixels*: coverage over the slab must be one. A second reading compares the bar
under the slab with the bar beside it, so a slab that drew a tint rather than a
hole fails too. Verified both ways: without the discard, coverage at the slab's
centre is **0.0**.

## What came after

The judgement above — *the depth buffer keeps ordering these panels* — was the
right one and was only half working when it was made. A day later
[a letter on a slab](2026_09_10_a_letter_on_a_slab.md) found that the slab's
two depth-facing triangles were wound clockwise around their own normals, so
back-face culling kept the face **pointing away from the camera** and each
panel wrote the depth of its own rear face. Panels did order each other, near
enough, because they were all wrong by their own thickness in the same
direction; what could never be occluded was anything drawn *inside* a slab,
which is where the catalogue was putting its labels. Nothing in this plan
changes, and its probe passed before and after.
