# Вариант загрузки Яндекса и владение сетевой попыткой

Пакет 43, 18 октября 2026. Внутренний слой; пользовательский экран ещё не
создаёт downloader. Настоящая авторизованная загрузка из Яндекса этим пакетом
не объявляется проверенной. Все сетевые проверки выполняются на loopback с
синтетическим токеном, музыка — repository fixtures.

## Контракт провайдера

Использованы первичные исходники MarshalX/yandex-music-api на commit
`9ca132e5c18a72aab779c1fc68c169380a9357d0`:

- [tracks / file-info](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/_client/tracks.py)
  и [batch metadata](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/_client/_batch.py).
- [Подпись и desktop client](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/utils/sign_request.py),
  [модель downloadInfo](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/track/file_download_info.py).
- [Исходный пример raw/CDN](https://github.com/MarshalX/yandex-music-api/issues/656)
  автора протокола. Это источник наблюдаемого контракта, не гарантия Яндекса.

Локальный YaDown 3.5.5 тоже прочитан: его encraw-вариант не копируется.
Актуальный закреплённый SDK поддерживает raw. Поддерживается только этот путь;
encrypted encraw и неожиданное поле key явно отклоняются. Дешифрование не
имитируется. Новая криптографическая зависимость не добавлена.

YandexLibraryClient реализует отдельную capability YandexDownloadReader.
Прежний YandexLibraryReader и его UI-потребители сохраняют интерфейс.
Сначала нужен verifiedAccount этой credential session. Затем фиксированный
read-only form POST /tracks, после проверки метаданных — GET /get-file-info.
OAuth передаётся только фиксированному API origin. POST не позволяет задавать
произвольный путь, тело или серверную мутацию; прежние endpoints остаются GET.

В обоих запросах track:album сохраняет исходные ID, включая ведущие нули.
Metadata response должен содержать один нужный трек и ровно один подходящий
альбом при заданном контексте. Подмена realId, substituted/matchedTrack,
недоступность, неподдерживаемый тип и неполные метаданные отклоняются. Без
album context альбомные теги не угадываются. Артисты трека и альбома отдельные;
version включается в title, жанр берётся из выбранного альбома. Теги ограничены
по числу/длине/UTF-8 бюджету; строки с управляющими символами отклоняются.
Track.fileSize не используется: он может относиться к другому кодированию.

File-info подписывается HMAC-SHA256 уже имеющейся crypto библиотекой. В подпись
входит полный composite track ID, timestamp UTC seconds, quality, codec, raw.
Из base64 удаляется один padding символ. Desktop header применяется только к
этому endpoint; публичная константа подписи не является токеном пользователя.
Три независимых Python-вектора фиксируют совместимость, включая album/zeroes.

## Качество и адрес

YandexAudioSelection задаёт точные API quality/codec. Для lossy вызывающая
сторона обязана отдельно задать минимум объявленного kbps и минимум реально
измеренного bitrate: номинал нельзя приравнивать среднему VBR. Это явная
политика вызывающего кода, не догадка о соответствии hq/nq и битрейта. Значения
порогов входят в resourceQuality, поэтому задания с разной проверкой различны.
Пользовательские presets ещё не выбирались. FLAC разрешён только с lossless;
MP3 и AAC в M4A имеют отдельные профили. FLAC-in-MP4/HE-AAC пока не поддержаны.

Ответ обязан сохранить требуемые quality/codec, track identity и raw transport.
Fallback ниже запроса не принимается автоматически. size > 0 проверяется как
ожидаемый размер; отсутствующий/нулевой size означает неизвестный, а не пустой
файл. Отрицательный/слишком большой размер и неверные типы отклоняются.

Разрешён только HTTPS 443 на label-bound поддоменах strm.yandex.net и путь
/music-v2/raw/. Это независимое правило адаптера, не доверие любому host из
ответа. Все URLs проверяются; primary обязан входить в ограниченный список.
Preview/crypt/encraw пути, userinfo, IP/local/чужой host, fragment и redirect
не разрешены. Неизвестный новый CDN потребует обновления адаптера.
Отдельный loopback seam связан с точным origin; production transport отвергает
тестовые адреса. Адрес только в памяти, используется сразу; retry/перебор CDN,
возобновление Range и сохранение подписанной ссылки не добавлены.

Отдельный binary HTTP client не получает OAuth/cookie/API headers. Вариант
содержит ограниченные теги, длительность и требования к проверке. Получение
raw не доказывает качество или полноту: дальше обязательны прежние decode/hash,
теги/обложка и проверка длительности. Короткое валидное аудио вместо полного
трека отклоняется реальным helper перед импортом.

## Владение попыткой

YandexTrackDownloader получает уже claimed job, текущий account и dedicated
reader/transport; не запускается сам и не ставит задания. Runner обязан создать
reader из credential, совпадающего с актуальными account ID/revision/UID;
проверка UID клиентом не заменяет связывание credential revision в session owner.
Downloader сверяет supplied account с repository и job, профиль — с job quality.

DownloadLeaseOwner продлевает попытку перед API и во время всей сети. Смена
аккаунта/повторный вход/отключение папки отзывают lease: lossControl отменяет
принятый HTTP и файловую запись. Heartbeat не держит SQLite transaction во время
сети. При завершении ещё одна короткая writer fence проверяет current attempt,
account revision и папку, даже если transfer закончился до первого tick.
После остановки и drain heartbeat возвращаются вместе raw и ПОСЛЕДНИЙ snapshot
job. Координатор заново подтверждает lease при приёме; задержка вызывающей
стороны или дальнейший отзыв всё ещё могут отклонить handoff.

На ошибке выполняется CAS fail/cancel, конкурирующий отзыв не перезаписывается.
При ownership loss новая попытка не усыновляется. Partial удаляется до возврата,
резерв удерживается при ошибке cleanup согласно RawDownloadPool. Успешный raw
закрывает потребитель после всех читателей; close downloader не удаляет выданный
файл. Busy/close, cancellation, тайм-аут и drain принятых работ явные. Остановка
после финального fence тоже учитывает позднюю отмену на последнем snapshot.

Исключения и toString не содержат URL/ключи/токены/названия. Диагностика API и
binary этапа сохраняет только фиксированные коды, числа и bool. Новые endpoints
добавлены в конец диагностического enum, старые индексы сохранены.

## Границы следующего этапа

Прежде чем подключать кнопку: общий raw+prepared+publication бюджет, восстановление
raw после crash, bounded cover download, runner с точным credential/session
binding, прогресс/отмена и проверка реального аккаунта с малой выбранной коллекцией.
Проверка приватного API на fixtures не заменяет эту живую проверку. Android SAF
publication/теги и macOS helper ещё отдельные платформенные работы. Расписание,
переработка рекомендаций и новый дизайн остаются в согласованной очереди.

Обновление пакета 44: [общий workspace budget и восстановление](download-workspace.md)
реализованы для явно собранного desktop pipeline. До UI остаются bounded cover
fetch, credential/session-bound runner и малая живая проверка API.

Обновление пакета 45: [bounded получение/декодирование и встраивание обложки](yandex-cover-download.md)
включены в явный network pipeline. До пользовательской кнопки остаётся runner
с актуальным credential revision и малая живая проверка выбранной коллекции.
