import 'dart:async' show Timer;
import 'dart:ui' show Color;

import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        State,
        StatefulWidget,
        StatelessWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Alignment3d, EdgeInsets3d, HitTestBehavior3d, Overlay3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneIgnorePointer3d,
        SceneListener3d,
        SceneOverlay3d,
        ScenePadding3d,
        SceneSemantics3d,
        SceneText3d,
        WidgetOverlay3dEntry;

import '../theme/theme.dart';
import 'anchor.dart';
import 'material.dart';
import 'overlay_style.dart';
import 'overlay_support.dart';
import 'reading_direction.dart';

/// A Material tooltip: a short label that appears under whatever it describes
/// while a pointer rests on it.
///
/// ```dart
/// Tooltip3d(
///   message: 'Compose',
///   child: IconButton3d(
///     icon: Icons.edit,
///     semanticLabel: 'Compose',
///     onPressed: _compose,
///   ),
/// )
/// ```
///
/// ## Waiting costs nothing
///
/// A tooltip is a timer for most of its life, and the whole design question is
/// what that timer is allowed to touch. The answer here is **nothing**: a
/// pointer entering starts a `Timer` and a pointer leaving cancels it, and
/// neither calls `setState`, marks anything dirty, or rebuilds the control
/// under the pointer. Only the timer *firing* does anything at all, and what
/// it does is insert an overlay entry. `test/tooltip_test.dart` counts the
/// builds and the layouts of the child across a hover that never matures and
/// asserts both are unmoved.
///
/// That is the same rule `InkWell3d` keeps for its wash, for the same reason:
/// anything on a per-frame or per-hover path that reaches layout turns a
/// smooth interaction into a stutter. See *Staying off the relayout path* in
/// `docs/traps.md`.
///
/// ## Where it appears
///
/// Under the child, [TooltipStyle3d.verticalOffset] below it, anchored with
/// the same machinery a menu uses: an [Anchor3d] around the child and a
/// [Follower3d] around the label, driven by `Layout3d.anchorOffsetTo` on the
/// node tier. It follows the child if the child moves, and it goes away with
/// it.
///
/// **It absorbs no pointer.** The label is wrapped in an `IgnorePointer3d`
/// and the entry has no barrier, because a tooltip that took the ray would
/// be a tooltip that dismissed itself the instant it appeared.
///
/// ## The trigger is hover, and only hover
///
/// Material also shows a tooltip on a long press on a touch screen. That
/// needs a gesture arena entry beside whatever the child already has, and the
/// innermost recognizer wins — so a tooltip around a button would take the
/// button's long press. See *What phase 6 left out*.
class Tooltip3d extends StatefulWidget {
  /// Creates a tooltip over [child].
  const Tooltip3d({
    super.key,
    required this.message,
    required this.child,
    this.style,
    this.semanticLabel,
    this.textDirection,
    this.enabled = true,
  });

  /// What the tooltip says, and what it announces.
  final String message;

  /// The control the tooltip describes.
  final Widget child;

  /// The tokens to draw with, or null for the theme's.
  final TooltipStyle3d? style;

  /// What a screen reader announces, or null for [message].
  ///
  /// The announcement is on the **child's** wrapper rather than on the label,
  /// which is where Flutter puts it too: a reader should hear the description
  /// when it reaches the control, not only when a pointer happens to rest on
  /// it.
  final String? semanticLabel;

  /// The direction the announcement reads in.
  final TextDirection? textDirection;

  /// Whether a hover shows anything.
  final bool enabled;

  @override
  State<Tooltip3d> createState() => _Tooltip3dState();
}

class _Tooltip3dState extends State<Tooltip3d> {
  Anchor3d? _anchor;
  Overlay3d? _overlay;
  WidgetOverlay3dEntry? _entry;
  Timer? _timer;

  /// Whether the label is up.
  bool get isShowing => _entry != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _overlay = SceneOverlay3d.maybeOf(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  TooltipStyle3d get _style =>
      widget.style ?? TooltipStyle3d.of(Theme3d.of(context));

  /// A pointer arrived. Start the wait, and touch nothing else.
  ///
  /// No `setState` here, deliberately: a hover that never matures into a
  /// tooltip must cost exactly one `Timer`.
  void _handleEnter() {
    if (!widget.enabled || isShowing) return;
    _timer?.cancel();
    _timer = Timer(_style.waitDuration, _show);
  }

  /// The pointer left. Cancel the wait, or take the label down.
  void _handleExit() {
    _timer?.cancel();
    _timer = null;
    if (isShowing) _hide();
  }

  void _show() {
    _timer = null;
    final anchor = _anchor;
    final overlay = _overlay;
    if (!mounted || anchor == null || overlay == null || isShowing) return;

    final style = _style;
    final metrics = Layout3dMetricsScope.of(context);
    final entry = _entry = WidgetOverlay3dEntry(
      layer: overlayLayer3d(Theme3d.of(context), metrics),
      debugLabel: 'Tooltip3d',
      // A tooltip is not a route and blocks nothing: no barrier, no focus
      // trap, and the label itself lets every ray through.
      contentBuilder: (context, _) => SceneIgnorePointer3d(
        child: Follower3dWidget(
          anchor: anchor,
          self: Alignment3d.topCenter,
          target: Alignment3d.bottomCenter,
          child: ScenePadding3d(
            // The offset is padding *inside* the follower, so the anchoring
            // stays one corner on another and the gap is a box rather than a
            // second number in the arithmetic.
            padding: metrics.dpInsets(
              EdgeInsets3d.only(top: style.verticalOffset),
            ),
            child: _Tooltip3dLabel(message: widget.message, style: style),
          ),
        ),
      ),
    );
    overlay.insertEntry(entry);

    // A tooltip that outstays its welcome is worse than one that never came.
    _timer = Timer(style.showDuration, _hide);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) => SceneSemantics3d(
    properties: SemanticsProperties(
      tooltip: widget.semanticLabel ?? widget.message,
      textDirection: readingDirection3d(context, widget.textDirection),
    ),
    child: SceneListener3d(
      onPointerEnter: (_) => _handleEnter(),
      onPointerExit: (_) => _handleExit(),
      // Opaque, unlike `InkWell3d`'s listener, and the difference is the
      // point: an ink well is hovered exactly where it is pressable, while a
      // tooltip describes whatever it wraps — including a plain label or an
      // icon, which answers no ray of its own. So the tooltip's own extent is
      // the hover region. The control inside still takes every tap, because
      // children are tested before their parent.
      behavior: HitTestBehavior3d.opaque,
      child: Anchor3dWidget(
        onCreated: (anchor) => _anchor = anchor,
        child: widget.child,
      ),
    ),
  );
}

/// The label a tooltip shows: the smallest surface in the catalogue.
class _Tooltip3dLabel extends StatelessWidget {
  const _Tooltip3dLabel({required this.message, required this.style});

  final String message;
  final TooltipStyle3d style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    return Material3d(
      color: style.container,
      contentColor: style.contentColor,
      shape: style.shape,
      elevation: style.elevation,
      thickness: style.thickness,
      surfaceTint: const Color(0x00000000),
      padding: style.padding,
      alignment: null,
      child: SceneAlign3d(
        alignment: Alignment3d.frontCenter,
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: SceneText3d(
          message,
          style: theme.textStyle(style.textStyle, color: style.contentColor),
        ),
      ),
    );
  }
}
