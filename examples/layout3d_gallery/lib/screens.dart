import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';

/// The two Material screens the gallery draws, and the state behind them.
///
/// Both are ordinary widget subtrees: a `Scaffold3d` and the components on it,
/// with no idea what plane they are laid out on. That is the claim the gallery
/// exists to make visible — [MaterialScreen] is mounted upright on a turning
/// panel and [TableScreen] flat on the ground, and neither one says a word
/// about geometry.
///
/// Everything here is sized in **logical pixels**. The surfaces that host
/// these screens carry the unit contract (`Layout3dMetrics`), so a 48dp touch
/// target is 48dp whether the panel is a metre wide or a hand's breadth.

/// An upright screen: a bar, a body that changes with the navigation bar, a
/// floating action button, and a snack bar when it is pressed.
///
/// It is a `Scaffold3d` and nothing else — the same widget an application
/// would write, with the same two tabs an application would write.
class MaterialScreen extends StatefulWidget {
  const MaterialScreen({super.key});

  @override
  State<MaterialScreen> createState() => _MaterialScreenState();
}

class _MaterialScreenState extends State<MaterialScreen> {
  int _tab = 0;

  // The inbox.
  final Set<int> _starred = <int>{1};
  int _filter = 0;

  // The settings.
  bool _notify = true;
  bool _compact = false;
  double _volume = 0.65;

  static const List<(String, String)> _messages = <(String, String)>[
    ('Ada Lovelace', 'The engine weaves algebraic patterns'),
    ('Grace Hopper', 'A ship in port is safe, but that is not'),
    ('Alan Kay', 'The best way to predict the future'),
    ('Barbara Liskov', 'A subtype must not surprise its caller'),
    ('Edsger Dijkstra', 'Simplicity is a prerequisite'),
  ];

  static const List<String> _filters = <String>['All', 'Unread', 'Starred'];

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger3d(
      child: Builder(
        builder: (context) => Scaffold3d(
          appBar: AppBar3d.text(
            title: _tab == 0 ? 'Inbox' : 'Settings',
            variant: AppBarVariant3d.small,
            actions: <Widget>[
              IconButton3d(
                icon: Icons.search,
                semanticLabel: 'Search',
                onPressed: () => _say(context, 'Nothing to search yet'),
              ),
            ],
          ),
          body: _tab == 0 ? _inbox(context) : _settings(context),
          bottomNavigationBar: NavigationBar3d(
            selectedIndex: _tab,
            onDestinationSelected: (index) => setState(() => _tab = index),
            destinations: const <NavigationDestination3d>[
              NavigationDestination3d(
                icon: Icon3d(Icons.inbox),
                label: 'Inbox',
              ),
              NavigationDestination3d(
                icon: Icon3d(Icons.tune),
                label: 'Settings',
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton3d(
            semanticLabel: 'Compose',
            onPressed: () => _say(context, 'Composing a message'),
            child: const Icon3d(Icons.edit),
          ),
        ),
      ),
    );
  }

  void _say(BuildContext context, String message) {
    ScaffoldMessenger3d.of(context).show(
      SnackBar3d(
        message: message,
        actionLabel: 'Undo',
        onAction: () {},
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// A row of filter chips over a scrolling list of cards.
  ///
  /// The list is where the clip earns its keep: it is taller than the room the
  /// scaffold gave it, and the body's window is what stops a row drawing over
  /// the bar above it. A card in it stays `raised` all the same — the window
  /// cuts the face and leaves the depth alone.
  Widget _inbox(BuildContext context) {
    return SceneColumn3d(
      crossAxisAlignment: CrossAxisAlignment3d.stretch,
      children: <Widget>[
        ScenePadding3d(
          padding: _insets(context, const EdgeInsets3d.all(8)),
          child: SceneRow3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
            children: <Widget>[
              for (var index = 0; index < _filters.length; index++)
                FilterChip3d(
                  label: SceneText3d(_filters[index]),
                  semanticLabel: _filters[index],
                  selected: _filter == index,
                  onSelected: (_) => setState(() => _filter = index),
                ),
            ],
          ),
        ),
        SceneExpanded3d(
          child: SceneListView3d(
            spacing: _dp(context, 8),
            children: <Widget>[
              for (var index = 0; index < _messages.length; index++)
                ScenePadding3d(
                  key: ValueKey<int>(index),
                  padding: _insets(
                    context,
                    const EdgeInsets3d.symmetric(horizontal: 12),
                  ),
                  child: ElevatedCard3d(
                    onTap: () => _say(context, 'Opened ${_messages[index].$1}'),
                    semanticLabel: _messages[index].$1,
                    child: ListTile3d(
                      leading: const Icon3d(Icons.person),
                      title: SceneText3d(_messages[index].$1),
                      subtitle: SceneText3d(_messages[index].$2),
                      trailing: Checkbox3d(
                        value: _starred.contains(index),
                        semanticLabel: 'Star',
                        onChanged: (value) => setState(() {
                          if (value) {
                            _starred.add(index);
                          } else {
                            _starred.remove(index);
                          }
                        }),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The controls, each one a real state that a press actually changes.
  Widget _settings(BuildContext context) {
    return ScenePadding3d(
      padding: _insets(context, const EdgeInsets3d.all(12)),
      child: SceneColumn3d(
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        mainAxisSize: MainAxisSize3d.min,
        spacing: _dp(context, 8),
        children: <Widget>[
          FilledCard3d(
            child: SceneColumn3d(
              crossAxisAlignment: CrossAxisAlignment3d.stretch,
              // Everything in a card sits on the card's **front face**, and
              // this is the line that puts it there. A flex centres its
              // children on the depth axis by default, in the depth of its
              // deepest child — so a 1dp divider beside a 2dp tile ends up
              // half a millimetre *inside* the card, where the card's own
              // face is drawn in front of it and it simply is not there. See
              // `docs/traps.md`, *Depth ordering*.
              depthAxisAlignment: CrossAxisAlignment3d.start,
              mainAxisSize: MainAxisSize3d.min,
              children: <Widget>[
                ListTile3d(
                  title: const SceneText3d('Notifications'),
                  trailing: Switch3d(
                    value: _notify,
                    semanticLabel: 'Notifications',
                    onChanged: (value) => setState(() => _notify = value),
                  ),
                ),
                const Divider3d(),
                ListTile3d(
                  title: const SceneText3d('Compact rows'),
                  trailing: Switch3d(
                    value: _compact,
                    semanticLabel: 'Compact rows',
                    onChanged: (value) => setState(() => _compact = value),
                  ),
                ),
              ],
            ),
          ),
          OutlinedCard3d(
            child: ScenePadding3d(
              padding: _insets(context, const EdgeInsets3d.all(12)),
              child: SceneColumn3d(
                crossAxisAlignment: CrossAxisAlignment3d.stretch,
                depthAxisAlignment: CrossAxisAlignment3d.start,
                mainAxisSize: MainAxisSize3d.min,
                spacing: _dp(context, 4),
                children: <Widget>[
                  const SceneText3d('Volume'),
                  SceneAlign3d(
                    alignment: Alignment3d.frontCenter,
                    child: Slider3d(
                      value: _volume,
                      width: 200,
                      semanticLabel: 'Volume',
                      onChanged: (value) => setState(() => _volume = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SceneRow3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
            children: <Widget>[
              TextButton3d(
                onPressed: () => setState(() {
                  _notify = true;
                  _compact = false;
                  _volume = 0.65;
                }),
                child: const SceneText3d('Reset'),
              ),
              FilledButton3d(
                onPressed: () => _say(context, 'Saved'),
                child: const SceneText3d('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The same catalogue lying on a table.
///
/// This is the screen that could not exist in a 2D toolkit. The surface it is
/// laid out on uses [LayoutBasis3d.xz], so layout's "down" runs away from the
/// camera and the whole scaffold is flat on the ground — and every elevation
/// on it becomes a **height** you can see from the side, because an elevation
/// here is a distance rather than a painted shadow.
///
/// One of the three cards standing at `level5` while the other two rest at
/// `level1` is therefore not an ornament: it is the claim, drawn. Tap a card,
/// or the floating action button, and the raised one moves. That button stands
/// furthest off the table of anything on the screen, which is what
/// `Scaffold3d`'s depth ordering says it should do.
class TableScreen extends StatefulWidget {
  const TableScreen({super.key});

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  int _lifted = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    return Scaffold3d(
      // A shorter step than the theme's twelve. The depth vocabulary was
      // designed to keep two slabs out of each other's depth test, not to
      // decide how a screen *looks*, and four steps of it is 48dp — a seventh
      // of a phone's width, and on a table it is 48dp of **height**, which
      // leaves the title bar hanging in the air above the thing it belongs
      // to. Eight still clears the six a `thickness.structural` bar over a
      // `thickness.raised` card needs, and `Scaffold3d` asserts as much.
      depthStep: 8,
      appBar: AppBar3d.text(title: 'On the table', centerTitle: true),
      floatingActionButton: FloatingActionButton3d(
        semanticLabel: 'Lift the next card',
        onPressed: () => setState(() => _lifted = (_lifted + 1) % 3),
        child: const Icon3d(Icons.layers),
      ),
      body: ScenePadding3d(
        padding: _insets(context, const EdgeInsets3d.all(8)),
        child: SceneRow3d(
          crossAxisAlignment: CrossAxisAlignment3d.stretch,
          spacing: _dp(context, 8),
          children: <Widget>[
            for (var index = 0; index < 3; index++)
              SceneExpanded3d(
                child: ElevatedCard3d(
                  semanticLabel: 'Card ${index + 1}',
                  onTap: () => setState(() => _lifted = index),
                  style: CardStyle3d.of(theme, CardVariant3d.elevated).copyWith(
                    elevation: _lifted == index
                        ? theme.elevation.level5
                        : theme.elevation.level1,
                  ),
                  child: SceneAlign3d(
                    alignment: Alignment3d.frontCenter,
                    child: SceneColumn3d(
                      mainAxisSize: MainAxisSize3d.min,
                      depthAxisAlignment: CrossAxisAlignment3d.start,
                      spacing: _dp(context, 6),
                      children: <Widget>[
                        Icon3d(_tableIcons[index]),
                        SceneText3d(_tableLabels[index]),
                        // The elevation, written out. It is the whole point of
                        // this screen: on the ground plane an elevation is a
                        // height, so the lifted card visibly stands off the
                        // table rather than merely being tinted.
                        SceneText3d(
                          _lifted == index ? 'level 5' : 'level 1',
                          style: theme.textStyle(
                            Typography3dToken.labelMedium,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const List<IconData> _tableIcons = <IconData>[
    Icons.map,
    Icons.local_cafe,
    Icons.calendar_today,
  ];

  static const List<String> _tableLabels = <String>['Route', 'Break', 'Agenda'];
}

/// A dp figure as world units, read from the surface's unit contract.
///
/// A `build` method reaches the contract through [Layout3dMetricsScope]; a
/// `performLayout` reaches the same thing as `Layout3d.metrics`. Everything
/// Material states is in logical pixels and has to cross that boundary
/// exactly once — never the other way round.
double _dp(BuildContext context, double logicalPixels) =>
    Layout3dMetricsScope.of(context).dp(logicalPixels);

EdgeInsets3d _insets(BuildContext context, EdgeInsets3d insets) =>
    Layout3dMetricsScope.of(context).dpInsets(insets);
