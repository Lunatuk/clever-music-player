import 'dart:io';
import 'package:clever_music_player/src/diagnostics/diagnostics_service.dart';

final class RecordingDiagnostics implements DiagnosticsService {
  final entries =
      <({DiagnosticEvent event, Map<DiagnosticField, Object?> fields})>[];
  @override
  void record(DiagnosticEvent event,
      {Map<DiagnosticField, Object?> fields = const {}, Object? error}) {
    entries.add((event: event, fields: Map.unmodifiable(fields)));
  }

  @override
  Future<void> flush() async {}
  @override
  Future<Directory> directory() => throw UnsupportedError('Memory fixture');
  @override
  Future<File> exportReport() => throw UnsupportedError('Memory fixture');
}
