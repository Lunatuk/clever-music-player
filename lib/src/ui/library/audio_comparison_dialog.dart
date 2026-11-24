import 'package:flutter/material.dart';

import '../../domain/models/audio_document_identity.dart';
import '../../domain/models/audio_source_reference.dart';
import '../../domain/models/track.dart';
import '../../library/audio_comparison.dart';
import '../../library/library_scan_control.dart';
import '../../library/library_track_list.dart';
import '../../library/library_track_variants.dart';
import '../track_display_helpers.dart';

Future<void> showAudioComparisonDialog(
  BuildContext context, {
  required List<Track> tracks,
  required AudioComparisonService comparison,
  AudioMatchRepository? matches,
  LibraryVariantEvidence evidence = const LibraryVariantEvidence(),
  String searchQuery = '',
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AudioComparisonDialog(
          tracks: tracks,
          comparison: comparison,
          matches: matches,
          evidence: evidence,
          searchQuery: searchQuery),
    );

class _AudioComparisonDialog extends StatefulWidget {
  const _AudioComparisonDialog(
      {required this.tracks,
      required this.comparison,
      this.matches,
      required this.evidence,
      required this.searchQuery});

  final List<Track> tracks;
  final AudioComparisonService comparison;
  final AudioMatchRepository? matches;
  final LibraryVariantEvidence evidence;
  final String searchQuery;

  @override
  State<_AudioComparisonDialog> createState() => _AudioComparisonDialogState();
}

class _AudioComparisonDialogState extends State<_AudioComparisonDialog> {
  static const _resultLimit = 100;
  final _selected = <Track>[];
  final _savedMatches = <int, String>{};
  late final TextEditingController _search;
  late final List<Track> _tracks;
  LibraryScanControl? _control;
  AudioComparisonResult? _result;
  AudioCandidateSearchResult? _found;
  AudioMatchProof? _proof;
  String? _saveMessage;
  bool _saving = false;
  bool _finding = false;

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
      _found = null;
      _proof = null;
      _saveMessage = null;
    });
    AudioComparison result;
    try {
      result = await widget.comparison
          .compareWithProof(_selected[0], _selected[1], control: control);
    } on Object {
      result = (result: AudioComparisonResult.unreadable, proof: null);
    }
    if (!mounted) return;
    setState(() {
      _control = null;
      _result = result.result;
      _proof = result.proof;
    });
  }

  Future<void> _findSimilar() async {
    if (_selected.length != 1 || _control != null) return;
    FocusScope.of(context).unfocus();
    final reference = _selected.single;
    final control = LibraryScanControl();
    setState(() {
      _control = control;
      _finding = true;
      _found = null;
      _result = null;
      _proof = null;
      _saveMessage = null;
    });
    final hasLink = _hasCatalogueLink(reference);
    final knownAudio = _knownAudioMatch(reference);
    AudioCandidateSearchResult result;
    try {
      result = await widget.comparison.findSimilarRecordings(
        reference,
        _tracks,
        control: control,
        alreadyKnown: (track) =>
            (hasLink && _hasCatalogueLink(track)) ||
            (knownAudio != null && knownAudio == _knownAudioMatch(track)),
      );
    } on Object {
      result = (
        outcome: AudioCandidateSearchOutcome.unreadable,
        matches: const [],
        checked: 0,
        candidates: 0
      );
    }
    if (!mounted) return;
    setState(() {
      _control = null;
      _finding = false;
      _found = result;
    });
  }

  bool _hasCatalogueLink(Track track) =>
      widget.evidence.identities[track.id]?.any(isLibraryVariantIdentity) ??
      false;

  String? _knownAudioMatch(Track track) =>
      _savedMatches[track.id] ?? widget.evidence.audioMatches[track.id];

  Future<void> _save() async {
    final proof = _proof;
    final matches = widget.matches;
    if (proof == null || matches == null) return;
    setState(() => _saving = true);
    String message;
    AudioMatchSaveResult? saved;
    try {
      saved = await matches.rememberAudioMatch(proof);
      message = switch (saved) {
        AudioMatchSaveResult.saved => 'Совпадение сохранено в медиатеке',
        AudioMatchSaveResult.changed => 'Файлы изменились. Сравни их ещё раз.',
        AudioMatchSaveResult.releaseConflict =>
          'Совпадение звука. Сведения о релизах требуют отдельных строк.',
      };
    } on Object {
      message = 'Не удалось сохранить совпадение. Попробуй ещё раз.';
    }
    if (!mounted) return;
    setState(() {
      if (saved == AudioMatchSaveResult.saved) {
        _savedMatches[proof.first.id!] = proof.key;
        _savedMatches[proof.second.id!] = proof.key;
      }
      _saving = false;
      _proof = null;
      _saveMessage = message;
    });
  }

  void _toggle(Track track) => setState(() {
        if (!_selected.remove(track) && _selected.length < 2) {
          _selected.add(track);
        }
        _result = null;
        _found = null;
        _proof = null;
        _saveMessage = null;
      });

  @override
  Widget build(BuildContext context) {
    final busy = _control != null || _saving;
    final readyToSave = _proof != null && widget.matches != null;
    final availableHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final found = _found;
    final suggested = found?.matches ?? const <Track>[];
    final results = _tracks
        .where((track) =>
            !_selected.any((selected) => _sameFile(selected, track)) &&
            !suggested.any((candidate) => _sameFile(candidate, track)) &&
            trackMatchesSearch(track, _search.text))
        .take(_resultLimit + 1)
        .toList(growable: false);
    final shown = results.length.clamp(0, _resultLimit);
    final message = _saveMessage ??
        (found == null ? null : _candidateMessage(found)) ??
        switch (_result) {
          AudioComparisonResult.equal => 'Звук совпадает',
          AudioComparisonResult.different => 'Звук различается',
          AudioComparisonResult.possiblySameRecording =>
            'Возможно, та же запись. Подсказка по сходству звучания.',
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
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_saving
                          ? 'Сохраняю версии…'
                          : _finding
                              ? 'Ищу похожие записи…'
                              : 'Сравниваю звук двух файлов…'),
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
                      if (_selected.isEmpty)
                        const Text('Для поиска похожих выбери один трек.'),
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
                      for (final track in suggested)
                        _TrackChoice(track: track, onTap: () => _toggle(track)),
                      if (shown == 0 && suggested.isEmpty)
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
          if (_control != null)
            TextButton(
                onPressed: _control!.cancel, child: const Text('Остановить'))
          else if (!_saving) ...[
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть')),
            if (readyToSave)
              FilledButton(
                  onPressed: _save, child: const Text('Сгруппировать версии'))
            else if (_selected.length == 1)
              FilledButton(
                  onPressed: _findSimilar, child: const Text('Найти похожие'))
            else
              FilledButton(
                  onPressed: _selected.length == 2 ? _compare : null,
                  child: const Text('Сравнить')),
          ],
        ],
      ),
    );
  }
}

String _candidateMessage(AudioCandidateSearchResult result) =>
    switch (result.outcome) {
      AudioCandidateSearchOutcome.cancelled => 'Поиск похожих остановлен.',
      AudioCandidateSearchOutcome.timedOut =>
        'Поиск занял слишком много времени.',
      AudioCandidateSearchOutcome.unreadable =>
        'Не удалось прочитать выбранный трек. Проверь доступ и формат.',
      AudioCandidateSearchOutcome.completed when result.candidates == 0 =>
        'Кандидатов по названию, исполнителю и длительности нет.',
      AudioCandidateSearchOutcome.completed when result.checked == 0 =>
        'Не удалось проверить звук у кандидатов.',
      AudioCandidateSearchOutcome.completed =>
        'Возможные версии: ${result.matches.length}. Проверено ${result.checked} из ${result.candidates}.',
    };

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
