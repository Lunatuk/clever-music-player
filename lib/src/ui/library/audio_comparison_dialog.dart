import 'package:flutter/material.dart';

import '../../domain/models/audio_document_identity.dart';
import '../../domain/models/audio_source_reference.dart';
import '../../domain/models/track.dart';
import '../../library/audio_comparison.dart';
import '../../library/library_scan_control.dart';
import '../../library/library_track_list.dart';
import '../track_display_helpers.dart';

Future<void> showAudioComparisonDialog(
  BuildContext context, {
  required List<Track> tracks,
  required AudioComparisonService comparison,
  String searchQuery = '',
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AudioComparisonDialog(
          tracks: tracks, comparison: comparison, searchQuery: searchQuery),
    );

class _AudioComparisonDialog extends StatefulWidget {
  const _AudioComparisonDialog(
      {required this.tracks,
      required this.comparison,
      required this.searchQuery});

  final List<Track> tracks;
  final AudioComparisonService comparison;
  final String searchQuery;

  @override
  State<_AudioComparisonDialog> createState() => _AudioComparisonDialogState();
}

class _AudioComparisonDialogState extends State<_AudioComparisonDialog> {
  static const _resultLimit = 100;
  final _selected = <Track>[];
  late final TextEditingController _search;
  late final List<Track> _tracks;
  LibraryScanControl? _control;
  AudioComparisonResult? _result;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.searchQuery);
    _tracks = sortLibraryTracks(
      widget.tracks.where((track) => !track.isMissing),
      sortOption: LibraryTrackSortOption.title,
    );
  }

  @override
  void dispose() {
    _control?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _compare() async {
    if (_selected.length != 2 || _control != null) return;
    FocusScope.of(context).unfocus();
    final control = LibraryScanControl();
    setState(() {
      _control = control;
      _result = null;
    });
    AudioComparisonResult result;
    try {
      result = await widget.comparison
          .compare(_selected[0], _selected[1], control: control);
    } on Object {
      result = AudioComparisonResult.unreadable;
    }
    if (!mounted) return;
    setState(() {
      _control = null;
      _result = result;
    });
  }

  void _toggle(Track track) => setState(() {
        if (!_selected.remove(track) && _selected.length < 2) {
          _selected.add(track);
        }
        _result = null;
      });

  @override
  Widget build(BuildContext context) {
    final busy = _control != null;
    final availableHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final results = _tracks
        .where((track) =>
            !_selected.any((selected) => _sameFile(selected, track)) &&
            trackMatchesSearch(track, _search.text))
        .take(_resultLimit + 1)
        .toList(growable: false);
    final shown = results.length.clamp(0, _resultLimit);
    final message = switch (_result) {
      AudioComparisonResult.equal => 'Звук совпадает',
      AudioComparisonResult.different => 'Звук различается',
      AudioComparisonResult.unreadable =>
        'Не удалось сравнить файлы. Проверь доступ к ним и формат.',
      AudioComparisonResult.cancelled => 'Сравнение остановлено',
      AudioComparisonResult.timedOut =>
        'Сравнение заняло слишком много времени',
      null => null,
    };
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Сравнить аудио'),
        content: SizedBox(
          width: 510,
          height: (availableHeight * 0.55).clamp(80.0, 430.0),
          child: busy
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Сравниваю звук двух файлов…'),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverList.list(children: [
                      TextField(
                        key: const ValueKey('audio-comparison-search'),
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        decoration:
                            const InputDecoration(labelText: 'Найти трек'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Text('Выбрано ${_selected.length} из 2'),
                      for (final track in _selected)
                        _TrackChoice(
                            track: track,
                            selected: true,
                            onTap: () => _toggle(track)),
                      if (message != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child:
                              Semantics(liveRegion: true, child: Text(message)),
                        ),
                      if (shown == 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text('Подходящих файлов больше нет.'),
                        ),
                    ]),
                    SliverList.builder(
                        itemCount: shown,
                        itemBuilder: (context, index) {
                          final track = results[index];
                          return _TrackChoice(
                              track: track,
                              onTap: _selected.length == 2
                                  ? null
                                  : () => _toggle(track));
                        }),
                    if (results.length > _resultLimit)
                      const SliverToBoxAdapter(
                          child: Text(
                              'Уточни поиск, чтобы увидеть другие файлы.')),
                  ],
                ),
        ),
        actions: [
          if (busy)
            TextButton(
                onPressed: _control!.cancel, child: const Text('Остановить'))
          else ...[
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть')),
            FilledButton(
                onPressed: _selected.length == 2 ? _compare : null,
                child: const Text('Сравнить')),
          ],
        ],
      ),
    );
  }
}

bool _sameFile(Track left, Track right) {
  if (left.filePath == right.filePath) return true;
  final document = audioDocumentIdentity(left.filePath);
  return document != null && document == audioDocumentIdentity(right.filePath);
}

class _TrackChoice extends StatelessWidget {
  const _TrackChoice(
      {required this.track, required this.onTap, this.selected = false});
  final Track track;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final path = track.filePath;
    final document = AudioSourceReference.isContentUriValue(path)
        ? Uri.tryParse(path)?.pathSegments
        : null;
    final parts = (document?.lastOrNull ?? path).split(RegExp(r'[/\\]'));
    final file = parts.skip(parts.length > 2 ? parts.length - 2 : 0).join('/');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      selected: selected,
      title: Text(track.displayTitle,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${artistLabel(track)}\n$file',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(
          selected ? Icons.check_circle_outline : Icons.add_circle_outline),
      onTap: onTap,
    );
  }
}
