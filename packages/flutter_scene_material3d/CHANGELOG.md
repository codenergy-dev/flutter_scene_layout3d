## Unreleased

The first contents of this package, and they are the whole catalogue: ten
phases from an empty package to a screen a person can look at, all of them
`completed` in [the plan](plans/2026_09_01_flutter_scene_material3d.md). Every
component in it is a **`Material3d` with a public token set resolved by
state**; there is no second mechanism anywhere in the catalogue.

Material 3 is a specification for a flat surface, so every token in it that
stands in for depth is re-derived here. An elevation is a shadow in Flutter
and a distance here. A disabled control is 38% opacity in Flutter and a
substituted colour here, because there is no opacity in this stack. A
component has no thickness in Flutter and must have one here, which is the
token Material does not publish at all. The plan's middle section is where
that reasoning lives.

- **A centred app bar title stays clear of the leading widget and the actions,
  and the controls keep their places.** The centred toolbar was a stack, which
  shrink-wraps its largest child: the title. So the row holding the leading
  widget and the actions was squeezed into the title's width and overflowed it,
  drawing the controls bunched around the title, and a long title was drawn
  straight over them. It is Flutter's `NavigationToolbar` arithmetic now — the
  controls at the bar's two ends, the title centred in the whole bar and pulled
  back so that it never comes closer than `titleSpacing` to the leading slot
  and never runs into the actions. A centred bar with no controls, which is the
  only kind the gallery has, looks as it did.

- **An app bar's title starts where Flutter's does behind a leading widget.**
  Flutter gives the leading widget a slot `kToolbarHeight` wide, 56dp, and
  starts the title 16dp past the end of the *slot*; `AppBar3d` started it 16dp
  past the widget, so behind a 48dp icon button the title sat at 68dp instead
  of 72. **`AppBarStyle3d.leadingWidth`**, 56 by default and checked against
  `kToolbarHeight`, is the slot, measured from the bar's edge with its padding
  included. The widget sits at the slot's leading edge, which puts a 48dp icon
  button's middle 28dp in — where Flutter centres its own, and where this
  bar's already was. `AppBarStyle3d`'s constructor takes the new field.

- **A menu item is pressed where it is drawn.** `Follower3d` puts a menu at its
  button with a node offset, and a hit test moves a ray into a box by its
  layout offset alone — so every item of a `PopupMenuButton3d` answered in the
  middle of the panel, where the overlay had laid the menu out and nothing was
  drawn, and a press on the item itself reached the barrier and closed the
  menu with nothing chosen. `Follower3d` now shifts its hit test by its own
  node offset, which is what Flutter's `CompositedTransformFollower` does. The
  component's test had been pressing the empty middle of the panel; it presses
  through the camera now, with `tester.tap3d`, which is how the defect was
  found.

- **An app bar keeps its title off an edge with nothing on it.** A bar with no
  leading widget put its title 4dp from its edge — the bar's own padding and
  nothing more — and a bar with no actions let a long title run to 4dp of the
  other one, because the toolbar row's `titleSpacing` is the gap *between* its
  children. Flutter's `NavigationToolbar` keeps the title 16dp clear of both
  ends whether or not anything is there, and so does `AppBar3d` now, for the
  small bar and for the headline of a medium or large `SliverAppBar3d`. The
  bar's padding counts toward the 16dp rather than being added to it. The
  gallery's inbox bar had shown the first half in every frame since the
  gallery was built; the photograph the render probe app now takes of it is
  what pointed at it.

- **A focused slider moves on the arrow keys.** All four, as Flutter's does: up
  and right raise it, down and left lower it, by one division, or by Flutter's
  platform unit for a continuous slider — a tenth on Apple platforms and a
  twentieth elsewhere. Each press is a whole gesture, bracketed by
  `onChangeStart` and `onChangeEnd`. Left and right follow the track rather
  than the reading direction, because the track does not mirror for a
  right-to-left locale yet.

- **Enter and Space activate a focused control, and Escape closes an overlay.**
  **`InkWell3d` binds `ActivateIntent`**, the way Flutter's `InkWell` does, so
  every button, card, tile, chip, menu item, navigation destination and
  selection control answers the keyboard: the ripple starts from the middle of
  the control, `onTap` runs, and the ripple is let go. The binding is enabled
  only for an enabled control with an `onTap`, so a key on one that would do
  nothing goes on up the tree. A dialog, a menu and a modal sheet take the
  focus when they open and close on Escape; **`showDialog3d` and
  `showModalBottomSheet3d` now hand `barrierDismissible` to their route** as
  well as to their scrim, so a dialog that must be answered refuses the key as
  it refuses the tap.

- **Every label and icon on a panel is lifted off its face.**
  **`Material3d.contentLift`**: two surfaces sharing a plane both write depth
  there and come out striped rather than one hiding the other, and no
  component can fix that for itself when the thing behind it belongs to the
  application. Icons came out thick for free when a glyph gained a wall,
  because an `Icon3d` is one glyph of a font.
- **The gallery**, in `examples/layout3d_gallery` — a Material screen on an
  upright panel that turns, the same catalogue flat on the ground, and raw
  meshes beside them. It is the phase that most repays reading, because four
  of the things it found were defects a full green suite had been standing
  behind:
  - **Every slot of every `Scaffold3d` was unreachable by a ray.** The depth
    lift was written into the slot's *position*, and toward the viewer is
    negative z, which puts a child outside its parent's extent where a hit
    test clamps. It is on the node tier now, where `Stack3d.depthStep` has
    always put it. **A lift written into a child's position takes that child
    out of reach of a ray.**
  - **A screen's slots were one logical pixel deep**, because a `Material3d`
    hands its child a *tight* depth and the backing was the arrangement's
    parent rather than its sibling.
  - **A `semanticLabel` with no `textDirection` crashed the frame** the moment
    anything switched semantics on, which `flutter test` never does.
    `readingDirection3d` resolves it from the ambient `Directionality`, with a
    final fallback because a scene is not obliged to have one.
  - The example app had **no build hook at all**, so the committed version
    could never have drawn its own cubes.
- **The press ripple.** **`Ripple3d`** on `StateLayer3d` is the layout
  package's half; here it is **`InkRipple3dRun`**, the timeline with no ticker
  in it, and **`InkRipple3dStyle`**, which holds Flutter's own `InkRipple`
  figures and is replaceable per controller the way `ButtonStyle3d` is
  replaceable per button.
  - **Material 3's ripple *is* the press state layer** rather than a second
    wash over it, so a pressed control's uniform opacity is now the hover
    figure and the ripple carries the rest.
  - One box carries one pair of uniforms, so it carries one ripple; a second
    press replaces the first, and the suite states that as the behaviour
    rather than leaving it undefined. A press with no noted point ripples from
    the middle of the surface, which is what a keyboard activation would get
    if anything in this stack activated a control from the keyboard.
- **The selection controls**: **`Checkbox3d`**, **`Radio3d`**, **`Switch3d`**
  and **`Slider3d`**, over `CheckboxStyle3d`, `RadioStyle3d`, `SwitchStyle3d`
  and `SliderStyle3d` with a resolved form each. The one phase since the
  buttons that needed **nothing** from the layout package:
  `PointerSequence3d.addArenaMember` had been built for exactly this customer
  and took a slider without a change, through `SliderGesture3d` and
  `SceneSliderGesture3d`.
  - **`Thickness3d.stepOver`**, because the "stand proud of what it is drawn
    on" arithmetic had been written by hand three times and this phase needed
    it four more.
  - **`NodeShift3d`** and **`SceneNodeShift3d`**, the declarative form of the
    node tier. Its *scale* channel is what lets a slider's track fill without
    a relayout.
  - `Slider3d` takes a `width` in logical pixels where Flutter's fills the room
    it is given: the thumb's position is written by the widget that builds it,
    so the width has to be known before layout rather than after it.
- **The overlays**, all sitting one depth step in front of the frontmost thing
  a `Scaffold3d` declares — which is **`Scaffold3d.overlayLift`** and is
  arithmetic rather than a figure. **`Dialog3d`** and `showDialog3d` over
  `Navigator3d.push`; **`Menu3d`**, `MenuItem3d`, `MenuItem3dEntry`,
  `PopupMenuButton3d` and `showMenu3d`; **`SnackBar3d`** behind a queueing
  **`ScaffoldMessenger3d`** with `SnackBar3dController` and
  `SnackBar3dClosedReason`; **`Tooltip3d`**; and **`BottomSheet3d`** modal or
  persistent on any of four `Sheet3dEdge`s, through `showBottomSheet3d` and
  `showModalBottomSheet3d`. Their tokens are `DialogStyle3d`, `MenuStyle3d`,
  `SnackBarStyle3d`, `TooltipStyle3d` and `BottomSheetStyle3d`.
  - **`Anchor3d`** and **`Follower3d`** (with their widget forms) put a menu at
    its button, over the layout package's `Layout3d.anchorOffsetTo`.
  - Nothing here slides, fades or grows. `Route3dTransition.none` is the
    honest default and this package has no motion tokens yet; the seam is
    `Navigator3d.transition`.
- **The structure.** **`Scaffold3d`** and `Scaffold3dSlot`, which owns the
  depths between a screen's slots rather than leaving each component to guess;
  **`AppBar3d`** and **`SliverAppBar3d`** over one `AppBarStyle3d` with
  `AppBarVariant3d`; **`NavigationBar3d`** and **`NavigationRail3d`** over one
  `NavigationStyle3d`, with `NavigationDestination3d`; and
  **`VerticalDivider3d`**, which the rail finally gave something to separate
  with.
  - M3's selection pill turned out to be a `Material3d` with a `full` shape and
    nothing new at all.
- **The surfaces and rows.** **`Card3d`** in Material's three kinds
  (`ElevatedCard3d`, `FilledCard3d`, `OutlinedCard3d`) over `CardStyle3d`;
  **`ListTile3d`** with its slots and its three heights; **`Divider3d`**,
  which had to decide what a 1dp line *is* when depth is real — a slab, because
  a zero-depth one is coplanar with the surface it is drawn on and z-fights
  it; and **`Chip3d`** in four (`AssistChip3d`, `FilterChip3d`, `InputChip3d`,
  `SuggestionChip3d`) over `ChipStyle3d`.
  - A card's `clipBehavior` is **not** implemented: it needs a clip whose
    region is a rounded rectangle, and `Clip3dRegion` is an intersection of
    planes — convex, and a radius is not expressible that way. A child
    overflowing a rounded card is not clipped to it.
- **The seven buttons**, which are one **`Button3d`** with seven
  `ButtonStyle3d` token sets: **`FilledButton3d`**,
  **`FilledTonalButton3d`**, **`OutlinedButton3d`**, **`TextButton3d`**,
  **`ElevatedButton3d`**, **`IconButton3d`** and
  **`FloatingActionButton3d`**, with `ButtonVariant3d` and
  `ResolvedButtonStyle3d`.
  - The placement rule every component from here on obeys: **a `TapTarget3d`
    reaches past its own extent and its parent does not**, so the target sits
    outside every box the size of the control — the panel and the semantics box
    included.
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
