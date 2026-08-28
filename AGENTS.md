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
| `examples/layout3d_gallery` | The example app. Three surfaces — an upright panel, a ground plane, a scrolling list — all hit-testable. |

`flutter_scene_material3d`, a Material catalogue (`Button3d`, `Card3d`,
`Scaffold3d`, `AppBar3d`) built as real geometry on this protocol, is the
reason the package exists and will live here as a second package when it
starts.

## Running things

Everything below runs from the repository root unless stated otherwise.

```sh
flutter pub get                                   # resolves the workspace
cd packages/flutter_scene_layout3d && flutter test # the suite
dart analyze                                      # must be clean, everywhere
dart format .                                     # before every commit
```

The example app commits no platform scaffolding, so generate the platform you
want first:

```sh
cd examples/layout3d_gallery
flutter create . --platforms=macos
flutter run -d macos --enable-flutter-gpu
```

## The engine rules that are expensive to get wrong

`flutter_scene` diverges from three.js, Godot and Unity in specific ways, and
most first-attempt failures come from reaching for another engine's spelling.

- **Not `package:vector_math/vector_math_64.dart`.** Use
  `package:vector_math/vector_math.dart`. The `_64` `Vector3` is a different,
  incompatible type.
- **Not `--enable-impeller`, not `--enable-experiment=native-assets`.** The run
  flag is `--enable-flutter-gpu` alone.
- **Not the master channel.** Flutter 3.47 stable or newer; master resolves
  worse, not better.
- **Not `node.position.set(...)`.** `Node` has `position`, `rotation` (a
  `Quaternion`) and `scale`, but they are whole-value get/set
  (`node.position = Vector3(0, 1, 0)`); the getters return copies. For a raw
  matrix edit use `node.mutateLocalTransform((m) => ...)`.
- **Not `Node.fromAsset(...)`.** Load a preprocessed model with
  `loadScene('assets/x.glb')`, or a runtime glTF with `Node.fromGlbAsset`.
- Rendering is gated on `Scene.initializeStaticResources()`. Until it resolves
  the engine prints "Flutter Scene is not ready to render. Skipping frame", so
  build geometry and materials only after it does.

For depth, the engine ships agent skills; install them into a checkout with
`dart run flutter_scene:skills`.

## The traps in this package

These cost real time and are not obvious from the code.

- **Writing `Layout3dSurface.metrics` relayouts the whole subtree, by design.**
  It belongs to a window resize, never to a per-frame path.
- **Animation must stay off the relayout path.** Three tiers, cheapest first:
  repaint-only (`DecoratedBox3d.decoration` and `.stateLayer` — shader
  uniforms, no layout), node-only (`nodeOffset` / `nodeTransform` — one matrix
  a frame), and implicit, only when a size really changed. Never put a new
  `Text3d.text`, a new `NodeBox3d.content` or a rebuilt mesh on a per-frame
  path. `test/animation_test.dart` asserts `debugTextParagraphCount` does not
  move while a container resizes a label; that test fails first if measurement
  gets back onto the layout path.
- **There are four transform channels** — `ParentData3d.sceneOffset`,
  `nodeOffset`, `nodeTransform` and `localTransform` — and they are not
  interchangeable. `Stack3d.depthStep` rewrites `sceneOffset` on every
  placement, so an animation stored there is silently erased. Use `nodeOffset`.
- **The package draws almost nothing by default.**
  `BoxDecoration3d.painterFactory` is null until something sets it, and
  `Text3dRenderer` has no in-tree implementation. Both are deliberate seams
  with real geometry behind them; neither can be verified in `flutter test`,
  which has no GPU context.
- **`TapTarget3d` grows the ray region but not the box.** The Material 48dp
  minimum is invisible to layout, to intrinsics, to `ensureVisible3d` and to
  semantics. Deliberate — it keeps neighbours from moving — but sharp.
- **A `Text3d` answers hit tests on its own account**, so a label inside a
  button usually wants an `IgnorePointer3d`.
- **A corner radius is not a clip.** `Clip3dRegion` is an intersection of
  planes and a plane region is convex; a radius is carved by the panel shader.

## Conventions

### Implementation plans live in `plans/`

Any piece of work worth planning before writing gets a plan file under the
`plans/` directory **of the package it belongs to**
(`packages/flutter_scene_layout3d/plans/`). Create the directory if it is not
there yet.

Name the file `YYYY_MM_DD_plan_title.md`, dated the day the plan is written,
with a lowercase snake_case title that says what the work is.

Every plan opens with YAML front matter:

```yaml
---
status: pending          # pending | in progress | completed | blocked
reason: ...              # only when blocked or in progress: what is left, briefly
created_at: 2026-08-25T03:32:15Z   # ISO 8601
updated_at: 2026-08-25T03:32:15Z   # ISO 8601
commit: 495b1ec4e93e3588c93612ef02862355d380933a   # HEAD when the plan was written
---
```

The `commit` field is the commit the plan was written against, so a later
reader can tell what the codebase looked like when it was reasoned about; it
does not change as the plan is worked.

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

What cannot be covered headlessly is anything needing a GPU context. Say so
explicitly rather than leaving a gap unmarked.

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
