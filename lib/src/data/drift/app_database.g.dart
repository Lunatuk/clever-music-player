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
  static const VerificationMeta _stableIdMeta =
      const VerificationMeta('stableId');
  @override
  late final GeneratedColumn<String> stableId = GeneratedColumn<String>(
      'stable_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
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
  static const VerificationMeta _artworkPathMeta =
      const VerificationMeta('artworkPath');
  @override
  late final GeneratedColumn<String> artworkPath = GeneratedColumn<String>(
      'artwork_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _artworkHashMeta =
      const VerificationMeta('artworkHash');
  @override
  late final GeneratedColumn<String> artworkHash = GeneratedColumn<String>(
      'artwork_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _artworkMimeTypeMeta =
      const VerificationMeta('artworkMimeType');
  @override
  late final GeneratedColumn<String> artworkMimeType = GeneratedColumn<String>(
      'artwork_mime_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _customArtworkPathMeta =
      const VerificationMeta('customArtworkPath');
  @override
  late final GeneratedColumn<String> customArtworkPath =
      GeneratedColumn<String>('custom_artwork_path', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _customArtworkHashMeta =
      const VerificationMeta('customArtworkHash');
  @override
  late final GeneratedColumn<String> customArtworkHash =
      GeneratedColumn<String>('custom_artwork_hash', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _customArtworkMimeTypeMeta =
      const VerificationMeta('customArtworkMimeType');
  @override
  late final GeneratedColumn<String> customArtworkMimeType =
      GeneratedColumn<String>('custom_artwork_mime_type', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _codecMeta = const VerificationMeta('codec');
  @override
  late final GeneratedColumn<String> codec = GeneratedColumn<String>(
      'codec', aliasedName, true,
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
  static const VerificationMeta _metadataSourceMeta =
      const VerificationMeta('metadataSource');
  @override
  late final GeneratedColumn<String> metadataSource = GeneratedColumn<String>(
      'metadata_source', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _metadataConfidenceMeta =
      const VerificationMeta('metadataConfidence');
  @override
  late final GeneratedColumn<double> metadataConfidence =
      GeneratedColumn<double>('metadata_confidence', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
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
  static const VerificationMeta _lastSeenAtMeta =
      const VerificationMeta('lastSeenAt');
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
      'last_seen_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _isMissingMeta =
      const VerificationMeta('isMissing');
  @override
  late final GeneratedColumn<bool> isMissing = GeneratedColumn<bool>(
      'is_missing', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_missing" IN (0, 1))'),
      defaultValue: const Constant(false));
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
        stableId,
        filePath,
        contentHash,
        title,
        artist,
        album,
        albumArtist,
        genre,
        artworkPath,
        artworkHash,
        artworkMimeType,
        customArtworkPath,
        customArtworkHash,
        customArtworkMimeType,
        codec,
        durationMs,
        trackNumber,
        discNumber,
        year,
        metadataSource,
        metadataConfidence,
        fileSizeBytes,
        modifiedAt,
        lastSeenAt,
        isMissing,
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
    if (data.containsKey('stable_id')) {
      context.handle(_stableIdMeta,
          stableId.isAcceptableOrUnknown(data['stable_id']!, _stableIdMeta));
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
    if (data.containsKey('artwork_path')) {
      context.handle(
          _artworkPathMeta,
          artworkPath.isAcceptableOrUnknown(
              data['artwork_path']!, _artworkPathMeta));
    }
    if (data.containsKey('artwork_hash')) {
      context.handle(
          _artworkHashMeta,
          artworkHash.isAcceptableOrUnknown(
              data['artwork_hash']!, _artworkHashMeta));
    }
    if (data.containsKey('artwork_mime_type')) {
      context.handle(
          _artworkMimeTypeMeta,
          artworkMimeType.isAcceptableOrUnknown(
              data['artwork_mime_type']!, _artworkMimeTypeMeta));
    }
    if (data.containsKey('custom_artwork_path')) {
      context.handle(
          _customArtworkPathMeta,
          customArtworkPath.isAcceptableOrUnknown(
              data['custom_artwork_path']!, _customArtworkPathMeta));
    }
    if (data.containsKey('custom_artwork_hash')) {
      context.handle(
          _customArtworkHashMeta,
          customArtworkHash.isAcceptableOrUnknown(
              data['custom_artwork_hash']!, _customArtworkHashMeta));
    }
    if (data.containsKey('custom_artwork_mime_type')) {
      context.handle(
          _customArtworkMimeTypeMeta,
          customArtworkMimeType.isAcceptableOrUnknown(
              data['custom_artwork_mime_type']!, _customArtworkMimeTypeMeta));
    }
    if (data.containsKey('codec')) {
      context.handle(
          _codecMeta, codec.isAcceptableOrUnknown(data['codec']!, _codecMeta));
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
    if (data.containsKey('metadata_source')) {
      context.handle(
          _metadataSourceMeta,
          metadataSource.isAcceptableOrUnknown(
              data['metadata_source']!, _metadataSourceMeta));
    }
    if (data.containsKey('metadata_confidence')) {
      context.handle(
          _metadataConfidenceMeta,
          metadataConfidence.isAcceptableOrUnknown(
              data['metadata_confidence']!, _metadataConfidenceMeta));
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
    if (data.containsKey('last_seen_at')) {
      context.handle(
          _lastSeenAtMeta,
          lastSeenAt.isAcceptableOrUnknown(
              data['last_seen_at']!, _lastSeenAtMeta));
    }
    if (data.containsKey('is_missing')) {
      context.handle(_isMissingMeta,
          isMissing.isAcceptableOrUnknown(data['is_missing']!, _isMissingMeta));
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
      stableId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}stable_id']),
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
      artworkPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artwork_path']),
      artworkHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artwork_hash']),
      artworkMimeType: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}artwork_mime_type']),
      customArtworkPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}custom_artwork_path']),
      customArtworkHash: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}custom_artwork_hash']),
      customArtworkMimeType: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}custom_artwork_mime_type']),
      codec: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}codec']),
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
      trackNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_number']),
      discNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}disc_number']),
      year: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}year']),
      metadataSource: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata_source']),
      metadataConfidence: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}metadata_confidence']),
      fileSizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}file_size_bytes']),
      modifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}modified_at']),
      lastSeenAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_seen_at']),
      isMissing: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_missing'])!,
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
  final String? stableId;
  final String filePath;
  final String? contentHash;
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final String? artworkPath;
  final String? artworkHash;
  final String? artworkMimeType;
  final String? customArtworkPath;
  final String? customArtworkHash;
  final String? customArtworkMimeType;
  final String? codec;
  final int? durationMs;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? metadataSource;
  final double? metadataConfidence;
  final int? fileSizeBytes;
  final DateTime? modifiedAt;
  final DateTime? lastSeenAt;
  final bool isMissing;
  final DateTime addedAt;
  final DateTime updatedAt;
  const TrackRow(
      {required this.id,
      this.libraryFolderId,
      this.stableId,
      required this.filePath,
      this.contentHash,
      this.title,
      this.artist,
      this.album,
      this.albumArtist,
      this.genre,
      this.artworkPath,
      this.artworkHash,
      this.artworkMimeType,
      this.customArtworkPath,
      this.customArtworkHash,
      this.customArtworkMimeType,
      this.codec,
      this.durationMs,
      this.trackNumber,
      this.discNumber,
      this.year,
      this.metadataSource,
      this.metadataConfidence,
      this.fileSizeBytes,
      this.modifiedAt,
      this.lastSeenAt,
      required this.isMissing,
      required this.addedAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || libraryFolderId != null) {
      map['library_folder_id'] = Variable<int>(libraryFolderId);
    }
    if (!nullToAbsent || stableId != null) {
      map['stable_id'] = Variable<String>(stableId);
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
    if (!nullToAbsent || artworkPath != null) {
      map['artwork_path'] = Variable<String>(artworkPath);
    }
    if (!nullToAbsent || artworkHash != null) {
      map['artwork_hash'] = Variable<String>(artworkHash);
    }
    if (!nullToAbsent || artworkMimeType != null) {
      map['artwork_mime_type'] = Variable<String>(artworkMimeType);
    }
    if (!nullToAbsent || customArtworkPath != null) {
      map['custom_artwork_path'] = Variable<String>(customArtworkPath);
    }
    if (!nullToAbsent || customArtworkHash != null) {
      map['custom_artwork_hash'] = Variable<String>(customArtworkHash);
    }
    if (!nullToAbsent || customArtworkMimeType != null) {
      map['custom_artwork_mime_type'] = Variable<String>(customArtworkMimeType);
    }
    if (!nullToAbsent || codec != null) {
      map['codec'] = Variable<String>(codec);
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
    if (!nullToAbsent || metadataSource != null) {
      map['metadata_source'] = Variable<String>(metadataSource);
    }
    if (!nullToAbsent || metadataConfidence != null) {
      map['metadata_confidence'] = Variable<double>(metadataConfidence);
    }
    if (!nullToAbsent || fileSizeBytes != null) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    }
    if (!nullToAbsent || modifiedAt != null) {
      map['modified_at'] = Variable<DateTime>(modifiedAt);
    }
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    }
    map['is_missing'] = Variable<bool>(isMissing);
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
      stableId: stableId == null && nullToAbsent
          ? const Value.absent()
          : Value(stableId),
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
      artworkPath: artworkPath == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkPath),
      artworkHash: artworkHash == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkHash),
      artworkMimeType: artworkMimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkMimeType),
      customArtworkPath: customArtworkPath == null && nullToAbsent
          ? const Value.absent()
          : Value(customArtworkPath),
      customArtworkHash: customArtworkHash == null && nullToAbsent
          ? const Value.absent()
          : Value(customArtworkHash),
      customArtworkMimeType: customArtworkMimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(customArtworkMimeType),
      codec:
          codec == null && nullToAbsent ? const Value.absent() : Value(codec),
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
      metadataSource: metadataSource == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataSource),
      metadataConfidence: metadataConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataConfidence),
      fileSizeBytes: fileSizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSizeBytes),
      modifiedAt: modifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(modifiedAt),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      isMissing: Value(isMissing),
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
      stableId: serializer.fromJson<String?>(json['stableId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      title: serializer.fromJson<String?>(json['title']),
      artist: serializer.fromJson<String?>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      albumArtist: serializer.fromJson<String?>(json['albumArtist']),
      genre: serializer.fromJson<String?>(json['genre']),
      artworkPath: serializer.fromJson<String?>(json['artworkPath']),
      artworkHash: serializer.fromJson<String?>(json['artworkHash']),
      artworkMimeType: serializer.fromJson<String?>(json['artworkMimeType']),
      customArtworkPath:
          serializer.fromJson<String?>(json['customArtworkPath']),
      customArtworkHash:
          serializer.fromJson<String?>(json['customArtworkHash']),
      customArtworkMimeType:
          serializer.fromJson<String?>(json['customArtworkMimeType']),
      codec: serializer.fromJson<String?>(json['codec']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      discNumber: serializer.fromJson<int?>(json['discNumber']),
      year: serializer.fromJson<int?>(json['year']),
      metadataSource: serializer.fromJson<String?>(json['metadataSource']),
      metadataConfidence:
          serializer.fromJson<double?>(json['metadataConfidence']),
      fileSizeBytes: serializer.fromJson<int?>(json['fileSizeBytes']),
      modifiedAt: serializer.fromJson<DateTime?>(json['modifiedAt']),
      lastSeenAt: serializer.fromJson<DateTime?>(json['lastSeenAt']),
      isMissing: serializer.fromJson<bool>(json['isMissing']),
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
      'stableId': serializer.toJson<String?>(stableId),
      'filePath': serializer.toJson<String>(filePath),
      'contentHash': serializer.toJson<String?>(contentHash),
      'title': serializer.toJson<String?>(title),
      'artist': serializer.toJson<String?>(artist),
      'album': serializer.toJson<String?>(album),
      'albumArtist': serializer.toJson<String?>(albumArtist),
      'genre': serializer.toJson<String?>(genre),
      'artworkPath': serializer.toJson<String?>(artworkPath),
      'artworkHash': serializer.toJson<String?>(artworkHash),
      'artworkMimeType': serializer.toJson<String?>(artworkMimeType),
      'customArtworkPath': serializer.toJson<String?>(customArtworkPath),
      'customArtworkHash': serializer.toJson<String?>(customArtworkHash),
      'customArtworkMimeType':
          serializer.toJson<String?>(customArtworkMimeType),
      'codec': serializer.toJson<String?>(codec),
      'durationMs': serializer.toJson<int?>(durationMs),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'discNumber': serializer.toJson<int?>(discNumber),
      'year': serializer.toJson<int?>(year),
      'metadataSource': serializer.toJson<String?>(metadataSource),
      'metadataConfidence': serializer.toJson<double?>(metadataConfidence),
      'fileSizeBytes': serializer.toJson<int?>(fileSizeBytes),
      'modifiedAt': serializer.toJson<DateTime?>(modifiedAt),
      'lastSeenAt': serializer.toJson<DateTime?>(lastSeenAt),
      'isMissing': serializer.toJson<bool>(isMissing),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TrackRow copyWith(
          {int? id,
          Value<int?> libraryFolderId = const Value.absent(),
          Value<String?> stableId = const Value.absent(),
          String? filePath,
          Value<String?> contentHash = const Value.absent(),
          Value<String?> title = const Value.absent(),
          Value<String?> artist = const Value.absent(),
          Value<String?> album = const Value.absent(),
          Value<String?> albumArtist = const Value.absent(),
          Value<String?> genre = const Value.absent(),
          Value<String?> artworkPath = const Value.absent(),
          Value<String?> artworkHash = const Value.absent(),
          Value<String?> artworkMimeType = const Value.absent(),
          Value<String?> customArtworkPath = const Value.absent(),
          Value<String?> customArtworkHash = const Value.absent(),
          Value<String?> customArtworkMimeType = const Value.absent(),
          Value<String?> codec = const Value.absent(),
          Value<int?> durationMs = const Value.absent(),
          Value<int?> trackNumber = const Value.absent(),
          Value<int?> discNumber = const Value.absent(),
          Value<int?> year = const Value.absent(),
          Value<String?> metadataSource = const Value.absent(),
          Value<double?> metadataConfidence = const Value.absent(),
          Value<int?> fileSizeBytes = const Value.absent(),
          Value<DateTime?> modifiedAt = const Value.absent(),
          Value<DateTime?> lastSeenAt = const Value.absent(),
          bool? isMissing,
          DateTime? addedAt,
          DateTime? updatedAt}) =>
      TrackRow(
        id: id ?? this.id,
        libraryFolderId: libraryFolderId.present
            ? libraryFolderId.value
            : this.libraryFolderId,
        stableId: stableId.present ? stableId.value : this.stableId,
        filePath: filePath ?? this.filePath,
        contentHash: contentHash.present ? contentHash.value : this.contentHash,
        title: title.present ? title.value : this.title,
        artist: artist.present ? artist.value : this.artist,
        album: album.present ? album.value : this.album,
        albumArtist: albumArtist.present ? albumArtist.value : this.albumArtist,
        genre: genre.present ? genre.value : this.genre,
        artworkPath: artworkPath.present ? artworkPath.value : this.artworkPath,
        artworkHash: artworkHash.present ? artworkHash.value : this.artworkHash,
        artworkMimeType: artworkMimeType.present
            ? artworkMimeType.value
            : this.artworkMimeType,
        customArtworkPath: customArtworkPath.present
            ? customArtworkPath.value
            : this.customArtworkPath,
        customArtworkHash: customArtworkHash.present
            ? customArtworkHash.value
            : this.customArtworkHash,
        customArtworkMimeType: customArtworkMimeType.present
            ? customArtworkMimeType.value
            : this.customArtworkMimeType,
        codec: codec.present ? codec.value : this.codec,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
        trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
        discNumber: discNumber.present ? discNumber.value : this.discNumber,
        year: year.present ? year.value : this.year,
        metadataSource:
            metadataSource.present ? metadataSource.value : this.metadataSource,
        metadataConfidence: metadataConfidence.present
            ? metadataConfidence.value
            : this.metadataConfidence,
        fileSizeBytes:
            fileSizeBytes.present ? fileSizeBytes.value : this.fileSizeBytes,
        modifiedAt: modifiedAt.present ? modifiedAt.value : this.modifiedAt,
        lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
        isMissing: isMissing ?? this.isMissing,
        addedAt: addedAt ?? this.addedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  TrackRow copyWithCompanion(TracksCompanion data) {
    return TrackRow(
      id: data.id.present ? data.id.value : this.id,
      libraryFolderId: data.libraryFolderId.present
          ? data.libraryFolderId.value
          : this.libraryFolderId,
      stableId: data.stableId.present ? data.stableId.value : this.stableId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      contentHash:
          data.contentHash.present ? data.contentHash.value : this.contentHash,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      albumArtist:
          data.albumArtist.present ? data.albumArtist.value : this.albumArtist,
      genre: data.genre.present ? data.genre.value : this.genre,
      artworkPath:
          data.artworkPath.present ? data.artworkPath.value : this.artworkPath,
      artworkHash:
          data.artworkHash.present ? data.artworkHash.value : this.artworkHash,
      artworkMimeType: data.artworkMimeType.present
          ? data.artworkMimeType.value
          : this.artworkMimeType,
      customArtworkPath: data.customArtworkPath.present
          ? data.customArtworkPath.value
          : this.customArtworkPath,
      customArtworkHash: data.customArtworkHash.present
          ? data.customArtworkHash.value
          : this.customArtworkHash,
      customArtworkMimeType: data.customArtworkMimeType.present
          ? data.customArtworkMimeType.value
          : this.customArtworkMimeType,
      codec: data.codec.present ? data.codec.value : this.codec,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      trackNumber:
          data.trackNumber.present ? data.trackNumber.value : this.trackNumber,
      discNumber:
          data.discNumber.present ? data.discNumber.value : this.discNumber,
      year: data.year.present ? data.year.value : this.year,
      metadataSource: data.metadataSource.present
          ? data.metadataSource.value
          : this.metadataSource,
      metadataConfidence: data.metadataConfidence.present
          ? data.metadataConfidence.value
          : this.metadataConfidence,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      modifiedAt:
          data.modifiedAt.present ? data.modifiedAt.value : this.modifiedAt,
      lastSeenAt:
          data.lastSeenAt.present ? data.lastSeenAt.value : this.lastSeenAt,
      isMissing: data.isMissing.present ? data.isMissing.value : this.isMissing,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackRow(')
          ..write('id: $id, ')
          ..write('libraryFolderId: $libraryFolderId, ')
          ..write('stableId: $stableId, ')
          ..write('filePath: $filePath, ')
          ..write('contentHash: $contentHash, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('genre: $genre, ')
          ..write('artworkPath: $artworkPath, ')
          ..write('artworkHash: $artworkHash, ')
          ..write('artworkMimeType: $artworkMimeType, ')
          ..write('customArtworkPath: $customArtworkPath, ')
          ..write('customArtworkHash: $customArtworkHash, ')
          ..write('customArtworkMimeType: $customArtworkMimeType, ')
          ..write('codec: $codec, ')
          ..write('durationMs: $durationMs, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('metadataSource: $metadataSource, ')
          ..write('metadataConfidence: $metadataConfidence, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('isMissing: $isMissing, ')
          ..write('addedAt: $addedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        libraryFolderId,
        stableId,
        filePath,
        contentHash,
        title,
        artist,
        album,
        albumArtist,
        genre,
        artworkPath,
        artworkHash,
        artworkMimeType,
        customArtworkPath,
        customArtworkHash,
        customArtworkMimeType,
        codec,
        durationMs,
        trackNumber,
        discNumber,
        year,
        metadataSource,
        metadataConfidence,
        fileSizeBytes,
        modifiedAt,
        lastSeenAt,
        isMissing,
        addedAt,
        updatedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackRow &&
          other.id == this.id &&
          other.libraryFolderId == this.libraryFolderId &&
          other.stableId == this.stableId &&
          other.filePath == this.filePath &&
          other.contentHash == this.contentHash &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.albumArtist == this.albumArtist &&
          other.genre == this.genre &&
          other.artworkPath == this.artworkPath &&
          other.artworkHash == this.artworkHash &&
          other.artworkMimeType == this.artworkMimeType &&
          other.customArtworkPath == this.customArtworkPath &&
          other.customArtworkHash == this.customArtworkHash &&
          other.customArtworkMimeType == this.customArtworkMimeType &&
          other.codec == this.codec &&
          other.durationMs == this.durationMs &&
          other.trackNumber == this.trackNumber &&
          other.discNumber == this.discNumber &&
          other.year == this.year &&
          other.metadataSource == this.metadataSource &&
          other.metadataConfidence == this.metadataConfidence &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.modifiedAt == this.modifiedAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.isMissing == this.isMissing &&
          other.addedAt == this.addedAt &&
          other.updatedAt == this.updatedAt);
}

class TracksCompanion extends UpdateCompanion<TrackRow> {
  final Value<int> id;
  final Value<int?> libraryFolderId;
  final Value<String?> stableId;
  final Value<String> filePath;
  final Value<String?> contentHash;
  final Value<String?> title;
  final Value<String?> artist;
  final Value<String?> album;
  final Value<String?> albumArtist;
  final Value<String?> genre;
  final Value<String?> artworkPath;
  final Value<String?> artworkHash;
  final Value<String?> artworkMimeType;
  final Value<String?> customArtworkPath;
  final Value<String?> customArtworkHash;
  final Value<String?> customArtworkMimeType;
  final Value<String?> codec;
  final Value<int?> durationMs;
  final Value<int?> trackNumber;
  final Value<int?> discNumber;
  final Value<int?> year;
  final Value<String?> metadataSource;
  final Value<double?> metadataConfidence;
  final Value<int?> fileSizeBytes;
  final Value<DateTime?> modifiedAt;
  final Value<DateTime?> lastSeenAt;
  final Value<bool> isMissing;
  final Value<DateTime> addedAt;
  final Value<DateTime> updatedAt;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.libraryFolderId = const Value.absent(),
    this.stableId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.genre = const Value.absent(),
    this.artworkPath = const Value.absent(),
    this.artworkHash = const Value.absent(),
    this.artworkMimeType = const Value.absent(),
    this.customArtworkPath = const Value.absent(),
    this.customArtworkHash = const Value.absent(),
    this.customArtworkMimeType = const Value.absent(),
    this.codec = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.metadataSource = const Value.absent(),
    this.metadataConfidence = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.isMissing = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TracksCompanion.insert({
    this.id = const Value.absent(),
    this.libraryFolderId = const Value.absent(),
    this.stableId = const Value.absent(),
    required String filePath,
    this.contentHash = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.genre = const Value.absent(),
    this.artworkPath = const Value.absent(),
    this.artworkHash = const Value.absent(),
    this.artworkMimeType = const Value.absent(),
    this.customArtworkPath = const Value.absent(),
    this.customArtworkHash = const Value.absent(),
    this.customArtworkMimeType = const Value.absent(),
    this.codec = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.metadataSource = const Value.absent(),
    this.metadataConfidence = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.isMissing = const Value.absent(),
    required DateTime addedAt,
    required DateTime updatedAt,
  })  : filePath = Value(filePath),
        addedAt = Value(addedAt),
        updatedAt = Value(updatedAt);
  static Insertable<TrackRow> custom({
    Expression<int>? id,
    Expression<int>? libraryFolderId,
    Expression<String>? stableId,
    Expression<String>? filePath,
    Expression<String>? contentHash,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? albumArtist,
    Expression<String>? genre,
    Expression<String>? artworkPath,
    Expression<String>? artworkHash,
    Expression<String>? artworkMimeType,
    Expression<String>? customArtworkPath,
    Expression<String>? customArtworkHash,
    Expression<String>? customArtworkMimeType,
    Expression<String>? codec,
    Expression<int>? durationMs,
    Expression<int>? trackNumber,
    Expression<int>? discNumber,
    Expression<int>? year,
    Expression<String>? metadataSource,
    Expression<double>? metadataConfidence,
    Expression<int>? fileSizeBytes,
    Expression<DateTime>? modifiedAt,
    Expression<DateTime>? lastSeenAt,
    Expression<bool>? isMissing,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (libraryFolderId != null) 'library_folder_id': libraryFolderId,
      if (stableId != null) 'stable_id': stableId,
      if (filePath != null) 'file_path': filePath,
      if (contentHash != null) 'content_hash': contentHash,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (albumArtist != null) 'album_artist': albumArtist,
      if (genre != null) 'genre': genre,
      if (artworkPath != null) 'artwork_path': artworkPath,
      if (artworkHash != null) 'artwork_hash': artworkHash,
      if (artworkMimeType != null) 'artwork_mime_type': artworkMimeType,
      if (customArtworkPath != null) 'custom_artwork_path': customArtworkPath,
      if (customArtworkHash != null) 'custom_artwork_hash': customArtworkHash,
      if (customArtworkMimeType != null)
        'custom_artwork_mime_type': customArtworkMimeType,
      if (codec != null) 'codec': codec,
      if (durationMs != null) 'duration_ms': durationMs,
      if (trackNumber != null) 'track_number': trackNumber,
      if (discNumber != null) 'disc_number': discNumber,
      if (year != null) 'year': year,
      if (metadataSource != null) 'metadata_source': metadataSource,
      if (metadataConfidence != null) 'metadata_confidence': metadataConfidence,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (isMissing != null) 'is_missing': isMissing,
      if (addedAt != null) 'added_at': addedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  TracksCompanion copyWith(
      {Value<int>? id,
      Value<int?>? libraryFolderId,
      Value<String?>? stableId,
      Value<String>? filePath,
      Value<String?>? contentHash,
      Value<String?>? title,
      Value<String?>? artist,
      Value<String?>? album,
      Value<String?>? albumArtist,
      Value<String?>? genre,
      Value<String?>? artworkPath,
      Value<String?>? artworkHash,
      Value<String?>? artworkMimeType,
      Value<String?>? customArtworkPath,
      Value<String?>? customArtworkHash,
      Value<String?>? customArtworkMimeType,
      Value<String?>? codec,
      Value<int?>? durationMs,
      Value<int?>? trackNumber,
      Value<int?>? discNumber,
      Value<int?>? year,
      Value<String?>? metadataSource,
      Value<double?>? metadataConfidence,
      Value<int?>? fileSizeBytes,
      Value<DateTime?>? modifiedAt,
      Value<DateTime?>? lastSeenAt,
      Value<bool>? isMissing,
      Value<DateTime>? addedAt,
      Value<DateTime>? updatedAt}) {
    return TracksCompanion(
      id: id ?? this.id,
      libraryFolderId: libraryFolderId ?? this.libraryFolderId,
      stableId: stableId ?? this.stableId,
      filePath: filePath ?? this.filePath,
      contentHash: contentHash ?? this.contentHash,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      artworkPath: artworkPath ?? this.artworkPath,
      artworkHash: artworkHash ?? this.artworkHash,
      artworkMimeType: artworkMimeType ?? this.artworkMimeType,
      customArtworkPath: customArtworkPath ?? this.customArtworkPath,
      customArtworkHash: customArtworkHash ?? this.customArtworkHash,
      customArtworkMimeType:
          customArtworkMimeType ?? this.customArtworkMimeType,
      codec: codec ?? this.codec,
      durationMs: durationMs ?? this.durationMs,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      metadataSource: metadataSource ?? this.metadataSource,
      metadataConfidence: metadataConfidence ?? this.metadataConfidence,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isMissing: isMissing ?? this.isMissing,
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
    if (stableId.present) {
      map['stable_id'] = Variable<String>(stableId.value);
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
    if (artworkPath.present) {
      map['artwork_path'] = Variable<String>(artworkPath.value);
    }
    if (artworkHash.present) {
      map['artwork_hash'] = Variable<String>(artworkHash.value);
    }
    if (artworkMimeType.present) {
      map['artwork_mime_type'] = Variable<String>(artworkMimeType.value);
    }
    if (customArtworkPath.present) {
      map['custom_artwork_path'] = Variable<String>(customArtworkPath.value);
    }
    if (customArtworkHash.present) {
      map['custom_artwork_hash'] = Variable<String>(customArtworkHash.value);
    }
    if (customArtworkMimeType.present) {
      map['custom_artwork_mime_type'] =
          Variable<String>(customArtworkMimeType.value);
    }
    if (codec.present) {
      map['codec'] = Variable<String>(codec.value);
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
    if (metadataSource.present) {
      map['metadata_source'] = Variable<String>(metadataSource.value);
    }
    if (metadataConfidence.present) {
      map['metadata_confidence'] = Variable<double>(metadataConfidence.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (isMissing.present) {
      map['is_missing'] = Variable<bool>(isMissing.value);
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
          ..write('stableId: $stableId, ')
          ..write('filePath: $filePath, ')
          ..write('contentHash: $contentHash, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('genre: $genre, ')
          ..write('artworkPath: $artworkPath, ')
          ..write('artworkHash: $artworkHash, ')
          ..write('artworkMimeType: $artworkMimeType, ')
          ..write('customArtworkPath: $customArtworkPath, ')
          ..write('customArtworkHash: $customArtworkHash, ')
          ..write('customArtworkMimeType: $customArtworkMimeType, ')
          ..write('codec: $codec, ')
          ..write('durationMs: $durationMs, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('metadataSource: $metadataSource, ')
          ..write('metadataConfidence: $metadataConfidence, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('isMissing: $isMissing, ')
          ..write('addedAt: $addedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, PlaylistRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
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
  List<GeneratedColumn> get $columns =>
      [id, name, description, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(Insertable<PlaylistRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
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
  PlaylistRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class PlaylistRow extends DataClass implements Insertable<PlaylistRow> {
  final int id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  const PlaylistRow(
      {required this.id,
      required this.name,
      this.description,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlaylistRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlaylistRow copyWith(
          {int? id,
          String? name,
          Value<String?> description = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      PlaylistRow(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description.present ? description.value : this.description,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  PlaylistRow copyWithCompanion(PlaylistsCompanion data) {
    return PlaylistRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, description, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlaylistsCompanion extends UpdateCompanion<PlaylistRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  })  : name = Value(name),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<PlaylistRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PlaylistsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String?>? description,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
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
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PlaylistTracksTable extends PlaylistTracks
    with TableInfo<$PlaylistTracksTable, PlaylistTrackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta =
      const VerificationMeta('playlistId');
  @override
  late final GeneratedColumn<int> playlistId = GeneratedColumn<int>(
      'playlist_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES playlists (id) ON DELETE CASCADE'));
  static const VerificationMeta _trackIdMeta =
      const VerificationMeta('trackId');
  @override
  late final GeneratedColumn<int> trackId = GeneratedColumn<int>(
      'track_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES tracks (id) ON DELETE CASCADE'));
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [playlistId, trackId, position, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_tracks';
  @override
  VerificationContext validateIntegrity(Insertable<PlaylistTrackRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
          _playlistIdMeta,
          playlistId.isAcceptableOrUnknown(
              data['playlist_id']!, _playlistIdMeta));
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('track_id')) {
      context.handle(_trackIdMeta,
          trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta));
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playlistId, trackId};
  @override
  PlaylistTrackRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistTrackRow(
      playlistId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}playlist_id'])!,
      trackId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_id'])!,
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $PlaylistTracksTable createAlias(String alias) {
    return $PlaylistTracksTable(attachedDatabase, alias);
  }
}

class PlaylistTrackRow extends DataClass
    implements Insertable<PlaylistTrackRow> {
  final int playlistId;
  final int trackId;
  final int position;
  final DateTime addedAt;
  const PlaylistTrackRow(
      {required this.playlistId,
      required this.trackId,
      required this.position,
      required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<int>(playlistId);
    map['track_id'] = Variable<int>(trackId);
    map['position'] = Variable<int>(position);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  PlaylistTracksCompanion toCompanion(bool nullToAbsent) {
    return PlaylistTracksCompanion(
      playlistId: Value(playlistId),
      trackId: Value(trackId),
      position: Value(position),
      addedAt: Value(addedAt),
    );
  }

  factory PlaylistTrackRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistTrackRow(
      playlistId: serializer.fromJson<int>(json['playlistId']),
      trackId: serializer.fromJson<int>(json['trackId']),
      position: serializer.fromJson<int>(json['position']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<int>(playlistId),
      'trackId': serializer.toJson<int>(trackId),
      'position': serializer.toJson<int>(position),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  PlaylistTrackRow copyWith(
          {int? playlistId, int? trackId, int? position, DateTime? addedAt}) =>
      PlaylistTrackRow(
        playlistId: playlistId ?? this.playlistId,
        trackId: trackId ?? this.trackId,
        position: position ?? this.position,
        addedAt: addedAt ?? this.addedAt,
      );
  PlaylistTrackRow copyWithCompanion(PlaylistTracksCompanion data) {
    return PlaylistTrackRow(
      playlistId:
          data.playlistId.present ? data.playlistId.value : this.playlistId,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      position: data.position.present ? data.position.value : this.position,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistTrackRow(')
          ..write('playlistId: $playlistId, ')
          ..write('trackId: $trackId, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(playlistId, trackId, position, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistTrackRow &&
          other.playlistId == this.playlistId &&
          other.trackId == this.trackId &&
          other.position == this.position &&
          other.addedAt == this.addedAt);
}

class PlaylistTracksCompanion extends UpdateCompanion<PlaylistTrackRow> {
  final Value<int> playlistId;
  final Value<int> trackId;
  final Value<int> position;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const PlaylistTracksCompanion({
    this.playlistId = const Value.absent(),
    this.trackId = const Value.absent(),
    this.position = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistTracksCompanion.insert({
    required int playlistId,
    required int trackId,
    required int position,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  })  : playlistId = Value(playlistId),
        trackId = Value(trackId),
        position = Value(position),
        addedAt = Value(addedAt);
  static Insertable<PlaylistTrackRow> custom({
    Expression<int>? playlistId,
    Expression<int>? trackId,
    Expression<int>? position,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (trackId != null) 'track_id': trackId,
      if (position != null) 'position': position,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistTracksCompanion copyWith(
      {Value<int>? playlistId,
      Value<int>? trackId,
      Value<int>? position,
      Value<DateTime>? addedAt,
      Value<int>? rowid}) {
    return PlaylistTracksCompanion(
      playlistId: playlistId ?? this.playlistId,
      trackId: trackId ?? this.trackId,
      position: position ?? this.position,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<int>(playlistId.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<int>(trackId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistTracksCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('trackId: $trackId, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
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
  static const VerificationMeta _operationIdMeta =
      const VerificationMeta('operationId');
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
      'operation_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
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
        operationId,
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
    if (data.containsKey('operation_id')) {
      context.handle(
          _operationIdMeta,
          operationId.isAcceptableOrUnknown(
              data['operation_id']!, _operationIdMeta));
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
      operationId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation_id']),
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
  final String? operationId;
  final int trackId;
  final String eventType;
  final DateTime occurredAt;
  final int? positionMs;
  final int? durationMs;
  final String? waveMode;
  final String? metadataJson;
  const PlaybackEventRow(
      {required this.id,
      this.operationId,
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
    if (!nullToAbsent || operationId != null) {
      map['operation_id'] = Variable<String>(operationId);
    }
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
      operationId: operationId == null && nullToAbsent
          ? const Value.absent()
          : Value(operationId),
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
      operationId: serializer.fromJson<String?>(json['operationId']),
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
      'operationId': serializer.toJson<String?>(operationId),
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
          Value<String?> operationId = const Value.absent(),
          int? trackId,
          String? eventType,
          DateTime? occurredAt,
          Value<int?> positionMs = const Value.absent(),
          Value<int?> durationMs = const Value.absent(),
          Value<String?> waveMode = const Value.absent(),
          Value<String?> metadataJson = const Value.absent()}) =>
      PlaybackEventRow(
        id: id ?? this.id,
        operationId: operationId.present ? operationId.value : this.operationId,
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
      operationId:
          data.operationId.present ? data.operationId.value : this.operationId,
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
          ..write('operationId: $operationId, ')
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
  int get hashCode => Object.hash(id, operationId, trackId, eventType,
      occurredAt, positionMs, durationMs, waveMode, metadataJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackEventRow &&
          other.id == this.id &&
          other.operationId == this.operationId &&
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
  final Value<String?> operationId;
  final Value<int> trackId;
  final Value<String> eventType;
  final Value<DateTime> occurredAt;
  final Value<int?> positionMs;
  final Value<int?> durationMs;
  final Value<String?> waveMode;
  final Value<String?> metadataJson;
  const PlaybackEventsCompanion({
    this.id = const Value.absent(),
    this.operationId = const Value.absent(),
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
    this.operationId = const Value.absent(),
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
    Expression<String>? operationId,
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
      if (operationId != null) 'operation_id': operationId,
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
      Value<String?>? operationId,
      Value<int>? trackId,
      Value<String>? eventType,
      Value<DateTime>? occurredAt,
      Value<int?>? positionMs,
      Value<int?>? durationMs,
      Value<String?>? waveMode,
      Value<String?>? metadataJson}) {
    return PlaybackEventsCompanion(
      id: id ?? this.id,
      operationId: operationId ?? this.operationId,
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
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
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
          ..write('operationId: $operationId, ')
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
  static const VerificationMeta _completeCountMeta =
      const VerificationMeta('completeCount');
  @override
  late final GeneratedColumn<int> completeCount = GeneratedColumn<int>(
      'complete_count', aliasedName, false,
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
        completeCount,
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
    if (data.containsKey('complete_count')) {
      context.handle(
          _completeCountMeta,
          completeCount.isAcceptableOrUnknown(
              data['complete_count']!, _completeCountMeta));
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
      completeCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}complete_count'])!,
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
  final int completeCount;
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
      required this.completeCount,
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
    map['complete_count'] = Variable<int>(completeCount);
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
      completeCount: Value(completeCount),
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
      completeCount: serializer.fromJson<int>(json['completeCount']),
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
      'completeCount': serializer.toJson<int>(completeCount),
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
          int? completeCount,
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
        completeCount: completeCount ?? this.completeCount,
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
      completeCount: data.completeCount.present
          ? data.completeCount.value
          : this.completeCount,
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
          ..write('completeCount: $completeCount, ')
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
      completeCount,
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
          other.completeCount == this.completeCount &&
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
  final Value<int> completeCount;
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
    this.completeCount = const Value.absent(),
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
    this.completeCount = const Value.absent(),
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
    Expression<int>? completeCount,
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
      if (completeCount != null) 'complete_count': completeCount,
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
      Value<int>? completeCount,
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
      completeCount: completeCount ?? this.completeCount,
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
    if (completeCount.present) {
      map['complete_count'] = Variable<int>(completeCount.value);
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
          ..write('completeCount: $completeCount, ')
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

class $ExternalTrackRefsTable extends ExternalTrackRefs
    with TableInfo<$ExternalTrackRefsTable, ExternalTrackRefRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExternalTrackRefsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackIdMeta =
      const VerificationMeta('trackId');
  @override
  late final GeneratedColumn<int> trackId = GeneratedColumn<int>(
      'track_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES tracks (id) ON DELETE CASCADE'));
  static const VerificationMeta _providerMeta =
      const VerificationMeta('provider');
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
      'provider', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _externalIdMeta =
      const VerificationMeta('externalId');
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
      'external_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _variantKeyMeta =
      const VerificationMeta('variantKey');
  @override
  late final GeneratedColumn<String> variantKey = GeneratedColumn<String>(
      'variant_key', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
      'origin', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _linkedAtMeta =
      const VerificationMeta('linkedAt');
  @override
  late final GeneratedColumn<DateTime> linkedAt = GeneratedColumn<DateTime>(
      'linked_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [trackId, provider, externalId, variantKey, origin, linkedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'external_track_refs';
  @override
  VerificationContext validateIntegrity(
      Insertable<ExternalTrackRefRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_id')) {
      context.handle(_trackIdMeta,
          trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta));
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(_providerMeta,
          provider.isAcceptableOrUnknown(data['provider']!, _providerMeta));
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('external_id')) {
      context.handle(
          _externalIdMeta,
          externalId.isAcceptableOrUnknown(
              data['external_id']!, _externalIdMeta));
    } else if (isInserting) {
      context.missing(_externalIdMeta);
    }
    if (data.containsKey('variant_key')) {
      context.handle(
          _variantKeyMeta,
          variantKey.isAcceptableOrUnknown(
              data['variant_key']!, _variantKeyMeta));
    }
    if (data.containsKey('origin')) {
      context.handle(_originMeta,
          origin.isAcceptableOrUnknown(data['origin']!, _originMeta));
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('linked_at')) {
      context.handle(_linkedAtMeta,
          linkedAt.isAcceptableOrUnknown(data['linked_at']!, _linkedAtMeta));
    } else if (isInserting) {
      context.missing(_linkedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey =>
      {trackId, provider, externalId, variantKey};
  @override
  ExternalTrackRefRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExternalTrackRefRow(
      trackId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_id'])!,
      provider: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}provider'])!,
      externalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}external_id'])!,
      variantKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}variant_key'])!,
      origin: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}origin'])!,
      linkedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}linked_at'])!,
    );
  }

  @override
  $ExternalTrackRefsTable createAlias(String alias) {
    return $ExternalTrackRefsTable(attachedDatabase, alias);
  }
}

class ExternalTrackRefRow extends DataClass
    implements Insertable<ExternalTrackRefRow> {
  final int trackId;
  final String provider;
  final String externalId;
  final String variantKey;
  final String origin;
  final DateTime linkedAt;
  const ExternalTrackRefRow(
      {required this.trackId,
      required this.provider,
      required this.externalId,
      required this.variantKey,
      required this.origin,
      required this.linkedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_id'] = Variable<int>(trackId);
    map['provider'] = Variable<String>(provider);
    map['external_id'] = Variable<String>(externalId);
    map['variant_key'] = Variable<String>(variantKey);
    map['origin'] = Variable<String>(origin);
    map['linked_at'] = Variable<DateTime>(linkedAt);
    return map;
  }

  ExternalTrackRefsCompanion toCompanion(bool nullToAbsent) {
    return ExternalTrackRefsCompanion(
      trackId: Value(trackId),
      provider: Value(provider),
      externalId: Value(externalId),
      variantKey: Value(variantKey),
      origin: Value(origin),
      linkedAt: Value(linkedAt),
    );
  }

  factory ExternalTrackRefRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExternalTrackRefRow(
      trackId: serializer.fromJson<int>(json['trackId']),
      provider: serializer.fromJson<String>(json['provider']),
      externalId: serializer.fromJson<String>(json['externalId']),
      variantKey: serializer.fromJson<String>(json['variantKey']),
      origin: serializer.fromJson<String>(json['origin']),
      linkedAt: serializer.fromJson<DateTime>(json['linkedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackId': serializer.toJson<int>(trackId),
      'provider': serializer.toJson<String>(provider),
      'externalId': serializer.toJson<String>(externalId),
      'variantKey': serializer.toJson<String>(variantKey),
      'origin': serializer.toJson<String>(origin),
      'linkedAt': serializer.toJson<DateTime>(linkedAt),
    };
  }

  ExternalTrackRefRow copyWith(
          {int? trackId,
          String? provider,
          String? externalId,
          String? variantKey,
          String? origin,
          DateTime? linkedAt}) =>
      ExternalTrackRefRow(
        trackId: trackId ?? this.trackId,
        provider: provider ?? this.provider,
        externalId: externalId ?? this.externalId,
        variantKey: variantKey ?? this.variantKey,
        origin: origin ?? this.origin,
        linkedAt: linkedAt ?? this.linkedAt,
      );
  ExternalTrackRefRow copyWithCompanion(ExternalTrackRefsCompanion data) {
    return ExternalTrackRefRow(
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      provider: data.provider.present ? data.provider.value : this.provider,
      externalId:
          data.externalId.present ? data.externalId.value : this.externalId,
      variantKey:
          data.variantKey.present ? data.variantKey.value : this.variantKey,
      origin: data.origin.present ? data.origin.value : this.origin,
      linkedAt: data.linkedAt.present ? data.linkedAt.value : this.linkedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExternalTrackRefRow(')
          ..write('trackId: $trackId, ')
          ..write('provider: $provider, ')
          ..write('externalId: $externalId, ')
          ..write('variantKey: $variantKey, ')
          ..write('origin: $origin, ')
          ..write('linkedAt: $linkedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(trackId, provider, externalId, variantKey, origin, linkedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExternalTrackRefRow &&
          other.trackId == this.trackId &&
          other.provider == this.provider &&
          other.externalId == this.externalId &&
          other.variantKey == this.variantKey &&
          other.origin == this.origin &&
          other.linkedAt == this.linkedAt);
}

class ExternalTrackRefsCompanion extends UpdateCompanion<ExternalTrackRefRow> {
  final Value<int> trackId;
  final Value<String> provider;
  final Value<String> externalId;
  final Value<String> variantKey;
  final Value<String> origin;
  final Value<DateTime> linkedAt;
  final Value<int> rowid;
  const ExternalTrackRefsCompanion({
    this.trackId = const Value.absent(),
    this.provider = const Value.absent(),
    this.externalId = const Value.absent(),
    this.variantKey = const Value.absent(),
    this.origin = const Value.absent(),
    this.linkedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExternalTrackRefsCompanion.insert({
    required int trackId,
    required String provider,
    required String externalId,
    this.variantKey = const Value.absent(),
    required String origin,
    required DateTime linkedAt,
    this.rowid = const Value.absent(),
  })  : trackId = Value(trackId),
        provider = Value(provider),
        externalId = Value(externalId),
        origin = Value(origin),
        linkedAt = Value(linkedAt);
  static Insertable<ExternalTrackRefRow> custom({
    Expression<int>? trackId,
    Expression<String>? provider,
    Expression<String>? externalId,
    Expression<String>? variantKey,
    Expression<String>? origin,
    Expression<DateTime>? linkedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackId != null) 'track_id': trackId,
      if (provider != null) 'provider': provider,
      if (externalId != null) 'external_id': externalId,
      if (variantKey != null) 'variant_key': variantKey,
      if (origin != null) 'origin': origin,
      if (linkedAt != null) 'linked_at': linkedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExternalTrackRefsCompanion copyWith(
      {Value<int>? trackId,
      Value<String>? provider,
      Value<String>? externalId,
      Value<String>? variantKey,
      Value<String>? origin,
      Value<DateTime>? linkedAt,
      Value<int>? rowid}) {
    return ExternalTrackRefsCompanion(
      trackId: trackId ?? this.trackId,
      provider: provider ?? this.provider,
      externalId: externalId ?? this.externalId,
      variantKey: variantKey ?? this.variantKey,
      origin: origin ?? this.origin,
      linkedAt: linkedAt ?? this.linkedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackId.present) {
      map['track_id'] = Variable<int>(trackId.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (variantKey.present) {
      map['variant_key'] = Variable<String>(variantKey.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (linkedAt.present) {
      map['linked_at'] = Variable<DateTime>(linkedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExternalTrackRefsCompanion(')
          ..write('trackId: $trackId, ')
          ..write('provider: $provider, ')
          ..write('externalId: $externalId, ')
          ..write('variantKey: $variantKey, ')
          ..write('origin: $origin, ')
          ..write('linkedAt: $linkedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadedAssetsTable extends DownloadedAssets
    with TableInfo<$DownloadedAssetsTable, DownloadedAssetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadedAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackIdMeta =
      const VerificationMeta('trackId');
  @override
  late final GeneratedColumn<int> trackId = GeneratedColumn<int>(
      'track_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES tracks (id) ON DELETE CASCADE'));
  static const VerificationMeta _providerMeta =
      const VerificationMeta('provider');
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
      'provider', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _externalIdMeta =
      const VerificationMeta('externalId');
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
      'external_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _variantKeyMeta =
      const VerificationMeta('variantKey');
  @override
  late final GeneratedColumn<String> variantKey = GeneratedColumn<String>(
      'variant_key', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _publicationIdMeta =
      const VerificationMeta('publicationId');
  @override
  late final GeneratedColumn<String> publicationId = GeneratedColumn<String>(
      'publication_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _requestedQualityMeta =
      const VerificationMeta('requestedQuality');
  @override
  late final GeneratedColumn<String> requestedQuality = GeneratedColumn<String>(
      'requested_quality', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _actualQualityMeta =
      const VerificationMeta('actualQuality');
  @override
  late final GeneratedColumn<String> actualQuality = GeneratedColumn<String>(
      'actual_quality', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _containerMeta =
      const VerificationMeta('container');
  @override
  late final GeneratedColumn<String> container = GeneratedColumn<String>(
      'container', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _codecMeta = const VerificationMeta('codec');
  @override
  late final GeneratedColumn<String> codec = GeneratedColumn<String>(
      'codec', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileSizeBytesMeta =
      const VerificationMeta('fileSizeBytes');
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
      'file_size_bytes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _contentHashMeta =
      const VerificationMeta('contentHash');
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
      'content_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _verifiedAtMicrosMeta =
      const VerificationMeta('verifiedAtMicros');
  @override
  late final GeneratedColumn<int> verifiedAtMicros = GeneratedColumn<int>(
      'verified_at_micros', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _revisionMeta =
      const VerificationMeta('revision');
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
      'revision', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  @override
  List<GeneratedColumn> get $columns => [
        trackId,
        provider,
        externalId,
        variantKey,
        source,
        publicationId,
        requestedQuality,
        actualQuality,
        container,
        codec,
        fileSizeBytes,
        durationMs,
        contentHash,
        verifiedAtMicros,
        state,
        revision
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downloaded_assets';
  @override
  VerificationContext validateIntegrity(Insertable<DownloadedAssetRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_id')) {
      context.handle(_trackIdMeta,
          trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta));
    }
    if (data.containsKey('provider')) {
      context.handle(_providerMeta,
          provider.isAcceptableOrUnknown(data['provider']!, _providerMeta));
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('external_id')) {
      context.handle(
          _externalIdMeta,
          externalId.isAcceptableOrUnknown(
              data['external_id']!, _externalIdMeta));
    } else if (isInserting) {
      context.missing(_externalIdMeta);
    }
    if (data.containsKey('variant_key')) {
      context.handle(
          _variantKeyMeta,
          variantKey.isAcceptableOrUnknown(
              data['variant_key']!, _variantKeyMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('publication_id')) {
      context.handle(
          _publicationIdMeta,
          publicationId.isAcceptableOrUnknown(
              data['publication_id']!, _publicationIdMeta));
    } else if (isInserting) {
      context.missing(_publicationIdMeta);
    }
    if (data.containsKey('requested_quality')) {
      context.handle(
          _requestedQualityMeta,
          requestedQuality.isAcceptableOrUnknown(
              data['requested_quality']!, _requestedQualityMeta));
    } else if (isInserting) {
      context.missing(_requestedQualityMeta);
    }
    if (data.containsKey('actual_quality')) {
      context.handle(
          _actualQualityMeta,
          actualQuality.isAcceptableOrUnknown(
              data['actual_quality']!, _actualQualityMeta));
    } else if (isInserting) {
      context.missing(_actualQualityMeta);
    }
    if (data.containsKey('container')) {
      context.handle(_containerMeta,
          container.isAcceptableOrUnknown(data['container']!, _containerMeta));
    } else if (isInserting) {
      context.missing(_containerMeta);
    }
    if (data.containsKey('codec')) {
      context.handle(
          _codecMeta, codec.isAcceptableOrUnknown(data['codec']!, _codecMeta));
    } else if (isInserting) {
      context.missing(_codecMeta);
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
          _fileSizeBytesMeta,
          fileSizeBytes.isAcceptableOrUnknown(
              data['file_size_bytes']!, _fileSizeBytesMeta));
    } else if (isInserting) {
      context.missing(_fileSizeBytesMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
          _contentHashMeta,
          contentHash.isAcceptableOrUnknown(
              data['content_hash']!, _contentHashMeta));
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('verified_at_micros')) {
      context.handle(
          _verifiedAtMicrosMeta,
          verifiedAtMicros.isAcceptableOrUnknown(
              data['verified_at_micros']!, _verifiedAtMicrosMeta));
    } else if (isInserting) {
      context.missing(_verifiedAtMicrosMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(_revisionMeta,
          revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackId};
  @override
  DownloadedAssetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadedAssetRow(
      trackId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_id'])!,
      provider: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}provider'])!,
      externalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}external_id'])!,
      variantKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}variant_key'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      publicationId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}publication_id'])!,
      requestedQuality: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}requested_quality'])!,
      actualQuality: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}actual_quality'])!,
      container: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}container'])!,
      codec: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}codec'])!,
      fileSizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}file_size_bytes'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms'])!,
      contentHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_hash'])!,
      verifiedAtMicros: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}verified_at_micros'])!,
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      revision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}revision'])!,
    );
  }

  @override
  $DownloadedAssetsTable createAlias(String alias) {
    return $DownloadedAssetsTable(attachedDatabase, alias);
  }
}

class DownloadedAssetRow extends DataClass
    implements Insertable<DownloadedAssetRow> {
  final int trackId;
  final String provider;
  final String externalId;
  final String variantKey;
  final String source;
  final String publicationId;
  final String requestedQuality;
  final String actualQuality;
  final String container;
  final String codec;
  final int fileSizeBytes;
  final int durationMs;
  final String contentHash;
  final int verifiedAtMicros;
  final String state;
  final int revision;
  const DownloadedAssetRow(
      {required this.trackId,
      required this.provider,
      required this.externalId,
      required this.variantKey,
      required this.source,
      required this.publicationId,
      required this.requestedQuality,
      required this.actualQuality,
      required this.container,
      required this.codec,
      required this.fileSizeBytes,
      required this.durationMs,
      required this.contentHash,
      required this.verifiedAtMicros,
      required this.state,
      required this.revision});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_id'] = Variable<int>(trackId);
    map['provider'] = Variable<String>(provider);
    map['external_id'] = Variable<String>(externalId);
    map['variant_key'] = Variable<String>(variantKey);
    map['source'] = Variable<String>(source);
    map['publication_id'] = Variable<String>(publicationId);
    map['requested_quality'] = Variable<String>(requestedQuality);
    map['actual_quality'] = Variable<String>(actualQuality);
    map['container'] = Variable<String>(container);
    map['codec'] = Variable<String>(codec);
    map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    map['duration_ms'] = Variable<int>(durationMs);
    map['content_hash'] = Variable<String>(contentHash);
    map['verified_at_micros'] = Variable<int>(verifiedAtMicros);
    map['state'] = Variable<String>(state);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  DownloadedAssetsCompanion toCompanion(bool nullToAbsent) {
    return DownloadedAssetsCompanion(
      trackId: Value(trackId),
      provider: Value(provider),
      externalId: Value(externalId),
      variantKey: Value(variantKey),
      source: Value(source),
      publicationId: Value(publicationId),
      requestedQuality: Value(requestedQuality),
      actualQuality: Value(actualQuality),
      container: Value(container),
      codec: Value(codec),
      fileSizeBytes: Value(fileSizeBytes),
      durationMs: Value(durationMs),
      contentHash: Value(contentHash),
      verifiedAtMicros: Value(verifiedAtMicros),
      state: Value(state),
      revision: Value(revision),
    );
  }

  factory DownloadedAssetRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadedAssetRow(
      trackId: serializer.fromJson<int>(json['trackId']),
      provider: serializer.fromJson<String>(json['provider']),
      externalId: serializer.fromJson<String>(json['externalId']),
      variantKey: serializer.fromJson<String>(json['variantKey']),
      source: serializer.fromJson<String>(json['source']),
      publicationId: serializer.fromJson<String>(json['publicationId']),
      requestedQuality: serializer.fromJson<String>(json['requestedQuality']),
      actualQuality: serializer.fromJson<String>(json['actualQuality']),
      container: serializer.fromJson<String>(json['container']),
      codec: serializer.fromJson<String>(json['codec']),
      fileSizeBytes: serializer.fromJson<int>(json['fileSizeBytes']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      verifiedAtMicros: serializer.fromJson<int>(json['verifiedAtMicros']),
      state: serializer.fromJson<String>(json['state']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackId': serializer.toJson<int>(trackId),
      'provider': serializer.toJson<String>(provider),
      'externalId': serializer.toJson<String>(externalId),
      'variantKey': serializer.toJson<String>(variantKey),
      'source': serializer.toJson<String>(source),
      'publicationId': serializer.toJson<String>(publicationId),
      'requestedQuality': serializer.toJson<String>(requestedQuality),
      'actualQuality': serializer.toJson<String>(actualQuality),
      'container': serializer.toJson<String>(container),
      'codec': serializer.toJson<String>(codec),
      'fileSizeBytes': serializer.toJson<int>(fileSizeBytes),
      'durationMs': serializer.toJson<int>(durationMs),
      'contentHash': serializer.toJson<String>(contentHash),
      'verifiedAtMicros': serializer.toJson<int>(verifiedAtMicros),
      'state': serializer.toJson<String>(state),
      'revision': serializer.toJson<int>(revision),
    };
  }

  DownloadedAssetRow copyWith(
          {int? trackId,
          String? provider,
          String? externalId,
          String? variantKey,
          String? source,
          String? publicationId,
          String? requestedQuality,
          String? actualQuality,
          String? container,
          String? codec,
          int? fileSizeBytes,
          int? durationMs,
          String? contentHash,
          int? verifiedAtMicros,
          String? state,
          int? revision}) =>
      DownloadedAssetRow(
        trackId: trackId ?? this.trackId,
        provider: provider ?? this.provider,
        externalId: externalId ?? this.externalId,
        variantKey: variantKey ?? this.variantKey,
        source: source ?? this.source,
        publicationId: publicationId ?? this.publicationId,
        requestedQuality: requestedQuality ?? this.requestedQuality,
        actualQuality: actualQuality ?? this.actualQuality,
        container: container ?? this.container,
        codec: codec ?? this.codec,
        fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
        durationMs: durationMs ?? this.durationMs,
        contentHash: contentHash ?? this.contentHash,
        verifiedAtMicros: verifiedAtMicros ?? this.verifiedAtMicros,
        state: state ?? this.state,
        revision: revision ?? this.revision,
      );
  DownloadedAssetRow copyWithCompanion(DownloadedAssetsCompanion data) {
    return DownloadedAssetRow(
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      provider: data.provider.present ? data.provider.value : this.provider,
      externalId:
          data.externalId.present ? data.externalId.value : this.externalId,
      variantKey:
          data.variantKey.present ? data.variantKey.value : this.variantKey,
      source: data.source.present ? data.source.value : this.source,
      publicationId: data.publicationId.present
          ? data.publicationId.value
          : this.publicationId,
      requestedQuality: data.requestedQuality.present
          ? data.requestedQuality.value
          : this.requestedQuality,
      actualQuality: data.actualQuality.present
          ? data.actualQuality.value
          : this.actualQuality,
      container: data.container.present ? data.container.value : this.container,
      codec: data.codec.present ? data.codec.value : this.codec,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      contentHash:
          data.contentHash.present ? data.contentHash.value : this.contentHash,
      verifiedAtMicros: data.verifiedAtMicros.present
          ? data.verifiedAtMicros.value
          : this.verifiedAtMicros,
      state: data.state.present ? data.state.value : this.state,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadedAssetRow(')
          ..write('trackId: $trackId, ')
          ..write('provider: $provider, ')
          ..write('externalId: $externalId, ')
          ..write('variantKey: $variantKey, ')
          ..write('source: $source, ')
          ..write('publicationId: $publicationId, ')
          ..write('requestedQuality: $requestedQuality, ')
          ..write('actualQuality: $actualQuality, ')
          ..write('container: $container, ')
          ..write('codec: $codec, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('durationMs: $durationMs, ')
          ..write('contentHash: $contentHash, ')
          ..write('verifiedAtMicros: $verifiedAtMicros, ')
          ..write('state: $state, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      trackId,
      provider,
      externalId,
      variantKey,
      source,
      publicationId,
      requestedQuality,
      actualQuality,
      container,
      codec,
      fileSizeBytes,
      durationMs,
      contentHash,
      verifiedAtMicros,
      state,
      revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadedAssetRow &&
          other.trackId == this.trackId &&
          other.provider == this.provider &&
          other.externalId == this.externalId &&
          other.variantKey == this.variantKey &&
          other.source == this.source &&
          other.publicationId == this.publicationId &&
          other.requestedQuality == this.requestedQuality &&
          other.actualQuality == this.actualQuality &&
          other.container == this.container &&
          other.codec == this.codec &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.durationMs == this.durationMs &&
          other.contentHash == this.contentHash &&
          other.verifiedAtMicros == this.verifiedAtMicros &&
          other.state == this.state &&
          other.revision == this.revision);
}

class DownloadedAssetsCompanion extends UpdateCompanion<DownloadedAssetRow> {
  final Value<int> trackId;
  final Value<String> provider;
  final Value<String> externalId;
  final Value<String> variantKey;
  final Value<String> source;
  final Value<String> publicationId;
  final Value<String> requestedQuality;
  final Value<String> actualQuality;
  final Value<String> container;
  final Value<String> codec;
  final Value<int> fileSizeBytes;
  final Value<int> durationMs;
  final Value<String> contentHash;
  final Value<int> verifiedAtMicros;
  final Value<String> state;
  final Value<int> revision;
  const DownloadedAssetsCompanion({
    this.trackId = const Value.absent(),
    this.provider = const Value.absent(),
    this.externalId = const Value.absent(),
    this.variantKey = const Value.absent(),
    this.source = const Value.absent(),
    this.publicationId = const Value.absent(),
    this.requestedQuality = const Value.absent(),
    this.actualQuality = const Value.absent(),
    this.container = const Value.absent(),
    this.codec = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.verifiedAtMicros = const Value.absent(),
    this.state = const Value.absent(),
    this.revision = const Value.absent(),
  });
  DownloadedAssetsCompanion.insert({
    this.trackId = const Value.absent(),
    required String provider,
    required String externalId,
    this.variantKey = const Value.absent(),
    required String source,
    required String publicationId,
    required String requestedQuality,
    required String actualQuality,
    required String container,
    required String codec,
    required int fileSizeBytes,
    required int durationMs,
    required String contentHash,
    required int verifiedAtMicros,
    required String state,
    this.revision = const Value.absent(),
  })  : provider = Value(provider),
        externalId = Value(externalId),
        source = Value(source),
        publicationId = Value(publicationId),
        requestedQuality = Value(requestedQuality),
        actualQuality = Value(actualQuality),
        container = Value(container),
        codec = Value(codec),
        fileSizeBytes = Value(fileSizeBytes),
        durationMs = Value(durationMs),
        contentHash = Value(contentHash),
        verifiedAtMicros = Value(verifiedAtMicros),
        state = Value(state);
  static Insertable<DownloadedAssetRow> custom({
    Expression<int>? trackId,
    Expression<String>? provider,
    Expression<String>? externalId,
    Expression<String>? variantKey,
    Expression<String>? source,
    Expression<String>? publicationId,
    Expression<String>? requestedQuality,
    Expression<String>? actualQuality,
    Expression<String>? container,
    Expression<String>? codec,
    Expression<int>? fileSizeBytes,
    Expression<int>? durationMs,
    Expression<String>? contentHash,
    Expression<int>? verifiedAtMicros,
    Expression<String>? state,
    Expression<int>? revision,
  }) {
    return RawValuesInsertable({
      if (trackId != null) 'track_id': trackId,
      if (provider != null) 'provider': provider,
      if (externalId != null) 'external_id': externalId,
      if (variantKey != null) 'variant_key': variantKey,
      if (source != null) 'source': source,
      if (publicationId != null) 'publication_id': publicationId,
      if (requestedQuality != null) 'requested_quality': requestedQuality,
      if (actualQuality != null) 'actual_quality': actualQuality,
      if (container != null) 'container': container,
      if (codec != null) 'codec': codec,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (durationMs != null) 'duration_ms': durationMs,
      if (contentHash != null) 'content_hash': contentHash,
      if (verifiedAtMicros != null) 'verified_at_micros': verifiedAtMicros,
      if (state != null) 'state': state,
      if (revision != null) 'revision': revision,
    });
  }

  DownloadedAssetsCompanion copyWith(
      {Value<int>? trackId,
      Value<String>? provider,
      Value<String>? externalId,
      Value<String>? variantKey,
      Value<String>? source,
      Value<String>? publicationId,
      Value<String>? requestedQuality,
      Value<String>? actualQuality,
      Value<String>? container,
      Value<String>? codec,
      Value<int>? fileSizeBytes,
      Value<int>? durationMs,
      Value<String>? contentHash,
      Value<int>? verifiedAtMicros,
      Value<String>? state,
      Value<int>? revision}) {
    return DownloadedAssetsCompanion(
      trackId: trackId ?? this.trackId,
      provider: provider ?? this.provider,
      externalId: externalId ?? this.externalId,
      variantKey: variantKey ?? this.variantKey,
      source: source ?? this.source,
      publicationId: publicationId ?? this.publicationId,
      requestedQuality: requestedQuality ?? this.requestedQuality,
      actualQuality: actualQuality ?? this.actualQuality,
      container: container ?? this.container,
      codec: codec ?? this.codec,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      durationMs: durationMs ?? this.durationMs,
      contentHash: contentHash ?? this.contentHash,
      verifiedAtMicros: verifiedAtMicros ?? this.verifiedAtMicros,
      state: state ?? this.state,
      revision: revision ?? this.revision,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackId.present) {
      map['track_id'] = Variable<int>(trackId.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (variantKey.present) {
      map['variant_key'] = Variable<String>(variantKey.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (publicationId.present) {
      map['publication_id'] = Variable<String>(publicationId.value);
    }
    if (requestedQuality.present) {
      map['requested_quality'] = Variable<String>(requestedQuality.value);
    }
    if (actualQuality.present) {
      map['actual_quality'] = Variable<String>(actualQuality.value);
    }
    if (container.present) {
      map['container'] = Variable<String>(container.value);
    }
    if (codec.present) {
      map['codec'] = Variable<String>(codec.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (verifiedAtMicros.present) {
      map['verified_at_micros'] = Variable<int>(verifiedAtMicros.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadedAssetsCompanion(')
          ..write('trackId: $trackId, ')
          ..write('provider: $provider, ')
          ..write('externalId: $externalId, ')
          ..write('variantKey: $variantKey, ')
          ..write('source: $source, ')
          ..write('publicationId: $publicationId, ')
          ..write('requestedQuality: $requestedQuality, ')
          ..write('actualQuality: $actualQuality, ')
          ..write('container: $container, ')
          ..write('codec: $codec, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('durationMs: $durationMs, ')
          ..write('contentHash: $contentHash, ')
          ..write('verifiedAtMicros: $verifiedAtMicros, ')
          ..write('state: $state, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }
}

class $RemoteAccountsTable extends RemoteAccounts
    with TableInfo<$RemoteAccountsTable, RemoteAccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteAccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _providerMeta =
      const VerificationMeta('provider');
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
      'provider', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'));
  static const VerificationMeta _revisionMeta =
      const VerificationMeta('revision');
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
      'revision', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, provider, accountId, displayName, isActive, revision];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_accounts';
  @override
  VerificationContext validateIntegrity(Insertable<RemoteAccountRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('provider')) {
      context.handle(_providerMeta,
          provider.isAcceptableOrUnknown(data['provider']!, _providerMeta));
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    } else if (isInserting) {
      context.missing(_isActiveMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(_revisionMeta,
          revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta));
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RemoteAccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteAccountRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      provider: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}provider'])!,
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      revision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}revision'])!,
    );
  }

  @override
  $RemoteAccountsTable createAlias(String alias) {
    return $RemoteAccountsTable(attachedDatabase, alias);
  }
}

class RemoteAccountRow extends DataClass
    implements Insertable<RemoteAccountRow> {
  final int id;
  final String provider;
  final String accountId;
  final String? displayName;
  final bool isActive;
  final int revision;
  const RemoteAccountRow(
      {required this.id,
      required this.provider,
      required this.accountId,
      this.displayName,
      required this.isActive,
      required this.revision});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['provider'] = Variable<String>(provider);
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  RemoteAccountsCompanion toCompanion(bool nullToAbsent) {
    return RemoteAccountsCompanion(
      id: Value(id),
      provider: Value(provider),
      accountId: Value(accountId),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      isActive: Value(isActive),
      revision: Value(revision),
    );
  }

  factory RemoteAccountRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteAccountRow(
      id: serializer.fromJson<int>(json['id']),
      provider: serializer.fromJson<String>(json['provider']),
      accountId: serializer.fromJson<String>(json['accountId']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'provider': serializer.toJson<String>(provider),
      'accountId': serializer.toJson<String>(accountId),
      'displayName': serializer.toJson<String?>(displayName),
      'isActive': serializer.toJson<bool>(isActive),
      'revision': serializer.toJson<int>(revision),
    };
  }

  RemoteAccountRow copyWith(
          {int? id,
          String? provider,
          String? accountId,
          Value<String?> displayName = const Value.absent(),
          bool? isActive,
          int? revision}) =>
      RemoteAccountRow(
        id: id ?? this.id,
        provider: provider ?? this.provider,
        accountId: accountId ?? this.accountId,
        displayName: displayName.present ? displayName.value : this.displayName,
        isActive: isActive ?? this.isActive,
        revision: revision ?? this.revision,
      );
  RemoteAccountRow copyWithCompanion(RemoteAccountsCompanion data) {
    return RemoteAccountRow(
      id: data.id.present ? data.id.value : this.id,
      provider: data.provider.present ? data.provider.value : this.provider,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteAccountRow(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('accountId: $accountId, ')
          ..write('displayName: $displayName, ')
          ..write('isActive: $isActive, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, provider, accountId, displayName, isActive, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteAccountRow &&
          other.id == this.id &&
          other.provider == this.provider &&
          other.accountId == this.accountId &&
          other.displayName == this.displayName &&
          other.isActive == this.isActive &&
          other.revision == this.revision);
}

class RemoteAccountsCompanion extends UpdateCompanion<RemoteAccountRow> {
  final Value<int> id;
  final Value<String> provider;
  final Value<String> accountId;
  final Value<String?> displayName;
  final Value<bool> isActive;
  final Value<int> revision;
  const RemoteAccountsCompanion({
    this.id = const Value.absent(),
    this.provider = const Value.absent(),
    this.accountId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.isActive = const Value.absent(),
    this.revision = const Value.absent(),
  });
  RemoteAccountsCompanion.insert({
    this.id = const Value.absent(),
    required String provider,
    required String accountId,
    this.displayName = const Value.absent(),
    required bool isActive,
    required int revision,
  })  : provider = Value(provider),
        accountId = Value(accountId),
        isActive = Value(isActive),
        revision = Value(revision);
  static Insertable<RemoteAccountRow> custom({
    Expression<int>? id,
    Expression<String>? provider,
    Expression<String>? accountId,
    Expression<String>? displayName,
    Expression<bool>? isActive,
    Expression<int>? revision,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (provider != null) 'provider': provider,
      if (accountId != null) 'account_id': accountId,
      if (displayName != null) 'display_name': displayName,
      if (isActive != null) 'is_active': isActive,
      if (revision != null) 'revision': revision,
    });
  }

  RemoteAccountsCompanion copyWith(
      {Value<int>? id,
      Value<String>? provider,
      Value<String>? accountId,
      Value<String?>? displayName,
      Value<bool>? isActive,
      Value<int>? revision}) {
    return RemoteAccountsCompanion(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      accountId: accountId ?? this.accountId,
      displayName: displayName ?? this.displayName,
      isActive: isActive ?? this.isActive,
      revision: revision ?? this.revision,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteAccountsCompanion(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('accountId: $accountId, ')
          ..write('displayName: $displayName, ')
          ..write('isActive: $isActive, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }
}

class $RemoteCollectionsTable extends RemoteCollections
    with TableInfo<$RemoteCollectionsTable, RemoteCollectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteCollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
      'account_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES remote_accounts (id) ON DELETE CASCADE'));
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _externalIdMeta =
      const VerificationMeta('externalId');
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
      'external_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isSelectedMeta =
      const VerificationMeta('isSelected');
  @override
  late final GeneratedColumn<bool> isSelected = GeneratedColumn<bool>(
      'is_selected', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_selected" IN (0, 1))'));
  static const VerificationMeta _revisionMeta =
      const VerificationMeta('revision');
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
      'revision', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _itemCountMeta =
      const VerificationMeta('itemCount');
  @override
  late final GeneratedColumn<int> itemCount = GeneratedColumn<int>(
      'item_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _remoteRevisionMeta =
      const VerificationMeta('remoteRevision');
  @override
  late final GeneratedColumn<String> remoteRevision = GeneratedColumn<String>(
      'remote_revision', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _completedAtMicrosMeta =
      const VerificationMeta('completedAtMicros');
  @override
  late final GeneratedColumn<int> completedAtMicros = GeneratedColumn<int>(
      'completed_at_micros', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        accountId,
        kind,
        externalId,
        ownerId,
        title,
        isSelected,
        revision,
        itemCount,
        remoteRevision,
        completedAtMicros
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_collections';
  @override
  VerificationContext validateIntegrity(
      Insertable<RemoteCollectionRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('external_id')) {
      context.handle(
          _externalIdMeta,
          externalId.isAcceptableOrUnknown(
              data['external_id']!, _externalIdMeta));
    } else if (isInserting) {
      context.missing(_externalIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('is_selected')) {
      context.handle(
          _isSelectedMeta,
          isSelected.isAcceptableOrUnknown(
              data['is_selected']!, _isSelectedMeta));
    } else if (isInserting) {
      context.missing(_isSelectedMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(_revisionMeta,
          revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta));
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('item_count')) {
      context.handle(_itemCountMeta,
          itemCount.isAcceptableOrUnknown(data['item_count']!, _itemCountMeta));
    }
    if (data.containsKey('remote_revision')) {
      context.handle(
          _remoteRevisionMeta,
          remoteRevision.isAcceptableOrUnknown(
              data['remote_revision']!, _remoteRevisionMeta));
    }
    if (data.containsKey('completed_at_micros')) {
      context.handle(
          _completedAtMicrosMeta,
          completedAtMicros.isAcceptableOrUnknown(
              data['completed_at_micros']!, _completedAtMicrosMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RemoteCollectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteCollectionRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}account_id'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      externalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}external_id'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title']),
      isSelected: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_selected'])!,
      revision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}revision'])!,
      itemCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}item_count'])!,
      remoteRevision: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}remote_revision']),
      completedAtMicros: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}completed_at_micros']),
    );
  }

  @override
  $RemoteCollectionsTable createAlias(String alias) {
    return $RemoteCollectionsTable(attachedDatabase, alias);
  }
}

class RemoteCollectionRow extends DataClass
    implements Insertable<RemoteCollectionRow> {
  final int id;
  final int accountId;
  final String kind;
  final String externalId;
  final String ownerId;
  final String? title;
  final bool isSelected;
  final int revision;
  final int itemCount;
  final String? remoteRevision;
  final int? completedAtMicros;
  const RemoteCollectionRow(
      {required this.id,
      required this.accountId,
      required this.kind,
      required this.externalId,
      required this.ownerId,
      this.title,
      required this.isSelected,
      required this.revision,
      required this.itemCount,
      this.remoteRevision,
      this.completedAtMicros});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_id'] = Variable<int>(accountId);
    map['kind'] = Variable<String>(kind);
    map['external_id'] = Variable<String>(externalId);
    map['owner_id'] = Variable<String>(ownerId);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['is_selected'] = Variable<bool>(isSelected);
    map['revision'] = Variable<int>(revision);
    map['item_count'] = Variable<int>(itemCount);
    if (!nullToAbsent || remoteRevision != null) {
      map['remote_revision'] = Variable<String>(remoteRevision);
    }
    if (!nullToAbsent || completedAtMicros != null) {
      map['completed_at_micros'] = Variable<int>(completedAtMicros);
    }
    return map;
  }

  RemoteCollectionsCompanion toCompanion(bool nullToAbsent) {
    return RemoteCollectionsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      kind: Value(kind),
      externalId: Value(externalId),
      ownerId: Value(ownerId),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      isSelected: Value(isSelected),
      revision: Value(revision),
      itemCount: Value(itemCount),
      remoteRevision: remoteRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteRevision),
      completedAtMicros: completedAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtMicros),
    );
  }

  factory RemoteCollectionRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteCollectionRow(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<int>(json['accountId']),
      kind: serializer.fromJson<String>(json['kind']),
      externalId: serializer.fromJson<String>(json['externalId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      title: serializer.fromJson<String?>(json['title']),
      isSelected: serializer.fromJson<bool>(json['isSelected']),
      revision: serializer.fromJson<int>(json['revision']),
      itemCount: serializer.fromJson<int>(json['itemCount']),
      remoteRevision: serializer.fromJson<String?>(json['remoteRevision']),
      completedAtMicros: serializer.fromJson<int?>(json['completedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountId': serializer.toJson<int>(accountId),
      'kind': serializer.toJson<String>(kind),
      'externalId': serializer.toJson<String>(externalId),
      'ownerId': serializer.toJson<String>(ownerId),
      'title': serializer.toJson<String?>(title),
      'isSelected': serializer.toJson<bool>(isSelected),
      'revision': serializer.toJson<int>(revision),
      'itemCount': serializer.toJson<int>(itemCount),
      'remoteRevision': serializer.toJson<String?>(remoteRevision),
      'completedAtMicros': serializer.toJson<int?>(completedAtMicros),
    };
  }

  RemoteCollectionRow copyWith(
          {int? id,
          int? accountId,
          String? kind,
          String? externalId,
          String? ownerId,
          Value<String?> title = const Value.absent(),
          bool? isSelected,
          int? revision,
          int? itemCount,
          Value<String?> remoteRevision = const Value.absent(),
          Value<int?> completedAtMicros = const Value.absent()}) =>
      RemoteCollectionRow(
        id: id ?? this.id,
        accountId: accountId ?? this.accountId,
        kind: kind ?? this.kind,
        externalId: externalId ?? this.externalId,
        ownerId: ownerId ?? this.ownerId,
        title: title.present ? title.value : this.title,
        isSelected: isSelected ?? this.isSelected,
        revision: revision ?? this.revision,
        itemCount: itemCount ?? this.itemCount,
        remoteRevision:
            remoteRevision.present ? remoteRevision.value : this.remoteRevision,
        completedAtMicros: completedAtMicros.present
            ? completedAtMicros.value
            : this.completedAtMicros,
      );
  RemoteCollectionRow copyWithCompanion(RemoteCollectionsCompanion data) {
    return RemoteCollectionRow(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      kind: data.kind.present ? data.kind.value : this.kind,
      externalId:
          data.externalId.present ? data.externalId.value : this.externalId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      title: data.title.present ? data.title.value : this.title,
      isSelected:
          data.isSelected.present ? data.isSelected.value : this.isSelected,
      revision: data.revision.present ? data.revision.value : this.revision,
      itemCount: data.itemCount.present ? data.itemCount.value : this.itemCount,
      remoteRevision: data.remoteRevision.present
          ? data.remoteRevision.value
          : this.remoteRevision,
      completedAtMicros: data.completedAtMicros.present
          ? data.completedAtMicros.value
          : this.completedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteCollectionRow(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('kind: $kind, ')
          ..write('externalId: $externalId, ')
          ..write('ownerId: $ownerId, ')
          ..write('title: $title, ')
          ..write('isSelected: $isSelected, ')
          ..write('revision: $revision, ')
          ..write('itemCount: $itemCount, ')
          ..write('remoteRevision: $remoteRevision, ')
          ..write('completedAtMicros: $completedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      accountId,
      kind,
      externalId,
      ownerId,
      title,
      isSelected,
      revision,
      itemCount,
      remoteRevision,
      completedAtMicros);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteCollectionRow &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.kind == this.kind &&
          other.externalId == this.externalId &&
          other.ownerId == this.ownerId &&
          other.title == this.title &&
          other.isSelected == this.isSelected &&
          other.revision == this.revision &&
          other.itemCount == this.itemCount &&
          other.remoteRevision == this.remoteRevision &&
          other.completedAtMicros == this.completedAtMicros);
}

class RemoteCollectionsCompanion extends UpdateCompanion<RemoteCollectionRow> {
  final Value<int> id;
  final Value<int> accountId;
  final Value<String> kind;
  final Value<String> externalId;
  final Value<String> ownerId;
  final Value<String?> title;
  final Value<bool> isSelected;
  final Value<int> revision;
  final Value<int> itemCount;
  final Value<String?> remoteRevision;
  final Value<int?> completedAtMicros;
  const RemoteCollectionsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.kind = const Value.absent(),
    this.externalId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.title = const Value.absent(),
    this.isSelected = const Value.absent(),
    this.revision = const Value.absent(),
    this.itemCount = const Value.absent(),
    this.remoteRevision = const Value.absent(),
    this.completedAtMicros = const Value.absent(),
  });
  RemoteCollectionsCompanion.insert({
    this.id = const Value.absent(),
    required int accountId,
    required String kind,
    required String externalId,
    required String ownerId,
    this.title = const Value.absent(),
    required bool isSelected,
    required int revision,
    this.itemCount = const Value.absent(),
    this.remoteRevision = const Value.absent(),
    this.completedAtMicros = const Value.absent(),
  })  : accountId = Value(accountId),
        kind = Value(kind),
        externalId = Value(externalId),
        ownerId = Value(ownerId),
        isSelected = Value(isSelected),
        revision = Value(revision);
  static Insertable<RemoteCollectionRow> custom({
    Expression<int>? id,
    Expression<int>? accountId,
    Expression<String>? kind,
    Expression<String>? externalId,
    Expression<String>? ownerId,
    Expression<String>? title,
    Expression<bool>? isSelected,
    Expression<int>? revision,
    Expression<int>? itemCount,
    Expression<String>? remoteRevision,
    Expression<int>? completedAtMicros,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (kind != null) 'kind': kind,
      if (externalId != null) 'external_id': externalId,
      if (ownerId != null) 'owner_id': ownerId,
      if (title != null) 'title': title,
      if (isSelected != null) 'is_selected': isSelected,
      if (revision != null) 'revision': revision,
      if (itemCount != null) 'item_count': itemCount,
      if (remoteRevision != null) 'remote_revision': remoteRevision,
      if (completedAtMicros != null) 'completed_at_micros': completedAtMicros,
    });
  }

  RemoteCollectionsCompanion copyWith(
      {Value<int>? id,
      Value<int>? accountId,
      Value<String>? kind,
      Value<String>? externalId,
      Value<String>? ownerId,
      Value<String?>? title,
      Value<bool>? isSelected,
      Value<int>? revision,
      Value<int>? itemCount,
      Value<String?>? remoteRevision,
      Value<int?>? completedAtMicros}) {
    return RemoteCollectionsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      kind: kind ?? this.kind,
      externalId: externalId ?? this.externalId,
      ownerId: ownerId ?? this.ownerId,
      title: title ?? this.title,
      isSelected: isSelected ?? this.isSelected,
      revision: revision ?? this.revision,
      itemCount: itemCount ?? this.itemCount,
      remoteRevision: remoteRevision ?? this.remoteRevision,
      completedAtMicros: completedAtMicros ?? this.completedAtMicros,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (isSelected.present) {
      map['is_selected'] = Variable<bool>(isSelected.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (itemCount.present) {
      map['item_count'] = Variable<int>(itemCount.value);
    }
    if (remoteRevision.present) {
      map['remote_revision'] = Variable<String>(remoteRevision.value);
    }
    if (completedAtMicros.present) {
      map['completed_at_micros'] = Variable<int>(completedAtMicros.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteCollectionsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('kind: $kind, ')
          ..write('externalId: $externalId, ')
          ..write('ownerId: $ownerId, ')
          ..write('title: $title, ')
          ..write('isSelected: $isSelected, ')
          ..write('revision: $revision, ')
          ..write('itemCount: $itemCount, ')
          ..write('remoteRevision: $remoteRevision, ')
          ..write('completedAtMicros: $completedAtMicros')
          ..write(')'))
        .toString();
  }
}

class $RemoteCollectionItemsTable extends RemoteCollectionItems
    with TableInfo<$RemoteCollectionItemsTable, RemoteCollectionItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteCollectionItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _collectionIdMeta =
      const VerificationMeta('collectionId');
  @override
  late final GeneratedColumn<int> collectionId = GeneratedColumn<int>(
      'collection_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES remote_collections (id) ON DELETE CASCADE'));
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _externalIdMeta =
      const VerificationMeta('externalId');
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
      'external_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _variantKeyMeta =
      const VerificationMeta('variantKey');
  @override
  late final GeneratedColumn<String> variantKey = GeneratedColumn<String>(
      'variant_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [collectionId, position, externalId, variantKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_collection_items';
  @override
  VerificationContext validateIntegrity(
      Insertable<RemoteCollectionItemRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('collection_id')) {
      context.handle(
          _collectionIdMeta,
          collectionId.isAcceptableOrUnknown(
              data['collection_id']!, _collectionIdMeta));
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('external_id')) {
      context.handle(
          _externalIdMeta,
          externalId.isAcceptableOrUnknown(
              data['external_id']!, _externalIdMeta));
    } else if (isInserting) {
      context.missing(_externalIdMeta);
    }
    if (data.containsKey('variant_key')) {
      context.handle(
          _variantKeyMeta,
          variantKey.isAcceptableOrUnknown(
              data['variant_key']!, _variantKeyMeta));
    } else if (isInserting) {
      context.missing(_variantKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {collectionId, position};
  @override
  RemoteCollectionItemRow map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteCollectionItemRow(
      collectionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}collection_id'])!,
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
      externalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}external_id'])!,
      variantKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}variant_key'])!,
    );
  }

  @override
  $RemoteCollectionItemsTable createAlias(String alias) {
    return $RemoteCollectionItemsTable(attachedDatabase, alias);
  }
}

class RemoteCollectionItemRow extends DataClass
    implements Insertable<RemoteCollectionItemRow> {
  final int collectionId;
  final int position;
  final String externalId;
  final String variantKey;
  const RemoteCollectionItemRow(
      {required this.collectionId,
      required this.position,
      required this.externalId,
      required this.variantKey});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['collection_id'] = Variable<int>(collectionId);
    map['position'] = Variable<int>(position);
    map['external_id'] = Variable<String>(externalId);
    map['variant_key'] = Variable<String>(variantKey);
    return map;
  }

  RemoteCollectionItemsCompanion toCompanion(bool nullToAbsent) {
    return RemoteCollectionItemsCompanion(
      collectionId: Value(collectionId),
      position: Value(position),
      externalId: Value(externalId),
      variantKey: Value(variantKey),
    );
  }

  factory RemoteCollectionItemRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteCollectionItemRow(
      collectionId: serializer.fromJson<int>(json['collectionId']),
      position: serializer.fromJson<int>(json['position']),
      externalId: serializer.fromJson<String>(json['externalId']),
      variantKey: serializer.fromJson<String>(json['variantKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'collectionId': serializer.toJson<int>(collectionId),
      'position': serializer.toJson<int>(position),
      'externalId': serializer.toJson<String>(externalId),
      'variantKey': serializer.toJson<String>(variantKey),
    };
  }

  RemoteCollectionItemRow copyWith(
          {int? collectionId,
          int? position,
          String? externalId,
          String? variantKey}) =>
      RemoteCollectionItemRow(
        collectionId: collectionId ?? this.collectionId,
        position: position ?? this.position,
        externalId: externalId ?? this.externalId,
        variantKey: variantKey ?? this.variantKey,
      );
  RemoteCollectionItemRow copyWithCompanion(
      RemoteCollectionItemsCompanion data) {
    return RemoteCollectionItemRow(
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      position: data.position.present ? data.position.value : this.position,
      externalId:
          data.externalId.present ? data.externalId.value : this.externalId,
      variantKey:
          data.variantKey.present ? data.variantKey.value : this.variantKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteCollectionItemRow(')
          ..write('collectionId: $collectionId, ')
          ..write('position: $position, ')
          ..write('externalId: $externalId, ')
          ..write('variantKey: $variantKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(collectionId, position, externalId, variantKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteCollectionItemRow &&
          other.collectionId == this.collectionId &&
          other.position == this.position &&
          other.externalId == this.externalId &&
          other.variantKey == this.variantKey);
}

class RemoteCollectionItemsCompanion
    extends UpdateCompanion<RemoteCollectionItemRow> {
  final Value<int> collectionId;
  final Value<int> position;
  final Value<String> externalId;
  final Value<String> variantKey;
  final Value<int> rowid;
  const RemoteCollectionItemsCompanion({
    this.collectionId = const Value.absent(),
    this.position = const Value.absent(),
    this.externalId = const Value.absent(),
    this.variantKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteCollectionItemsCompanion.insert({
    required int collectionId,
    required int position,
    required String externalId,
    required String variantKey,
    this.rowid = const Value.absent(),
  })  : collectionId = Value(collectionId),
        position = Value(position),
        externalId = Value(externalId),
        variantKey = Value(variantKey);
  static Insertable<RemoteCollectionItemRow> custom({
    Expression<int>? collectionId,
    Expression<int>? position,
    Expression<String>? externalId,
    Expression<String>? variantKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (collectionId != null) 'collection_id': collectionId,
      if (position != null) 'position': position,
      if (externalId != null) 'external_id': externalId,
      if (variantKey != null) 'variant_key': variantKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteCollectionItemsCompanion copyWith(
      {Value<int>? collectionId,
      Value<int>? position,
      Value<String>? externalId,
      Value<String>? variantKey,
      Value<int>? rowid}) {
    return RemoteCollectionItemsCompanion(
      collectionId: collectionId ?? this.collectionId,
      position: position ?? this.position,
      externalId: externalId ?? this.externalId,
      variantKey: variantKey ?? this.variantKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (collectionId.present) {
      map['collection_id'] = Variable<int>(collectionId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (variantKey.present) {
      map['variant_key'] = Variable<String>(variantKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteCollectionItemsCompanion(')
          ..write('collectionId: $collectionId, ')
          ..write('position: $position, ')
          ..write('externalId: $externalId, ')
          ..write('variantKey: $variantKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadJobsTable extends DownloadJobs
    with TableInfo<$DownloadJobsTable, DownloadJobRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadJobsTable(this.attachedDatabase, [this._alias]);
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
      'library_folder_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES library_folders (id) ON DELETE CASCADE'));
  static const VerificationMeta _providerMeta =
      const VerificationMeta('provider');
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
      'provider', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _externalIdMeta =
      const VerificationMeta('externalId');
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
      'external_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _variantKeyMeta =
      const VerificationMeta('variantKey');
  @override
  late final GeneratedColumn<String> variantKey = GeneratedColumn<String>(
      'variant_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _qualityMeta =
      const VerificationMeta('quality');
  @override
  late final GeneratedColumn<String> quality = GeneratedColumn<String>(
      'quality', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
      'account_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES remote_accounts (id) ON DELETE CASCADE'));
  static const VerificationMeta _accountRevisionMeta =
      const VerificationMeta('accountRevision');
  @override
  late final GeneratedColumn<int> accountRevision = GeneratedColumn<int>(
      'account_revision', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
      'stage', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _revisionMeta =
      const VerificationMeta('revision');
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
      'revision', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _attemptCountMeta =
      const VerificationMeta('attemptCount');
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
      'attempt_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _maxAttemptsMeta =
      const VerificationMeta('maxAttempts');
  @override
  late final GeneratedColumn<int> maxAttempts = GeneratedColumn<int>(
      'max_attempts', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _remainingAttemptsMeta =
      const VerificationMeta('remainingAttempts');
  @override
  late final GeneratedColumn<int> remainingAttempts = GeneratedColumn<int>(
      'remaining_attempts', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _attemptTokenMeta =
      const VerificationMeta('attemptToken');
  @override
  late final GeneratedColumn<String> attemptToken = GeneratedColumn<String>(
      'attempt_token', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _leaseUntilMicrosMeta =
      const VerificationMeta('leaseUntilMicros');
  @override
  late final GeneratedColumn<int> leaseUntilMicros = GeneratedColumn<int>(
      'lease_until_micros', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _retryAtMicrosMeta =
      const VerificationMeta('retryAtMicros');
  @override
  late final GeneratedColumn<int> retryAtMicros = GeneratedColumn<int>(
      'retry_at_micros', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _failureMeta =
      const VerificationMeta('failure');
  @override
  late final GeneratedColumn<String> failure = GeneratedColumn<String>(
      'failure', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _completedTrackIdMeta =
      const VerificationMeta('completedTrackId');
  @override
  late final GeneratedColumn<int> completedTrackId = GeneratedColumn<int>(
      'completed_track_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMicrosMeta =
      const VerificationMeta('createdAtMicros');
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
      'created_at_micros', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMicrosMeta =
      const VerificationMeta('updatedAtMicros');
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
      'updated_at_micros', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        libraryFolderId,
        provider,
        externalId,
        variantKey,
        quality,
        accountId,
        accountRevision,
        state,
        stage,
        revision,
        attemptCount,
        maxAttempts,
        remainingAttempts,
        attemptToken,
        leaseUntilMicros,
        retryAtMicros,
        failure,
        completedTrackId,
        createdAtMicros,
        updatedAtMicros
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_jobs';
  @override
  VerificationContext validateIntegrity(Insertable<DownloadJobRow> instance,
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
    } else if (isInserting) {
      context.missing(_libraryFolderIdMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(_providerMeta,
          provider.isAcceptableOrUnknown(data['provider']!, _providerMeta));
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('external_id')) {
      context.handle(
          _externalIdMeta,
          externalId.isAcceptableOrUnknown(
              data['external_id']!, _externalIdMeta));
    } else if (isInserting) {
      context.missing(_externalIdMeta);
    }
    if (data.containsKey('variant_key')) {
      context.handle(
          _variantKeyMeta,
          variantKey.isAcceptableOrUnknown(
              data['variant_key']!, _variantKeyMeta));
    } else if (isInserting) {
      context.missing(_variantKeyMeta);
    }
    if (data.containsKey('quality')) {
      context.handle(_qualityMeta,
          quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta));
    } else if (isInserting) {
      context.missing(_qualityMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('account_revision')) {
      context.handle(
          _accountRevisionMeta,
          accountRevision.isAcceptableOrUnknown(
              data['account_revision']!, _accountRevisionMeta));
    } else if (isInserting) {
      context.missing(_accountRevisionMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('stage')) {
      context.handle(
          _stageMeta, stage.isAcceptableOrUnknown(data['stage']!, _stageMeta));
    } else if (isInserting) {
      context.missing(_stageMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(_revisionMeta,
          revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta));
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
          _attemptCountMeta,
          attemptCount.isAcceptableOrUnknown(
              data['attempt_count']!, _attemptCountMeta));
    }
    if (data.containsKey('max_attempts')) {
      context.handle(
          _maxAttemptsMeta,
          maxAttempts.isAcceptableOrUnknown(
              data['max_attempts']!, _maxAttemptsMeta));
    } else if (isInserting) {
      context.missing(_maxAttemptsMeta);
    }
    if (data.containsKey('remaining_attempts')) {
      context.handle(
          _remainingAttemptsMeta,
          remainingAttempts.isAcceptableOrUnknown(
              data['remaining_attempts']!, _remainingAttemptsMeta));
    } else if (isInserting) {
      context.missing(_remainingAttemptsMeta);
    }
    if (data.containsKey('attempt_token')) {
      context.handle(
          _attemptTokenMeta,
          attemptToken.isAcceptableOrUnknown(
              data['attempt_token']!, _attemptTokenMeta));
    }
    if (data.containsKey('lease_until_micros')) {
      context.handle(
          _leaseUntilMicrosMeta,
          leaseUntilMicros.isAcceptableOrUnknown(
              data['lease_until_micros']!, _leaseUntilMicrosMeta));
    }
    if (data.containsKey('retry_at_micros')) {
      context.handle(
          _retryAtMicrosMeta,
          retryAtMicros.isAcceptableOrUnknown(
              data['retry_at_micros']!, _retryAtMicrosMeta));
    }
    if (data.containsKey('failure')) {
      context.handle(_failureMeta,
          failure.isAcceptableOrUnknown(data['failure']!, _failureMeta));
    }
    if (data.containsKey('completed_track_id')) {
      context.handle(
          _completedTrackIdMeta,
          completedTrackId.isAcceptableOrUnknown(
              data['completed_track_id']!, _completedTrackIdMeta));
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
          _createdAtMicrosMeta,
          createdAtMicros.isAcceptableOrUnknown(
              data['created_at_micros']!, _createdAtMicrosMeta));
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
          _updatedAtMicrosMeta,
          updatedAtMicros.isAcceptableOrUnknown(
              data['updated_at_micros']!, _updatedAtMicrosMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DownloadJobRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadJobRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      libraryFolderId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}library_folder_id'])!,
      provider: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}provider'])!,
      externalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}external_id'])!,
      variantKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}variant_key'])!,
      quality: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}quality'])!,
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}account_id'])!,
      accountRevision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}account_revision'])!,
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      stage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}stage'])!,
      revision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}revision'])!,
      attemptCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempt_count'])!,
      maxAttempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}max_attempts'])!,
      remainingAttempts: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}remaining_attempts'])!,
      attemptToken: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}attempt_token']),
      leaseUntilMicros: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}lease_until_micros']),
      retryAtMicros: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_at_micros']),
      failure: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}failure']),
      completedTrackId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}completed_track_id']),
      createdAtMicros: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at_micros'])!,
      updatedAtMicros: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at_micros'])!,
    );
  }

  @override
  $DownloadJobsTable createAlias(String alias) {
    return $DownloadJobsTable(attachedDatabase, alias);
  }
}

class DownloadJobRow extends DataClass implements Insertable<DownloadJobRow> {
  final int id;
  final int libraryFolderId;
  final String provider;
  final String externalId;
  final String variantKey;
  final String quality;
  final int accountId;
  final int accountRevision;
  final String state;
  final String stage;
  final int revision;
  final int attemptCount;
  final int maxAttempts;
  final int remainingAttempts;
  final String? attemptToken;
  final int? leaseUntilMicros;
  final int? retryAtMicros;
  final String? failure;
  final int? completedTrackId;
  final int createdAtMicros;
  final int updatedAtMicros;
  const DownloadJobRow(
      {required this.id,
      required this.libraryFolderId,
      required this.provider,
      required this.externalId,
      required this.variantKey,
      required this.quality,
      required this.accountId,
      required this.accountRevision,
      required this.state,
      required this.stage,
      required this.revision,
      required this.attemptCount,
      required this.maxAttempts,
      required this.remainingAttempts,
      this.attemptToken,
      this.leaseUntilMicros,
      this.retryAtMicros,
      this.failure,
      this.completedTrackId,
      required this.createdAtMicros,
      required this.updatedAtMicros});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['library_folder_id'] = Variable<int>(libraryFolderId);
    map['provider'] = Variable<String>(provider);
    map['external_id'] = Variable<String>(externalId);
    map['variant_key'] = Variable<String>(variantKey);
    map['quality'] = Variable<String>(quality);
    map['account_id'] = Variable<int>(accountId);
    map['account_revision'] = Variable<int>(accountRevision);
    map['state'] = Variable<String>(state);
    map['stage'] = Variable<String>(stage);
    map['revision'] = Variable<int>(revision);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['max_attempts'] = Variable<int>(maxAttempts);
    map['remaining_attempts'] = Variable<int>(remainingAttempts);
    if (!nullToAbsent || attemptToken != null) {
      map['attempt_token'] = Variable<String>(attemptToken);
    }
    if (!nullToAbsent || leaseUntilMicros != null) {
      map['lease_until_micros'] = Variable<int>(leaseUntilMicros);
    }
    if (!nullToAbsent || retryAtMicros != null) {
      map['retry_at_micros'] = Variable<int>(retryAtMicros);
    }
    if (!nullToAbsent || failure != null) {
      map['failure'] = Variable<String>(failure);
    }
    if (!nullToAbsent || completedTrackId != null) {
      map['completed_track_id'] = Variable<int>(completedTrackId);
    }
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  DownloadJobsCompanion toCompanion(bool nullToAbsent) {
    return DownloadJobsCompanion(
      id: Value(id),
      libraryFolderId: Value(libraryFolderId),
      provider: Value(provider),
      externalId: Value(externalId),
      variantKey: Value(variantKey),
      quality: Value(quality),
      accountId: Value(accountId),
      accountRevision: Value(accountRevision),
      state: Value(state),
      stage: Value(stage),
      revision: Value(revision),
      attemptCount: Value(attemptCount),
      maxAttempts: Value(maxAttempts),
      remainingAttempts: Value(remainingAttempts),
      attemptToken: attemptToken == null && nullToAbsent
          ? const Value.absent()
          : Value(attemptToken),
      leaseUntilMicros: leaseUntilMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseUntilMicros),
      retryAtMicros: retryAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(retryAtMicros),
      failure: failure == null && nullToAbsent
          ? const Value.absent()
          : Value(failure),
      completedTrackId: completedTrackId == null && nullToAbsent
          ? const Value.absent()
          : Value(completedTrackId),
      createdAtMicros: Value(createdAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory DownloadJobRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadJobRow(
      id: serializer.fromJson<int>(json['id']),
      libraryFolderId: serializer.fromJson<int>(json['libraryFolderId']),
      provider: serializer.fromJson<String>(json['provider']),
      externalId: serializer.fromJson<String>(json['externalId']),
      variantKey: serializer.fromJson<String>(json['variantKey']),
      quality: serializer.fromJson<String>(json['quality']),
      accountId: serializer.fromJson<int>(json['accountId']),
      accountRevision: serializer.fromJson<int>(json['accountRevision']),
      state: serializer.fromJson<String>(json['state']),
      stage: serializer.fromJson<String>(json['stage']),
      revision: serializer.fromJson<int>(json['revision']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      maxAttempts: serializer.fromJson<int>(json['maxAttempts']),
      remainingAttempts: serializer.fromJson<int>(json['remainingAttempts']),
      attemptToken: serializer.fromJson<String?>(json['attemptToken']),
      leaseUntilMicros: serializer.fromJson<int?>(json['leaseUntilMicros']),
      retryAtMicros: serializer.fromJson<int?>(json['retryAtMicros']),
      failure: serializer.fromJson<String?>(json['failure']),
      completedTrackId: serializer.fromJson<int?>(json['completedTrackId']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'libraryFolderId': serializer.toJson<int>(libraryFolderId),
      'provider': serializer.toJson<String>(provider),
      'externalId': serializer.toJson<String>(externalId),
      'variantKey': serializer.toJson<String>(variantKey),
      'quality': serializer.toJson<String>(quality),
      'accountId': serializer.toJson<int>(accountId),
      'accountRevision': serializer.toJson<int>(accountRevision),
      'state': serializer.toJson<String>(state),
      'stage': serializer.toJson<String>(stage),
      'revision': serializer.toJson<int>(revision),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'maxAttempts': serializer.toJson<int>(maxAttempts),
      'remainingAttempts': serializer.toJson<int>(remainingAttempts),
      'attemptToken': serializer.toJson<String?>(attemptToken),
      'leaseUntilMicros': serializer.toJson<int?>(leaseUntilMicros),
      'retryAtMicros': serializer.toJson<int?>(retryAtMicros),
      'failure': serializer.toJson<String?>(failure),
      'completedTrackId': serializer.toJson<int?>(completedTrackId),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  DownloadJobRow copyWith(
          {int? id,
          int? libraryFolderId,
          String? provider,
          String? externalId,
          String? variantKey,
          String? quality,
          int? accountId,
          int? accountRevision,
          String? state,
          String? stage,
          int? revision,
          int? attemptCount,
          int? maxAttempts,
          int? remainingAttempts,
          Value<String?> attemptToken = const Value.absent(),
          Value<int?> leaseUntilMicros = const Value.absent(),
          Value<int?> retryAtMicros = const Value.absent(),
          Value<String?> failure = const Value.absent(),
          Value<int?> completedTrackId = const Value.absent(),
          int? createdAtMicros,
          int? updatedAtMicros}) =>
      DownloadJobRow(
        id: id ?? this.id,
        libraryFolderId: libraryFolderId ?? this.libraryFolderId,
        provider: provider ?? this.provider,
        externalId: externalId ?? this.externalId,
        variantKey: variantKey ?? this.variantKey,
        quality: quality ?? this.quality,
        accountId: accountId ?? this.accountId,
        accountRevision: accountRevision ?? this.accountRevision,
        state: state ?? this.state,
        stage: stage ?? this.stage,
        revision: revision ?? this.revision,
        attemptCount: attemptCount ?? this.attemptCount,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        remainingAttempts: remainingAttempts ?? this.remainingAttempts,
        attemptToken:
            attemptToken.present ? attemptToken.value : this.attemptToken,
        leaseUntilMicros: leaseUntilMicros.present
            ? leaseUntilMicros.value
            : this.leaseUntilMicros,
        retryAtMicros:
            retryAtMicros.present ? retryAtMicros.value : this.retryAtMicros,
        failure: failure.present ? failure.value : this.failure,
        completedTrackId: completedTrackId.present
            ? completedTrackId.value
            : this.completedTrackId,
        createdAtMicros: createdAtMicros ?? this.createdAtMicros,
        updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      );
  DownloadJobRow copyWithCompanion(DownloadJobsCompanion data) {
    return DownloadJobRow(
      id: data.id.present ? data.id.value : this.id,
      libraryFolderId: data.libraryFolderId.present
          ? data.libraryFolderId.value
          : this.libraryFolderId,
      provider: data.provider.present ? data.provider.value : this.provider,
      externalId:
          data.externalId.present ? data.externalId.value : this.externalId,
      variantKey:
          data.variantKey.present ? data.variantKey.value : this.variantKey,
      quality: data.quality.present ? data.quality.value : this.quality,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      accountRevision: data.accountRevision.present
          ? data.accountRevision.value
          : this.accountRevision,
      state: data.state.present ? data.state.value : this.state,
      stage: data.stage.present ? data.stage.value : this.stage,
      revision: data.revision.present ? data.revision.value : this.revision,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      maxAttempts:
          data.maxAttempts.present ? data.maxAttempts.value : this.maxAttempts,
      remainingAttempts: data.remainingAttempts.present
          ? data.remainingAttempts.value
          : this.remainingAttempts,
      attemptToken: data.attemptToken.present
          ? data.attemptToken.value
          : this.attemptToken,
      leaseUntilMicros: data.leaseUntilMicros.present
          ? data.leaseUntilMicros.value
          : this.leaseUntilMicros,
      retryAtMicros: data.retryAtMicros.present
          ? data.retryAtMicros.value
          : this.retryAtMicros,
      failure: data.failure.present ? data.failure.value : this.failure,
      completedTrackId: data.completedTrackId.present
          ? data.completedTrackId.value
          : this.completedTrackId,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadJobRow(')
          ..write('id: $id, ')
          ..write('libraryFolderId: $libraryFolderId, ')
          ..write('provider: $provider, ')
          ..write('externalId: $externalId, ')
          ..write('variantKey: $variantKey, ')
          ..write('quality: $quality, ')
          ..write('accountId: $accountId, ')
          ..write('accountRevision: $accountRevision, ')
          ..write('state: $state, ')
          ..write('stage: $stage, ')
          ..write('revision: $revision, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('maxAttempts: $maxAttempts, ')
          ..write('remainingAttempts: $remainingAttempts, ')
          ..write('attemptToken: $attemptToken, ')
          ..write('leaseUntilMicros: $leaseUntilMicros, ')
          ..write('retryAtMicros: $retryAtMicros, ')
          ..write('failure: $failure, ')
          ..write('completedTrackId: $completedTrackId, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        libraryFolderId,
        provider,
        externalId,
        variantKey,
        quality,
        accountId,
        accountRevision,
        state,
        stage,
        revision,
        attemptCount,
        maxAttempts,
        remainingAttempts,
        attemptToken,
        leaseUntilMicros,
        retryAtMicros,
        failure,
        completedTrackId,
        createdAtMicros,
        updatedAtMicros
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadJobRow &&
          other.id == this.id &&
          other.libraryFolderId == this.libraryFolderId &&
          other.provider == this.provider &&
          other.externalId == this.externalId &&
          other.variantKey == this.variantKey &&
          other.quality == this.quality &&
          other.accountId == this.accountId &&
          other.accountRevision == this.accountRevision &&
          other.state == this.state &&
          other.stage == this.stage &&
          other.revision == this.revision &&
          other.attemptCount == this.attemptCount &&
          other.maxAttempts == this.maxAttempts &&
          other.remainingAttempts == this.remainingAttempts &&
          other.attemptToken == this.attemptToken &&
          other.leaseUntilMicros == this.leaseUntilMicros &&
          other.retryAtMicros == this.retryAtMicros &&
          other.failure == this.failure &&
          other.completedTrackId == this.completedTrackId &&
          other.createdAtMicros == this.createdAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class DownloadJobsCompanion extends UpdateCompanion<DownloadJobRow> {
  final Value<int> id;
  final Value<int> libraryFolderId;
  final Value<String> provider;
  final Value<String> externalId;
  final Value<String> variantKey;
  final Value<String> quality;
  final Value<int> accountId;
  final Value<int> accountRevision;
  final Value<String> state;
  final Value<String> stage;
  final Value<int> revision;
  final Value<int> attemptCount;
  final Value<int> maxAttempts;
  final Value<int> remainingAttempts;
  final Value<String?> attemptToken;
  final Value<int?> leaseUntilMicros;
  final Value<int?> retryAtMicros;
  final Value<String?> failure;
  final Value<int?> completedTrackId;
  final Value<int> createdAtMicros;
  final Value<int> updatedAtMicros;
  const DownloadJobsCompanion({
    this.id = const Value.absent(),
    this.libraryFolderId = const Value.absent(),
    this.provider = const Value.absent(),
    this.externalId = const Value.absent(),
    this.variantKey = const Value.absent(),
    this.quality = const Value.absent(),
    this.accountId = const Value.absent(),
    this.accountRevision = const Value.absent(),
    this.state = const Value.absent(),
    this.stage = const Value.absent(),
    this.revision = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.maxAttempts = const Value.absent(),
    this.remainingAttempts = const Value.absent(),
    this.attemptToken = const Value.absent(),
    this.leaseUntilMicros = const Value.absent(),
    this.retryAtMicros = const Value.absent(),
    this.failure = const Value.absent(),
    this.completedTrackId = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
  });
  DownloadJobsCompanion.insert({
    this.id = const Value.absent(),
    required int libraryFolderId,
    required String provider,
    required String externalId,
    required String variantKey,
    required String quality,
    required int accountId,
    required int accountRevision,
    required String state,
    required String stage,
    required int revision,
    this.attemptCount = const Value.absent(),
    required int maxAttempts,
    required int remainingAttempts,
    this.attemptToken = const Value.absent(),
    this.leaseUntilMicros = const Value.absent(),
    this.retryAtMicros = const Value.absent(),
    this.failure = const Value.absent(),
    this.completedTrackId = const Value.absent(),
    required int createdAtMicros,
    required int updatedAtMicros,
  })  : libraryFolderId = Value(libraryFolderId),
        provider = Value(provider),
        externalId = Value(externalId),
        variantKey = Value(variantKey),
        quality = Value(quality),
        accountId = Value(accountId),
        accountRevision = Value(accountRevision),
        state = Value(state),
        stage = Value(stage),
        revision = Value(revision),
        maxAttempts = Value(maxAttempts),
        remainingAttempts = Value(remainingAttempts),
        createdAtMicros = Value(createdAtMicros),
        updatedAtMicros = Value(updatedAtMicros);
  static Insertable<DownloadJobRow> custom({
    Expression<int>? id,
    Expression<int>? libraryFolderId,
    Expression<String>? provider,
    Expression<String>? externalId,
    Expression<String>? variantKey,
    Expression<String>? quality,
    Expression<int>? accountId,
    Expression<int>? accountRevision,
    Expression<String>? state,
    Expression<String>? stage,
    Expression<int>? revision,
    Expression<int>? attemptCount,
    Expression<int>? maxAttempts,
    Expression<int>? remainingAttempts,
    Expression<String>? attemptToken,
    Expression<int>? leaseUntilMicros,
    Expression<int>? retryAtMicros,
    Expression<String>? failure,
    Expression<int>? completedTrackId,
    Expression<int>? createdAtMicros,
    Expression<int>? updatedAtMicros,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (libraryFolderId != null) 'library_folder_id': libraryFolderId,
      if (provider != null) 'provider': provider,
      if (externalId != null) 'external_id': externalId,
      if (variantKey != null) 'variant_key': variantKey,
      if (quality != null) 'quality': quality,
      if (accountId != null) 'account_id': accountId,
      if (accountRevision != null) 'account_revision': accountRevision,
      if (state != null) 'state': state,
      if (stage != null) 'stage': stage,
      if (revision != null) 'revision': revision,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (maxAttempts != null) 'max_attempts': maxAttempts,
      if (remainingAttempts != null) 'remaining_attempts': remainingAttempts,
      if (attemptToken != null) 'attempt_token': attemptToken,
      if (leaseUntilMicros != null) 'lease_until_micros': leaseUntilMicros,
      if (retryAtMicros != null) 'retry_at_micros': retryAtMicros,
      if (failure != null) 'failure': failure,
      if (completedTrackId != null) 'completed_track_id': completedTrackId,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
    });
  }

  DownloadJobsCompanion copyWith(
      {Value<int>? id,
      Value<int>? libraryFolderId,
      Value<String>? provider,
      Value<String>? externalId,
      Value<String>? variantKey,
      Value<String>? quality,
      Value<int>? accountId,
      Value<int>? accountRevision,
      Value<String>? state,
      Value<String>? stage,
      Value<int>? revision,
      Value<int>? attemptCount,
      Value<int>? maxAttempts,
      Value<int>? remainingAttempts,
      Value<String?>? attemptToken,
      Value<int?>? leaseUntilMicros,
      Value<int?>? retryAtMicros,
      Value<String?>? failure,
      Value<int?>? completedTrackId,
      Value<int>? createdAtMicros,
      Value<int>? updatedAtMicros}) {
    return DownloadJobsCompanion(
      id: id ?? this.id,
      libraryFolderId: libraryFolderId ?? this.libraryFolderId,
      provider: provider ?? this.provider,
      externalId: externalId ?? this.externalId,
      variantKey: variantKey ?? this.variantKey,
      quality: quality ?? this.quality,
      accountId: accountId ?? this.accountId,
      accountRevision: accountRevision ?? this.accountRevision,
      state: state ?? this.state,
      stage: stage ?? this.stage,
      revision: revision ?? this.revision,
      attemptCount: attemptCount ?? this.attemptCount,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      remainingAttempts: remainingAttempts ?? this.remainingAttempts,
      attemptToken: attemptToken ?? this.attemptToken,
      leaseUntilMicros: leaseUntilMicros ?? this.leaseUntilMicros,
      retryAtMicros: retryAtMicros ?? this.retryAtMicros,
      failure: failure ?? this.failure,
      completedTrackId: completedTrackId ?? this.completedTrackId,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
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
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (variantKey.present) {
      map['variant_key'] = Variable<String>(variantKey.value);
    }
    if (quality.present) {
      map['quality'] = Variable<String>(quality.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (accountRevision.present) {
      map['account_revision'] = Variable<int>(accountRevision.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (maxAttempts.present) {
      map['max_attempts'] = Variable<int>(maxAttempts.value);
    }
    if (remainingAttempts.present) {
      map['remaining_attempts'] = Variable<int>(remainingAttempts.value);
    }
    if (attemptToken.present) {
      map['attempt_token'] = Variable<String>(attemptToken.value);
    }
    if (leaseUntilMicros.present) {
      map['lease_until_micros'] = Variable<int>(leaseUntilMicros.value);
    }
    if (retryAtMicros.present) {
      map['retry_at_micros'] = Variable<int>(retryAtMicros.value);
    }
    if (failure.present) {
      map['failure'] = Variable<String>(failure.value);
    }
    if (completedTrackId.present) {
      map['completed_track_id'] = Variable<int>(completedTrackId.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadJobsCompanion(')
          ..write('id: $id, ')
          ..write('libraryFolderId: $libraryFolderId, ')
          ..write('provider: $provider, ')
          ..write('externalId: $externalId, ')
          ..write('variantKey: $variantKey, ')
          ..write('quality: $quality, ')
          ..write('accountId: $accountId, ')
          ..write('accountRevision: $accountRevision, ')
          ..write('state: $state, ')
          ..write('stage: $stage, ')
          ..write('revision: $revision, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('maxAttempts: $maxAttempts, ')
          ..write('remainingAttempts: $remainingAttempts, ')
          ..write('attemptToken: $attemptToken, ')
          ..write('leaseUntilMicros: $leaseUntilMicros, ')
          ..write('retryAtMicros: $retryAtMicros, ')
          ..write('failure: $failure, ')
          ..write('completedTrackId: $completedTrackId, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }
}

class $DownloadAttemptsTable extends DownloadAttempts
    with TableInfo<$DownloadAttemptsTable, DownloadAttemptRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadAttemptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<int> jobId = GeneratedColumn<int>(
      'job_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES download_jobs (id) ON DELETE CASCADE'));
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
      'number', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _tokenMeta = const VerificationMeta('token');
  @override
  late final GeneratedColumn<String> token = GeneratedColumn<String>(
      'token', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
      'account_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _accountRevisionMeta =
      const VerificationMeta('accountRevision');
  @override
  late final GeneratedColumn<int> accountRevision = GeneratedColumn<int>(
      'account_revision', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
      'stage', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _outcomeMeta =
      const VerificationMeta('outcome');
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
      'outcome', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startedAtMicrosMeta =
      const VerificationMeta('startedAtMicros');
  @override
  late final GeneratedColumn<int> startedAtMicros = GeneratedColumn<int>(
      'started_at_micros', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _finishedAtMicrosMeta =
      const VerificationMeta('finishedAtMicros');
  @override
  late final GeneratedColumn<int> finishedAtMicros = GeneratedColumn<int>(
      'finished_at_micros', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _failureMeta =
      const VerificationMeta('failure');
  @override
  late final GeneratedColumn<String> failure = GeneratedColumn<String>(
      'failure', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        jobId,
        number,
        token,
        accountId,
        accountRevision,
        stage,
        outcome,
        startedAtMicros,
        finishedAtMicros,
        failure
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_attempts';
  @override
  VerificationContext validateIntegrity(Insertable<DownloadAttemptRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('job_id')) {
      context.handle(
          _jobIdMeta, jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta));
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(_numberMeta,
          number.isAcceptableOrUnknown(data['number']!, _numberMeta));
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('token')) {
      context.handle(
          _tokenMeta, token.isAcceptableOrUnknown(data['token']!, _tokenMeta));
    } else if (isInserting) {
      context.missing(_tokenMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('account_revision')) {
      context.handle(
          _accountRevisionMeta,
          accountRevision.isAcceptableOrUnknown(
              data['account_revision']!, _accountRevisionMeta));
    } else if (isInserting) {
      context.missing(_accountRevisionMeta);
    }
    if (data.containsKey('stage')) {
      context.handle(
          _stageMeta, stage.isAcceptableOrUnknown(data['stage']!, _stageMeta));
    } else if (isInserting) {
      context.missing(_stageMeta);
    }
    if (data.containsKey('outcome')) {
      context.handle(_outcomeMeta,
          outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta));
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('started_at_micros')) {
      context.handle(
          _startedAtMicrosMeta,
          startedAtMicros.isAcceptableOrUnknown(
              data['started_at_micros']!, _startedAtMicrosMeta));
    } else if (isInserting) {
      context.missing(_startedAtMicrosMeta);
    }
    if (data.containsKey('finished_at_micros')) {
      context.handle(
          _finishedAtMicrosMeta,
          finishedAtMicros.isAcceptableOrUnknown(
              data['finished_at_micros']!, _finishedAtMicrosMeta));
    }
    if (data.containsKey('failure')) {
      context.handle(_failureMeta,
          failure.isAcceptableOrUnknown(data['failure']!, _failureMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {jobId, number};
  @override
  DownloadAttemptRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadAttemptRow(
      jobId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}job_id'])!,
      number: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}number'])!,
      token: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}token'])!,
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}account_id'])!,
      accountRevision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}account_revision'])!,
      stage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}stage'])!,
      outcome: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}outcome'])!,
      startedAtMicros: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}started_at_micros'])!,
      finishedAtMicros: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}finished_at_micros']),
      failure: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}failure']),
    );
  }

  @override
  $DownloadAttemptsTable createAlias(String alias) {
    return $DownloadAttemptsTable(attachedDatabase, alias);
  }
}

class DownloadAttemptRow extends DataClass
    implements Insertable<DownloadAttemptRow> {
  final int jobId;
  final int number;
  final String token;
  final int accountId;
  final int accountRevision;
  final String stage;
  final String outcome;
  final int startedAtMicros;
  final int? finishedAtMicros;
  final String? failure;
  const DownloadAttemptRow(
      {required this.jobId,
      required this.number,
      required this.token,
      required this.accountId,
      required this.accountRevision,
      required this.stage,
      required this.outcome,
      required this.startedAtMicros,
      this.finishedAtMicros,
      this.failure});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['job_id'] = Variable<int>(jobId);
    map['number'] = Variable<int>(number);
    map['token'] = Variable<String>(token);
    map['account_id'] = Variable<int>(accountId);
    map['account_revision'] = Variable<int>(accountRevision);
    map['stage'] = Variable<String>(stage);
    map['outcome'] = Variable<String>(outcome);
    map['started_at_micros'] = Variable<int>(startedAtMicros);
    if (!nullToAbsent || finishedAtMicros != null) {
      map['finished_at_micros'] = Variable<int>(finishedAtMicros);
    }
    if (!nullToAbsent || failure != null) {
      map['failure'] = Variable<String>(failure);
    }
    return map;
  }

  DownloadAttemptsCompanion toCompanion(bool nullToAbsent) {
    return DownloadAttemptsCompanion(
      jobId: Value(jobId),
      number: Value(number),
      token: Value(token),
      accountId: Value(accountId),
      accountRevision: Value(accountRevision),
      stage: Value(stage),
      outcome: Value(outcome),
      startedAtMicros: Value(startedAtMicros),
      finishedAtMicros: finishedAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAtMicros),
      failure: failure == null && nullToAbsent
          ? const Value.absent()
          : Value(failure),
    );
  }

  factory DownloadAttemptRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadAttemptRow(
      jobId: serializer.fromJson<int>(json['jobId']),
      number: serializer.fromJson<int>(json['number']),
      token: serializer.fromJson<String>(json['token']),
      accountId: serializer.fromJson<int>(json['accountId']),
      accountRevision: serializer.fromJson<int>(json['accountRevision']),
      stage: serializer.fromJson<String>(json['stage']),
      outcome: serializer.fromJson<String>(json['outcome']),
      startedAtMicros: serializer.fromJson<int>(json['startedAtMicros']),
      finishedAtMicros: serializer.fromJson<int?>(json['finishedAtMicros']),
      failure: serializer.fromJson<String?>(json['failure']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'jobId': serializer.toJson<int>(jobId),
      'number': serializer.toJson<int>(number),
      'token': serializer.toJson<String>(token),
      'accountId': serializer.toJson<int>(accountId),
      'accountRevision': serializer.toJson<int>(accountRevision),
      'stage': serializer.toJson<String>(stage),
      'outcome': serializer.toJson<String>(outcome),
      'startedAtMicros': serializer.toJson<int>(startedAtMicros),
      'finishedAtMicros': serializer.toJson<int?>(finishedAtMicros),
      'failure': serializer.toJson<String?>(failure),
    };
  }

  DownloadAttemptRow copyWith(
          {int? jobId,
          int? number,
          String? token,
          int? accountId,
          int? accountRevision,
          String? stage,
          String? outcome,
          int? startedAtMicros,
          Value<int?> finishedAtMicros = const Value.absent(),
          Value<String?> failure = const Value.absent()}) =>
      DownloadAttemptRow(
        jobId: jobId ?? this.jobId,
        number: number ?? this.number,
        token: token ?? this.token,
        accountId: accountId ?? this.accountId,
        accountRevision: accountRevision ?? this.accountRevision,
        stage: stage ?? this.stage,
        outcome: outcome ?? this.outcome,
        startedAtMicros: startedAtMicros ?? this.startedAtMicros,
        finishedAtMicros: finishedAtMicros.present
            ? finishedAtMicros.value
            : this.finishedAtMicros,
        failure: failure.present ? failure.value : this.failure,
      );
  DownloadAttemptRow copyWithCompanion(DownloadAttemptsCompanion data) {
    return DownloadAttemptRow(
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      number: data.number.present ? data.number.value : this.number,
      token: data.token.present ? data.token.value : this.token,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      accountRevision: data.accountRevision.present
          ? data.accountRevision.value
          : this.accountRevision,
      stage: data.stage.present ? data.stage.value : this.stage,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      startedAtMicros: data.startedAtMicros.present
          ? data.startedAtMicros.value
          : this.startedAtMicros,
      finishedAtMicros: data.finishedAtMicros.present
          ? data.finishedAtMicros.value
          : this.finishedAtMicros,
      failure: data.failure.present ? data.failure.value : this.failure,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadAttemptRow(')
          ..write('jobId: $jobId, ')
          ..write('number: $number, ')
          ..write('token: $token, ')
          ..write('accountId: $accountId, ')
          ..write('accountRevision: $accountRevision, ')
          ..write('stage: $stage, ')
          ..write('outcome: $outcome, ')
          ..write('startedAtMicros: $startedAtMicros, ')
          ..write('finishedAtMicros: $finishedAtMicros, ')
          ..write('failure: $failure')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      jobId,
      number,
      token,
      accountId,
      accountRevision,
      stage,
      outcome,
      startedAtMicros,
      finishedAtMicros,
      failure);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadAttemptRow &&
          other.jobId == this.jobId &&
          other.number == this.number &&
          other.token == this.token &&
          other.accountId == this.accountId &&
          other.accountRevision == this.accountRevision &&
          other.stage == this.stage &&
          other.outcome == this.outcome &&
          other.startedAtMicros == this.startedAtMicros &&
          other.finishedAtMicros == this.finishedAtMicros &&
          other.failure == this.failure);
}

class DownloadAttemptsCompanion extends UpdateCompanion<DownloadAttemptRow> {
  final Value<int> jobId;
  final Value<int> number;
  final Value<String> token;
  final Value<int> accountId;
  final Value<int> accountRevision;
  final Value<String> stage;
  final Value<String> outcome;
  final Value<int> startedAtMicros;
  final Value<int?> finishedAtMicros;
  final Value<String?> failure;
  final Value<int> rowid;
  const DownloadAttemptsCompanion({
    this.jobId = const Value.absent(),
    this.number = const Value.absent(),
    this.token = const Value.absent(),
    this.accountId = const Value.absent(),
    this.accountRevision = const Value.absent(),
    this.stage = const Value.absent(),
    this.outcome = const Value.absent(),
    this.startedAtMicros = const Value.absent(),
    this.finishedAtMicros = const Value.absent(),
    this.failure = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadAttemptsCompanion.insert({
    required int jobId,
    required int number,
    required String token,
    required int accountId,
    required int accountRevision,
    required String stage,
    required String outcome,
    required int startedAtMicros,
    this.finishedAtMicros = const Value.absent(),
    this.failure = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : jobId = Value(jobId),
        number = Value(number),
        token = Value(token),
        accountId = Value(accountId),
        accountRevision = Value(accountRevision),
        stage = Value(stage),
        outcome = Value(outcome),
        startedAtMicros = Value(startedAtMicros);
  static Insertable<DownloadAttemptRow> custom({
    Expression<int>? jobId,
    Expression<int>? number,
    Expression<String>? token,
    Expression<int>? accountId,
    Expression<int>? accountRevision,
    Expression<String>? stage,
    Expression<String>? outcome,
    Expression<int>? startedAtMicros,
    Expression<int>? finishedAtMicros,
    Expression<String>? failure,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (jobId != null) 'job_id': jobId,
      if (number != null) 'number': number,
      if (token != null) 'token': token,
      if (accountId != null) 'account_id': accountId,
      if (accountRevision != null) 'account_revision': accountRevision,
      if (stage != null) 'stage': stage,
      if (outcome != null) 'outcome': outcome,
      if (startedAtMicros != null) 'started_at_micros': startedAtMicros,
      if (finishedAtMicros != null) 'finished_at_micros': finishedAtMicros,
      if (failure != null) 'failure': failure,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadAttemptsCompanion copyWith(
      {Value<int>? jobId,
      Value<int>? number,
      Value<String>? token,
      Value<int>? accountId,
      Value<int>? accountRevision,
      Value<String>? stage,
      Value<String>? outcome,
      Value<int>? startedAtMicros,
      Value<int?>? finishedAtMicros,
      Value<String?>? failure,
      Value<int>? rowid}) {
    return DownloadAttemptsCompanion(
      jobId: jobId ?? this.jobId,
      number: number ?? this.number,
      token: token ?? this.token,
      accountId: accountId ?? this.accountId,
      accountRevision: accountRevision ?? this.accountRevision,
      stage: stage ?? this.stage,
      outcome: outcome ?? this.outcome,
      startedAtMicros: startedAtMicros ?? this.startedAtMicros,
      finishedAtMicros: finishedAtMicros ?? this.finishedAtMicros,
      failure: failure ?? this.failure,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (jobId.present) {
      map['job_id'] = Variable<int>(jobId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (token.present) {
      map['token'] = Variable<String>(token.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (accountRevision.present) {
      map['account_revision'] = Variable<int>(accountRevision.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (startedAtMicros.present) {
      map['started_at_micros'] = Variable<int>(startedAtMicros.value);
    }
    if (finishedAtMicros.present) {
      map['finished_at_micros'] = Variable<int>(finishedAtMicros.value);
    }
    if (failure.present) {
      map['failure'] = Variable<String>(failure.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadAttemptsCompanion(')
          ..write('jobId: $jobId, ')
          ..write('number: $number, ')
          ..write('token: $token, ')
          ..write('accountId: $accountId, ')
          ..write('accountRevision: $accountRevision, ')
          ..write('stage: $stage, ')
          ..write('outcome: $outcome, ')
          ..write('startedAtMicros: $startedAtMicros, ')
          ..write('finishedAtMicros: $finishedAtMicros, ')
          ..write('failure: $failure, ')
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
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $PlaylistTracksTable playlistTracks = $PlaylistTracksTable(this);
  late final $PlaybackEventsTable playbackEvents = $PlaybackEventsTable(this);
  late final $TrackUserStatesTable trackUserStates =
      $TrackUserStatesTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $ExternalTrackRefsTable externalTrackRefs =
      $ExternalTrackRefsTable(this);
  late final $DownloadedAssetsTable downloadedAssets =
      $DownloadedAssetsTable(this);
  late final $RemoteAccountsTable remoteAccounts = $RemoteAccountsTable(this);
  late final $RemoteCollectionsTable remoteCollections =
      $RemoteCollectionsTable(this);
  late final $RemoteCollectionItemsTable remoteCollectionItems =
      $RemoteCollectionItemsTable(this);
  late final $DownloadJobsTable downloadJobs = $DownloadJobsTable(this);
  late final $DownloadAttemptsTable downloadAttempts =
      $DownloadAttemptsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        libraryFolders,
        tracks,
        playlists,
        playlistTracks,
        playbackEvents,
        trackUserStates,
        appSettings,
        externalTrackRefs,
        downloadedAssets,
        remoteAccounts,
        remoteCollections,
        remoteCollectionItems,
        downloadJobs,
        downloadAttempts
      ];
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
            on: TableUpdateQuery.onTableName('playlists',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('playlist_tracks', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('tracks',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('playlist_tracks', kind: UpdateKind.delete),
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
          WritePropagation(
            on: TableUpdateQuery.onTableName('tracks',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('external_track_refs', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('tracks',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('downloaded_assets', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('remote_accounts',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('remote_collections', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('remote_collections',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('remote_collection_items', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('library_folders',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('download_jobs', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('remote_accounts',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('download_jobs', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('download_jobs',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('download_attempts', kind: UpdateKind.delete),
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

  static MultiTypedResultKey<$DownloadJobsTable, List<DownloadJobRow>>
      _downloadJobsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.downloadJobs,
              aliasName: $_aliasNameGenerator(
                  db.libraryFolders.id, db.downloadJobs.libraryFolderId));

  $$DownloadJobsTableProcessedTableManager get downloadJobsRefs {
    final manager = $$DownloadJobsTableTableManager($_db, $_db.downloadJobs)
        .filter(
            (f) => f.libraryFolderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_downloadJobsRefsTable($_db));
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

  Expression<bool> downloadJobsRefs(
      Expression<bool> Function($$DownloadJobsTableFilterComposer f) f) {
    final $$DownloadJobsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadJobs,
        getReferencedColumn: (t) => t.libraryFolderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadJobsTableFilterComposer(
              $db: $db,
              $table: $db.downloadJobs,
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

  Expression<T> downloadJobsRefs<T extends Object>(
      Expression<T> Function($$DownloadJobsTableAnnotationComposer a) f) {
    final $$DownloadJobsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadJobs,
        getReferencedColumn: (t) => t.libraryFolderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadJobsTableAnnotationComposer(
              $db: $db,
              $table: $db.downloadJobs,
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
    PrefetchHooks Function({bool tracksRefs, bool downloadJobsRefs})> {
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
          prefetchHooksCallback: (
              {tracksRefs = false, downloadJobsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (tracksRefs) db.tracks,
                if (downloadJobsRefs) db.downloadJobs
              ],
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
                        typedResults: items),
                  if (downloadJobsRefs)
                    await $_getPrefetchedData<LibraryFolderRow,
                            $LibraryFoldersTable, DownloadJobRow>(
                        currentTable: table,
                        referencedTable: $$LibraryFoldersTableReferences
                            ._downloadJobsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LibraryFoldersTableReferences(db, table, p0)
                                .downloadJobsRefs,
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
    PrefetchHooks Function({bool tracksRefs, bool downloadJobsRefs})>;
typedef $$TracksTableCreateCompanionBuilder = TracksCompanion Function({
  Value<int> id,
  Value<int?> libraryFolderId,
  Value<String?> stableId,
  required String filePath,
  Value<String?> contentHash,
  Value<String?> title,
  Value<String?> artist,
  Value<String?> album,
  Value<String?> albumArtist,
  Value<String?> genre,
  Value<String?> artworkPath,
  Value<String?> artworkHash,
  Value<String?> artworkMimeType,
  Value<String?> customArtworkPath,
  Value<String?> customArtworkHash,
  Value<String?> customArtworkMimeType,
  Value<String?> codec,
  Value<int?> durationMs,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<int?> year,
  Value<String?> metadataSource,
  Value<double?> metadataConfidence,
  Value<int?> fileSizeBytes,
  Value<DateTime?> modifiedAt,
  Value<DateTime?> lastSeenAt,
  Value<bool> isMissing,
  required DateTime addedAt,
  required DateTime updatedAt,
});
typedef $$TracksTableUpdateCompanionBuilder = TracksCompanion Function({
  Value<int> id,
  Value<int?> libraryFolderId,
  Value<String?> stableId,
  Value<String> filePath,
  Value<String?> contentHash,
  Value<String?> title,
  Value<String?> artist,
  Value<String?> album,
  Value<String?> albumArtist,
  Value<String?> genre,
  Value<String?> artworkPath,
  Value<String?> artworkHash,
  Value<String?> artworkMimeType,
  Value<String?> customArtworkPath,
  Value<String?> customArtworkHash,
  Value<String?> customArtworkMimeType,
  Value<String?> codec,
  Value<int?> durationMs,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<int?> year,
  Value<String?> metadataSource,
  Value<double?> metadataConfidence,
  Value<int?> fileSizeBytes,
  Value<DateTime?> modifiedAt,
  Value<DateTime?> lastSeenAt,
  Value<bool> isMissing,
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

  static MultiTypedResultKey<$PlaylistTracksTable, List<PlaylistTrackRow>>
      _playlistTracksRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.playlistTracks,
              aliasName: $_aliasNameGenerator(
                  db.tracks.id, db.playlistTracks.trackId));

  $$PlaylistTracksTableProcessedTableManager get playlistTracksRefs {
    final manager = $$PlaylistTracksTableTableManager($_db, $_db.playlistTracks)
        .filter((f) => f.trackId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_playlistTracksRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
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

  static MultiTypedResultKey<$ExternalTrackRefsTable, List<ExternalTrackRefRow>>
      _externalTrackRefsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.externalTrackRefs,
              aliasName: $_aliasNameGenerator(
                  db.tracks.id, db.externalTrackRefs.trackId));

  $$ExternalTrackRefsTableProcessedTableManager get externalTrackRefsRefs {
    final manager =
        $$ExternalTrackRefsTableTableManager($_db, $_db.externalTrackRefs)
            .filter((f) => f.trackId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_externalTrackRefsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$DownloadedAssetsTable, List<DownloadedAssetRow>>
      _downloadedAssetsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.downloadedAssets,
              aliasName: $_aliasNameGenerator(
                  db.tracks.id, db.downloadedAssets.trackId));

  $$DownloadedAssetsTableProcessedTableManager get downloadedAssetsRefs {
    final manager =
        $$DownloadedAssetsTableTableManager($_db, $_db.downloadedAssets)
            .filter((f) => f.trackId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_downloadedAssetsRefsTable($_db));
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

  ColumnFilters<String> get stableId => $composableBuilder(
      column: $table.stableId, builder: (column) => ColumnFilters(column));

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

  ColumnFilters<String> get artworkPath => $composableBuilder(
      column: $table.artworkPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artworkHash => $composableBuilder(
      column: $table.artworkHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artworkMimeType => $composableBuilder(
      column: $table.artworkMimeType,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customArtworkPath => $composableBuilder(
      column: $table.customArtworkPath,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customArtworkHash => $composableBuilder(
      column: $table.customArtworkHash,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customArtworkMimeType => $composableBuilder(
      column: $table.customArtworkMimeType,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get codec => $composableBuilder(
      column: $table.codec, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get metadataSource => $composableBuilder(
      column: $table.metadataSource,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get metadataConfidence => $composableBuilder(
      column: $table.metadataConfidence,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
      column: $table.lastSeenAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isMissing => $composableBuilder(
      column: $table.isMissing, builder: (column) => ColumnFilters(column));

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

  Expression<bool> playlistTracksRefs(
      Expression<bool> Function($$PlaylistTracksTableFilterComposer f) f) {
    final $$PlaylistTracksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.playlistTracks,
        getReferencedColumn: (t) => t.trackId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistTracksTableFilterComposer(
              $db: $db,
              $table: $db.playlistTracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
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

  Expression<bool> externalTrackRefsRefs(
      Expression<bool> Function($$ExternalTrackRefsTableFilterComposer f) f) {
    final $$ExternalTrackRefsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.externalTrackRefs,
        getReferencedColumn: (t) => t.trackId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ExternalTrackRefsTableFilterComposer(
              $db: $db,
              $table: $db.externalTrackRefs,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> downloadedAssetsRefs(
      Expression<bool> Function($$DownloadedAssetsTableFilterComposer f) f) {
    final $$DownloadedAssetsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadedAssets,
        getReferencedColumn: (t) => t.trackId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadedAssetsTableFilterComposer(
              $db: $db,
              $table: $db.downloadedAssets,
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

  ColumnOrderings<String> get stableId => $composableBuilder(
      column: $table.stableId, builder: (column) => ColumnOrderings(column));

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

  ColumnOrderings<String> get artworkPath => $composableBuilder(
      column: $table.artworkPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artworkHash => $composableBuilder(
      column: $table.artworkHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artworkMimeType => $composableBuilder(
      column: $table.artworkMimeType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customArtworkPath => $composableBuilder(
      column: $table.customArtworkPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customArtworkHash => $composableBuilder(
      column: $table.customArtworkHash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customArtworkMimeType => $composableBuilder(
      column: $table.customArtworkMimeType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get codec => $composableBuilder(
      column: $table.codec, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get metadataSource => $composableBuilder(
      column: $table.metadataSource,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get metadataConfidence => $composableBuilder(
      column: $table.metadataConfidence,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
      column: $table.lastSeenAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isMissing => $composableBuilder(
      column: $table.isMissing, builder: (column) => ColumnOrderings(column));

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

  GeneratedColumn<String> get stableId =>
      $composableBuilder(column: $table.stableId, builder: (column) => column);

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

  GeneratedColumn<String> get artworkPath => $composableBuilder(
      column: $table.artworkPath, builder: (column) => column);

  GeneratedColumn<String> get artworkHash => $composableBuilder(
      column: $table.artworkHash, builder: (column) => column);

  GeneratedColumn<String> get artworkMimeType => $composableBuilder(
      column: $table.artworkMimeType, builder: (column) => column);

  GeneratedColumn<String> get customArtworkPath => $composableBuilder(
      column: $table.customArtworkPath, builder: (column) => column);

  GeneratedColumn<String> get customArtworkHash => $composableBuilder(
      column: $table.customArtworkHash, builder: (column) => column);

  GeneratedColumn<String> get customArtworkMimeType => $composableBuilder(
      column: $table.customArtworkMimeType, builder: (column) => column);

  GeneratedColumn<String> get codec =>
      $composableBuilder(column: $table.codec, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => column);

  GeneratedColumn<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get metadataSource => $composableBuilder(
      column: $table.metadataSource, builder: (column) => column);

  GeneratedColumn<double> get metadataConfidence => $composableBuilder(
      column: $table.metadataConfidence, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
      column: $table.lastSeenAt, builder: (column) => column);

  GeneratedColumn<bool> get isMissing =>
      $composableBuilder(column: $table.isMissing, builder: (column) => column);

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

  Expression<T> playlistTracksRefs<T extends Object>(
      Expression<T> Function($$PlaylistTracksTableAnnotationComposer a) f) {
    final $$PlaylistTracksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.playlistTracks,
        getReferencedColumn: (t) => t.trackId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistTracksTableAnnotationComposer(
              $db: $db,
              $table: $db.playlistTracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
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

  Expression<T> externalTrackRefsRefs<T extends Object>(
      Expression<T> Function($$ExternalTrackRefsTableAnnotationComposer a) f) {
    final $$ExternalTrackRefsTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.externalTrackRefs,
            getReferencedColumn: (t) => t.trackId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$ExternalTrackRefsTableAnnotationComposer(
                  $db: $db,
                  $table: $db.externalTrackRefs,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> downloadedAssetsRefs<T extends Object>(
      Expression<T> Function($$DownloadedAssetsTableAnnotationComposer a) f) {
    final $$DownloadedAssetsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadedAssets,
        getReferencedColumn: (t) => t.trackId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadedAssetsTableAnnotationComposer(
              $db: $db,
              $table: $db.downloadedAssets,
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
        bool playlistTracksRefs,
        bool playbackEventsRefs,
        bool trackUserStatesRefs,
        bool externalTrackRefsRefs,
        bool downloadedAssetsRefs})> {
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
            Value<String?> stableId = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<String?> contentHash = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<String?> artist = const Value.absent(),
            Value<String?> album = const Value.absent(),
            Value<String?> albumArtist = const Value.absent(),
            Value<String?> genre = const Value.absent(),
            Value<String?> artworkPath = const Value.absent(),
            Value<String?> artworkHash = const Value.absent(),
            Value<String?> artworkMimeType = const Value.absent(),
            Value<String?> customArtworkPath = const Value.absent(),
            Value<String?> customArtworkHash = const Value.absent(),
            Value<String?> customArtworkMimeType = const Value.absent(),
            Value<String?> codec = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int?> trackNumber = const Value.absent(),
            Value<int?> discNumber = const Value.absent(),
            Value<int?> year = const Value.absent(),
            Value<String?> metadataSource = const Value.absent(),
            Value<double?> metadataConfidence = const Value.absent(),
            Value<int?> fileSizeBytes = const Value.absent(),
            Value<DateTime?> modifiedAt = const Value.absent(),
            Value<DateTime?> lastSeenAt = const Value.absent(),
            Value<bool> isMissing = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              TracksCompanion(
            id: id,
            libraryFolderId: libraryFolderId,
            stableId: stableId,
            filePath: filePath,
            contentHash: contentHash,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            artworkPath: artworkPath,
            artworkHash: artworkHash,
            artworkMimeType: artworkMimeType,
            customArtworkPath: customArtworkPath,
            customArtworkHash: customArtworkHash,
            customArtworkMimeType: customArtworkMimeType,
            codec: codec,
            durationMs: durationMs,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            metadataSource: metadataSource,
            metadataConfidence: metadataConfidence,
            fileSizeBytes: fileSizeBytes,
            modifiedAt: modifiedAt,
            lastSeenAt: lastSeenAt,
            isMissing: isMissing,
            addedAt: addedAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> libraryFolderId = const Value.absent(),
            Value<String?> stableId = const Value.absent(),
            required String filePath,
            Value<String?> contentHash = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<String?> artist = const Value.absent(),
            Value<String?> album = const Value.absent(),
            Value<String?> albumArtist = const Value.absent(),
            Value<String?> genre = const Value.absent(),
            Value<String?> artworkPath = const Value.absent(),
            Value<String?> artworkHash = const Value.absent(),
            Value<String?> artworkMimeType = const Value.absent(),
            Value<String?> customArtworkPath = const Value.absent(),
            Value<String?> customArtworkHash = const Value.absent(),
            Value<String?> customArtworkMimeType = const Value.absent(),
            Value<String?> codec = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int?> trackNumber = const Value.absent(),
            Value<int?> discNumber = const Value.absent(),
            Value<int?> year = const Value.absent(),
            Value<String?> metadataSource = const Value.absent(),
            Value<double?> metadataConfidence = const Value.absent(),
            Value<int?> fileSizeBytes = const Value.absent(),
            Value<DateTime?> modifiedAt = const Value.absent(),
            Value<DateTime?> lastSeenAt = const Value.absent(),
            Value<bool> isMissing = const Value.absent(),
            required DateTime addedAt,
            required DateTime updatedAt,
          }) =>
              TracksCompanion.insert(
            id: id,
            libraryFolderId: libraryFolderId,
            stableId: stableId,
            filePath: filePath,
            contentHash: contentHash,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            artworkPath: artworkPath,
            artworkHash: artworkHash,
            artworkMimeType: artworkMimeType,
            customArtworkPath: customArtworkPath,
            customArtworkHash: customArtworkHash,
            customArtworkMimeType: customArtworkMimeType,
            codec: codec,
            durationMs: durationMs,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            metadataSource: metadataSource,
            metadataConfidence: metadataConfidence,
            fileSizeBytes: fileSizeBytes,
            modifiedAt: modifiedAt,
            lastSeenAt: lastSeenAt,
            isMissing: isMissing,
            addedAt: addedAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$TracksTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {libraryFolderId = false,
              playlistTracksRefs = false,
              playbackEventsRefs = false,
              trackUserStatesRefs = false,
              externalTrackRefsRefs = false,
              downloadedAssetsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (playlistTracksRefs) db.playlistTracks,
                if (playbackEventsRefs) db.playbackEvents,
                if (trackUserStatesRefs) db.trackUserStates,
                if (externalTrackRefsRefs) db.externalTrackRefs,
                if (downloadedAssetsRefs) db.downloadedAssets
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
                  if (playlistTracksRefs)
                    await $_getPrefetchedData<TrackRow, $TracksTable,
                            PlaylistTrackRow>(
                        currentTable: table,
                        referencedTable: $$TracksTableReferences
                            ._playlistTracksRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TracksTableReferences(db, table, p0)
                                .playlistTracksRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.trackId == item.id),
                        typedResults: items),
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
                        typedResults: items),
                  if (externalTrackRefsRefs)
                    await $_getPrefetchedData<TrackRow, $TracksTable,
                            ExternalTrackRefRow>(
                        currentTable: table,
                        referencedTable: $$TracksTableReferences
                            ._externalTrackRefsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TracksTableReferences(db, table, p0)
                                .externalTrackRefsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.trackId == item.id),
                        typedResults: items),
                  if (downloadedAssetsRefs)
                    await $_getPrefetchedData<TrackRow, $TracksTable,
                            DownloadedAssetRow>(
                        currentTable: table,
                        referencedTable: $$TracksTableReferences
                            ._downloadedAssetsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TracksTableReferences(db, table, p0)
                                .downloadedAssetsRefs,
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
        bool playlistTracksRefs,
        bool playbackEventsRefs,
        bool trackUserStatesRefs,
        bool externalTrackRefsRefs,
        bool downloadedAssetsRefs})>;
typedef $$PlaylistsTableCreateCompanionBuilder = PlaylistsCompanion Function({
  Value<int> id,
  required String name,
  Value<String?> description,
  required DateTime createdAt,
  required DateTime updatedAt,
});
typedef $$PlaylistsTableUpdateCompanionBuilder = PlaylistsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String?> description,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$PlaylistsTableReferences
    extends BaseReferences<_$AppDatabase, $PlaylistsTable, PlaylistRow> {
  $$PlaylistsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PlaylistTracksTable, List<PlaylistTrackRow>>
      _playlistTracksRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.playlistTracks,
              aliasName: $_aliasNameGenerator(
                  db.playlists.id, db.playlistTracks.playlistId));

  $$PlaylistTracksTableProcessedTableManager get playlistTracksRefs {
    final manager = $$PlaylistTracksTableTableManager($_db, $_db.playlistTracks)
        .filter((f) => f.playlistId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_playlistTracksRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> playlistTracksRefs(
      Expression<bool> Function($$PlaylistTracksTableFilterComposer f) f) {
    final $$PlaylistTracksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.playlistTracks,
        getReferencedColumn: (t) => t.playlistId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistTracksTableFilterComposer(
              $db: $db,
              $table: $db.playlistTracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> playlistTracksRefs<T extends Object>(
      Expression<T> Function($$PlaylistTracksTableAnnotationComposer a) f) {
    final $$PlaylistTracksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.playlistTracks,
        getReferencedColumn: (t) => t.playlistId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistTracksTableAnnotationComposer(
              $db: $db,
              $table: $db.playlistTracks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$PlaylistsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlaylistsTable,
    PlaylistRow,
    $$PlaylistsTableFilterComposer,
    $$PlaylistsTableOrderingComposer,
    $$PlaylistsTableAnnotationComposer,
    $$PlaylistsTableCreateCompanionBuilder,
    $$PlaylistsTableUpdateCompanionBuilder,
    (PlaylistRow, $$PlaylistsTableReferences),
    PlaylistRow,
    PrefetchHooks Function({bool playlistTracksRefs})> {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              PlaylistsCompanion(
            id: id,
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String?> description = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
          }) =>
              PlaylistsCompanion.insert(
            id: id,
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PlaylistsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({playlistTracksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (playlistTracksRefs) db.playlistTracks
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (playlistTracksRefs)
                    await $_getPrefetchedData<PlaylistRow, $PlaylistsTable,
                            PlaylistTrackRow>(
                        currentTable: table,
                        referencedTable: $$PlaylistsTableReferences
                            ._playlistTracksRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$PlaylistsTableReferences(db, table, p0)
                                .playlistTracksRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.playlistId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$PlaylistsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlaylistsTable,
    PlaylistRow,
    $$PlaylistsTableFilterComposer,
    $$PlaylistsTableOrderingComposer,
    $$PlaylistsTableAnnotationComposer,
    $$PlaylistsTableCreateCompanionBuilder,
    $$PlaylistsTableUpdateCompanionBuilder,
    (PlaylistRow, $$PlaylistsTableReferences),
    PlaylistRow,
    PrefetchHooks Function({bool playlistTracksRefs})>;
typedef $$PlaylistTracksTableCreateCompanionBuilder = PlaylistTracksCompanion
    Function({
  required int playlistId,
  required int trackId,
  required int position,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$PlaylistTracksTableUpdateCompanionBuilder = PlaylistTracksCompanion
    Function({
  Value<int> playlistId,
  Value<int> trackId,
  Value<int> position,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

final class $$PlaylistTracksTableReferences extends BaseReferences<
    _$AppDatabase, $PlaylistTracksTable, PlaylistTrackRow> {
  $$PlaylistTracksTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $PlaylistsTable _playlistIdTable(_$AppDatabase db) =>
      db.playlists.createAlias(
          $_aliasNameGenerator(db.playlistTracks.playlistId, db.playlists.id));

  $$PlaylistsTableProcessedTableManager get playlistId {
    final $_column = $_itemColumn<int>('playlist_id')!;

    final manager = $$PlaylistsTableTableManager($_db, $_db.playlists)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_playlistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $TracksTable _trackIdTable(_$AppDatabase db) => db.tracks.createAlias(
      $_aliasNameGenerator(db.playlistTracks.trackId, db.tracks.id));

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

class $$PlaylistTracksTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistTracksTable> {
  $$PlaylistTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));

  $$PlaylistsTableFilterComposer get playlistId {
    final $$PlaylistsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.playlistId,
        referencedTable: $db.playlists,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistsTableFilterComposer(
              $db: $db,
              $table: $db.playlists,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

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

class $$PlaylistTracksTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistTracksTable> {
  $$PlaylistTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));

  $$PlaylistsTableOrderingComposer get playlistId {
    final $$PlaylistsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.playlistId,
        referencedTable: $db.playlists,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistsTableOrderingComposer(
              $db: $db,
              $table: $db.playlists,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

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

class $$PlaylistTracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistTracksTable> {
  $$PlaylistTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  $$PlaylistsTableAnnotationComposer get playlistId {
    final $$PlaylistsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.playlistId,
        referencedTable: $db.playlists,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistsTableAnnotationComposer(
              $db: $db,
              $table: $db.playlists,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

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

class $$PlaylistTracksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlaylistTracksTable,
    PlaylistTrackRow,
    $$PlaylistTracksTableFilterComposer,
    $$PlaylistTracksTableOrderingComposer,
    $$PlaylistTracksTableAnnotationComposer,
    $$PlaylistTracksTableCreateCompanionBuilder,
    $$PlaylistTracksTableUpdateCompanionBuilder,
    (PlaylistTrackRow, $$PlaylistTracksTableReferences),
    PlaylistTrackRow,
    PrefetchHooks Function({bool playlistId, bool trackId})> {
  $$PlaylistTracksTableTableManager(
      _$AppDatabase db, $PlaylistTracksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistTracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> playlistId = const Value.absent(),
            Value<int> trackId = const Value.absent(),
            Value<int> position = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PlaylistTracksCompanion(
            playlistId: playlistId,
            trackId: trackId,
            position: position,
            addedAt: addedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int playlistId,
            required int trackId,
            required int position,
            required DateTime addedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PlaylistTracksCompanion.insert(
            playlistId: playlistId,
            trackId: trackId,
            position: position,
            addedAt: addedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PlaylistTracksTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({playlistId = false, trackId = false}) {
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
                if (playlistId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.playlistId,
                    referencedTable:
                        $$PlaylistTracksTableReferences._playlistIdTable(db),
                    referencedColumn:
                        $$PlaylistTracksTableReferences._playlistIdTable(db).id,
                  ) as T;
                }
                if (trackId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.trackId,
                    referencedTable:
                        $$PlaylistTracksTableReferences._trackIdTable(db),
                    referencedColumn:
                        $$PlaylistTracksTableReferences._trackIdTable(db).id,
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

typedef $$PlaylistTracksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlaylistTracksTable,
    PlaylistTrackRow,
    $$PlaylistTracksTableFilterComposer,
    $$PlaylistTracksTableOrderingComposer,
    $$PlaylistTracksTableAnnotationComposer,
    $$PlaylistTracksTableCreateCompanionBuilder,
    $$PlaylistTracksTableUpdateCompanionBuilder,
    (PlaylistTrackRow, $$PlaylistTracksTableReferences),
    PlaylistTrackRow,
    PrefetchHooks Function({bool playlistId, bool trackId})>;
typedef $$PlaybackEventsTableCreateCompanionBuilder = PlaybackEventsCompanion
    Function({
  Value<int> id,
  Value<String?> operationId,
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
  Value<String?> operationId,
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

  ColumnFilters<String> get operationId => $composableBuilder(
      column: $table.operationId, builder: (column) => ColumnFilters(column));

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

  ColumnOrderings<String> get operationId => $composableBuilder(
      column: $table.operationId, builder: (column) => ColumnOrderings(column));

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

  GeneratedColumn<String> get operationId => $composableBuilder(
      column: $table.operationId, builder: (column) => column);

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
            Value<String?> operationId = const Value.absent(),
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
            operationId: operationId,
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
            Value<String?> operationId = const Value.absent(),
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
            operationId: operationId,
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
  Value<int> completeCount,
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
  Value<int> completeCount,
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

  ColumnFilters<int> get completeCount => $composableBuilder(
      column: $table.completeCount, builder: (column) => ColumnFilters(column));

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

  ColumnOrderings<int> get completeCount => $composableBuilder(
      column: $table.completeCount,
      builder: (column) => ColumnOrderings(column));

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

  GeneratedColumn<int> get completeCount => $composableBuilder(
      column: $table.completeCount, builder: (column) => column);

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
            Value<int> completeCount = const Value.absent(),
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
            completeCount: completeCount,
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
            Value<int> completeCount = const Value.absent(),
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
            completeCount: completeCount,
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
typedef $$ExternalTrackRefsTableCreateCompanionBuilder
    = ExternalTrackRefsCompanion Function({
  required int trackId,
  required String provider,
  required String externalId,
  Value<String> variantKey,
  required String origin,
  required DateTime linkedAt,
  Value<int> rowid,
});
typedef $$ExternalTrackRefsTableUpdateCompanionBuilder
    = ExternalTrackRefsCompanion Function({
  Value<int> trackId,
  Value<String> provider,
  Value<String> externalId,
  Value<String> variantKey,
  Value<String> origin,
  Value<DateTime> linkedAt,
  Value<int> rowid,
});

final class $$ExternalTrackRefsTableReferences extends BaseReferences<
    _$AppDatabase, $ExternalTrackRefsTable, ExternalTrackRefRow> {
  $$ExternalTrackRefsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $TracksTable _trackIdTable(_$AppDatabase db) => db.tracks.createAlias(
      $_aliasNameGenerator(db.externalTrackRefs.trackId, db.tracks.id));

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

class $$ExternalTrackRefsTableFilterComposer
    extends Composer<_$AppDatabase, $ExternalTrackRefsTable> {
  $$ExternalTrackRefsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get linkedAt => $composableBuilder(
      column: $table.linkedAt, builder: (column) => ColumnFilters(column));

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

class $$ExternalTrackRefsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExternalTrackRefsTable> {
  $$ExternalTrackRefsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get linkedAt => $composableBuilder(
      column: $table.linkedAt, builder: (column) => ColumnOrderings(column));

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

class $$ExternalTrackRefsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExternalTrackRefsTable> {
  $$ExternalTrackRefsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => column);

  GeneratedColumn<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<DateTime> get linkedAt =>
      $composableBuilder(column: $table.linkedAt, builder: (column) => column);

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

class $$ExternalTrackRefsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ExternalTrackRefsTable,
    ExternalTrackRefRow,
    $$ExternalTrackRefsTableFilterComposer,
    $$ExternalTrackRefsTableOrderingComposer,
    $$ExternalTrackRefsTableAnnotationComposer,
    $$ExternalTrackRefsTableCreateCompanionBuilder,
    $$ExternalTrackRefsTableUpdateCompanionBuilder,
    (ExternalTrackRefRow, $$ExternalTrackRefsTableReferences),
    ExternalTrackRefRow,
    PrefetchHooks Function({bool trackId})> {
  $$ExternalTrackRefsTableTableManager(
      _$AppDatabase db, $ExternalTrackRefsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExternalTrackRefsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExternalTrackRefsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExternalTrackRefsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> trackId = const Value.absent(),
            Value<String> provider = const Value.absent(),
            Value<String> externalId = const Value.absent(),
            Value<String> variantKey = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<DateTime> linkedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExternalTrackRefsCompanion(
            trackId: trackId,
            provider: provider,
            externalId: externalId,
            variantKey: variantKey,
            origin: origin,
            linkedAt: linkedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int trackId,
            required String provider,
            required String externalId,
            Value<String> variantKey = const Value.absent(),
            required String origin,
            required DateTime linkedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ExternalTrackRefsCompanion.insert(
            trackId: trackId,
            provider: provider,
            externalId: externalId,
            variantKey: variantKey,
            origin: origin,
            linkedAt: linkedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ExternalTrackRefsTableReferences(db, table, e)
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
                        $$ExternalTrackRefsTableReferences._trackIdTable(db),
                    referencedColumn:
                        $$ExternalTrackRefsTableReferences._trackIdTable(db).id,
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

typedef $$ExternalTrackRefsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ExternalTrackRefsTable,
    ExternalTrackRefRow,
    $$ExternalTrackRefsTableFilterComposer,
    $$ExternalTrackRefsTableOrderingComposer,
    $$ExternalTrackRefsTableAnnotationComposer,
    $$ExternalTrackRefsTableCreateCompanionBuilder,
    $$ExternalTrackRefsTableUpdateCompanionBuilder,
    (ExternalTrackRefRow, $$ExternalTrackRefsTableReferences),
    ExternalTrackRefRow,
    PrefetchHooks Function({bool trackId})>;
typedef $$DownloadedAssetsTableCreateCompanionBuilder
    = DownloadedAssetsCompanion Function({
  Value<int> trackId,
  required String provider,
  required String externalId,
  Value<String> variantKey,
  required String source,
  required String publicationId,
  required String requestedQuality,
  required String actualQuality,
  required String container,
  required String codec,
  required int fileSizeBytes,
  required int durationMs,
  required String contentHash,
  required int verifiedAtMicros,
  required String state,
  Value<int> revision,
});
typedef $$DownloadedAssetsTableUpdateCompanionBuilder
    = DownloadedAssetsCompanion Function({
  Value<int> trackId,
  Value<String> provider,
  Value<String> externalId,
  Value<String> variantKey,
  Value<String> source,
  Value<String> publicationId,
  Value<String> requestedQuality,
  Value<String> actualQuality,
  Value<String> container,
  Value<String> codec,
  Value<int> fileSizeBytes,
  Value<int> durationMs,
  Value<String> contentHash,
  Value<int> verifiedAtMicros,
  Value<String> state,
  Value<int> revision,
});

final class $$DownloadedAssetsTableReferences extends BaseReferences<
    _$AppDatabase, $DownloadedAssetsTable, DownloadedAssetRow> {
  $$DownloadedAssetsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $TracksTable _trackIdTable(_$AppDatabase db) => db.tracks.createAlias(
      $_aliasNameGenerator(db.downloadedAssets.trackId, db.tracks.id));

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

class $$DownloadedAssetsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadedAssetsTable> {
  $$DownloadedAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get publicationId => $composableBuilder(
      column: $table.publicationId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get requestedQuality => $composableBuilder(
      column: $table.requestedQuality,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get actualQuality => $composableBuilder(
      column: $table.actualQuality, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get container => $composableBuilder(
      column: $table.container, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get codec => $composableBuilder(
      column: $table.codec, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get verifiedAtMicros => $composableBuilder(
      column: $table.verifiedAtMicros,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnFilters(column));

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

class $$DownloadedAssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadedAssetsTable> {
  $$DownloadedAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get publicationId => $composableBuilder(
      column: $table.publicationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get requestedQuality => $composableBuilder(
      column: $table.requestedQuality,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get actualQuality => $composableBuilder(
      column: $table.actualQuality,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get container => $composableBuilder(
      column: $table.container, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get codec => $composableBuilder(
      column: $table.codec, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get verifiedAtMicros => $composableBuilder(
      column: $table.verifiedAtMicros,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnOrderings(column));

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

class $$DownloadedAssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadedAssetsTable> {
  $$DownloadedAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => column);

  GeneratedColumn<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get publicationId => $composableBuilder(
      column: $table.publicationId, builder: (column) => column);

  GeneratedColumn<String> get requestedQuality => $composableBuilder(
      column: $table.requestedQuality, builder: (column) => column);

  GeneratedColumn<String> get actualQuality => $composableBuilder(
      column: $table.actualQuality, builder: (column) => column);

  GeneratedColumn<String> get container =>
      $composableBuilder(column: $table.container, builder: (column) => column);

  GeneratedColumn<String> get codec =>
      $composableBuilder(column: $table.codec, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => column);

  GeneratedColumn<int> get verifiedAtMicros => $composableBuilder(
      column: $table.verifiedAtMicros, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

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

class $$DownloadedAssetsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DownloadedAssetsTable,
    DownloadedAssetRow,
    $$DownloadedAssetsTableFilterComposer,
    $$DownloadedAssetsTableOrderingComposer,
    $$DownloadedAssetsTableAnnotationComposer,
    $$DownloadedAssetsTableCreateCompanionBuilder,
    $$DownloadedAssetsTableUpdateCompanionBuilder,
    (DownloadedAssetRow, $$DownloadedAssetsTableReferences),
    DownloadedAssetRow,
    PrefetchHooks Function({bool trackId})> {
  $$DownloadedAssetsTableTableManager(
      _$AppDatabase db, $DownloadedAssetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadedAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadedAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadedAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> trackId = const Value.absent(),
            Value<String> provider = const Value.absent(),
            Value<String> externalId = const Value.absent(),
            Value<String> variantKey = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<String> publicationId = const Value.absent(),
            Value<String> requestedQuality = const Value.absent(),
            Value<String> actualQuality = const Value.absent(),
            Value<String> container = const Value.absent(),
            Value<String> codec = const Value.absent(),
            Value<int> fileSizeBytes = const Value.absent(),
            Value<int> durationMs = const Value.absent(),
            Value<String> contentHash = const Value.absent(),
            Value<int> verifiedAtMicros = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<int> revision = const Value.absent(),
          }) =>
              DownloadedAssetsCompanion(
            trackId: trackId,
            provider: provider,
            externalId: externalId,
            variantKey: variantKey,
            source: source,
            publicationId: publicationId,
            requestedQuality: requestedQuality,
            actualQuality: actualQuality,
            container: container,
            codec: codec,
            fileSizeBytes: fileSizeBytes,
            durationMs: durationMs,
            contentHash: contentHash,
            verifiedAtMicros: verifiedAtMicros,
            state: state,
            revision: revision,
          ),
          createCompanionCallback: ({
            Value<int> trackId = const Value.absent(),
            required String provider,
            required String externalId,
            Value<String> variantKey = const Value.absent(),
            required String source,
            required String publicationId,
            required String requestedQuality,
            required String actualQuality,
            required String container,
            required String codec,
            required int fileSizeBytes,
            required int durationMs,
            required String contentHash,
            required int verifiedAtMicros,
            required String state,
            Value<int> revision = const Value.absent(),
          }) =>
              DownloadedAssetsCompanion.insert(
            trackId: trackId,
            provider: provider,
            externalId: externalId,
            variantKey: variantKey,
            source: source,
            publicationId: publicationId,
            requestedQuality: requestedQuality,
            actualQuality: actualQuality,
            container: container,
            codec: codec,
            fileSizeBytes: fileSizeBytes,
            durationMs: durationMs,
            contentHash: contentHash,
            verifiedAtMicros: verifiedAtMicros,
            state: state,
            revision: revision,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$DownloadedAssetsTableReferences(db, table, e)
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
                        $$DownloadedAssetsTableReferences._trackIdTable(db),
                    referencedColumn:
                        $$DownloadedAssetsTableReferences._trackIdTable(db).id,
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

typedef $$DownloadedAssetsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DownloadedAssetsTable,
    DownloadedAssetRow,
    $$DownloadedAssetsTableFilterComposer,
    $$DownloadedAssetsTableOrderingComposer,
    $$DownloadedAssetsTableAnnotationComposer,
    $$DownloadedAssetsTableCreateCompanionBuilder,
    $$DownloadedAssetsTableUpdateCompanionBuilder,
    (DownloadedAssetRow, $$DownloadedAssetsTableReferences),
    DownloadedAssetRow,
    PrefetchHooks Function({bool trackId})>;
typedef $$RemoteAccountsTableCreateCompanionBuilder = RemoteAccountsCompanion
    Function({
  Value<int> id,
  required String provider,
  required String accountId,
  Value<String?> displayName,
  required bool isActive,
  required int revision,
});
typedef $$RemoteAccountsTableUpdateCompanionBuilder = RemoteAccountsCompanion
    Function({
  Value<int> id,
  Value<String> provider,
  Value<String> accountId,
  Value<String?> displayName,
  Value<bool> isActive,
  Value<int> revision,
});

final class $$RemoteAccountsTableReferences extends BaseReferences<
    _$AppDatabase, $RemoteAccountsTable, RemoteAccountRow> {
  $$RemoteAccountsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$RemoteCollectionsTable, List<RemoteCollectionRow>>
      _remoteCollectionsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.remoteCollections,
              aliasName: $_aliasNameGenerator(
                  db.remoteAccounts.id, db.remoteCollections.accountId));

  $$RemoteCollectionsTableProcessedTableManager get remoteCollectionsRefs {
    final manager =
        $$RemoteCollectionsTableTableManager($_db, $_db.remoteCollections)
            .filter((f) => f.accountId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_remoteCollectionsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$DownloadJobsTable, List<DownloadJobRow>>
      _downloadJobsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.downloadJobs,
              aliasName: $_aliasNameGenerator(
                  db.remoteAccounts.id, db.downloadJobs.accountId));

  $$DownloadJobsTableProcessedTableManager get downloadJobsRefs {
    final manager = $$DownloadJobsTableTableManager($_db, $_db.downloadJobs)
        .filter((f) => f.accountId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_downloadJobsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$RemoteAccountsTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteAccountsTable> {
  $$RemoteAccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnFilters(column));

  Expression<bool> remoteCollectionsRefs(
      Expression<bool> Function($$RemoteCollectionsTableFilterComposer f) f) {
    final $$RemoteCollectionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.remoteCollections,
        getReferencedColumn: (t) => t.accountId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RemoteCollectionsTableFilterComposer(
              $db: $db,
              $table: $db.remoteCollections,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> downloadJobsRefs(
      Expression<bool> Function($$DownloadJobsTableFilterComposer f) f) {
    final $$DownloadJobsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadJobs,
        getReferencedColumn: (t) => t.accountId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadJobsTableFilterComposer(
              $db: $db,
              $table: $db.downloadJobs,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RemoteAccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteAccountsTable> {
  $$RemoteAccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnOrderings(column));
}

class $$RemoteAccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteAccountsTable> {
  $$RemoteAccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  Expression<T> remoteCollectionsRefs<T extends Object>(
      Expression<T> Function($$RemoteCollectionsTableAnnotationComposer a) f) {
    final $$RemoteCollectionsTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.remoteCollections,
            getReferencedColumn: (t) => t.accountId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$RemoteCollectionsTableAnnotationComposer(
                  $db: $db,
                  $table: $db.remoteCollections,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> downloadJobsRefs<T extends Object>(
      Expression<T> Function($$DownloadJobsTableAnnotationComposer a) f) {
    final $$DownloadJobsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadJobs,
        getReferencedColumn: (t) => t.accountId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadJobsTableAnnotationComposer(
              $db: $db,
              $table: $db.downloadJobs,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RemoteAccountsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RemoteAccountsTable,
    RemoteAccountRow,
    $$RemoteAccountsTableFilterComposer,
    $$RemoteAccountsTableOrderingComposer,
    $$RemoteAccountsTableAnnotationComposer,
    $$RemoteAccountsTableCreateCompanionBuilder,
    $$RemoteAccountsTableUpdateCompanionBuilder,
    (RemoteAccountRow, $$RemoteAccountsTableReferences),
    RemoteAccountRow,
    PrefetchHooks Function(
        {bool remoteCollectionsRefs, bool downloadJobsRefs})> {
  $$RemoteAccountsTableTableManager(
      _$AppDatabase db, $RemoteAccountsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteAccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteAccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemoteAccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> provider = const Value.absent(),
            Value<String> accountId = const Value.absent(),
            Value<String?> displayName = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int> revision = const Value.absent(),
          }) =>
              RemoteAccountsCompanion(
            id: id,
            provider: provider,
            accountId: accountId,
            displayName: displayName,
            isActive: isActive,
            revision: revision,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String provider,
            required String accountId,
            Value<String?> displayName = const Value.absent(),
            required bool isActive,
            required int revision,
          }) =>
              RemoteAccountsCompanion.insert(
            id: id,
            provider: provider,
            accountId: accountId,
            displayName: displayName,
            isActive: isActive,
            revision: revision,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$RemoteAccountsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {remoteCollectionsRefs = false, downloadJobsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (remoteCollectionsRefs) db.remoteCollections,
                if (downloadJobsRefs) db.downloadJobs
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (remoteCollectionsRefs)
                    await $_getPrefetchedData<RemoteAccountRow,
                            $RemoteAccountsTable, RemoteCollectionRow>(
                        currentTable: table,
                        referencedTable: $$RemoteAccountsTableReferences
                            ._remoteCollectionsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RemoteAccountsTableReferences(db, table, p0)
                                .remoteCollectionsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.accountId == item.id),
                        typedResults: items),
                  if (downloadJobsRefs)
                    await $_getPrefetchedData<RemoteAccountRow,
                            $RemoteAccountsTable, DownloadJobRow>(
                        currentTable: table,
                        referencedTable: $$RemoteAccountsTableReferences
                            ._downloadJobsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RemoteAccountsTableReferences(db, table, p0)
                                .downloadJobsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.accountId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$RemoteAccountsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RemoteAccountsTable,
    RemoteAccountRow,
    $$RemoteAccountsTableFilterComposer,
    $$RemoteAccountsTableOrderingComposer,
    $$RemoteAccountsTableAnnotationComposer,
    $$RemoteAccountsTableCreateCompanionBuilder,
    $$RemoteAccountsTableUpdateCompanionBuilder,
    (RemoteAccountRow, $$RemoteAccountsTableReferences),
    RemoteAccountRow,
    PrefetchHooks Function(
        {bool remoteCollectionsRefs, bool downloadJobsRefs})>;
typedef $$RemoteCollectionsTableCreateCompanionBuilder
    = RemoteCollectionsCompanion Function({
  Value<int> id,
  required int accountId,
  required String kind,
  required String externalId,
  required String ownerId,
  Value<String?> title,
  required bool isSelected,
  required int revision,
  Value<int> itemCount,
  Value<String?> remoteRevision,
  Value<int?> completedAtMicros,
});
typedef $$RemoteCollectionsTableUpdateCompanionBuilder
    = RemoteCollectionsCompanion Function({
  Value<int> id,
  Value<int> accountId,
  Value<String> kind,
  Value<String> externalId,
  Value<String> ownerId,
  Value<String?> title,
  Value<bool> isSelected,
  Value<int> revision,
  Value<int> itemCount,
  Value<String?> remoteRevision,
  Value<int?> completedAtMicros,
});

final class $$RemoteCollectionsTableReferences extends BaseReferences<
    _$AppDatabase, $RemoteCollectionsTable, RemoteCollectionRow> {
  $$RemoteCollectionsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $RemoteAccountsTable _accountIdTable(_$AppDatabase db) =>
      db.remoteAccounts.createAlias($_aliasNameGenerator(
          db.remoteCollections.accountId, db.remoteAccounts.id));

  $$RemoteAccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<int>('account_id')!;

    final manager = $$RemoteAccountsTableTableManager($_db, $_db.remoteAccounts)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$RemoteCollectionItemsTable,
      List<RemoteCollectionItemRow>> _remoteCollectionItemsRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.remoteCollectionItems,
          aliasName: $_aliasNameGenerator(
              db.remoteCollections.id, db.remoteCollectionItems.collectionId));

  $$RemoteCollectionItemsTableProcessedTableManager
      get remoteCollectionItemsRefs {
    final manager = $$RemoteCollectionItemsTableTableManager(
            $_db, $_db.remoteCollectionItems)
        .filter((f) => f.collectionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_remoteCollectionItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$RemoteCollectionsTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteCollectionsTable> {
  $$RemoteCollectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSelected => $composableBuilder(
      column: $table.isSelected, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get itemCount => $composableBuilder(
      column: $table.itemCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get remoteRevision => $composableBuilder(
      column: $table.remoteRevision,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get completedAtMicros => $composableBuilder(
      column: $table.completedAtMicros,
      builder: (column) => ColumnFilters(column));

  $$RemoteAccountsTableFilterComposer get accountId {
    final $$RemoteAccountsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.accountId,
        referencedTable: $db.remoteAccounts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RemoteAccountsTableFilterComposer(
              $db: $db,
              $table: $db.remoteAccounts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> remoteCollectionItemsRefs(
      Expression<bool> Function($$RemoteCollectionItemsTableFilterComposer f)
          f) {
    final $$RemoteCollectionItemsTableFilterComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.remoteCollectionItems,
            getReferencedColumn: (t) => t.collectionId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$RemoteCollectionItemsTableFilterComposer(
                  $db: $db,
                  $table: $db.remoteCollectionItems,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$RemoteCollectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteCollectionsTable> {
  $$RemoteCollectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSelected => $composableBuilder(
      column: $table.isSelected, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get itemCount => $composableBuilder(
      column: $table.itemCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get remoteRevision => $composableBuilder(
      column: $table.remoteRevision,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get completedAtMicros => $composableBuilder(
      column: $table.completedAtMicros,
      builder: (column) => ColumnOrderings(column));

  $$RemoteAccountsTableOrderingComposer get accountId {
    final $$RemoteAccountsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.accountId,
        referencedTable: $db.remoteAccounts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RemoteAccountsTableOrderingComposer(
              $db: $db,
              $table: $db.remoteAccounts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RemoteCollectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteCollectionsTable> {
  $$RemoteCollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get isSelected => $composableBuilder(
      column: $table.isSelected, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get itemCount =>
      $composableBuilder(column: $table.itemCount, builder: (column) => column);

  GeneratedColumn<String> get remoteRevision => $composableBuilder(
      column: $table.remoteRevision, builder: (column) => column);

  GeneratedColumn<int> get completedAtMicros => $composableBuilder(
      column: $table.completedAtMicros, builder: (column) => column);

  $$RemoteAccountsTableAnnotationComposer get accountId {
    final $$RemoteAccountsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.accountId,
        referencedTable: $db.remoteAccounts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RemoteAccountsTableAnnotationComposer(
              $db: $db,
              $table: $db.remoteAccounts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> remoteCollectionItemsRefs<T extends Object>(
      Expression<T> Function($$RemoteCollectionItemsTableAnnotationComposer a)
          f) {
    final $$RemoteCollectionItemsTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.remoteCollectionItems,
            getReferencedColumn: (t) => t.collectionId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$RemoteCollectionItemsTableAnnotationComposer(
                  $db: $db,
                  $table: $db.remoteCollectionItems,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$RemoteCollectionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RemoteCollectionsTable,
    RemoteCollectionRow,
    $$RemoteCollectionsTableFilterComposer,
    $$RemoteCollectionsTableOrderingComposer,
    $$RemoteCollectionsTableAnnotationComposer,
    $$RemoteCollectionsTableCreateCompanionBuilder,
    $$RemoteCollectionsTableUpdateCompanionBuilder,
    (RemoteCollectionRow, $$RemoteCollectionsTableReferences),
    RemoteCollectionRow,
    PrefetchHooks Function({bool accountId, bool remoteCollectionItemsRefs})> {
  $$RemoteCollectionsTableTableManager(
      _$AppDatabase db, $RemoteCollectionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteCollectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteCollectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemoteCollectionsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> accountId = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> externalId = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<bool> isSelected = const Value.absent(),
            Value<int> revision = const Value.absent(),
            Value<int> itemCount = const Value.absent(),
            Value<String?> remoteRevision = const Value.absent(),
            Value<int?> completedAtMicros = const Value.absent(),
          }) =>
              RemoteCollectionsCompanion(
            id: id,
            accountId: accountId,
            kind: kind,
            externalId: externalId,
            ownerId: ownerId,
            title: title,
            isSelected: isSelected,
            revision: revision,
            itemCount: itemCount,
            remoteRevision: remoteRevision,
            completedAtMicros: completedAtMicros,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int accountId,
            required String kind,
            required String externalId,
            required String ownerId,
            Value<String?> title = const Value.absent(),
            required bool isSelected,
            required int revision,
            Value<int> itemCount = const Value.absent(),
            Value<String?> remoteRevision = const Value.absent(),
            Value<int?> completedAtMicros = const Value.absent(),
          }) =>
              RemoteCollectionsCompanion.insert(
            id: id,
            accountId: accountId,
            kind: kind,
            externalId: externalId,
            ownerId: ownerId,
            title: title,
            isSelected: isSelected,
            revision: revision,
            itemCount: itemCount,
            remoteRevision: remoteRevision,
            completedAtMicros: completedAtMicros,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$RemoteCollectionsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {accountId = false, remoteCollectionItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (remoteCollectionItemsRefs) db.remoteCollectionItems
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
                if (accountId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.accountId,
                    referencedTable:
                        $$RemoteCollectionsTableReferences._accountIdTable(db),
                    referencedColumn: $$RemoteCollectionsTableReferences
                        ._accountIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (remoteCollectionItemsRefs)
                    await $_getPrefetchedData<RemoteCollectionRow,
                            $RemoteCollectionsTable, RemoteCollectionItemRow>(
                        currentTable: table,
                        referencedTable: $$RemoteCollectionsTableReferences
                            ._remoteCollectionItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RemoteCollectionsTableReferences(db, table, p0)
                                .remoteCollectionItemsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.collectionId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$RemoteCollectionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RemoteCollectionsTable,
    RemoteCollectionRow,
    $$RemoteCollectionsTableFilterComposer,
    $$RemoteCollectionsTableOrderingComposer,
    $$RemoteCollectionsTableAnnotationComposer,
    $$RemoteCollectionsTableCreateCompanionBuilder,
    $$RemoteCollectionsTableUpdateCompanionBuilder,
    (RemoteCollectionRow, $$RemoteCollectionsTableReferences),
    RemoteCollectionRow,
    PrefetchHooks Function({bool accountId, bool remoteCollectionItemsRefs})>;
typedef $$RemoteCollectionItemsTableCreateCompanionBuilder
    = RemoteCollectionItemsCompanion Function({
  required int collectionId,
  required int position,
  required String externalId,
  required String variantKey,
  Value<int> rowid,
});
typedef $$RemoteCollectionItemsTableUpdateCompanionBuilder
    = RemoteCollectionItemsCompanion Function({
  Value<int> collectionId,
  Value<int> position,
  Value<String> externalId,
  Value<String> variantKey,
  Value<int> rowid,
});

final class $$RemoteCollectionItemsTableReferences extends BaseReferences<
    _$AppDatabase, $RemoteCollectionItemsTable, RemoteCollectionItemRow> {
  $$RemoteCollectionItemsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $RemoteCollectionsTable _collectionIdTable(_$AppDatabase db) =>
      db.remoteCollections.createAlias($_aliasNameGenerator(
          db.remoteCollectionItems.collectionId, db.remoteCollections.id));

  $$RemoteCollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<int>('collection_id')!;

    final manager =
        $$RemoteCollectionsTableTableManager($_db, $_db.remoteCollections)
            .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$RemoteCollectionItemsTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteCollectionItemsTable> {
  $$RemoteCollectionItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => ColumnFilters(column));

  $$RemoteCollectionsTableFilterComposer get collectionId {
    final $$RemoteCollectionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.collectionId,
        referencedTable: $db.remoteCollections,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RemoteCollectionsTableFilterComposer(
              $db: $db,
              $table: $db.remoteCollections,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RemoteCollectionItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteCollectionItemsTable> {
  $$RemoteCollectionItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => ColumnOrderings(column));

  $$RemoteCollectionsTableOrderingComposer get collectionId {
    final $$RemoteCollectionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.collectionId,
        referencedTable: $db.remoteCollections,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RemoteCollectionsTableOrderingComposer(
              $db: $db,
              $table: $db.remoteCollections,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RemoteCollectionItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteCollectionItemsTable> {
  $$RemoteCollectionItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => column);

  GeneratedColumn<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => column);

  $$RemoteCollectionsTableAnnotationComposer get collectionId {
    final $$RemoteCollectionsTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.collectionId,
            referencedTable: $db.remoteCollections,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$RemoteCollectionsTableAnnotationComposer(
                  $db: $db,
                  $table: $db.remoteCollections,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return composer;
  }
}

class $$RemoteCollectionItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RemoteCollectionItemsTable,
    RemoteCollectionItemRow,
    $$RemoteCollectionItemsTableFilterComposer,
    $$RemoteCollectionItemsTableOrderingComposer,
    $$RemoteCollectionItemsTableAnnotationComposer,
    $$RemoteCollectionItemsTableCreateCompanionBuilder,
    $$RemoteCollectionItemsTableUpdateCompanionBuilder,
    (RemoteCollectionItemRow, $$RemoteCollectionItemsTableReferences),
    RemoteCollectionItemRow,
    PrefetchHooks Function({bool collectionId})> {
  $$RemoteCollectionItemsTableTableManager(
      _$AppDatabase db, $RemoteCollectionItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteCollectionItemsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteCollectionItemsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemoteCollectionItemsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> collectionId = const Value.absent(),
            Value<int> position = const Value.absent(),
            Value<String> externalId = const Value.absent(),
            Value<String> variantKey = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RemoteCollectionItemsCompanion(
            collectionId: collectionId,
            position: position,
            externalId: externalId,
            variantKey: variantKey,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int collectionId,
            required int position,
            required String externalId,
            required String variantKey,
            Value<int> rowid = const Value.absent(),
          }) =>
              RemoteCollectionItemsCompanion.insert(
            collectionId: collectionId,
            position: position,
            externalId: externalId,
            variantKey: variantKey,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$RemoteCollectionItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({collectionId = false}) {
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
                if (collectionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.collectionId,
                    referencedTable: $$RemoteCollectionItemsTableReferences
                        ._collectionIdTable(db),
                    referencedColumn: $$RemoteCollectionItemsTableReferences
                        ._collectionIdTable(db)
                        .id,
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

typedef $$RemoteCollectionItemsTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $RemoteCollectionItemsTable,
        RemoteCollectionItemRow,
        $$RemoteCollectionItemsTableFilterComposer,
        $$RemoteCollectionItemsTableOrderingComposer,
        $$RemoteCollectionItemsTableAnnotationComposer,
        $$RemoteCollectionItemsTableCreateCompanionBuilder,
        $$RemoteCollectionItemsTableUpdateCompanionBuilder,
        (RemoteCollectionItemRow, $$RemoteCollectionItemsTableReferences),
        RemoteCollectionItemRow,
        PrefetchHooks Function({bool collectionId})>;
typedef $$DownloadJobsTableCreateCompanionBuilder = DownloadJobsCompanion
    Function({
  Value<int> id,
  required int libraryFolderId,
  required String provider,
  required String externalId,
  required String variantKey,
  required String quality,
  required int accountId,
  required int accountRevision,
  required String state,
  required String stage,
  required int revision,
  Value<int> attemptCount,
  required int maxAttempts,
  required int remainingAttempts,
  Value<String?> attemptToken,
  Value<int?> leaseUntilMicros,
  Value<int?> retryAtMicros,
  Value<String?> failure,
  Value<int?> completedTrackId,
  required int createdAtMicros,
  required int updatedAtMicros,
});
typedef $$DownloadJobsTableUpdateCompanionBuilder = DownloadJobsCompanion
    Function({
  Value<int> id,
  Value<int> libraryFolderId,
  Value<String> provider,
  Value<String> externalId,
  Value<String> variantKey,
  Value<String> quality,
  Value<int> accountId,
  Value<int> accountRevision,
  Value<String> state,
  Value<String> stage,
  Value<int> revision,
  Value<int> attemptCount,
  Value<int> maxAttempts,
  Value<int> remainingAttempts,
  Value<String?> attemptToken,
  Value<int?> leaseUntilMicros,
  Value<int?> retryAtMicros,
  Value<String?> failure,
  Value<int?> completedTrackId,
  Value<int> createdAtMicros,
  Value<int> updatedAtMicros,
});

final class $$DownloadJobsTableReferences
    extends BaseReferences<_$AppDatabase, $DownloadJobsTable, DownloadJobRow> {
  $$DownloadJobsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LibraryFoldersTable _libraryFolderIdTable(_$AppDatabase db) =>
      db.libraryFolders.createAlias($_aliasNameGenerator(
          db.downloadJobs.libraryFolderId, db.libraryFolders.id));

  $$LibraryFoldersTableProcessedTableManager get libraryFolderId {
    final $_column = $_itemColumn<int>('library_folder_id')!;

    final manager = $$LibraryFoldersTableTableManager($_db, $_db.libraryFolders)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_libraryFolderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $RemoteAccountsTable _accountIdTable(_$AppDatabase db) =>
      db.remoteAccounts.createAlias($_aliasNameGenerator(
          db.downloadJobs.accountId, db.remoteAccounts.id));

  $$RemoteAccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<int>('account_id')!;

    final manager = $$RemoteAccountsTableTableManager($_db, $_db.remoteAccounts)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$DownloadAttemptsTable, List<DownloadAttemptRow>>
      _downloadAttemptsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.downloadAttempts,
              aliasName: $_aliasNameGenerator(
                  db.downloadJobs.id, db.downloadAttempts.jobId));

  $$DownloadAttemptsTableProcessedTableManager get downloadAttemptsRefs {
    final manager =
        $$DownloadAttemptsTableTableManager($_db, $_db.downloadAttempts)
            .filter((f) => f.jobId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_downloadAttemptsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$DownloadJobsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadJobsTable> {
  $$DownloadJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get quality => $composableBuilder(
      column: $table.quality, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get accountRevision => $composableBuilder(
      column: $table.accountRevision,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get stage => $composableBuilder(
      column: $table.stage, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxAttempts => $composableBuilder(
      column: $table.maxAttempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remainingAttempts => $composableBuilder(
      column: $table.remainingAttempts,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get attemptToken => $composableBuilder(
      column: $table.attemptToken, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get leaseUntilMicros => $composableBuilder(
      column: $table.leaseUntilMicros,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryAtMicros => $composableBuilder(
      column: $table.retryAtMicros, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get failure => $composableBuilder(
      column: $table.failure, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get completedTrackId => $composableBuilder(
      column: $table.completedTrackId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
      column: $table.createdAtMicros,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
      column: $table.updatedAtMicros,
      builder: (column) => ColumnFilters(column));

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

  $$RemoteAccountsTableFilterComposer get accountId {
    final $$RemoteAccountsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.accountId,
        referencedTable: $db.remoteAccounts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RemoteAccountsTableFilterComposer(
              $db: $db,
              $table: $db.remoteAccounts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> downloadAttemptsRefs(
      Expression<bool> Function($$DownloadAttemptsTableFilterComposer f) f) {
    final $$DownloadAttemptsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadAttempts,
        getReferencedColumn: (t) => t.jobId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadAttemptsTableFilterComposer(
              $db: $db,
              $table: $db.downloadAttempts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$DownloadJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadJobsTable> {
  $$DownloadJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get quality => $composableBuilder(
      column: $table.quality, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get accountRevision => $composableBuilder(
      column: $table.accountRevision,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get stage => $composableBuilder(
      column: $table.stage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxAttempts => $composableBuilder(
      column: $table.maxAttempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remainingAttempts => $composableBuilder(
      column: $table.remainingAttempts,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get attemptToken => $composableBuilder(
      column: $table.attemptToken,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get leaseUntilMicros => $composableBuilder(
      column: $table.leaseUntilMicros,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryAtMicros => $composableBuilder(
      column: $table.retryAtMicros,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get failure => $composableBuilder(
      column: $table.failure, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get completedTrackId => $composableBuilder(
      column: $table.completedTrackId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
      column: $table.createdAtMicros,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
      column: $table.updatedAtMicros,
      builder: (column) => ColumnOrderings(column));

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

  $$RemoteAccountsTableOrderingComposer get accountId {
    final $$RemoteAccountsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.accountId,
        referencedTable: $db.remoteAccounts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RemoteAccountsTableOrderingComposer(
              $db: $db,
              $table: $db.remoteAccounts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DownloadJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadJobsTable> {
  $$DownloadJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => column);

  GeneratedColumn<String> get variantKey => $composableBuilder(
      column: $table.variantKey, builder: (column) => column);

  GeneratedColumn<String> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<int> get accountRevision => $composableBuilder(
      column: $table.accountRevision, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => column);

  GeneratedColumn<int> get maxAttempts => $composableBuilder(
      column: $table.maxAttempts, builder: (column) => column);

  GeneratedColumn<int> get remainingAttempts => $composableBuilder(
      column: $table.remainingAttempts, builder: (column) => column);

  GeneratedColumn<String> get attemptToken => $composableBuilder(
      column: $table.attemptToken, builder: (column) => column);

  GeneratedColumn<int> get leaseUntilMicros => $composableBuilder(
      column: $table.leaseUntilMicros, builder: (column) => column);

  GeneratedColumn<int> get retryAtMicros => $composableBuilder(
      column: $table.retryAtMicros, builder: (column) => column);

  GeneratedColumn<String> get failure =>
      $composableBuilder(column: $table.failure, builder: (column) => column);

  GeneratedColumn<int> get completedTrackId => $composableBuilder(
      column: $table.completedTrackId, builder: (column) => column);

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
      column: $table.createdAtMicros, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
      column: $table.updatedAtMicros, builder: (column) => column);

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

  $$RemoteAccountsTableAnnotationComposer get accountId {
    final $$RemoteAccountsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.accountId,
        referencedTable: $db.remoteAccounts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RemoteAccountsTableAnnotationComposer(
              $db: $db,
              $table: $db.remoteAccounts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> downloadAttemptsRefs<T extends Object>(
      Expression<T> Function($$DownloadAttemptsTableAnnotationComposer a) f) {
    final $$DownloadAttemptsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadAttempts,
        getReferencedColumn: (t) => t.jobId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadAttemptsTableAnnotationComposer(
              $db: $db,
              $table: $db.downloadAttempts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$DownloadJobsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DownloadJobsTable,
    DownloadJobRow,
    $$DownloadJobsTableFilterComposer,
    $$DownloadJobsTableOrderingComposer,
    $$DownloadJobsTableAnnotationComposer,
    $$DownloadJobsTableCreateCompanionBuilder,
    $$DownloadJobsTableUpdateCompanionBuilder,
    (DownloadJobRow, $$DownloadJobsTableReferences),
    DownloadJobRow,
    PrefetchHooks Function(
        {bool libraryFolderId, bool accountId, bool downloadAttemptsRefs})> {
  $$DownloadJobsTableTableManager(_$AppDatabase db, $DownloadJobsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> libraryFolderId = const Value.absent(),
            Value<String> provider = const Value.absent(),
            Value<String> externalId = const Value.absent(),
            Value<String> variantKey = const Value.absent(),
            Value<String> quality = const Value.absent(),
            Value<int> accountId = const Value.absent(),
            Value<int> accountRevision = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<String> stage = const Value.absent(),
            Value<int> revision = const Value.absent(),
            Value<int> attemptCount = const Value.absent(),
            Value<int> maxAttempts = const Value.absent(),
            Value<int> remainingAttempts = const Value.absent(),
            Value<String?> attemptToken = const Value.absent(),
            Value<int?> leaseUntilMicros = const Value.absent(),
            Value<int?> retryAtMicros = const Value.absent(),
            Value<String?> failure = const Value.absent(),
            Value<int?> completedTrackId = const Value.absent(),
            Value<int> createdAtMicros = const Value.absent(),
            Value<int> updatedAtMicros = const Value.absent(),
          }) =>
              DownloadJobsCompanion(
            id: id,
            libraryFolderId: libraryFolderId,
            provider: provider,
            externalId: externalId,
            variantKey: variantKey,
            quality: quality,
            accountId: accountId,
            accountRevision: accountRevision,
            state: state,
            stage: stage,
            revision: revision,
            attemptCount: attemptCount,
            maxAttempts: maxAttempts,
            remainingAttempts: remainingAttempts,
            attemptToken: attemptToken,
            leaseUntilMicros: leaseUntilMicros,
            retryAtMicros: retryAtMicros,
            failure: failure,
            completedTrackId: completedTrackId,
            createdAtMicros: createdAtMicros,
            updatedAtMicros: updatedAtMicros,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int libraryFolderId,
            required String provider,
            required String externalId,
            required String variantKey,
            required String quality,
            required int accountId,
            required int accountRevision,
            required String state,
            required String stage,
            required int revision,
            Value<int> attemptCount = const Value.absent(),
            required int maxAttempts,
            required int remainingAttempts,
            Value<String?> attemptToken = const Value.absent(),
            Value<int?> leaseUntilMicros = const Value.absent(),
            Value<int?> retryAtMicros = const Value.absent(),
            Value<String?> failure = const Value.absent(),
            Value<int?> completedTrackId = const Value.absent(),
            required int createdAtMicros,
            required int updatedAtMicros,
          }) =>
              DownloadJobsCompanion.insert(
            id: id,
            libraryFolderId: libraryFolderId,
            provider: provider,
            externalId: externalId,
            variantKey: variantKey,
            quality: quality,
            accountId: accountId,
            accountRevision: accountRevision,
            state: state,
            stage: stage,
            revision: revision,
            attemptCount: attemptCount,
            maxAttempts: maxAttempts,
            remainingAttempts: remainingAttempts,
            attemptToken: attemptToken,
            leaseUntilMicros: leaseUntilMicros,
            retryAtMicros: retryAtMicros,
            failure: failure,
            completedTrackId: completedTrackId,
            createdAtMicros: createdAtMicros,
            updatedAtMicros: updatedAtMicros,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$DownloadJobsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {libraryFolderId = false,
              accountId = false,
              downloadAttemptsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (downloadAttemptsRefs) db.downloadAttempts
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
                        $$DownloadJobsTableReferences._libraryFolderIdTable(db),
                    referencedColumn: $$DownloadJobsTableReferences
                        ._libraryFolderIdTable(db)
                        .id,
                  ) as T;
                }
                if (accountId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.accountId,
                    referencedTable:
                        $$DownloadJobsTableReferences._accountIdTable(db),
                    referencedColumn:
                        $$DownloadJobsTableReferences._accountIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (downloadAttemptsRefs)
                    await $_getPrefetchedData<DownloadJobRow,
                            $DownloadJobsTable, DownloadAttemptRow>(
                        currentTable: table,
                        referencedTable: $$DownloadJobsTableReferences
                            ._downloadAttemptsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$DownloadJobsTableReferences(db, table, p0)
                                .downloadAttemptsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.jobId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$DownloadJobsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DownloadJobsTable,
    DownloadJobRow,
    $$DownloadJobsTableFilterComposer,
    $$DownloadJobsTableOrderingComposer,
    $$DownloadJobsTableAnnotationComposer,
    $$DownloadJobsTableCreateCompanionBuilder,
    $$DownloadJobsTableUpdateCompanionBuilder,
    (DownloadJobRow, $$DownloadJobsTableReferences),
    DownloadJobRow,
    PrefetchHooks Function(
        {bool libraryFolderId, bool accountId, bool downloadAttemptsRefs})>;
typedef $$DownloadAttemptsTableCreateCompanionBuilder
    = DownloadAttemptsCompanion Function({
  required int jobId,
  required int number,
  required String token,
  required int accountId,
  required int accountRevision,
  required String stage,
  required String outcome,
  required int startedAtMicros,
  Value<int?> finishedAtMicros,
  Value<String?> failure,
  Value<int> rowid,
});
typedef $$DownloadAttemptsTableUpdateCompanionBuilder
    = DownloadAttemptsCompanion Function({
  Value<int> jobId,
  Value<int> number,
  Value<String> token,
  Value<int> accountId,
  Value<int> accountRevision,
  Value<String> stage,
  Value<String> outcome,
  Value<int> startedAtMicros,
  Value<int?> finishedAtMicros,
  Value<String?> failure,
  Value<int> rowid,
});

final class $$DownloadAttemptsTableReferences extends BaseReferences<
    _$AppDatabase, $DownloadAttemptsTable, DownloadAttemptRow> {
  $$DownloadAttemptsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $DownloadJobsTable _jobIdTable(_$AppDatabase db) =>
      db.downloadJobs.createAlias(
          $_aliasNameGenerator(db.downloadAttempts.jobId, db.downloadJobs.id));

  $$DownloadJobsTableProcessedTableManager get jobId {
    final $_column = $_itemColumn<int>('job_id')!;

    final manager = $$DownloadJobsTableTableManager($_db, $_db.downloadJobs)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_jobIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$DownloadAttemptsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadAttemptsTable> {
  $$DownloadAttemptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get number => $composableBuilder(
      column: $table.number, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get token => $composableBuilder(
      column: $table.token, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get accountRevision => $composableBuilder(
      column: $table.accountRevision,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get stage => $composableBuilder(
      column: $table.stage, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get outcome => $composableBuilder(
      column: $table.outcome, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startedAtMicros => $composableBuilder(
      column: $table.startedAtMicros,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get finishedAtMicros => $composableBuilder(
      column: $table.finishedAtMicros,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get failure => $composableBuilder(
      column: $table.failure, builder: (column) => ColumnFilters(column));

  $$DownloadJobsTableFilterComposer get jobId {
    final $$DownloadJobsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.jobId,
        referencedTable: $db.downloadJobs,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadJobsTableFilterComposer(
              $db: $db,
              $table: $db.downloadJobs,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DownloadAttemptsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadAttemptsTable> {
  $$DownloadAttemptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get number => $composableBuilder(
      column: $table.number, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get token => $composableBuilder(
      column: $table.token, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get accountRevision => $composableBuilder(
      column: $table.accountRevision,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get stage => $composableBuilder(
      column: $table.stage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get outcome => $composableBuilder(
      column: $table.outcome, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startedAtMicros => $composableBuilder(
      column: $table.startedAtMicros,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get finishedAtMicros => $composableBuilder(
      column: $table.finishedAtMicros,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get failure => $composableBuilder(
      column: $table.failure, builder: (column) => ColumnOrderings(column));

  $$DownloadJobsTableOrderingComposer get jobId {
    final $$DownloadJobsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.jobId,
        referencedTable: $db.downloadJobs,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadJobsTableOrderingComposer(
              $db: $db,
              $table: $db.downloadJobs,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DownloadAttemptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadAttemptsTable> {
  $$DownloadAttemptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get token =>
      $composableBuilder(column: $table.token, builder: (column) => column);

  GeneratedColumn<int> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get accountRevision => $composableBuilder(
      column: $table.accountRevision, builder: (column) => column);

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<int> get startedAtMicros => $composableBuilder(
      column: $table.startedAtMicros, builder: (column) => column);

  GeneratedColumn<int> get finishedAtMicros => $composableBuilder(
      column: $table.finishedAtMicros, builder: (column) => column);

  GeneratedColumn<String> get failure =>
      $composableBuilder(column: $table.failure, builder: (column) => column);

  $$DownloadJobsTableAnnotationComposer get jobId {
    final $$DownloadJobsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.jobId,
        referencedTable: $db.downloadJobs,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadJobsTableAnnotationComposer(
              $db: $db,
              $table: $db.downloadJobs,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DownloadAttemptsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DownloadAttemptsTable,
    DownloadAttemptRow,
    $$DownloadAttemptsTableFilterComposer,
    $$DownloadAttemptsTableOrderingComposer,
    $$DownloadAttemptsTableAnnotationComposer,
    $$DownloadAttemptsTableCreateCompanionBuilder,
    $$DownloadAttemptsTableUpdateCompanionBuilder,
    (DownloadAttemptRow, $$DownloadAttemptsTableReferences),
    DownloadAttemptRow,
    PrefetchHooks Function({bool jobId})> {
  $$DownloadAttemptsTableTableManager(
      _$AppDatabase db, $DownloadAttemptsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadAttemptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadAttemptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadAttemptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> jobId = const Value.absent(),
            Value<int> number = const Value.absent(),
            Value<String> token = const Value.absent(),
            Value<int> accountId = const Value.absent(),
            Value<int> accountRevision = const Value.absent(),
            Value<String> stage = const Value.absent(),
            Value<String> outcome = const Value.absent(),
            Value<int> startedAtMicros = const Value.absent(),
            Value<int?> finishedAtMicros = const Value.absent(),
            Value<String?> failure = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DownloadAttemptsCompanion(
            jobId: jobId,
            number: number,
            token: token,
            accountId: accountId,
            accountRevision: accountRevision,
            stage: stage,
            outcome: outcome,
            startedAtMicros: startedAtMicros,
            finishedAtMicros: finishedAtMicros,
            failure: failure,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int jobId,
            required int number,
            required String token,
            required int accountId,
            required int accountRevision,
            required String stage,
            required String outcome,
            required int startedAtMicros,
            Value<int?> finishedAtMicros = const Value.absent(),
            Value<String?> failure = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DownloadAttemptsCompanion.insert(
            jobId: jobId,
            number: number,
            token: token,
            accountId: accountId,
            accountRevision: accountRevision,
            stage: stage,
            outcome: outcome,
            startedAtMicros: startedAtMicros,
            finishedAtMicros: finishedAtMicros,
            failure: failure,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$DownloadAttemptsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({jobId = false}) {
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
                if (jobId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.jobId,
                    referencedTable:
                        $$DownloadAttemptsTableReferences._jobIdTable(db),
                    referencedColumn:
                        $$DownloadAttemptsTableReferences._jobIdTable(db).id,
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

typedef $$DownloadAttemptsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DownloadAttemptsTable,
    DownloadAttemptRow,
    $$DownloadAttemptsTableFilterComposer,
    $$DownloadAttemptsTableOrderingComposer,
    $$DownloadAttemptsTableAnnotationComposer,
    $$DownloadAttemptsTableCreateCompanionBuilder,
    $$DownloadAttemptsTableUpdateCompanionBuilder,
    (DownloadAttemptRow, $$DownloadAttemptsTableReferences),
    DownloadAttemptRow,
    PrefetchHooks Function({bool jobId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LibraryFoldersTableTableManager get libraryFolders =>
      $$LibraryFoldersTableTableManager(_db, _db.libraryFolders);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$PlaylistTracksTableTableManager get playlistTracks =>
      $$PlaylistTracksTableTableManager(_db, _db.playlistTracks);
  $$PlaybackEventsTableTableManager get playbackEvents =>
      $$PlaybackEventsTableTableManager(_db, _db.playbackEvents);
  $$TrackUserStatesTableTableManager get trackUserStates =>
      $$TrackUserStatesTableTableManager(_db, _db.trackUserStates);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$ExternalTrackRefsTableTableManager get externalTrackRefs =>
      $$ExternalTrackRefsTableTableManager(_db, _db.externalTrackRefs);
  $$DownloadedAssetsTableTableManager get downloadedAssets =>
      $$DownloadedAssetsTableTableManager(_db, _db.downloadedAssets);
  $$RemoteAccountsTableTableManager get remoteAccounts =>
      $$RemoteAccountsTableTableManager(_db, _db.remoteAccounts);
  $$RemoteCollectionsTableTableManager get remoteCollections =>
      $$RemoteCollectionsTableTableManager(_db, _db.remoteCollections);
  $$RemoteCollectionItemsTableTableManager get remoteCollectionItems =>
      $$RemoteCollectionItemsTableTableManager(_db, _db.remoteCollectionItems);
  $$DownloadJobsTableTableManager get downloadJobs =>
      $$DownloadJobsTableTableManager(_db, _db.downloadJobs);
  $$DownloadAttemptsTableTableManager get downloadAttempts =>
      $$DownloadAttemptsTableTableManager(_db, _db.downloadAttempts);
}
