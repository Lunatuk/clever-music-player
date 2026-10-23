# Android download coordinator

Пакет58, 23 октября 2026 года. Проверка57 на телефоне подтверждена пользователем.
В58 координатор внутренний. В59 подключены Android song download/controller:
[композиция и публичная кнопка](android-yandex-downloads.md). Ниже контракт58.

## Ответственность и владение

`AndroidDownloadCoordinator` принимает скачанный app-private `FileAudioSource`
для текущего running/download job либо claimed reconciling job. Не получает
токен, не делает сетевых запросов, не выбирает очередь и не работает при старте.
Владеет preparer и per-job native adapters; journal/workspace/repositories и
artwork cache заимствованы. Caller закрывает coordinator до journal/workspace/DB.
Backend/verifier factories вызываются только после допуска и проверки owner.
Каждый успешно созданный владелец закрывается, даже если следующий factory
или чужой close выбросил ошибку. Publisher.close теперь закрывает оба адаптера
через finishCleanup. Ошибка cleanup не превращает completed в повторную загрузку.

Общий `DownloadCoordinationResult/Outcome` вынесен из desktop coordinator в
`library_sync/download_coordination.dart`; прежний desktop import его экспортирует
для совместимости. Runner больше не импортирует desktop implementation.

## Новый файл

1. Lease owner стартует и проверяет enabled SAF destination.
2. Читаются оба журнала для этого job/key. Pending не обходится новой записью.
3. Checkpoints metadata → verification: общий preparer56 проверяет source,
   теги/обложку, формат/качество, full decode, packets/PCM и итоговый SHA-256.
   Его workspace обязан совпадать с бюджетом координатора, если он передан.
4. Publication intent получает случайный64hex ID; publication checkpoint
   предшествует вызову publisher55. Source seal удерживается до receipt/ack.
5. Из уже опубликованного URI читаются теги и thumbnail. Название не берётся
   из opaque имени; должны совпасть provider name, размер и длительность
   (допуск500мс), title обязателен. Теги ограничены4096/8192символов, NUL
   запрещён, thumbnail≤256КиБ; проверяются номера/год. Artist и albumArtist
   остаются разными полями. Отсутствующий album допускается как прежде.
6. Importer54 заново проверяет полный документ ПОСЛЕ чтения метаданных и до
   commit. SQLite атомарно добавляет Track/ref/verified asset и completed job,
   сохраняя ручные изменения/feedback по прежнему контракту импорта.
7. Receipt удаляется только с current completed-asset authority. Копии private
   prepared освобождаются после publisher/importer drain; raw закрывает caller.

Android `readAudio` дополнительно возвращает CD_TRACK_NUMBER, DISC_NUMBER и
YEAR через прежний MediaMetadataRetriever/release. Dart читает положительный
первый компонент `2/10`, ограничивает номера1..1000000, год1..9999; остальные
optional поля совместимы с прежними вызовами. Strict download reader не
использует filename fallback. Реальный verifier подтверждает bytes, но SAF
не предоставляет OS seal опубликованного документа и не обещает атомарного
снимка метаданных с байтами при посторонней конкурентной записи.

## Восстановление и отмена

* Нет публикации или доказанно не начатый INTENT: recovery57 даёт
  requiresDownload, owner.resolve(download) делает текущую попытку пригодной
  для нового raw. Coordinator не запускает скачивание сам.
* Полный native document либо Dart receipt: fresh recovery, resolve checkpoint,
  чтение опубликованного URI и обычный atomic import без source/preparer/write.
* Partial/changed/ambiguous: needsReconciliation, данные/receipt сохраняются.
  Ошибка provider/access не разрешает новый download. Очистки музыки нет.
* До публикации cancel останавливает подготовку без provider effect. После
  durably accepted publication поздняя caller cancel дренирует импорт;
  потеря lease/account/folder по-прежнему запрещает завершение.
* Provider IO, metadata read и hashing идут вне коротких SQLite fences;
  heartbeat обновляет текущую ревизию. На uncertain publication/failure
  owner.interrupt сохраняет checkpoint, до publication — fail/cancel.
* Close блокирует следующий вызов, отменяет принятую работу и ждёт всех чтений,
  закрытий/receipt finalization. MediaMetadataRetriever existing readAudio не
  имеет принудительного прерывания: accepted call дренируется до ответа.

## Квалификация и следующий шаг

Flutter fixture tests используют настоящий SQLite, private receipt journal,
file-backed opaque URI provider и общий preparer. Покрыты SQL rollback,
отсутствующий raw, native ack failure, partial, current-owner release,
heartbeat, смена аккаунта/папки, cancellation/drain, malformed metadata,
factory/close failures и accepted completion. Windows helper tests проходят
реальные MP3/M4A/FLAC, теги/обложку и quota release; отдельный тест заново
открывает persistent SQLite/journal после rollback и удаления raw.

Test provider не является Android ContentResolver, а host helper не является
новым Android runtime. Проверки56/57 на Redmi подтверждают нижние компоненты;
полный координатор потребует маленькой живой квалификации после подключения
pipeline/UI. В58 ручных проверок нет, APK57 можно оставить установленным.
Native C/media/fileops, schema13 и зависимости не менялись.

Следом: композиция network/resolver/cover/workspace/journal/coordinator на одну
явную сессию runner; private-only уборка receipt для подтверждённых completed
asset, понятное состояние retained, Android destination/quality/progress/cancel
и ручная кнопка. Автозапуска/расписания нет. Дизайн далее; рекомендации отложены.
