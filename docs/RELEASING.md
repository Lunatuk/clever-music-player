# Версии и выпуск

Начиная с 0.3.0, пользовательская версия — `MAJOR.MINOR.PATCH`:

| Изменение | Пример следующей версии |
| --- | --- |
| Исправления и небольшая доводка | 0.3.0 → 0.3.1 |
| Новый функционал, заметное развитие приложения | 0.3.1 → 0.4.0 |
| Крупный рубеж или существенная переработка | 0.4.0 → 1.0.0 |

Каждая переданная пользователю итерация повышает версию. При повышении MINOR
PATCH обнуляется; при повышении MAJOR обнуляются MINOR и PATCH. Повторные
локальные сборки до передачи пользователю сохраняют версию этой итерации.

Единственный источник — `version` в корневом `pubspec.yaml`, сейчас
`0.4.1+2067`. После плюса идёт отдельный монотонный номер сборки BUILD.
Это Android versionCode и четвёртый числовой компонент версии Windows.
Он повышается при любом выпуске, даже при повышении MAJOR. Все компоненты
ограничены 65535 из-за формата Windows VERSIONINFO; BUILD начинается с 1.

Число 2065 сохраняет возможность обновить Android поверх прежнего APK63
(его фактический versionCode — 2063). Раньше `--split-per-abi` добавлял к
счётчику 2000. Теперь ARM64 APK собирается без этого флага; архитектура
задаётся `--target-platform android-arm64`. Gradle фильтрует и CMake-сборку,
и библиотеки из зависимостей в release: в APK остаётся только ARM64.
Идентификатор приложения и ключ подписи сохраняем при обновлении.
Исторические «пакеты 1–64» остаются в журнале под своими номерами.

## Рабочий цикл

1. Создать ветку `feat/...`, `fix/...`, `refactor/...`, `chore/...` или `docs/...`.
   Сообщения новых коммитов — по-русски. Старые ветки и историю не переписываем.
2. В начале итерации выполнить один из вариантов:

   ```sh
   python tool/release_version.py bump patch
   python tool/release_version.py bump minor
   python tool/release_version.py bump major
   ```

   Команда меняет только версию в pubspec и повышает BUILD. Проверка:
   `python tool/release_version.py check --base-ref <коммит-предыдущего-выпуска>`.
   Команда `show` выводит текущую версию без изменений.
3. Выполнить анализатор, тесты затронутых сценариев и необходимые проверки
   сборок. До передачи выпуска запустить общий набор Flutter-тестов и
   `python -m unittest discover -s tool -p test_release_version.py`.
   В CI проверяются формат версии и метаданные готового Windows/Android-файла.
4. Собирать из pubspec без `--build-name` и `--build-number`:

   ```sh
   flutter build windows --release --no-pub
   flutter build apk --release --no-pub --target-platform android-arm64
   ```

   Для Windows действуют существующие требования ASCII-пути сборки и
   квалифицированного медиапомощника; см. текущий журнал сборок.
5. Проверить настоящий результат:

   ```sh
   python tool/release_version.py verify-windows build/windows/x64/runner/Release/clever_music_player.exe
   python tool/release_version.py verify-android build/app/outputs/flutter-apk/app-release.apk
   ```

   Android-проверка ищет aapt в PATH или SDK из ANDROID_SDK_ROOT/ANDROID_HOME;
   можно передать `--aapt <путь>`. Проверка отвергает старую версию и ABI-смещение
   versionCode. Windows-проверка сверяет числовые и строковые поля FILEVERSION
   и PRODUCTVERSION. Проверки плагина аудио, медиапомощника, подписи APK,
   архитектуры и выравнивания библиотек также сохраняются.
6. Использовать имя `clever-music-player-0.3.0-build2065-windows-x64.zip`
   или `clever-music-player-0.3.0-build2065-android-arm64.apk`, подставив текущую
   версию. Приложить контрольную сумму и короткие ручные проверки.
   Записать результат в IMPLEMENTATION_LOG и передать файлы пользователю.

В Windows номер виден в настройках → «Информация о приложении» и в свойствах
EXE → «Подробно». В Android — в диалоге «О версии» и информации о приложении
в системных настройках. Интерфейс читает фактические нативные метаданные через
`package_info_plus` 8.3.1: эта версия совместима с текущим Android toolchain.
Подход опирается на [версионирование Flutter для Windows](https://docs.flutter.dev/deployment/windows#updating-the-apps-version-number),
[Android](https://docs.flutter.dev/deployment/android#update-the-apps-version-number)
и [API метаданных пакета](https://pub.dev/packages/package_info_plus/versions/8.3.1).
