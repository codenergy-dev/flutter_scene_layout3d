import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show
        Action,
        BuildContext,
        FocusNode,
        InheritedWidget,
        Intent,
        ShortcutActivator,
        SingleActivator,
        State,
        StatefulWidget,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Focus3d, Focus3dTraversal;
import 'package:flutter_scene_layout3d/widgets.dart'
    show SceneActions3d, SceneShortcuts3d;

/// What a [RadioGroup3d] hands the radios below it: the chosen value and what
/// to call when it changes.
///
/// Flutter's `RadioGroupRegistry`, without its registration half, which is
/// this package's business rather than a caller's.
abstract interface class RadioGroupRegistry3d<T> {
  /// Which option of the group is chosen, or null for none.
  T? get groupValue;

  /// Called with the newly chosen value, or with null when a toggleable
  /// radio that was chosen is pressed again.
  ValueChanged<T?> get onChanged;
}

/// A set of options of which one is chosen, and the radios that show it.
///
/// ```dart
/// RadioGroup3d<Delivery>(
///   groupValue: _delivery,
///   onChanged: (value) => setState(() => _delivery = value),
///   child: SceneColumn3d(
///     mainAxisSize: MainAxisSize3d.min,
///     depthAxisAlignment: CrossAxisAlignment3d.start,
///     children: <Widget>[
///       RadioListTile3d<Delivery>.text(
///         title: 'Standard',
///         value: Delivery.standard,
///       ),
///       RadioListTile3d<Delivery>.text(
///         title: 'Express',
///         value: Delivery.express,
///       ),
///     ],
///   ),
/// )
/// ```
///
/// Flutter's `RadioGroup`, which since Flutter 3.35 is how a set of radios is
/// written. The group holds the value and the callback once, and every
/// [Radio3d] and [RadioListTile3d] **of the same type** below it takes them
/// from here — so their own `groupValue` and `onChanged` are optional, and
/// inside a group they are ignored, the way Flutter's `_effectiveRegistry`
/// prefers the group. A radio of another type does not see this group at
/// all, which is also Flutter's rule and is what lets two groups nest.
///
/// ## The arrows
///
/// What the group adds is the keyboard. **An arrow moves the choice and the
/// focus together**: to the next enabled radio of the group in tree order,
/// and round from the last to the first. Left and up are the previous one,
/// right and down the next, whatever the reading direction — that is
/// Flutter's map, so a ported screen behaves as it did. Space is the radio's
/// own activation and needs nothing from here.
///
/// The bindings are a `SceneShortcuts3d` around the group, which is where a
/// binding for a plane has to be — a Flutter `Shortcuts` around the view
/// reaches nothing on it; see `docs/traps.md`. They are enabled only while a
/// radio of this group holds the focus, so an arrow on any other control
/// inside the group goes on up the walk and moves the focus as it would have.
///
/// **This is therefore a box on the plane**, and goes inside a surface,
/// around the radios — not above the `SceneLayout3d` the way a
/// `DefaultTabController` can.
///
/// ## Tab stops on every radio
///
/// Flutter's group also makes only the chosen radio a Tab stop, so Tab
/// enters the group at its answer and leaves it in one step. That is a
/// traversal policy, and `Focus3dTraversal` has no way to skip a box that can
/// take the focus; here Tab stops on each radio in turn. It is a change to the
/// layout package's traversal rather than to this widget, and not yet made.
///
/// ## What it announces
///
/// Nothing of its own; each radio announces itself as before, `checked` and
/// `inMutuallyExclusiveGroup`. Flutter's group wears the `radioGroup` role on
/// a node whose children are its radios, and a `Semantics3d` has no children
/// in the semantics tree — a group node here would group nothing. The same
/// absence is what stops `TabBar3d` wearing `tabBar`, where Flutter checks
/// the children and a frame with an empty bar in it will not build.
class RadioGroup3d<T> extends StatefulWidget {
  /// Creates a group of radios choosing a [T].
  const RadioGroup3d({
    super.key,
    this.groupValue,
    required this.onChanged,
    required this.child,
  });

  /// Which option is chosen, or null for none.
  final T? groupValue;

  /// Called with the newly chosen value.
  final ValueChanged<T?> onChanged;

  /// The radios, in whatever arrangement the screen needs.
  final Widget child;

  /// The group of [T] above [context], or null when there is none.
  ///
  /// Makes [context] depend on it, so a radio rebuilds when the choice moves.
  static RadioGroupRegistry3d<T>? maybeOf<T>(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_RadioGroup3dScope<T>>()
      ?.state;

  @override
  State<RadioGroup3d<T>> createState() => _RadioGroup3dState<T>();
}

class _RadioGroup3dState<T> extends State<RadioGroup3d<T>>
    implements RadioGroupRegistry3d<T> {
  /// Every radio of this group standing now, in no particular order: the
  /// order an arrow walks is the tree's, read when the arrow arrives.
  final Set<RadioGroupMember3dState<T>> _members =
      <RadioGroupMember3dState<T>>{};

  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveChoiceIntent(
          forward: false,
        ),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveChoiceIntent(
          forward: false,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): _MoveChoiceIntent(
          forward: true,
        ),
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveChoiceIntent(
          forward: true,
        ),
      };

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    _MoveChoiceIntent: _MoveChoiceAction<T>(this),
  };

  @override
  T? get groupValue => widget.groupValue;

  @override
  ValueChanged<T?> get onChanged => widget.onChanged;

  void _register(RadioGroupMember3dState<T> member) => _members.add(member);

  void _unregister(RadioGroupMember3dState<T> member) =>
      _members.remove(member);

  /// The radio of this group holding the focus, or null.
  RadioGroupMember3dState<T>? get _focused {
    for (final member in _members) {
      if (member.focusNode.hasFocus) return member;
    }
    return null;
  }

  /// Moves the choice and the focus one radio along, in tree order.
  void _move({required bool forward}) {
    final focused = _focused;
    if (focused == null) return;
    final box = Focus3d.layoutFor(focused.focusNode);
    if (box == null) return;
    // The tree's order, from the root the focus is trapped in: the order Tab
    // walks, which for a column or a row of radios is the reading order — a
    // row mirrored for right to left lists its first child at the right.
    // A disabled radio's box cannot take the focus and so is not listed.
    final members = <FocusNode, RadioGroupMember3dState<T>>{
      for (final member in _members) member.focusNode: member,
    };
    final order = <RadioGroupMember3dState<T>>[
      for (final candidate in const Focus3dTraversal().focusableDescendants(
        Focus3dTraversal.traversalRootFor(box),
      ))
        if (members[candidate.focusNode] case final member?
            when member.widget.enabled)
          member,
    ];
    final at = order.indexOf(focused);
    if (at < 0 || order.length < 2) return;
    final next = order[(at + (forward ? 1 : -1) + order.length) % order.length];
    widget.onChanged(next.widget.value);
    final nextBox = Focus3d.layoutFor(next.focusNode);
    if (nextBox is Focus3d) nextBox.requestFocus();
  }

  @override
  Widget build(BuildContext context) => SceneShortcuts3d(
    shortcuts: _shortcuts,
    child: SceneActions3d(
      actions: _actions,
      child: _RadioGroup3dScope<T>(
        state: this,
        groupValue: widget.groupValue,
        child: widget.child,
      ),
    ),
  );
}

class _RadioGroup3dScope<T> extends InheritedWidget {
  const _RadioGroup3dScope({
    required this.state,
    required this.groupValue,
    required super.child,
  });

  final _RadioGroup3dState<T> state;
  final T? groupValue;

  @override
  bool updateShouldNotify(_RadioGroup3dScope<T> oldWidget) =>
      state != oldWidget.state || groupValue != oldWidget.groupValue;
}

/// An arrow inside a [RadioGroup3d].
class _MoveChoiceIntent extends Intent {
  const _MoveChoiceIntent({required this.forward});

  final bool forward;
}

/// Moves the choice, while a radio of the group holds the focus.
///
/// Disabled otherwise, which is what sends an arrow on any other control in
/// the group on up the walk to the default that moves the focus: a nearer
/// binding that is disabled is not an answer.
class _MoveChoiceAction<T> extends Action<_MoveChoiceIntent> {
  _MoveChoiceAction(this.group);

  final _RadioGroup3dState<T> group;

  @override
  bool isEnabled(_MoveChoiceIntent intent) =>
      group.mounted && group._focused != null;

  @override
  Object? invoke(_MoveChoiceIntent intent) {
    group._move(forward: intent.forward);
    return null;
  }
}

/// One radio's place in a [RadioGroup3d]: the focus node the group moves,
/// and the value it chooses.
///
/// Not exported. `Radio3d` and `RadioListTile3d` build through it when they
/// find a group, because the group has to be able to move the focus to a
/// radio, and a radio's focus normally belongs to an `InkWell3d` that owns it
/// privately. So this owns one when the caller gave none, registers it, and
/// hands it to [builder] along with the group.
class RadioGroupMember3d<T> extends StatefulWidget {
  /// Places a radio standing for [value] in [group].
  const RadioGroupMember3d({
    super.key,
    required this.group,
    required this.value,
    required this.enabled,
    required this.focusNode,
    required this.builder,
  });

  /// The group this radio is part of.
  final RadioGroupRegistry3d<T> group;

  /// What the radio stands for.
  final T value;

  /// Whether the radio can be chosen, by a press or by an arrow.
  final bool enabled;

  /// The caller's own focus node, or null for one this owns.
  final FocusNode? focusNode;

  /// Builds the radio, with the node the group will move the focus to.
  final Widget Function(BuildContext context, FocusNode focusNode) builder;

  @override
  State<RadioGroupMember3d<T>> createState() => RadioGroupMember3dState<T>();
}

/// The state of a [RadioGroupMember3d], which is what a group holds.
class RadioGroupMember3dState<T> extends State<RadioGroupMember3d<T>> {
  FocusNode? _owned;
  _RadioGroup3dState<T>? _group;

  /// The node the radio's control holds its focus in.
  FocusNode get focusNode =>
      widget.focusNode ??
      (_owned ??= FocusNode(debugLabel: 'Radio3d', skipTraversal: true));

  void _join() {
    final group = widget.group;
    final state = group is _RadioGroup3dState<T> ? group : null;
    if (identical(state, _group)) return;
    _group?._unregister(this);
    _group = state?.._register(this);
  }

  @override
  void initState() {
    super.initState();
    _join();
  }

  @override
  void didUpdateWidget(RadioGroupMember3d<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _join();
  }

  @override
  void dispose() {
    _group?._unregister(this);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, focusNode);
}
