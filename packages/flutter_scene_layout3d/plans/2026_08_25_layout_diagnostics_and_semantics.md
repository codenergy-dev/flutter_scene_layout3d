---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-28T20:34:35Z
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

**The inventory this plan was written against has grown.** It was written when
plans 1–9 were pending; all nine landed first, so the package it was
implemented against is much larger than the one it describes. Instrumenting
"every box" now means text, decorations and clipping, input and focus,
overlays and routes, slivers and persistent headers, the animation layer, the
scroll physics, and a dozen boxes (`LayoutBuilder3d`, `CustomMultiChildLayout3d`,
`Flow3d`, `Table3d`, `FittedBox3d`, `IndexedStack3d`, …) that did not exist
when the plan was reasoned about. What was implemented covers what is actually
there, not what the plan's text lists.

## The cheap items, worth doing first

- [x] **`Diagnosticable` on `Layout3d`.** `Layout3d` now mixes in
      `DiagnosticableTreeMixin`, so `toStringShallow`, `toStringDeep` and
      `toDiagnosticsNode` all come from Flutter's own machinery rather than a
      parallel one. `Layout3d.debugFillProperties` carries the name, the
      constraints, the size (`MISSING` rather than a plausible-looking zero
      when the box was never laid out), the offset, `sceneOffset`,
      `nodeOffset`, `nodeTransform`, `sizedByParent`, the relayout boundary in
      Flutter's `up{n}` spelling, and the `NEEDS-LAYOUT` / `DETACHED` /
      `DISPOSED` flags; `debugDescribeChildren` walks `visitChildren`, so a
      box that arranges its children in an order of its own dumps them in that
      order. `lib/src/debug/diagnostics.dart` adds
      `debugDumpLayout3dTree`, `debugDescribeLayout3dTree` and
      `debugDescribeLayout3dAncestry`.

      Roughly forty-five classes got a `debugFillProperties` of their own,
      across the whole package rather than the boxes the plan knew about:
      every box, `ClipBox3d`, `DecoratedBox3d`, `Text3d`, the scroll views and
      `Scroll3dHolderMixin` (which prints the scroll offset and extents), the
      slivers including `SliverPersistentHeader3d`, `Focus3d`, `FocusScope3d`,
      the hit-test-behaviour boxes, `GestureDetector3d`, `TapTarget3d`,
      `ModalBarrier3d`, `Overlay3d`, `Layout3dSurface` and `Semantics3d`.

      Six classes had a `toString()` of their own that a `DiagnosticableTree`
      cannot keep (the signature differs); each was converted to
      `debugFillProperties`, which says strictly more than the string it
      replaced.

- [x] **An assertion for the silent-drop trap.**
      `debugCheckNoInterposedRenderObject` in
      [framework.dart](../lib/src/widgets/framework.dart), asserted from
      `Layout3dRenderBox.layoutChildBoxes` for every render child that is not
      a `Layout3dRenderBox`. It walks the interposed subtree, and if any
      `Layout3d` is hiding under it, throws a `FlutterError` naming the
      offending *widget* (through `debugCreator`, so the message says
      `Padding`, not `RenderPadding`), the first layout that was lost, the
      rule about which widgets may sit between two `Scene*3d` widgets, and the
      3D widget to use instead. An interposed render object with nothing 3D
      below it is legal and stays silent.

- [x] **An overflow report.** `lib/src/debug/overflow.dart`:
      `Layout3dOverflow` (the box, the per-axis amount, a hint, and a
      `describe()` that names the edge — `right`, `bottom`, `back`),
      `Layout3dOverflowReportingMixin` (`debugReportOverflow`, `debugOverflow`,
      and the throttling that reports a given overflow once rather than on
      every frame of a fling), and `debugLayout3dOverflowReporter`, which
      defaults to `FlutterError.reportError` and can be pointed at a collector.
      Mixed into `Flex3d` (main axis and both cross axes) and
      `UnconstrainedBox3d` — the two places Flutter stripes, for the same
      reasons.

## The visual half

- [x] **A debug wireframe.** `lib/src/debug/wireframe.dart`:
      `debugPaintLayout3dSize` hangs the twelve edges of every laid-out box
      under its scene node, synced by `Layout3dSurface.flush` (inside an
      `assert`, so release pays nothing) and taken back out when the flag is
      cleared. It is one shared unit-cube `LineSegmentsGeometry` scaled per
      box — the decoration painter's economy, so a box animating its size
      rebuilds nothing. A hidden or culled subtree draws nothing.
- [x] **Baselines and offsets** on `debugPaintLayout3dBaselines`: a baseline
      is drawn as two lines across the box at the declared distance, on every
      axis that declares one, and the placement offset as a line running back
      to the parent's origin corner.

The one thing the plan did not anticipate: building line geometry allocates a
device buffer, so the real wireframe cannot exist before
`Scene.isReadyToRender` and cannot exist at all in a headless test. It is
therefore behind `debugLayout3dWireframeFactory`, the same seam
`BoxDecoration3d.painterFactory` uses; the default returns the real
`LineSegments3dWireframe` once the engine is ready and null before that, and a
test installs a recording implementation. The assembly (which boxes, which
lines, which extents) is fully covered; the pixels are not, for the same
reason nothing else in this package's test suite draws.

## Semantics

- [x] **A `Semantics3d` box** (`lib/src/semantics.dart`), with
      `SceneSemantics3d` as its widget form. It attaches a
      `SemanticsComponent` to its node and overrides
      `SemanticsComponent.boundsOverride` with the box's own extent on every
      layout, so the platform's focus rectangle is the box the layout protocol
      produced rather than whatever meshes happen to hang under the node.
      Setting a new label writes one field and lays nothing out again.
- [x] **What a component author writes** is Flutter's own
      `SemanticsProperties`, passed through unchanged. `SemanticsComponent`
      already accepts one, so `button: true, label: ...` reaches the platform
      through the existing `SceneView` path with nothing in between.
- [x] **Focus and semantics agreement**:
      `debugFocusableBoxesWithoutSemantics(root)` lists every `Focus3d` that
      no `Semantics3d` speaks for, which is the assertion a catalogue page
      makes in a test. Traversal order needed no code: reading order follows
      the scene graph, and in this package the scene graph *is* the layout
      tree, because a child's node is added to its parent's node in layout
      order by `adoptChild`. `sortOrder` is exposed for the cases where that
      is wrong.

## Tests

`test/diagnostics_test.dart`, 24 tests, in the style of the existing suite.

- [x] `toStringDeep` of a small tree against a golden string
      (`equalsIgnoringHashCodes`, as Flutter tests its own), plus the
      never-laid-out case, the relayout boundary at `DiagnosticLevel.fine`,
      and the ancestry walk.
- [x] The interposed-render-object error fires on a `Padding` between two
      `Scene*3d` widgets, with the widget name and the lost layout in the
      message, and does not fire on a `Builder`, a `StatefulWidget`, an
      `InheritedWidget`, or an interposed render object with nothing 3D below.
- [x] An overflow on the main axis and on depth, each reported once with the
      right amount, cleared when it fits and reported again when it comes
      back, from `Flex3d` and from `UnconstrainedBox3d`, and the default
      reporter's `FlutterError`.
- [x] The wireframe: what is drawn per box and at what extent, the baseline
      and offset lines, a hidden subtree giving its lines back, the flag going
      off disposing the wireframe, and the default factory drawing nothing
      while the engine is not ready.
- [x] `Semantics3d` produces a component whose bounds come from the box (not
      from the child), a label change that relayouts nothing, disabling,
      traversal order following the scene graph, and
      `debugFocusableBoxesWithoutSemantics`.

## What the original reasoning got wrong

- **"there is no `Diagnosticable` anywhere in `lib/src`"** was true of the
  boxes, but six classes had hand-rolled `toString()` overrides whose
  signature is incompatible with `DiagnosticableTreeMixin`. Adopting Flutter's
  machinery meant replacing them, not adding beside them.
- **The wireframe is not pure assembly.** The plan called it "assembly, not
  new rendering" because `line_segments_geometry.dart` ships. It is — but the
  geometry allocates a GPU buffer at construction, which needs an engine seam
  and a headless fallback the plan did not budget for.
- **Cross-axis overflow in a `Flex3d` is nearly unreachable**, because the
  flex hands its own cross-axis constraints down and a well-behaved child
  cannot exceed them. The check is still there (baseline alignment can push a
  line past its constraints), but the axis that actually overflows in practice
  is the main one, and depth overflows come from a `Depth3d` or from content
  thicker than the plane.
- **`ClipBox3d` deliberately does not report.** An early draft had it report
  content standing outside the clip; that is the *point* of a clip (a
  `ListView3d` inside one overflows by design), so it would have fired
  constantly. Flutter does not report there either.
- **`TapTarget3d` and `Semantics3d` disagree by construction.** The target
  grows the region a ray reaches without growing the box, so a semantics
  rectangle taken from the box is smaller than the touch target around it.
  Documented in the README rather than papered over; making them agree means
  deciding whether a touch target is a layout extent, which is a catalogue
  question, not a diagnostics one.

## Out of scope

A visual inspector or editor integration (the Flutter Scene Editor, which
lives in the engine's own repository, is where that would belong), and
performance profiling, which the engine's own
`flutter_scene-performance` skill already covers. Both were deferred by the
plan's own text and remain deferred.
