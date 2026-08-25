---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
---

# Diagnostics, and the accessibility story

Building a component catalogue against this package means debugging layout
that cannot be seen: nothing paints, boxes are invisible, and the only output
is a tree of node transforms. Flutter's answer to the same problem is
`toStringDeep`, the overflow stripes, `debugPaintSize` and the inspector.
This package has none of them: there is no `Diagnosticable` anywhere in
`lib/src`.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).
Worth pulling forward the moment catalogue work starts, because every other
plan is debugged with these tools.

## The cheap items, worth doing first

- [ ] **`Diagnosticable` on `Layout3d`.** `debugFillProperties` with
      constraints, size, offset, relayout boundary and dirt state;
      `toStringShallow` and `toStringDeep`; `debugDumpLayout3dTree(surface)`.
      Mechanical, and it turns every failing layout test from a number
      mismatch into a readable tree.
- [ ] **An assertion for the silent-drop trap.**
      [Layout3dRenderBox.performLayout](../lib/src/widgets/framework.dart)
      collects only children that are `Layout3dRenderBox` and *silently
      ignores the rest*. `StatelessWidget`, `StatefulWidget`,
      `InheritedWidget` and `Builder` are transparent, which is what makes a
      component library writable at all — but interpose one ordinary Flutter
      widget that creates a render object (a `Padding`, an `Opacity`) and the
      whole subtree below it vanishes with no error. In debug, assert with a
      message that names the offending widget and says which layout widgets
      may appear between two `Scene*3d` widgets. This is a handful of lines
      and will save someone a day.
- [ ] **An overflow report.** A child that exceeded the constraints its
      parent gave it, reported in debug with the box, the axis and the amount.
      The depth axis matters most: geometry standing out through a panel is
      the 3D symptom of an overflow and it is much easier to miss than a
      yellow stripe.

## The visual half

- [ ] **A debug wireframe.** Every box's extent as line geometry hung under
      its node, toggled by a flag — `debugPaintSize` with real lines. The
      engine already ships `line_segments_geometry.dart`, so this is
      assembly, not new rendering. This is the single most useful tool in the
      list for someone laying out a component they cannot see.
- [ ] **Baselines and offsets** as optional overlays on the same flag, since
      `Baseline3d` and `CrossAxisAlignment3d.baseline` are otherwise entirely
      invisible.

## Semantics

`flutter_scene` already has the pieces: `SemanticsComponent`
(`lib/src/components/semantics_component.dart`), and `SceneView` synthesizes
Flutter semantics nodes from the components in the scene, sized from
`component.size` (`lib/src/widgets/scene_view.dart:695`–`708`). So the path is
concrete rather than speculative:

- [ ] **A `Semantics3d` box** that attaches a `SemanticsComponent` to its
      node, carrying the label, hint, value and flags, and sized from the
      box's own extent projected to the view.
- [ ] **Decide what a component author writes.** Most likely the same
      `SemanticsProperties` Flutter uses, so a `Button3d` declares
      `button: true, label: ...` and it reaches the platform through the
      existing `SceneView` path.
- [ ] **Focus and semantics agreement**: a focusable box
      ([pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md)) should be
      a semantics node, and traversal order should follow layout order.

A catalogue that claims to implement Material claims accessibility with it.
Getting this designed early is much cheaper than retrofitting it across fifty
components.

## Tests

- `toStringDeep` of a small tree matches an expected shape (a golden string,
  as Flutter tests its own).
- The interposed-render-object assertion fires on a `Padding` between two
  `Scene*3d` widgets and not on a `Builder`, a `StatefulWidget` or an
  `InheritedWidget`.
- An overflow on each axis is reported once, with the right amount.
- A `Semantics3d` box produces a semantics node with the expected label and a
  size derived from the box.

## Out of scope

A visual inspector or editor integration (the
[Flutter Scene Editor](../../../apps/flutter_scene_editor_app) is where that
would belong), and performance profiling, which the engine's own
`flutter_scene-performance` skill already covers.
