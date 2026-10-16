# Комплект медиапомощника — пакет 34

Пакет 33 подтверждён пользователем. Windows x64 теперь получает собственные
FFmpeg/ffprobe и шесть DLL в `tools/media-helper` рядом с EXE. Это подготовка
файлов для будущей синхронизации, не новый движок воспроизведения. Вход, сеть,
скачивание и координатор ещё не подключены. Схема БД остаётся 13.

## Поставка и происхождение

`tool/build_media_helper.py` собирает FFmpeg 7.1.5 из официального архива,
зафиксированного SHA-256. Это последняя обслуживаемая версия ветки 7.1 на момент
пакета; контракт предыдущих пакетов проверялся на 7.1. Исходный архив проверен
PGP-ключом с официальным fingerprint
`FCF986EA15E6E293A5644F10B4322F04D67658D8` в отдельном локальном keyring.
Последующие загрузки требуют того же SHA-256; обновление версии — отдельный
пересмотр pins, возможностей, лицензий и реальных audio checks.
[Официальные релизы и проверка подписи](https://ffmpeg.org/download.html).

Никаких глобальных установок: разработчику нужны Python, Git Bash и полный
MSVC с C11; GNU Make собирается локально из pinned source. Его документированная
настройка HAVE_CYGWIN_SHELL включается рецептом. Для одноразовой сборки отключён
awk dependency scanner через make overrides: это не отключает компиляцию.
FFmpeg/zlib source не изменяется. Локальная неполная VS 2022 пропускается,
используется установленный полный VS 2019 Build Tools. CI выбирает полный MSVC
через vswhere. [Требования upstream](https://ffmpeg.org/platform.html).

Профиль `cmp-audio-1`: MP3/AAC/FLAC decode, PNG/JPEG decode, MP3/M4A/FLAC
stream copy, null/hash muxers, PCM S16LE/S32LE для проверки, wrapped_avframe
для проверки картинки, нужные фильтры. Включены только file/pipe; network,
autodetect сторонних библиотек, устройства, ffplay, GPL/version3/nonfree
отключены. x86 assembly отключён, NASM не требуется; потоковая поддержка Windows
сохранена, операции backend по-прежнему ограничивают число потоков.
Универсальный transcoder, вывод звука и доступ к аккаунту не поставляются.

Восемь runtime-файлов занимают **4 401 664 байта** в проверенной сборке MSVC
2019. В архив также входят полные соответствующие исходники FFmpeg и zlib,
подпись/ключ, рецепты, build-info и тексты лицензий. Поэтому общий размер
поставки больше размера runtime. FFmpeg DLL динамические; zlib 1.3.2 статически
включён для PNG. GNU Make — только build tool: архив его source дан для
повторения сборки, executable не поставляется. Импортируются только вложенные
FFmpeg DLL и Windows KERNEL32/SHELL32/PSAPI/bcrypt; отдельный VC redistributable
этой сборке не нужен. [Условия FFmpeg](https://ffmpeg.org/legal.html),
[исходники и лицензия zlib](https://zlib.net/).

## Проверка и владение

`BundledMediaHelper.forCurrentProcess()` поддерживает только Windows x64 и
вычисляет каталог от `Platform.resolvedExecutable`. Нет PATH lookup, скачивания
помощника во время работы или зависимости от `C:\ffmpeg`, Python, `D:\YaDown`.
Конструктор ленивый; обычный запуск/воспроизведение ничего не хэширует и
не запускает. Future coordinator должен явно квалифицировать комплект перед
использованием и заново после обновления установки.

Проверка требует schema/profile/target/version manifest, фиксированные восемь
имён, размеры и SHA-256 всех EXE/DLL до и после запуска. Manifest ограничен
8 KiB, каждый бинарник — 64 MiB; файлы и корневой каталог не должны быть links.
Процессы должны сообщить именно ожидаемую версию/конфигурацию, реальные записи
таблиц decoder/encoder/demuxer/muxer/filter и только file/pipe protocols.
Название кодека в описании посторонней записи не считается возможностью.

Один процесс/проверка за раз, ограниченный вывод, 30 секунд на всю квалификацию,
отмена и close дренируют процесс. Ошибки типизированы и не показывают paths,
stderr или исходный текст исключений. Успех даёт абсолютные пути для создания
FfmpegAudioMetadataBackend. Это доказательство совместимости стабильной
установки, не вечное разрешение: нельзя сохранять его через обновление файлов.
Editable manifest — контроль неполной/повреждённой поставки, не криптографическая
подпись приложения и не sandbox от владельца каталога. Самостоятельно собранные
DLL разрешено заменить с обновлением локального manifest; NOTICE это поясняет.
Атака с подменой файлов между проверкой и OS loader находится за этим контрактом.

## UI и сборка

Windows: «Настройки → Диагностика → Проверить медиапомощник», отмена и результат
под кнопкой. Уход из настроек отменяет принятую проверку. Отдельная ссылка
открывает каталог лицензий/соответствующего source. Сама проверка не читает
музыку/БД/аккаунт и не подготавливает файлы пользователя.

Сборка официального Windows пакета задаёт `CMP_MEDIA_HELPER_BUNDLE` — путь
к готовому комплекту. CMake устанавливает его целиком в `tools/media-helper`.
Обычный playback developer build может не задавать переменную; кнопка тогда
сообщит об отсутствии комплекта. CI собирает helper из pinned source, проверяет
runtime/source/licenses/imports, прогоняет реальные synthetic fixtures и
повторяет проверку после CMake installation в Windows release.

```powershell
python tool/build_media_helper.py --work-dir C:/cmp-helper-work --output C:/cmp-helper
$env:CMP_MEDIA_HELPER_BUNDLE = 'C:/cmp-helper'
python tool/verify_media_helper_bundle.py $env:CMP_MEDIA_HELPER_BUNDLE
# Bare Dart VM avoids unrelated native build hooks for this pure-Dart checker.
& "$env:FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart.exe" --packages=.dart_tool/package_config.json tool/check_bundled_media_helper.dart $env:CMP_MEDIA_HELPER_BUNDLE test/fixtures/media_helper
flutter build windows --release --no-pub
```

Указанные work/output пути должны быть новыми. Native work path — ASCII без
пробелов; готовый комплект проверен в пути с кириллицей и пробелами. Включённые
в репозиторий test fixtures — самостоятельно сгенерированные двухсекундные
тоны и одноцветные картинки (CC0), не Flutter assets. Для расширенного
`check_downloaded_audio_metadata.dart` добавлен третий, необязательный путь
к developer generator: production helper не обязан содержать кодировщики
libmp3lame/AAC/FLAC/Vorbis или lavfi.

## Проверено и оставшаяся очередь

36 новых Flutter tests проверяют manifest, повреждённые/отсутствующие DLL,
подмену во время probes, версии/лицензионные flags/возможности/network, lifecycle,
отмену/timeout/close. Ещё 7 — UI lazy/repeat/cancel/dispose/errors/license action.
Все **1301 Flutter tests** прошли, analyze без замечаний, format 218 файлов.
На реально собранном helper — 31 expanded synthetic сценарий предыдущего
pipeline и 9 сценариев из фиксированных fixtures (PNG → JPEG → сохранение
в каждом из трёх форматов), полные packets/PCM/decode/hash checks.

Новый APK не выпускается: Android playback/SAF не менялись, можно оставить
прежнюю проверенную версию. Desktop EXE/DLL не переносятся на Android.
macOS helper bundle ещё не квалифицирован: существующая macOS сборка/локальное
воспроизведение сохраняются, новый Windows UI там не показывается. Физические
macOS/Android helper checks здесь не выполнялись. Для macOS нужен отдельный
build/install-name/signing/packaging проход до включения загрузки на платформе;
для Android — native SAF preparation/validation/publication adapter.

Далее: общий coordinator с атомарным Track/ref/asset import и retention журнала;
после этого provider adapter, credentials, «Мне нравится»/выбранные плейлисты и
кнопка обновления. Настраиваемое расписание после рабочего ручного обновления.
