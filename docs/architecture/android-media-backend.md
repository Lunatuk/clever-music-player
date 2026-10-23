# Android: теги, обложки и проверка аудио (пакет 56)

Проверка записи55 подтверждена пользователем. В56 реализован Android backend
общего `DownloadedAudioMetadataPreparer`. Публичная загрузка песен ещё выключена:
следом разрешение незавершённых публикаций и подключение общего runner к
publisher55/importer54. Схема13, очередь, рекомендации и Windows51 прежние.

## Библиотеки и сборка

FFmpeg7.1.5 собирается из того же официального архива с pinned SHA-256 и
проверенной в34 подписью. Профиль `cmp-android-audio-1`: MP3/AAC/FLAC decode,
PNG/JPEG decode, MP3/M4A/FLAC stream copy, swresample для S32 PCM. Сторонние
кодеки, GPL/version3/nonfree, программы, сеть, все URL protocols, avfilter,
swscale, avdevice и assembly выключены. Работа с файлами — custom AVIO на
проверенных дескрипторах, не запуск FFmpeg executable.
[Официальные релизы](https://ffmpeg.org/download.html),
[libavformat API](https://ffmpeg.org/doxygen/7.1/group__libavf.html).

NDK28.2.13676358, API24, ARM64, ELF16КиБ. Четыре динамические библиотеки
занимают 1627048байт; JNI wrapper компилируется CMake3.22.1 вместе с приложением
с `-Wall -Wextra -Werror`. Вендорный manifest фиксирует каждый lib/header/source
kit по размеру и SHA-256. CMake проверяет эти данные до компиляции. Git
сохраняет bytes в vendor без преобразования концов строк.

`tool/build_android_media.py` — рецепт полной сборки; рабочая директория новая,
ASCII, без пробелов. На Windows нужны Git Bash, GNU Make и полноценный MSVC SDK
для host tools; сам Android-код собирает NDK clang. Host compiler имеет
отдельный wrapper, чтобы Windows headers не попадали в Android cross compile.
Upstream source не правится, создаются только build/config outputs. Чистая
повторная сборка дала идентичные четыре runtime-библиотеки.

## Владение и границы

Библиотека загружается лениво при явной операции. Обычный запуск/воспроизведение
не декодирует музыку через FFmpeg. Отдельный native worker сериализует запросы,
глобальный atomic admission исключает одновременную работу с общим ответом.
Положительный request ID связывает cancellation с текущим запросом.

Источник — существующий непустой regular file внутри app-private filesDir.
Алиасы родительского пути нормализуются; ссылка в последнем компоненте
отклоняется. C повторяет O_NOFOLLOW/fstat и ограничивает чтение размером,
полученным при открытии, даже если файл затем вырос. Output должен быть уже
зарезервированным пустым regular file, отличным от source; он не открывается
с truncate. Существующую музыку этот backend не редактирует.

Файлы до8ГиБ, не более12часов декодированного аудио, 1–8каналов, 8–192кГц.
IO buffer64КиБ; write/seek проверяют maxOutputBytes workspace. Обложка до8МиБ,
PNG/JPEG, до4096×4096; максимальная отдельная FFmpeg allocation64МиБ. Это не
общий RSS limit процесса. До двух streams: один audio и не более одной
attached picture. JSON response до128КиБ, восемь разрешённых тегов.

Kotlin передаёт явные UTF-8 byte arrays в JNI, включая пути и emoji в тегах.
JNI modified UTF-8 не используется. Ответ декодируется строго; произвольные
native logs, пути и exception messages не попадают в диагностику.

## Подготовка и доказательство

Общий preparer сохраняет прежний контракт: source SHA до/после, отдельный
private output, полный validator, затем финальный output SHA. Native backend:

1. Определяет container/codec/duration/rate/channels/bit depth и встроенные теги.
2. Считает SHA-256 последовательности audio packets и полностью декодированного
   S32 PCM. Для обложки декодируется картинка и хэшируются исходные image bytes.
3. Копирует audio packets, не создавая audio encoder. Старые теги заменяются
   ожидаемым набором; artist и album_artist отдельны. Новая картинка заменяет
   прежнюю; при отсутствии новой сохраняется прежняя. M4A — обычный локальный
   MP4/ipod output без дополнительного faststart-переоткрытия файла.
4. Закрывает/flush/fsync output, затем общий preparer вновь читает результат,
   проверяет tags/cover/quality/duration, неизменность audio packets/PCM,
   sample rate/channels/bit depth и точные байты обложки.

PCM используется для сравнения до/после внутри этого backend, не как
межплатформенный акустический ID и не для нового поиска похожих дубликатов.
Неполные/ошибочные чтения и decode errors не становятся успехом. FFmpeg
ошибки фиксируются без текста; обычные предупреждения не объявляют файл
повреждённым. Отмена atomic flag проверяется в IO и decode loops; close ждёт
завершения. Библиотека не убивает поток принудительно, поэтому жёсткий срок
прерывания любого патологического codec call не обещается.

## Проверка в приложении

В Яндекс Музыке новая карточка «Подготовка музыки» запускает реальный общий
preparer на шести сочетаниях MP3/M4A/FLAC × PNG/JPEG. Тесты — сгенерированные
стереосигналы440/660Гц, 0,6с, 48кГц; FLAC24-bit. Проверяются кириллица/emoji,
отдельные исполнители и остальные теги. Ничего не проигрывается, не публикуется,
не импортируется в БД; токен, сеть и папка фонотеки не нужны.

Известные private files удаляются после drain. Отмена/уход со страницы/закрытие
приложения не удаляют их во время записи. Неизвестные остатки не обходятся
рекурсивно. Диагностика содержит только elapsedMs, case0–5 (MP3PNG/JPEG,
M4APNG/JPEG, FLACPNG/JPEG; -1 до case) и outcome по AudioValidationOutcome.

## Лицензия и соответствующие исходники

LGPL2.1+ текст, notices и source-kit.zip находятся внутри APK; отдельная
страница показывает лицензию и сохраняет kit через системный Save dialog.
В kit — точный upstream archive, подпись/ключ, generated configurations,
build info, рецепты и C/JNI wrapper source. Библиотеки динамические, комплект
содержит инструкции по пересборке, замене и подписанию APK своим ключом.
[Условия FFmpeg](https://ffmpeg.org/legal.html).

Gradle добавляет эти файлы только в Android assets. Windows/macOS Flutter
bundles не получают повторный архив Android-source. `tool/verify_android_media.py`
проверяет CRC, pins, profile и соответствие source kit текущим исходникам,
допуская только Git-перевод концов строк у текстовых исходников проекта.

## Квалификация

37 новых Flutter tests: typed protocol, отдельные теги, quota, malformed replies,
cancel/close/drain, шесть шагов реального preparer с mock codec, cleanup/error,
узкий экран и offline license export. Четыре JVM tests проверяют private paths,
UTF-8/emoji, алиасы, empty output, source/outside/relative/NUL/size bounds.

`tool/check_android_media.py` компилирует тот же C core на Windows с настоящим
FFmpeg7.1.5. 13 сценариев включают шесть format/cover round trips, очистку
тегов/сохранение обложки, exact packets/PCM/image hashes, отказ overwrite,
quota, плохие файлы/картинки, admission и отмену длинного decode с закрытием fd.
Android C/JNI отдельно собраны NDK с Werror; в APK проверяются реальные .so,
JNI exports, DEX/AOT channel, source-kit/assets, подпись и16КиБ.

Host/JVM/build tests не заменяют исполнение на телефоне. APK56 требует короткой
квалификации кнопки и экспорта на Redmi Note14Pro/Android16. Реальные скачивания,
заполнение памяти, длительная нагрузка и аварийное завершение runner остаются
следующим этапом. Расписание/дизайн позже, рекомендации отложены.
