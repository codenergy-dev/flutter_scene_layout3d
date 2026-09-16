---
status: pending
created_at: 2026-09-16T23:10:00Z
updated_at: 2026-09-16T23:10:00Z
commit: d029f849eeaa63d2bc3a4192f5cb1955b0f0addb
---

# A box that fades

The ninth plan off
[what a real application still needs](2026_09_11_what_a_real_application_still_needs.md),
and the only item on that map carrying an **upstream gate**. Its entry says
there is no `Opacity3d` and that there may not be able to be one, because
subtree opacity needs a per-node opacity in `flutter_scene` and the engine has
none. That was checked twice, in August and again on 2026-09-16 by
[a route that arrives](2026_09_16_a_route_that_arrives_instead_of_appearing.md),
and both times the answer came back no.

**The gate is real and it is not that one.** This plan is written after an
experiment rather than before one, and the experiment is the reason its
recommendation is a sentence rather than a paragraph of hedging. What it found:
the engine's missing `Node.opacity` does not matter, because this package owns
the materials it draws with and both of them already multiply alpha. What
stands in the way is **`depth_write`** — and there is a way through it that
costs one uniform.

The experiment is committed, in `examples/render_probe`, behind its own target:

```sh
cd examples/render_probe
flutter drive --driver=test_driver/photograph.dart \
  --target=integration_test/opacity_poc_test.dart \
  -d macos --enable-flutter-gpu
```

Its README section says how it is built and what each capture shows. **Read it
before starting**, and look at the PNGs; the whole argument below is downstream
of five pictures.

## What is actually missing

Checked at `d029f84`, against a green 1230/545/4 and 103 render probes.

- **Nothing fades.** There is no `Opacity3d`, no `AnimatedOpacity3d`, no
  `FadeTransition3d`, and `Motion3d` ships with no opacity field — deliberately,
  because a motion that faded a panel and left its label would be worse than
  one that did not fade. The catalogue substitutes a colour for Material's
  disabled treatment for the same reason, and its plan says so and defends it.
- **The engine still has no per-node opacity**, at the `flutter_scene 0.23.0`
  that `pubspec.lock` resolves. `Node` carries `visible`, `highlightColor`,
  layer and light masks, shadow flags, and nothing else that would do.
- **It has something adjacent, and it is out of reach.** `Material.lodFade` is
  a real per-draw fade — screen-door coverage, driven by
  `shaders/lod_fade.glsl` — but it is `@internal` and its own dartdoc says
  *only the built-in lit and unlit materials honor it*. A `.fmat` material
  gets no `fade` uniform unless it declares one. So the mechanism exists,
  upstream, and a consumer cannot reach it.
- **And alpha was never the problem.** `box_decoration3d.fmat` takes a
  `vec4 color` and ends on `base.a *= coverage`; `text_glyph3d.fmat` computes
  `sampled.a * color.a`. `BoxDecoration3dUniforms` already folds an opacity
  into a colour's alpha in two places — the state layer's, and the picture's.
  Fading is uniform arithmetic and needs nothing from the engine.

What is in the way is **depth**. Both shaders declare `depth_write: true`,
deliberately, with twenty lines of comment and a photographed experiment behind
each; see
[a transparent slab that does not erase](2026_09_10_a_transparent_slab_that_does_not_erase.md)
and the header of `assets/text_glyph3d.fmat`. A blended draw that writes depth
occludes whatever is drawn after it, so a partly transparent panel standing
where the sort puts it first hides what is behind it instead of showing it
through. That plan closed the *fully* transparent case with a discard and left
the *partly* transparent one open, calling it upstream and naming the rule to
encode when the engine grows a runtime depth-write flag. **A fading subtree is
that open case, in every box at once.**

## What was photographed, and what it settled

Five approaches, one scene, four opacities each. The scene has two halves,
because the defect lives in only one of them: a faded card standing plainly in
front of a backdrop is drawn second and behaves perfectly whatever the
approach, so the left half answers the questions about alpha and the right half
— a panel whose bounds centre is further than the backdrop's while its front
face is nearer — is where erasure lives. A small opaque `pin` stands in front
of the card, outside the faded subtree, and exists to catch one failure that
nothing else in the scene can show.

| approach | how it fades | result |
| --- | --- | --- |
| alpha, shaders as shipped | opacity into every colour | **hole**, and a ghost label |
| alpha, `depth_write: false` | opacity into every colour | **fails at opacity 1.0** |
| screen door, the engine's hash | a `fade` uniform | correct; visible hatching |
| screen door, ordered 4x4 Bayer | a `fade` uniform | **correct, and invisible** |
| subtree to a texture, `Opacity` | Flutter composites it | exact, but flattens depth |

- **Folding into the alpha** fades correctly wherever the ordering was already
  benign and punches a hole where it was not: at 12% the backdrop is gone and
  the scene's own clear colour shows through a rectangle the size of the card
  (coverage 0.000 where the panel is). Its labels fail earlier and separately —
  see *the third seam* below.
- **Turning depth write off** is worse, and worse in a way that has nothing to
  do with opacity: at **opacity 1.0** the panel in front is painted over by the
  backdrop behind it, because with nothing writing depth the only ordering left
  is the back-to-front sort and that sort is one number per draw. Same finding
  the 09-10 plan photographed, reproduced deterministically. **Do not
  re-litigate this.**
- **Screen door** — discarding fragments against a threshold instead of
  blending — makes the two halves of the scene pixel-for-pixel
  indistinguishable. That is the whole claim: the fade stops depending on the
  ordering, because the fragments that survive draw and write depth exactly as
  an unfaded panel does. Labels fade smoothly with no cliff, because the tint's
  alpha never moves.
- **Which threshold matters, and only to the eye.** The engine's own hash is
  tuned for foliage far away under temporal anti-aliasing; on a still panel
  hundreds of pixels across, with no TAA in this stack, it photographs as
  diagonal hatching. An ordered 4x4 Bayer matrix gives the same numbers and no
  visible pattern at all.
- **Rendering the subtree into a texture** is the only approach that is a
  `saveLayer` rather than an approximation of one, and it was built and
  measured rather than reasoned about: `RenderTexture`, a second `RenderView`
  with a `layerMask`, `Node.layers`, and Flutter's `Opacity` over a
  `RenderTextureView`. It gets group opacity exactly right — the label's
  contrast against its card falls linearly, 0.316 at full and a measured 0.096
  at 30% against a predicted 0.095, where screen door reads 0.140 — and it gets
  depth exactly wrong. The `pin` is buried **at opacity 1.0**, where nothing is
  supposed to be happening; only the sliver overhanging the card survives.

**So: ordered Bayer screen door, and the group-opacity error is the price.**
It is about half again as much label as there should be at 30%, zero at either
end, and largest exactly where everything is moving.

## The three seams an opacity has to reach, and the one nobody knew about

Verified by grepping for every mesh this package builds. There are three, plus
the caller's own.

1. **The panel slab** — `decoration/box_decoration_painter.dart:102`, one
   `Node` and one `PreprocessedMaterial` per decorated box, built through
   `BoxDecoration3d.painterFactory`.
2. **The glyph faces** — `text/atlas_text_renderer.dart:282` and
   `text/rich_text3d.dart:719`, both drawn with whatever
   `GlyphMaterial3d.factory` makes, so one seam covers both.
3. **The glyph wall**, and this is the find. `atlas_text_renderer.dart:276`
   adds a third primitive whose material is *not* the glyph material: it is
   `buildWallMaterial()`, an `UnlitMaterial` with `alphaMode = AlphaMode.opaque`
   and `vertexColorWeight = 1.0`, so its colour is baked into the geometry's
   vertex colours and **nothing a uniform can say will fade it**. It is not a
   corner case: `resolveDepth` is `depth ?? depthFactor * fontSize` with
   `depthFactor` defaulting to `0.10`, so **every label has a wall unless a
   caller asks for a flat one**.

   This is what the experiment photographed as a ghost: at 30% the glyph faces
   fall below `text_glyph3d.fmat`'s `alpha_cutoff: 0.35` and are discarded
   entirely, while the opaque wall stays at full strength — so a faded label
   is a hollow outline of itself rather than faint type. The map's entry
   forbade shipping an `Opacity3d` that faded a panel and left its label; the
   real version of that hazard is one level finer and lives inside the label.

4. **`NodeBox3d`** — geometry the application brought. The package cannot fade
   what it did not build, and this is where the protocol has to say so rather
   than fail quietly.

## The shape, and the four decisions in it

**Where the opacity lives: inherited on `Layout3d`, the way the clip is.**
`clipRegion` is the precedent and it is an exact one — an ambient value an
ancestor imposes, computed by walking *up* on demand rather than pushed down
(`layout3d.dart:990`, with the reasoning for the direction written there),
republished through `refreshClipRegion`/`refreshClipSubtree` when it is settled
later than the boxes below it were laid out, carried to the painter on
`Decoration3dPaintRequest`, and packed into uniforms by the shader. Opacity is
the same shape of thing and should be the same mechanism. The experiment's
`FadedBoxDecoration3d` — a decoration subclass with a cache key of its own — is
**not** the design; it is a way to get a per-box uniform without building the
inheritance, and it cannot express a subtree.

**Screen door rather than alpha, and the reason is not only depth.** Folding an
opacity into the alpha means folding it into *every* colour the panel shader
takes: `color`, `border_color`, `state_layer`, `surface_tint`, the eight
gradient colours, and `image_opacity` — all of them, correctly, or a fade
leaves a border at full strength. Screen door folds nothing. One uniform,
every colour untouched, and the arithmetic below it unchanged.

**The wall needs its own answer, and there are two.** Either it gets a
compiled `.fmat` like the other two — consistent, and the third shader this
package ships — or `Material.lodFade` becomes public upstream, at which point
an `UnlitMaterial` fades for free and the ask is a one-word change to an
annotation. **Write down which, and if it is the second, open the issue.**
That decision is the one piece of this plan that is genuinely open.

**What the widget layer is called.** `FadeTransition3d` and
`AnimatedOpacity3d` are honest names for what this builds. `Opacity3d` is the
one to be careful with, because a reader will expect Flutter's semantics and
get coverage instead: correct at both ends, correct in ordering, and about half
again as much label as Flutter would draw at 30%. Ship it, and say so in its
own dartdoc rather than in a plan nobody reads.

## What this plan does not build, and why

- **True group opacity.** The texture route was built and measured, and it
  fails at opacity 1.0 by burying whatever stands in front of the faded
  subtree. It is only safe when that subtree is already the frontmost thing —
  which is exactly an overlay, where screen door already works without a render
  pass per frame and without stamping `Node.layers` onto every mesh node in the
  subtree (which is not inherited, so a node created mid-fade is born on the
  wrong layer and appears at full opacity). Record it as an escape hatch,
  build it as nothing.
- **A runtime depth-write flag.** Still the right upstream ask for the *other*
  half of the 09-10 plan, and this plan does not need it. Do not let it become
  a blocker here.
- **Material's disabled treatment.** The catalogue substitutes a colour because
  there was no opacity. There is one now, and revisiting that is the
  catalogue's call and its plan's entry, not this one's.

## The work

1. Add a `fade` uniform and an ordered Bayer screen-door discard to
   `assets/box_decoration3d.fmat` and `assets/text_glyph3d.fmat`. Copy the
   experiment's blocks; they compile and are photographed.
   `examples/render_probe/tool/make_opacity_variants.dart` is where they live.
2. Decide the glyph wall (a third `.fmat`, or the upstream ask) and do it.
   **A label that fades to an outline is the defect this plan exists to
   avoid.**
3. Inherit opacity on `Layout3d` the way `clipRegion` is inherited, with the
   refresh hook, and an `Opacity3d` box that imposes it.
4. Carry it on `Decoration3dPaintRequest` and write it in
   `BoxDecoration3dPainter`; carry it to `GlyphMaterial3d`.
5. Give `NodeBox3d`'s content a way to say it can fade, and assert in debug
   when a faded subtree contains something that cannot.
6. `FadeTransition3d` and `AnimatedOpacity3d`, and an opacity field on
   `Motion3d` — which is the thing the route plan left out and the reason this
   item is in the motion lane at all.
7. Probes: promote the experiment's two halves into `kProbeScenes` as real
   assertions — a faded panel lets the panel behind it through, and the same
   scene in both orderings reads the same — and a headless test that the
   inherited value composes down a subtree.

## The traps this one has to respect

- **The tiers.** A fade is a uniform write. It must not relayout, and it must
  not rebuild geometry — which is the second reason the wall cannot be faded by
  editing its vertex colours.
- **The ticker rule.** An animation that has stopped changing must stop asking
  for frames, or `pumpAndSettle` spins forever. Written up already; the route
  plan paid for it.
- **`Decoration3dPainterCache` keys on `cacheKey`.** Whatever carries the
  opacity must not make the key finer, or a screen of panels stops sharing a
  painter and the frame rate falls with nothing saying why.
- **A fade at 1.0 must be byte-for-byte what no fade draws.** Two of the five
  approaches failed exactly there, and both failures were invisible until
  something stood in front of a faded box. Whatever ships, put a probe on it.

## What the map's entry got wrong

Its first step was *check whether the engine has moved*, and it sent the reader
to look for opacity on `Node`. That grep has now been run three times and will
always come back no, because the thing to look for was never there: this
package draws with its own shaders, and the obstacle is `depth_write` rather
than alpha. **The entry sent two investigations to ask the wrong question.**

It was also right for a reason it did not know. It says an `Opacity3d` that
faded only `BoxDecoration3d` would be worse than no opacity, because a box
whose panel fades and whose label does not is worse than neither. That is true,
and the sharp version is one level down: a label's *wall* is an opaque material
coloured by its vertices, so the naive fade does not merely leave a label
behind — it dissolves the letter and keeps its outline.

And the map lists this item as gated while
[the motion tokens](../../flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md)
are ripe. It is not gated. It is takeable, it is roughly a shader block and an
inherited value, and the expensive half — deciding which of five ways to do it
— has been spent.
