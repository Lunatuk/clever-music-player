import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_preview_model.dart';

/// An interactive visual prototype with invented data. Never imports runtime,
/// repositories, native media, files, credentials or networking.
final class DesignPreviewCanvas extends StatefulWidget {
  const DesignPreviewCanvas(
      {super.key,
      required this.direction,
      this.initialPage = PreviewPage.library,
      this.onPageChanged,
      this.fontFamily});
  final PreviewDirection direction;
  final PreviewPage initialPage;
  final ValueChanged<PreviewPage>? onPageChanged;
  final String? fontFamily;
  @override
  State<DesignPreviewCanvas> createState() => _DesignPreviewCanvasState();
}

final class _DesignPreviewCanvasState extends State<DesignPreviewCanvas> {
  late PreviewPage _page = widget.initialPage;
  int _current = 0, _section = 0;
  bool _playing = true,
      _shuffle = false,
      _repeat = false,
      _reverse = false,
      _favoritesOnly = false;
  double _position = .257, _volume = .64;
  String _query = '';
  String? _album;
  final _search = TextEditingController();
  final _favorites = <int>{0, 2};
  final _queue = <int>[1, 2, 3, 4, 5, 6];
  PreviewColors get c => widget.direction.colors;
  PreviewSong get song => previewSongs[_current];
  bool get paper => widget.direction == PreviewDirection.paper;
  bool get midnight => widget.direction == PreviewDirection.midnight;
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

  void _select(int index) {
    setState(() {
      _current = index;
      _position = 0;
      _playing = true;
    });
    _open(PreviewPage.player);
  }

  void _step(int delta) => setState(() {
        _current = (_current + delta) % previewSongs.length;
        _position = 0;
      });
  void _favorite(int index) => setState(() => _favorites.contains(index)
      ? _favorites.remove(index)
      : _favorites.add(index));
  TextStyle _style(double size,
          {bool muted = false, FontWeight weight = FontWeight.w400}) =>
      TextStyle(
          fontSize: size,
          color: muted ? c.muted : c.text,
          fontWeight: weight,
          letterSpacing: size >= 26 ? -.8 : 0);
  Widget _title(String title, {double size = 28}) => Text(title,
      style: _style(size, weight: paper ? FontWeight.w400 : FontWeight.w700));
  Widget _icon(String tip, IconData icon, VoidCallback action,
          {Color? color}) =>
      IconButton(
          tooltip: tip, onPressed: action, icon: Icon(icon, color: color));
  Widget _favoriteButton(int index) => _icon(
      _favorites.contains(index) ? 'Убрать из избранного' : 'В избранное',
      _favorites.contains(index)
          ? Icons.favorite_rounded
          : Icons.favorite_border_rounded,
      () => _favorite(index),
      color: _favorites.contains(index) ? c.accent : c.muted);

  @override
  Widget build(BuildContext context) => Theme(
      data: c.theme(fontFamily: widget.fontFamily),
      child: Material(
          color: c.background,
          child: LayoutBuilder(builder: (context, box) {
            final desktop = box.maxWidth >= 900;
            final body = switch (_page) {
              PreviewPage.library => _library(context, desktop),
              PreviewPage.player => _player(context, desktop),
              PreviewPage.queue => _queuePage(context),
            };
            if (desktop) {
              return Row(children: [
                _rail(),
                Expanded(
                    child: Column(children: [
                  Expanded(
                      child: Row(children: [
                    Expanded(child: body),
                    if (_page == PreviewPage.library &&
                        box.maxWidth >= 1180 &&
                        !paper)
                      _sideDetail(context)
                  ])),
                  _desktopDock(),
                ]))
              ]);
            }
            return Column(children: [
              Expanded(child: body),
              if (_page != PreviewPage.player) ...[
                _mobileDock(),
                NavigationBar(
                    backgroundColor: c.background,
                    indicatorColor: c.accent.withValues(alpha: .16),
                    selectedIndex: _section,
                    onDestinationSelected: (value) => setState(() {
                          _section = value;
                          _album = null;
                          _page = PreviewPage.library;
                        }),
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.library_music_outlined),
                          selectedIcon: Icon(Icons.library_music_rounded),
                          label: 'Музыка'),
                      NavigationDestination(
                          icon: Icon(Icons.waves_rounded), label: 'Волна'),
                      NavigationDestination(
                          icon: Icon(Icons.queue_music_rounded),
                          label: 'Плейлисты')
                    ]),
              ]
            ]);
          })));

  Widget _rail() => Container(
      width: midnight ? 88 : 190,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
      decoration: BoxDecoration(
          border:
              Border(right: BorderSide(color: c.muted.withValues(alpha: .15)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 42),
            child: midnight
                ? Icon(Icons.album_rounded, color: c.accent, size: 32)
                : Text(paper ? 'clever.' : 'clever',
                    style: _style(29, weight: FontWeight.w700))),
        for (final entry in [
          (Icons.library_music_outlined, 'Моя музыка'),
          (Icons.waves_rounded, 'Волна'),
          (Icons.queue_music_rounded, 'Плейлисты')
        ].indexed)
          Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Tooltip(
                  message: entry.$2.$2,
                  child: Material(
                      color:
                          _section == entry.$1 && _page == PreviewPage.library
                              ? c.accent.withValues(alpha: .12)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                                _section = entry.$1;
                                _album = null;
                                _page = PreviewPage.library;
                              }),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 15),
                              child: Row(children: [
                                Icon(entry.$2.$1,
                                    color: _section == entry.$1
                                        ? c.accent
                                        : c.muted,
                                    size: 22),
                                if (!midnight) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text(entry.$2.$2,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: _style(13,
                                              weight: FontWeight.w600)))
                                ],
                              ])))))),
        const Spacer(),
        if (!midnight)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text('МУЗЫКА РЯДОМ',
                  style: _style(10, muted: true, weight: FontWeight.w600))),
      ]));

  Widget _library(BuildContext context, bool desktop) {
    final heading = _section == 1
        ? 'Моя волна'
        : _section == 2
            ? 'Плейлисты'
            : _album ?? 'Моя музыка';
    var indices = List.generate(previewSongs.length, (i) => i).where((i) {
      final s = previewSongs[i];
      final q = _query.toLowerCase().trim();
      return (!_favoritesOnly || _favorites.contains(i)) &&
          (_album == null || s.album == _album) &&
          (q.isEmpty ||
              '${s.title} ${s.artist} ${s.album}'.toLowerCase().contains(q));
    }).toList();
    if (_reverse) indices = indices.reversed.toList();
    final albums = [0, 1, 3, 5];
    final margin = desktop ? 32.0 : 22.0;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: Padding(
              padding:
                  EdgeInsets.fromLTRB(margin, desktop ? 36 : 26, margin, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (midnight)
                      Text('ТВОЁ ПРОСТРАНСТВО',
                          style:
                              _style(10, muted: true, weight: FontWeight.w600)),
                    _title(heading, size: paper ? 34 : 30),
                    const SizedBox(height: 6),
                    Text(
                        _section == 1
                            ? 'Подбор из твоей музыки'
                            : _section == 2
                                ? 'Свои подборки для любого дня'
                                : '${previewSongs.length} треков · на устройстве',
                        style: _style(12, muted: true)),
                    if (_section == 0) ...[
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                key: const ValueKey('preview-search'),
                                controller: _search,
                                onChanged: (v) => setState(() => _query = v),
                                decoration: InputDecoration(
                                    hintText: 'Найти в музыке',
                                    isDense: true,
                                    filled: true,
                                    fillColor: c.panel,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    prefixIcon: Icon(Icons.search_rounded,
                                        size: 20, color: c.muted),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                            paper ? 8 : 14),
                                        borderSide: BorderSide.none)))),
                        _icon('Изменить порядок', Icons.sort_rounded,
                            () => setState(() => _reverse = !_reverse),
                            color: _reverse ? c.accent : c.muted)
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        ChoiceChip(
                            label: const Text('Все треки'),
                            selected: !_favoritesOnly && _album == null,
                            onSelected: (_) => setState(() {
                                  _favoritesOnly = false;
                                  _album = null;
                                })),
                        ChoiceChip(
                            label: const Text('Избранное'),
                            selected: _favoritesOnly,
                            onSelected: (v) =>
                                setState(() => _favoritesOnly = v)),
                      ]),
                    ],
                  ]))),
      if (_section == 1)
        SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.fromLTRB(margin, 4, margin, 24),
                child: _waveHero())),
      if (_section == 2 ||
          paper &&
              _section == 0 &&
              _album == null &&
              _query.isEmpty &&
              !_favoritesOnly)
        SliverPadding(
            padding: EdgeInsets.fromLTRB(margin, 4, margin, 24),
            sliver: SliverLayoutBuilder(builder: (context, box) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final columns = desktop
                  ? (box.crossAxisExtent / 230).floor().clamp(2, 4)
                  : scale > 1.5
                      ? 1
                      : 2;
              final width =
                  (box.crossAxisExtent - 18 * (columns - 1)) / columns;
              return SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final s = previewSongs[albums[index]];
                    return _albumTile(
                        s,
                        width,
                        () => setState(() {
                              _album = s.album;
                              _section = 0;
                            }));
                  }, childCount: albums.length),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 20,
                      mainAxisExtent: width + 64 * scale));
            })),
      if (midnight &&
          _section == 0 &&
          _album == null &&
          _query.isEmpty &&
          !_favoritesOnly)
        SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.fromLTRB(margin, 2, margin, 24),
                child: _continueHero())),
      if (_section != 2) ...[
        SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.symmetric(horizontal: margin, vertical: 8),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          _section == 1
                              ? 'Знакомые треки'
                              : paper
                                  ? 'Треки'
                                  : 'В библиотеке',
                          style: _style(13,
                              muted: true, weight: FontWeight.w600))),
                  Text('${indices.length}', style: _style(12, muted: true)),
                ]))),
        if (indices.isEmpty)
          const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Ничего не найдено')))
        else
          SliverPadding(
              padding: EdgeInsets.fromLTRB(margin - 8, 0, margin - 8, 24),
              sliver: SliverList.builder(
                  itemCount: indices.length,
                  itemBuilder: (context, index) =>
                      _songRow(context, indices[index], showAlbum: desktop))),
      ],
    ]);
  }

  Widget _albumTile(PreviewSong song, double width, VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PreviewCover(
                index: song.cover, size: width, radius: paper ? 6 : 16),
            const SizedBox(height: 12),
            Text(song.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _style(15, weight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _style(12, muted: true))
          ]));
  Widget _continueHero() => Material(
      color: c.panel,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
          onTap: () => _open(PreviewPage.player),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                PreviewCover(index: song.cover, size: 94, radius: 10),
                const SizedBox(width: 18),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('ПРОДОЛЖИТЬ',
                          style:
                              _style(10, muted: true, weight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(song.album,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _style(22, weight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _style(12, muted: true)),
                    ])),
                const SizedBox(width: 8),
                Icon(Icons.play_circle_fill_rounded, color: c.accent, size: 38),
              ]))));
  Widget _waveHero() => Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: c.panel, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.waves_rounded, color: c.accent, size: 56),
        const SizedBox(height: 24),
        _title('В своём ритме', size: 26),
        const SizedBox(height: 8),
        Text('Знакомые альбомы и новые сочетания.',
            style: _style(13, muted: true)),
        const SizedBox(height: 20),
        FilledButton.icon(
            onPressed: () => _select(0),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Слушать волну'))
      ]));

  Widget _songRow(BuildContext context, int index,
      {bool showAlbum = false, Widget? trailing}) {
    final s = previewSongs[index];
    final active = index == _current;
    return Material(
        color: active
            ? c.accent.withValues(alpha: paper ? 0.1 : 0.09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(paper ? 6 : 12),
        child: InkWell(
            onTap: () => _select(index),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(children: [
                  PreviewCover(
                      index: s.cover,
                      size: midnight ? 44 : 50,
                      radius: paper ? 5 : 9),
                  const SizedBox(width: 13),
                  Expanded(
                      flex: 3,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _style(14, weight: FontWeight.w600)
                                    .copyWith(
                                        color: active ? c.accent : c.text)),
                            const SizedBox(height: 4),
                            Text(s.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _style(12, muted: true))
                          ])),
                  if (showAlbum) ...[
                    const SizedBox(width: 16),
                    Expanded(
                        flex: 2,
                        child: Text(s.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _style(12, muted: true))),
                    const SizedBox(width: 12),
                    Text(s.duration, style: _style(12, muted: true)),
                    const SizedBox(width: 10),
                    _favoriteButton(index)
                  ],
                  trailing ??
                      PopupMenuButton<int>(
                          tooltip: 'Действия с треком',
                          icon: Icon(Icons.more_horiz_rounded, color: c.muted),
                          onSelected: (value) => setState(() {
                                if (value == 0) {
                                  _queue.insert(0, index);
                                } else if (value == 1) {
                                  _queue.add(index);
                                } else {
                                  _favorites.contains(index)
                                      ? _favorites.remove(index)
                                      : _favorites.add(index);
                                }
                              }),
                          itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 0, child: Text('Слушать следующим')),
                                const PopupMenuItem(
                                    value: 1, child: Text('В конец очереди')),
                                PopupMenuItem(
                                    value: 2,
                                    child: Text(_favorites.contains(index)
                                        ? 'Убрать из избранного'
                                        : 'В избранное'))
                              ]),
                ]))));
  }

  Widget _controls({bool compact = false}) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _icon('Перемешать', Icons.shuffle_rounded,
            () => setState(() => _shuffle = !_shuffle),
            color: _shuffle ? c.accent : c.muted),
        _icon('Предыдущий трек', Icons.skip_previous_rounded, () => _step(-1)),
        const SizedBox(width: 8),
        IconButton.filled(
            tooltip: _playing ? 'Пауза' : 'Воспроизвести',
            onPressed: () => setState(() => _playing = !_playing),
            style: IconButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.background,
                minimumSize: Size.square(compact ? 42 : 62)),
            icon: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: compact ? 24 : 32)),
        const SizedBox(width: 8),
        _icon('Следующий трек', Icons.skip_next_rounded, () => _step(1)),
        _icon('Повтор', Icons.repeat_rounded,
            () => setState(() => _repeat = !_repeat),
            color: _repeat ? c.accent : c.muted),
      ]));
  String get _positionLabel {
    final parts = song.duration.split(':').map(int.parse).toList();
    final seconds = ((parts[0] * 60 + parts[1]) * _position).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _timeline() => Column(children: [
        Slider(
            value: _position,
            onChanged: (v) => setState(() => _position = v),
            activeColor: c.accent,
            inactiveColor: c.muted.withValues(alpha: .22)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_positionLabel, style: _style(11, muted: true)),
                  Text(song.duration, style: _style(11, muted: true))
                ]))
      ]);

  Widget _player(BuildContext context, bool desktop) =>
      LayoutBuilder(builder: (context, box) {
        final cover = math.min(desktop ? 380.0 : box.maxWidth - 72,
            math.max(150.0, box.maxHeight * .43));
        final details = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _style(desktop ? 34 : 26,
                              weight:
                                  paper ? FontWeight.w400 : FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(song.artist,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _style(15, muted: true))
                    ])),
                _favoriteButton(_current)
              ]),
              const SizedBox(height: 18),
              _timeline(),
              const SizedBox(height: 16),
              _controls(),
              const SizedBox(height: 24),
              TextButton.icon(
                  onPressed: () => _open(PreviewPage.queue),
                  icon: const Icon(Icons.queue_music_rounded),
                  label: Text('Очередь · ${_queue.length} треков')),
            ]);
        return Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 18, 8),
              child: Row(children: [
                _icon('В медиатеку', Icons.keyboard_arrow_down_rounded,
                    () => _open(PreviewPage.library)),
                Expanded(
                    child: Column(children: [
                  Text('СЕЙЧАС ИГРАЕТ',
                      style: _style(10, muted: true, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(song.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(12))
                ])),
                _icon('Открыть очередь', Icons.queue_music_rounded,
                    () => _open(PreviewPage.queue))
              ])),
          Expanded(
              child: SingleChildScrollView(
                  padding: EdgeInsets.all(desktop ? 40 : 26),
                  child: desktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                              Expanded(
                                  child: Center(
                                      child: PreviewCover(
                                          index: song.cover,
                                          size: cover,
                                          radius: paper ? 8 : 24))),
                              const SizedBox(width: 46),
                              Expanded(child: details)
                            ])
                      : Column(children: [
                          const SizedBox(height: 12),
                          Center(
                              child: PreviewCover(
                                  index: song.cover,
                                  size: cover,
                                  radius: paper ? 8 : 24)),
                          const SizedBox(height: 30),
                          details
                        ]))),
        ]);
      });

  Widget _queuePage(BuildContext context) => CustomScrollView(slivers: [
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 14, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: _title('Очередь')),
                        _icon('В медиатеку', Icons.close_rounded,
                            () => _open(PreviewPage.library))
                      ]),
                      const SizedBox(height: 18),
                      Text('Сейчас играет', style: _style(12, muted: true)),
                      const SizedBox(height: 8),
                      _songRow(context, _current),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(
                            child: Text('Далее · ${_queue.length}',
                                style: _style(13, weight: FontWeight.w600))),
                        TextButton(
                            onPressed: _queue.isEmpty
                                ? null
                                : () => setState(_queue.clear),
                            child: const Text('Очистить'))
                      ]),
                    ]))),
        _queue.isEmpty
            ? const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Очередь пуста')))
            : SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                sliver: SliverReorderableList(
                    itemCount: _queue.length,
                    onReorder: (oldIndex, newIndex) => setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          _queue.insert(newIndex, _queue.removeAt(oldIndex));
                        }),
                    itemBuilder: (context, index) => Padding(
                        key: ValueKey('queue-$index-${_queue[index]}'),
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _songRow(context, _queue[index],
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              _icon('Убрать из очереди', Icons.close_rounded,
                                  () => setState(() => _queue.removeAt(index))),
                              ReorderableDragStartListener(
                                  index: index,
                                  child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Icon(Icons.drag_handle_rounded,
                                          color: c.muted)))
                            ]))))),
      ]);

  Widget _mobileDock() => Container(
      decoration: BoxDecoration(
          color: c.panel,
          border:
              Border(top: BorderSide(color: c.muted.withValues(alpha: .16)))),
      child: InkWell(
          onTap: () => _open(PreviewPage.player),
          child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
              child: Row(children: [
                PreviewCover(index: song.cover, size: 44, radius: 8),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _style(13, weight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _style(11, muted: true))
                    ])),
                _icon(
                    _playing ? 'Пауза' : 'Воспроизвести',
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    () => setState(() => _playing = !_playing)),
                _icon('Открыть очередь', Icons.queue_music_rounded,
                    () => _open(PreviewPage.queue)),
              ]))));
  Widget _desktopDock() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
          color: c.panel,
          border:
              Border(top: BorderSide(color: c.muted.withValues(alpha: .15)))),
      child: Row(children: [
        Expanded(
            flex: 3,
            child: InkWell(
                onTap: () => _open(PreviewPage.player),
                child: Row(children: [
                  PreviewCover(index: song.cover, size: 46, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _style(13, weight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _style(11, muted: true))
                      ]))
                ]))),
        Expanded(flex: 4, child: _controls(compact: true)),
        const SizedBox(width: 16),
        SizedBox(
            width: 104,
            child: Slider(
                value: _volume, onChanged: (v) => setState(() => _volume = v))),
        _icon('Открыть очередь', Icons.queue_music_rounded,
            () => _open(PreviewPage.queue)),
      ]));
  Widget _sideDetail(BuildContext context) => Container(
      width: 260,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          border:
              Border(left: BorderSide(color: c.muted.withValues(alpha: .14)))),
      child: midnight
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 12),
              Text('Далее', style: _style(16, weight: FontWeight.w600)),
              const SizedBox(height: 22),
              for (final index in _queue.take(5))
                Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(children: [
                      PreviewCover(
                          index: previewSongs[index].cover,
                          size: 38,
                          radius: 7),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(previewSongs[index].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _style(12)))
                    ])),
              TextButton(
                  onPressed: () => _open(PreviewPage.queue),
                  child: const Text('Вся очередь')),
            ])
          : SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const SizedBox(height: 12),
                  Text('Сейчас играет', style: _style(12, muted: true)),
                  const SizedBox(height: 24),
                  PreviewCover(index: song.cover, size: 212, radius: 18),
                  const SizedBox(height: 22),
                  Text(song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _style(20, weight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(song.artist, style: _style(13, muted: true)),
                  const SizedBox(height: 18),
                  _timeline(),
                  const SizedBox(height: 10),
                  TextButton(
                      onPressed: () => _open(PreviewPage.player),
                      child: const Text('Открыть плеер')),
                ])));
}
