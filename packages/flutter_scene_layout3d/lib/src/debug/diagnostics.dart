import 'package:flutter/foundation.dart'
    show DiagnosticLevel, DiagnosticsTreeStyle, debugPrint;

import '../layout3d.dart';

/// Prints the layout tree under [root], the 3D analogue of
/// `debugDumpRenderTree`.
///
/// The tool this package was missing. A layout here has no display list to
/// look at and no widget inspector behind it, so when a box comes out the
/// wrong size the only evidence is a number in a test failure. This prints
/// the whole story instead: what constraints each box was given, what size it
/// chose, where its parent put it, and whether the answer is stale.
///
/// ```dart
/// surface.flush();
/// debugDumpLayout3dTree(surface);
/// ```
///
/// ```
/// Layout3dSurface#a1b2c
///  │ constraints: Constraints3d(0.0<=w<=4.0, 0.0<=h<=3.0, 0.0<=d<=Infinity)
///  │ size: Size3d(4.000, 3.000, 0.000)
///  │
///  └─child: Column3d#d4e5f
///      │ mainAxisAlignment: center
///      │ size: Size3d(4.000, 3.000, 0.000)
///      ...
/// ```
///
/// Works on any box, not only a surface: pass the subtree you are suspicious
/// of. [minLevel] raises or lowers how much each box says about itself;
/// [DiagnosticLevel.fine] adds the relayout boundary and the `sizedByParent`
/// flag, which is what to reach for when a change is not showing up at all.
void debugDumpLayout3dTree(
  Layout3d root, {
  DiagnosticLevel minLevel = DiagnosticLevel.debug,
}) {
  debugPrint(root.toStringDeep(minLevel: minLevel));
}

/// The layout tree under [root] as a string, without printing it.
///
/// What [debugDumpLayout3dTree] prints. Useful in a test — a golden tree is a
/// far better assertion than a size comparison, because it says what went
/// wrong rather than only that something did — and in an error message that
/// wants to quote a subtree.
///
/// Wrap the expectation in `equalsIgnoringHashCodes` from `flutter_test`: the
/// object identities in the dump differ between runs, and nothing else does.
String debugDescribeLayout3dTree(
  Layout3d root, {
  DiagnosticLevel minLevel = DiagnosticLevel.debug,
}) => root.toStringDeep(minLevel: minLevel);

/// The chain from [box] up to the root, innermost first.
///
/// The other half of a tree dump, and the one an error message wants: a box
/// that came out wrong was made wrong by something above it, and this is the
/// list of suspects. Each entry is described shallowly (its own properties,
/// none of its children), which is what makes the chain readable at all.
String debugDescribeLayout3dAncestry(Layout3d box) {
  final buffer = StringBuffer();
  Layout3d? node = box;
  var depth = 0;
  while (node != null) {
    buffer.writeln('${'  ' * depth}${node.toStringShallow(joiner: ', ')}');
    node = node.parent;
    depth += 1;
  }
  return buffer.toString();
}

/// The style every box in this package is dumped in.
///
/// Named so a box that describes a child of its own (a sliver quoting the
/// item it built, an overlay entry quoting its layer) matches the rest of the
/// tree instead of inventing a second shape.
const DiagnosticsTreeStyle layout3dTreeStyle = DiagnosticsTreeStyle.sparse;
