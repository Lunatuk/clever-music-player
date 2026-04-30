import 'package:file_picker/file_picker.dart';

abstract interface class DirectoryPickerService {
  Future<String?> pickMusicFolder();
}

final class FilePickerDirectoryPickerService implements DirectoryPickerService {
  const FilePickerDirectoryPickerService();

  @override
  Future<String?> pickMusicFolder() {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose music folder',
      lockParentWindow: true,
    );
  }
}
