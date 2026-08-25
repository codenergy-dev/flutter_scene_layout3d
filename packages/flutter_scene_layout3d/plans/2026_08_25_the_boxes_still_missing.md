---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
---

# The layout boxes still missing

The layout algebra is close to complete; a handful of Flutter's boxes have no
counterpart here, and a component catalogue asks for them by name. This plan
is a list with a difficulty grading, not one design — take an item, build it,
tick it off.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).

## The one that matters most

**`LayoutBuilder3d`.** Without it, nothing can build differently depending on
the room it is given: no responsive component, no "show the label only if it
fits", no `Scaffold3d` that changes shape on a narrow panel. It is the single
absent box that blocks the most.

It needs to build widgets during the layout pass, which is exactly the
machinery
[lazily built children](2026_08_25_lazily_built_children_in_the_widget_layer.md)
builds. **Do that plan first and this becomes a small addition** — the same
`buildScope`-during-layout window, one child instead of many. Attempting it
before that plan means building the machinery twice.

## Grade 1: mechanical

Each is a small `SingleChildLayout3d` with a constraints transformation and no
open questions. Any of them can be done in an afternoon, with a widget and a
test.

- [ ] `LimitedBox3d` — caps an unbounded axis. Worth more here than in
      Flutter: a `Layout3dSurface` is unbounded on all three axes by default,
      so unbounded constraints are the normal case rather than the exception.
- [ ] `UnconstrainedBox3d`
- [ ] `OverflowBox3d`
- [ ] `FractionallySizedBox3d`
- [ ] `IndexedStack3d` — one visible child; with no clipping this is
      `Stack3d` plus `node.visible`, which is already how the scrolling views
      cull.
- [ ] `SliverPadding3d` (listed here rather than with
      [persistent headers](2026_08_25_persistent_sliver_headers.md) because it
      is mechanical and independent).

## Grade 2: needs a decision first

- [ ] **`AspectRatio3d`.** A ratio between *which* two axes? Three sensible
      answers: a pair of axes plus a ratio; a full `Size3d` ratio constrained
      to fit; or a 2D ratio on the surface plane with depth free. Pick one,
      write down why, and note that the 2D-habit answer (width : height) is
      the one a caller will assume.
- [ ] **`FittedBox3d`.** `NodeBox3d.fit` already does this for engine content.
      For a laid-out *subtree* it means laying out at one size and scaling by
      a transform, which is `Transform3d` territory — and `Transform3d` is
      already the documented exception in hit testing (it neither answers hits
      itself nor gates children on its extent). Decide whether `FittedBox3d`
      inherits that exception or does better, and say so in its doc.
- [ ] **`Table3d`.** Flutter's `Table` is column widths negotiated from
      intrinsics. The intrinsic protocol here is per-axis and already
      supports it; the question is whether a third axis means anything for a
      table, or whether it is a plane arrangement with depth as an alignment
      axis, the choice `Wrap3d` already made and documented.

## Grade 3: needs machinery

- [ ] **`LayoutBuilder3d`** — see above; after
      [lazily built children](2026_08_25_lazily_built_children_in_the_widget_layer.md).
- [ ] **`CustomMultiChildLayout3d` and `MultiChildLayout3dDelegate`.**
      Flutter's `Scaffold` is literally a `CustomMultiChildLayout`, so a
      faithful `Scaffold3d` wants this. The delegate API ports directly:
      `hasChild(id)`, `layoutChild(id, constraints)`, `positionChild(id,
      offset)`, with `Size3d`/`Offset3d`/`Constraints3d` substituted.
- [ ] **`Flow3d`** — a paint-time transform per child. Here "paint time" is
      the node transform, which makes `Flow3d` *cheaper* than in Flutter: a
      repositioning that never touches layout, the same category as the
      node-only animations in
      [animation](2026_08_25_animation_and_scroll_physics.md).
- [ ] **`PageView3d` / `TabBarView3d`** — a viewport with paged physics.
      Depends on physics from
      [animation](2026_08_25_animation_and_scroll_physics.md).
- [ ] **`Dismissible3d`, `Draggable3d`, `DragTarget3d`, reorderable lists** —
      all depend on real drag recognition from
      [pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md).

## Conventions to keep

Every item follows what the package already does, so none of this needs
re-deciding per box:

- A layout, then a `Scene`-prefixed widget for it, both named after the
  Flutter class with the `3d` suffix, and both exported.
- `crossAxisAlignment` is the first cross axis, `depthAxisAlignment` the
  second; the depth axis aligns rather than wraps.
- An unbounded axis is normal, not an error, and a box that cannot cope says
  so with an assertion that names the fix.
- Intrinsics are implemented, or refused for a stated reason (the scrolling
  views refuse; `Wrap3d` documents that its cross-run answer is a lower
  bound).
- The README's table of counterparts gains a row in the same pass.

## Tests

Per box: sizing under tight, loose and unbounded constraints on each of the
three axes; intrinsics; hit testing including the depth axis; and the widget
form applying a property change without rebuilding the layout object.
