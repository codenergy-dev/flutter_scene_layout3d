## Unreleased

- **A modal's scrim dims the screen evenly.** Its alpha is spent as
  *coverage* rather than as a blend: the slab draws in its colour at full
  strength and keeps that fraction of its fragments, which is the same
  screen-door `Opacity3d` fades a subtree with. `scrimCoverage3d` is where the
  reasoning lives, and `DialogStyle3d.scrimColor` and
  `BottomSheetStyle3d.scrimColor` keep Material's `scrim` at 32% — only how
  that number is spent has changed.
  - **A blended scrim did not dim unevenly, it erased.** Every panel and every
    glyph on a Material screen writes depth, each for a reason its own shader
    header explains, and the translucent pass sorts by one number per draw —
    so a 32% slab in front of a screen wiped out whatever the sort put after
    it. An app bar's title came out as a bare outline while the navigation
    bar's labels were untouched, on the same screen, under the same scrim.
  - **Four treatments were built over the gallery and photographed**, and the
    one that was *predicted* to work does not: with `depth_write` off — which
    is what `box_decoration3d.fmat`'s own note used to prescribe — the app bar
    is drawn over the scrim and is not dimmed at all. The error inverts rather
    than closing. That note is corrected, and
    [the plan](plans/2026_09_17_a_scrim_that_dims_evenly.md) has the pictures.
  - The cost is that the dim is dithered rather than smooth. It was chosen by
    looking at a window, which is the only thing that answers that.
  - **A scrim given an opaque colour now hides the screen** rather than
    dimming it, which is the third treatment and is worth knowing before
    writing one.

- **A modal's scrim clears the whole screen it dims.** `modalFrame3d` puts its
  barrier on the frame's **front** face in depth and takes the caller's
  alignment across, where before it took both — and an `Alignment3d` centres
  in depth as well, so the scrim sat a fraction of a slab behind the frame's
  own face. Together with the layout package's lift fix, a dialog's scrim and
  a sheet's now land in the same place instead of 35dp apart, and both are in
  front of the app bar and the floating action button, which neither used to
  dim. `test/dialog_test.dart` asserts a real scaffold's scrim clears every
  opaque panel on it, which is the alarm that was missing.

- **The catalogue moves.** `MotionScheme3d` is the seventh token family —
  Material 3's sixteen durations and nine easing curves, carried on
  `Theme3dData.motion`, with `copyWith`, a `lerp` and a `MotionScheme3dTween`
  beside the other six. Every figure is `Durations`' or `Easing`'s, which
  Flutter generates straight from the Material token database, so
  `test/motion_test.dart` compares value to value and a figure that moves
  upstream fails on the next `flutter upgrade`. That is the strongest drift
  lane in this package: nothing is rendered and nothing is reflected over.
  - **The family stayed closed until there were customers, and now there are
    six.** The plan refused it three times with the same sentence — *one
    animation is not a scale* — and shipped the press ripple as
    `InkRipple3dStyle` instead. Six overlays needing the same curve is the
    case that was being waited for.
  - **The durations interpolate and the curves snap at the midpoint.** A
    `Curve` is a function and there is no value half way between two of them
    that is itself a curve, which is what `TextStyle.lerp` does with every
    discrete field it carries. And because `Cubic` has no value equality, two
    schemes compare by identity — exactly right for `const` tokens, and a
    reason to hold a computed curve in a `static const`.
  - **It is a vocabulary, not a cage.** A style may carry any duration it can
    defend: `InkRipple3dStyle` holds 75, 225 and 375 and none of those is a
    token, and neither is the tooltip's 75ms fade out.

- **Every overlay arrives instead of appearing.** A dialog grows from 85% and
  fades in over its own scrim; a menu grows out of its top edge; a sheet rises
  one whole height from off the edge it is pinned to; a snack bar rises the
  same way; a tooltip fades. `Arrival3d` is the value each of the five overlay
  styles now carries — a `Motion3d`, two durations and two curves — and
  `Arrival3d.transition` is the clock a route runs on.
  - **The durations are Flutter's own** and all but one land on an M3 duration
    token: 150ms for a dialog, 300ms for a menu, 250ms in and 200ms out for a
    sheet, 250ms for a snack bar, 150ms in and 75ms out for a tooltip. **The
    curves deliberately are not.** Flutter opens a dialog on `Curves.easeOut`
    and a modal sheet on `Easing.legacyDecelerate`, both of which predate the
    motion tokens — the second says so in its own name — so the catalogue
    arrives on `emphasizedDecelerate` and leaves on `emphasizedAccelerate`,
    which is what the family exists to adopt. Every one is a field on a public
    style.
  - **The motion goes inside the scrim and the scrim fades on its own.** A
    catalogue modal builds its own barrier through `modalFrame3d`, so a
    transition around the whole of a route's content would slide the dim in
    with the dialog it dims. `modalFrame3d` takes a `scrimFade` instead.
  - **The two overlays that are not routes keep their own clock.** A tooltip
    and a snack bar are bare overlay entries and should stay that way — a
    route would give them a barrier, a focus trap and a result future they
    have no use for — so each drives an `AnimationController` of its own and
    removes its entry when the reverse finishes. The messenger's queue had to
    be taught the difference: a bar on its way out is **still in the overlay**,
    so the next one waits for it rather than arriving on top of it.
  - **A bar or a label that is leaving is still pressable where layout put
    it**, not where it is drawn. That is the node tier's contract everywhere
    in this stack, and an arrival is the first thing in the catalogue to make
    it visible: a test that presses an overlay now settles first, as a person
    waits.

- **A popup menu's button could not be pressed.** `PopupMenuButton3d` had no
  outer `TapTarget3d` at all, where `Button3d` has had one since phase 2, so
  its whole reach was its child — and its child is usually an `Icon3d`, which
  is a 24dp glyph. It also put the align that shrink-wraps that child
  *outside* its ink well, which handed the well loose constraints and left the
  target with a glyph's depth, which is none: a slab with no thickness is
  degenerate and no ray intersects it. An overflow button in an app bar laid
  out, drew, announced itself to a screen reader and did nothing. Both are
  fixed, and `test/menu_test.dart` states each as its own case.

- **`PopupMenuButton3d` takes `menuCorner` and `anchorCorner`**, the pair
  `showMenu3d` already had. A button against the trailing edge of a panel
  needs them: a menu opening the usual way runs off the surface, where a ray
  finds nothing at all. **Nothing chooses them for you**, and that is the
  deferral this catalogue has now made twice — what "off the edge" means for a
  surface at any angle, which may be looked at from behind, is a design
  question and not a parameter.

The first contents of this package, and they are the whole catalogue: ten
phases from an empty package to a screen a person can look at, all of them
`completed` in [the plan](plans/2026_09_01_flutter_scene_material3d.md). Every
component in it is a **`Material3d` with a public token set resolved by
state**; there is no second mechanism anywhere in the catalogue.

Material 3 is a specification for a flat surface, so every token in it that
stands in for depth is re-derived here. An elevation is a shadow in Flutter
and a distance here. A disabled control is 38% opacity in Flutter and a
substituted colour here — originally because there was no opacity in this
stack at all, and still now that there is one, because `Opacity3d` is
screen-door coverage and fades a label and the slab under it independently,
where Material's 38% composites the pair first. A
component has no thickness in Flutter and must have one here, which is the
token Material does not publish at all. The plan's middle section is where
that reasoning lives.

- **Disabled is still a colour, and now it is a choice rather than an
  absence.** `flutter_scene_layout3d` has an `Opacity3d`, so a catalogue could
  fade a disabled control the way Flutter does. It does not, and the README
  says why in its own section: the fade this stack can do is coverage, which
  fades a label and its container on their own and is at its least faithful
  exactly in the middle — while the tokens this catalogue substitutes are the
  figures Material's specification states as the *result* of its 38%. What
  changed is the reasoning, not a line of code.

- **The catalogue's type follows the reader's own font setting.** Nothing here
  changed to make it so: `Layout3dMetrics` carries a `TextScaler` now, a
  `SceneLayout3d` writes the ambient `MediaQuery.textScalerOf` into it, and
  every label in the catalogue is a `Text3d` that measures through it. What is
  worth knowing is the component side of it — a control whose height is a
  fixed dp figure does not grow with its label, exactly as in Flutter, so a
  48dp row of 14sp text at a large setting is a row the text overflows.
  `Scaffold3d` does not consume the safe area either: on a surface bound to
  the camera, wrap the screen in `SceneSafeArea3d` yourself. Both belong to
  the components plan rather than to the theme.
- **The catalogue mirrors in a right-to-left application.** Its rows follow
  the ambient `Directionality` on their own now that the layout package's do,
  so what changed here is everything that would otherwise have been left on
  the wrong side:
  - **`ListTile3d.defaultContentPadding` is directional** — 16dp at the start
    and 24dp at the end, Flutter's `EdgeInsetsDirectional` — and
    `contentPadding` and `Material3d.padding` take any `EdgeInsetsGeometry3d`.
    `Material3d.alignment` takes any `AlignmentGeometry3d`.
  - **`Divider3d` indents from its leading edge**, as Flutter's does.
  - **An app bar puts its leading widget at the start**, and keeps its title
    `titleSpacing` off whichever edge is empty; the centred toolbar mirrors
    its `NavigationToolbar` arithmetic. `AppBarStyle3d.padding` stays
    physical, and the side counted toward the leading slot is the side the
    leading widget is on.
  - **A slider's minimum is at the right**, its fill grows from there, a press
    reads its fraction from the right, and left and right on the keyboard move
    the thumb the way the arrow points — Flutter's slider, which the arrow-key
    entry below had to diverge from until now. `SliderGesture3d` takes a
    `textDirection`.
  - **A switch that is on has its thumb at the left**, as Flutter's has.
  - **A menu hangs from its button's start corner.** `Follower3dWidget`'s
    `self` and `target` are `AlignmentGeometry3d`, defaulting to
    `AlignmentDirectional3d.topStart` and `bottomStart`, which is Flutter's
    `MenuAnchor`; `showMenu3d`'s `menuCorner` and `anchorCorner` follow, and a
    `Follower3d`'s corners can be changed after it is built.

- **An app bar's last action reaches the bar's edge, as Flutter's does.**
  `AppBarStyle3d.padding` defaulted to 4dp on both sides, which stood in for
  Flutter centring a 48dp leading button in its 56dp slot — and also held the
  actions 4dp in from the trailing edge, where Flutter's M3 bar has no padding
  at all (`actionsPadding` is zero). The padding is **zero** by default now,
  and the leading widget is centred in its `leadingWidth` slot instead, so a
  leading button and the title stay exactly where they were and the actions
  move out to the edge. A leading widget narrower than a button is centred in
  the slot too, as Flutter's is. A style that states its own padding keeps it,
  counted toward the leading slot and the title's spacing at the edges.

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
  `onChangeStart` and `onChangeEnd`. Left and right follow the track, which
  mirrors in a right-to-left application — see the entry above.

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
