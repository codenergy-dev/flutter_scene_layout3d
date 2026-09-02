import 'package:flutter/widgets.dart'
    show BuildContext, InheritedWidget, StatelessWidget, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Text3dRendererFactory;
import 'package:flutter_scene_layout3d/widgets.dart'
    show DefaultTextRenderer3d, SceneSlotProvider3d;

import 'theme_data.dart';

/// The widget-layer half of the theme: `Theme3d.of(context)`.
///
/// An ordinary inherited widget, spelled the way Flutter's `Theme` is, so a
/// widget that builds a component reads the tokens the way it always has.
/// It is only half the channel — a `Layout3d` has no `BuildContext` — and
/// [SceneTheme3d] is what installs both halves at once. Use this class
/// directly only to theme a widget subtree that has no layout in it, or to
/// read the theme.
class Theme3d extends InheritedWidget {
  /// Publishes [data] to the widgets below.
  const Theme3d({super.key, required this.data, required super.child});

  /// The tokens in force.
  final Theme3dData data;

  /// The theme in force at [context], or [Theme3dData.light] when there is
  /// none.
  ///
  /// **It does not throw.** A missing theme yields the baseline light theme,
  /// matching what a `Layout3d` sees through `theme3d` and what
  /// `Layout3d.metrics` does with a missing unit contract. The reasoning is
  /// that a component rendered in the wrong-but-valid baseline is visible and
  /// diagnosable — you can see that it is not your theme — whereas a throw
  /// during a build over a missing default costs more than it explains. Use
  /// [maybeOf] when the difference matters to you.
  static Theme3dData of(BuildContext context) =>
      maybeOf(context) ?? Theme3dData.light;

  /// The theme in force at [context], or null when nothing published one.
  static Theme3dData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Theme3d>()?.data;

  @override
  bool updateShouldNotify(Theme3d oldWidget) => data != oldWidget.data;
}

/// Installs a theme for both layers: the widgets above the layout and the
/// boxes inside it.
///
/// One widget, two writes. It publishes [data] as a [Theme3d] for
/// `Theme3d.of(context)`, and into the surface's `'material3d.theme'` owner
/// slot for a `Layout3d` reading `theme3d` inside `performLayout`. Without
/// the second, a component whose *size* comes from a token — a 40dp button, a
/// list tile at the theme's density — could not see the theme at all.
///
/// ```dart
/// SceneLayout3d(
///   size: const Size3d(4, 3, 0.5),
///   child: SceneTheme3d(
///     data: Theme3dData.dark,
///     textRendererFactory: AtlasText3dRenderer.new,
///     child: screen,
///   ),
/// )
/// ```
///
/// **It is a layout widget, so it goes inside the surface**, under a
/// `SceneLayout3d` and not above it — the slot is written by a box that has
/// to attach to an owner to write anything. To theme a subtree that contains
/// no layout, use [Theme3d] on its own; to theme a surface from its own
/// constructor, pass the slot to `SceneLayout3d.slots`:
///
/// ```dart
/// SceneLayout3d(
///   slots: {Theme3dData.slot: Theme3dData.dark},
///   child: screen,
/// )
/// ```
///
/// That form writes only the owner slot, so `Theme3d.of(context)` below it
/// still finds nothing; it is for a surface whose components are built
/// imperatively.
///
/// **A theme change relayouts the subtree**, which is correct and is also the
/// reason nothing on a per-frame path may rebuild this widget with a new
/// value. Tokens decide sizes. A hover or a press animates a decoration
/// instead, on the repaint-only tier, and marks nothing dirty.
///
/// ## Why the text renderer is offered and not assumed
///
/// [textRendererFactory] is null by default, and only then does this widget
/// leave the theme's own vocabulary. Passing one wraps the child in a
/// `DefaultTextRenderer3d`, so an application says "here is my theme, and
/// here is how labels are drawn" in one call, which is what a Material
/// application actually wants.
///
/// It is not the default because a renderer is not a token: it is a
/// *resource*, owned by the label that holds it and disposed with it, which
/// is exactly why `DefaultTextRenderer3d` carries a factory rather than an
/// instance. A theme that silently created resources would be reaching past
/// what a theme is for, and an application drawing labels some other way —
/// a `RichText3d` subtree, a renderer of its own — would have to opt out of
/// something it never asked for. Offered, never assumed.
///
/// Whatever you pass must be a **stable** function: a constructor tear-off
/// (`AtlasText3dRenderer.new`) or a field on a `State`. A closure written
/// inline in `build` is a new function every build, and every label in the
/// tree rebuilds its renderer.
class SceneTheme3d extends StatelessWidget {
  /// Publishes [data] to the widgets and the boxes below.
  const SceneTheme3d({
    super.key,
    required this.data,
    this.textRendererFactory,
    required this.child,
  });

  /// The tokens to publish.
  final Theme3dData data;

  /// Makes one text renderer, for one label, or null to install none.
  ///
  /// See the class doc for why this is here and why it is optional.
  final Text3dRendererFactory? textRendererFactory;

  /// The subtree the theme covers.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final factory = textRendererFactory;
    final content = factory == null
        ? child
        : DefaultTextRenderer3d(factory: factory, child: child);
    return Theme3d(
      data: data,
      child: SceneSlotProvider3d<Theme3dData>(
        slot: Theme3dData.slot,
        value: data,
        child: content,
      ),
    );
  }
}
