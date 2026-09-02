## Unreleased

- Initial contents: the token layer and the theme that carries it. No
  components yet — `Material3d`, `InkWell3d` and the catalogue are the next
  phase of
  [the plan](plans/2026_09_01_flutter_scene_material3d.md).
- **`ColorScheme3d`**, Material 3's forty-six colour roles with hand-written
  light and dark baselines. The figures are checked against Flutter's own
  generated M3 tables rather than against a second hand-written copy, so the
  suite is a drift alarm as well as a transcription check. Seed generation is
  out of scope.
- **`Typography3d`**, the fifteen-style M3 type scale as Flutter `TextStyle`s,
  which `Text3d` consumes directly. Sizes, weights and tracking are
  Material's; the line heights are the exact published ratios (`64 / 57`)
  rather than Flutter's rounded multiples (`1.12`), which is under half a
  percent of a line and in the direction of the spec.
- **`ShapeScale3d`**, the corner radii from `none` to `full`, plus
  `bevelFor(thickness)`: a slab's rim wants rounding in proportion to how deep
  it is, and Material has no token for either. `full` is a large finite radius
  that `BorderRadius3d.resolve` turns into a stadium on any box —
  `double.infinity` would resolve to `NaN` and draw nothing.
- **`Elevation3d`**, Material's six levels in logical pixels. The elevation is
  a real distance here and casts no shadow, so the surface tint carries the
  weight; `tintOpacityFor` delegates to the same table the panel shader's
  uniforms are resolved through, rather than transcribing it a second time.
- **`Thickness3d`**, the token Material does not have: how deep a component
  is. Four steps on a stated `depthStep`, with `minimumStepFor` and
  `separates` encoding the rule that a `Stack3d` only separates children when
  its step exceeds the *mean* of two adjacent thicknesses.
- **`Theme3dData`**, holding the five families and a `VisualDensity3d`, with
  `lerp` on every one of them so a theme change can be animated, and a tween
  per family beside `BoxDecoration3dTween`'s shape.
- **`SceneTheme3d`** writes both halves of the theme channel: a `Theme3d`
  inherited widget for `Theme3d.of(context)`, and the `'material3d.theme'`
  owner slot for a `Layout3d` reading `theme3d` inside `performLayout`, where
  there is no `BuildContext`. Writing the slot relayouts the subtree, which is
  right — tokens decide sizes — and means nothing on a per-frame path may
  write a theme.
- `SceneTheme3d.textRendererFactory` is optional and null by default. A
  renderer is a resource with an ownership contract rather than a token, so
  the theme offers to install one and never assumes it.
- With no theme published, `Theme3d.of` and `theme3d` return
  `Theme3dData.light` rather than throwing, the way `Layout3d.metrics` falls
  back to a standard unit contract. `Theme3d.maybeOf` and `hasTheme3d` answer
  the question directly.
- The package ships **no build hook**. The panel shader every component draws
  through belongs to `flutter_scene_layout3d`, which compiles it for its
  consumers; the only thing a hook here could add is `buildEngineAssets`, and
  a library must never call that.
