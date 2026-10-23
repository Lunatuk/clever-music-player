import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../appearance/appearance_settings.dart';
import '../../appearance/appearance_theme.dart';
import 'design_preview_model.dart';

/// Reference composition with synthetic content. No runtime/audio/file/network
/// dependency; its preferences and visual tokens are shared with the real app.
final class DesignPreviewCanvas extends StatefulWidget {
  const DesignPreviewCanvas(
      {super.key,
      this.appearance = const AppearanceSettings(),
      this.initialPage = PreviewPage.home,
      this.onPageChanged,
      this.fontFamily});
  final AppearanceSettings appearance;
  final PreviewPage initialPage;
  final ValueChanged<PreviewPage>? onPageChanged;
  final String? fontFamily;
  @override
  State<DesignPreviewCanvas> createState() => _DesignPreviewCanvasState();
}

final class _DesignPreviewCanvasState extends State<DesignPreviewCanvas> {
  late PreviewPage _page = widget.initialPage;
  late ThemeData _theme;
  int _current = 0, _tab = 0, _nextEntry = 7;
  bool _playing = true,
      _reverse = false,
      _shuffle = false,
      _repeat = false,
      _likedOnly = false;
  double _position = .257, _volume = .64;
  String _query = '';
  final _search = TextEditingController();
  final _likes = <int>{0, 2};
  final _queue = <({int id, int song})>[
    for (var i = 1; i <= 6; i++) (id: i, song: i)
  ];
  AppearanceTokens get t => _theme.extension<AppearanceTokens>()!;
  Color get fg => _theme.colorScheme.onSurface;
  Color get bg => _theme.colorScheme.surface;
  Color get panel => _theme.colorScheme.surfaceContainer;
  PreviewSong get song => previewSongs[_current];
  @override
  void didUpdateWidget(covariant DesignPreviewCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPage != widget.initialPage) _page = widget.initialPage;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(PreviewPage page) {
    setState(() => _page = page);
    widget.onPageChanged?.call(page);
  }

  void _select(int i) {
    setState(() {
      _current = i;
      _playing = true;
      _position = 0;
    });
    _open(PreviewPage.player);
  }

  void _step(int delta) => setState(() {
        _current = (_current + delta) % previewSongs.length;
        _position = 0;
      });
  void _like(int i) => setState(() {
        if (!_likes.add(i)) _likes.remove(i);
      });
  TextStyle style(double size,
          {bool secondary = false, FontWeight weight = FontWeight.w400}) =>
      TextStyle(
          fontSize: size, color: secondary ? t.muted : fg, fontWeight: weight);
  Widget icon(String tip, IconData data, VoidCallback action, {Color? color}) =>
      IconButton(
          tooltip: tip,
          onPressed: action,
          icon: Icon(data, color: color ?? fg));
  Widget like(int i) => icon(
      _likes.contains(i) ? 'Убрать из избранного' : 'В избранное',
      _likes.contains(i)
          ? Icons.favorite_rounded
          : Icons.favorite_border_rounded,
      () => _like(i),
      color: _likes.contains(i) ? _theme.colorScheme.primary : t.muted);
  Widget cover(int i, double size) => PreviewCover(
      index: previewSongs[i].cover, size: size, radius: t.coverRadius);
  Widget button(String label, VoidCallback action,
          {bool filled = false, IconData? leading}) =>
      TextButton(
          onPressed: action,
          style: TextButton.styleFrom(
              backgroundColor: filled ? t.accent : panel,
              foregroundColor: filled ? t.onAccent : fg,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[
              Icon(leading, size: 18),
              const SizedBox(width: 6)
            ],
            Flexible(child: Text(label))
          ]));

  @override
  Widget build(BuildContext context) {
    final brightness = switch (widget.appearance.mode) {
      AppearanceMode.system => MediaQuery.platformBrightnessOf(context),
      AppearanceMode.dark => Brightness.dark,
      AppearanceMode.light => Brightness.light,
    };
    _theme = createAppearanceTheme(widget.appearance, brightness,
        fontFamily: widget.fontFamily);
    return AnimatedTheme(
        data: _theme,
        duration: t.duration(context),
        child: Material(
            color: bg,
            child: LayoutBuilder(builder: (context, box) {
              final desktop = box.maxWidth >= 900;
              final main = switch (_page) {
                PreviewPage.home => _home(context, desktop),
                PreviewPage.library => _library(context, desktop),
                PreviewPage.player => _player(context, desktop),
                PreviewPage.queue => _queuePage(context),
              };
              final body = AnimatedSwitcher(
                  duration: t.duration(context),
                  child: KeyedSubtree(key: ValueKey(_page), child: main));
              if (desktop) {
                return Column(children: [
                  Expanded(
                      child:
                          Row(children: [_sidebar(), Expanded(child: body)])),
                  _desktopDock()
                ]);
              }
              return Column(children: [
                Expanded(child: body),
                if (_page != PreviewPage.player) ...[
                  _mobileDock(),
                  _bottomNavigation()
                ]
              ]);
            })));
  }

  Widget _sidebar() => Container(
      width: 180,
      color: bg,
      padding: const EdgeInsets.fromLTRB(14, 26, 14, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 0, 28),
            child: Row(children: [
              Icon(Icons.graphic_eq_rounded, color: t.accent, size: 28),
              const SizedBox(width: 8),
              Text('Clever\nМузыка', style: style(17, weight: FontWeight.w700))
            ])),
        for (final e in [
          (Icons.search, 'Поиск', PreviewPage.library),
          (Icons.music_note_rounded, 'Главная', PreviewPage.home),
          (Icons.library_music_outlined, 'Коллекция', PreviewPage.library),
          (Icons.queue_music, 'Очередь', PreviewPage.queue)
        ])
          ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(e.$1, size: 20),
              title: Text(e.$2, style: style(13)),
              selected: _page == e.$3 && e.$2 != 'Поиск',
              selectedTileColor: panel,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              onTap: () => _open(e.$3)),
        const Spacer(),
        Row(children: [
          CircleAvatar(
              radius: 15,
              backgroundColor: panel,
              child: Icon(Icons.person_outline, color: t.muted, size: 18)),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Моя музыка\nНа устройстве',
                  style: style(11, secondary: true)))
        ]),
      ]));

  Widget _bottomNavigation() => SafeArea(
      top: false,
      child: Container(
          color: bg,
          child: Row(children: [
            for (final e in [
              (Icons.music_note_rounded, 'Главная', PreviewPage.home),
              (Icons.queue_music, 'Очередь', PreviewPage.queue),
              (Icons.library_music_outlined, 'Коллекция', PreviewPage.library)
            ])
              Expanded(
                  child: Semantics(
                      selected: _page == e.$3,
                      button: true,
                      child: InkWell(
                          onTap: () => _open(e.$3),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(e.$1,
                                        size: 24,
                                        color: _page == e.$3 ? fg : t.muted),
                                    const SizedBox(height: 4),
                                    Text(e.$2,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            style(10, secondary: _page != e.$3))
                                  ]))))),
          ])));

  Widget _home(BuildContext context, bool desktop) =>
      CustomScrollView(slivers: [
        SliverToBoxAdapter(
            child: Column(children: [
          if (!desktop)
            Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(children: [
                  CircleAvatar(
                      radius: 14,
                      backgroundColor: panel,
                      child:
                          Icon(Icons.person_outline, size: 18, color: t.muted)),
                  Expanded(
                      child: Center(
                          child: Text('Clever Музыка',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style(18, weight: FontWeight.w700)))),
                  icon('Поиск в коллекции', Icons.search,
                      () => _open(PreviewPage.library))
                ])),
          SizedBox(
              width: double.infinity,
              height: desktop ? 370 : 410,
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(
                    child: RepaintBoundary(
                        child: CustomPaint(painter: _WavePainter(t.accent)))),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  TextButton.icon(
                      onPressed: () => setState(() => _playing = !_playing),
                      icon: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 32,
                          color: fg),
                      label: Text('Моя волна',
                          style: style(desktop ? 32 : 28,
                              weight: FontWeight.w800))),
                  const SizedBox(height: 8),
                  button('Коллекция', () => _open(PreviewPage.library)),
                ]),
                Positioned(
                    left: 20,
                    right: 20,
                    bottom: 8,
                    child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          button('Для вас', () => _open(PreviewPage.library),
                              leading: Icons.person_outline),
                          button('Плейлисты', () {
                            setState(() => _tab = 1);
                            _open(PreviewPage.library);
                          }, leading: Icons.queue_music)
                        ])),
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
              child: Row(children: [
                Expanded(
                    child: Text('Недавно в коллекции',
                        style: style(20, weight: FontWeight.w700))),
                TextButton(
                    onPressed: () => _open(PreviewPage.library),
                    child: const Text('Все'))
              ])),
        ])),
        SliverToBoxAdapter(
            child: SizedBox(
                height: 260,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: 4,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 16),
                    itemBuilder: (context, i) => SizedBox(
                        width: 154,
                        child: InkWell(
                            onTap: () => _select(i),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  cover(i, 154),
                                  const SizedBox(height: 10),
                                  Text(previewSongs[i].album,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          style(14, weight: FontWeight.w600)),
                                  Text(previewSongs[i].artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: style(12, secondary: true))
                                ])))))),
      ]);

  Widget _library(BuildContext context, bool desktop) {
    final q = _query.trim().toLowerCase();
    var indices = [
      for (var i = 0; i < previewSongs.length; i++)
        if ((!_likedOnly || _likes.contains(i)) &&
            '${previewSongs[i].title} ${previewSongs[i].artist} ${previewSongs[i].album}'
                .toLowerCase()
                .contains(q))
          i
    ];
    if (_reverse) indices = indices.reversed.toList();
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.fromLTRB(
                  desktop ? 30 : 20, 24, desktop ? 30 : 20, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Коллекция',
                        style: style(30, weight: FontWeight.w700)),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              key: const ValueKey('preview-search'),
                              controller: _search,
                              onChanged: (v) => setState(() => _query = v),
                              decoration: InputDecoration(
                                  hintText: 'Поиск в моей музыке',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: q.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Очистить поиск',
                                          icon: const Icon(Icons.close),
                                          onPressed: () {
                                            _search.clear();
                                            setState(() => _query = '');
                                          })))),
                      const SizedBox(width: 8),
                      icon('Сортировать в обратном порядке', Icons.sort,
                          () => setState(() => _reverse = !_reverse))
                    ]),
                    const SizedBox(height: 18),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      button('Моя волна по коллекции',
                          () => _open(PreviewPage.home),
                          filled: true, leading: Icons.play_arrow),
                      button(_likedOnly ? 'Все треки' : 'Мне нравится',
                          () => setState(() => _likedOnly = !_likedOnly),
                          leading: Icons.favorite_border)
                    ]),
                    const SizedBox(height: 20),
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final e
                              in ['Треки', 'Плейлисты', 'Альбомы'].indexed)
                            Padding(
                                padding: const EdgeInsets.only(right: 18),
                                child: InkWell(
                                    onTap: () => setState(() => _tab = e.$1),
                                    child: Container(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        decoration: BoxDecoration(
                                            border: Border(
                                                bottom: BorderSide(
                                                    color: _tab == e.$1
                                                        ? t.accent
                                                        : Colors.transparent,
                                                    width: 2))),
                                        child: Text(e.$2,
                                            style: style(15,
                                                weight: _tab == e.$1
                                                    ? FontWeight.w700
                                                    : FontWeight.w400))))),
                        ])),
                    const SizedBox(height: 16),
                    Text(
                        '${_tab == 1 ? 'Мои плейлисты' : _tab == 2 ? 'Альбомы' : 'Треки'} · ${indices.length}',
                        style: style(14, secondary: true)),
                  ]))),
      if (_tab == 0) ...[
        if (indices.isEmpty)
          const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Ничего не найдено')))
        else
          SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverList.builder(
                  itemCount: indices.length,
                  itemBuilder: (context, i) =>
                      _track(context, indices[i], desktop: desktop))),
      ] else
        SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverLayoutBuilder(builder: (context, box) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final count = scale > 1.5
                  ? 1
                  : math.max(2, (box.crossAxisExtent / 210).floor());
              final width = (box.crossAxisExtent - 16 * (count - 1)) / count;
              return SliverGrid.builder(
                  itemCount: 4,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 20,
                      mainAxisExtent: width + 76 * scale),
                  itemBuilder: (context, i) => InkWell(
                      onTap: () => setState(() => _tab = 0),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            cover(i, width),
                            const SizedBox(height: 8),
                            Text(
                                _tab == 1
                                    ? [
                                        'Мне нравится',
                                        'На каждый день',
                                        'В дороге',
                                        'Вечер'
                                      ][i]
                                    : previewSongs[i].album,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: style(14, weight: FontWeight.w600)),
                            Text('${i + 2} трека · на устройстве',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style(12, secondary: true))
                          ])));
            })),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ]);
  }

  Widget _track(BuildContext context, int i,
      {bool desktop = false, Widget? trailing}) {
    final s = previewSongs[i];
    return Material(
        color: i == _current ? panel : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
            onTap: () => _select(i),
            child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: t.rowPadding),
                child: Row(children: [
                  cover(i, desktop ? 40 : 44),
                  const SizedBox(width: 12),
                  Expanded(
                      flex: 3,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style(14, weight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(s.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style(12, secondary: true))
                          ])),
                  if (desktop) ...[
                    Expanded(
                        flex: 2,
                        child: Text(s.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style(12, secondary: true))),
                    const SizedBox(width: 12),
                    Text(s.duration, style: style(12, secondary: true)),
                    const SizedBox(width: 8),
                    like(i)
                  ],
                  trailing ??
                      PopupMenuButton<int>(
                          tooltip: 'Действия с треком',
                          icon: Icon(Icons.more_horiz, color: t.muted),
                          onSelected: (v) {
                            if (v == 2) {
                              _like(i);
                            } else {
                              setState(() {
                                final entry = (id: _nextEntry++, song: i);
                                if (v == 0) {
                                  _queue.insert(0, entry);
                                } else {
                                  _queue.add(entry);
                                }
                              });
                            }
                          },
                          itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 0, child: Text('Слушать следующим')),
                                const PopupMenuItem(
                                    value: 1, child: Text('В конец очереди')),
                                PopupMenuItem(
                                    value: 2,
                                    child: Text(_likes.contains(i)
                                        ? 'Убрать из избранного'
                                        : 'В избранное'))
                              ]),
                ]))));
  }

  Widget _transport({bool compact = false}) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!compact)
          icon('Перемешать', Icons.shuffle,
              () => setState(() => _shuffle = !_shuffle),
              color: _shuffle ? _theme.colorScheme.primary : t.muted),
        icon('Предыдущий трек', Icons.skip_previous_rounded, () => _step(-1)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: IconButton.filled(
                tooltip: _playing ? 'Пауза' : 'Воспроизвести',
                onPressed: () => setState(() => _playing = !_playing),
                style: IconButton.styleFrom(
                    backgroundColor: t.accent,
                    foregroundColor: t.onAccent,
                    minimumSize: Size.square(compact ? 40 : 64)),
                icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: compact ? 25 : 38))),
        icon('Следующий трек', Icons.skip_next_rounded, () => _step(1)),
        if (!compact)
          icon('Повторять', Icons.repeat,
              () => setState(() => _repeat = !_repeat),
              color: _repeat ? _theme.colorScheme.primary : t.muted),
      ]));
  String get _positionLabel {
    final time = song.duration.split(':');
    final seconds =
        ((int.parse(time[0]) * 60 + int.parse(time[1])) * _position).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _timeline() => Column(children: [
        Slider(
            value: _position, onChanged: (v) => setState(() => _position = v)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text(_positionLabel, style: style(11, secondary: true)),
              const Spacer(),
              Text(song.duration, style: style(11, secondary: true))
            ]))
      ]);

  Widget _player(BuildContext context, bool desktop) =>
      LayoutBuilder(builder: (context, box) {
        final size = (desktop ? 340.0 : box.maxWidth - 60).clamp(140.0, 380.0);
        final controls = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: style(desktop ? 30 : 22,
                              weight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(song.artist,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: style(15, secondary: true))
                    ])),
                like(_current)
              ]),
              const SizedBox(height: 24),
              _timeline(),
              const SizedBox(height: 24),
              Center(child: _transport()),
              const SizedBox(height: 26),
              Center(
                  child: TextButton.icon(
                      onPressed: () => _open(PreviewPage.queue),
                      icon: const Icon(Icons.queue_music),
                      label: Text('Очередь · ${_queue.length} треков'))),
            ]);
        return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                desktop ? 36 : 20, 12, desktop ? 36 : 20, 28),
            child: Column(children: [
              Row(children: [
                icon('В медиатеку', Icons.keyboard_arrow_down,
                    () => _open(PreviewPage.library)),
                Expanded(
                    child: Column(children: [
                  Text('Сейчас играет', style: style(11, secondary: true)),
                  Text(song.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style(13))
                ])),
                icon('Открыть очередь', Icons.queue_music,
                    () => _open(PreviewPage.queue))
              ]),
              SizedBox(height: desktop ? 36 : 32),
              if (desktop && MediaQuery.textScalerOf(context).scale(14) <= 21)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  cover(_current, size),
                  const SizedBox(width: 40),
                  Expanded(child: controls)
                ])
              else ...[
                cover(_current, size),
                const SizedBox(height: 32),
                controls
              ],
            ]));
      });

  Widget _queuePage(BuildContext context) => CustomScrollView(slivers: [
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('Очередь',
                                style: style(28, weight: FontWeight.w700))),
                        icon('В медиатеку', Icons.close,
                            () => _open(PreviewPage.library))
                      ]),
                      const SizedBox(height: 18),
                      Text('Сейчас играет', style: style(12, secondary: true)),
                      const SizedBox(height: 8),
                      _track(context, _current),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                            child: Text('Далее · ${_queue.length}',
                                style: style(16, weight: FontWeight.w600))),
                        TextButton(
                            onPressed: () => setState(_queue.clear),
                            child: const Text('Очистить'))
                      ]),
                    ]))),
        if (_queue.isEmpty)
          const SliverFillRemaining(
              hasScrollBody: false, child: Center(child: Text('Очередь пуста')))
        else
          SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverReorderableList(
                  itemCount: _queue.length,
                  onReorder: (oldIndex, newIndex) => setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final entry = _queue.removeAt(oldIndex);
                        _queue.insert(newIndex, entry);
                      }),
                  itemBuilder: (context, index) {
                    final entry = _queue[index];
                    return KeyedSubtree(
                        key: ValueKey(entry.id),
                        child: _track(context, entry.song,
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              icon(
                                  'Убрать из очереди',
                                  Icons.close,
                                  () => setState(() => _queue
                                      .removeWhere((e) => e.id == entry.id))),
                              ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Icon(Icons.drag_handle)))
                            ])));
                  })),
      ]);

  Widget _mobileDock() => Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      decoration:
          BoxDecoration(color: panel, borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        LinearProgressIndicator(
            value: _position,
            minHeight: 2,
            backgroundColor: Colors.transparent),
        Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Row(children: [
              InkWell(
                  onTap: () => _open(PreviewPage.player),
                  child: cover(_current, 40)),
              const SizedBox(width: 10),
              Expanded(
                  child: InkWell(
                      onTap: () => _open(PreviewPage.player),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style(12, weight: FontWeight.w600)),
                            Text(song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style(11, secondary: true))
                          ]))),
              like(_current),
              icon(
                  _playing ? 'Пауза' : 'Воспроизвести',
                  _playing ? Icons.pause : Icons.play_arrow,
                  () => setState(() => _playing = !_playing)),
            ])),
      ]));
  Widget _desktopDock() => Container(
      color: panel,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 3, child: LinearProgressIndicator(value: _position)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(children: [
              cover(_current, 42),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style(13, weight: FontWeight.w600)),
                    Text(song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style(11, secondary: true))
                  ])),
              like(_current),
              const SizedBox(width: 22),
              _transport(compact: true),
              const SizedBox(width: 22),
              icon('Открыть очередь', Icons.queue_music,
                  () => _open(PreviewPage.queue)),
              const SizedBox(width: 12),
              Icon(Icons.volume_up_outlined, color: t.muted, size: 20),
              SizedBox(
                  width: 100,
                  child: Slider(
                      value: _volume,
                      onChanged: (v) => setState(() => _volume = v))),
            ])),
      ]));
}

/// Original bounded vector illustration: no shader asset, video, network,
/// image decode, or continuous ticker on the home screen.
final class _WavePainter extends CustomPainter {
  const _WavePainter(this.accent);
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    final d = math.min(size.width * .95, size.height * .94);
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * .47), width: d, height: d);
    final hsl = HSLColor.fromColor(accent);
    final warm = hsl.withHue((hsl.hue - 22) % 360).toColor();
    canvas.drawOval(
        rect.inflate(16),
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.transparent,
            accent.withValues(alpha: .08),
            Colors.transparent
          ], stops: const [
            .6,
            .85,
            1
          ]).createShader(rect.inflate(16)));
    for (var i = 9; i >= 0; i--) {
      final ring = rect.deflate(i * .8);
      canvas.drawOval(
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 + i
            ..shader =
                SweepGradient(transform: const GradientRotation(-.9), colors: [
              warm.withValues(alpha: .01),
              accent.withValues(alpha: .65 / (i + 1)),
              warm.withValues(alpha: .8 / (i + 1)),
              accent.withValues(alpha: .04),
              Colors.transparent,
              warm.withValues(alpha: .01)
            ], stops: const [
              0,
              .18,
              .38,
              .62,
              .83,
              1
            ]).createShader(ring));
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.accent != accent;
}
