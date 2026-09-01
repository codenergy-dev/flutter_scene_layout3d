import 'package:flutter/widgets.dart' show BuildContext, InheritedWidget;

import '../text/text3d.dart';
import '../text/text_renderer.dart';

/// The renderer every [SceneText3d] below this widget draws through, unless
/// it was handed one of its own.
///
/// The gap this fills is the one `DefaultTextStyle` fills for a style.
/// [Text3d.renderer] is null by default and a label with no renderer draws
/// nothing — deliberate, because rasterization needs a GPU context that
/// `flutter test` does not have — so without an inherited default every label
/// in an application has to be handed an `AtlasText3dRenderer` by hand. Put
/// one of these above the surface instead:
///
/// ```dart
/// DefaultTextRenderer3d(
///   factory: AtlasText3dRenderer.new,
///   child: SceneView.declarative(children: [SceneLayout3d(child: screen)]),
/// )
/// ```
///
/// **It carries a factory, not a renderer, and that is not a detail.** A
/// [Text3dRenderer] handed to a [Text3d] is owned by that box: the box
/// disposes it when it is disposed and when a different one is set. One
/// inherited *instance* shared by a screen of labels would therefore be
/// disposed by whichever label left the tree first, and every remaining label
/// would be holding a dead renderer — drawing nothing, or worse. So each
/// label calls [factory] once and owns what comes back. The expensive thing,
/// the glyph atlas, is shared underneath through `GlyphAtlasCache3d.shared`,
/// which is what makes a screen of labels one texture; the renderer in front
/// of it is cheap.
///
/// A label states its own renderer to override this, exactly as it states its
/// own style to override a `DefaultTextStyle`.
class DefaultTextRenderer3d extends InheritedWidget {
  /// Creates an inherited default renderer.
  const DefaultTextRenderer3d({
    super.key,
    required this.factory,
    required super.child,
  });

  /// Makes one renderer, for one label.
  ///
  /// Called once per `SceneText3d` below this widget, and again for all of
  /// them if this widget is rebuilt with a different function — so keep it
  /// stable. A tear-off of a constructor (`AtlasText3dRenderer.new`) or a
  /// field on a `State` is stable; a closure written inline in `build` is a
  /// new function on every build and would rebuild every renderer in the
  /// tree.
  final Text3dRendererFactory factory;

  /// The factory in force at [context], or null when there is none.
  static Text3dRendererFactory? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DefaultTextRenderer3d>()
      ?.factory;

  /// The factory in force at [context].
  ///
  /// Throws when there is none, for a caller that would rather fail than draw
  /// an invisible label. Most callers want [maybeOf].
  static Text3dRendererFactory of(BuildContext context) {
    final factory = maybeOf(context);
    assert(factory != null, 'No DefaultTextRenderer3d found in this context.');
    return factory!;
  }

  @override
  bool updateShouldNotify(DefaultTextRenderer3d oldWidget) =>
      factory != oldWidget.factory;
}
