import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueChanged, VoidCallback;
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
    show
        Alignment3d,
        Constraints3d,
        CrossAxisAlignment3d,
        MainAxisSize3d,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneColumn3d,
        SceneConstrainedBox3d,
        SceneIgnorePointer3d,
        SceneIntrinsicWidth3d,
        ScenePadding3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneText3d,
        WidgetPageRoute3d;

import '../theme/theme.dart';
import 'anchor.dart';
import 'ink_well.dart';
import 'material.dart';
import 'overlay_style.dart';
import 'overlay_support.dart';
import 'reading_direction.dart';

/// A Material menu: a small surface of items, put in front of everything.
///
/// The surface alone. [PopupMenuButton3d] is what opens one at a button, and
/// [showMenu3d] is the function underneath it.
///
/// ## Every item is its own surface
///
/// An `InkWell3d` washes the **enclosing** `Material3d`, so an item placed
/// straight inside the menu's panel would light the whole menu up under one
/// finger — the trap `docs/traps.md` records for a chip's delete icon. A menu
/// can afford the answer a navigation bar uses: a `Thickness3d.thin` slab per
/// item, lifted `MenuStyle3d.itemDepthStep` off the menu's front face so that
/// neither of its faces is coplanar with the surface it is drawn on.
class Menu3d extends StatelessWidget {
  /// Creates a menu holding [children].
  const Menu3d({
    super.key,
    required this.children,
    this.style,
    this.semanticLabel,
    this.textDirection,
  });

  /// The items, top to bottom. Usually [MenuItem3d]s.
  final List<Widget> children;

  /// The tokens to draw with, or null for the theme's.
  final MenuStyle3d? style;

  /// What a screen reader announces the menu as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? MenuStyle3d.of(theme);

    return SceneSemantics3d(
      properties: SemanticsProperties(
        scopesRoute: true,
        namesRoute: semanticLabel != null,
        label: semanticLabel,
        textDirection: readingDirection3d(context, textDirection),
      ),
      child: SceneConstrainedBox3d(
        constraints: Constraints3d(
          minWidth: metrics.dp(resolved.minWidth),
          maxWidth: metrics.dp(resolved.maxWidth),
        ),
        // The width of the widest item, clamped into the two figures above —
        // which is what Flutter's `PopupMenu` does with an `IntrinsicWidth`
        // for the same reason: a menu that filled its maximum would be 280dp
        // wide however short its labels are.
        child: SceneIntrinsicWidth3d(
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
              child: SceneColumn3d(
                mainAxisSize: MainAxisSize3d.min,
                crossAxisAlignment: CrossAxisAlignment3d.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of a [Menu3d]: a label, a tap, and a surface of its own.
///
/// 48dp tall, which is also Material's minimum tap target — so a menu item is
/// the rare control that needs no `TapTarget3d` reach beyond its own extent.
class MenuItem3d extends StatelessWidget {
  /// Creates a menu item.
  const MenuItem3d({
    super.key,
    required this.label,
    this.onPressed,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.semanticLabel,
    this.textDirection,
    this.style,
  });

  /// The item's label, as a string rather than a widget.
  ///
  /// A string because the item has to **announce** it: a `Semantics3d`
  /// gathers nothing from the labels below it, so an item that took a widget
  /// would have no name unless the caller repeated it. Same decision, same
  /// reason, as `ListTile3d.text`.
  final String label;

  /// Called when the item is chosen.
  final VoidCallback? onPressed;

  /// A glyph before the label.
  final Widget? leading;

  /// A glyph or a shortcut after it.
  final Widget? trailing;

  /// Whether the item responds at all.
  final bool enabled;

  /// What a screen reader announces, or null for [label].
  final String? semanticLabel;

  /// The direction the announcement reads in.
  final TextDirection? textDirection;

  /// The tokens to draw with, or null for the theme's.
  final MenuStyle3d? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? MenuStyle3d.of(theme);
    final live = enabled && onPressed != null;
    final content = live
        ? resolved.contentColor
        : theme.colorScheme.disabledContent;

    final row = ScenePadding3d(
      padding: metrics.dpInsets(resolved.itemPadding),
      child: SceneRow3d(
        crossAxisAlignment: CrossAxisAlignment3d.center,
        spacing: metrics.dp(12),
        children: <Widget>[
          if (leading != null) SceneIgnorePointer3d(child: leading!),
          SceneIgnorePointer3d(
            child: SceneText3d(
              label,
              style: theme.textStyle(resolved.itemTextStyle, color: content),
            ),
          ),
          if (trailing != null) SceneIgnorePointer3d(child: trailing!),
        ],
      ),
    );

    return SceneSemantics3d(
      properties: SemanticsProperties(
        button: true,
        enabled: live,
        label: semanticLabel ?? label,
        textDirection: readingDirection3d(context, textDirection),
        onTap: live ? onPressed : null,
      ),
      child: SceneSizedBox3d(
        height: metrics.dp(resolved.itemHeight),
        child: Material3d(
          // Transparent: the menu behind it is the surface a reader sees, and
          // this slab exists to carry the wash and nothing else.
          color: const Color(0x00000000),
          contentColor: resolved.contentColor,
          shape: theme.shape.none,
          // An elevation is a lift, so this stands the item's slab clear of
          // the menu's front face without moving anything in layout.
          elevation: resolved.itemDepthStep,
          thickness: resolved.itemThickness,
          surfaceTint: const Color(0x00000000),
          alignment: null,
          child: live
              ? InkWell3d(
                  minimumSize: Size3d.zero,
                  onTap: onPressed,
                  child: row,
                )
              : row,
        ),
      ),
    );
  }
}

/// A button that opens a menu anchored to itself.
///
/// ```dart
/// PopupMenuButton3d<String>(
///   semanticLabel: 'More',
///   itemBuilder: (context) => <MenuItem3dEntry<String>>[
///     const MenuItem3dEntry(value: 'rename', label: 'Rename'),
///     const MenuItem3dEntry(value: 'delete', label: 'Delete'),
///   ],
///   onSelected: (value) => act(value),
///   child: const Icon3d(Icons.more_vert),
/// )
/// ```
///
/// ## Anchoring, which nothing in the layout package did before this
///
/// An overlay entry is placed by the overlay's own `Stack3d.alignment`, which
/// is in the middle of the panel and nowhere near the button. There is no
/// `CompositedTransformTarget` here. What there is, since phase 6, is
/// `Layout3d.anchorOffsetTo`: the button's corner taken into world space
/// through `worldTransform` and back out again in the menu's own frame, which
/// is the `nodeOffset` that puts the menu's top-left on the button's
/// bottom-left.
///
/// **It is written on the node tier**, so anchoring lays nothing out and
/// costs one matrix.
///
/// ## When the anchor moves
///
/// The menu **follows it**, and does so within the same frame rather than one
/// behind. Two hooks, and between them they cover everything that can move a
/// button:
///
/// - the menu re-anchors when it is itself placed, which covers a resize and
///   anything that relays the overlay out;
/// - and when the *button* is placed, which covers a scroll — a scrolling
///   view places its rows rather than relaying them out, so the second hook
///   is the one that matters there.
///
/// The menu closes when the button leaves the tree, because an anchor that no
/// longer exists cannot be followed and a menu hanging at the last place its
/// button was is worse than no menu.
///
/// What it does **not** do is shift itself to stay inside the panel. Flutter's
/// `PopupMenuButton` reflows the menu against the screen edges; that is a
/// two-dimensional idea, and what it should mean for a surface floating in a
/// scene is a real question rather than an oversight. See *What phase 6 left
/// out*.
class PopupMenuButton3d<T> extends StatefulWidget {
  /// Creates a button that opens a menu.
  const PopupMenuButton3d({
    super.key,
    required this.itemBuilder,
    required this.child,
    this.onSelected,
    this.onCanceled,
    this.enabled = true,
    this.semanticLabel,
    this.textDirection,
    this.style,
  });

  /// Builds the items, each carrying the value it stands for.
  final List<MenuItem3dEntry<T>> Function(BuildContext context) itemBuilder;

  /// The trigger: whatever is tapped to open the menu.
  final Widget child;

  /// Called with the value of the item that was chosen.
  final ValueChanged<T>? onSelected;

  /// Called when the menu closes without a choice.
  final VoidCallback? onCanceled;

  /// Whether the button opens anything.
  final bool enabled;

  /// What a screen reader announces the button as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// The tokens the menu is drawn with.
  final MenuStyle3d? style;

  @override
  State<PopupMenuButton3d<T>> createState() => _PopupMenuButton3dState<T>();
}

class _PopupMenuButton3dState<T> extends State<PopupMenuButton3d<T>> {
  Anchor3d? _anchor;
  WidgetPageRoute3d<T>? _open;

  @override
  void dispose() {
    // An anchor that has left the tree cannot be followed, so the menu goes
    // with the button rather than hanging where the button used to be.
    _open?.pop();
    _open = null;
    super.dispose();
  }

  Future<void> _open3d() async {
    final anchor = _anchor;
    if (anchor == null || _open != null) return;
    final route = WidgetPageRoute3d<T>(
      layer: overlayLayer3d(
        Theme3d.of(context),
        Layout3dMetricsScope.of(context),
      ),
      modal: false,
      trapFocus: true,
      debugLabel: 'PopupMenuButton3d',
      builder: (context, self) => modalFrame3d(
        // No scrim: a menu dims nothing. The barrier is still there, which is
        // what closes the menu on a tap outside it.
        scrimColor: null,
        scrimThickness: 0.0,
        depthStep: Layout3dMetricsScope.of(
          context,
        ).dp(Theme3d.of(context).thickness.depthStep),
        dismissible: true,
        onDismiss: self.pop,
        child: Follower3dWidget(
          anchor: anchor,
          child: Menu3d(
            style: widget.style,
            semanticLabel: widget.semanticLabel,
            children: <Widget>[
              for (final item in widget.itemBuilder(context))
                MenuItem3d(
                  label: item.label,
                  leading: item.leading,
                  trailing: item.trailing,
                  enabled: item.enabled,
                  style: widget.style,
                  onPressed: () => self.pop(item.value),
                ),
            ],
          ),
        ),
      ),
    );
    _open = route;
    final chosen = await navigatorOf3d(context).push(route);
    _open = null;
    if (chosen == null) {
      widget.onCanceled?.call();
    } else {
      widget.onSelected?.call(chosen);
    }
  }

  @override
  Widget build(BuildContext context) => SceneSemantics3d(
    properties: SemanticsProperties(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      textDirection: readingDirection3d(context, widget.textDirection),
      onTap: widget.enabled ? _open3d : null,
    ),
    child: Anchor3dWidget(
      onCreated: (anchor) => _anchor = anchor,
      child: Material3d(
        color: const Color(0x00000000),
        shape: Theme3d.of(context).shape.full,
        thickness: Theme3d.of(context).thickness.thin,
        surfaceTint: const Color(0x00000000),
        alignment: null,
        child: SceneAlign3d(
          alignment: Alignment3d.frontCenter,
          widthFactor: 1.0,
          heightFactor: 1.0,
          child: InkWell3d(
            minimumSize: Size3d.zero,
            enabled: widget.enabled,
            onTap: widget.enabled ? _open3d : null,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

/// One entry in a [PopupMenuButton3d]'s menu: a label and the value it stands
/// for.
class MenuItem3dEntry<T> {
  /// Creates an entry.
  const MenuItem3dEntry({
    required this.value,
    required this.label,
    this.leading,
    this.trailing,
    this.enabled = true,
  });

  /// What choosing this item pops the menu with.
  final T value;

  /// The item's label, which is also what it announces.
  final String label;

  /// A glyph before the label.
  final Widget? leading;

  /// A glyph or shortcut after it.
  final Widget? trailing;

  /// Whether the item can be chosen.
  final bool enabled;
}

/// Puts a menu in front of everything, anchored to [anchor], and returns what
/// it is popped with.
///
/// What [PopupMenuButton3d] calls. Useful on its own for a menu opened by
/// something that is not a button — a long press on a row, a keyboard
/// shortcut — as long as there is a [Anchor3d] to hang it on.
Future<T?> showMenu3d<T>({
  required BuildContext context,
  required Anchor3d anchor,
  required List<Widget> children,
  MenuStyle3d? style,
  String? semanticLabel,
  Alignment3d menuCorner = Alignment3d.topLeft,
  Alignment3d anchorCorner = Alignment3d.bottomLeft,
  String? debugLabel,
}) {
  final theme = Theme3d.of(context);
  final metrics = Layout3dMetricsScope.of(context);
  late final WidgetPageRoute3d<T> route;
  route = WidgetPageRoute3d<T>(
    layer: overlayLayer3d(theme, metrics),
    modal: false,
    trapFocus: true,
    debugLabel: debugLabel ?? 'Menu3d',
    builder: (context, self) => modalFrame3d(
      scrimColor: null,
      scrimThickness: 0.0,
      depthStep: metrics.dp(theme.thickness.depthStep),
      dismissible: true,
      onDismiss: route.pop,
      child: Follower3dWidget(
        anchor: anchor,
        self: menuCorner,
        target: anchorCorner,
        child: Menu3d(
          style: style,
          semanticLabel: semanticLabel,
          children: children,
        ),
      ),
    ),
  );
  return navigatorOf3d(context).push(route);
}
