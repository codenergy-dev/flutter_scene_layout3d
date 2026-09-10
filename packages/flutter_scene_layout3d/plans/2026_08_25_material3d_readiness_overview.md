---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-09-10T13:40:00Z
commit: 657eef80eb8dc8085c3b3a84a8069273495506be
---

# What a component library needs from this package

A map, not a work item. The goal behind it is `flutter_scene_material3d`: the
Material catalogue — `Button3d`, `Card3d`, `Icon3d`, `Scaffold3d`, `AppBar3d`,
and the rest — built as real geometry on this package's layout protocol.

The finding that produced these plans is that **the layout algebra is close to
done and almost nothing else is there**. Constraints, intrinsics, baselines,
flex, stack, wrap, the sliver protocol and ray hit testing all exist and are
faithful. What a component library needs on top of them — text, geometry that
follows a box's size, event dispatch, lazily built widget children, overlays,
animation — is either absent or stops halfway.

Each item below is a plan of its own, written to be handed to an implementer
who has read only that plan and this paragraph. Where two plans touch, the
seam is named in both.

## The plans

| Plan | What it unblocks |
| --- | --- |
| [Text in a 3D layout](2026_08_25_text_in_a_3d_layout.md) | every label in the catalogue |
| [Size-driven geometry](2026_08_25_size_driven_geometry.md) | panels, corners, borders, elevation, state layers |
| [Pointer dispatch and focus](2026_08_25_pointer_dispatch_and_focus.md) | pressed / hovered / focused, every interactive control |
| [Lazily built children](2026_08_25_lazily_built_children_in_the_widget_layer.md) | long lists of widget-built items |
| [Overlays and layered surfaces](2026_08_25_overlays_and_layered_surfaces.md) | `Scaffold3d`, dialogs, menus, snack bars, tooltips |
| [Persistent sliver headers](2026_08_25_persistent_sliver_headers.md) | `SliverAppBar3d` |
| [Animation and scroll physics](2026_08_25_animation_and_scroll_physics.md) | ripples, elevation changes, fling, `ensureVisible` |
| [The boxes still missing](2026_08_25_the_boxes_still_missing.md) | `LayoutBuilder3d`, `CustomMultiChildLayout3d`, and friends |
| [Diagnostics and semantics](2026_08_25_layout_diagnostics_and_semantics.md) | developing the catalogue without flying blind |
| [Camera-bound surfaces](2026_08_25_camera_bound_surfaces.md) | a panel that *is* the screen, and the dp ↔ world-unit contract |

Two more plans were written after these ten and belong on the same map.
[Render coverage](2026_08_28_render_coverage.md) built the lane that draws a
frame on a real GPU and checks it against the layout — the answer to the first
paragraph of *What is still missing* below.
[Drag and drop](2026_09_01_drag_and_drop.md) built the payload-carrying drag
that the pointer plan put outside its own scope, and that the last of the
boxes were waiting on.

## The order, and why

**[Camera-bound surfaces](2026_08_25_camera_bound_surfaces.md) first**, even
though it looks like the most exotic of the ten. It owns the unit contract —
how many world units a logical pixel is — and text sizing, corner radii,
touch targets, elevation and rasterization resolution all need that number.
Deriving it from a camera-bound surface is the one place it is *derivable*
rather than invented, which is why it leads.

Then the three that stand between here and a single working button:

1. [Text](2026_08_25_text_in_a_3d_layout.md).
2. [Size-driven geometry](2026_08_25_size_driven_geometry.md).
3. [Pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md).

With those, `Button3d`, `Card3d`, `Icon3d` and `ListTile3d` are writable.

Then the two that unblock whole regions of the catalogue:
[lazily built children](2026_08_25_lazily_built_children_in_the_widget_layer.md)
(long lists, and — because it is the same machinery —
`LayoutBuilder3d`) and
[overlays](2026_08_25_overlays_and_layered_surfaces.md) (`Scaffold3d` and
everything modal).

[Persistent headers](2026_08_25_persistent_sliver_headers.md) and
[animation](2026_08_25_animation_and_scroll_physics.md) follow.
[The remaining boxes](2026_08_25_the_boxes_still_missing.md) are all here now,
and
[diagnostics](2026_08_25_layout_diagnostics_and_semantics.md) is worth pulling
forward the moment the catalogue work starts, because it pays for itself in
debugging time.

## The seams to keep an eye on

- **Clipping does not exist and several plans want it.** Size-driven geometry
  proposes shader plane-clipping; persistent headers need it to stop content
  sliding visibly under a pinned bar; overlays need it for menus. Whoever gets
  there first owns the contract, and the other two consume it.
- **Relayout cost compounds.** Animation dirties layout every frame; text
  measurement and geometry rebuilding are the two things that must not be on
  that path. This is why text is planned around a prepare/layout split and
  decorations around a shader rather than regenerated meshes.
- **`Layout3dOwner` is the tree-wide channel.** It already carries the basis
  and the visual-update callback; the metrics contract belongs there too, not
  in an inherited widget, so the imperative layer has it as well. (Shipped,
  and with one consequence nobody wrote down at the time: because the metrics
  is *only* on the owner, the widget layer cannot read it at all. See the
  Material catalogue entry under *Where to pick up*.)

## What happened

All ten plans were implemented, in the order above, one commit each, between
`45adb23` and `e890920`. (Those hashes are the ones in this repository. The
work was done inside a fork of the engine's monorepo and moved here with its
history rewritten, so the original hashes no longer resolve; the `commit:`
field in each plan's front matter still names the fork commit the plan was
reasoned against, which is what that field is for.) The suite went from 276
tests to **716**, and `dart analyze` is clean across the package and both
example apps that depend on it. The two plans written since took it further:
**862** headless tests today, beside **40** that draw on a GPU and probe the
pixels.

| Plan | Status | Landed as |
| --- | --- | --- |
| Camera-bound surfaces | completed | `45adb23` |
| Text in a 3D layout | completed | `3f15f2a`, then the atlas renderer |
| Size-driven geometry | completed | `3646134`, then its probes |
| Pointer dispatch and focus | completed | `b20ce06` |
| Lazily built children | completed | `4e34e72` |
| Overlays and layered surfaces | completed | `1ab5d68` |
| Persistent sliver headers | completed | `2bcea83` |
| Animation and scroll physics | completed | `f98bbc0` |
| The boxes still missing | completed | `213245b`, then the drag boxes |
| Diagnostics and semantics | completed | `e890920` |

**All ten are closed.** The last three closed later than the rest, each once
the thing it was waiting for existed — text once `examples/render_probe` could
draw a glyph atlas and check the frame against it; the boxes once
[drag and drop](2026_09_01_drag_and_drop.md) shipped the payload-carrying drag
their last item wanted; and size-driven geometry once that same render lane
could probe an elevation, a border and a state layer, and could answer the
shadow question the plan had only guessed at. What each of them deliberately
left out is in *What is still missing* below, with the reason.

## How the seams resolved

- **Clipping got built, and all three consumers use it.** Size-driven geometry
  owned the contract as planned; `Clip3dRegion` is an intersection of planes in
  a box's own frame, `clipRegionForChild` is the override point. Persistent
  headers is the tier-two consumer — a pinned bar publishes a single plane and
  a row half under it is genuinely cut, with nothing added to the material to
  make that work. Overlays needed only the culling tier. A corner radius is
  *not* a clip: a plane region is convex, and the radius is carved by the panel
  shader instead.
- **Relayout cost stayed off the animation path.** Animation landed three
  tiers: repaint-only (decoration and state-layer setters, shader uniforms, no
  layout), node-only (`nodeOffset`/`nodeTransform`, one matrix a frame), and
  implicit, only when a size really changed. A test asserts
  `debugTextParagraphCount` does not move while a container resizes a label
  through a whole run — the guard the text plan asked for, and the test that
  fails first if measurement gets back onto the layout path.
- **`Layout3dOwner` carried the metrics contract**, as the overview wanted.
  `Layout3dMetrics` sits beside the basis and a box reads it as
  `Layout3d.metrics` inside `performLayout` — no `BuildContext`, no inherited
  widget, so the imperative layer has it too. Writing it relayouts the subtree
  by design, which is why nothing per-frame may touch it.

## What is still missing

**The package draws nothing until it is asked to.** This was the single
largest gap and it is now a deliberate pair of seams rather than a hole:
`BoxDecoration3d.painterFactory` is null until an application sets it, and
`Text3d` takes a renderer and has none by default — though the widget layer
now inherits one from a `DefaultTextRenderer3d`, and the shader behind the
painter is compiled by this package's own build hook rather than by the app. Both now have an in-tree
implementation behind them — `BoxDecoration3dPainter` over the shipped
`assets/box_decoration3d.fmat`, and `AtlasText3dRenderer` over a shared glyph
atlas, with `RichText3d` beside it for what an atlas cannot assemble — and
both are verified where they can be: the arithmetic in `flutter test`, the
pixels in [render coverage](2026_08_28_render_coverage.md)'s
`examples/render_probe`, which compiles the `.fmat` and probes a drawn
label.

Also open, each for a stated reason rather than for lack of time:

- **A reorderable list has no declarative form.** There is no
  `SceneReorderableList3d`, and there cannot be one until
  `Layout3dBuiltChildrenMixin` grows a seam that lets a view adopt what the
  child manager built: the list wraps every item in a `Draggable3d` of its
  own, and the declarative contract is that `removeChild` is handed back the
  very layout `createChild` returned. The same seam is what an
  explicit-children constructor for that list would need.
- **`Drag3dAnchor.targetPlane` is reserved, not built.** Re-parenting a
  feedback box into the target's overlay costs two layout passes and a rebuild
  in the middle of the one interaction this whole design keeps off the
  relayout path. The alternative — projecting the carried box onto the
  target's plane on the node tier — is written up in the drag plan rather than
  half-built here.
- **Keep-alive** for lazily built children, deferred by that plan's own text.
- **Subtree opacity**, which needs a per-node opacity in `flutter_scene` that
  the materials honour, and there is none in 0.23.0: `Node` carries `visible`,
  a selection-outline `highlightColor`, layer and light masks and shadow
  flags, and no opacity or tint of any kind. Shipping an `Opacity3d` that
  faded only `BoxDecoration3d` is the thing that plan told its implementer not
  to do.
- **A decorated panel casts no shadow.** Not "the shadow of its whole slab",
  which is what this list said while it was a guess: `box_decoration3d.fmat`
  declares `blending: alpha` and `ShadowEncoder` drops every non-opaque
  material before it reaches a shadow map, so a panel is not a caster at all.
  (An opaque one *would* cast its whole rectangular slab, since a shadow pass
  runs `DepthOnlyFragment` and never a material's `Surface()`.)
  `examples/render_probe`'s `panel_shadow` scene demonstrates it, against an
  opaque cube as the control, and fails if the engine ever changes.
- **`TapTarget3d` grows the ray region but not the box.** The Material 48dp
  minimum is invisible to layout, to intrinsics, to `ensureVisible3d` and now
  to semantics, which announces the smaller rectangle. Deliberate — it keeps
  neighbours from moving — but it is the sharpest edge a catalogue author will
  meet. *Two later corrections, both under
  [a tap target that delivers a press](2026_09_02_a_tap_target_that_delivers_a_press.md):*
  the reach delivered no press at all until that plan, and the edge it turned
  out to be is **placement** — a target reaches past its own extent and its
  parent does not, so it has to sit outside every box the size of the control.
- **`Layout3d.clipRegion` walks up per call**, and `DecoratedBox3d` calls it
  every layout: O(depth²) per frame on a deep screen. Fine today, and worth
  measuring at catalogue scale.

## Where to pick up

Enough context to hand a single plan to an implementer who has read only that
plan and this section.

**Nothing is blocked on infrastructure any more.** The plans that used to wait
on there being no way to draw or verify a frame no longer do:
[render coverage](2026_08_28_render_coverage.md) built that lane and is done.
`examples/render_probe` draws on a real GPU and checks the frame against the
layout, and it already carries a `.fmat` from source through compilation to a
probed frame — which is the path a glyph atlas needs too.

In the order I would take them:

1. ~~**[Text](2026_08_25_text_in_a_3d_layout.md) phase 4, the glyph atlas.**~~
   Done: `AtlasText3dRenderer` draws a label out of a shared atlas and
   `RichText3d` is the escape hatch, both probed on a real GPU. What is left
   of text is sharpness at distance — the atlas holds coverage rasters, not a
   distance field — which is a level-of-detail question rather than a
   rendering one.
2. ~~**A drag plan, then the drag boxes.**~~ **Done.**
   [Drag and drop](2026_09_01_drag_and_drop.md) is the plan that was missing
   here, and it shipped: `Drag3dSession` and the cross-surface search under
   it, `Draggable3d`, `DragTarget3d`, `Dismissible3d` and reorderable lists
   over it, and autoscroll on a ticker. With those,
   [the boxes still missing](2026_08_25_the_boxes_still_missing.md) has
   nothing left and is `completed`. The premise held: a drag is arithmetic and
   state, and all but two claims about it were pinned down headlessly.
3. ~~**[Size-driven geometry](2026_08_25_size_driven_geometry.md)'s
   remainder.**~~ **Done.** Elevation, the border and the state layer have
   probes now — the lifted panel projects wider than the flat one and the
   frame agrees, the border draws in its own colour at the rim and not in the
   middle, a state layer lightens the same panel — and the probe found the
   shader drawing its border inside out, which sixty-two headless tests had
   passed over. The shadow item is answered rather than open: the engine will
   not cast a shadow from that material at all, and the plan records both the
   gate and what a catalogue does instead. Subtree opacity stays unshipped for
   the reason above, which is the plan's own rule and not a shortcut.
4. ~~**[`flutter_scene_material3d`](../../flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md)**,
   the catalogue this whole map was drawn for.~~ **Done — it shipped.** All
   ten phases of it, from the tokens to the gallery: `Material3d` and the
   primitive layer, the seven buttons, the surfaces and rows, `Scaffold3d` and
   the bars, the overlays, the selection controls, the press ripple, and an
   example app that draws every one of them on an upright panel and on a
   table. Everything the readiness work set out to provide was in place before
   it started, and the render harness meant a `Button3d` could be checked as a
   picture and not only as arithmetic. Its plan started
   with four things missing from *this* package rather than from that one —
   the widget layer could not draw, a label had no default renderer, there was
   nowhere tree-wide to put a theme, and compiling the panel shader was an
   application's job. All four landed, as
   [the four things before a component](2026_09_01_the_four_things_before_a_component.md):
   `SceneDecoratedBox3d`, `DefaultTextRenderer3d`, `Layout3dSlot<T>`, and a
   build hook on this package that compiles its own shader for every consumer.
   Read that plan's *what the original reasoning got wrong* before building on
   any of them; two of the four came out differently than expected. The
   catalogue's own plan is `completed`, and its closing section is the thing
   to read before extending any of it.

   Building it turned up **five** things this map did not have on its list,
   each closed in *this* package with a plan of its own, the way phase 0's
   four were. Read them in order; the last two are the same defect found
   twice.

   - ~~**`Layout3dMetrics` cannot be read from a `BuildContext`.**~~ Nothing
     exposed the surface's unit contract to the widget layer, so a `build`
     method could not convert a Material dp figure into world units. Closed in
     [the metrics a build method can read](2026_09_02_the_metrics_a_build_method_can_read.md).
   - ~~**A `TapTarget3d`'s reach delivered no press.**~~ The 48dp minimum grew
     the ray region and a press out in the margin landed on nothing. Closed in
     [a tap target that delivers a press](2026_09_02_a_tap_target_that_delivers_a_press.md),
     with the placement rule underneath it.
   - ~~**The clip contract's plane tier had never fired.**~~ A `ClipBox3d`
     takes its size from its child, so every panel under one was born with the
     unbounded block. Closed in
     [a clip that reaches the shader](2026_09_03_a_clip_that_reaches_the_shader.md).
   - ~~**And it was dead in a second place.**~~ A viewport learns what a
     pinned header is sitting on after its rows have painted, so a
     `SliverAppBar3d` cut nothing either. Closed, with the two widget forms
     the declarative layer was missing, in
     [the declarative side of a pinned bar](2026_09_08_the_declarative_side_of_a_pinned_bar.md).
   - ~~**Nothing anchored anything.**~~ An overlay entry sat where the
     overlay's alignment put it, so a menu could not be *at* its button, and a
     widget subtree could not be an entry's content at all. Both closed in
     [a widget under an overlay entry](2026_09_08_a_widget_under_an_overlay_entry.md),
     with `Layout3d.anchorOffsetTo` as the arithmetic.

   The fifth thing this map did not list is not a gap in the layout package at
   all — it is a rule about it that was written down and then broken. **A lift
   written into a child's position takes that child out of reach of a ray**,
   because a hit test clamps the ray to each box before asking its children.
   `ParentData3d.sceneOffset` has always said so, in as many words, and it is
   why `Stack3d.depthStep` is a scene offset. `Scaffold3d` wrote its depth
   ordering into `positionChild` anyway and every slot of every Material
   screen was unpressable, with 488 headless tests and 75 render probes all
   green. Only running the gallery found it. It is now in
   [docs/traps.md](../../../docs/traps.md) under *Depth ordering*.

**Every plan's `commit:` field resolves in this repository.** The plans that
predate the move out of the engine's monorepo were written against fork
commits; each was realigned onto the commit here that carries the same change,
matched by subject and commit date. `git show` one and you get the layout
package exactly as that plan's author saw it.

The `completed` plans record what their original reasoning got wrong. Read
those sections before extending any of them; several of the corrections are
load-bearing, and the drag plan's are the freshest — one of them is a bug that
861 headless tests agreed with, and only a drawn frame caught.

For everything outside the plans — the protocol reference box by box, the
traps, the engine's own rules — the
[documentation map](../../../docs/README.md) says which page answers which
question.
