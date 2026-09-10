import 'package:flutter/widgets.dart'
    show BuildContext, Directionality, TextDirection;

/// The direction a component's own announcement reads in.
///
/// Every component in this catalogue takes a nullable `textDirection` beside
/// its `semanticLabel`, and null has to mean *the enclosing one* rather than
/// *none*. `SemanticsData` **asserts** that a non-empty label, value or hint
/// carries a direction, and the assert fires inside
/// `PipelineOwner.flushSemantics` — so a component that publishes a label and
/// leaves the direction null looks perfectly correct until something switches
/// semantics on, and then throws on every frame. A headless `flutter test`
/// does not switch them on. A screen reader does, and so does an integration
/// test, which is how this was found: the gallery could not draw a single
/// frame with a `Checkbox3d` on it.
///
/// Flutter's own `Semantics` widget resolves the same way, from the same
/// `Directionality`. The final fallback exists because a layout surface can
/// legitimately be mounted with no `Directionality` above it — a scene is not
/// obliged to sit under a `MaterialApp` — and a wrong-but-valid reading order
/// is better than a frame that will not build.
TextDirection readingDirection3d(BuildContext context, TextDirection? stated) =>
    stated ?? Directionality.maybeOf(context) ?? TextDirection.ltr;
