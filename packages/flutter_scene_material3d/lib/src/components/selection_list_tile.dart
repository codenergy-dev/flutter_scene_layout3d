import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, FocusNode, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show EdgeInsetsGeometry3d;
import 'package:flutter_scene_layout3d/widgets.dart' show SceneText3d;

import 'control_in_tile.dart';
import 'list_tile.dart';
import 'reading_direction.dart';
import 'selection.dart';
import 'selection_style.dart';

/// Which end of a labelled tile its control sits at.
///
/// Flutter's `ListTileControlAffinity`, spelled again because that one lives
/// in `package:flutter/material.dart`, which this package does not import —
/// the reason `ColorSchemeVariant3d` gives for itself.
enum ListTileControlAffinity3d {
  /// At the leading edge: the left in left to right, the right in right to
  /// left.
  leading,

  /// At the trailing edge.
  trailing,

  /// Wherever that component's own convention puts it: trailing for a
  /// checkbox and a switch, leading for a radio button — Flutter's defaults.
  platform,
}

/// What the three labelled tiles share: a whole `ListTile3d` that is one
/// control.
///
/// **The row is the control, and the checkbox in it is only its picture.**
/// Flutter makes a `CheckboxListTile` announce once by wrapping it in
/// `MergeSemantics` and the checkbox in `ExcludeFocus`. Neither exists here —
/// a `Semantics3d` gathers nothing, and taking one node out of the tree
/// leaves every node under it published — so two announcements cannot be
/// merged after the fact, and this does not try. The control in the tile is
/// built inside `ControlInTile3d`, where it publishes nothing, takes no
/// focus, has no ink well and answers no ray. The tile does all four, over
/// its whole rectangle, which is what a person means when they press the
/// words beside a checkbox and expect it to tick.
///
/// That is also why this does not *wrap* a [ListTile3d]: the tile would
/// publish a `button` node of its own under this one. It is built by the
/// same function a tile is built by, with this component's announcement in
/// place of the tile's.
abstract class _SelectionListTile3d extends StatelessWidget {
  const _SelectionListTile3d({
    super.key,
    required this.title,
    required this.subtitle,
    required this.secondary,
    required this.isThreeLine,
    required this.dense,
    required this.selected,
    required this.enabled,
    required this.controlAffinity,
    required this.focusNode,
    required this.autofocus,
    required this.tileColor,
    required this.selectedColor,
    required this.contentPadding,
    required this.semanticLabel,
    required this.textDirection,
  }) : assert(!isThreeLine || subtitle != null);

  /// The tile's first line, which is what the control is *for*.
  final Widget? title;

  /// The supporting line under the title.
  final Widget? subtitle;

  /// What sits at the other end from the control: an icon, an avatar.
  final Widget? secondary;

  /// Whether the subtitle is allowed two lines. See [ListTile3d.isThreeLine].
  final bool isThreeLine;

  /// Whether the tile uses the shorter height scale.
  final bool dense;

  /// Whether the tile's text is drawn in its selected colour.
  ///
  /// Not the control's value, as in Flutter: a ticked row is not a selected
  /// row unless the caller says so.
  final bool selected;

  /// Whether the tile responds at all, or null to follow whether it has a
  /// callback.
  ///
  /// False draws the control disabled as well, whatever it was handed.
  final bool? enabled;

  /// Which end the control sits at.
  final ListTileControlAffinity3d controlAffinity;

  /// The node holding the tile's place in the focus tree. The control in it
  /// has none of its own.
  final FocusNode? focusNode;

  /// Whether the tile takes the focus as soon as it is laid out.
  final bool autofocus;

  /// The slab's colour, or null for a transparent one.
  final Color? tileColor;

  /// The text colour when [selected], or null for `colorScheme.primary`.
  final Color? selectedColor;

  /// Space between the tile's faces and its content, or null for
  /// [ListTile3d.defaultContentPadding].
  final EdgeInsetsGeometry3d? contentPadding;

  /// What a screen reader announces the row as, beside the control's state.
  ///
  /// **State it**, or use the `.text` constructor, which composes it from
  /// the strings it is handed. A tile built out of widgets has no way to read
  /// a label out of them.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// Whether the control sits at the leading edge when [controlAffinity] is
  /// [ListTileControlAffinity3d.platform].
  bool get leadsByDefault;

  /// Whether a callback is there to call.
  bool get hasCallback;

  /// Whether the tile and its control respond.
  bool get active => (enabled ?? true) && hasCallback;

  /// The control, built to be drawn rather than operated.
  Widget buildControl(BuildContext context);

  /// What a press on the row does, or null for a row that does nothing.
  void Function()? get onTap;

  /// The control's state, for the one node the row publishes.
  SemanticsProperties stateProperties();

  @override
  Widget build(BuildContext context) {
    final control = ControlInTile3d(child: buildControl(context));
    final leads = switch (controlAffinity) {
      ListTileControlAffinity3d.leading => true,
      ListTileControlAffinity3d.trailing => false,
      ListTileControlAffinity3d.platform => leadsByDefault,
    };
    final tap = active ? onTap : null;
    final state = stateProperties();
    final tile = ListTile3d(
      leading: leads ? control : secondary,
      title: title,
      subtitle: subtitle,
      trailing: leads ? secondary : control,
      isThreeLine: isThreeLine,
      dense: dense,
      selected: selected,
      enabled: active,
      onTap: tap,
      focusNode: focusNode,
      autofocus: autofocus,
      tileColor: tileColor,
      selectedColor: selectedColor,
      contentPadding: contentPadding,
    );
    return buildListTile3d(
      context,
      tile,
      SemanticsProperties(
        checked: state.checked,
        mixed: state.mixed,
        toggled: state.toggled,
        inMutuallyExclusiveGroup: state.inMutuallyExclusiveGroup,
        selected: selected ? true : null,
        enabled: active,
        label: semanticLabel,
        textDirection: readingDirection3d(context, textDirection),
        onTap: tap,
      ),
    );
  }
}

/// The label a `.text` constructor composes: the title, then the subtitle,
/// the way [ListTile3d.text] composes its own.
String _composed(String title, String? subtitle) =>
    subtitle == null ? title : '$title, $subtitle';

/// A list tile that is a checkbox: the whole row ticks it.
///
/// ```dart
/// CheckboxListTile3d.text(
///   title: 'Remember me',
///   value: _remember,
///   onChanged: (value) => setState(() => _remember = value!),
/// )
/// ```
///
/// One node for the row, one focus, one target, one wash. **The checkbox in
/// it is only drawn**: it publishes nothing, takes no focus and answers no
/// ray, because the row does all of that over its whole rectangle — there is
/// no `MergeSemantics` here to fold two announcements into one, so there is
/// only one control to begin with. The row publishes the checkbox's
/// `checked` (or `mixed`, when [tristate]) with the tile's label, which is
/// the announcement Flutter's `CheckboxListTile` ends up with after its
/// merge.
///
/// The checkbox goes at the trailing edge by default, as Flutter's does.
class CheckboxListTile3d extends _SelectionListTile3d {
  /// Creates a checkbox tile out of widgets, announcing [semanticLabel].
  const CheckboxListTile3d({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.checkboxStyle,
    super.title,
    super.subtitle,
    super.secondary,
    super.isThreeLine = false,
    super.dense = false,
    super.selected = false,
    super.enabled,
    super.controlAffinity = ListTileControlAffinity3d.platform,
    super.focusNode,
    super.autofocus = false,
    super.tileColor,
    super.selectedColor,
    super.contentPadding,
    super.semanticLabel,
    super.textDirection,
  }) : assert(tristate || value != null);

  /// Creates a checkbox tile out of strings, which are also what it
  /// announces.
  CheckboxListTile3d.text({
    super.key,
    required String title,
    String? subtitle,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.checkboxStyle,
    super.secondary,
    super.isThreeLine = false,
    super.dense = false,
    super.selected = false,
    super.enabled,
    super.controlAffinity = ListTileControlAffinity3d.platform,
    super.focusNode,
    super.autofocus = false,
    super.tileColor,
    super.selectedColor,
    super.contentPadding,
    String? semanticLabel,
    super.textDirection,
  }) : assert(tristate || value != null),
       super(
         title: SceneText3d(title),
         subtitle: subtitle == null ? null : SceneText3d(subtitle),
         semanticLabel: semanticLabel ?? _composed(title, subtitle),
       );

  /// Whether the box is ticked, or null for mixed. See [Checkbox3d.value].
  final bool? value;

  /// Called with the value a press makes, or null for a tile that cannot be
  /// changed. See [Checkbox3d.onChanged].
  final ValueChanged<bool?>? onChanged;

  /// Whether the box has a third, mixed state.
  final bool tristate;

  /// The checkbox's tokens, or null for the theme's.
  final CheckboxStyle3d? checkboxStyle;

  @override
  bool get leadsByDefault => false;

  @override
  bool get hasCallback => onChanged != null;

  @override
  void Function()? get onTap {
    final changed = onChanged;
    if (changed == null) return null;
    return () => changed(Checkbox3d.next(value, tristate: tristate));
  }

  @override
  Widget buildControl(BuildContext context) => Checkbox3d(
    value: value,
    tristate: tristate,
    style: checkboxStyle,
    onChanged: active ? onChanged : null,
  );

  @override
  SemanticsProperties stateProperties() => SemanticsProperties(
    checked: value ?? false,
    mixed: tristate ? value == null : null,
  );
}

/// A list tile that is a switch: the whole row flips it.
///
/// ```dart
/// SwitchListTile3d.text(
///   title: 'Notifications',
///   value: _notify,
///   onChanged: (value) => setState(() => _notify = value),
/// )
/// ```
///
/// The row publishes `toggled` rather than `checked`, for the reason
/// [Switch3d] does. The switch goes at the trailing edge by default.
class SwitchListTile3d extends _SelectionListTile3d {
  /// Creates a switch tile out of widgets, announcing [semanticLabel].
  const SwitchListTile3d({
    super.key,
    required this.value,
    required this.onChanged,
    this.switchStyle,
    super.title,
    super.subtitle,
    super.secondary,
    super.isThreeLine = false,
    super.dense = false,
    super.selected = false,
    super.enabled,
    super.controlAffinity = ListTileControlAffinity3d.platform,
    super.focusNode,
    super.autofocus = false,
    super.tileColor,
    super.selectedColor,
    super.contentPadding,
    super.semanticLabel,
    super.textDirection,
  });

  /// Creates a switch tile out of strings, which are also what it announces.
  SwitchListTile3d.text({
    super.key,
    required String title,
    String? subtitle,
    required this.value,
    required this.onChanged,
    this.switchStyle,
    super.secondary,
    super.isThreeLine = false,
    super.dense = false,
    super.selected = false,
    super.enabled,
    super.controlAffinity = ListTileControlAffinity3d.platform,
    super.focusNode,
    super.autofocus = false,
    super.tileColor,
    super.selectedColor,
    super.contentPadding,
    String? semanticLabel,
    super.textDirection,
  }) : super(
         title: SceneText3d(title),
         subtitle: subtitle == null ? null : SceneText3d(subtitle),
         semanticLabel: semanticLabel ?? _composed(title, subtitle),
       );

  /// Whether the switch is on.
  final bool value;

  /// Called with the value a press makes, or null for a tile that cannot be
  /// changed.
  final ValueChanged<bool>? onChanged;

  /// The switch's tokens, or null for the theme's.
  final SwitchStyle3d? switchStyle;

  @override
  bool get leadsByDefault => false;

  @override
  bool get hasCallback => onChanged != null;

  @override
  void Function()? get onTap {
    final changed = onChanged;
    if (changed == null) return null;
    return () => changed(!value);
  }

  @override
  Widget buildControl(BuildContext context) => Switch3d(
    value: value,
    style: switchStyle,
    onChanged: active ? onChanged : null,
  );

  @override
  SemanticsProperties stateProperties() => SemanticsProperties(toggled: value);
}

/// A list tile that is one option of a set: the whole row chooses it.
///
/// ```dart
/// RadioListTile3d<Delivery>.text(
///   title: 'Standard delivery',
///   value: Delivery.standard,
///   groupValue: _delivery,
///   onChanged: (value) => setState(() => _delivery = value!),
/// )
/// ```
///
/// The row publishes `checked` and `inMutuallyExclusiveGroup`, as [Radio3d]
/// does. The radio goes at the **leading** edge by default, which is
/// Flutter's convention for this one of the three.
///
/// Pressing the chosen row does nothing unless [toggleable], and it is still
/// a pressable row — Flutter's own behaviour, and the right one: a row that
/// went inert once chosen would lose its wash and its focus the moment it
/// was pressed.
class RadioListTile3d<T> extends _SelectionListTile3d {
  /// Creates a radio tile out of widgets, announcing [semanticLabel].
  const RadioListTile3d({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.toggleable = false,
    this.radioStyle,
    super.title,
    super.subtitle,
    super.secondary,
    super.isThreeLine = false,
    super.dense = false,
    super.selected = false,
    super.enabled,
    super.controlAffinity = ListTileControlAffinity3d.platform,
    super.focusNode,
    super.autofocus = false,
    super.tileColor,
    super.selectedColor,
    super.contentPadding,
    super.semanticLabel,
    super.textDirection,
  });

  /// Creates a radio tile out of strings, which are also what it announces.
  RadioListTile3d.text({
    super.key,
    required String title,
    String? subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.toggleable = false,
    this.radioStyle,
    super.secondary,
    super.isThreeLine = false,
    super.dense = false,
    super.selected = false,
    super.enabled,
    super.controlAffinity = ListTileControlAffinity3d.platform,
    super.focusNode,
    super.autofocus = false,
    super.tileColor,
    super.selectedColor,
    super.contentPadding,
    String? semanticLabel,
    super.textDirection,
  }) : super(
         title: SceneText3d(title),
         subtitle: subtitle == null ? null : SceneText3d(subtitle),
         semanticLabel: semanticLabel ?? _composed(title, subtitle),
       );

  /// What this option stands for.
  final T value;

  /// Which of the set is currently chosen.
  final T? groupValue;

  /// Called with the newly chosen value, or null for a set that cannot be
  /// changed. Called with null when a [toggleable] chosen row is pressed.
  final ValueChanged<T?>? onChanged;

  /// Whether pressing the chosen row clears the set.
  final bool toggleable;

  /// The radio's tokens, or null for the theme's.
  final RadioStyle3d? radioStyle;

  /// Whether this row is the chosen one.
  bool get checked => value == groupValue;

  @override
  bool get leadsByDefault => true;

  @override
  bool get hasCallback => onChanged != null;

  @override
  void Function()? get onTap {
    final changed = onChanged;
    if (changed == null) return null;
    return () {
      if (!checked) {
        changed(value);
      } else if (toggleable) {
        changed(null);
      }
    };
  }

  @override
  Widget buildControl(BuildContext context) => Radio3d<T>(
    value: value,
    groupValue: groupValue,
    toggleable: toggleable,
    style: radioStyle,
    onChanged: active ? onChanged : null,
  );

  @override
  SemanticsProperties stateProperties() =>
      SemanticsProperties(checked: checked, inMutuallyExclusiveGroup: true);
}
