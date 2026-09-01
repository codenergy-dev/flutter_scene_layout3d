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
| Use the layout protocol: boxes, slivers, scrolling, text, decoration, input, overlays, animation | the [package README](../packages/flutter_scene_layout3d/README.md) — the deep reference, box by box |
| Work in this repository as a coding agent | [AGENTS.md](../AGENTS.md) — conventions, plans, commits, how to run things |
| Avoid the sharp edges of this package | [traps.md](traps.md) |
| Use `flutter_scene` correctly | [engine-rules.md](engine-rules.md) |
| See it running, or write a demo | [examples/layout3d_gallery](../examples/layout3d_gallery/README.md) |
| Verify something actually draws | [examples/render_probe](../examples/render_probe/README.md) |
| Know what is planned, in progress, or was decided and why | [the plans directory](../packages/flutter_scene_layout3d/plans/) |
| Know what is being built next | [the Material catalogue plan](../packages/flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md) |

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
  without, and the two places that plan's own reasoning turned out wrong.

## Keeping this true

A page that describes behaviour the code no longer has is worse than no page,
because the next reader trusts it. When you change behaviour, the page changes
in the same commit — and when you add a page, it gets a row above. Both are
part of the change, not follow-up work.
