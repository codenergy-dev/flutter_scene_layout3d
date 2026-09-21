import 'package:flutter/widgets.dart' show BuildContext, InheritedWidget;

/// Says to the selection control below it that a labelled tile is the
/// control, and it is only the picture of one.
///
/// Not exported. It is a promise between the three labelled tiles and the
/// three controls they hold, and nothing else: inside it a `Checkbox3d`, a
/// `Radio3d` or a `Switch3d` publishes no semantics, takes no focus, installs
/// no ink well and answers no ray, because the tile around it does all four.
///
/// That is this package's answer to the problem Flutter solves with
/// `MergeSemantics` and `ExcludeFocus`. There is no merge here — a
/// `Semantics3d` gathers nothing — and taking one component off one node
/// leaves every node under it published, so two announcements cannot be made
/// into one after the fact. **There has to be only one control to begin
/// with**, and this is what says which one it is.
class ControlInTile3d extends InheritedWidget {
  /// Marks [child] as drawn inside a tile that operates it.
  const ControlInTile3d({super.key, required super.child});

  /// Whether [context] is inside a labelled tile's control slot.
  ///
  /// Read without a dependency: whether a control sits in a tile is decided
  /// by where it was built, and it does not change while it stays there.
  static bool isIn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ControlInTile3d>() != null;

  @override
  bool updateShouldNotify(ControlInTile3d oldWidget) => false;
}
