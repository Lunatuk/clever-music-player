import '../domain/models/models.dart';
import '../domain/repositories/settings_repository.dart';
import '../library/library_scan_control.dart';
import 'android_download_folders.dart';
import 'android_download_storage_controller.dart';

/// Recheck the saved destination and its live grants before planning/network.
/// A crash halfway through changing the folder must not select the old target.
final class AndroidYandexDestinationGuard {
  const AndroidYandexDestinationGuard(
      {required this.settings,
      this.documents = const AndroidDownloadFolders()});
  final SettingsRepository settings;
  final DownloadFolderDocuments documents;
  Future<bool> call(LibraryFolder folder, LibraryScanControl control) async {
    control.throwIfCancelled();
    final saved =
        await settings.readString(AndroidDownloadStorageController.settingKey);
    control.throwIfCancelled();
    if (!folder.isEnabled || saved == null || saved != folder.path) {
      return false;
    }
    final ContentUriAudioSource tree;
    try {
      tree = AndroidDownloadFolders.parseTree(saved);
    } on FormatException {
      return false;
    }
    final DownloadFolderAccess access;
    try {
      access = await documents.inspectDownloadFolder(tree);
    } on LibraryScanCancelled {
      rethrow;
    } on Object {
      return false;
    }
    control.throwIfCancelled();
    return access.usable;
  }
}
