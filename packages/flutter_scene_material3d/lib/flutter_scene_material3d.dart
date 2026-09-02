/// Material Design 3, built as real geometry on `flutter_scene_layout3d`.
///
/// Material 3 is a specification for a flat surface, and every token in it
/// that stands in for depth has to be re-derived here, because here the depth
/// is real. An elevation is a shadow in Flutter and a distance here. A
/// disabled control is 38% opacity in Flutter and a substituted colour here.
/// A component has no thickness in Flutter and must have one here, which is
/// the token Material does not publish at all.
///
/// The library is in two halves. The **tokens** — [ColorScheme3d],
/// [Typography3d], [ShapeScale3d], [Elevation3d], [Thickness3d] and
/// [StateLayerOpacity3d] — are held by a [Theme3dData], installed by
/// [SceneTheme3d], and read by `Theme3d.of(context)` in the widget layer or
/// `theme3d` inside a `Layout3d`'s `performLayout`. The **primitive** is
/// [Material3d], a decorated box with those tokens resolved into it, with
/// [InkWell3d] for the interaction, [Icon3d] for a glyph and
/// [SceneTextStyle3d] for a group of labels. Every component in the catalogue
/// is a `Material3d` with a different set of tokens.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initializeMaterial3d();   // nothing draws without this
///   runApp(const MyApp());
/// }
///
/// SceneLayout3d(
///   size: const Size3d(4, 3, 0.5),
///   child: SceneTheme3d(
///     data: Theme3dData.dark,
///     textRendererFactory: AtlasText3dRenderer.new,
///     child: Material3d(
///       shape: Theme3dData.dark.shape.full,
///       padding: const EdgeInsets3d.symmetric(horizontal: 24, vertical: 10),
///       child: InkWell3d(onTap: submit, child: const SceneText3d('Continue')),
///     ),
///   ),
/// )
/// ```
///
/// There is one import rather than the `flutter_scene_layout3d.dart` /
/// `widgets.dart` pair the layout package has, because the split there
/// separates a complete imperative protocol from a declarative layer over
/// it, and no such split exists here: a catalogue is widgets, and the tokens
/// underneath are plain values both layers read.
///
/// **Nothing in this package draws until [initializeMaterial3d] has run.**
/// `BoxDecoration3d.painterFactory` is null until something sets it, so a
/// themed component measures, lays out and shows nothing, with no error
/// anywhere. That call awaits the engine and installs the painter — giving
/// each box a material of its own, since panels that share one all come out
/// the colour of whichever painted last. The shader itself is compiled for
/// you by `flutter_scene_layout3d`'s own build hook, and this package
/// deliberately ships no build hook of its own.
library;

export 'src/app/setup.dart'
    show
        PanelMaterialFactory,
        initializeMaterial3d,
        installPanelPainter3d,
        kPanelMaterialSource,
        loadPanelMaterialFactory;
export 'src/components/icon.dart' show Icon3d;
export 'src/components/ink.dart'
    show InkController3d, InkController3dScope, MutableInkController3d;
export 'src/components/ink_well.dart' show InkWell3d;
export 'src/components/material.dart' show Material3d;
export 'src/components/text_style.dart' show SceneTextStyle3d;
export 'src/theme/theme.dart' show SceneTheme3d, Theme3d;
export 'src/theme/theme_data.dart' show Layout3dTheme3d, Theme3dData;
export 'src/theme/tweens.dart'
    show
        ColorScheme3dTween,
        Elevation3dTween,
        ShapeScale3dTween,
        StateLayerOpacity3dTween,
        Theme3dDataTween,
        Thickness3dTween,
        Typography3dTween;
export 'src/tokens/color_scheme.dart' show ColorScheme3d;
export 'src/tokens/depth.dart' show Elevation3d, Thickness3d;
export 'src/tokens/shape.dart' show ShapeScale3d;
export 'src/tokens/state_layer.dart' show Material3dState, StateLayerOpacity3d;
export 'src/tokens/typography.dart' show Typography3d, Typography3dToken;
