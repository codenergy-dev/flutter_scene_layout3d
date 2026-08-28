---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-28T21:10:00Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
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
[The remaining boxes](2026_08_25_the_boxes_still_missing.md) can be picked off
as components ask for them, and
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
  in an inherited widget, so the imperative layer has it as well.

## What happened

All ten plans were implemented, in the order above, one commit each, between
`45adb23` and `e890920`. (Those hashes are the ones in this repository. The
work was done inside a fork of the engine's monorepo and moved here with its
history rewritten, so the original hashes no longer resolve; the `commit:`
field in each plan's front matter still names the fork commit the plan was
reasoned against, which is what that field is for.) The suite went from 276 tests to **716**, and
`dart analyze` is clean across the package and both example apps that depend
on it.

| Plan | Status | Landed as |
| --- | --- | --- |
| Camera-bound surfaces | completed | `45adb23` |
| Text in a 3D layout | in progress | `3f15f2a` |
| Size-driven geometry | in progress | `3646134` |
| Pointer dispatch and focus | completed | `b20ce06` |
| Lazily built children | completed | `4e34e72` |
| Overlays and layered surfaces | completed | `1ab5d68` |
| Persistent sliver headers | completed | `2bcea83` |
| Animation and scroll physics | completed | `f98bbc0` |
| The boxes still missing | in progress | `213245b` |
| Diagnostics and semantics | completed | `e890920` |

The three still open are open for one reason each, recorded in their own front
matter: text has no glyph atlas, geometry has no compiled shader, and the drag
boxes have no drag. See *What is still missing* below.

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

**The package draws almost nothing by default.** This is the single largest
gap, and it is one gap wearing two hats: `BoxDecoration3d.painterFactory` is
null until something sets it, and `Text3dRenderer` has no in-tree
implementation. Both are seams with real geometry behind them
(`assets/box_decoration3d.fmat` ships; the measurement layer is exact against
Skia at every whole width tested), and neither can be verified here, because a
glyph atlas needs a GPU context `flutter test` does not have and no lane in
this repository compiles a `.fmat`. The debug wireframe is currently the only
thing in the package that puts geometry into a scene on its own account.

Also open, each for a stated reason rather than for lack of time:

- **Drag and drop.** `Dismissible3d`, `Draggable3d`, `DragTarget3d` and
  reorderable lists wait on a payload-carrying drag that the pointer plan put
  in its own out-of-scope section. It is a plan of its own.
- **Keep-alive** for lazily built children, deferred by that plan's own text.
- **Subtree opacity**, which needs a per-node opacity in `flutter_scene` that
  the materials honour.
- **A shadow pass does not run `Surface()`**, so a rounded panel casts the
  shadow of its whole slab.
- **`TapTarget3d` grows the ray region but not the box.** The Material 48dp
  minimum is invisible to layout, to intrinsics, to `ensureVisible3d` and now
  to semantics, which announces the smaller rectangle. Deliberate — it keeps
  neighbours from moving — but it is the sharpest edge a catalogue author will
  meet.
- **`Layout3d.clipRegion` walks up per call**, and `DecoratedBox3d` calls it
  every layout: O(depth²) per frame on a deep screen. Fine today, and worth
  measuring at catalogue scale.
