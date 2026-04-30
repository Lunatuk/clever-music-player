// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LibraryFoldersTable extends LibraryFolders
    with TableInfo<$LibraryFoldersTable, LibraryFolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryFoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isEnabledMeta =
      const VerificationMeta('isEnabled');
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
      'is_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _isRecursiveMeta =
      const VerificationMeta('isRecursive');
  @override
  late final GeneratedColumn<bool> isRecursive = GeneratedColumn<bool>(
      'is_recursive', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_recursive" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _lastScannedAtMeta =
      const VerificationMeta('lastScannedAt');
  @override
  late final GeneratedColumn<DateTime> lastScannedAt =
      GeneratedColumn<DateTime>('last_scanned_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        path,
        displayName,
        isEnabled,
        isRecursive,
        lastScannedAt,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_folders';
  @override
  VerificationContext validateIntegrity(Insertable<LibraryFolderRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    }
    if (data.containsKey('is_enabled')) {
      context.handle(_isEnabledMeta,
          isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta));
    }
    if (data.containsKey('is_recursive')) {
      context.handle(
          _isRecursiveMeta,
          isRecursive.isAcceptableOrUnknown(
              data['is_recursive']!, _isRecursiveMeta));
    }
    if (data.containsKey('last_scanned_at')) {
      context.handle(
          _lastScannedAtMeta,
          lastScannedAt.isAcceptableOrUnknown(
              data['last_scanned_at']!, _lastScannedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LibraryFolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryFolderRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name']),
      isEnabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_enabled'])!,
      isRecursive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_recursive'])!,
      lastScannedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_scanned_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LibraryFoldersTable createAlias(String alias) {
    return $LibraryFoldersTable(attachedDatabase, alias);
  }
}

class LibraryFolderRow extends DataClass
    implements Insertable<LibraryFolderRow> {
  final int id;
  final String path;
  final String? displayName;
  final bool isEnabled;
  final bool isRecursive;
  final DateTime? lastScannedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LibraryFolderRow(
      {required this.id,
      required this.path,
      this.displayName,
      required this.isEnabled,
      required this.isRecursive,
      this.lastScannedAt,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['is_enabled'] = Variable<bool>(isEnabled);
    map['is_recursive'] = Variable<bool>(isRecursive);
    if (!nullToAbsent || lastScannedAt != null) {
      map['last_scanned_at'] = Variable<DateTime>(lastScannedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LibraryFoldersCompanion toCompanion(bool nullToAbsent) {
    return LibraryFoldersCompanion(
      id: Value(id),
      path: Value(path),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      isEnabled: Value(isEnabled),
      isRecursive: Value(isRecursive),
      lastScannedAt: lastScannedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastScannedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LibraryFolderRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryFolderRow(
      id: serializer.fromJson<int>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      isRecursive: serializer.fromJson<bool>(json['isRecursive']),
      lastScannedAt: serializer.fromJson<DateTime?>(json['lastScannedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'path': serializer.toJson<String>(path),
      'displayName': serializer.toJson<String?>(displayName),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'isRecursive': serializer.toJson<bool>(isRecursive),
      'lastScannedAt': serializer.toJson<DateTime?>(lastScannedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LibraryFolderRow copyWith(
          {int? id,
          String? path,
          Value<String?> displayName = const Value.absent(),
          bool? isEnabled,
          bool? isRecursive,
          Value<DateTime?> lastScannedAt = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      LibraryFolderRow(
        id: id ?? this.id,
        path: path ?? this.path,
        displayName: displayName.present ? displayName.value : this.displayName,
        isEnabled: isEnabled ?? this.isEnabled,
        isRecursive: isRecursive ?? this.isRecursive,
        lastScannedAt:
            lastScannedAt.present ? lastScannedAt.value : this.lastScannedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LibraryFolderRow copyWithCompanion(LibraryFoldersCompanion data) {
    return LibraryFolderRow(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      isRecursive:
          data.isRecursive.present ? data.isRecursive.value : this.isRecursive,
      lastScannedAt: data.lastScannedAt.present
          ? data.lastScannedAt.value
          : this.lastScannedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFolderRow(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('displayName: $displayName, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('isRecursive: $isRecursive, ')
          ..write('lastScannedAt: $lastScannedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, path, displayName, isEnabled, isRecursive,
      lastScannedAt, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryFolderRow &&
          other.id == this.id &&
          other.path == this.path &&
          other.displayName == this.displayName &&
          other.isEnabled == this.isEnabled &&
          other.isRecursive == this.isRecursive &&
          other.lastScannedAt == this.lastScannedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LibraryFoldersCompanion extends UpdateCompanion<LibraryFolderRow> {
  final Value<int> id;
  final Value<String> path;
  final Value<String?> displayName;
  final Value<bool> isEnabled;
  final Value<bool> isRecursive;
  final Value<DateTime?> lastScannedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const LibraryFoldersCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.displayName = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.isRecursive = const Value.absent(),
    this.lastScannedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  LibraryFoldersCompanion.insert({
    this.id = const Value.absent(),
    required String path,
    this.displayName = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.isRecursive = const Value.absent(),
    this.lastScannedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  })  : path = Value(path),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<LibraryFolderRow> custom({
    Expression<int>? id,
    Expression<String>? path,
    Expression<String>? displayName,
    Expression<bool>? isEnabled,
    Expression<bool>? isRecursive,
    Expression<DateTime>? lastScannedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (displayName != null) 'display_name': displayName,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (isRecursive != null) 'is_recursive': isRecursive,
      if (lastScannedAt != null) 'last_scanned_at': lastScannedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  LibraryFoldersCompanion copyWith(
      {Value<int>? id,
      Value<String>? path,
      Value<String?>? displayName,
      Value<bool>? isEnabled,
      Value<bool>? isRecursive,
      Value<DateTime?>? lastScannedAt,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return LibraryFoldersCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      displayName: displayName ?? this.displayName,
      isEnabled: isEnabled ?? this.isEnabled,
      isRecursive: isRecursive ?? this.isRecursive,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (isRecursive.present) {
      map['is_recursive'] = Variable<bool>(isRecursive.value);
    }
    if (lastScannedAt.present) {
      map['last_scanned_at'] = Variable<DateTime>(lastScannedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFoldersCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('displayName: $displayName, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('isRecursive: $isRecursive, ')
          ..write('lastScannedAt: $lastScannedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TracksTable extends Tracks with TableInfo<$TracksTable, TrackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _libraryFolderIdMeta =
      const VerificationMeta('libraryFolderId');
  @override
  late final GeneratedColumn<int> libraryFolderId = GeneratedColumn<int>(
      'library_folder_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES library_folders (id) ON DELETE SET NULL'));
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _contentHashMeta =
      const VerificationMeta('contentHash');
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
      'content_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
      'artist', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
      'album', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _albumArtistMeta =
      const VerificationMeta('albumArtist');
  @override
  late final GeneratedColumn<String> albumArtist = GeneratedColumn<String>(
      'album_artist', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
      'genre', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _trackNumberMeta =
      const VerificationMeta('trackNumber');
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
      'track_number', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _discNumberMeta =
      const VerificationMeta('discNumber');
  @override
  late final GeneratedColumn<int> discNumber = GeneratedColumn<int>(
      'disc_number', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
      'year', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _fileSizeBytesMeta =
      const VerificationMeta('fileSizeBytes');
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
      'file_size_bytes', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _modifiedAtMeta =
      const VerificationMeta('modifiedAt');
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
      'modified_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        libraryFolderId,
        filePath,
        contentHash,
        title,
        artist,
        album,
        albumArtist,
        genre,
        durationMs,
        trackNumber,
        discNumber,
        year,
        fileSizeBytes,
        modifiedAt,
        addedAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(Insertable<TrackRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('library_folder_id')) {
      context.handle(
          _libraryFolderIdMeta,
          libraryFolderId.isAcceptableOrUnknown(
              data['library_folder_id']!, _libraryFolderIdMeta));
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
          _contentHashMeta,
          contentHash.isAcceptableOrUnknown(
              data['content_hash']!, _contentHashMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('artist')) {
      context.handle(_artistMeta,
          artist.isAcceptableOrUnknown(data['artist']!, _artistMeta));
    }
    if (data.containsKey('album')) {
      context.handle(
          _albumMeta, album.isAcceptableOrUnknown(data['album']!, _albumMeta));
    }
    if (data.containsKey('album_artist')) {
      context.handle(
          _albumArtistMeta,
          albumArtist.isAcceptableOrUnknown(
              data['album_artist']!, _albumArtistMeta));
    }
    if (data.containsKey('genre')) {
      context.handle(
          _genreMeta, genre.isAcceptableOrUnknown(data['genre']!, _genreMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('track_number')) {
      context.handle(
          _trackNumberMeta,
          trackNumber.isAcceptableOrUnknown(
              data['track_number']!, _trackNumberMeta));
    }
    if (data.containsKey('disc_number')) {
      context.handle(
          _discNumberMeta,
          discNumber.isAcceptableOrUnknown(
              data['disc_number']!, _discNumberMeta));
    }
    if (data.containsKey('year')) {
      context.handle(
          _yearMeta, year.isAcceptableOrUnknown(data['year']!, _yearMeta));
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
          _fileSizeBytesMeta,
          fileSizeBytes.isAcceptableOrUnknown(
              data['file_size_bytes']!, _fileSizeBytesMeta));
    }
    if (data.containsKey('modified_at')) {
      context.handle(
          _modifiedAtMeta,
          modifiedAt.isAcceptableOrUnknown(
              data['modified_at']!, _modifiedAtMeta));
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      libraryFolderId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}library_folder_id']),
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      contentHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_hash']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title']),
      artist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist']),
      album: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}album']),
      albumArtist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}album_artist']),
      genre: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}genre']),
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
      trackNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_number']),
      discNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}disc_number']),
      year: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}year']),
      fileSizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}file_size_bytes']),
      modifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}modified_at']),
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class TrackRow extends DataClass implements Insertable<TrackRow> {
  final int id;
  final int? libraryFolderId;
  final String filePath;
  final String? contentHash;
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final int? durationMs;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final int? fileSizeBytes;
  final DateTime? modifiedAt;
  final DateTime addedAt;
  final DateTime updatedAt;
  const TrackRow(
      {required this.id,
      this.libraryFolderId,
      required this.filePath,
      this.contentHash,
      this.title,
      this.artist,
      this.album,
      this.albumArtist,
      this.genre,
      this.durationMs,
      this.trackNumber,
      this.discNumber,
      this.year,
      this.fileSizeBytes,
      this.modifiedAt,
      required this.addedAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || libraryFolderId != null) {
      map['library_folder_id'] = Variable<int>(libraryFolderId);
    }
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || albumArtist != null) {
      map['album_artist'] = Variable<String>(albumArtist);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    if (!nullToAbsent || discNumber != null) {
      map['disc_number'] = Variable<int>(discNumber);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || fileSizeBytes != null) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    }
    if (!nullToAbsent || modifiedAt != null) {
      map['modified_at'] = Variable<DateTime>(modifiedAt);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      id: Value(id),
      libraryFolderId: libraryFolderId == null && nullToAbsent
          ? const Value.absent()
          : Value(libraryFolderId),
      filePath: Value(filePath),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      artist:
          artist == null && nullToAbsent ? const Value.absent() : Value(artist),
      album:
          album == null && nullToAbsent ? const Value.absent() : Value(album),
      albumArtist: albumArtist == null && nullToAbsent
          ? const Value.absent()
          : Value(albumArtist),
      genre:
          genre == null && nullToAbsent ? const Value.absent() : Value(genre),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
      discNumber: discNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(discNumber),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      fileSizeBytes: fileSizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSizeBytes),
      modifiedAt: modifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(modifiedAt),
      addedAt: Value(addedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TrackRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackRow(
      id: serializer.fromJson<int>(json['id']),
      libraryFolderId: serializer.fromJson<int?>(json['libraryFolderId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      title: serializer.fromJson<String?>(json['title']),
      artist: serializer.fromJson<String?>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      albumArtist: serializer.fromJson<String?>(json['albumArtist']),
      genre: serializer.fromJson<String?>(json['genre']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      discNumber: serializer.fromJson<int?>(json['discNumber']),
      year: serializer.fromJson<int?>(json['year']),
      fileSizeBytes: serializer.fromJson<int?>(json['fileSizeBytes']),
      modifiedAt: serializer.fromJson<DateTime?>(json['modifiedAt']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'libraryFolderId': serializer.toJson<int?>(libraryFolderId),
      'filePath': serializer.toJson<String>(filePath),
      'contentHash': serializer.toJson<String?>(contentHash),
      'title': serializer.toJson<String?>(title),
      'artist': serializer.toJson<String?>(artist),
      'album': serializer.toJson<String?>(album),
      'albumArtist': serializer.toJson<String?>(albumArtist),
      'genre': serializer.toJson<String?>(genre),
      'durationMs': serializer.toJson<int?>(durationMs),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'discNumber': serializer.toJson<int?>(discNumber),
      'year': serializer.toJson<int?>(year),
      'fileSizeBytes': serializer.toJson<int?>(fileSizeBytes),
      'modifiedAt': serializer.toJson<DateTime?>(modifiedAt),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TrackRow copyWith(
          {int? id,
          Value<int?> libraryFolderId = const Value.absent(),
          String? filePath,
          Value<String?> contentHash = const Value.absent(),
          Value<String?> title = const Value.absent(),
          Value<String?> artist = const Value.absent(),
          Value<String?> album = const Value.absent(),
          Value<String?> albumArtist = const Value.absent(),
          Value<String?> genre = const Value.absent(),
          Value<int?> durationMs = const Value.absent(),
          Value<int?> trackNumber = const Value.absent(),
          Value<int?> discNumber = const Value.absent(),
          Value<int?> year = const Value.absent(),
          Value<int?> fileSizeBytes = const Value.absent(),
          Value<DateTime?> modifiedAt = const Value.absent(),
          DateTime? addedAt,
          DateTime? updatedAt}) =>
      TrackRow(
        id: id ?? this.id,
        libraryFolderId: libraryFolderId.present
            ? libraryFolderId.value
            : this.libraryFolderId,
        filePath: filePath ?? this.filePath,
        contentHash: contentHash.present ? contentHash.value : this.contentHash,
        title: title.present ? title.value : this.title,
        artist: artist.present ? artist.value : this.artist,
        album: album.present ? album.value : this.album,
        albumArtist: albumArtist.present ? albumArtist.value : this.albumArtist,
        genre: genre.present ? genre.value : this.genre,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
        trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
        discNumber: discNumber.present ? discNumber.value : this.discNumber,
        year: year.present ? year.value : this.year,
        fileSizeBytes:
            fileSizeBytes.present ? fileSizeBytes.value : this.fileSizeBytes,
        modifiedAt: modifiedAt.present ? modifiedAt.value : this.modifiedAt,
        addedAt: addedAt ?? this.addedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  TrackRow copyWithCompanion(TracksCompanion data) {
    return TrackRow(
      id: data.id.present ? data.id.value : this.id,
      libraryFolderId: data.libraryFolderId.present
          ? data.libraryFolderId.value
          : this.libraryFolderId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      contentHash:
          data.contentHash.present ? data.contentHash.value : this.contentHash,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      albumArtist:
          data.albumArtist.present ? data.albumArtist.value : this.albumArtist,
      genre: data.genre.present ? data.genre.value : this.genre,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      trackNumber:
          data.trackNumber.present ? data.trackNumber.value : this.trackNumber,
      discNumber:
          data.discNumber.present ? data.discNumber.value : this.discNumber,
      year: data.year.present ? data.year.value : this.year,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      modifiedAt:
          data.modifiedAt.present ? data.modifiedAt.value : this.modifiedAt,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackRow(')
          ..write('id: $id, ')
          ..write('libraryFolderId: $libraryFolderId, ')
          ..write('filePath: $filePath, ')
          ..write('contentHash: $contentHash, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('genre: $genre, ')
          ..write('durationMs: $durationMs, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      libraryFolderId,
      filePath,
      contentHash,
      title,
      artist,
      album,
      albumArtist,
      genre,
      durationMs,
      trackNumber,
      discNumber,
      year,
      fileSizeBytes,
      modifiedAt,
      addedAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackRow &&
          other.id == this.id &&
          other.libraryFolderId == this.libraryFolderId &&
          other.filePath == this.filePath &&
          other.contentHash == this.contentHash &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.albumArtist == this.albumArtist &&
          other.genre == this.genre &&
          other.durationMs == this.durationMs &&
          other.trackNumber == this.trackNumber &&
          other.discNumber == this.discNumber &&
          other.year == this.year &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.modifiedAt == this.modifiedAt &&
          other.addedAt == this.addedAt &&
          other.updatedAt == this.updatedAt);
}

class TracksCompanion extends UpdateCompanion<TrackRow> {
  final Value<int> id;
  final Value<int?> libraryFolderId;
  final Value<String> filePath;
  final Value<String?> contentHash;
  final Value<String?> title;
  final Value<String?> artist;
  final Value<String?> album;
  final Value<String?> albumArtist;
  final Value<String?> genre;
  final Value<int?> durationMs;
  final Value<int?> trackNumber;
  final Value<int?> discNumber;
  final Value<int?> year;
  final Value<int?> fileSizeBytes;
  final Value<DateTime?> modifiedAt;
  final Value<DateTime> addedAt;
  final Value<DateTime> updatedAt;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.libraryFolderId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.genre = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TracksCompanion.insert({
    this.id = const Value.absent(),
    this.libraryFolderId = const Value.absent(),
    required String filePath,
    this.contentHash = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.genre = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    required DateTime addedAt,
    required DateTime updatedAt,
  })  : filePath = Value(filePath),
        addedAt = Value(addedAt),
        updatedAt = Value(updatedAt);
  static Insertable<TrackRow> custom({
    Expression<int>? id,
    Expression<int>? libraryFolderId,
    Expression<String>? filePath,
    Expression<String>? contentHash,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? albumArtist,
    Expression<String>? genre,
    Expression<int>? durationMs,
    Expression<int>? trackNumber,
    Expression<int>? discNumber,
    Expression<int>? year,
    Expression<int>? fileSizeBytes,
    Expression<DateTime>? modifiedAt,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (libraryFolderId != null) 'library_folder_id': libraryFolderId,
      if (filePath != null) 'file_path': filePath,
      if (contentHash != null) 'content_hash': contentHash,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (albumArtist != null) 'album_artist': albumArtist,
      if (genre != null) 'genre': genre,
      if (durationMs != null) 'duration_ms': durationMs,
      if (trackNumber != null) 'track_number': trackNumber,
      if (discNumber != null) 'disc_number': discNumber,
      if (year != null) 'year': year,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (addedAt != null) 'added_at': addedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  TracksCompanion copyWith(
      {Value<int>? id,
      Value<int?>? libraryFolderId,
      Value<String>? filePath,
      Value<String?>? contentHash,
      Value<String?>? title,
      Value<String?>? artist,
      Value<String?>? album,
      Value<String?>? albumArtist,
      Value<String?>? genre,
      Value<int?>? durationMs,
      Value<int?>? trackNumber,
      Value<int?>? discNumber,
      Value<int?>? year,
      Value<int?>? fileSizeBytes,
      Value<DateTime?>? modifiedAt,
      Value<DateTime>? addedAt,
      Value<DateTime>? updatedAt}) {
    return TracksCompanion(
      id: id ?? this.id,
      libraryFolderId: libraryFolderId ?? this.libraryFolderId,
      filePath: filePath ?? this.filePath,
      contentHash: contentHash ?? this.contentHash,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      durationMs: durationMs ?? this.durationMs,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (libraryFolderId.present) {
      map['library_folder_id'] = Variable<int>(libraryFolderId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (albumArtist.present) {
      map['album_artist'] = Variable<String>(albumArtist.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (discNumber.present) {
      map['disc_number'] = Variable<int>(discNumber.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('id: $id, ')
          ..write('libraryFolderId: $libraryFolderId, ')
          ..write('filePath: $filePath, ')
          ..write('contentHash: $contentHash, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('genre: $genre, ')
          ..write('durationMs: $durationMs, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PlaybackEventsTable extends PlaybackEvents
    with TableInfo<$PlaybackEventsTable, PlaybackEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _trackIdMeta =
      const VerificationMeta('trackId');
  @override
  late final GeneratedColumn<int> trackId = GeneratedColumn<int>(
      'track_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES tracks (id) ON DELETE CASCADE'));
  static const VerificationMeta _eventTypeMeta =
      const VerificationMeta('eventType');
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
      'event_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _occurredAtMeta =
      const VerificationMeta('occurredAt');
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
      'occurred_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _positionMsMeta =
      const VerificationMeta('positionMs');
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
      'position_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _waveModeMeta =
      const VerificationMeta('waveMode');
  @override
  late final GeneratedColumn<String> waveMode = GeneratedColumn<String>(
      'wave_mode', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _metadataJsonMeta =
      const VerificationMeta('metadataJson');
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
      'metadata_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        trackId,
        eventType,
        occurredAt,
        positionMs,
        durationMs,
        waveMode,
        metadataJson
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_events';
  @override
  VerificationContext validateIntegrity(Insertable<PlaybackEventRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('track_id')) {
      context.handle(_trackIdMeta,
          trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta));
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(_eventTypeMeta,
          eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta));
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
          _occurredAtMeta,
          occurredAt.isAcceptableOrUnknown(
              data['occurred_at']!, _occurredAtMeta));
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
          _positionMsMeta,
          positionMs.isAcceptableOrUnknown(
              data['position_ms']!, _positionMsMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('wave_mode')) {
      context.handle(_waveModeMeta,
          waveMode.isAcceptableOrUnknown(data['wave_mode']!, _waveModeMeta));
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
          _metadataJsonMeta,
          metadataJson.isAcceptableOrUnknown(
              data['metadata_json']!, _metadataJsonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaybackEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackEventRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      trackId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_id'])!,
      eventType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}event_type'])!,
      occurredAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}occurred_at'])!,
      positionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position_ms']),
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
      waveMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}wave_mode']),
      metadataJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata_json']),
    );
  }

  @override
  $PlaybackEventsTable createAlias(String alias) {
    return $PlaybackEventsTable(attachedDatabase, alias);
  }
}

class PlaybackEventRow extends DataClass
    implements Insertable<PlaybackEventRow> {
  final int id;
  final int trackId;
  final String eventType;
  final DateTime occurredAt;
  final int? positionMs;
  final int? durationMs;
  final String? waveMode;
  final String? metadataJson;
  const PlaybackEventRow(
      {required this.id,
      required this.trackId,
      required this.eventType,
      required this.occurredAt,
      this.positionMs,
      this.durationMs,
      this.waveMode,
      this.metadataJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['track_id'] = Variable<int>(trackId);
    map['event_type'] = Variable<String>(eventType);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    if (!nullToAbsent || positionMs != null) {
      map['position_ms'] = Variable<int>(positionMs);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || waveMode != null) {
      map['wave_mode'] = Variable<String>(waveMode);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    return map;
  }

  PlaybackEventsCompanion toCompanion(bool nullToAbsent) {
    return PlaybackEventsCompanion(
      id: Value(id),
      trackId: Value(trackId),
      eventType: Value(eventType),
      occurredAt: Value(occurredAt),
      positionMs: positionMs == null && nullToAbsent
          ? const Value.absent()
          : Value(positionMs),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      waveMode: waveMode == null && nullToAbsent
          ? const Value.absent()
          : Value(waveMode),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
    );
  }

  factory PlaybackEventRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackEventRow(
      id: serializer.fromJson<int>(json['id']),
      trackId: serializer.fromJson<int>(json['trackId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      positionMs: serializer.fromJson<int?>(json['positionMs']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      waveMode: serializer.fromJson<String?>(json['waveMode']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackId': serializer.toJson<int>(trackId),
      'eventType': serializer.toJson<String>(eventType),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'positionMs': serializer.toJson<int?>(positionMs),
      'durationMs': serializer.toJson<int?>(durationMs),
      'waveMode': serializer.toJson<String?>(waveMode),
      'metadataJson': serializer.toJson<String?>(metadataJson),
    };
  }

  PlaybackEventRow copyWith(
          {int? id,
          int? trackId,
          String? eventType,
          DateTime? occurredAt,
          Value<int?> positionMs = const Value.absent(),
          Value<int?> durationMs = const Value.absent(),
          Value<String?> waveMode = const Value.absent(),
          Value<String?> metadataJson = const Value.absent()}) =>
      PlaybackEventRow(
        id: id ?? this.id,
        trackId: trackId ?? this.trackId,
        eventType: eventType ?? this.eventType,
        occurredAt: occurredAt ?? this.occurredAt,
        positionMs: positionMs.present ? positionMs.value : this.positionMs,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
        waveMode: waveMode.present ? waveMode.value : this.waveMode,
        metadataJson:
            metadataJson.present ? metadataJson.value : this.metadataJson,
      );
  PlaybackEventRow copyWithCompanion(PlaybackEventsCompanion data) {
    return PlaybackEventRow(
      id: data.id.present ? data.id.value : this.id,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      occurredAt:
          data.occurredAt.present ? data.occurredAt.value : this.occurredAt,
      positionMs:
          data.positionMs.present ? data.positionMs.value : this.positionMs,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      waveMode: data.waveMode.present ? data.waveMode.value : this.waveMode,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackEventRow(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('eventType: $eventType, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('waveMode: $waveMode, ')
          ..write('metadataJson: $metadataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, trackId, eventType, occurredAt,
      positionMs, durationMs, waveMode, metadataJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackEventRow &&
          other.id == this.id &&
          other.trackId == this.trackId &&
          other.eventType == this.eventType &&
          other.occurredAt == this.occurredAt &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.waveMode == this.waveMode &&
          other.metadataJson == this.metadataJson);
}

class PlaybackEventsCompanion extends UpdateCompanion<PlaybackEventRow> {
  final Value<int> id;
  final Value<int> trackId;
  final Value<String> eventType;
  final Value<DateTime> occurredAt;
  final Value<int?> positionMs;
  final Value<int?> durationMs;
  final Value<String?> waveMode;
  final Value<String?> metadataJson;
  const PlaybackEventsCompanion({
    this.id = const Value.absent(),
    this.trackId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.waveMode = const Value.absent(),
    this.metadataJson = const Value.absent(),
  });
  PlaybackEventsCompanion.insert({
    this.id = const Value.absent(),
    required int trackId,
    required String eventType,
    required DateTime occurredAt,
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.waveMode = const Value.absent(),
    this.metadataJson = const Value.absent(),
  })  : trackId = Value(trackId),
        eventType = Value(eventType),
        occurredAt = Value(occurredAt);
  static Insertable<PlaybackEventRow> custom({
    Expression<int>? id,
    Expression<int>? trackId,
    Expression<String>? eventType,
    Expression<DateTime>? occurredAt,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<String>? waveMode,
    Expression<String>? metadataJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackId != null) 'track_id': trackId,
      if (eventType != null) 'event_type': eventType,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (waveMode != null) 'wave_mode': waveMode,
      if (metadataJson != null) 'metadata_json': metadataJson,
    });
  }

  PlaybackEventsCompanion copyWith(
      {Value<int>? id,
      Value<int>? trackId,
      Value<String>? eventType,
      Value<DateTime>? occurredAt,
      Value<int?>? positionMs,
      Value<int?>? durationMs,
      Value<String?>? waveMode,
      Value<String?>? metadataJson}) {
    return PlaybackEventsCompanion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      eventType: eventType ?? this.eventType,
      occurredAt: occurredAt ?? this.occurredAt,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      waveMode: waveMode ?? this.waveMode,
      metadataJson: metadataJson ?? this.metadataJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<int>(trackId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (waveMode.present) {
      map['wave_mode'] = Variable<String>(waveMode.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackEventsCompanion(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('eventType: $eventType, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('waveMode: $waveMode, ')
          ..write('metadataJson: $metadataJson')
          ..write(')'))
        .toString();
  }
}

class $TrackUserStatesTable extends TrackUserStates
    with TableInfo<$TrackUserStatesTable, TrackUserStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackUserStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackIdMeta =
      const VerificationMeta('trackId');
  @override
  late final GeneratedColumn<int> trackId = GeneratedColumn<int>(
      'track_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES tracks (id) ON DELETE CASCADE'));
  static const VerificationMeta _isFavoriteMeta =
      const VerificationMeta('isFavorite');
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
      'is_favorite', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_favorite" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isHiddenMeta =
      const VerificationMeta('isHidden');
  @override
  late final GeneratedColumn<bool> isHidden = GeneratedColumn<bool>(
      'is_hidden', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_hidden" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
      'rating', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _playCountMeta =
      const VerificationMeta('playCount');
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
      'play_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _skipCountMeta =
      const VerificationMeta('skipCount');
  @override
  late final GeneratedColumn<int> skipCount = GeneratedColumn<int>(
      'skip_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastPlayedAtMeta =
      const VerificationMeta('lastPlayedAt');
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
      'last_played_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastSkippedAtMeta =
      const VerificationMeta('lastSkippedAt');
  @override
  late final GeneratedColumn<DateTime> lastSkippedAt =
      GeneratedColumn<DateTime>('last_skipped_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastCompletedAtMeta =
      const VerificationMeta('lastCompletedAt');
  @override
  late final GeneratedColumn<DateTime> lastCompletedAt =
      GeneratedColumn<DateTime>('last_completed_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _userScoreBoostMeta =
      const VerificationMeta('userScoreBoost');
  @override
  late final GeneratedColumn<double> userScoreBoost = GeneratedColumn<double>(
      'user_score_boost', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _preferredWaveModeMeta =
      const VerificationMeta('preferredWaveMode');
  @override
  late final GeneratedColumn<String> preferredWaveMode =
      GeneratedColumn<String>('preferred_wave_mode', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        trackId,
        isFavorite,
        isHidden,
        rating,
        playCount,
        skipCount,
        lastPlayedAt,
        lastSkippedAt,
        lastCompletedAt,
        userScoreBoost,
        preferredWaveMode,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_user_state';
  @override
  VerificationContext validateIntegrity(Insertable<TrackUserStateRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_id')) {
      context.handle(_trackIdMeta,
          trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta));
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
          _isFavoriteMeta,
          isFavorite.isAcceptableOrUnknown(
              data['is_favorite']!, _isFavoriteMeta));
    }
    if (data.containsKey('is_hidden')) {
      context.handle(_isHiddenMeta,
          isHidden.isAcceptableOrUnknown(data['is_hidden']!, _isHiddenMeta));
    }
    if (data.containsKey('rating')) {
      context.handle(_ratingMeta,
          rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta));
    }
    if (data.containsKey('play_count')) {
      context.handle(_playCountMeta,
          playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta));
    }
    if (data.containsKey('skip_count')) {
      context.handle(_skipCountMeta,
          skipCount.isAcceptableOrUnknown(data['skip_count']!, _skipCountMeta));
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
          _lastPlayedAtMeta,
          lastPlayedAt.isAcceptableOrUnknown(
              data['last_played_at']!, _lastPlayedAtMeta));
    }
    if (data.containsKey('last_skipped_at')) {
      context.handle(
          _lastSkippedAtMeta,
          lastSkippedAt.isAcceptableOrUnknown(
              data['last_skipped_at']!, _lastSkippedAtMeta));
    }
    if (data.containsKey('last_completed_at')) {
      context.handle(
          _lastCompletedAtMeta,
          lastCompletedAt.isAcceptableOrUnknown(
              data['last_completed_at']!, _lastCompletedAtMeta));
    }
    if (data.containsKey('user_score_boost')) {
      context.handle(
          _userScoreBoostMeta,
          userScoreBoost.isAcceptableOrUnknown(
              data['user_score_boost']!, _userScoreBoostMeta));
    }
    if (data.containsKey('preferred_wave_mode')) {
      context.handle(
          _preferredWaveModeMeta,
          preferredWaveMode.isAcceptableOrUnknown(
              data['preferred_wave_mode']!, _preferredWaveModeMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackId};
  @override
  TrackUserStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackUserStateRow(
      trackId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_id'])!,
      isFavorite: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_favorite'])!,
      isHidden: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_hidden'])!,
      rating: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rating']),
      playCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}play_count'])!,
      skipCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}skip_count'])!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_played_at']),
      lastSkippedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_skipped_at']),
      lastCompletedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_completed_at']),
      userScoreBoost: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}user_score_boost'])!,
      preferredWaveMode: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}preferred_wave_mode']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TrackUserStatesTable createAlias(String alias) {
    return $TrackUserStatesTable(attachedDatabase, alias);
  }
}

class TrackUserStateRow extends DataClass
    implements Insertable<TrackUserStateRow> {
  final int trackId;
  final bool isFavorite;
  final bool isHidden;
  final int? rating;
  final int playCount;
  final int skipCount;
  final DateTime? lastPlayedAt;
  final DateTime? lastSkippedAt;
  final DateTime? lastCompletedAt;
  final double userScoreBoost;
  final String? preferredWaveMode;
  final DateTime updatedAt;
  const TrackUserStateRow(
      {required this.trackId,
      required this.isFavorite,
      required this.isHidden,
      this.rating,
      required this.playCount,
      required this.skipCount,
      this.lastPlayedAt,
      this.lastSkippedAt,
      this.lastCompletedAt,
      required this.userScoreBoost,
      this.preferredWaveMode,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_id'] = Variable<int>(trackId);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['is_hidden'] = Variable<bool>(isHidden);
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<int>(rating);
    }
    map['play_count'] = Variable<int>(playCount);
    map['skip_count'] = Variable<int>(skipCount);
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    }
    if (!nullToAbsent || lastSkippedAt != null) {
      map['last_skipped_at'] = Variable<DateTime>(lastSkippedAt);
    }
    if (!nullToAbsent || lastCompletedAt != null) {
      map['last_completed_at'] = Variable<DateTime>(lastCompletedAt);
    }
    map['user_score_boost'] = Variable<double>(userScoreBoost);
    if (!nullToAbsent || preferredWaveMode != null) {
      map['preferred_wave_mode'] = Variable<String>(preferredWaveMode);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TrackUserStatesCompanion toCompanion(bool nullToAbsent) {
    return TrackUserStatesCompanion(
      trackId: Value(trackId),
      isFavorite: Value(isFavorite),
      isHidden: Value(isHidden),
      rating:
          rating == null && nullToAbsent ? const Value.absent() : Value(rating),
      playCount: Value(playCount),
      skipCount: Value(skipCount),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
      lastSkippedAt: lastSkippedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSkippedAt),
      lastCompletedAt: lastCompletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCompletedAt),
      userScoreBoost: Value(userScoreBoost),
      preferredWaveMode: preferredWaveMode == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredWaveMode),
      updatedAt: Value(updatedAt),
    );
  }

  factory TrackUserStateRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackUserStateRow(
      trackId: serializer.fromJson<int>(json['trackId']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      isHidden: serializer.fromJson<bool>(json['isHidden']),
      rating: serializer.fromJson<int?>(json['rating']),
      playCount: serializer.fromJson<int>(json['playCount']),
      skipCount: serializer.fromJson<int>(json['skipCount']),
      lastPlayedAt: serializer.fromJson<DateTime?>(json['lastPlayedAt']),
      lastSkippedAt: serializer.fromJson<DateTime?>(json['lastSkippedAt']),
      lastCompletedAt: serializer.fromJson<DateTime?>(json['lastCompletedAt']),
      userScoreBoost: serializer.fromJson<double>(json['userScoreBoost']),
      preferredWaveMode:
          serializer.fromJson<String?>(json['preferredWaveMode']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackId': serializer.toJson<int>(trackId),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'isHidden': serializer.toJson<bool>(isHidden),
      'rating': serializer.toJson<int?>(rating),
      'playCount': serializer.toJson<int>(playCount),
      'skipCount': serializer.toJson<int>(skipCount),
      'lastPlayedAt': serializer.toJson<DateTime?>(lastPlayedAt),
      'lastSkippedAt': serializer.toJson<DateTime?>(lastSkippedAt),
      'lastCompletedAt': serializer.toJson<DateTime?>(lastCompletedAt),
      'userScoreBoost': serializer.toJson<double>(userScoreBoost),
      'preferredWaveMode': serializer.toJson<String?>(preferredWaveMode),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TrackUserStateRow copyWith(
          {int? trackId,
          bool? isFavorite,
          bool? isHidden,
          Value<int?> rating = const Value.absent(),
          int? playCount,
          int? skipCount,
          Value<DateTime?> lastPlayedAt = const Value.absent(),
          Value<DateTime?> lastSkippedAt = const Value.absent(),
          Value<DateTime?> lastCompletedAt = const Value.absent(),
          double? userScoreBoost,
          Value<String?> preferredWaveMode = const Value.absent(),
          DateTime? updatedAt}) =>
      TrackUserStateRow(
        trackId: trackId ?? this.trackId,
        isFavorite: isFavorite ?? this.isFavorite,
        isHidden: isHidden ?? this.isHidden,
        rating: rating.present ? rating.value : this.rating,
        playCount: playCount ?? this.playCount,
        skipCount: skipCount ?? this.skipCount,
        lastPlayedAt:
            lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
        lastSkippedAt:
            lastSkippedAt.present ? lastSkippedAt.value : this.lastSkippedAt,
        lastCompletedAt: lastCompletedAt.present
            ? lastCompletedAt.value
            : this.lastCompletedAt,
        userScoreBoost: userScoreBoost ?? this.userScoreBoost,
        preferredWaveMode: preferredWaveMode.present
            ? preferredWaveMode.value
            : this.preferredWaveMode,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  TrackUserStateRow copyWithCompanion(TrackUserStatesCompanion data) {
    return TrackUserStateRow(
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      isFavorite:
          data.isFavorite.present ? data.isFavorite.value : this.isFavorite,
      isHidden: data.isHidden.present ? data.isHidden.value : this.isHidden,
      rating: data.rating.present ? data.rating.value : this.rating,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      skipCount: data.skipCount.present ? data.skipCount.value : this.skipCount,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
      lastSkippedAt: data.lastSkippedAt.present
          ? data.lastSkippedAt.value
          : this.lastSkippedAt,
      lastCompletedAt: data.lastCompletedAt.present
          ? data.lastCompletedAt.value
          : this.lastCompletedAt,
      userScoreBoost: data.userScoreBoost.present
          ? data.userScoreBoost.value
          : this.userScoreBoost,
      preferredWaveMode: data.preferredWaveMode.present
          ? data.preferredWaveMode.value
          : this.preferredWaveMode,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackUserStateRow(')
          ..write('trackId: $trackId, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isHidden: $isHidden, ')
          ..write('rating: $rating, ')
          ..write('playCount: $playCount, ')
          ..write('skipCount: $skipCount, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('lastSkippedAt: $lastSkippedAt, ')
          ..write('lastCompletedAt: $lastCompletedAt, ')
          ..write('userScoreBoost: $userScoreBoost, ')
          ..write('preferredWaveMode: $preferredWaveMode, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      trackId,
      isFavorite,
      isHidden,
      rating,
      playCount,
      skipCount,
      lastPlayedAt,
      lastSkippedAt,
      lastCompletedAt,
      userScoreBoost,
      preferredWaveMode,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackUserStateRow &&
          other.trackId == this.trackId &&
          other.isFavorite == this.isFavorite &&
          other.isHidden == this.isHidden &&
          other.rating == this.rating &&
          other.playCount == this.playCount &&
          other.skipCount == this.skipCount &&
          other.lastPlayedAt == this.lastPlayedAt &&
          other.lastSkippedAt == this.lastSkippedAt &&
          other.lastCompletedAt == this.lastCompletedAt &&
          other.userScoreBoost == this.userScoreBoost &&
          other.preferredWaveMode == this.preferredWaveMode &&
          other.updatedAt == this.updatedAt);
}

class TrackUserStatesCompanion extends UpdateCompanion<TrackUserStateRow> {
  final Value<int> trackId;
  final Value<bool> isFavorite;
  final Value<bool> isHidden;
  final Value<int?> rating;
  final Value<int> playCount;
  final Value<int> skipCount;
  final Value<DateTime?> lastPlayedAt;
  final Value<DateTime?> lastSkippedAt;
  final Value<DateTime?> lastCompletedAt;
  final Value<double> userScoreBoost;
  final Value<String?> preferredWaveMode;
  final Value<DateTime> updatedAt;
  const TrackUserStatesCompanion({
    this.trackId = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isHidden = const Value.absent(),
    this.rating = const Value.absent(),
    this.playCount = const Value.absent(),
    this.skipCount = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.lastSkippedAt = const Value.absent(),
    this.lastCompletedAt = const Value.absent(),
    this.userScoreBoost = const Value.absent(),
    this.preferredWaveMode = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TrackUserStatesCompanion.insert({
    this.trackId = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isHidden = const Value.absent(),
    this.rating = const Value.absent(),
    this.playCount = const Value.absent(),
    this.skipCount = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.lastSkippedAt = const Value.absent(),
    this.lastCompletedAt = const Value.absent(),
    this.userScoreBoost = const Value.absent(),
    this.preferredWaveMode = const Value.absent(),
    required DateTime updatedAt,
  }) : updatedAt = Value(updatedAt);
  static Insertable<TrackUserStateRow> custom({
    Expression<int>? trackId,
    Expression<bool>? isFavorite,
    Expression<bool>? isHidden,
    Expression<int>? rating,
    Expression<int>? playCount,
    Expression<int>? skipCount,
    Expression<DateTime>? lastPlayedAt,
    Expression<DateTime>? lastSkippedAt,
    Expression<DateTime>? lastCompletedAt,
    Expression<double>? userScoreBoost,
    Expression<String>? preferredWaveMode,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (trackId != null) 'track_id': trackId,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (isHidden != null) 'is_hidden': isHidden,
      if (rating != null) 'rating': rating,
      if (playCount != null) 'play_count': playCount,
      if (skipCount != null) 'skip_count': skipCount,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (lastSkippedAt != null) 'last_skipped_at': lastSkippedAt,
      if (lastCompletedAt != null) 'last_completed_at': lastCompletedAt,
      if (userScoreBoost != null) 'user_score_boost': userScoreBoost,
      if (preferredWaveMode != null) 'preferred_wave_mode': preferredWaveMode,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  TrackUserStatesCompanion copyWith(
      {Value<int>? trackId,
      Value<bool>? isFavorite,
      Value<bool>? isHidden,
      Value<int?>? rating,
      Value<int>? playCount,
      Value<int>? skipCount,
      Value<DateTime?>? lastPlayedAt,
      Value<DateTime?>? lastSkippedAt,
      Value<DateTime?>? lastCompletedAt,
      Value<double>? userScoreBoost,
      Value<String?>? preferredWaveMode,
      Value<DateTime>? updatedAt}) {
    return TrackUserStatesCompanion(
      trackId: trackId ?? this.trackId,
      isFavorite: isFavorite ?? this.isFavorite,
      isHidden: isHidden ?? this.isHidden,
      rating: rating ?? this.rating,
      playCount: playCount ?? this.playCount,
      skipCount: skipCount ?? this.skipCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      lastSkippedAt: lastSkippedAt ?? this.lastSkippedAt,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      userScoreBoost: userScoreBoost ?? this.userScoreBoost,
      preferredWaveMode: preferredWaveMode ?? this.preferredWaveMode,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackId.present) {
      map['track_id'] = Variable<int>(trackId.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (isHidden.present) {
      map['is_hidden'] = Variable<bool>(isHidden.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (skipCount.present) {
      map['skip_count'] = Variable<int>(skipCount.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (lastSkippedAt.present) {
      map['last_skipped_at'] = Variable<DateTime>(lastSkippedAt.value);
    }
    if (lastCompletedAt.present) {
      map['last_completed_at'] = Variable<DateTime>(lastCompletedAt.value);
    }
    if (userScoreBoost.present) {
      map['user_score_boost'] = Variable<double>(userScoreBoost.value);
    }
    if (preferredWaveMode.present) {
      map['preferred_wave_mode'] = Variable<String>(preferredWaveMode.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackUserStatesCompanion(')
          ..write('trackId: $trackId, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isHidden: $isHidden, ')
          ..write('rating: $rating, ')
          ..write('playCount: $playCount, ')
          ..write('skipCount: $skipCount, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('lastSkippedAt: $lastSkippedAt, ')
          ..write('lastCompletedAt: $lastCompletedAt, ')
          ..write('userScoreBoost: $userScoreBoost, ')
          ..write('preferredWaveMode: $preferredWaveMode, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(Insertable<AppSettingRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingRow(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSettingRow extends DataClass implements Insertable<AppSettingRow> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const AppSettingRow(
      {required this.key, required this.value, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSettingRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSettingRow copyWith({String? key, String? value, DateTime? updatedAt}) =>
      AppSettingRow(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSettingRow copyWithCompanion(AppSettingsCompanion data) {
    return AppSettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingRow &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value),
        updatedAt = Value(updatedAt);
  static Insertable<AppSettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith(
      {Value<String>? key,
      Value<String>? value,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LibraryFoldersTable libraryFolders = $LibraryFoldersTable(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $PlaybackEventsTable playbackEvents = $PlaybackEventsTable(this);
  late final $TrackUserStatesTable trackUserStates =
      $TrackUserStatesTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [libraryFolders, tracks, playbackEvents, trackUserStates, appSettings];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('library_folders',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('tracks', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('tracks',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('playback_events', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('tracks',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('track_user_state', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$LibraryFoldersTableCreateCompanionBuilder = LibraryFoldersCompanion
    Function({
  Value<int> id,
  required String path,
  Value<String?> displayName,
  Value<bool> isEnabled,
  Value<bool> isRecursive,
  Value<DateTime?> lastScannedAt,
  required DateTime createdAt,
  required DateTime updatedAt,
});
typedef $$LibraryFoldersTableUpdateCompanionBuilder = LibraryFoldersCompanion
    Function({
  Value<int> id,
  Value<String> path,
  Value<String?> displayName,
  Value<bool> isEnabled,
  Value<bool> isRecursive,
  Value<DateTime?> lastScannedAt,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$LibraryFoldersTableReferences extends BaseReferences<
    _$AppDatabase, $LibraryFoldersTable, LibraryFolderRow> {
  $$LibraryFoldersTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TracksTable, List<TrackRow>> _tracksRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.tracks,
          aliasName: $_aliasNameGenerator(
              db.libraryFolders.id, db.tracks.libraryFolderId));

  $$TracksTableProcessedTableManager get tracksRefs {
    final manager = $$TracksTableTableManager($_db, $_db.tracks).filter(
        (f) => f.libraryFolderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_tracksRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$LibraryFoldersTableFilterComposer
    extends Composer<_$AppDatabase, $LibraryFoldersTable> {
  $$LibraryFoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRecursive => $composableBuilder(
      column: $table.isRecursive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastScannedAt => $composableBuilder(
      column: $table.lastScannedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> tracksRefs(
      Expression<bool> Function($$TracksTableFilterComposer f) f) {
    final $$TracksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.tracks,
        getReferencedColumn: (t) => t.libraryFolderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TracksTableFilterComposer(
              $db: $db,
              $table: $db.tracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LibraryFoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $LibraryFoldersTable> {
  $$LibraryFoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRecursive => $composableBuilder(
      column: $table.isRecursive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastScannedAt => $composableBuilder(
      column: $table.lastScannedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LibraryFoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $LibraryFoldersTable> {
  $$LibraryFoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<bool> get isRecursive => $composableBuilder(
      column: $table.isRecursive, builder: (column) => column);

  GeneratedColumn<DateTime> get lastScannedAt => $composableBuilder(
      column: $table.lastScannedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> tracksRefs<T extends Object>(
      Expression<T> Function($$TracksTableAnnotationComposer a) f) {
    final $$TracksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.tracks,
        getReferencedColumn: (t) => t.libraryFolderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TracksTableAnnotationComposer(
              $db: $db,
              $table: $db.tracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LibraryFoldersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LibraryFoldersTable,
    LibraryFolderRow,
    $$LibraryFoldersTableFilterComposer,
    $$LibraryFoldersTableOrderingComposer,
    $$LibraryFoldersTableAnnotationComposer,
    $$LibraryFoldersTableCreateCompanionBuilder,
    $$LibraryFoldersTableUpdateCompanionBuilder,
    (LibraryFolderRow, $$LibraryFoldersTableReferences),
    LibraryFolderRow,
    PrefetchHooks Function({bool tracksRefs})> {
  $$LibraryFoldersTableTableManager(
      _$AppDatabase db, $LibraryFoldersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryFoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryFoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryFoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> path = const Value.absent(),
            Value<String?> displayName = const Value.absent(),
            Value<bool> isEnabled = const Value.absent(),
            Value<bool> isRecursive = const Value.absent(),
            Value<DateTime?> lastScannedAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              LibraryFoldersCompanion(
            id: id,
            path: path,
            displayName: displayName,
            isEnabled: isEnabled,
            isRecursive: isRecursive,
            lastScannedAt: lastScannedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String path,
            Value<String?> displayName = const Value.absent(),
            Value<bool> isEnabled = const Value.absent(),
            Value<bool> isRecursive = const Value.absent(),
            Value<DateTime?> lastScannedAt = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
          }) =>
              LibraryFoldersCompanion.insert(
            id: id,
            path: path,
            displayName: displayName,
            isEnabled: isEnabled,
            isRecursive: isRecursive,
            lastScannedAt: lastScannedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$LibraryFoldersTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({tracksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (tracksRefs) db.tracks],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (tracksRefs)
                    await $_getPrefetchedData<LibraryFolderRow,
                            $LibraryFoldersTable, TrackRow>(
                        currentTable: table,
                        referencedTable: $$LibraryFoldersTableReferences
                            ._tracksRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LibraryFoldersTableReferences(db, table, p0)
                                .tracksRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.libraryFolderId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$LibraryFoldersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LibraryFoldersTable,
    LibraryFolderRow,
    $$LibraryFoldersTableFilterComposer,
    $$LibraryFoldersTableOrderingComposer,
    $$LibraryFoldersTableAnnotationComposer,
    $$LibraryFoldersTableCreateCompanionBuilder,
    $$LibraryFoldersTableUpdateCompanionBuilder,
    (LibraryFolderRow, $$LibraryFoldersTableReferences),
    LibraryFolderRow,
    PrefetchHooks Function({bool tracksRefs})>;
typedef $$TracksTableCreateCompanionBuilder = TracksCompanion Function({
  Value<int> id,
  Value<int?> libraryFolderId,
  required String filePath,
  Value<String?> contentHash,
  Value<String?> title,
  Value<String?> artist,
  Value<String?> album,
  Value<String?> albumArtist,
  Value<String?> genre,
  Value<int?> durationMs,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<int?> year,
  Value<int?> fileSizeBytes,
  Value<DateTime?> modifiedAt,
  required DateTime addedAt,
  required DateTime updatedAt,
});
typedef $$TracksTableUpdateCompanionBuilder = TracksCompanion Function({
  Value<int> id,
  Value<int?> libraryFolderId,
  Value<String> filePath,
  Value<String?> contentHash,
  Value<String?> title,
  Value<String?> artist,
  Value<String?> album,
  Value<String?> albumArtist,
  Value<String?> genre,
  Value<int?> durationMs,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<int?> year,
  Value<int?> fileSizeBytes,
  Value<DateTime?> modifiedAt,
  Value<DateTime> addedAt,
  Value<DateTime> updatedAt,
});

final class $$TracksTableReferences
    extends BaseReferences<_$AppDatabase, $TracksTable, TrackRow> {
  $$TracksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LibraryFoldersTable _libraryFolderIdTable(_$AppDatabase db) =>
      db.libraryFolders.createAlias($_aliasNameGenerator(
          db.tracks.libraryFolderId, db.libraryFolders.id));

  $$LibraryFoldersTableProcessedTableManager? get libraryFolderId {
    final $_column = $_itemColumn<int>('library_folder_id');
    if ($_column == null) return null;
    final manager = $$LibraryFoldersTableTableManager($_db, $_db.libraryFolders)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_libraryFolderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$PlaybackEventsTable, List<PlaybackEventRow>>
      _playbackEventsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.playbackEvents,
              aliasName: $_aliasNameGenerator(
                  db.tracks.id, db.playbackEvents.trackId));

  $$PlaybackEventsTableProcessedTableManager get playbackEventsRefs {
    final manager = $$PlaybackEventsTableTableManager($_db, $_db.playbackEvents)
        .filter((f) => f.trackId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_playbackEventsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$TrackUserStatesTable, List<TrackUserStateRow>>
      _trackUserStatesRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.trackUserStates,
              aliasName: $_aliasNameGenerator(
                  db.tracks.id, db.trackUserStates.trackId));

  $$TrackUserStatesTableProcessedTableManager get trackUserStatesRefs {
    final manager =
        $$TrackUserStatesTableTableManager($_db, $_db.trackUserStates)
            .filter((f) => f.trackId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_trackUserStatesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$TracksTableFilterComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get album => $composableBuilder(
      column: $table.album, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get albumArtist => $composableBuilder(
      column: $table.albumArtist, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get genre => $composableBuilder(
      column: $table.genre, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$LibraryFoldersTableFilterComposer get libraryFolderId {
    final $$LibraryFoldersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.libraryFolderId,
        referencedTable: $db.libraryFolders,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LibraryFoldersTableFilterComposer(
              $db: $db,
              $table: $db.libraryFolders,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> playbackEventsRefs(
      Expression<bool> Function($$PlaybackEventsTableFilterComposer f) f) {
    final $$PlaybackEventsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.playbackEvents,
        getReferencedColumn: (t) => t.trackId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaybackEventsTableFilterComposer(
              $db: $db,
              $table: $db.playbackEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> trackUserStatesRefs(
      Expression<bool> Function($$TrackUserStatesTableFilterComposer f) f) {
    final $$TrackUserStatesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.trackUserStates,
        getReferencedColumn: (t) => t.trackId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TrackUserStatesTableFilterComposer(
              $db: $db,
              $table: $db.trackUserStates,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TracksTableOrderingComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get album => $composableBuilder(
      column: $table.album, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get albumArtist => $composableBuilder(
      column: $table.albumArtist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get genre => $composableBuilder(
      column: $table.genre, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$LibraryFoldersTableOrderingComposer get libraryFolderId {
    final $$LibraryFoldersTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.libraryFolderId,
        referencedTable: $db.libraryFolders,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LibraryFoldersTableOrderingComposer(
              $db: $db,
              $table: $db.libraryFolders,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get albumArtist => $composableBuilder(
      column: $table.albumArtist, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => column);

  GeneratedColumn<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$LibraryFoldersTableAnnotationComposer get libraryFolderId {
    final $$LibraryFoldersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.libraryFolderId,
        referencedTable: $db.libraryFolders,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LibraryFoldersTableAnnotationComposer(
              $db: $db,
              $table: $db.libraryFolders,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> playbackEventsRefs<T extends Object>(
      Expression<T> Function($$PlaybackEventsTableAnnotationComposer a) f) {
    final $$PlaybackEventsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.playbackEvents,
        getReferencedColumn: (t) => t.trackId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaybackEventsTableAnnotationComposer(
              $db: $db,
              $table: $db.playbackEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> trackUserStatesRefs<T extends Object>(
      Expression<T> Function($$TrackUserStatesTableAnnotationComposer a) f) {
    final $$TrackUserStatesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.trackUserStates,
        getReferencedColumn: (t) => t.trackId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TrackUserStatesTableAnnotationComposer(
              $db: $db,
              $table: $db.trackUserStates,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TracksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TracksTable,
    TrackRow,
    $$TracksTableFilterComposer,
    $$TracksTableOrderingComposer,
    $$TracksTableAnnotationComposer,
    $$TracksTableCreateCompanionBuilder,
    $$TracksTableUpdateCompanionBuilder,
    (TrackRow, $$TracksTableReferences),
    TrackRow,
    PrefetchHooks Function(
        {bool libraryFolderId,
        bool playbackEventsRefs,
        bool trackUserStatesRefs})> {
  $$TracksTableTableManager(_$AppDatabase db, $TracksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> libraryFolderId = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<String?> contentHash = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<String?> artist = const Value.absent(),
            Value<String?> album = const Value.absent(),
            Value<String?> albumArtist = const Value.absent(),
            Value<String?> genre = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int?> trackNumber = const Value.absent(),
            Value<int?> discNumber = const Value.absent(),
            Value<int?> year = const Value.absent(),
            Value<int?> fileSizeBytes = const Value.absent(),
            Value<DateTime?> modifiedAt = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              TracksCompanion(
            id: id,
            libraryFolderId: libraryFolderId,
            filePath: filePath,
            contentHash: contentHash,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            durationMs: durationMs,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            fileSizeBytes: fileSizeBytes,
            modifiedAt: modifiedAt,
            addedAt: addedAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> libraryFolderId = const Value.absent(),
            required String filePath,
            Value<String?> contentHash = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<String?> artist = const Value.absent(),
            Value<String?> album = const Value.absent(),
            Value<String?> albumArtist = const Value.absent(),
            Value<String?> genre = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int?> trackNumber = const Value.absent(),
            Value<int?> discNumber = const Value.absent(),
            Value<int?> year = const Value.absent(),
            Value<int?> fileSizeBytes = const Value.absent(),
            Value<DateTime?> modifiedAt = const Value.absent(),
            required DateTime addedAt,
            required DateTime updatedAt,
          }) =>
              TracksCompanion.insert(
            id: id,
            libraryFolderId: libraryFolderId,
            filePath: filePath,
            contentHash: contentHash,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            durationMs: durationMs,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            fileSizeBytes: fileSizeBytes,
            modifiedAt: modifiedAt,
            addedAt: addedAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$TracksTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {libraryFolderId = false,
              playbackEventsRefs = false,
              trackUserStatesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (playbackEventsRefs) db.playbackEvents,
                if (trackUserStatesRefs) db.trackUserStates
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (libraryFolderId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.libraryFolderId,
                    referencedTable:
                        $$TracksTableReferences._libraryFolderIdTable(db),
                    referencedColumn:
                        $$TracksTableReferences._libraryFolderIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (playbackEventsRefs)
                    await $_getPrefetchedData<TrackRow, $TracksTable,
                            PlaybackEventRow>(
                        currentTable: table,
                        referencedTable: $$TracksTableReferences
                            ._playbackEventsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TracksTableReferences(db, table, p0)
                                .playbackEventsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.trackId == item.id),
                        typedResults: items),
                  if (trackUserStatesRefs)
                    await $_getPrefetchedData<TrackRow, $TracksTable,
                            TrackUserStateRow>(
                        currentTable: table,
                        referencedTable: $$TracksTableReferences
                            ._trackUserStatesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TracksTableReferences(db, table, p0)
                                .trackUserStatesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.trackId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$TracksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TracksTable,
    TrackRow,
    $$TracksTableFilterComposer,
    $$TracksTableOrderingComposer,
    $$TracksTableAnnotationComposer,
    $$TracksTableCreateCompanionBuilder,
    $$TracksTableUpdateCompanionBuilder,
    (TrackRow, $$TracksTableReferences),
    TrackRow,
    PrefetchHooks Function(
        {bool libraryFolderId,
        bool playbackEventsRefs,
        bool trackUserStatesRefs})>;
typedef $$PlaybackEventsTableCreateCompanionBuilder = PlaybackEventsCompanion
    Function({
  Value<int> id,
  required int trackId,
  required String eventType,
  required DateTime occurredAt,
  Value<int?> positionMs,
  Value<int?> durationMs,
  Value<String?> waveMode,
  Value<String?> metadataJson,
});
typedef $$PlaybackEventsTableUpdateCompanionBuilder = PlaybackEventsCompanion
    Function({
  Value<int> id,
  Value<int> trackId,
  Value<String> eventType,
  Value<DateTime> occurredAt,
  Value<int?> positionMs,
  Value<int?> durationMs,
  Value<String?> waveMode,
  Value<String?> metadataJson,
});

final class $$PlaybackEventsTableReferences extends BaseReferences<
    _$AppDatabase, $PlaybackEventsTable, PlaybackEventRow> {
  $$PlaybackEventsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $TracksTable _trackIdTable(_$AppDatabase db) => db.tracks.createAlias(
      $_aliasNameGenerator(db.playbackEvents.trackId, db.tracks.id));

  $$TracksTableProcessedTableManager get trackId {
    final $_column = $_itemColumn<int>('track_id')!;

    final manager = $$TracksTableTableManager($_db, $_db.tracks)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_trackIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$PlaybackEventsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackEventsTable> {
  $$PlaybackEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get eventType => $composableBuilder(
      column: $table.eventType, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get waveMode => $composableBuilder(
      column: $table.waveMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson, builder: (column) => ColumnFilters(column));

  $$TracksTableFilterComposer get trackId {
    final $$TracksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.trackId,
        referencedTable: $db.tracks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TracksTableFilterComposer(
              $db: $db,
              $table: $db.tracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PlaybackEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackEventsTable> {
  $$PlaybackEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get eventType => $composableBuilder(
      column: $table.eventType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get waveMode => $composableBuilder(
      column: $table.waveMode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson,
      builder: (column) => ColumnOrderings(column));

  $$TracksTableOrderingComposer get trackId {
    final $$TracksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.trackId,
        referencedTable: $db.tracks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TracksTableOrderingComposer(
              $db: $db,
              $table: $db.tracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PlaybackEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackEventsTable> {
  $$PlaybackEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<String> get waveMode =>
      $composableBuilder(column: $table.waveMode, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson, builder: (column) => column);

  $$TracksTableAnnotationComposer get trackId {
    final $$TracksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.trackId,
        referencedTable: $db.tracks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TracksTableAnnotationComposer(
              $db: $db,
              $table: $db.tracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PlaybackEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlaybackEventsTable,
    PlaybackEventRow,
    $$PlaybackEventsTableFilterComposer,
    $$PlaybackEventsTableOrderingComposer,
    $$PlaybackEventsTableAnnotationComposer,
    $$PlaybackEventsTableCreateCompanionBuilder,
    $$PlaybackEventsTableUpdateCompanionBuilder,
    (PlaybackEventRow, $$PlaybackEventsTableReferences),
    PlaybackEventRow,
    PrefetchHooks Function({bool trackId})> {
  $$PlaybackEventsTableTableManager(
      _$AppDatabase db, $PlaybackEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaybackEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaybackEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> trackId = const Value.absent(),
            Value<String> eventType = const Value.absent(),
            Value<DateTime> occurredAt = const Value.absent(),
            Value<int?> positionMs = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<String?> waveMode = const Value.absent(),
            Value<String?> metadataJson = const Value.absent(),
          }) =>
              PlaybackEventsCompanion(
            id: id,
            trackId: trackId,
            eventType: eventType,
            occurredAt: occurredAt,
            positionMs: positionMs,
            durationMs: durationMs,
            waveMode: waveMode,
            metadataJson: metadataJson,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int trackId,
            required String eventType,
            required DateTime occurredAt,
            Value<int?> positionMs = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<String?> waveMode = const Value.absent(),
            Value<String?> metadataJson = const Value.absent(),
          }) =>
              PlaybackEventsCompanion.insert(
            id: id,
            trackId: trackId,
            eventType: eventType,
            occurredAt: occurredAt,
            positionMs: positionMs,
            durationMs: durationMs,
            waveMode: waveMode,
            metadataJson: metadataJson,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PlaybackEventsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({trackId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (trackId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.trackId,
                    referencedTable:
                        $$PlaybackEventsTableReferences._trackIdTable(db),
                    referencedColumn:
                        $$PlaybackEventsTableReferences._trackIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$PlaybackEventsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlaybackEventsTable,
    PlaybackEventRow,
    $$PlaybackEventsTableFilterComposer,
    $$PlaybackEventsTableOrderingComposer,
    $$PlaybackEventsTableAnnotationComposer,
    $$PlaybackEventsTableCreateCompanionBuilder,
    $$PlaybackEventsTableUpdateCompanionBuilder,
    (PlaybackEventRow, $$PlaybackEventsTableReferences),
    PlaybackEventRow,
    PrefetchHooks Function({bool trackId})>;
typedef $$TrackUserStatesTableCreateCompanionBuilder = TrackUserStatesCompanion
    Function({
  Value<int> trackId,
  Value<bool> isFavorite,
  Value<bool> isHidden,
  Value<int?> rating,
  Value<int> playCount,
  Value<int> skipCount,
  Value<DateTime?> lastPlayedAt,
  Value<DateTime?> lastSkippedAt,
  Value<DateTime?> lastCompletedAt,
  Value<double> userScoreBoost,
  Value<String?> preferredWaveMode,
  required DateTime updatedAt,
});
typedef $$TrackUserStatesTableUpdateCompanionBuilder = TrackUserStatesCompanion
    Function({
  Value<int> trackId,
  Value<bool> isFavorite,
  Value<bool> isHidden,
  Value<int?> rating,
  Value<int> playCount,
  Value<int> skipCount,
  Value<DateTime?> lastPlayedAt,
  Value<DateTime?> lastSkippedAt,
  Value<DateTime?> lastCompletedAt,
  Value<double> userScoreBoost,
  Value<String?> preferredWaveMode,
  Value<DateTime> updatedAt,
});

final class $$TrackUserStatesTableReferences extends BaseReferences<
    _$AppDatabase, $TrackUserStatesTable, TrackUserStateRow> {
  $$TrackUserStatesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $TracksTable _trackIdTable(_$AppDatabase db) => db.tracks.createAlias(
      $_aliasNameGenerator(db.trackUserStates.trackId, db.tracks.id));

  $$TracksTableProcessedTableManager get trackId {
    final $_column = $_itemColumn<int>('track_id')!;

    final manager = $$TracksTableTableManager($_db, $_db.tracks)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_trackIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TrackUserStatesTableFilterComposer
    extends Composer<_$AppDatabase, $TrackUserStatesTable> {
  $$TrackUserStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isHidden => $composableBuilder(
      column: $table.isHidden, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get skipCount => $composableBuilder(
      column: $table.skipCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
      column: $table.lastPlayedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSkippedAt => $composableBuilder(
      column: $table.lastSkippedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastCompletedAt => $composableBuilder(
      column: $table.lastCompletedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get userScoreBoost => $composableBuilder(
      column: $table.userScoreBoost,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get preferredWaveMode => $composableBuilder(
      column: $table.preferredWaveMode,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$TracksTableFilterComposer get trackId {
    final $$TracksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.trackId,
        referencedTable: $db.tracks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TracksTableFilterComposer(
              $db: $db,
              $table: $db.tracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TrackUserStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $TrackUserStatesTable> {
  $$TrackUserStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isHidden => $composableBuilder(
      column: $table.isHidden, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get skipCount => $composableBuilder(
      column: $table.skipCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
      column: $table.lastPlayedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSkippedAt => $composableBuilder(
      column: $table.lastSkippedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastCompletedAt => $composableBuilder(
      column: $table.lastCompletedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get userScoreBoost => $composableBuilder(
      column: $table.userScoreBoost,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get preferredWaveMode => $composableBuilder(
      column: $table.preferredWaveMode,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$TracksTableOrderingComposer get trackId {
    final $$TracksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.trackId,
        referencedTable: $db.tracks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TracksTableOrderingComposer(
              $db: $db,
              $table: $db.tracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TrackUserStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrackUserStatesTable> {
  $$TrackUserStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => column);

  GeneratedColumn<bool> get isHidden =>
      $composableBuilder(column: $table.isHidden, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get skipCount =>
      $composableBuilder(column: $table.skipCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
      column: $table.lastPlayedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSkippedAt => $composableBuilder(
      column: $table.lastSkippedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastCompletedAt => $composableBuilder(
      column: $table.lastCompletedAt, builder: (column) => column);

  GeneratedColumn<double> get userScoreBoost => $composableBuilder(
      column: $table.userScoreBoost, builder: (column) => column);

  GeneratedColumn<String> get preferredWaveMode => $composableBuilder(
      column: $table.preferredWaveMode, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$TracksTableAnnotationComposer get trackId {
    final $$TracksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.trackId,
        referencedTable: $db.tracks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TracksTableAnnotationComposer(
              $db: $db,
              $table: $db.tracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TrackUserStatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TrackUserStatesTable,
    TrackUserStateRow,
    $$TrackUserStatesTableFilterComposer,
    $$TrackUserStatesTableOrderingComposer,
    $$TrackUserStatesTableAnnotationComposer,
    $$TrackUserStatesTableCreateCompanionBuilder,
    $$TrackUserStatesTableUpdateCompanionBuilder,
    (TrackUserStateRow, $$TrackUserStatesTableReferences),
    TrackUserStateRow,
    PrefetchHooks Function({bool trackId})> {
  $$TrackUserStatesTableTableManager(
      _$AppDatabase db, $TrackUserStatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackUserStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackUserStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackUserStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> trackId = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<bool> isHidden = const Value.absent(),
            Value<int?> rating = const Value.absent(),
            Value<int> playCount = const Value.absent(),
            Value<int> skipCount = const Value.absent(),
            Value<DateTime?> lastPlayedAt = const Value.absent(),
            Value<DateTime?> lastSkippedAt = const Value.absent(),
            Value<DateTime?> lastCompletedAt = const Value.absent(),
            Value<double> userScoreBoost = const Value.absent(),
            Value<String?> preferredWaveMode = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              TrackUserStatesCompanion(
            trackId: trackId,
            isFavorite: isFavorite,
            isHidden: isHidden,
            rating: rating,
            playCount: playCount,
            skipCount: skipCount,
            lastPlayedAt: lastPlayedAt,
            lastSkippedAt: lastSkippedAt,
            lastCompletedAt: lastCompletedAt,
            userScoreBoost: userScoreBoost,
            preferredWaveMode: preferredWaveMode,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> trackId = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<bool> isHidden = const Value.absent(),
            Value<int?> rating = const Value.absent(),
            Value<int> playCount = const Value.absent(),
            Value<int> skipCount = const Value.absent(),
            Value<DateTime?> lastPlayedAt = const Value.absent(),
            Value<DateTime?> lastSkippedAt = const Value.absent(),
            Value<DateTime?> lastCompletedAt = const Value.absent(),
            Value<double> userScoreBoost = const Value.absent(),
            Value<String?> preferredWaveMode = const Value.absent(),
            required DateTime updatedAt,
          }) =>
              TrackUserStatesCompanion.insert(
            trackId: trackId,
            isFavorite: isFavorite,
            isHidden: isHidden,
            rating: rating,
            playCount: playCount,
            skipCount: skipCount,
            lastPlayedAt: lastPlayedAt,
            lastSkippedAt: lastSkippedAt,
            lastCompletedAt: lastCompletedAt,
            userScoreBoost: userScoreBoost,
            preferredWaveMode: preferredWaveMode,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$TrackUserStatesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({trackId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (trackId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.trackId,
                    referencedTable:
                        $$TrackUserStatesTableReferences._trackIdTable(db),
                    referencedColumn:
                        $$TrackUserStatesTableReferences._trackIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TrackUserStatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TrackUserStatesTable,
    TrackUserStateRow,
    $$TrackUserStatesTableFilterComposer,
    $$TrackUserStatesTableOrderingComposer,
    $$TrackUserStatesTableAnnotationComposer,
    $$TrackUserStatesTableCreateCompanionBuilder,
    $$TrackUserStatesTableUpdateCompanionBuilder,
    (TrackUserStateRow, $$TrackUserStatesTableReferences),
    TrackUserStateRow,
    PrefetchHooks Function({bool trackId})>;
typedef $$AppSettingsTableCreateCompanionBuilder = AppSettingsCompanion
    Function({
  required String key,
  required String value,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$AppSettingsTableUpdateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppSettingsTable,
    AppSettingRow,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      AppSettingRow,
      BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>
    ),
    AppSettingRow,
    PrefetchHooks Function()> {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppSettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AppSettingsTable,
    AppSettingRow,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      AppSettingRow,
      BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>
    ),
    AppSettingRow,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LibraryFoldersTableTableManager get libraryFolders =>
      $$LibraryFoldersTableTableManager(_db, _db.libraryFolders);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$PlaybackEventsTableTableManager get playbackEvents =>
      $$PlaybackEventsTableTableManager(_db, _db.playbackEvents);
  $$TrackUserStatesTableTableManager get trackUserStates =>
      $$TrackUserStatesTableTableManager(_db, _db.trackUserStates);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
