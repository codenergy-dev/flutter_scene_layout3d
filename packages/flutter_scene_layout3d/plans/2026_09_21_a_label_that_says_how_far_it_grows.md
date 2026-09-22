---
status: completed
created_at: 2026-09-21T16:05:00Z
updated_at: 2026-09-21T16:22:20Z
commit: 6f78d36e550feba9f1a516cb5e5225d22e7bc30a
---

# A label that says how far it grows

Phase 0 of phase 2 of
[the components a screen still needs](../../flutter_scene_material3d/plans/2026_09_21_the_components_a_screen_still_needs.md),
in the package it belongs to, which is the rule the catalogue's own phase 0
set: a change to the layout protocol that the catalogue needs gets its plan
here rather than a line item in a Material plan.

## What the catalogue needed

That phase asked which of the catalogue's controls stop fitting their label
at a large font setting, and measured it rather than guessing: a screen's
worth of components laid out at 1.3 and at twice the size. One overflowed —
`NavigationBar3d`, already at 1.3 — and Flutter's does not, for two reasons
that are both about labels that **do not follow the reader's setting all the
way**:

- Flutter's `Icon` is a `RichText`, whose scaler is `TextScaler.noScaling`.
  Icons never grow with type. `Icon3d` is a `SceneText3d`, and did.
- Flutter's `NavigationBar` clamps its labels to 1.3 and its `AppBar` clamps
  its title to 1.34, with `MediaQuery.withClampedTextScaling` around the
  label.

Neither is expressible here. The reader's setting is
`Layout3dMetrics.textScaler`, one value per surface, read by a `Text3d`
inside `performLayout`; there is no per-label scaler and no way to clamp one
for a subtree.

## The design

Two things, both Flutter's spelling:

- **`Text3d.textScaler` and `RichText3d.textScaler`**, null by default, which
  replace the surface's scaler for that box. `effectiveTextScaler` is what the
  box measures with. `SceneText3d` and `SceneRichText3d` take the same
  parameter, as Flutter's `Text` does.
- **`SceneTextScaling3d`**, an inherited widget carrying the scaler for a
  subtree, with a `clamped` constructor that clamps whatever is in force
  where it is built. The two text widgets pass its scaler to their box when
  they were given none of their own.

The question that decided the shape was the one
[a screen that knows how big it is](2026_09_16_a_screen_that_knows_how_big_it_is.md)
settled for the setting itself: **one number, one home**. A scope that
*restated* the reader's setting for a subtree would be a second home; this one
states what a subtree *does with* the setting, and it is null-by-default at
every box, so a box that is told nothing keeps following the surface when the
setting changes rather than holding a copy of it. The scope lives in the
widget layer, as `MediaQuery3d` does, because only a `build` method reads it.

## The work

- [x] `Text3d.textScaler`, `effectiveTextScaler`, and `logicalPixelScale`
      over it; the same on `RichText3d`, whose painter, capture and
      invalidation all read the effective scaler.
- [x] `SceneText3d.textScaler` and `SceneRichText3d.textScaler`, falling back
      to `SceneTextScaling3d.maybeOf`.
- [x] `SceneTextScaling3d` and `SceneTextScaling3d.clamped`, exported from
      `widgets.dart`.
- [x] Tests: an override replacing and releasing the surface's scaler on both
      boxes; the widget following the surface with none; a clamp capping,
      passing a smaller setting through, reaching every label below, nesting,
      losing to an explicit scaler, and following the setting as it changes.
- [x] The changelog, the README's *The reader's own font setting*,
      `docs/traps.md`, and the dartdoc example in the compile test.

## What the reasoning got wrong

Only one thing, and it is a warning about the design rather than a defect in
it. **The scope reaches labels built by the widget layer and nothing else.**
An imperative `Text3d` has no `BuildContext`, so a component that builds its
labels imperatively and wraps them in a clamp gets no clamp at all, silently.
Every label in the catalogue is a `SceneText3d`, so nothing is affected today;
`docs/traps.md` says so where the next author will look.
