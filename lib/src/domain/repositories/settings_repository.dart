import '../models/app_setting.dart';

abstract interface class SettingsRepository {
  Future<AppSetting?> read(String key);

  Future<String?> readString(String key);

  Future<void> writeString(String key, String value);

  Future<void> delete(String key);
}
