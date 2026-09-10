import 'dart:async' show Completer, Timer;
import 'dart:collection' show Queue;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        InheritedWidget,
        State,
        StatefulWidget,
        StatelessWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        Constraints3d,
        CrossAxisAlignment3d,
        MainAxisSize3d,
        Overlay3d,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneConstrainedBox3d,
        SceneIgnorePointer3d,
        SceneOverlay3d,
        ScenePadding3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneText3d,
        WidgetOverlay3dEntry;

import '../theme/theme.dart';
import 'ink_well.dart';
import 'material.dart';
import 'overlay_style.dart';
import 'overlay_support.dart';
import 'reading_direction.dart';

/// Why a snack bar went away.
enum SnackBar3dClosedReason {
  /// Its duration ran out.
  timeout,

  /// Its action was pressed.
  action,

  /// Something asked for it to be taken down.
  remove,

  /// The messenger left the tree.
  dispose,
}

/// A handle on one shown snack bar.
///
/// The 3D analogue of Flutter's `ScaffoldFeatureController`: [closed]
/// completes with the reason the bar went away, and [close] takes it down
/// early.
class SnackBar3dController {
  SnackBar3dController._(this.bar);

  /// The bar this controller is for.
  final SnackBar3d bar;

  final Completer<SnackBar3dClosedReason> _closed =
      Completer<SnackBar3dClosedReason>();

  void Function(SnackBar3dClosedReason reason)? _close;

  /// Completes when the bar has gone away, with the reason.
  Future<SnackBar3dClosedReason> get closed => _closed.future;

  /// Whether the bar has already gone.
  bool get isClosed => _closed.isCompleted;

  /// Takes the bar down now.
  ///
  /// Safe to call twice, and safe to call on a bar that is still queued: a
  /// queued bar is dropped without ever being shown.
  void close([SnackBar3dClosedReason reason = SnackBar3dClosedReason.remove]) =>
      _close?.call(reason);

  void _finish(SnackBar3dClosedReason reason) {
    _close = null;
    if (!_closed.isCompleted) _closed.complete(reason);
  }
}

/// The queue of snack bars, one at a time.
///
/// Flutter's `ScaffoldMessenger`, in the shape a catalogue over `Overlay3d`
/// can have it. Put one around whatever shows messages — inside the
/// `SceneOverlay3d` and outside the `Scaffold3d`, which is the order Flutter's
/// own `MaterialApp` uses:
///
/// ```dart
/// SceneOverlay3d(
///   child: ScaffoldMessenger3d(
///     child: Scaffold3d(body: page),
///   ),
/// )
///
/// // ... from anywhere below it:
/// ScaffoldMessenger3d.of(context).show(
///   const SnackBar3d(message: 'Saved', actionLabel: 'Undo'),
/// );
/// ```
///
/// ## One at a time, and what that costs
///
/// [show] returns at once and the bar may not appear for four seconds. That
/// is the whole point of a messenger: two things reporting themselves in the
/// same instant produce two messages one after the other rather than one on
/// top of the other. Each is up for its own duration, and
/// [SnackBar3dController.closed] is how a caller learns which way it went.
///
/// A queued bar that is closed before its turn is **dropped**, not shown, and
/// its future completes all the same. So does every bar still waiting when
/// the messenger leaves the tree.
///
/// ## The timing is a `Timer`, and nothing else
///
/// There is no animation here — this package has no motion tokens yet, and
/// `Route3dTransition.none` is the honest default the layout package ships.
/// A bar appears, waits and goes. The waiting is one `Timer`, which touches
/// no layout at all: showing and hiding a bar inserts and removes an overlay
/// entry, and the four seconds in between cost nothing.
class ScaffoldMessenger3d extends StatefulWidget {
  /// Creates a messenger over [child].
  const ScaffoldMessenger3d({super.key, required this.child});

  /// What the messenger's queue serves.
  final Widget child;

  /// The messenger above [context].
  ///
  /// Throws when there is none, which is a programming error: something asked
  /// to show a message with nowhere to put it.
  static ScaffoldMessenger3dState of(BuildContext context) {
    final state = maybeOf(context);
    assert(
      state != null,
      'ScaffoldMessenger3d.of found no ScaffoldMessenger3d above this '
      'context. Wrap the part of the tree that shows messages in one, inside '
      'the SceneOverlay3d that will hold them.',
    );
    return state!;
  }

  /// The messenger above [context], or null.
  static ScaffoldMessenger3dState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ScaffoldMessenger3dScope>()
      ?.messenger;

  @override
  State<ScaffoldMessenger3d> createState() => ScaffoldMessenger3dState();
}

/// The queue behind a [ScaffoldMessenger3d].
class ScaffoldMessenger3dState extends State<ScaffoldMessenger3d> {
  final Queue<SnackBar3dController> _queue = Queue<SnackBar3dController>();

  Overlay3d? _overlay;
  WidgetOverlay3dEntry? _entry;
  Timer? _timer;

  /// The bar on screen, or null when there is none.
  SnackBar3dController? get current => _queue.isEmpty ? null : _queue.first;

  /// How many bars are waiting, the one on screen included.
  int get length => _queue.length;

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
    for (final controller in _queue) {
      controller._finish(SnackBar3dClosedReason.dispose);
    }
    _queue.clear();
    super.dispose();
  }

  /// Puts [bar] at the back of the queue, and shows it when its turn comes.
  SnackBar3dController show(SnackBar3d bar) {
    final controller = SnackBar3dController._(bar);
    controller._close = (reason) => _closeController(controller, reason);
    _queue.addLast(controller);
    if (_queue.length == 1) _present();
    return controller;
  }

  /// Takes the bar on screen down now.
  void removeCurrent([
    SnackBar3dClosedReason reason = SnackBar3dClosedReason.remove,
  ]) => current?.close(reason);

  /// Empties the queue, the bar on screen included.
  void clear([SnackBar3dClosedReason reason = SnackBar3dClosedReason.remove]) {
    while (_queue.isNotEmpty) {
      _closeController(_queue.last, reason);
    }
  }

  void _closeController(
    SnackBar3dController controller,
    SnackBar3dClosedReason reason,
  ) {
    if (controller.isClosed) return;
    final wasCurrent = identical(controller, current);
    if (!_queue.remove(controller)) {
      controller._finish(reason);
      return;
    }
    controller._finish(reason);
    // A bar closed before its turn is dropped from the queue and nothing
    // else happens; only the one on screen has anything to take down.
    if (!wasCurrent) return;
    _dismiss();
    _present();
  }

  /// Takes whatever is on screen off it.
  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  /// Puts the head of the queue up, if there is one and nothing is up.
  void _present() {
    if (_entry != null) return;
    final controller = current;
    final overlay = _overlay;
    if (controller == null || overlay == null) return;

    final entry = _entry = WidgetOverlay3dEntry(
      layer: overlayLayer3d(
        Theme3d.of(context),
        Layout3dMetricsScope.of(context),
      ),
      debugLabel: 'SnackBar3d',
      contentBuilder: (context, _) => SceneAlign3d(
        // Bottom, and on the **front** face: `Alignment3d.bottomCenter`
        // centres in depth as well, which would put the bar inside the lift
        // that was meant to carry it in front of the screen.
        alignment: const Alignment3d(0, 1, -1),
        child: _SnackBar3dFrame(
          bar: controller.bar,
          onAction: () {
            controller.bar.onAction?.call();
            _closeController(controller, SnackBar3dClosedReason.action);
          },
        ),
      ),
    );
    overlay.insertEntry(entry);

    final duration =
        controller.bar.duration ??
        SnackBarStyle3d.of(Theme3d.of(context)).displayDuration;
    _timer = Timer(duration, () {
      _timer = null;
      _closeController(controller, SnackBar3dClosedReason.timeout);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ScaffoldMessenger3dScope(messenger: this, child: widget.child);
}

class _ScaffoldMessenger3dScope extends InheritedWidget {
  const _ScaffoldMessenger3dScope({
    required this.messenger,
    required super.child,
  });

  final ScaffoldMessenger3dState messenger;

  @override
  bool updateShouldNotify(_ScaffoldMessenger3dScope oldWidget) =>
      !identical(messenger, oldWidget.messenger);
}

/// A Material snack bar: a short message near the bottom of the screen, with
/// at most one action on it.
///
/// A description rather than a widget in the tree: hand one to
/// [ScaffoldMessenger3dState.show] and the messenger builds it when its turn
/// comes. It is a `StatelessWidget` all the same, so it can also be put in a
/// layout directly — which is what the tests and the render probe do.
///
/// The message is a **string** rather than a widget, for the reason
/// `ListTile3d`'s title is: a `Semantics3d` gathers nothing from the labels
/// below it, and a message nobody can hear is not a message.
class SnackBar3d extends StatelessWidget {
  /// Creates a snack bar.
  const SnackBar3d({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.duration,
    this.style,
    this.semanticLabel,
    this.textDirection,
  }) : assert(
         actionLabel == null || onAction != null,
         'A snack bar with an action label needs something for it to do.',
       );

  /// What the bar says.
  final String message;

  /// The label of the one action, or null for a bar with none.
  ///
  /// Material allows exactly one. A second would be a dialog.
  final String? actionLabel;

  /// What the action does. Pressing it also closes the bar.
  final VoidCallback? onAction;

  /// How long the bar stays up, or null for the style's four seconds.
  final Duration? duration;

  /// The tokens to draw with, or null for the theme's.
  final SnackBarStyle3d? style;

  /// What a screen reader announces, or null for [message].
  final String? semanticLabel;

  /// The direction the announcement reads in.
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) =>
      _SnackBar3dFrame(bar: this, onAction: onAction);
}

/// The bar itself, with the action wired to whoever owns it.
///
/// Separate from [SnackBar3d] because the messenger has to close the bar when
/// the action is pressed, and the description a caller wrote knows nothing
/// about the messenger holding it.
class _SnackBar3dFrame extends StatelessWidget {
  const _SnackBar3dFrame({required this.bar, this.onAction});

  final SnackBar3d bar;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = bar.style ?? SnackBarStyle3d.of(theme);
    final hasAction = bar.actionLabel != null && onAction != null;

    final content = SceneRow3d(
      mainAxisSize: MainAxisSize3d.min,
      crossAxisAlignment: CrossAxisAlignment3d.center,
      spacing: metrics.dp(16),
      children: <Widget>[
        SceneIgnorePointer3d(
          child: SceneText3d(
            bar.message,
            style: theme.textStyle(
              resolved.textStyle,
              color: resolved.contentColor,
            ),
          ),
        ),
        if (hasAction)
          // The action is a second affordance *inside* a component, which
          // `docs/traps.md` says gets neither a 48dp reach nor a wash of its
          // own — the enclosing Material3d would light the whole bar up. A
          // bar is `raised`, deep enough to afford the answer a navigation
          // destination uses: a thin slab of its own, standing clear.
          Material3d(
            color: const Color(0x00000000),
            contentColor: resolved.actionColor,
            shape: theme.shape.extraSmall,
            elevation: 2 * theme.thickness.thin,
            thickness: theme.thickness.thin,
            surfaceTint: const Color(0x00000000),
            alignment: null,
            child: SceneAlign3d(
              alignment: Alignment3d.frontCenter,
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: SceneSemantics3d(
                properties: SemanticsProperties(
                  button: true,
                  enabled: true,
                  label: bar.actionLabel,
                  textDirection: readingDirection3d(context, bar.textDirection),
                  onTap: onAction,
                ),
                child: InkWell3d(
                  minimumSize: Size3d.zero,
                  onTap: onAction,
                  child: ScenePadding3d(
                    padding: metrics.dpInsets(resolved.actionPadding),
                    child: SceneIgnorePointer3d(
                      child: SceneText3d(
                        bar.actionLabel!,
                        style: theme.textStyle(
                          resolved.textStyle,
                          color: resolved.actionColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return SceneSemantics3d(
      properties: SemanticsProperties(
        liveRegion: true,
        label: bar.semanticLabel ?? bar.message,
        textDirection: readingDirection3d(context, bar.textDirection),
      ),
      child: ScenePadding3d(
        padding: metrics.dpInsets(resolved.margin),
        child: SceneConstrainedBox3d(
          constraints: Constraints3d(
            minHeight: metrics.dp(resolved.minHeight),
            maxWidth: metrics.dp(resolved.maxWidth),
          ),
          child: Material3d(
            color: resolved.container,
            contentColor: resolved.contentColor,
            shape: resolved.shape,
            elevation: resolved.elevation,
            thickness: resolved.thickness,
            surfaceTint: const Color(0x00000000),
            padding: resolved.padding,
            alignment: null,
            child: SceneAlign3d(
              alignment: Alignment3d.frontCenter,
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
