import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_language.dart';
import '../../data/epg.dart';
import '../../data/live.dart';
import '../../data/on_now.dart';
import '../../data/provider_login.dart';
import '../../data/session.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../components/badges.dart';
import '../components/buttons.dart';
import '../components/cards.dart';
import '../components/chips.dart';
import '../components/dialogs.dart';
import '../components/rows.dart';
import '../components/title_menu.dart';
import '../theme.dart';
import 'number_entry.dart';

const _columns = 5;

/// How long a short and a long message stay (the TV's toasts).
const messageShort = Duration(seconds: 2);
const messageLong = Duration(milliseconds: 3500);

/// The Live TV page: a chip per group (Favourites, then the provider's
/// categories) over a grid of channel cards. Moving onto a chip shows its
/// group. Enter on a card watches the channel, with the group as the channel
/// list. A card's menu (right click, the Menu key, Shift+F10) has favourite,
/// hide the channel, and hide its group (not the main one, the provider's
/// first). Hidden things come back in Settings. A channel number typed on the
/// number keys opens that channel, as on a TV box.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.firstFocus, required this.onWatch});

  /// Takes the focus for the page, and passes it on to the shown group's chip.
  final FocusNode firstFocus;

  /// Watch `channels[index]`; Left and Right then move through `channels`. `all` is every channel the page shows.
  final void Function(List<Channel> channels, int index, List<Channel> all) onWatch;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

enum _MenuChoice { favorite, hide, hideGroup }

class _LiveScreenState extends State<LiveScreen> {
  // Null until read.
  List<Channel>? _channels;
  var _categories = const <LiveCategory>[];
  String? _failed;
  var _retrying = false;
  // Favourites and what is hidden load on their own: without them the page still works.
  final _favorites = <int>{};
  var _filters = const LiveFilters();
  // The shown group, by label: it survives a favourites change that adds or drops the Favourites group.
  String? _shownLabel;
  // As last built: the keys and the menu act on what is on screen.
  var _groups = const <LiveGroup>[];
  var _all = const <Channel>[];
  final _chips = <String, FocusNode>{};
  final _retry = FocusNode();
  late final _numbers = NumberEntry(_onNumber);
  String? _message;
  Timer? _messageTimer;
  @override
  void initState() {
    super.initState();
    _load();
    final catalog = services.catalog;
    catalog.favoriteChannels().then((ids) {
      if (mounted) setState(() => _favorites.addAll(ids));
    }, onError: (Object _) {});
    catalog.liveFilters().then((filters) {
      if (mounted) setState(() => _filters = filters);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _numbers.dispose();
    _retry.dispose();
    for (final node in _chips.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (_failed != null) setState(() => _retrying = true);
    try {
      final catalog = services.catalog;
      final channels = await catalog.channels();
      final categories = await catalog.liveCategories();
      if (!mounted) return;
      // Retry had the focus, and goes: the shown group's chip takes it.
      final inPage = FocusScope.of(context).hasFocus;
      setState(() {
        _channels = channels;
        _categories = categories;
        _failed = null;
      });
      if (inPage) _afterFrame(_focusShown);
    } on Exception catch (e) {
      if (!mounted) return;
      // The page had the focus while it loaded, with nothing to show it on: Retry takes it.
      final waiting = widget.firstFocus.hasPrimaryFocus;
      setState(() => _failed = e is ApiException ? e.message : e.toString());
      if (waiting) _afterFrame(_retry.requestFocus);
    }
    if (mounted) setState(() => _retrying = false);
  }

  LiveGroup? get _shown => _groups.where((g) => g.label == _shownLabel).firstOrNull ?? _groups.firstOrNull;

  FocusNode _chip(String label) => _chips.putIfAbsent(label, FocusNode.new);

  void _focusShown() {
    final shown = _shown;
    if (shown != null && _chip(shown.label).context != null) _chip(shown.label).requestFocus();
  }

  void _afterFrame(VoidCallback run) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) run();
  });

  /// A card that had the focus went (hidden, or no longer a favourite): the shown group's chip takes it.
  void _keepFocus() => _afterFrame(() {
    if (FocusScope.of(context).hasPrimaryFocus) _focusShown();
  });

  void _say(String message, Duration stay) {
    _messageTimer?.cancel();
    setState(() => _message = message);
    _messageTimer = Timer(stay, () => setState(() => _message = null));
  }

  bool _onNumber(int number) {
    final found = channelByNumber(number, const [], _all);
    if (found == null) return false;
    widget.onWatch(found.$1, found.$2, _all);
    return true;
  }

  Future<void> _toggleFavorite(Channel c) async {
    final l = AppLocalizations.of(context)!;
    final now = !_favorites.contains(c.id);
    void set(bool favorite) => setState(() => favorite ? _favorites.add(c.id) : _favorites.remove(c.id));
    set(now);
    _say(now ? l.liveFavoriteAdded : l.liveFavoriteRemoved, messageShort);
    _keepFocus();
    try {
      await services.catalog.setFavorite(c.id, now);
    } on Exception {
      // Put back, so the star shows what is saved; unless a later press already changed it.
      if (mounted && _favorites.contains(c.id) == now) set(!now);
    }
  }

  Future<void> _hideChannel(Channel c) async {
    void set(bool hidden) => setState(() {
      final ids = {..._filters.hiddenChannels};
      hidden ? ids.add(c.id) : ids.remove(c.id);
      _filters = _filters.copyWith(hiddenChannels: ids);
    });
    set(true);
    _say(AppLocalizations.of(context)!.liveHidden, messageLong);
    _keepFocus();
    try {
      await services.catalog.setChannelHidden(c.id, true);
    } on Exception {
      if (mounted) set(false);
    }
  }

  Future<void> _hideGroup(LiveGroup group, LiveCategory category) async {
    void set(bool hidden) => setState(() {
      final ids = {..._filters.hiddenGroups};
      hidden ? ids.add(category.id) : ids.remove(category.id);
      _filters = _filters.copyWith(hiddenGroups: ids);
    });
    // Then a neighbour group is shown, and its chip takes the focus.
    final i = _groups.indexOf(group);
    _shownLabel = (_groups.elementAtOrNull(i + 1) ?? (i > 0 ? _groups[i - 1] : null))?.label;
    set(true);
    _say(AppLocalizations.of(context)!.liveHidden, messageLong);
    _keepFocus();
    try {
      await services.catalog.setGroupHidden(category.id, true);
    } on Exception {
      if (mounted) set(false);
    }
  }

  Future<void> _menu(Channel c) async {
    final shown = _shown;
    if (shown == null) return;
    // Favourites and the main group (the provider's first) cannot be hidden.
    final category = shown.category;
    final group = category != null && category.id != _categories.firstOrNull?.id ? category : null;
    final choice = await showDialog<_MenuChoice>(
      context: context,
      builder: (_) => _ChannelMenu(c.name, favorite: _favorites.contains(c.id), group: group == null ? null : shown.label),
    );
    if (!mounted) return;
    switch (choice) {
      case _MenuChoice.favorite:
        _toggleFavorite(c);
      case _MenuChoice.hide:
        _hideChannel(c);
      case _MenuChoice.hideGroup:
        _hideGroup(shown, group!);
      case null:
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final channels = _channels;
    _groups = channels == null
        ? const []
        : liveGroups(channels, _categories, _favorites, l.liveFavorites, hebrew: isHebrew(context), filters: _filters);
    _all = allShown(_groups);
    final shown = _shown;
    final failed = _failed;
    // For what is on now on each card; without a login the cards show the channel only.
    final login = switch (services.provider.login) {
      final login? when login.isComplete => login,
      _ => null,
    };
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // A number still being typed when the focus leaves the page (another page opened) is dropped:
      // taken later, it would open the player over that page.
      onFocusChange: (focused) {
        if (!focused) _numbers.clear();
      },
      onKeyEvent: (_, event) => _numbers.key(event) ? KeyEventResult.handled : KeyEventResult.ignored,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Focus(
            focusNode: widget.firstFocus,
            skipTraversal: true,
            onFocusChange: (focused) {
              if (!focused) return;
              failed != null ? _retry.requestFocus() : _focusShown();
            },
            child: const SizedBox.shrink(),
          ),
          if (failed != null)
            // While a retry runs the button stays, holding the focus, and the text says so.
            _Message(_retrying ? l.loading : l.loadFailed(failed), retry: _retry, onRetry: _load)
          else if (channels == null)
            _Message(l.loading)
          else if (shown == null)
            _Message(l.nothingHere)
          else
            Padding(
              // 8 less than the page's 88 and 48: the grid keeps that room for the focused card's lift.
              padding: const EdgeInsetsDirectional.only(start: 80, end: 40, top: 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        // As on the TV, the row does not scroll: groups past the window's edge are cut off.
                        Flexible(
                          child: UnconstrainedBox(
                            alignment: AlignmentDirectional.centerStart,
                            constrainedAxis: Axis.vertical,
                            clipBehavior: Clip.hardEdge,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 8,
                              children: [
                                for (final g in _groups)
                                  OptionChip(
                                    key: ValueKey(g.label),
                                    selected: g.label == shown.label,
                                    focusNode: _chip(g.label),
                                    // The focus shows the group: the pointer passing over a chip must not.
                                    hoverFocuses: false,
                                    onFocusChange: (focused) {
                                      if (focused && _shownLabel != g.label) setState(() => _shownLabel = g.label);
                                    },
                                    // A click gives the chip the focus, which shows its group.
                                    onPressed: () {},
                                    label: g.label,
                                    detail: '${g.channels.length}',
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Text(l.liveHint, style: text.bodySmall!.copyWith(color: WtvColors.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: GridView.builder(
                      // A group opens at its top.
                      key: ValueKey(shown.label),
                      padding: const EdgeInsets.only(left: 8, right: 8, top: 6, bottom: 48),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 16 / 9,
                      ),
                      itemCount: shown.channels.length,
                      itemBuilder: (context, i) {
                        final c = shown.channels[i];
                        final card = _OnNowCard(
                          channel: c,
                          login: login,
                          favorite: _favorites.contains(c.id),
                          onPressed: () => widget.onWatch(shown.channels, i, _all),
                          onMenu: () => _menu(c),
                        );
                        return KeyedSubtree(
                          key: ValueKey(c.id),
                          // Up from the first row goes to the shown group's chip: another chip would switch the group.
                          child: i < _columns ? UpTo(_chip(shown.label), child: card) : card,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          NumberOverlay(_numbers),
          if (_message != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 36),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: WtvColors.chip, borderRadius: BorderRadius.circular(999)),
                    child: Text(_message!, style: text.bodyMedium),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A channel's card with what is on now: asked when the card comes on screen, and again when that programme ends.
class _OnNowCard extends StatefulWidget {
  const _OnNowCard({required this.channel, required this.login, required this.favorite, required this.onPressed, required this.onMenu});

  final Channel channel;
  final ProviderLogin? login;
  final bool favorite;
  final VoidCallback onPressed;
  final VoidCallback onMenu;

  @override
  State<_OnNowCard> createState() => _OnNowCardState();
}

class _OnNowCardState extends State<_OnNowCard> {
  late Programme? _onNow = OnNow.cached(widget.channel.extId, _nowSecs()).$2;
  Timer? _next;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(_OnNowCard old) {
    super.didUpdateWidget(old);
    // A login saved since (in Settings): what is on can be asked now.
    if (old.login == null && widget.login != null) _ask();
  }

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
  }

  Future<void> _ask() async {
    final login = widget.login;
    if (login == null) return;
    final programme = await OnNow.fetch(services.http, login, widget.channel.extId, _nowSecs());
    if (!mounted) return;
    setState(() => _onNow = programme);
    // No guide, or a failed call: OnNow's own wait decides when asking again is worth it.
    final wait = (programme?.end ?? _nowSecs() + 60) - _nowSecs();
    _next = Timer(Duration(seconds: wait < 5 ? 5 : wait), _ask);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    final title = _onNow?.title.trim() ?? '';
    return ChannelCard(
      logo: c.logo,
      name: c.name,
      number: c.num,
      favorite: widget.favorite,
      onNow: title.isEmpty ? null : title,
      onPressed: widget.onPressed,
      onMenu: widget.onMenu,
    );
  }
}

int _nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// A channel's menu: favourite (focused), hide it, hide the group it is shown in (with `group`, its name), or close.
/// Pops with the choice; Back closes.
class _ChannelMenu extends StatelessWidget {
  const _ChannelMenu(this.name, {required this.favorite, required this.group});

  final String name;
  final bool favorite;
  final String? group;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    void choose(_MenuChoice? choice) => Navigator.pop(context, choice);
    return Panel(
      width: 440,
      children: [
        ContentText(name, style: Theme.of(context).textTheme.titleLarge, maxLines: 2),
        const SizedBox(height: 16),
        Column(
          spacing: 8,
          children: [
            MenuItem(
              favorite ? Icons.star : Icons.star_border,
              favorite ? l.liveMenuUnfavorite : l.liveMenuFavorite,
              () => choose(_MenuChoice.favorite),
              autofocus: true,
            ),
            MenuItem(Icons.visibility_off_outlined, l.liveMenuHide, () => choose(_MenuChoice.hide)),
            if (group != null) MenuItem(Icons.folder_off_outlined, l.liveMenuHideGroup(group!), () => choose(_MenuChoice.hideGroup)),
            MenuItem(Icons.close, l.close, () => choose(null)),
          ],
        ),
      ],
    );
  }
}

/// Loading, empty or error message; with `onRetry`, a Retry button that can take the focus.
class _Message extends StatelessWidget {
  const _Message(this.text, {this.retry, this.onRetry});

  final String text;
  final FocusNode? retry;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: Theme.of(context).textTheme.titleMedium!.copyWith(color: WtvColors.textMuted)),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          ActionButton(label: AppLocalizations.of(context)!.retry, focusNode: retry, onPressed: onRetry!),
        ],
      ],
    ),
  );
}
