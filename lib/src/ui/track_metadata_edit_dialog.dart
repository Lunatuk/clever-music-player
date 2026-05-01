import 'package:flutter/material.dart';

import '../domain/models/models.dart';
import '../library/manual_track_metadata.dart';

final class TrackMetadataEditDialog extends StatefulWidget {
  const TrackMetadataEditDialog({
    required this.track,
    this.now = _defaultNow,
    super.key,
  });

  final Track track;
  final DateTime Function() now;

  @override
  State<TrackMetadataEditDialog> createState() =>
      _TrackMetadataEditDialogState();
}

final class _TrackMetadataEditDialogState
    extends State<TrackMetadataEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _albumArtistController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;
  late final TextEditingController _trackNumberController;
  late final TextEditingController _discNumberController;

  @override
  void initState() {
    super.initState();
    final track = widget.track;
    _titleController = TextEditingController(
      text: _initialText(track.title ?? track.displayTitle),
    );
    _artistController = TextEditingController(text: _initialText(track.artist));
    _albumController = TextEditingController(text: _initialText(track.album));
    _albumArtistController = TextEditingController(
      text: _initialText(track.albumArtist),
    );
    _genreController = TextEditingController(text: _initialText(track.genre));
    _yearController = TextEditingController(text: _initialInt(track.year));
    _trackNumberController = TextEditingController(
      text: _initialInt(track.trackNumber),
    );
    _discNumberController = TextEditingController(
      text: _initialInt(track.discNumber),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _albumArtistController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _trackNumberController.dispose();
    _discNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackId = widget.track.id;

    return AlertDialog(
      title: const Text('Edit metadata'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('metadataTitleField'),
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  textInputAction: TextInputAction.next,
                  validator: validateManualMetadataTitle,
                ),
                TextFormField(
                  key: const Key('metadataArtistField'),
                  controller: _artistController,
                  decoration: const InputDecoration(labelText: 'Artist'),
                  textInputAction: TextInputAction.next,
                ),
                TextFormField(
                  key: const Key('metadataAlbumField'),
                  controller: _albumController,
                  decoration: const InputDecoration(labelText: 'Album'),
                  textInputAction: TextInputAction.next,
                ),
                TextFormField(
                  key: const Key('metadataAlbumArtistField'),
                  controller: _albumArtistController,
                  decoration: const InputDecoration(labelText: 'Album artist'),
                  textInputAction: TextInputAction.next,
                ),
                TextFormField(
                  key: const Key('metadataGenreField'),
                  controller: _genreController,
                  decoration: const InputDecoration(labelText: 'Genre'),
                  textInputAction: TextInputAction.next,
                ),
                TextFormField(
                  key: const Key('metadataYearField'),
                  controller: _yearController,
                  decoration: const InputDecoration(labelText: 'Year'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: validateOptionalMetadataYear,
                ),
                TextFormField(
                  key: const Key('metadataTrackNumberField'),
                  controller: _trackNumberController,
                  decoration: const InputDecoration(labelText: 'Track number'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (value) => validateOptionalPositiveMetadataInteger(
                    value,
                    'Track number',
                  ),
                ),
                TextFormField(
                  key: const Key('metadataDiscNumberField'),
                  controller: _discNumberController,
                  decoration: const InputDecoration(labelText: 'Disc number'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  validator: (value) => validateOptionalPositiveMetadataInteger(
                    value,
                    'Disc number',
                  ),
                  onFieldSubmitted: (_) => _save(trackId),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: trackId == null ? null : () => _save(trackId),
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save(int? trackId) {
    if (trackId == null || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final update = buildManualTrackMetadataUpdate(
      trackId: trackId,
      updatedAt: widget.now(),
      title: _titleController.text,
      artist: _artistController.text,
      album: _albumController.text,
      albumArtist: _albumArtistController.text,
      genre: _genreController.text,
      year: _yearController.text,
      trackNumber: _trackNumberController.text,
      discNumber: _discNumberController.text,
    );
    Navigator.of(context).pop(update);
  }

  static String _initialText(String? value) {
    return value?.trim() ?? '';
  }

  static String _initialInt(int? value) {
    return value?.toString() ?? '';
  }
}

DateTime _defaultNow() => DateTime.now();
