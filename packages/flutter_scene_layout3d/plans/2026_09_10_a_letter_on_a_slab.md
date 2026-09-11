---
status: completed
created_at: 2026-09-10T21:27:20Z
updated_at: 2026-09-11T01:30:00Z
commit: b7ad02e7780b4f7906a63dccc23721aa9017b84a
---

# A letter on a slab

## What was reported

The gallery's upright screen **blinks**. Titles, subtitles, icons and
navigation labels come and go while the panel turns — a different set each
time — and the catalogue on the table, which does not turn, never does it.

## What it is not

Not the glyph atlas. Instrumenting `GlyphAtlas3d` and `AtlasText3dRenderer`
through a whole run shows every reservation, repack, rasterization and upload
finishing **before the first frame is photographed**; nothing rebuilds a mesh
afterwards. Not a race, and not
[a label that survives a repack](2026_09_10_a_label_that_survives_a_repack.md)
coming back.

The way to see that it is not time-dependent at all is to hold the panel
still. With the gallery's pivot frozen at one angle, successive frames are
**identical byte for byte** — and *which* labels are missing changes only when
the angle does. The picture is a function of the yaw.

## What it is

Four defects, stacked. Every one of them was measured in
`examples/render_probe` with a scene built for the purpose — a slab, a ladder
of labels at known depths inside and in front of it, and a camera that can be
told to turn the plane.

### 1. The decoration slab is built inside out

`BoxDecoration3dPainter.buildUnitSlab` winds each face's two triangles
**clockwise around that face's own normal**. The convention everywhere else in
this package — stated in `AtlasText3dRenderer.buildGlyphGeometry`, which gets
it right — is counter-clockwise around the outward normal, because the
surface's basis is a mirror and `flutter_scene` flips the front face for a
mirrored transform on its own.

Wound the other way, the flip lands on the wrong side and `culling: back`
keeps the face **pointing away from the camera**. Two things follow, and the
second is what breaks the type:

- Every panel in the catalogue is lit by a normal that points away from the
  viewer.
- A panel writes its depth **a whole thickness too far back**. A 4dp card
  writes the depth of its rear face, so nothing drawn inside it — which is
  where the catalogue puts its labels, see 2 — is ever rejected by the depth
  test. The `depth_write: true` the panel shader argues for so carefully has
  been landing behind everything it was meant to order.

Measured: a label 0.1 and 0.18 units *behind* the front face of a 0.4-deep
slab draws over it. With the winding corrected, both vanish and the one in
front of the face survives.

### 2. The catalogue buries its content inside the slab

`Flex3d.depthAxisAlignment` defaults to `CrossAxisAlignment3d.center`, and a
`Material3d` with `alignment: null` — which `ListTile3d`, `AppBar3d`,
`NavigationBar3d` and `Card3d` all pass, so the row fills the tile rather than
being centred in it — hands its child the surface's own **tight** depth. A row
in a 4dp card is therefore 4dp deep and centres a zero-depth label in it: the
label sits 2dp behind the face of the card it is written on.

Measured on the gallery's own inbox screen, in world units, larger is nearer:

| | face of the slab | where the label is |
| --- | --- | --- |
| card under a `ListTile3d` (0.04 deep) | 0.150 | 0.130 |
| `AppBar3d` (0.08) | 0.660 | 0.650 |
| `NavigationBar3d` (0.08), its pill (0.01) | 0.570, 0.535 | 0.530 |
| `FilterChip3d` (0.01) | 0.125 | 0.125 |

The chips are the only component that puts its label on the face, and the
chips are the only labels in the photographs that never blink.

`Material3d`'s own dartdoc already says this is wrong — *"a label centred in
depth sits in the middle of the slab and is hidden by the front half of it"* —
and its `alignment` defaults to `Alignment3d.frontCenter` for that reason. The
default is dead: a tight depth leaves nothing to align.

### 3. A glyph mesh does not write depth, so the sort erases it

This is the one that makes it blink rather than simply be wrong.

`flutter_scene` draws translucent geometry back to front, sorted by **one
number per draw**: the distance from the camera to the centre of the object's
world bounds. A glyph mesh is `UnlitMaterial` with `AlphaMode.blend`, and
`Material.translucentDepthWrite` is false for it, so a panel drawn *after* a
label paints straight over it — the label has written nothing the panel's
depth test could be rejected by.

Whether the panel is drawn after the label is decided by that one number, and
turning the panel mixes the label's **horizontal offset** into it. A label `d`
units to the side of the slab's centre, on a plane yawed by `θ`, sorts
`d·sin θ` farther away. The gallery's panel turns ±0.13 rad and its cards are
three units wide, so a label at the left edge swings ±0.15 units in sort depth
— against a lift of 0.002. Half the screen changes hands every time the panel
passes through its own centre.

Measured: six labels at three depths and two horizontal positions on one slab.
At yaw 0 all six draw. At yaw 0.2 the two on the left at and behind the face
are gone and the one lifted 0.11 in front of it — more than half the slab's
thickness — survives. The rule the picture obeys is exactly
`lift > distance-from-centre × sin θ`, which is not a rule any layout can
satisfy: it depends on where the viewer is standing.

`Material.depthBias` does not help and the experiment says so: 0.05 of bias on
the glyph material, with the geometry left alone, changes nothing at any yaw.
Bias moves a fragment's depth, and depth is not what is deciding.

### 4. One glyph atlas per text colour

Not part of the blinking, found while instrumenting it. `glyphAtlasStyleOf`
takes the colour out of the style an atlas is keyed by, because glyphs are
rasterized white and tinted by the material — but Material's `TextStyle`
carries `decorationColor` alongside `color`, and that stays in the key. The
gallery ends up with **27 atlases for 9 styles**: the same alphabet
rasterized once per text colour, three times over.

## The fix

Four changes, and the first two have to land together: correcting the winding
makes a slab occlude what is inside it, which turns "the label is 2dp behind
the face" from a coin toss into a certainty.

1. **Wind the slab counter-clockwise around each face's normal**
   (`BoxDecoration3dPainter.buildUnitSlab`). One line, plus the comment that
   says which convention this package uses and why.
2. **Front-align in depth by default** (`Flex3d.depthAxisAlignment`), so a
   flex inside a slab puts its children on the face rather than in the middle,
   and audit the catalogue for anything else that buries content.
3. **Give the glyph mesh a material that blends *and* writes depth**, so a
   label defends itself against a panel drawn after it, whatever the sort
   decided. `flutter_scene`'s `UnlitMaterial` cannot: `translucentDepthWrite`
   is not settable, and `AlphaMode.mask` is unimplemented for unlit (the
   engine's own TODO). So this package ships a second `.fmat` —
   `assets/text_glyph3d.fmat`, unlit, `blending: alpha`, `depth_write: true`,
   discarding where the atlas has nothing — and `AtlasText3dRenderer` uses it
   through a factory that falls back to today's `UnlitMaterial` when nothing
   has been installed. `initializeMaterial3d()` installs it, exactly as it
   installs the panel painter.
4. **Key the atlas by the style with its decoration colour taken out too.**

The lift itself (`AtlasText3dRenderer.depthOffset`, and `RichText3d`'s) stays a
nudge, but becomes a figure in **logical pixels** rather than 0.002 world
units, because what it has to clear is a face and faces are where they are in
dp. A fifth of a logical pixel is the same 0.002 units at the standard rate, so
nothing drawn today moves.

## What is deliberately not done

**The panel is not moved to the opaque pass.** It would order text by the
depth buffer alone and need no glyph material at all, but a `Material3d` is
transparent whenever a component wants it to be — a navigation destination, a
text button, a scrim — and the anti-aliased outline the panel shader draws is
an alpha. The trade was already photographed once, under
`depth_write` in `assets/box_decoration3d.fmat`.

**No eviction is added to `GlyphAtlasCache3d`.** Fixing 4 takes the atlas
count in the gallery from 27 to 9; the bound the class documents is unchanged.

## The probes

Both are in `examples/render_probe`, and both were **verified by breaking the
fix again** rather than by passing once.

- `slab_occludes_its_inside` — a label on a slab's front face and a label sunk
  a third of the way into it, asking for ink at the first and none at the
  second. With the winding put back the way it was, it fails; so does
  `an outlined button draws its outline at the rim`, which turns out to be a
  second witness to the same thing (see below).
- `type_on_a_turning_panel` — three labels on a card-thin slab, one at each
  edge and one in the middle, on a plane yawed a quarter of a radian. With
  `installGlyphMaterial3d` stubbed out it fails, naming the edge label that
  went. It is the first scene in the harness to turn a surface at all.

The second one took two attempts, and what the first one got wrong is the
thing to know: it used a **0.6-deep slab**, and half of that is a third of a
unit of head start — enough for the label to win the sort on its own and pass
whether the material wrote depth or not. What keeps a label in front of the
panel it is written on is *half the panel's thickness*, so a probe for this has
to use a thickness a component would use. Eight dp does it; the gallery's cards
are four.

## What was found on the way

- **The two labels of a Material screen were never occluded by anything.** The
  winding defect is older and wider than the blinking it caused: for its whole
  life the catalogue drew every panel from its **rear** face, lit by a normal
  facing away from the camera and projected one thickness smaller than the box
  layout gave it. `an outlined button draws its outline at the rim` had been
  passing on that parallax — its rim point is 0.096 units in from the edge of a
  0.06-unit band, which is *outside* it, and the band only reached that point
  because the geometry was drawn small. Correcting the winding made the
  arithmetic in that probe have to become true.
- **`Center3d` still centres in depth, and now that is visible.** Changing a
  *default* was right; changing what an explicit alignment means was not, so
  `Center3d` and `Align3d(Alignment3d.center)` put their child in the middle of
  the depth they are given, which on a slab is inside it. `text_on_panel` was
  written that way and had to be moved to `Alignment3d.frontCenter` — it was
  the scene demonstrating the trap rather than the rule. It is in
  `docs/traps.md` in both halves now.
- **A `Depth3d`'s second cross axis is vertical, not depth.** The name
  `depthAxisAlignment` says which *slot* it is, not which axis it lands on, so
  a blanket `start` default would have silently top-aligned every depth-running
  line. `Flex3d.defaultDepthAxisAlignmentFor` resolves it from the direction
  instead, and follows a direction that changes later.
- **The scrolling family kept the centred default.** `ListView3d`,
  `SliverList3d`, `GridView3d` and their relatives arrange *items* in the depth
  a scroll view has, and an item is a slab of its own whose content is on its
  own face. Front-aligning them would move every card in every list toward the
  viewer to fix nothing. The rule this plan establishes is about content
  sharing the depth of the thing that arranges it, which is a line, a table and
  a Material surface.

## How it was looked at

The gallery, photographed from inside `examples/render_probe` — the recipe in
[a label that survives a repack](2026_09_10_a_label_that_survives_a_repack.md)
— first with the pivot frozen at a series of angles, which is what turned
"it blinks" into "it is a function of the yaw", and then turning on its own
clock to check the result. A scratch scene of slabs and labels at measured
depths answered everything in between: which depth a panel writes, whether the
depth test or the draw order is deciding, and at what lift a label survives a
given angle. `Material.depthBias` was tried and changes nothing at any yaw,
which is what proved the sort rather than the depth test was the arbiter.

Every claim in this plan is a picture, not an argument.

## The one it caused, and the rule that closed it

Reported the same evening, against the committed fix: the switch's track and
the navigation bar's selection pill **striped**, in bands that came and went as
the panel turned. Measured rather than guessed, and it was one line of a depth
dump:

| | front face |
| --- | --- |
| card | 0.0200 |
| switch track on it | **0.0200** |
| navigation bar | 0.0700 |
| its selection pill | **0.0700** |

`Material3d` aligns its child to its own front face — which is the rule this
plan put there — and a child that is itself a `Material3d` therefore starts
exactly *on* that face. Two surfaces on one plane, both writing depth, is a
z-fight; it had been invisible for the same reason everything else here was,
because the depth being written was the rear face's and the rear faces were a
thickness apart. Correcting the winding did not cause the coplanarity. It
revealed it.

Neither `Thickness3d.stepOver` nor a component-side fix reaches this: the
outermost slab of a component is flush with whatever the *application* put
behind it, and a `Switch3d` cannot know it is on a card. So the surface takes
responsibility for its own contact: `Material3d.contentLift`, a fifth of a
logical pixel on the node tier, the same figure the glyphs are lifted by. A
surface lifts what is drawn on it; nesting surfaces adds the lifts up; the
boxes do not move, so layout, intrinsics and hit testing are untouched.

`content_on_the_face_test.dart` grew the second half of its rule with it —
**no two overlapping opaque panels share a front face** — asked of the switch,
the navigation bar, and a card holding a slider, a checkbox and a chip, with a
deliberately flush pair proving the check can fail. Transparent panels are
exempt and that is not a fudge: the panel shader discards where its own alpha
is zero, so a colourless surface writes no depth and has nothing to fight
with.
