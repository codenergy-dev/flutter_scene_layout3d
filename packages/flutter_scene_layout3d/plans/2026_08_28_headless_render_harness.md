---
status: pending
created_at: 2026-08-28T22:40:00Z
updated_at: 2026-08-28T22:40:00Z
commit: 80f0d91
---

# A harness that proves a frame comes out

The suite is 716 tests and every one of them is arithmetic. That is the right
shape for a layout protocol — constraints and sizes are numbers, and numbers
are cheap to pin down — but it means the package has **no test that a laid-out
surface produces geometry at all**. `flutter test` has no GPU context, so it
cannot have one.

This matters more here than it would in most packages, because
[the readiness overview](2026_08_25_material3d_readiness_overview.md) closed
with the package deliberately drawing almost nothing: the decoration painter
and the glyph atlas are seams. The moment either is implemented, the only thing
standing between a regression and a release is a person running the gallery and
looking at it.

## What was lost in the move

Five scenes lived in `examples/smoke_render` in the engine monorepo this
package grew up in, and did not move with it:

- `layout3d_panel` and `layout3d_ground` — the two bases.
- `layout3d_wrap_grid`, `layout3d_slivers`, `layout3d_intrinsic`.

They render a laid-out surface headlessly and assert a sane frame, so a layout
that stops producing geometry fails in CI. They are roughly 480 lines, and they
are worth reading before rewriting: they are in the fork's
`examples/smoke_render/lib/smoke_scenes.dart`, from `SmokeScene('layout3d_panel'`
onward.

They were not ported with the package because the *harness* is the hard part,
not the scenes. It needs committed platform scaffolding, an `integration_test`
driver, native-asset hooks and a device or a software rasterizer in CI — an
example app's worth of infrastructure, which is why this is its own plan rather
than a line in the migration.

## The work

- [ ] **Phase 1 — the harness.** An `examples/render_smoke` app that commits
      its platform scaffolding (unlike the gallery, which deliberately does
      not), boots the engine, renders one named scene to an offscreen target
      and exits with a status. Decide early whether this drives through
      `integration_test` or a plain `flutter drive`; the engine's harness uses
      the former.
- [ ] **Phase 2 — a frame assertion worth making.** "A sane frame" needs a
      definition. At minimum: not blank, not NaN, and stable between runs.
      Prefer a cheap perceptual hash over a golden image — goldens across
      backends and driver versions are a maintenance tax this project cannot
      pay yet.
- [ ] **Phase 3 — the five scenes**, rewritten against the current API. They
      were written before metrics, decoration, text, overlays and animation
      landed, so they will not port verbatim.
- [ ] **Phase 4 — the seams that have no coverage at all.** Once a frame can be
      asserted, the two things worth pointing it at are the ones no unit test
      can reach: a `BoxDecoration3d` with a painter attached (does the shipped
      `assets/box_decoration3d.fmat` compile, and does a rounded panel actually
      come out rounded?) and, when it exists, a text renderer.
- [ ] **Phase 5 — CI.** A macOS runner with a GPU is the straightforward path;
      settle whether a software backend is good enough before assuming it is.

## What to watch

- **The shader has never been compiled by anything in either repository.** No
  lane runs `impellerc` over `box_decoration3d.fmat`. Today a unit test parses
  it and checks that every parameter the Dart side writes is declared, which
  catches the silent failure but not a syntax error. Phase 4 is the first time
  anything would find out whether it builds.
- **Do not let the harness become a golden-image suite by accident.** The
  question this answers is "did a frame come out, and does it have the right
  shape", not "is this pixel that colour". The second question needs a stable
  backend matrix, and the project does not have one.
