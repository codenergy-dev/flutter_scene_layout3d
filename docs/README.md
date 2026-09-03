# Documentation map

Where everything is written down, and which question each place answers. Start
here when you do not yet know what you are looking for.

The rule this repository follows: **documentation lives next to what it
describes**, and this index maps it. A page here exists only when the thing it
covers has no natural home next to code — cross-cutting rules, traps that span
several files, guidance for using the engine underneath.

## Start with the question you have

| You want to | Read |
| --- | --- |
| Understand what this project is and why | the root [README](../README.md) |
| Use the layout protocol: boxes, slivers, scrolling, text, decoration, input, overlays, animation | the [layout package README](../packages/flutter_scene_layout3d/README.md) — the deep reference, box by box |
| Theme a surface, or build a Material component | the [Material package README](../packages/flutter_scene_material3d/README.md) — the one setup call, `Material3d` and `InkWell3d`, the token families, and both halves of the theme channel |
| Work in this repository as a coding agent | [AGENTS.md](../AGENTS.md) — conventions, plans, commits, how to run things |
| Avoid the sharp edges of this package | [traps.md](traps.md) |
| Use `flutter_scene` correctly | [engine-rules.md](engine-rules.md) |
| See it running, or write a demo | [examples/layout3d_gallery](../examples/layout3d_gallery/README.md) |
| Verify something actually draws | [examples/render_probe](../examples/render_probe/README.md) |
| Know what is planned, in progress, or was decided and why | the plans directories of [the layout package](../packages/flutter_scene_layout3d/plans/) and [the Material package](../packages/flutter_scene_material3d/plans/) |
| Know what is being built next | [the Material catalogue plan](../packages/flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md) — phases 0 to 3 done, the buttons included, and the rest of the catalogue from phase 4 |

## The pages here

- **[traps.md](traps.md)** — what costs real time and is not obvious from the
  code. The unit contract, staying off the relayout path, the four transform
  channels, why nothing draws by default, depth ordering, and the pointer,
  drag and clipping edges.
  If you are about to write a component, read this first.
- **[engine-rules.md](engine-rules.md)** — `flutter_scene` diverges from
  three.js, Godot and Unity in specific ways, and most first-attempt failures
  come from reaching for another engine's spelling. Short, and each item is a
  build failure or a silent wrong result.

## The diagrams

Used by the root README, and worth reading on their own:

- **[protocol.svg](protocol.svg)** — constraints down, sizes up, the parent
  positions the child, and the result as geometry on a plane.
- **[basis.svg](basis.svg)** — the same layout tree on an upright panel and on
  the ground, and what "down" means in each.
- **[units.svg](units.svg)** — where the dp ↔ world-unit rate comes from when
  a surface is bound to the camera.

## Where the reasoning lives

`packages/flutter_scene_layout3d/plans/` is not a backlog. Each plan records
what was intended, what shipped, and — in a section every finished plan has —
**what the original reasoning got wrong**. Several of those corrections are
load-bearing and are not deducible from the code.

Two entry points:

- [The Material readiness overview](../packages/flutter_scene_layout3d/plans/2026_08_25_material3d_readiness_overview.md)
  is the map of the ten plans that built most of this package, and its *Where
  to pick up* section says what to do next and why.
- [The render coverage plan](../packages/flutter_scene_layout3d/plans/2026_08_28_render_coverage.md)
  built the lane that draws a frame and checks it, and its findings section is
  a good sample of what surprises people here.
- [The Material catalogue plan](../packages/flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md)
  is what happens next, and the only plan in either package still open. Its
  middle section — what an elevation, a ripple, a disabled state and a
  thickness mean once the depth is real — is design reasoning that exists
  nowhere else. Its phase 0 is done, in
  [the four things before a component](../packages/flutter_scene_layout3d/plans/2026_09_01_the_four_things_before_a_component.md):
  the four additions to the layout package a first component could not do
  without, and the two places that plan's own reasoning turned out wrong. Its
  phase 1 — the package and the tokens — is done too, and its findings section
  records what that turned up, including the gap that stood in phase 2's way:
  the widget layer could not read the surface's metrics, so a figure written in
  a `build` method was in world units and not logical pixels. That is closed,
  in [the metrics a build method can read](../packages/flutter_scene_layout3d/plans/2026_09_02_the_metrics_a_build_method_can_read.md)
  — `Layout3dMetricsScope.of(context)`, and the phase-ordering argument that
  says a value read in `build` is not stale by the time the layout uses it.
  Phase 2 left one gap of its own and phase 3 closed it the same way:
  `TapTarget3d`'s 48dp minimum grew the ray region and delivered no press out
  in the margin, which is settled in
  [a tap target that delivers a press](../packages/flutter_scene_layout3d/plans/2026_09_02_a_tap_target_that_delivers_a_press.md)
  — the nine-line fix, and the placement rule underneath it that is the half
  worth reading. Phase 3, the seven buttons, is done.

## Keeping this true

A page that describes behaviour the code no longer has is worse than no page,
because the next reader trusts it. When you change behaviour, the page changes
in the same commit — and when you add a page, it gets a row above. Both are
part of the change, not follow-up work.
