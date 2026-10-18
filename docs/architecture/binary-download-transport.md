# Потоковая загрузка во временный raw-файл — пакет 42

17 октября 2026 года. Пакет 41 подтверждён пользователем; схема 13 и зависимости
прежние. Пакет 42 реализует транспорт и ограниченные raw-файлы. Нормальный
запуск приложения/экран Яндекса пока не создают этот транспорт.

## Контракт

`BinaryDownloadAddress` требует HTTPS и точный host из независимо доверенной
конфигурации адаптера. Нельзя строить trustedHosts из полученного серверного URL.
Поддомены не наследуют доверие. HTTP, IP/локальные host, userInfo, нестандартный
порт, fragment, raw control/space/backslash и адрес длиннее 8192 символов
отвергаются. URL остаётся только в памяти, toString redacted. Политика реальных
CDN Яндекса ещё должна быть проверена вместе с адаптером получения варианта.
Loopback test-конструкторы ограничены одним literal 127.0.0.1/::1 origin;
production-транспорт их не принимает.

`BinaryHttpDownloadTransport` делает один GET отдельным HttpClient без OAuth,
Cookie/Range/Referer и без автоматических redirect/retry/resume. API-клиент с
токеном не переиспользуется. TLS имеет стандартную проверку Dart. HTTP200 —
единственный успешный статус; 401/403/404/429/5xx имеют фиксированные причины,
403 не называется автоматически отсутствием подписки. HTML/JSON/XML, range
response и Content-Encoding кроме identity отвергаются до записи. Отсутствующий
MIME допускается как opaque bytes, не как доказательство музыки.

Accept-Encoding=identity и autoUncompress=false сохраняют смысл Content-Length;
см. [Dart autoUncompress](https://api.dart.dev/dart-io/HttpClient/autoUncompress.html)
и [redirect](https://api.dart.dev/dart-io/HttpClientRequest/followRedirects.html).
Известный размер адаптера и Content-Length обязаны совпадать. StreamIterator
даёт backpressure; записи не больше 64 KiB, буфера всего файла нет. Каждый chunk
проверяется до записи относительно лимита/ожидаемого размера. Пустой, короткий
и избыточный ответ не выдаётся читателю. После EOF — flush/close, проверка
типа/размера и отмены, затем результат RawDownloadedAudio.

Прогресс: только received/total bytes, начало/конец и не чаще 200 ms; ошибка
observer не ломает владение. Тайм-аут по умолчанию 10 минут (максимум 30),
idle/connect/header — 30 секунд (максимум 2 минуты). Отмена abort/force-close
прерывает соединение, принятые connect/header Futures и body subscription
дренируются. Это кооперативные границы для непрерываемого OS DNS/file IO,
не обещание жёсткого срока; [Dart force-close](https://api.dart.dev/dart-io/HttpClient/close.html).

## Владение и бюджет

RawDownloadPool резервирует до 512 MiB/2 файлов по умолчанию, настраивается до
32 GiB/32 файлов; отдельный файл максимум 8 GiB. Предел файла явно передаётся
каждой операцией. Резервирование синхронно, до сети/файлов. Весь предел удерживается
до закрытия результата, включая время подготовки/публикации. Это общий raw-бюджет
одного pool/процесса, не OS disk quota и не лимит всего pipeline.

RawDownloadReservation создаёт случайный подкаталог доверенного app-private
parent и exclusive audio.part. URL/Content-Disposition не определяют путь.
Удаляются только созданный файл и пустой созданный каталог; рекурсивного
удаления нет. Неизвестный файл/подмена типа мешают очистке; резерв остаётся
занят. retryFailedCleanup повторяет только закрытые ресурсы, не активных
читателей. closeAdmission прекращает новый допуск, закрытие HTTP-транспорта
не удаляет выданный читателю файл. Владелец закрывает RawDownloadedAudio после
всех читателей/координатора. Partial при отказе очищается до возврата; ошибка
очистки возвращается отдельно и не освобождает бюджет фиктивно.

Успех транспорта не доказывает аудио, качество, музыкальную идентичность или
полноту неизвестного HTTP тела. Прежний DesktopDownloadCoordinator выполняет
теги/обложку, decode/hash, публикацию и атомарный импорт после передачи source.

## Проверки и следующий шаг

95 новых тестов: raw pool20, address30, real loopback HTTP43, pipeline2. Три
прежних MP3/M4A/FLAC native coordinator tests теперь получают fixture через
HTTP перед настоящим FFmpeg/cover/SQLite. Native recovery test сохранён.
Профильный набор с диагностикой:111 passed. Проверены размеры/truncation,
MIME/encoding/range/redirect/status, тайм-аут/отмена/close/reentrant callbacks,
busy/quota, reader lifetime, отказ очистки/retry и отсутствие URL/путей/server
text в release-отчёте. События transfer started/completed/failed/cleanupFailed
содержат только фиксированные имена и числа stage/failure/status/bytes/time.

До кнопки обновления нужны: адаптер варианта Яндекса (track/album, качество/
кодек, доступность, URL/ключ), ownership lease на сетевом этапе с передачей
последнего snapshot координатору; общий бюджет raw+prepared+publication и
учёт/восстановление брошенных raw после перезапуска. Raw-бюджет пакета 42
не объявляется завершением этих задач. После них подключается runner/UI.
Android SAF writer/теги и macOS helper остаются платформенными шагами;
расписание и новый алгоритм рекомендаций сейчас не включаются.

Обновление пакета 43: [Yandex resolver и сетевой lease](yandex-download-resolver.md)
реализованы для raw full audio с точным track/album/quality/codec. Encraw явно
отклоняется. До UI остаются общий рабочий бюджет/учёт orphan raw, bounded cover
download и session-bound runner. Прежние ограничения raw pool сохраняются.
