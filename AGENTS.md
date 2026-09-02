# Working in this repository

This repository is **flutter_scene_layout3d**: Flutter's box layout protocol,
in three dimensions, over the [flutter_scene](https://github.com/bdero/flutter_scene)
realtime 3D engine. Constraints go down, sizes come up, the parent positions
the child — arranged on a freely transformable plane in a real 3D scene.

This file orients coding agents, and the people directing them. Read it before
working here.

## What this repository is, and is not

It is a **consumer** of `flutter_scene`, not a fork of it. The engine is a pub
dependency like any other. Work here never edits the engine; if something is
genuinely missing from `flutter_scene`, the answer is either to work around it
on this side or to open an issue upstream, and to write down which.

The package began inside a fork of the engine's own monorepo and was moved out
once it became clear the scope was its own project. That history is preserved:
`git log` reaches back to the first layout commit.

## The packages

| Package | What it is |
| --- | --- |
| `packages/flutter_scene_layout3d` | The layout protocol. Constraints, intrinsics, baselines, flex, stack, wrap, slivers, scrolling, text measurement, decoration, clipping, pointer dispatch, focus, overlays, animation, diagnostics. |
| `packages/flutter_scene_material3d` | Material Design 3 on that protocol. Today: the token families (`ColorScheme3d`, `Typography3d`, `ShapeScale3d`, `Elevation3d`, `Thickness3d`), `Theme3dData`, `SceneTheme3d` and `Theme3d.of`. The catalogue itself is next. |
| `examples/layout3d_gallery` | The example app. Three surfaces — an upright panel, a ground plane, a scrolling list — all hit-testable. |
| `examples/render_probe` | Render tests. Draws the layout on a GPU and probes the frame at the pixels layout says to check. Commits its platform scaffolding, unlike the gallery. |

`flutter_scene_material3d` is the reason the layout package exists: a Material
catalogue (`Button3d`, `Card3d`, `Scaffold3d`, `AppBar3d`) built as real
geometry rather than as a picture of it. It is
[planned in full](packages/flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md)
and partly written. Phase 0 — four additions to `flutter_scene_layout3d` that
a first component could not do without — landed in the layout package under
[its own plan](packages/flutter_scene_layout3d/plans/2026_09_01_the_four_things_before_a_component.md).
Phase 1, the package and its tokens, is done, and the one gap it left in the
layout package — a `build` method that could not read the unit contract, so a
dp padding could not be written — is closed under
[its own plan](packages/flutter_scene_layout3d/plans/2026_09_02_the_metrics_a_build_method_can_read.md)
there. **There is no `Material3d`, `InkWell3d` or `Icon3d` yet**, and nothing in the catalogue; phase 2 is where
they start, and the icon question in particular is to be settled with a render
probe rather than guessed at.

## Running things

Everything below runs from the repository root unless stated otherwise.

```sh
flutter pub get                                    # resolves the workspace
cd packages/flutter_scene_layout3d && flutter test  # the layout suite
cd packages/flutter_scene_material3d && flutter test # the Material suite
dart analyze                                       # must be clean, everywhere
dart format .                                      # before every commit
```

Both suites are headless, and both must be green. The Material package's is
arithmetic and state — tokens, `lerp`, and the theme reaching a box's
`performLayout` — so nothing in it needs a GPU.

The example app commits no platform scaffolding, so generate the platform you
want first:

```sh
cd examples/layout3d_gallery
flutter create . --platforms=macos
flutter run -d macos --enable-flutter-gpu
```

## What you need to know before writing code

Both of these are short, and both are lists of things that cost real time.
They live in `docs/` rather than here because they grow, and this file should
stay readable end to end.

- **[docs/traps.md](docs/traps.md)** — the sharp edges of *this package*.
  A box's size is in world units while a Material figure is in logical pixels;
  writing `metrics` relayouts everything; there are four transform channels and
  a `Stack3d` silently erases one of them; the package draws almost nothing
  until you install a painter; a corner radius is not a clip. **Read it before
  building a component.**
- **[docs/engine-rules.md](docs/engine-rules.md)** — using `flutter_scene`
  correctly. `vector_math` not `vector_math_64`, `--enable-flutter-gpu` alone,
  `node.position` getters return copies, and nothing renders until
  `Scene.initializeStaticResources()` resolves.

[docs/README.md](docs/README.md) maps everything else — which document answers
which question, and where the reasoning behind past decisions is recorded.

## Conventions

### Implementation plans live in `plans/`

Any piece of work worth planning before writing gets a plan file under the
`plans/` directory **of the package it belongs to**
(`packages/flutter_scene_layout3d/plans/`,
`packages/flutter_scene_material3d/plans/`). Create the directory if it is not
there yet. A change to the layout protocol that the catalogue needs gets its
own plan in the layout package, not a line item in a Material plan — that is
what phase 0 did.

Name the file `YYYY_MM_DD_plan_title.md`, dated the day the plan is written,
with a lowercase snake_case title that says what the work is.

Every plan opens with YAML front matter:

```yaml
---
status: pending          # pending | in progress | completed | blocked
reason: ...              # only when blocked or in progress: what is left, briefly
created_at: 2026-08-25T03:32:15Z   # ISO 8601
updated_at: 2026-08-25T03:32:15Z   # ISO 8601
commit: af9e94128d3d9a9a41a2cc79688a29017f27a78a   # HEAD when the plan was written
---
```

The `commit` field is the commit the plan was written against, so a later
reader can tell what the codebase looked like when it was reasoned about; it
does not change as the plan is worked, with one exception already spent: the
plans that predate this package leaving the engine's monorepo had their
`commit` realigned onto the equivalent commit here, so every one of them
resolves.

**A plan is a living document.** Update it as you implement: move `status`
along, revise `updated_at` on every edit, tick items off, and write down what
turned out to be wrong about the original reasoning. A plan left at `pending`
after the work has shipped is worse than no plan, because the next reader
trusts it. **Never mark a plan `completed` while items are open** — if the
plan's own text defers something to a follow-up, that is out of scope rather
than an open item, and saying so in the body is what makes `completed` honest.

### Tests are the verification, and there is room to be thorough here

`flutter test` must be green and `dart analyze` clean before anything is
committed — both, every time, no exceptions. This repository is not bound by
the engine's test conventions, so cover the edge cases properly: the protocol
is arithmetic, and arithmetic is cheap to pin down.

What cannot be covered headlessly goes in `examples/render_probe`, which draws
real geometry and asks the frame whether it matches the layout:

```sh
cd examples/render_probe
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/render_test.dart -d macos --enable-flutter-gpu
```

How to write a scene is in
[examples/render_probe/README.md](examples/render_probe/README.md); the
gotchas are in [docs/traps.md](docs/traps.md), under *When probing a rendered
frame*.

That lane is also the only thing that *runs* the compiled
`packages/flutter_scene_layout3d/assets/box_decoration3d.fmat`. The package's
own `hook/build.dart` compiles it — for the render probe, the gallery, and any
application that depends on the package — so a syntax error in the panel
shader fails every build; a shader that compiles and draws the wrong thing
fails there and nowhere else.

### Suggest a commit message each round

At the end of every round of work, propose a commit message for what changed
and let the user commit. Do not commit or push unless asked. If nothing
changed — a review, a question answered — say so instead of inventing a
message.

Subject lines here are short, imperative and say what the change does for the
reader, not which files moved: "Pin a header to the leading edge and cut the
content under it", not "Add SliverPersistentHeader3d".

### Documentation is part of the change, not follow-up work

Prose lives next to what it describes, and [docs/](docs/) holds what has no
such home — cross-cutting traps, engine rules, the map. When you change
behaviour, the page that describes it changes in the same commit; when you add
a page, it gets a row in [docs/README.md](docs/README.md).

Two habits that this repository learned the hard way:

- **Closing a plan can invalidate another one.** The render-coverage work made
  three statements in other plans false — they still said the work was blocked
  on infrastructure that now existed. Nothing warns you. When you finish a
  plan, reread the `reason:` of every plan it mentions.
- **A page that is wrong is worse than a page that is missing**, because the
  next reader trusts it. If you find one describing behaviour the code no
  longer has, fix it or say so; do not leave it.

### README files are written for humans

Every `README.md` here is documentation a person reads, not a generated API
listing. That means:

- **Natural prose.** Explain the thing, in order, the way you would to a
  colleague. Not a wall of headings with one line under each.
- **Not exhaustive.** A README covers what a reader needs to get going and the
  handful of traps that cost real time. Everything else belongs in dartdoc on
  the API itself, where it is next to the code and cannot drift as easily.
- **Worked examples.** Show code that runs, in the order a caller writes it.
  Prefer one example that does something real over five fragments.
- **Didactic.** Say *why* a rule exists, not only what it is. A reader who
  understands the reason can extrapolate to the case you did not cover.
- **Faithful to what is actually implemented.** This is the hard requirement.
  Never document a feature that does not exist, a behaviour the code does not
  have, or a roadmap item as though it had landed. When you change behaviour,
  the README changes in the same pass.

The root `README.md` introduces the project and teaches the shape of it. The
package `README.md` is the deep reference. Keep the split.
