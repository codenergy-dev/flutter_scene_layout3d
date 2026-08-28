---
status: pending
created_at: 2026-08-28T23:20:00Z
updated_at: 2026-08-28T23:20:00Z
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

- [ ] **Phase 1 — the app.** `examples/render_probe`, committing its platform
      scaffolding (unlike `layout3d_gallery`, which deliberately does not).
      A `RenderProbeScene` type — an id, a scene builder, a camera, and the
      surface it built — plus a widget that hosts one inside a keyed
      `RepaintBoundary`. Nothing clever; the value is all in phase 2.
- [ ] **Phase 2 — the probe harness**, and the reason this plan exists.
      A `FrameProbe` over the captured RGBA: `coverageAt(Offset, radius)`,
      `isClearAt`, `meanLumaIn(Rect)`, `distinctColorsIn(Rect)`. Then the
      layout-aware layer on top: given a `Layout3d` and the camera, resolve its
      centre and its corners to pixels and assert coverage there. Get the
      helper right and every later scene is five lines.
- [ ] **Phase 3 — the floor.** Reference-free sanity for every scene, the
      engine's four checks: corners clear, centre coverage above a threshold,
      foreground luma not ~black, more than a handful of distinct colours.
      These catch "nothing drew" and "unlit", and they cost nothing to keep.
- [ ] **Phase 4 — the layout scenes**, with primitives only: cuboids, spheres,
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
- [ ] **Phase 5 — the seams that no unit test can reach.** The point of the
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
- [ ] **Phase 6 — CI.** A macOS runner with a GPU is the straightforward path.
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
