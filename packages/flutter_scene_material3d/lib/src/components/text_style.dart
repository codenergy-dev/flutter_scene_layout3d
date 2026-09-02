import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter/widgets.dart'
    show BuildContext, DefaultTextStyle, StatelessWidget, Widget;

import '../theme/theme.dart';
import '../tokens/typography.dart';

/// Styles every label below it with one type token and one colour role.
///
/// The gap it fills is small and constant. `SceneText3d` already picks up the
/// ambient `DefaultTextStyle`, so the machinery is there; what is missing is
/// a way to say *which Material style* without assembling a `TextStyle` by
/// hand at every call site and re-deriving it whenever the theme changes:
///
/// ```dart
/// SceneTextStyle3d(
///   style: Typography3dToken.titleMedium,
///   color: theme.colorScheme.onSurfaceVariant,
///   child: SceneColumn3d(children: [SceneText3d('Inbox'), ...]),
/// )
/// ```
///
/// [Material3d] does the same thing for the surface it draws — that is what
/// its `textStyle` and `contentColor` are — so a label inside a component
/// usually needs none of this. Reach for it for a *group* of labels that
/// share a role inside one surface: a list tile's supporting text, a
/// section's captions.
///
/// It merges rather than replaces, exactly as Flutter's
/// `DefaultTextStyle.merge` does, so an enclosing style's family and its
/// inherited colour survive whatever this one does not state.
class SceneTextStyle3d extends StatelessWidget {
  /// Styles [child] with the theme's [style] token, in [color].
  const SceneTextStyle3d({
    super.key,
    required this.style,
    this.color,
    this.merge,
    required this.child,
  });

  /// Which of the type scale's fifteen styles labels below take.
  final Typography3dToken style;

  /// The colour they take, or null to keep whatever is already in force.
  ///
  /// A colour is a `ColorScheme3d` role and depends on what the label is
  /// drawn on, which is why the type scale carries none of its own.
  final Color? color;

  /// Anything else to fold in, applied last so it wins.
  final TextStyle? merge;

  /// The subtree the style covers.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final resolved = Theme3d.of(context).textStyle(style, color: color);
    return DefaultTextStyle.merge(
      style: merge == null ? resolved : resolved.merge(merge),
      child: child,
    );
  }
}
