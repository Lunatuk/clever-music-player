final class AppSetting {
  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String key;
  final String value;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppSetting &&
            other.key == key &&
            other.value == value &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
}
