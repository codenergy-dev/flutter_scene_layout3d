import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter/gestures.dart'
    show GestureLongPressCallback, GestureTapCallback;
import 'package:flutter/widgets.dart'
    show BuildContext, FocusNode, State, StatefulWidget, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show HitTestBehavior3d, Size3d, TapTarget3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        SceneFocus3d,
        SceneGestureDetector3d,
        SceneListener3d,
        SceneTapTarget3d;

import '../tokens/state_layer.dart';
import 'ink.dart';

/// The interactive half of a Material surface: a tap target, a focusable box,
/// and the hover, focus and press that light the [Material3d] above it up.
///
/// ```dart
/// Material3d(
///   color: theme.colorScheme.primary,
///   contentColor: theme.colorScheme.onPrimary,
///   shape: theme.shape.full,
///   child: InkWell3d(
///     onTap: _submit,
///     child: const SceneText3d('Continue'),
///   ),
/// )
/// ```
///
/// Three boxes, in an order that matters. Outermost is a `TapTarget3d` at
/// Material's 48dp minimum, so a small control is still easy to hit; then a
/// `Focus3d`, so the control is reachable from a keyboard and lights up when
/// it is; then a `Listener3d` and a `GestureDetector3d` for the pointer.
///
/// ## The tier it must not leave
///
/// **A hover, a focus or a press rebuilds nothing and lays nothing out.**
/// This widget never calls `setState` for a state change; it calls
/// [InkController3d.setInkState] on the controller the enclosing `Material3d`
/// published, which assigns `DecoratedBox3d.stateLayer` and asks for a
/// repaint. That is the whole design of the decoration layer — a pointer
/// crossing a list of twenty tiles costs twenty uniform writes and no layout
/// at all — and a test in this package states it in those terms, by counting
/// builds and layouts across a hover.
///
/// It follows that a component whose *tokens* change with a state (a filled
/// button is a different colour when pressed, not merely washed) cannot use
/// this channel for that half. It rebuilds, deliberately, and pays for it.
///
/// ## Two sharp edges inherited from the protocol
///
/// **The 48dp target grows the ray region and not the box.** Layout,
/// intrinsics, `ensureVisible3d` and semantics all see the smaller rectangle,
/// which is what keeps neighbours from moving apart when a dense toolbar pads
/// its targets. Announce a label with a `SceneSemantics3d` around the whole
/// control, not around the target.
///
/// **A `Text3d` answers hit tests on its own account.** A label inside a
/// control is not a problem — the gesture detector below this widget is
/// opaque and is found first — but a label that has to let a ray through to
/// something behind it wants a `SceneIgnorePointer3d`.
class InkWell3d extends StatefulWidget {
  /// Creates an interactive region over [child].
  const InkWell3d({
    super.key,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.focusOnPointerDown = true,
    this.enabled = true,
    this.minimumSize,
    this.child,
  });

  /// Called when the control is tapped.
  final GestureTapCallback? onTap;

  /// Called when the control is tapped twice in quick succession.
  final GestureTapCallback? onDoubleTap;

  /// Called when the control is long-pressed.
  final GestureLongPressCallback? onLongPress;

  /// Called when the pointer arrives over the control or leaves it.
  final ValueChanged<bool>? onHover;

  /// Called when the control gains or loses the focus.
  final ValueChanged<bool>? onFocusChange;

  /// The node holding this control's place in the focus tree, or null for one
  /// of its own.
  final FocusNode? focusNode;

  /// Whether the control takes the focus as soon as it is laid out.
  final bool autofocus;

  /// Whether a press focuses the control, which it does by default.
  ///
  /// The protocol's own default, and Flutter's on a desktop. It has a visible
  /// consequence here that is worth knowing before it surprises you: a
  /// pressed control ends up **focused**, so the focus wash stays after the
  /// pointer is lifted. Flutter hides that behind
  /// `FocusManager.highlightMode`, which distinguishes a focus taken by a
  /// pointer from one taken by a key; nothing in this stack reads that yet,
  /// so a control that should not glow after a click sets this false.
  final bool focusOnPointerDown;

  /// Whether the control responds at all.
  ///
  /// A disabled control takes no focus, lights up for nothing, and drops any
  /// state it was in the moment it is disabled — so a pointer that was
  /// hovering a button when it went disabled does not leave a wash behind.
  /// It does *not* dim itself: there is no opacity in this stack, and a
  /// disabled component is drawn by substituting `disabledContainer` and
  /// `disabledContent` for its colours, which is the enclosing component's
  /// job rather than this one's.
  final bool enabled;

  /// The smallest area the pointer is given, in **world units**, or null for
  /// [TapTarget3d.materialMinimum] resolved through the surface's metrics.
  ///
  /// The odd unit is the layout package's: every extent there is in world
  /// units, and the 48dp default is converted at hit-test time so that a
  /// camera-bound surface keeps its targets 48dp as the view changes. Leave
  /// it null unless a control genuinely wants a different reach.
  final Size3d? minimumSize;

  /// The control's contents.
  final Widget? child;

  @override
  State<InkWell3d> createState() => _InkWell3dState();
}

class _InkWell3dState extends State<InkWell3d> {
  InkController3d? _ink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Looked up once, here, rather than in every callback: this is what keeps
    // a hover off the build path entirely.
    _ink = InkController3d.maybeOf(context);
  }

  @override
  void didUpdateWidget(InkWell3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) _ink?.clearInkStates();
  }

  @override
  void dispose() {
    // The controller outlives this widget — it belongs to the Material3d
    // above — so a control taken out of the tree mid-hover has to say so, or
    // the panel keeps the wash forever.
    _ink?.clearInkStates();
    super.dispose();
  }

  void _set(Material3dState state, bool active) =>
      _ink?.setInkState(state, active: active && widget.enabled);

  void _handleFocusChange(bool focused) {
    _set(Material3dState.focused, focused);
    widget.onFocusChange?.call(focused);
  }

  void _handleHover(bool hovered) {
    _set(Material3dState.hovered, hovered);
    widget.onHover?.call(hovered);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return SceneTapTarget3d(
      minimumSize: widget.minimumSize,
      child: SceneFocus3d(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        focusOnPointerDown: widget.focusOnPointerDown,
        canRequestFocus: enabled,
        onFocusChange: _handleFocusChange,
        child: SceneListener3d(
          onPointerEnter: (_) => _handleHover(true),
          onPointerExit: (_) => _handleHover(false),
          // Defers to the gesture detector below, which is opaque: a control
          // is hovered exactly where it is pressable.
          behavior: HitTestBehavior3d.deferToChild,
          child: SceneGestureDetector3d(
            onTapDown: enabled
                ? (_) => _set(Material3dState.pressed, true)
                : null,
            onTapUp: enabled
                ? (_) => _set(Material3dState.pressed, false)
                : null,
            onTapCancel: enabled
                ? () => _set(Material3dState.pressed, false)
                : null,
            onTap: enabled ? widget.onTap : null,
            onDoubleTap: enabled ? widget.onDoubleTap : null,
            onLongPress: enabled ? widget.onLongPress : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
