import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, IntProperty;

import '../layout3d.dart';
import 'stack.dart';

/// A [Stack3d] that shows one child at a time, the 3D analogue of
/// [IndexedStack].
///
/// Every child is laid out, so the stack is as big as its largest one and
/// switching between them moves nothing; only the chosen child is visible.
/// In Flutter that costs a paint-time branch. Here it costs nothing at all:
/// a scene node either draws or it does not, and hiding one is the same flag
/// the scrolling views already write to cull what has left their window. Hit
/// testing honours it, so a hidden page is unreachable as well as unseen.
///
/// Because of that, [index] is a *visibility* change and not a layout one:
/// setting it rewrites three booleans and asks for a frame. Nothing is
/// measured again, no text is re-shaped, and no decoration re-derives its
/// uniforms — which is what makes this the right way to build a tab body or a
/// wizard whose steps must keep their state.
///
/// ```dart
/// IndexedStack3d(index: step, children: [details, payment, review])
/// ```
///
/// A null [index] hides every child while still reserving the room, the same
/// as Flutter's.
class IndexedStack3d extends Stack3d {
  /// Creates a stack showing the child at [index].
  IndexedStack3d({
    int? index = 0,
    super.alignment,
    super.fit,
    super.depthStep,
    super.children,
    super.name,
  }) : _index = index,
       assert(index == null || index >= 0);

  int? _index;

  /// Which child is shown, or null for none.
  ///
  /// Setting it does not relayout: every child was laid out already and none
  /// of them changes size by being shown.
  int? get index => _index;

  set index(int? value) {
    if (_index == value) return;
    assert(value == null || value >= 0);
    _index = value;
    _applyVisibility();
    owner?.requestVisualUpdate();
  }

  void _applyVisibility() {
    for (var i = 0; i < childCount; i++) {
      childAt(i).node.visible = i == _index;
    }
  }

  @override
  void insert(Layout3d child, {int? index}) {
    super.insert(child, index: index);
    _applyVisibility();
  }

  @override
  void remove(Layout3d child) {
    super.remove(child);
    _applyVisibility();
  }

  @override
  void removeAll() {
    super.removeAll();
    _applyVisibility();
  }

  @override
  void syncChildren(List<Layout3d> children) {
    super.syncChildren(children);
    _applyVisibility();
  }

  @override
  void performLayout() {
    super.performLayout();
    // Last writer wins, and the decision is this box's. A child that was
    // hidden while it was outside some other view's window is shown again by
    // the stack if it is the one selected, which is what a caller means.
    _applyVisibility();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IntProperty('index', index, ifNull: 'none shown'));
  }
}
