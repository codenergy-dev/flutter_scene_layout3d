# Working in this repository

This repository is **flutter_scene_layout3d**: Flutter's box layout protocol,
in three dimensions, over the [flutter_scene](https://github.com/bdero/flutter_scene)
realtime 3D engine. Constraints go down, sizes come up, the parent positions
the child — arranged on a freely transformable plane in a real 3D scene.

This file orients coding agents, and the people directing them. It is about
**how work is done here** — the process, the contracts, and what "done" means.
What the packages *are*, and where they bite, is in `docs/` and in the package
READMEs; what has *happened* is in the changelogs and the plans. Read this
before working here, and put any new agent instruction in this file rather
than scattering it.

## What this repository is, and is not

It is a **consumer** of `flutter_scene`, not a fork of it. The engine is a pub
dependency like any other. Work here never edits the engine; if something is
genuinely missing from `flutter_scene`, the answer is either to work around it
on this side or to open an issue upstream, and to write down which.

The package began inside a fork of the engine's own monorepo and was moved out
once it became clear the scope was its own project. That history is preserved:
`git log` reaches back to the first layout commit.

## Why this file differs from the engine's

`flutter_scene`'s own agent instructions take the position that documentation
is for people *using* the package, not for people developing it. That is a
good position for a repository where an agent is an occasional tool. It is the
wrong one here, and the divergence is deliberate rather than drift — **do not
"correct" this file back toward it.**

The reason is the working method. Work here goes plan → agent → reviewed by a
person who is following along, and the thing that prevents a deviation costing
a day is a written contract for the process: what a plan is, what verification
means, what has to be true before a change is called finished. So this file is
the process contract, and it earns its length by being *only* that.

Three places, three questions, and keeping them apart is what stops any of
them rotting:

| Where | The question it answers |
| --- | --- |
| this file | how work is done here |
| [docs/](docs/) and the package READMEs | how the packages are used, and where they bite |
| `CHANGELOG.md` and `plans/` | what happened, and why it was done that way |

That separation was learned the hard way. This file once carried a
phase-by-phase narrative of everything that had shipped — 185 lines of it,
half the file — while the changelogs it belonged in stayed empty for nine
commits. The discipline was real and pointed at the wrong target. **History
goes in the changelog and the plans. This file stays a contract.**

## The packages

| Package | What it is |
| --- | --- |
| `packages/flutter_scene_layout3d` | The layout protocol. Constraints, intrinsics, baselines, flex, stack, wrap, reading direction, slivers, scrolling, text measurement and geometry, decoration with pictures and gradients, clipping, pointer dispatch, wheel and trackpad scrolling, focus and key bindings, overlays, animation, diagnostics, the unit contract and the screen a surface stands in for — and `testing.dart`, the library an application tests its screens with. |
| `packages/flutter_scene_material3d` | Material Design 3 on that protocol: seven token families, a theme both layers read, and the catalogue over one `Material3d` primitive — buttons, cards, rows, chips, the structure, the overlays that arrive rather than appear, the selection controls and the press ripple. |
| `examples/layout3d_gallery` | The example app, and the only place a person sees any of this drawn. A Material screen on an upright panel that turns — with a gradient header, a circular avatar on every row, and an overflow menu that opens a dialog and a sheet so that an arrival has somewhere to be looked at — the same catalogue flat on the ground, and a scrolling list of raw meshes beside them: all hit-testable, through one `SceneInput3d` around the view. |
| `examples/render_probe` | Render tests. Draws the layout on a GPU and probes the frame at the pixels layout says to check, and photographs the gallery. Commits its platform scaffolding, unlike the gallery. |

`flutter_scene_material3d` is the reason the layout package exists: a Material
catalogue built as real geometry rather than as a picture of it. It is
[planned in full](packages/flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md),
all ten phases of it are `completed`, and that plan's closing sections — what
the whole thing proved, what its reasoning got wrong, and what each phase
deliberately left out — are the thing to read before extending any of it.

**What is being built next**, and the map of the plans that get there, is
[what a real application still needs](packages/flutter_scene_layout3d/plans/2026_09_11_what_a_real_application_still_needs.md).
Start there rather than here when you want the shape of the remaining work.

## Running things

Everything below runs from the repository root unless stated otherwise.

```sh
flutter pub get                                      # resolves the workspace
cd packages/flutter_scene_layout3d && flutter test   # 1256 today
cd packages/flutter_scene_material3d && flutter test # 569 today
cd examples/layout3d_gallery && flutter test         # 5 today
dart analyze                                         # must be clean, everywhere
dart format .                                        # before every commit
```

All three suites are headless, all three must be green, and CI runs all
three. The Material
package's is arithmetic and state — tokens, `lerp`, and the theme reaching a
box's `performLayout` — so nothing in it needs a GPU. The counts are there as
a drift alarm: a green suite that is suddenly four hundred tests shorter is a
signal. Update them when they move.

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
frame*. That lane is also the only thing that *runs* the compiled shaders in
`packages/flutter_scene_layout3d/assets/`. The package's own `hook/build.dart`
compiles them — for the render probe, the gallery, and any application that
depends on the package — so a syntax error in the panel shader fails every
build, while a shader that compiles and draws the wrong thing fails there and
nowhere else.

The example app commits no platform scaffolding, so generate the platform you
want first:

```sh
cd examples/layout3d_gallery
flutter create . --platforms=macos
flutter run -d macos --enable-flutter-gpu
```

**And then look at it.** This is a third verification lane and not a nicety.
Ten of the worst defects ever found here were invisible to the headless suites
and the render probes alike, and every one was found by a person starting the
gallery and looking at the window: a screen nothing could press, a screen one
logical pixel deep, a frame that would not build with semantics on, every
panel drawn from its back face, a label sunk into the slab it belongs to. A
probe answers *is this one claim true*; running the app answers *is anything
obviously wrong*, and in this stack those are different questions. **Turning
something is a question of its own**, and nothing here had asked it until a
person watched a panel rotate.

When the window itself cannot be looked at — from a shell, from CI — the
render probe app photographs the gallery, twice, a few seconds apart so the
panel has turned:

```sh
cd examples/render_probe
flutter drive --driver=test_driver/photograph.dart \
  --target=integration_test/photograph_test.dart -d macos --enable-flutter-gpu
```

The PNGs are in `build/photographs/`. **Open them.** The test asserts that a
frame came out and nothing else; the looking is the lane, and CI keeps the
pictures from every run for that reason. Headless tests of a *screen* — can
this be pressed, is this label hidden inside its card — are written with
`package:flutter_scene_layout3d/testing.dart`, and the gallery's
`test/screens_test.dart` is the example.

## What you need to know before writing code

Both of these are short, and both are lists of things that cost real time.
They live in `docs/` rather than here because they grow, and because they
answer a different question than this file does.

- **[docs/traps.md](docs/traps.md)** — the sharp edges of *these packages*.
  A box's size is in world units while a Material figure is in logical pixels;
  writing `metrics` relayouts everything; there are four transform channels and
  a `Stack3d` silently erases one of them; the package draws almost nothing
  until you install a painter; a corner radius is not a clip; the depth axis is
  not symmetric with the other two, because the viewer is on one side of it.
  **Read it before building a component.** Do not summarize it here — it has
  been tried, and the summary rotted while the page stayed right.
- **[docs/engine-rules.md](docs/engine-rules.md)** — using `flutter_scene`
  correctly. `vector_math` not `vector_math_64`, `--enable-flutter-gpu` alone,
  `node.position` getters return copies, and nothing renders until
  `Scene.initializeStaticResources()` resolves.

[docs/README.md](docs/README.md) maps everything else — which document answers
which question, and where the reasoning behind past decisions is recorded.

## Before you call it done

Every one of these, every time. They are not a summary of the conventions
below; they are the conventions reduced to the things that can be checked, and
the list exists because the ones that were only described in prose are the
ones that got skipped.

1. **`flutter test` is green** in both packages and in the gallery.
2. **`dart analyze` is clean** across the whole workspace.
3. **`dart format .`** has been run.
4. **The changed package's `CHANGELOG.md` has its entry**, in this commit.
5. **The page that describes the changed behaviour changed too**, in this
   commit — a README, a dartdoc, a `docs/` page.
6. **The plan's `status` and `updated_at` moved**, what the original reasoning
   got wrong is written down, and the `reason:` of every plan it mentions has
   been reread.
7. **The indexes that track state were checked**:
   [docs/README.md](docs/README.md) and the
   [plan index](packages/flutter_scene_layout3d/plans/2026_09_11_what_a_real_application_still_needs.md).
   An index pointing at finished work as "next" is the failure mode here.
8. **A commit message is proposed, and nothing is committed** unless the user
   asked.

If something on this list cannot be satisfied, say which and why in the
round's summary. An unsatisfied item reported is fine; an unsatisfied item
unmentioned is what makes the next reader trust something false.

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

**Closing a plan can invalidate another one.** The render-coverage work made
three statements in other plans false: they still said the work was blocked on
infrastructure that now existed. Nothing warns you.

### Tests are the verification, and there is room to be thorough here

`flutter test` green and `dart analyze` clean, both, every time, no
exceptions. This repository is not bound by the engine's test conventions, so
cover the edge cases properly: the protocol is arithmetic, and arithmetic is
cheap to pin down.

The split between the lanes is the one *Running things* describes, and the
rule the render harness earned is worth restating: **the laid-out tree is the
oracle.** Ask `screenCenter` or `screenPointOf` where a box is, never a
hard-coded pixel — and a scene that cannot honestly assert its claim is
removed, not weakened.

### Versions and the changelog

**Every change a consumer of the package would notice gets a `CHANGELOG.md`
entry, in the package that changed, in the same commit.** New API, changed
behaviour, a fixed defect, a new asset, a deprecation. What does not need one:
a plan, a documentation-only change, an internal refactor with no visible
effect, a test.

Entries here are prose in the same voice as everything else — a bold lead-in
naming the thing, then what it is for and why it is that way. Not "Added
`Foo3d`". The existing entries are the model; match them.

Accumulate under `## Unreleased`. **Do not bump a version or cut a release
heading** — that is the user's call, and it is tied to a publishing decision
that has not been made yet.

This convention exists because it was absent and the cost was visible. The
habit held for the first weeks and then died the moment the catalogue phases
began: nine commits of shipped work — the whole catalogue from the buttons to
the gallery, the clip tier, the overlays and anchoring, the ripple, the glyph
walls — went unrecorded, so the Material package's own changelog still
described it as "the token layer, and the buttons are the next phase" after
all nine had landed. A changelog is the first thing a consumer of these
packages reads.

### Documentation is part of the change, not follow-up work

Prose lives next to what it describes, and [docs/](docs/) holds what has no
such home — cross-cutting traps, engine rules, the map. When you change
behaviour, the page that describes it changes in the same commit; when you add
a page, it gets a row in [docs/README.md](docs/README.md).

Two rules under that:

- **A page that is wrong is worse than a page that is missing**, because the
  next reader trusts it. If you find one describing behaviour the code no
  longer has, fix it or say so; do not leave it. This applies hardest to the
  rows in an index that claim to say what is current.
- **Verify before you write it down.** Grep for the symbol before naming it,
  read the file before describing it, run the suite before quoting a count.
  The prose here is confident by house style, which means an unchecked claim
  reads exactly like a checked one — and this repository's own documentation
  drift was found by grepping, not by reading.

### Suggest a commit message each round

At the end of every round of work, propose a commit message for what changed
and let the user commit. Do not commit or push unless asked. If nothing
changed — a review, a question answered — say so instead of inventing a
message.

Subject lines here are short, imperative and say what the change does for the
reader, not which files moved: "Pin a header to the leading edge and cut the
content under it", not "Add SliverPersistentHeader3d".

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
