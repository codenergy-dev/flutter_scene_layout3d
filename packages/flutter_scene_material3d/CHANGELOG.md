## Unreleased

- Initial contents: the token layer, the theme that carries it, and the
  primitive every component is made of. The buttons, cards and bars are the
  next phase of
  [the plan](plans/2026_09_01_flutter_scene_material3d.md).
- **`initializeMaterial3d()`**, the one call a Material application makes
  before `runApp`: it awaits `Scene.initializeStaticResources()` and installs
  the panel painter, without which every component measures, lays out and
  draws nothing. It gives each decorated box a material of its own rather
  than sharing one — a screen of panels sharing a material comes out in one
  colour, because the last box painted wins the parameter block — which needs
  a synchronous factory over an asynchronous load, and
  `loadPanelMaterialFactory` is that, public for anyone writing their own
  painter. The default text renderer is deliberately not in it: a renderer is
  owned by one label, so there is no global one to install, and
  `SceneTheme3d.textRendererFactory` is the other half.
- **`Material3d`**, a `SceneDecoratedBox3d` with the theme resolved into it:
  the colour, the shape, the elevation, the surface tint, the state layer, and
  a thickness with the bevel `ShapeScale3d.bevelFor` implies. Its padding and
  thickness are in logical pixels and it converts them through
  `Layout3dMetricsScope.of(context)`, so it must be built inside a
  `SceneLayout3d`. Its `contentColor` is both the wash colour and the colour
  of the labels and icons below, through a `DefaultTextStyle` it installs. It
  aligns its child to `Alignment3d.frontCenter`, because a child centred in
  depth sits inside the slab and is hidden by it.
- **`InkWell3d`**, the interaction over it: a 48dp `SceneTapTarget3d`, a
  `SceneFocus3d`, and hover, focus and press driving the panel's state layer
  through an **`InkController3d`** rather than through `setState`. A hover
  rebuilds nothing and lays nothing out, and the tests assert that by
  counting. `focusOnPointerDown` is there because a press focuses the control
  by default and nothing here reads Flutter's highlight mode, so the focus
  wash otherwise outlives the press.
- **`Icon3d`**, one code point of an icon font drawn as a one-character
  `SceneText3d` through the same glyph atlas as every label — verified on a
  GPU rather than assumed. It takes its colour from the surface it is on, is
  drawn unlit like all text here, and does not honour
  `IconData.matchTextDirection`.
- **`StateLayerOpacity3d`** and **`Material3dState`**, the sixth token family:
  Material's 8/10/10/16 wash opacities, with the rule that a component in more
  than one state takes the strongest and never the sum.
- **`Typography3dToken`**, `Typography3d.resolve`, `Theme3dData.textStyle` and
  **`SceneTextStyle3d`**: a type role as a value, so a component can be handed
  one, and a subtree can be styled with a token and a colour role rather than
  an assembled `TextStyle`.
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
- **`Theme3dData`**, holding the six families and a `VisualDensity3d`, with
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
