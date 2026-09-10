---
status: pending
created_at: 2026-09-10T14:20:00Z
updated_at: 2026-09-10T14:20:00Z
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

The selected destination hides the same bug: its pill is opaque
`secondaryContainer`, so the hole is filled by the thing that made it.

## Why nothing caught it

Every render probe of a state layer draws a wash over a panel with an opaque
colour under it. The one shape this needs — a *fully transparent* slab on a
surface, drawn in front of it — is what `OutlinedButton3d` and `TextButton3d`
also are, and their probes ask about the outline and the label rather than
about the pixels of the surface behind. Headlessly there is nothing to see:
the arithmetic places the slab correctly, which it does.

## Where to look

Three candidates, cheapest first.

1. **Depth write on the panel material.** If `flutter_scene` exposes a
   depth-write flag on a `ShaderMaterial`, a decoration whose resolved colour
   is fully transparent should not write depth — and arguably no
   `blending: alpha` material should. Check what `Material` offers in 0.23.0
   before assuming it is there; if it is not, that is an upstream issue and
   this plan says so rather than working around it.
2. **Discarding in the shader.** The panel shader could `discard` where its
   own alpha is zero. That fixes the hole and does nothing for a slab at 5%
   alpha, which has the same problem in a milder form.
3. **Not drawing the box at all.** `BoxDecoration3dPainter` could skip a
   decoration with no visible ink in it — no colour, no border, no state
   layer. Cheapest at runtime and the narrowest fix; it leaves a genuinely
   translucent panel still erasing what is behind it.

Whichever it is, the probe that pins it is: an opaque panel, a fully
transparent `Material3d` one depth step in front of it, and an assertion that
the pixels behind the transparent one are still the opaque panel's colour and
not the clear colour.

## What it blocks

Nothing, which is why this is `pending` rather than urgent — but it is visible
in the one app a person runs, in the first screen they look at, and it makes a
navigation bar look broken. It is also a *class* of defect rather than one
component's: a transparent `Material3d` on a surface is how the whole catalogue
builds an ink well.
