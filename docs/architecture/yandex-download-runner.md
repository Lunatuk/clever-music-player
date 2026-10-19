# Управление заданиями загрузки

Пакет 46: явный session-bound runner и собранный Windows pipeline. Код пока не
вызывается пользовательским экраном или обычным запуском приложения. Управление
заданиями проверено на настоящей SQLite; полный pipeline — на синтетическом
loopback API/CDN с настоящим Windows helper. Токен и фонотека пользователя не
использовались. Проверка реального приватного API остаётся следующим этапом.

## Сессия и границы

`YandexDownloadRunner.run` принимает account snapshot, ID папки, точный профиль
качества и предел числа заданий (по умолчанию 3, допустимо 1..1000). Конструирование
runner не читает OS credential storage/БД, не открывает workspace и не создаёт
таймеров. Run работает с уже поставленными заданиями: планирование, enqueue,
повтор failed/cancelled и повтор completed с repair intent остаются явными
действиями контроллера обновления. Лимит считает начатые попытки, не только успехи.

Перед созданием dedicated reader проверяются:

- точное совпадение единственной активной сессии с supplied account;
- сохранённый credential с теми же account ID, UID, revision и active flag;
- повторный SQLite snapshot после OS credential read;
- UID из verifyAccount и ещё один актуальный snapshot.

Reader создаётся заново для каждого запуска; старый токен не подменяется во время
работы. Runner не изменяет и не удаляет OS credential при ошибке: к этому моменту
там уже может лежать новое подключение. Проверка UID сама по себе не связывает
токен с revision — эту связь даёт saved credential и проверка SQLite до/после read.
Ни network, ни helper/хеширование не выполняются под SQLite writer transaction.

В течение verification, открытия pipeline и выполнения заданий сериализованный
poller проверяет сессию раз в секунду (настраиваемо 10ms..5s); не более одного
poll read одновременно. На границах setup/claim/execute есть дополнительные
проверки. Ошибка чтения сессии отзывает разрешение так же, как смена сессии, но
возвращает storage failure, а не пользовательскую отмену. Поллер — кооперативная
отмена принятой работы, не обещание мгновенно прервать OS IO за одну секунду.
Он останавливается и дожидается принятого read до завершения run. Прежние job
heartbeat и final writer fences дополнительно проверяют session/folder/lease
при передаче raw, публикации и импорте.

## Очередь и восстановление

claimNext получил optional exact libraryFolderId/quality с bound SQL parameters.
Несовпадение не приводит к выбору другого назначения или профиля; старые callers
без scope сохраняют FIFO. Enabled folder, актуальный account/revision, finite
attempt budget, retryAt и занятость музыкального ресурса проверяются как прежде.
Изменений схемы нет; прежняя recovery просроченных leases внутри claim сохранена.

Runner открывает/проверяет pipeline до claim: отсутствующий/повреждённый helper
или занятый/небезопасный workspace не расходуют попытку. Выполнение последовательно.
После первой ошибки, busy, необходимости reconciliation или cleanup failure
новые задания не берутся. Нет автоматического цикла fail/retry/reclaim. Исход
limited означает достижение предела, не доказательство наличия остатка в очереди.
Пустая matching queue означает отсутствие доступных заданий, не гарантию полной
синхронизации выбранных коллекций.

Reconciling attempt сначала проходит прежний coordinator.recover. Если готовый
файл уже опубликован, он импортируется без metadata/raw/cover HTTP. Если готового
файла нет, coordinator безопасно возвращает последний snapshot на download stage;
под той же claimed attempt продолжается скачивание. При ошибке очистки recovery
продолжение не допускается. Рабочие файлы/журналы удаляются только прежними
workspace/publication retention механизмами; runner не удаляет музыку.

Если execute бросил исключение или вернул ещё выполняющуюся попытку, runner
снова читает job и делает CAS interrupt только при совпадении attempt token,
account ID/revision и ключа. Старый revision после heartbeat не используется;
новая конкурентная попытка никогда не усыновляется и не прерывается. Уже failed,
cancelled, needsReconciliation и completed не перезаписываются.

## Владение desktop pipeline

DesktopYandexDownloadPipeline.open явно квалифицирует установленный helper,
открывает общий DownloadWorkspace и собирает downloader/preparer/coordinator.
По умолчанию audio ceiling 256MiB, raw pool имеет два slot и дополнительный
резерв 2MiB под обложку; общий workspace по-прежнему 2GiB. Подготовка/публикация
считают перекрывающиеся копии. Квоты допуска не являются OS disk quota.

Сначала выполняются [скачивание raw/обложки](yandex-cover-download.md), затем
preparer/полный decode/digest/tags/unchanged audio и атомарный Track/ref/asset/import.
Raw остаётся жив до завершения читателей и закрывается в finally. Ошибка его
очистки после успешного импорта сохраняет completed и сообщается отдельным
cleanupFailed; следующий claim не допускается.

Pipeline владеет transport, backend, workspace и всеми выданными temporary
readers. Reader он заимствует у runner: downloader создаётся с ownsReader=false;
default downloader вне композиции по-прежнему закрывает reader сам. При close
сначала закрывается допуск и запрашивается отмена, затем drain принятых работ,
закрытие компонентов, retry failed raw cleanup и workspace unlock. Все close
выполняются даже после одного отказа. Runner закрывает credential reader последним.
Factory, бросившая исключение до выдачи pipeline, сама очищает созданные ресурсы.

close runner запрещает новые run, отменяет активный и дожидается очистки. cancel
останавливает текущий run, сохраняя возможность нового явного запуска. Прежняя
семантика stop сохранена: отмена downloader помечает текущий job cancelled;
после принятой publication coordinator дожидается импорта. Другие queued остаются
в очереди. Очередь не запускается автоматически при перезапуске приложения.

Прогресс: authenticating/preparing/recovering/downloading/processing/finished,
started/completed и audio byte counters. Пока аудио и обложка входят в общий
downloading stage. Observer exceptions не прерывают работу/очистку; повторный
run во время активного возвращает busy. View state и ошибки содержат enum/числа,
не секреты, URL, путь, название трека или текст исключения.

## Следующий этап

Подключить controller/UI: папка назначения, профиль качества, свежие снимки
выбранных коллекций, план/постановка заданий, ручная кнопка обновления, прогресс
и отмена. Начать с маленькой явной проверки реального аккаунта на Windows.
Android private lock/SAF publication/теги и macOS helper требуют отдельной
платформенной реализации/квалификации; этот пакет их готовность не заявляет.
Расписание, дизайн и рекомендации остаются далее в согласованном плане.
