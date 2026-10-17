**Пакет 37 — read-only адаптер фонотеки Яндекса**

Пакет40 изменяет порядок входа и каталог: verified credential сохраняется до
discovery, объединяются свои и сохранённые плейлисты, optional labels/counts
не блокируют вход. Ниже зафиксирован контракт соответствующего прежнего пакета;
актуальные отличия описаны в [пакете40](yandex-playlist-catalogue.md).

Пакет 36 подтверждён пользователем. Новый Dart-клиент самостоятельно реализует
ограниченную часть протокола; Python/requests/YaDown в продукт не добавляются.
Схема остаётся 13, pubspec/lock прежние. Ни bootstrap, ни UI пока не создают
этот клиент; обычные запуск, воспроизведение и сканирование не обращаются к API.

Методы сверены с авторскими исходниками yandex-music-api, commit
[`9ca132e5c18a72aab779c1fc68c169380a9357d0`](https://github.com/MarshalX/yandex-music-api/tree/9ca132e5c18a72aab779c1fc68c169380a9357d0).
Local YaDown 3.5.5 зависит от yandex-music >= 3.0.0, но его собственные download/
decrypt функции здесь не используются. Это не официальный договор стабильности
API Яндекса; работоспособность конкретной авторизации проверим при подключении
входа. Пользовательские credentials/аккаунт не читались и не отправлялись.

| Чтение | Endpoint | Источник контракта |
| --- | --- | --- |
| UID / отображаемое имя | GET /account/status | [account.py](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/_client/account.py) |
| Собственные плейлисты | GET /users/{uid}/playlists/list | [playlists.py](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/_client/playlists.py) |
| Мне нравится | GET /users/{uid}/likes/tracks | [likes.py](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/_client/likes.py) |
| Состав плейлиста | GET /users/{owner}/playlists/{kind} | [playlists.py](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/_client/playlists.py), [page/pageSize/richTracks в Rust-клиенте](https://docs.rs/yandex-music/0.7.0/src/yandex_music/api/playlist/get_playlist.rs.html) |

`YandexHttpTransport` принимает типизированный read request вместо произвольного
адреса. Production origin — только https://api.music.yandex.net, TLS штатный,
redirects отключены. Loopback-only constructor предназначен для тестов и не
принимает произвольный удалённый host. Токен идёт только в OAuth header; cookie
jar, отправка истории, запросы изменения лайков/плейлистов и автоповторы отсутствуют.
UA приложения и compatibility client header заданы явно; пароль не используется.

Каждый запрос владеет HttpClient, закрывает его force при отмене/таймауте и в
finally. Принятый Future наблюдается внутри, close отменяет и дренирует его.
По умолчанию 20 секунд на запрос, 16 MiB ответа; лимит применяется и к chunked/
распакованному gzip. Большой JSON от 256 KiB разбирается на isolate без передачи
HttpClient/credentials. Ограничения настраиваются до 2 минут / 32 MiB. Это лимит
каждого ответа, не общего объёма трафика за операцию. Нет обещания жёсткого срока
прерывания системного DNS или CPU-декодирования: принятое чтение дренируется.

Проверяются status, JSON MIME, UTF-8, envelope/result и API error даже в HTTP 200.
401, 403, 404, 429, 304 и 5xx различаются техническими кодами. 403 не объявляется
автоматически отсутствием подписки. Retry-After 429 хранится как bounded duration
до суток, не запускает retry. Исключение не содержит raw body/URL/header/exception
text; OAuth object печатается как redacted и здесь не сериализуется/не сохраняется.
Очистки строк из heap не обещается; persistence относится к следующему шагу.

`YandexLibraryClient` принадлежит одной неизменяемой credential session, принимает
одну операцию одновременно и сначала требует verifyAccount. Возвращённый UID
связывается с RemoteAccountIdentity(provider=yandex_music). Повторная проверка
того же клиента с другим UID не переключает аккаунт молча. Получение фонотеки
требует именно проверенной identity; catalogue проверяет own owner/kind, не
выбирает плейлист по названию. Повторяющийся ключ catalogue — ошибка. Состав
чужого выбранного плейлиста поддержан с явным ownerId; обнаружение подписанных
чужих списков в catalogue и вставка ссылок в UI пока не реализованы.

TrackShort.id переносится в externalId, явный albumId — в variantKey; ведущие
нули строк сохраняются. При отсутствии albumId контекст пустой; из названия или
первого альбома вложенного track он не угадывается. Порядок, повторения и позиции
недоступных треков с корректным ID сохраняются. Противоречие outer/nested ID
отклоняется. Отдельные контексты альбома не склеиваются; будущая загрузка должна
запрашивать тот же track/album context. Никаких URL скачивания в SQLite нет.

Likes запрашиваются полностью с if-modified-since-revision=0: нужны library.uid,
revision и явный tracks array. Отсутствующий список не считается пустым. При
наличии count/pager/completeness hints они также должны подтверждать полноту;
Likes с pager, указывающим неполный состав, отклоняются; продолжение этого
endpoint пока не запрашивается.

Для playlist нужен declared trackCount. Без pager длина tracks должна совпасть
целиком. При pager проверяются total/page/perPage и точная длина каждой страницы;
первый ответ может иметь индекс 0 или 1, следующие запросы продолжают именно
его нумерацию. Owner/kind/count/revision должны оставаться теми же. Повторённая/
пропущенная/короткая страница, ложный hasMore последней страницы или смена ревизии
не создают complete snapshot. Rich tracks отключены, IDs остаются основанием
порядка. Конкретную поддержку сервером параметров ещё подтвердим с аккаунтом.

Вся коллекция читается дважды; совпадают ревизия и все ordered identities.
При отсутствии playlist revision сравниваются два полных состава. Это две
согласованные наблюдаемые версии, не server-side transaction: незаметное ABA
изменение или ложь сервера не исключаются. По умолчанию maxItems 100 000,
maxPlaylists 2000, maxPages 256 за проход, operation timeout 5 минут; превышение
явно отказывает, не обрезает данные. Непрерывно меняющаяся коллекция возвращает
changed, автоматического бесконечного retry нет.

`YandexCollectionRefresher` получает existing account/selected collection,
проверяет identity клиента и приобретает beginRefresh ticket до сетевого чтения.
Полный снимок передаётся прежнему commitSnapshot. Отзыв/смена session revision,
снятие выбора или более новый ticket дают stale; network/auth/partial/changed
сохраняют старые позиции и completedAt. SQLite failure откатывает замену. Между
коллекциями общей transaction нет; будущий runner передаёт planner актуальность
всех выбранных snapshots. После принятого commit поздняя отмена дренирует его
фактический результат. Close refresher освобождает reader до закрытия SQLite.

91 новый тест: 45 client, 30 real loopback HTTP, 16 refresher/SQLite. Проверены
два прохода и paging, повторы/версии/недоступные позиции, неверные/частичные
ответы, gzip/chunked/большой JSON, redirects, socket failure, timeout/cancel/
close, смена аккаунта/выбора/ticket, SQL rollback и поздняя отмена commit. Есть
vertical snapshot → существующий planner → две durable jobs для трёх позиций.
Все ответы синтетические, данные БД временные; реального OAuth/сети Яндекса в
тестах нет. Общий набор: 1507 passed (91 новый), 52 секунды, concurrency 4;
analyze без замечаний, format 249 файлов без изменений.

Далее защищённое хранение credentials, вход и выбор коллекций в UI, затем
transport/ownership/budget raw+prepared workspace и кнопка обновления. Release
Android пока не добавляет INTERNET, поскольку сетевой UI не включён: разрешение
нужно при его фактическом подключении. Native Android SAF writer и macOS helper
qualification остаются отдельными платформенными задачами. Расписание после
рабочего ручного обновления, алгоритм рекомендаций отложен.
