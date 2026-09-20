---
status: completed
created_at: 2026-09-20T18:40:00Z
updated_at: 2026-09-20T20:05:00Z
commit: 729413244220f9ce1b00f810ab5e8d4970abb134
---

# A scheme from one colour

`ColorScheme3d` carries all forty-six of Material 3's colour roles, pinned
against Flutter's own figures, in exactly two instances: a hand-written
`light` and a hand-written `dark`. There is no `fromSeed`, and **no real
application uses the Material baseline** — every one of them starts from a
brand colour. This plan is the generator, taken from
[what a real application still needs](../../flutter_scene_layout3d/plans/2026_09_11_what_a_real_application_still_needs.md#a-scheme-from-one-colour),
which files it as the narrow, deep item that is independent of everything
else on the map.

The catalogue plan put it out of its own scope with a promise attached — "a
generator can be added later without changing a single component" — and that
promise holds: nothing below touches a component, a token family other than
this one, or a shader. It adds one factory, one enum and one cache.

## What the map's entry got wrong, measured before anything was written

The entry proposes an oracle, and the oracle does not exist:

> The existing hand-written schemes become the test oracle — a generator
> seeded with Material's own baseline primary should reproduce them within
> tolerance, and if it does not, one of the two is wrong.

**It does not reproduce them, and neither of the two is wrong.** Flutter's own
`ColorScheme.fromSeed(seedColor: Color(0xFF6750A4))` was run against
`ThemeData(brightness: …).colorScheme` at this commit, role by role.
**Twenty-seven of the forty-six roles differ, in both brightnesses** — well
over half the scheme — and the largest of them are not rounding:

*(The first pass of this plan said "eight in light and nine in dark". That was
a count over the twelve roles the probe happened to sample, and the suite is
what corrected it. The figure is 27, and it is now a test.)*

| role | seeded | baseline |
| --- | --- | --- |
| `primary` (light) | `#65558F` | `#6750A4` |
| `error` (light) | `#BA1A1A` | `#B3261E` |
| `inversePrimary` (light) | `#CFBDFE` | `#D0BCFF` |
| `primary` (dark) | `#CFBDFE` | `#D0BCFF` |
| `error` (dark) | `#FFB4AB` | `#F2B8B5` |

Two separate reasons, both by design. The seed's own chroma is 47.9 and
`tonalSpot` clamps the primary palette to 36, so a scheme generated from
`#6750A4` is *quieter* than `#6750A4` — the seed is an input to the palette,
not a role of the result. And the error palette in a generated scheme is
`tonalSpot`'s fixed one rather than the baseline's error tokens, so `error`
diverges for every seed including this one.

So the hand-written tables stay exactly as they are. They are the Material
**baseline token set**, which is a published artefact in its own right, and
the existing drift test that pins them against `ThemeData(…).colorScheme`
keeps its job. **A `fromSeed` that reproduced them would be the bug.**

The real oracle is better than the one the entry proposed, and it was
available the whole time: **Flutter's own `ColorScheme.fromSeed`, role by
role, over many seeds, both brightnesses and several contrast levels.** The
suite already imports `package:flutter/material.dart` for exactly this kind of
comparison — the existing `color_scheme_test.dart` opens by saying
transcription is where errors hide — so this is the same lane, widened.

## The other thing the entry got wrong: this is not a package's worth of work

The entry says the work is "M3's tonal palettes: HCT, the tone stops, and the
role-to-tone mapping for light and dark", and the catalogue plan before it
called a generator "a package's worth of work". That was true when it was
written and it is the wrong conclusion here, because **the package already
exists in every Flutter application's dependency graph.**

`material_color_utilities` is what Flutter's `ColorScheme.fromSeed` is built
out of, and `package:flutter` depends on it directly — the SDK pins
`material_color_utilities: 0.13.0` in `packages/flutter/pubspec.yaml`, and it
resolves into this workspace today as a transitive dependency. Declaring it is
naming a package that is already there, not adding one.

The alternative was measured too: transcribing the reachable half of it —
`color_utils`, `math_utils`, `viewing_conditions`, `cam16`, `hct_solver`,
`hct`, `tonal_palette`, `contrast`, `dislike_analyzer`, `dynamic_color`,
`dynamic_scheme`, `material_dynamic_colors` and the nine scheme variants — is
**3,910 lines** of CAM16 colour science. That is a fork of a Google library
maintained to produce numbers this package would then have to keep matching,
and `AGENTS.md` is explicit that this repository is a consumer rather than a
fork. Owning three thousand nine hundred lines to arrive at the same integers
is the expensive way to be wrong later.

**Decision: depend on `material_color_utilities`, at the version the Flutter
SDK pins.** What this package writes is the part that is genuinely its own —
the role-to-field mapping into `ColorScheme3d`, the variant vocabulary, and
the memo. The cost is one constraint to bump when Flutter bumps its own, and
that is written into the pubspec beside the dependency so the next reader
finds it there rather than here.

It does not reach `lib/` for anything else: `material_color_utilities` is pure
Dart with no Flutter dependency, which matters because this package's `lib/`
deliberately does not import `package:flutter/material.dart` — two components
already carry a comment saying so. The variant enum is therefore ours rather
than Flutter's `DynamicSchemeVariant`, which lives in the Material library.

## What ships

### The factory

```dart
final scheme = ColorScheme3d.fromSeed(seedColor: const Color(0xFF00696E));
```

```dart
factory ColorScheme3d.fromSeed({
  required Color seedColor,
  Brightness brightness = Brightness.light,
  ColorSchemeVariant3d variant = ColorSchemeVariant3d.tonalSpot,
  double contrastLevel = 0.0,
});
```

Four parameters and no more. Flutter's own `fromSeed` takes forty-six
`Color?` overrides on top of these, and **this one takes none of them on
purpose**: `ColorScheme3d` already has a `copyWith` over every role, so
`ColorScheme3d.fromSeed(seedColor: brand).copyWith(error: brandRed)` says the
same thing in less, and the override list on Flutter's factory is a
consequence of `ColorScheme` having no `copyWith` at the time rather than a
design anyone would repeat.

`contrastLevel` runs from −1.0 to 1.0 and is asserted, as Flutter asserts it.
It is the accessibility knob, and it is forwarded rather than reinvented.

### The variants

`ColorSchemeVariant3d`, mirroring Flutter's `DynamicSchemeVariant` name for
name — `tonalSpot`, `fidelity`, `monochrome`, `neutral`, `vibrant`,
`expressive`, `content`, `rainbow`, `fruitSalad` — so that a figure written
against Flutter's Material transfers here unchanged, which is the same promise
the role names make. `tonalSpot` is the default, as it is there.

The parameter is named `variant` rather than `dynamicSchemeVariant`, because
every other family in this catalogue spells that idea `variant`:
`ButtonVariant3d`, `CardVariant3d`, `AppBarVariant3d`, `NavigationVariant3d`.

### The memo, and why it is not over-engineering

**A generated scheme costs 679µs.** Measured at this commit, 200 calls,
warmed, in the test VM — the HCT solver runs once per role and there are
forty-six of them.

That number is the whole argument. An author writes

```dart
SceneTheme3d(
  data: Theme3dData(colorScheme: ColorScheme3d.fromSeed(seedColor: brand)),
  child: …,
)
```

inside a `build` method, because that is where a theme is installed, and a
`build` method runs on frames. 679µs is four percent of a 60Hz frame spent
re-deriving a value that did not change — and nothing says why, which is the
failure mode `Decoration3dPainterCache` exists to prevent and which the
`ColorScheme3d` class doc already warns about in the next paragraph over.

So `fromSeed` memoizes on its four arguments. The cache is bounded and
least-recently-used, because a seed that animates is a real thing an
application might do and an unbounded map keyed on a colour is a leak. The
first call pays; every equal call after it is a map lookup.

This does not change what `fromSeed` returns, and the suite proves that: a
memoized scheme and a freshly computed one are `==`, which they already would
be, since `ColorScheme3d` has value semantics over all forty-six roles.

### Where the files go

- `lib/src/tokens/color_scheme_variant.dart` — the enum, and the one function
  that turns the four arguments into `material_color_utilities`'
  `DynamicScheme`. Separate from `color_scheme.dart` because it is a public
  vocabulary type and every other one here has its own file, and because it
  keeps the cycle from existing: this file does not know `ColorScheme3d`
  exists.
- `lib/src/tokens/color_scheme.dart` — the factory, the role mapping and the
  memo, beside the `light` and `dark` tables a reader is already looking at.

*(This section first said the split would keep the colour library's import in
one file. It does not: the role mapping needs `MaterialDynamicColors`, so
`color_scheme.dart` imports it too, narrowly. The split is still the right
one, for the reason above rather than the one written first.)*

## Phases

1. **The dependency and the variant vocabulary.** `material_color_utilities`
   in `pubspec.yaml` with its constraint note; `ColorSchemeVariant3d` and the
   `DynamicScheme` builder; exported.
2. **The factory.** All forty-six roles mapped off `MaterialDynamicColors`,
   with `surfaceTint` taken from `primary` as Flutter takes it, and
   `brightness` set from the argument rather than inferred.
3. **The memo.** Bounded LRU on the four arguments.
4. **The suite.** Role by role against Flutter's `ColorScheme.fromSeed` across
   a spread of seeds — including the achromatic ones, which are where a hue
   is undefined — both brightnesses, all nine variants, and five contrast
   levels. Plus: the baseline tables are *not* reproduced and the suite says
   so out loud with the figures above, so the next reader does not file it as
   a defect; the memo returns an equal scheme and an evicted one regenerates
   to the same forty-six roles; the contrast assert fires; and a brand colour
   reaches a filled button's container through `Theme3dData`, which is the
   catalogue plan's promise stated as a test rather than as a sentence.
5. **The prose.** The changelog entry, the README's colour paragraph (which
   currently says a generator is out of scope), the class dartdoc (which says
   the same), and the map's row and entry.

## What this deliberately leaves out

- **`fromImageProvider`.** Flutter has one, and
  `material_color_utilities` carries the quantizer and the scorer it needs, so
  it is buildable — but it is asynchronous, it wants a decoded image, and the
  seam it would want is
  [a picture on a panel](../../flutter_scene_layout3d/plans/2026_09_15_a_picture_on_a_panel.md)'s
  rather than this one's. It is a follow-up, not an open item here.
- **Harmonizing a colour into the scheme.** `Blend.harmonize` is one call away
  and would be one more factory; nothing in the catalogue asks for it and no
  ported screen has yet.
- **A `Theme3dData.fromSeed`.** `Theme3dData(colorScheme: ColorScheme3d.fromSeed(…))`
  is already one line, and phase 6 of the catalogue plan refused
  `AlertDialog3d` for being the first component that exists only to save a
  caller writing a `SceneColumn3d`. The same judgement applies.
- **Anything about how a generated colour is *drawn*.** A scheme is forty-six
  `Color`s; every component already resolves them. This plan has no render
  lane for that reason, and no photograph would tell anyone anything a
  role-by-role comparison against Flutter does not tell them exactly.

## What shipped, and what the plan itself got wrong

All five phases landed in one round, and the suite is **585 tests** in this
package, up from 569 — sixteen new ones, all in `color_scheme_test.dart`.
`dart analyze` is clean across the workspace and the other two suites are
untouched at 1288 and 6.

The design held: the four-parameter factory, the mirrored variant enum, the
`copyWith` argument against per-role overrides, and the memo are all exactly
as reasoned above. Two things this plan got wrong, both corrected in place:

- **The divergence figure was a sample, not a count.** This plan opened by
  saying eight roles differ in light and nine in dark. That was eight of the
  *twelve roles the probe happened to compare*; over all forty-six it is
  **twenty-seven, in both brightnesses** — well over half the scheme. The
  suite is what found it, on its first run, which is the argument for writing
  the count as a test rather than as a sentence. It is now both.
- **The file split's stated reason was wrong**, though the split was right.
  See the note under *Where the files go*.

And one thing worth recording that neither the map nor this plan anticipated:
**`MaterialDynamicColors` does not spell two of the roles the way
`ColorScheme3d` does.** `onInverseSurface` is `inverseOnSurface` there, and
`surfaceTint` has no entry at all because it is `primary` — which is exactly
the pair a hand-written mapping of forty-six fields would get wrong silently,
and exactly what the role-by-role comparison against Flutter is for. Both are
commented where the mapping makes them.
