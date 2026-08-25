---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
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
