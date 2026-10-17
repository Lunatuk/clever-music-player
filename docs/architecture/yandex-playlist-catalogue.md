# Пакет 40 — вход и каталог плейлистов

Отчёт пользователя из 39 показал: проба API без токена HTTP 200 / 269 ms,
проверка аккаунта с токеном HTTP 200 / 41 ms, каталог HTTP 200 / 123 ms.
После этого операция завершилась UI-кодом invalidResponse. Сеть и проверка
аккаунта в этой попытке успешны; отказ возникает в семантической проверке
каталога. Конкретное поле из 39 определить нельзя: UI объединял несколько
protocol failures и не записывал причину валидации. Нельзя утверждать, что
отказал именно чужой владелец или название. Пользователь подтвердил наличие
и своих, и сохранённых чужих плейлистов.

## Подключение

Проверенный профиль теперь сохраняется в credential store/DB до discovery.
Это меняет порядок из пакета 38: verify account → fenced protected write →
configure likes/restore saved choices → own+saved catalogue. Ошибка получения
каталога оставляет действующий вход и «Мне нравится»; каталог можно повторить
без нового токена. UI одновременно показывает подключённый аккаунт и понятную
ошибку/предложение повторить список. Отмена после commit сохраняет принятый
вход. Ошибка protected write откатывает DB и не начинает запрос каталога.

Неверный кандидат по-прежнему не заменяет старый рабочий вход. Если уже после
успешной проверки новый токен получает 401 при discovery, новая сессия отзывается
и credential удаляется через прежний fence; ошибка удаления откатывает DB.
OS/DB crash consistency, revision binding, cancel/close/drain и сохранность
локальной музыки не меняются. Credentials/сырые ответы для исследования
не читались; авторизация пользователя автоматически не воспроизводилась.

## Собственные и сохранённые списки

К прежнему GET `/users/{uid}/playlists/list` добавлен фиксированный read-only GET
`/users/{uid}/likes/playlists`. Контракт сверён с авторскими
[_get_likes/users_likes_playlists](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/_client/likes.py)
и моделью [Like](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/like.py):
saved result — массив wrappers с вложенным `playlist`. Wrapper.id не считается
ресурсом плейлиста. Python SDK не входит в приложение.

Идентичность выбора всегда `(owner UID, kind)`. Явный чужой владелец сохраняется,
не подменяется текущим аккаунтом; readCollection и раньше поддерживал такой
ключ. Одинаковые kind разных владельцев или одинаковые названия не склеиваются.
Один ресурс, повторённый в одном/обоих каталогах, даёт один checkbox; own metadata
имеет стабильный приоритет. Это дедупликация каталога, не ordered track positions.
В UI чужие ресурсы отмечены «Сохранённый плейлист» и выбираются явно.

Если own summary не содержит обоих owner полей, используется проверенный UID
из scope собственного запроса. Если owner указан — он проверяется; противоречие
root/nested UID отвергается. Для saved summary владелец всегда нужен явно:
его не выводим из текущего аккаунта, названия или wrapper.id. Неверный kind,
повреждённый wrapper/owner и отсутствующий список остаются ошибками, элементы
не пропускаются молча. Сохраняется предыдущая конфигурация/зеркала.

Названия и счётчики каталога — необязательные данные представления. Неполное
название получает нейтральный текст, C0/DEL/whitespace нормализуются, обработка
ограничена 2048 runes, результат 512 UTF-16 units без обрыва surrogate pair.
Неизвестный/некорректный count остаётся null, не пустым завершённым списком.
Счётчик discovery не доказывает полноту. Strict owner/kind/count/revision/pages
и два одинаковых полных чтения для snapshot не ослаблены. Повторы треков
сохраняются. Каждый источник ограничен maxPlaylists, объединение уникальных
ключей тоже; никаких дополнительных detail запросов на каждый summary нет.

## Диагностика и проверки

remoteEndpoint **4** = likedPlaylists; коды 0–3 не меняются. В operation failure
теперь сохраняется исходный remoteFailure (YandexLibraryFailure) отдельно от
remoteConnectionFailure UI. Новый remoteResponseIssue — только enum-код:
0 catalogueList, 1 playlistEntry, 2 playlistOwner, 3 conflictingOwner,
4 playlistId, 5 savedPlaylistEntry. Нет значений полей, названий, UID, URI,
секретов, сырых ошибок или ответов. Схема13, зависимости/права прежние.

35 новых тестов: 26 catalogue compatibility/identity/limits/content invariants,
6 controller/реальная SQLite/credential commit/recovery, 2 widget и 1 настоящий
loopback HTTP endpoint check. Проверены same-name/different-owner keys,
сохранённый foreign snapshot с повторами, выбор/restart без HTTP, malformed
optional metadata, missing/conflicting owner, unknown count, 401 после commit,
отмена и повторный каталог без нового токена. Данные синтетические.

Дополнительно публичные search/каталоги двух публичных владельцев проверены без
Authorization: 1065 и141 summaries прошли прежние identity/title/count проверки.
Это полезная сверка обычного формата, а не воспроизведение конкретного поля
пользователя. Приватные данные/токен не запрашивались и не сохранялись.
Нужна [ручная проверка](../MANUAL_CHECKS.md) действующего входа и списка.
