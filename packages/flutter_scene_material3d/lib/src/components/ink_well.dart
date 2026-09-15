import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter/gestures.dart'
    show GestureLongPressCallback, GestureTapCallback;
import 'package:flutter/widgets.dart'
    show
        Action,
        ActivateIntent,
        BuildContext,
        FocusNode,
        Intent,
        State,
        StatefulWidget,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Focus3d,
        HitTestBehavior3d,
        Offset3d,
        PointerEvent3d,
        Size3d,
        TapTarget3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        SceneActions3d,
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
/// Boxes in an order that matters. Outermost is a `TapTarget3d` at
/// Material's 48dp minimum, so a small control is still easy to hit; then an
/// `Actions3d` binding `ActivateIntent`, and a `Focus3d` inside it, so the
/// control is reachable from a keyboard, lights up when it is, and fires on
/// Enter or Space; then a `Listener3d` and a `GestureDetector3d` for the
/// pointer.
///
/// ## Activation from the keyboard
///
/// Flutter's `InkWell` binds `ActivateIntent` and `GestureDetector` does not,
/// and the split is kept: this is the control, so this is where Enter and
/// Space land. An activation is a press with no pointer behind it — the
/// ripple starts from the middle of the control, `onTap` runs, and the ripple
/// is let go. It is enabled only for an enabled control with an [onTap], so a
/// key on a control that would do nothing goes on up the tree instead of
/// being swallowed.
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
/// The press **ripple** is on the same tier, and it is the only thing in the
/// catalogue that writes a uniform every frame. This widget's only part in it
/// is to say *where*: the pointer down carries a position in the box it landed
/// on, `InkController3d.noteRipplePoint` moves that point into the frame of the
/// panel that will be washed, and the ripple itself starts when the press is
/// reported — which is later, and arena-resolved, so a press that becomes a
/// scroll never ripples.
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
    this.onHighlightChanged,
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

  /// Called when a press starts or ends, with Flutter's own spelling.
  ///
  /// A component needs this when one of its *tokens* moves with the press
  /// rather than only its wash — a Material button drops back to its resting
  /// elevation while it is held, so it has to know. Note that a press does
  /// not report itself until Flutter's tap recognizer wins the arena or its
  /// `kPressTimeout` deadline expires, which is correct (a press that becomes
  /// a scroll should never flash a highlight) and means a press and a release
  /// in the same instant report nothing at all.
  final ValueChanged<bool>? onHighlightChanged;

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

  /// The node the focus box uses when the caller gave none.
  ///
  /// Held here rather than left to the box, because an activation has to find
  /// the box it is centred on, and [Focus3d.layoutFor] finds a box from its
  /// node. Skips Flutter's own traversal, as a node the box made would.
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(
        debugLabel: 'InkWell3d',
        skipTraversal: true,
      ));

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ActivateIntent: _ActivateInkWell3d(this),
  };

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
    // After the focus box, which the element tree has already unmounted: a
    // child is taken down before its parent's state is disposed.
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  /// A press with no pointer behind it, from Enter or Space.
  ///
  /// The ripple is centred on the control by noting its middle first — a
  /// point left over from an earlier pointer press that never became a tap
  /// would otherwise be where a keyboard press ripples from. The pressed state
  /// goes on and off around [InkWell3d.onTap], which starts the ripple and
  /// lets it go; [InkWell3d.onHighlightChanged] is not called, because Flutter
  /// does not highlight a keyboard activation either.
  void _activate() {
    final box = Focus3d.layoutFor(_focusNode);
    if (box != null && box.hasSize) {
      _ink?.noteRipplePoint(
        box,
        Offset3d(box.size.width / 2.0, box.size.height / 2.0, 0.0),
      );
    }
    _set(Material3dState.pressed, true);
    widget.onTap?.call();
    _set(Material3dState.pressed, false);
  }

  void _set(Material3dState state, bool active) =>
      _ink?.setInkState(state, active: active && widget.enabled);

  void _handleHighlight(bool pressed) {
    _set(Material3dState.pressed, pressed);
    widget.onHighlightChanged?.call(pressed && widget.enabled);
  }

  /// Notes where the finger landed, in the panel's own frame.
  ///
  /// On the *down* rather than on the highlight, because by the time the
  /// arena has reported a press the event carrying the position is gone —
  /// `onTapDown` reports one too, but in logical pixels and in the gesture
  /// detector's frame, while this one is in world units and exact for a
  /// surface seen at any angle. The controller does the change of frame.
  void _handleDown(PointerEvent3d event) {
    if (!widget.enabled) return;
    _ink?.noteRipplePoint(event.entry.layout, event.localPosition);
  }

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
      child: SceneActions3d(
        actions: _actions,
        child: SceneFocus3d(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          focusOnPointerDown: widget.focusOnPointerDown,
          canRequestFocus: enabled,
          onFocusChange: _handleFocusChange,
          child: SceneListener3d(
            onPointerEnter: (_) => _handleHover(true),
            onPointerExit: (_) => _handleHover(false),
            onPointerDown: _handleDown,
            // Defers to the gesture detector below, which is opaque: a control
            // is hovered exactly where it is pressable.
            behavior: HitTestBehavior3d.deferToChild,
            child: SceneGestureDetector3d(
              onTapDown: enabled ? (_) => _handleHighlight(true) : null,
              onTapUp: enabled ? (_) => _handleHighlight(false) : null,
              onTapCancel: enabled ? () => _handleHighlight(false) : null,
              onTap: enabled ? widget.onTap : null,
              onDoubleTap: enabled ? widget.onDoubleTap : null,
              onLongPress: enabled ? widget.onLongPress : null,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Enter and Space on an [InkWell3d].
class _ActivateInkWell3d extends Action<ActivateIntent> {
  _ActivateInkWell3d(this.state);

  final _InkWell3dState state;

  @override
  bool isEnabled(ActivateIntent intent) =>
      state.mounted && state.widget.enabled && state.widget.onTap != null;

  @override
  Object? invoke(ActivateIntent intent) {
    state._activate();
    return null;
  }
}
