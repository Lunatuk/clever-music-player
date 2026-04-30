import 'package:flutter/material.dart';

import '../../app/dependency_scope.dart';
import '../../domain/models/models.dart';

final class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clever Music Player'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Local-first music intelligence',
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Desktop architecture is wired and ready for library scanning.',
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ArchitectureChip(
                    label: 'Drift SQLite',
                    isReady: dependencies.database.schemaVersion == 1,
                  ),
                  const _ArchitectureChip(
                    label: 'Repositories',
                    isReady: true,
                  ),
                  const _ArchitectureChip(
                    label: 'Recommendations',
                    isReady: true,
                  ),
                  const _ArchitectureChip(
                    label: 'Playback pending',
                    isReady: false,
                  ),
                  const _ArchitectureChip(
                    label: 'Scanning pending',
                    isReady: false,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              FutureBuilder<List<Track>>(
                future: dependencies.repositories.tracks.listTracks(limit: 5),
                builder: (context, snapshot) {
                  final trackCount = snapshot.data?.length ?? 0;
                  return Text(
                    'Indexed tracks visible to UI: $trackCount',
                    style: textTheme.titleMedium,
                  );
                },
              ),
              const Spacer(),
              Text(
                'Next: library folder scanning.',
                style: textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ArchitectureChip extends StatelessWidget {
  const _ArchitectureChip({
    required this.label,
    required this.isReady,
  });

  final String label;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor =
        isReady ? colorScheme.primaryContainer : colorScheme.surfaceContainer;
    final foregroundColor =
        isReady ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant;

    return Chip(
      avatar: Icon(
        isReady ? Icons.check_circle_outline : Icons.pending_outlined,
        size: 18,
        color: foregroundColor,
      ),
      label: Text(label),
      backgroundColor: backgroundColor,
      labelStyle: TextStyle(color: foregroundColor),
      side: BorderSide.none,
    );
  }
}
