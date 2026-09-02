import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        DefaultTextStyle,
        IconData,
        StatelessWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene_layout3d/widgets.dart'
    show SceneSemantics3d, SceneText3d;

import '../theme/theme.dart';

/// A Material icon, which is one glyph of a font and nothing else.
///
/// ```dart
/// Icon3d(Icons.favorite, size: 24)
/// ```
///
/// The design bet the catalogue plan made and phase 2 verified on a GPU: an
/// icon here is a one-character [SceneText3d] in the icon font, drawn out of
/// the same `GlyphAtlasCache3d` as every label. `examples/render_probe`'s
/// `icon_glyph` scene is the proof — it rasterizes a `MaterialIcons` code
/// point, puts the ink inside the box layout gave it, tints it, and its
/// control with no renderer draws nothing.
///
/// What that buys is the whole reason to care. An icon costs one quad; a
/// screen of icons and labels is **one texture and one draw call's worth of
/// atlas**, because they share it; and every feature the label path already
/// has — measurement off the relayout path, the unit contract, the clip
/// planes — applies unchanged. The alternative, a mesh or a texture per
/// icon, would have been a phase of its own.
///
/// ## Three things it inherits from being text
///
/// **It is drawn unlit.** `AtlasText3dRenderer` uses an `UnlitMaterial`, so an
/// icon keeps its colour as the surface it sits on turns away from a light
/// while the panel underneath does not. That is deliberate and matches
/// Flutter — text that dims as a card rotates is unreadable — but it means
/// contrast has to be chosen against the *unlit* glyph and the *lit* panel,
/// and a catalogue that ignores it drifts.
///
/// **It answers hit tests on its own account**, as any `Text3d` does. Inside
/// an [InkWell3d] that is harmless: the gesture detector below the ink well
/// is opaque and is found first. An icon that has to let a ray through to
/// something behind it wants a `SceneIgnorePointer3d`.
///
/// **`IconData.matchTextDirection` is not honoured.** A mirrored icon would
/// need a negative scale on the glyph quad, which the atlas renderer does not
/// express; a right-to-left layout gets the unmirrored glyph. State the
/// mirrored icon explicitly until that changes.
class Icon3d extends StatelessWidget {
  /// Creates an icon.
  const Icon3d(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
  });

  /// Material's default icon size, in logical pixels.
  static const double defaultSize = 24.0;

  /// The glyph to draw.
  final IconData icon;

  /// How tall the glyph is, in logical pixels. [defaultSize] by default.
  final double? size;

  /// The colour to draw it in, or null for the ambient [DefaultTextStyle]'s.
  ///
  /// Null is the useful case and is why [Material3d] installs a text style at
  /// all: an icon inside a filled button comes out `onPrimary` without the
  /// button saying anything, because the surface already said what its
  /// content colour is.
  final Color? color;

  /// What the platform announces this icon as, or null to announce nothing.
  ///
  /// Null is right for an icon inside a labelled control — the control names
  /// itself — and wrong for an icon that *is* the control, which is why
  /// `IconButton3d` will pass one.
  final String? semanticLabel;

  /// The direction the announcement reads in; the theme has no opinion, so
  /// this is only needed when [semanticLabel] is set outside a
  /// `Directionality`.
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final inherited = DefaultTextStyle.of(context).style;
    final glyph = SceneText3d(
      String.fromCharCode(icon.codePoint),
      style: TextStyle(
        // The font the icon's own IconData names, with its package, which is
        // what makes an icon from a third-party set work. Flutter's own icons
        // carry `fontFamily: 'MaterialIcons'` and no package, because the
        // font ships with the application under `uses-material-design: true`.
        fontFamily: icon.fontFamily,
        fontFamilyFallback: icon.fontFamilyFallback,
        package: icon.fontPackage,
        fontSize: size ?? defaultSize,
        color: color ?? inherited.color ?? theme.colorScheme.onSurface,
        // A glyph, not a line of type: the extra leading a type scale carries
        // would put the icon off its own centre.
        height: 1.0,
      ),
    );

    final label = semanticLabel;
    if (label == null) return glyph;
    return SceneSemantics3d(
      properties: SemanticsProperties(
        label: label,
        textDirection: textDirection,
      ),
      child: glyph,
    );
  }
}
