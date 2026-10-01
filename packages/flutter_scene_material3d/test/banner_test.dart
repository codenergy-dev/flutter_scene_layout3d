// MaterialBanner3d: the two arrangements, the rule and the margin, and what
// it announces.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

/// A banner at the top of a screen-shaped column, which is where a static
/// banner goes, and where its height is its own rather than the surface's.
Widget _atTop(Widget banner) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    banner,
    const SceneExpanded3d(child: SceneSizedBox3d()),
  ],
);

/// Where [box]'s origin is on the surface.
Offset3d _origin(Layout3d box) {
  var at = Offset3d.zero;
  Layout3d? walk = box;
  while (walk != null) {
    at += walk.offset;
    walk = walk.parent;
  }
  return at;
}

Text3d _label(Layout3dSurface surface, String text) =>
    boxesOf<Text3d>(surface).singleWhere((box) => box.data == text);

/// The banner's own panel: the one in its container colour.
DecoratedBox3d _strip(Layout3dSurface surface) =>
    boxesOf<DecoratedBox3d>(surface).firstWhere(
      (box) =>
          (box.decoration as BoxDecoration3d).color ==
          _theme.colorScheme.surfaceContainerLow,
    );

TextButton3d _button(String label) => TextButton3d(
  semanticLabel: label,
  onPressed: () {},
  child: SceneText3d(label),
);

const String _message = 'Offline';

void main() {
  group('the tokens', () {
    test('are Flutter\'s Material 3 banner', () {
      final style = MaterialBannerStyle3d.of(_theme);
      expect(style.container, _theme.colorScheme.surfaceContainerLow);
      expect(style.dividerColor, _theme.colorScheme.outlineVariant);
      expect(style.textStyle, Typography3dToken.bodyMedium);
      // Flat: Flutter's banner never reads its token table's 1dp.
      expect(style.elevation, 0.0);
      expect(style.actionsBarMinHeight, 52.0);
      expect(style.elevatedMargin, 10.0);
      expect(style.maxTextScaleFactor, 1.5);
      // A banner lives in the body, so it is no deeper than a card: the
      // scaffold keeps its bars in front of `raised` and nothing deeper.
      expect(style.thickness, _theme.thickness.raised);
    });
  });

  group('one action', () {
    testWidgets('sits beside the content, which starts 16dp in', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => _atTop(
          MaterialBanner3d.text(
            content: _message,
            actions: <Widget>[_button('Retry')],
          ),
        ),
        centred: false,
      );
      final content = _origin(_label(pumped.surface, _message));
      final action = _origin(_label(pumped.surface, 'Retry'));
      expect(content.x, closeTo(16 * _dp, 1e-9));
      expect(action.x, greaterThan(content.x));
      final strip = _strip(pumped.surface);
      // The single-row arrangement: the 52dp bar beside the content, with
      // 2dp above it, and the flat banner's 1dp rule under it.
      expect(strip.size.height, closeTo(55 * _dp, 1e-9));
    });

    testWidgets('goes under the content when it is told to', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => _atTop(
          MaterialBanner3d.text(
            content: _message,
            forceActionsBelow: true,
            actions: <Widget>[_button('Retry')],
          ),
        ),
        centred: false,
      );
      final content = _label(pumped.surface, _message);
      expect(
        _origin(_label(pumped.surface, 'Retry')).y,
        greaterThan(_origin(content).y + content.size.height),
      );
    });
  });

  group('two actions', () {
    testWidgets('sit under the content, at the trailing edge', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => _atTop(
          MaterialBanner3d.text(
            content: _message,
            leading: const Icon3d(Icons.cloud_off),
            actions: <Widget>[_button('Later'), _button('Retry')],
          ),
        ),
        centred: false,
      );
      final content = _label(pumped.surface, _message);
      final later = _label(pumped.surface, 'Later');
      final retry = _label(pumped.surface, 'Retry');
      expect(
        _origin(later).y,
        greaterThan(_origin(content).y + content.size.height),
      );
      expect(_origin(retry).x, greaterThan(_origin(later).x));
      // The content is 24dp down, and after the icon and its 16dp.
      expect(_origin(content).y, greaterThanOrEqualTo(24 * _dp - 1e-9));
      expect(_origin(content).x, greaterThan(16 * _dp + 16 * _dp));
      // Retry ends near the trailing edge: 8dp of bar padding and the
      // button's own.
      final strip = _strip(pumped.surface);
      expect(
        _origin(retry).x + retry.size.width,
        greaterThan(strip.size.width - 48 * _dp),
      );
    });

    testWidgets('and at the left in right to left', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => _atTop(
          MaterialBanner3d.text(
            content: _message,
            actions: <Widget>[_button('Later'), _button('Retry')],
          ),
        ),
        centred: false,
        textDirection: TextDirection.rtl,
      );
      final strip = _strip(pumped.surface);
      final later = _label(pumped.surface, 'Later');
      final retry = _label(pumped.surface, 'Retry');
      // First to last from the right, ending near the left edge.
      expect(_origin(retry).x, lessThan(_origin(later).x));
      expect(_origin(retry).x, lessThan(48 * _dp));
      // And the content starts 16dp from the right.
      final content = _label(pumped.surface, _message);
      expect(
        _origin(content).x + content.size.width,
        closeTo(strip.size.width - 16 * _dp, 1e-9),
      );
    });
  });

  group('raised and flat', () {
    testWidgets('raised, it has a 10dp margin and no rule', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => _atTop(
          MaterialBanner3d.text(
            content: _message,
            elevation: 1,
            actions: <Widget>[_button('Retry')],
          ),
        ),
        centred: false,
      );
      final strip = _strip(pumped.surface);
      expect((strip.decoration as BoxDecoration3d).elevation, 1.0);
      final rules = boxesOf<DecoratedBox3d>(pumped.surface).where(
        (box) =>
            (box.decoration as BoxDecoration3d).color ==
            _theme.colorScheme.outlineVariant,
      );
      expect(rules, isEmpty);
      // The margin is under the strip: the first box below the column is
      // ten logical pixels taller than the strip.
      final column = outermostOf<Flex3d>(pumped.surface);
      final banner = boxesOf<Layout3d>(
        pumped.surface,
      ).firstWhere((box) => identical(box.parent, column));
      expect(banner.size.height, closeTo(strip.size.height + 10 * _dp, 1e-9));
    });

    testWidgets('flat, which is the default, it has an outlineVariant rule '
        'and no margin', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => _atTop(
          MaterialBanner3d.text(
            content: _message,
            actions: <Widget>[_button('Retry')],
          ),
        ),
        centred: false,
      );
      final rules = boxesOf<DecoratedBox3d>(pumped.surface).where(
        (box) =>
            (box.decoration as BoxDecoration3d).color ==
            _theme.colorScheme.outlineVariant,
      );
      expect(rules, hasLength(1));
      final column = outermostOf<Flex3d>(pumped.surface);
      final banner = boxesOf<Layout3d>(
        pumped.surface,
      ).firstWhere((box) => identical(box.parent, column));
      expect(
        banner.size.height,
        closeTo(_strip(pumped.surface).size.height, 1e-9),
      );
    });
  });

  group('what it announces', () {
    testWidgets('the content, from .text', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => _atTop(
          MaterialBanner3d.text(
            content: _message,
            actions: <Widget>[_button('Retry')],
          ),
        ),
        centred: false,
      );
      final labels = boxesOf<Semantics3d>(
        pumped.surface,
      ).map((box) => box.properties.label);
      expect(labels, contains(_message));
      expect(labels, contains('Retry'));
    });

    testWidgets('a banner with no action is refused', (tester) async {
      await pumpComponent(
        tester,
        () => _atTop(
          MaterialBanner3d.text(content: _message, actions: const <Widget>[]),
        ),
        centred: false,
      );
      expect(tester.takeException(), isAssertionError);
    });
  });
}
