import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, IterableProperty;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show
        Action,
        ActionDispatcher,
        ActivateIntent,
        AxisDirection,
        DirectionalFocusIntent,
        DismissIntent,
        DoNothingAction,
        DoNothingAndStopPropagationIntent,
        DoNothingIntent,
        FocusManager,
        Intent,
        KeyEventResult,
        NextFocusIntent,
        PreviousFocusIntent,
        ScrollIncrementType,
        ScrollIntent,
        ShortcutActivator,
        SingleActivator,
        TraversalDirection,
        VoidCallbackAction,
        VoidCallbackIntent;

import '../geometry/offset3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import '../scroll/scrollable.dart';
import 'focus.dart';

/// Maps key presses to intents for the boxes below it, the 3D analogue of
/// Flutter's `Shortcuts`.
///
/// The vocabulary is Flutter's own, unchanged: a [ShortcutActivator] — most
/// often a [SingleActivator] — names the keys, and an [Intent] names what they
/// mean. What an intent *does* is an [Actions3d]'s business, looked up from
/// the box that holds the focus, so the same Enter can submit a form in one
/// place and open a menu in another.
///
/// ```dart
/// Shortcuts3d(
///   shortcuts: const <ShortcutActivator, Intent>{
///     SingleActivator(LogicalKeyboardKey.keyS, meta: true): SaveIntent(),
///   },
///   child: Actions3d(
///     actions: <Type, Action<Intent>>{
///       SaveIntent: CallbackAction<SaveIntent>(onInvoke: (_) => save()),
///     },
///     child: editor,
///   ),
/// )
/// ```
///
/// ## Why this is not Flutter's widget
///
/// Two structural reasons, and neither is a missing feature. Flutter looks the
/// action up from `primaryFocus.context`, and a [Focus3d]'s node has no
/// context. And a key walks the *focus* tree, where a [Focus3d]'s ancestors are
/// its scope and the surface's scope rather than the boxes around it — so a
/// `Shortcuts` widget anywhere in the application never sees a key meant for a
/// box on a plane. The walk is re-expressed over the layout tree instead; see
/// [Actions3d.handleKeyEvent].
///
/// ## The defaults
///
/// Every key walk ends at [defaults], which is `WidgetsApp`'s own map for the
/// non-web platforms: Enter, Space and friends activate, Escape dismisses,
/// Tab and the arrows move focus, and Page Up and Page Down scroll. Override
/// one by mapping its activator nearer the focused box — to another intent, or
/// to [DoNothingAndStopPropagationIntent] to switch it off.
///
/// A detached overlay entry is a surface of its own, so its walk ends at its
/// own root and does not pass through the panel that opened it: a
/// `Shortcuts3d` around a screen does not reach a dialog floating in front of
/// that screen.
class Shortcuts3d extends ProxyLayout3d {
  /// Creates a box that maps [shortcuts] for its subtree.
  Shortcuts3d({
    Map<ShortcutActivator, Intent> shortcuts =
        const <ShortcutActivator, Intent>{},
    super.child,
    super.name,
  }) : _shortcuts = shortcuts;

  Map<ShortcutActivator, Intent> _shortcuts;

  /// The bindings this box adds.
  ///
  /// Costs nothing to change: nothing reads it until a key arrives.
  // ignore: unnecessary_getters_setters
  Map<ShortcutActivator, Intent> get shortcuts => _shortcuts;

  set shortcuts(Map<ShortcutActivator, Intent> value) {
    _shortcuts = value;
  }

  /// The bindings every key walk ends at, which are `WidgetsApp`'s.
  static const Map<ShortcutActivator, Intent>
  defaults = <ShortcutActivator, Intent>{
    // Activation.
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),

    // Dismissal.
    SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),

    // Traversal.
    SingleActivator(LogicalKeyboardKey.tab): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.tab, shift: true): PreviousFocusIntent(),
    SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
      TraversalDirection.left,
    ),
    SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
      TraversalDirection.right,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
      TraversalDirection.down,
    ),
    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
      TraversalDirection.up,
    ),

    // Scrolling.
    SingleActivator(LogicalKeyboardKey.arrowUp, control: true): ScrollIntent(
      direction: AxisDirection.up,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown, control: true): ScrollIntent(
      direction: AxisDirection.down,
    ),
    SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): ScrollIntent(
      direction: AxisDirection.left,
    ),
    SingleActivator(LogicalKeyboardKey.arrowRight, control: true): ScrollIntent(
      direction: AxisDirection.right,
    ),
    SingleActivator(LogicalKeyboardKey.pageUp): ScrollIntent(
      direction: AxisDirection.up,
      type: ScrollIncrementType.page,
    ),
    SingleActivator(LogicalKeyboardKey.pageDown): ScrollIntent(
      direction: AxisDirection.down,
      type: ScrollIncrementType.page,
    ),
  };

  /// The intent [event] maps to in [shortcuts], or null.
  Intent? intentFor(KeyEvent event) => _find(_shortcuts, event);

  static Intent? _find(Map<ShortcutActivator, Intent> map, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    for (final binding in map.entries) {
      if (binding.key.accepts(event, keyboard)) return binding.value;
    }
    return null;
  }

  /// Passes the ray straight to the child, without gating it on this box's
  /// extent.
  ///
  /// A key binding has nothing to do with pointers, and a box the size of a
  /// control wrapped around a `TapTarget3d` would otherwise cut off the reach
  /// the target grants beyond that size.
  @override
  bool hitTest(HitTestResult3d result, {required Ray3d ray}) =>
      hasSize && hitTestChildren(result, ray: ray);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      IterableProperty<String>(
        'shortcuts',
        _shortcuts.entries.map((e) => '${e.key} → ${e.value}'),
        ifEmpty: 'none',
      ),
    );
  }
}

/// Binds intents to what they do for the boxes below it, the 3D analogue of
/// Flutter's `Actions`.
///
/// Keyed by the intent's type, holding Flutter's own [Action]s — a
/// `CallbackAction` works here unchanged. A control binds what it can do:
/// `InkWell3d` in the Material catalogue binds [ActivateIntent], and a trapping
/// `Overlay3dEntry` binds [DismissIntent].
///
/// Lookup starts at the box that holds the focus and takes the **nearest**
/// binding for the intent's type, falling back to [defaults] above the root.
/// A nearer binding that is disabled is not skipped over, which is Flutter's
/// rule too: the key goes on up the focus walk instead, as though nothing had
/// mapped it.
class Actions3d extends ProxyLayout3d {
  /// Creates a box that binds [actions] for its subtree.
  Actions3d({
    Map<Type, Action<Intent>> actions = const <Type, Action<Intent>>{},
    super.child,
    super.name,
  }) : _actions = actions;

  Map<Type, Action<Intent>> _actions;

  /// The bindings this box adds.
  ///
  /// Costs nothing to change: nothing reads it until an intent is invoked.
  // ignore: unnecessary_getters_setters
  Map<Type, Action<Intent>> get actions => _actions;

  set actions(Map<Type, Action<Intent>> value) {
    _actions = value;
  }

  /// The bindings every lookup ends at.
  ///
  /// The actions `WidgetsApp` supplies, re-expressed for a plane where
  /// Flutter's need a `BuildContext`. Tab and the arrows move focus with
  /// [Focus3dTraversal], inside [Focus3dTraversal.traversalRootFor] the
  /// focused box, so a dialog cycles itself; a [ScrollIntent] animates the
  /// nearest enclosing [Scrollable3d] on its axis by Flutter's increments —
  /// fifty logical pixels a line, eighty per cent of the window a page — over
  /// Flutter's hundred milliseconds. [ActivateIntent] and [DismissIntent] have
  /// no default, as in Flutter: a control supplies the first, a modal the
  /// second.
  static final Map<Type, Action<Intent>> defaults = <Type, Action<Intent>>{
    DoNothingIntent: DoNothingAction(),
    DoNothingAndStopPropagationIntent: DoNothingAction(consumesKey: false),
    VoidCallbackIntent: VoidCallbackAction(),
    NextFocusIntent: _TraverseAction<NextFocusIntent>(forward: true),
    PreviousFocusIntent: _TraverseAction<PreviousFocusIntent>(forward: false),
    DirectionalFocusIntent: _DirectionalFocusAction(),
    ScrollIntent: _ScrollAction(),
  };

  /// The action bound to [intent]'s type nearest [from], or null.
  static Action<Intent>? maybeFind(Layout3d from, Intent intent) {
    final type = intent.runtimeType;
    Layout3d? node = from;
    while (node != null) {
      if (node is Actions3d) {
        final action = node._actions[type];
        if (action != null) return action;
      }
      node = node.parent;
    }
    return defaults[type];
  }

  /// Invokes the action bound to [intent] nearest [from], if it is enabled.
  ///
  /// Answers whether it was enabled and what it returned — Flutter's
  /// `ActionDispatcher.invokeActionIfEnabled`, which is what does the
  /// invoking, so an action's listeners hear about it exactly as they would
  /// in a widget tree. The way a gamepad handler or a menu of commands fires
  /// an intent without a key behind it.
  static (bool, Object?) maybeInvoke(Layout3d from, Intent intent) {
    final action = maybeFind(from, intent);
    if (action == null) return (false, null);
    return const ActionDispatcher().invokeActionIfEnabled(action, intent);
  }

  /// Offers [event] to the key bindings around [from], the box that holds
  /// primary focus.
  ///
  /// The walk behind every key that reaches a plane. It goes up from [from],
  /// nearest first, and at each box:
  ///
  ///  * a [Focus3d] other than [from] with an `onKeyEvent` is offered the key,
  ///    which is how a `Focus3d` around a region sees the keys of the controls
  ///    inside it — the bubbling Flutter's `Focus` has, and which the focus
  ///    tree cannot give here because every node hangs flat under its scope;
  ///  * a [Shortcuts3d] that maps the key names an intent, whose action is
  ///    found from [from] with [maybeFind] and invoked if enabled.
  ///
  /// The first answer that is not [KeyEventResult.ignored] ends the walk.
  /// After the root, [Shortcuts3d.defaults] has the same chance. [from]'s own
  /// `onKeyEvent` is not called here: it is the caller, and has already had
  /// the key.
  static KeyEventResult handleKeyEvent(Layout3d from, KeyEvent event) {
    Layout3d? node = from;
    while (node != null) {
      if (node is Focus3d && !identical(node, from)) {
        final result = node.onKeyEvent?.call(node.focusNode, event);
        if (result != null && result != KeyEventResult.ignored) return result;
      }
      if (node is Shortcuts3d) {
        final result = _invokeFor(from, node.intentFor(event));
        if (result != KeyEventResult.ignored) return result;
      }
      node = node.parent;
    }
    return _invokeFor(from, Shortcuts3d._find(Shortcuts3d.defaults, event));
  }

  static KeyEventResult _invokeFor(Layout3d from, Intent? intent) {
    if (intent == null) return KeyEventResult.ignored;
    final action = maybeFind(from, intent);
    if (action == null) return KeyEventResult.ignored;
    final (enabled, result) = const ActionDispatcher().invokeActionIfEnabled(
      action,
      intent,
    );
    return enabled
        ? action.toKeyEventResult(intent, result)
        : KeyEventResult.ignored;
  }

  /// Passes the ray straight to the child; see [Shortcuts3d.hitTest].
  @override
  bool hitTest(HitTestResult3d result, {required Ray3d ray}) =>
      hasSize && hitTestChildren(result, ray: ray);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      IterableProperty<String>(
        'actions',
        _actions.keys.map((type) => '$type'),
        ifEmpty: 'none',
      ),
    );
  }
}

/// The box holding primary focus, when it is a box on a plane.
///
/// Flutter's default actions read `primaryFocus` rather than being handed a
/// context, and these do the same, which is what keeps them invokable from
/// [Actions3d.maybeInvoke] with no key behind the call.
Layout3d? _focusedLayout() {
  final node = FocusManager.instance.primaryFocus;
  return node == null ? null : Focus3d.layoutFor(node);
}

/// Tab and Shift-Tab: the next or previous box in tree order, inside the
/// scope that holds the focus.
class _TraverseAction<T extends Intent> extends Action<T> {
  _TraverseAction({required this.forward});

  final bool forward;

  @override
  bool isEnabled(T intent) => _focusedLayout() != null;

  @override
  Object? invoke(T intent) {
    final from = _focusedLayout();
    if (from == null) return null;
    // A scope or a surface holding the focus itself has no current box, and
    // the walk starts from the first one.
    final current = from is Focus3d ? from : null;
    final root = Focus3dTraversal.traversalRootFor(from);
    const traversal = Focus3dTraversal();
    final target = forward
        ? traversal.next(root, current)
        : traversal.previous(root, current);
    target?.requestFocus();
    return null;
  }
}

/// The arrows: the nearest box that way on the plane, or the first box when
/// nothing is focused yet.
class _DirectionalFocusAction extends Action<DirectionalFocusIntent> {
  @override
  bool isEnabled(DirectionalFocusIntent intent) => _focusedLayout() != null;

  @override
  Object? invoke(DirectionalFocusIntent intent) {
    final from = _focusedLayout();
    if (from == null) return null;
    final root = Focus3dTraversal.traversalRootFor(from);
    const traversal = Focus3dTraversal();
    if (from is Focus3d) {
      traversal.moveInDirection(root, from, intent.direction);
    } else {
      traversal.firstFocus(root)?.requestFocus();
    }
    return null;
  }
}

/// Page Up, Page Down and the control-arrows: the nearest enclosing view on
/// the intent's axis, by a line or a page.
class _ScrollAction extends Action<ScrollIntent> {
  /// Flutter's `ScrollAction` figures.
  static const double _lineLogicalPixels = 50.0;
  static const double _pageFraction = 0.8;
  static const Duration _duration = Duration(milliseconds: 100);

  @override
  bool isEnabled(ScrollIntent intent) => _viewFor(intent) != null;

  @override
  Object? invoke(ScrollIntent intent) {
    final view = _viewFor(intent);
    if (view == null) return null;
    final controller = view.controller;
    final increment = switch (intent.type) {
      ScrollIncrementType.line =>
        _lineLogicalPixels * controller.unitsPerLogicalPixel,
      ScrollIncrementType.page => _pageFraction * controller.viewportExtent,
    };
    final sign = switch (intent.direction) {
      AxisDirection.up || AxisDirection.left => -1.0,
      AxisDirection.down || AxisDirection.right => 1.0,
    };
    controller.animateTo(
      controller.pointerScrollTarget(sign * increment),
      duration: _duration,
      curve: Curves.easeInOut,
    );
    return null;
  }

  /// The nearest view around the focused box that scrolls along the intent's
  /// axis and has somewhere to go.
  static Scrollable3d? _viewFor(ScrollIntent intent) {
    final axis = switch (intent.direction) {
      AxisDirection.up || AxisDirection.down => Axis3d.vertical,
      AxisDirection.left || AxisDirection.right => Axis3d.horizontal,
    };
    Layout3d? node = _focusedLayout();
    while (node != null) {
      if (node is Scrollable3d) {
        final view = node as Scrollable3d;
        if (view.scrollAxis == axis && view.controller.canScroll) return view;
      }
      node = node.parent;
    }
    return null;
  }
}
