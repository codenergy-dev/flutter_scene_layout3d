---
status: completed
created_at: 2026-08-28T23:20:00Z
updated_at: 2026-08-29T02:40:00Z
commit: 3f1bd45cc0b06131a50ab145917648f9164d8f57
---

# Tests that actually draw, and let the layout say where to look

The suite is 716 tests and every one of them is arithmetic. That is the right
shape for a layout protocol — constraints and sizes are numbers, and numbers
are cheap to pin down — but it means the package has **no test that a laid-out
surface produces geometry at all**. `flutter test` has no Flutter GPU context,
so it cannot have one.

This matters more here than in most packages, because
[the readiness overview](2026_08_25_material3d_readiness_overview.md) closed
with the package deliberately drawing almost nothing: the decoration painter
and the glyph atlas are seams with no in-tree implementation. Two of the three
plans still open are open for exactly this reason and no other —
[text](2026_08_25_text_in_a_3d_layout.md) phase 4 and
[size-driven geometry](2026_08_25_size_driven_geometry.md)'s shader check both
say, in their own words, that this repository cannot run them. **This plan is
what unblocks them.** It is worth doing before either.

## The idea worth having

The engine's own smoke harness, in the monorepo this package grew up in, asks
one question of a frame: *did something sane draw?* Corners clear, centre
covered, foreground not black, more than a handful of distinct colours. It is
reference-free, which is why it survives across backends where golden images
would not.

That is a good floor and it is not what a layout package should settle for.
We can ask a much sharper question, because **we know where every box ended
up**. Layout computed it. So:

> Project a box's world position to a pixel, and assert the frame has geometry
> at *that* pixel — and clear space where layout says there is none.

That turns a render test from "something drew" into "the `Row3d` put the three
cubes side by side, and the frame agrees". It is a genuine end-to-end check of
the protocol, the basis, the metrics, the camera binding and the engine at
once, and it fails loudly on the class of bug no unit test can see: layout is
right, and the picture is still wrong.

Both halves already exist and neither has to be invented:

- `Layout3d.worldTransform` gives a box's placement in world space.
- `Camera.worldToScreen(Vector3, Size)` — shipped by `flutter_scene` — gives
  the pixel, or null behind the camera.

Compose them and the layout tree becomes the test's oracle.

## How a frame gets captured

The mechanism is settled and known to work; the engine's harness uses it.

```
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/render_test.dart \
  -d macos --enable-flutter-gpu
```

Inside, with `IntegrationTestWidgetsFlutterBinding`: pump a plain frame first,
`await Scene.initializeStaticResources()`, then pump the scene inside a
`RepaintBoundary` with a known key, settle for a fixed number of frames, and
`boundary.toImage(pixelRatio: 1.0)` → `toByteData(rawRgba)`. From there it is
pixels in a byte buffer.

Two traps worth carrying over from the engine's harness, which learned them the
hard way: render one ordinary Flutter frame *before* touching `flutter_scene`
(some backends race GPU context setup otherwise), and give the scene real
settling time rather than a single pump.

## The work

- [x] **Phase 1 — the app.** `examples/render_probe`, committing its platform
      scaffolding (unlike `layout3d_gallery`, which deliberately does not).
      A `RenderProbeScene` type — an id, a scene builder, a camera, and the
      surface it built — plus a widget that hosts one inside a keyed
      `RepaintBoundary`. Nothing clever; the value is all in phase 2.
- [x] **Phase 2 — the probe harness**, and the reason this plan exists.
      A `FrameProbe` over the captured RGBA: `coverageAt(Offset, radius)`,
      `isClearAt`, `meanLumaIn(Rect)`, `distinctColorsIn(Rect)`. Then the
      layout-aware layer on top: given a `Layout3d` and the camera, resolve its
      centre and its corners to pixels and assert coverage there. Get the
      helper right and every later scene is five lines.
- [x] **Phase 3 — the floor.** Reference-free sanity for every scene, the
      engine's four checks: corners clear, centre coverage above a threshold,
      foreground luma not ~black, more than a handful of distinct colours.
      These catch "nothing drew" and "unlit", and they cost nothing to keep.
- [x] **Phase 4 — the layout scenes**, with primitives only: cuboids, spheres,
      cylinders through `NodeBox3d`. One per claim the protocol makes.
      - `row_of_cubes` — three cubes in a `Row3d`; three separated clusters,
        in left-to-right order, with clear gaps between them.
      - `column_spacing` — `spacing` shows up as clear bands of the right size.
      - `basis_xy_vs_xz` — the same tree on both bases; on `xz` the far row
        projects *higher and smaller* on screen. This is the one that proves
        the basis is real and not a relabelling.
      - `stack_depth` — `Stack3d` depth ordering: the front child occludes the
        back one at the overlapping pixel.
      - `alignment_and_padding` — a padded, aligned child lands where
        `worldToScreen` says, within a pixel tolerance.
      - `intrinsic_sizing` — a `NodeBox3d` around a sphere measures the sphere,
        so the row's width tracks the geometry rather than a guess.
      - `list_scroll` — a `ListView3d` scrolled by a known offset moves the
        visible items by the projected equivalent.
      - `clip_plane` — a child half outside a `ClipBox3d` is cut, and the cut
        edge is where the plane says.
- [x] **Phase 5 — the seams that no unit test can reach.** The point of the
      whole exercise.
      - **Does `assets/box_decoration3d.fmat` compile?** Nothing in either
        repository has ever run `impellerc` over it. A unit test parses it and
        checks that every parameter the Dart side writes is declared, which
        catches a silent mismatch but not a syntax error. This is the first
        time anything would find out.
      - **Does a rounded panel come out rounded?** Probe the corner: inside the
        radius is clear, inside the body is not.
      - Elevation, borders and the state layer, once the painter is attached.
      - A text renderer, when one exists.
- [x] **Phase 6 — CI.** A macOS runner with a GPU is the straightforward path.
      Settle whether a software backend is good enough before assuming it is;
      the engine's harness keeps its thresholds deliberately loose because
      software rasterizers produce far fewer distinct colours than hardware.
      Until CI runs it, say so in the README rather than implying coverage.

## What to watch

- **Do not let this become a golden-image suite.** The question is "is the
  geometry where layout put it", not "is this pixel that colour". Goldens
  across backends and driver versions are a maintenance tax this project
  cannot pay, and they fail for reasons that have nothing to do with the
  package.
- **Tolerances are part of the design, not an afterthought.** Anti-aliasing,
  perspective and a sphere's silhouette all mean a projected centre is
  approximate. Probe a small disc and assert a *fraction* covered, never a
  single pixel's value.
- **A scene that needs an asset is a scene that can break for the wrong
  reason.** Primitives only, generated in code. `GeometryBuilder` and the ten
  built-in geometries are enough for everything phase 4 asks for.
- **Keep the scenes deterministic.** No time-dependent animation in a probe
  scene unless the test drives the clock; a fling settling on its own schedule
  is a flake waiting to happen.
- The five scenes the engine's harness had for this package (`layout3d_panel`,
  `layout3d_ground`, `layout3d_wrap_grid`, `layout3d_slivers`,
  `layout3d_intrinsic`) are worth reading before writing phase 4 — they are in
  the fork at `examples/smoke_render/lib/smoke_scenes.dart`, from
  `SmokeScene('layout3d_panel'` onward. They predate metrics, decoration, text,
  overlays and animation, so they will not port verbatim, and they only ever
  asked the floor question. Take the scene setup, not the assertions.


## What happened

All six phases landed. `examples/render_probe` runs twenty render tests on a
Metal GPU through `flutter drive`, and they pass.

The split turned out better than the plan drew it. **The projection went into
the package, not the harness** — `Layout3dScreenProjection` in
`lib/src/debug/screen_projection.dart`, giving every `Layout3d` a
`screenCenter`, `screenPointOf` and `screenBounds`. It is layout arithmetic
rather than test infrastructure, it needs no GPU, and putting it there means
twelve headless tests pin it down *and* `flutter_scene_material3d` inherits it
for free, along with anything wanting a debug overlay or an editor selection
rectangle. `FrameProbe` stayed in the app, where the pixels are.

**The shader compiles.** That was the plan's largest open question and the
answer is yes: the app's `hook/build.dart` runs `buildMaterials` over
`assets/box_decoration3d.fmat` — reached by a symlink, so it is the shipped
file and not a copy that could drift — and `impellerc` produces a bundle with
a `BoxDecoration3d` entry and its full parameter sidecar. Then it draws: a
panel with a 60dp radius reads empty at 1%, 2% and 4% of the way in along its
corner diagonal and solid from 8%, while the square control is solid from 4%.
The SDF is real.

## What the plan got wrong, and what the first runs taught

- **`NodeBox3d` defaults to `BoxFit3d.none`**, so content keeps its own size
  inside whatever slot layout gave it. A box's screen bounds then enclose
  empty space, and a probe aimed at the box's edge finds nothing. Every probe
  scene uses `BoxFit3d.contain`, which is what makes "where the box is" and
  "where the geometry is" the same question — the premise the harness rests
  on. This is written at the top of `probe_scenes.dart`.
- **`screenBounds` bounds all eight corners, including the depth extrusion**,
  so on a slab with any depth its corners sit outside the front face. Probing
  a *face* wants `screenPointOf` with an explicit z fraction. Two tests were
  written against bounds, failed, and were rewritten; the dartdoc now says so.
- **The plan wanted a distinct-colour floor of eight.** A single flat-shaded
  lit cube on a flat clear yields five. The bar is three, and it is a backstop
  against a uniform fill and nothing more — coverage and luma are the real
  blank detectors.
- **A level camera cannot see a ground plane.** `xz` seen from y=0 is exactly
  edge-on: every point lands on the horizon and near is indistinguishable from
  far. The ground scene needs a raised camera. The same mistake was made first
  in a headless projection test, which is where it was cheapest to find.
- **A corner assertion needs a control.** "The rounded panel's corner is
  empty" could equally mean the panel never drew. The test draws a square
  panel too and compares, which also removes the need for an absolute
  threshold on a probe that straddles an edge.
- **An item scrolled out of a viewport is not off the view** — the view is
  larger than the surface. The first scroll test asked "is it inside the
  frame", which is the wrong question; the right one is whether the viewport
  still draws it.
- **`BoxFit3d.contain` scales uniformly, to the smallest bounded axis.** A
  cube in a 1.6 x 1.6 x 0.1 slot comes out a 0.1 cube: a speck. Thin slabs
  want `fill`, which scales each axis on its own. Every other scene wants
  `contain`, which keeps a sphere spherical. The stack scene needed three
  attempts, and this was the third.
- **`Stack3d.depthStep` does not separate children thicker than the step.** A
  1.6-deep slab centred on the plane reaches further toward the viewer than a
  0.8-deep child stepped 0.35, so the back child wins the depth test and the
  stack looks inverted. The first version of that scene passed once, on
  z-fighting, and failed on the next run — which is how it was found.

Two documentation bugs fell out, both fixed:

- Both READMEs and the basis diagram said "down" on the ground plane runs
  *away* from the camera. It walks *toward* the viewer — `xz` maps layout y to
  scene `+z` — and `LayoutBasis3d.xz`'s own dartdoc had it right all along.
- `BoxDecoration3d.painterFactory`'s dartdoc showed
  `createMaterial: material.clone`, which does not compile:
  `PreprocessedMaterial` has no `clone`. The painter's own dartdoc, two files
  over, had the correct `() => material`.

And one trap that is not a bug but cost an hour: **a panel's size is in world
units and its corner radius is in logical pixels.** `BorderRadius3d.circular(0.6)`
asks for 0.6dp, which at the default rate is 0.006 world units and renders as
an indistinguishably square corner. The scene wants `circular(60)`. This is
documented and deliberate — a Material shape token is written in dp — but the
two units sitting side by side in one constructor is sharp.

## Still open

- **Only macOS is covered.** The CI lane pins `macos-14` because Flutter GPU
  wants a real GPU there; whether a software backend suffices has not been
  tried, and the thresholds would likely need loosening if it does.
- **Elevation, borders and the state layer have no probe yet.** The painter
  draws them and the shader declares them; nothing looks.
- **No text.** There is still no glyph atlas to point a probe at. When
  `2026_08_25_text_in_a_3d_layout.md` phase 4 lands, this is the lane that
  verifies it, and a label's projected baseline is the obvious thing to probe.
