# Android: ручное обновление из Яндекс Музыки (59)

На ARM64 Android включён общий YandexLibraryUpdateController/runner. Likes и
выбранные свои/сохранённые чужие плейлисты, форматы MP3/M4A/FLAC, лимит по
умолчанию 3. Расписания и автозапуска нет. OAuth/сеть не запускаются обычным
воспроизведением; восстановление настроек начинается при открытии экрана.

## Папка и видимость

AndroidDownloadStorageController сохраняет выбранный SAF tree в прежнем ключе
android.download_destination.v1. Выбор вызывает app-owned callback: bookmark
атомарно добавляется в список корней и library_folders, затем его ID сохраняется
в общих update options. Полный scan не нужен; каждый завершённый download
импортируется координатором. При новом запуске bookmark сохраняет этот корень
включённым. Удаление корня через экран папок по-прежнему скрывает его музыку.

Выбор из старых сборок не подключается к загрузкам автоматически: кнопка
«Использовать выбранную папку» заново проверяет доступ и явно подключает её.
Сброс назначения очищает update options и сохранённый tree, оставляя библиотечный
корень и музыку. Конфигурация перечитывает enabled roots внутри своей операции,
поэтому новый bookmark можно выбрать до первого события watchFolders.

Перед обновлением AndroidYandexDestinationGuard сравнивает сохранённый tree с
текущим enabled root и заново проверяет read/write/create. Ошибка между двумя
записями настроек при смене папки не разрешает тихо писать в прежнюю папку.
Проверка выполняется до refresh коллекций/планирования/сетевого downloader.
Настройки папки и локальные диагностические проверки блокируются во время
обновления; update/изменения аккаунта блокируются во время проверок хранилища.
Отдельная кнопка остановки остаётся доступной. Закрытие маршрута не отменяет
принятое обновление. Закрытие приложения дренирует его до SQLite close.

## Владение ресурсами одной сессии

AppDependencies выбирает AndroidYandexDownloadPipeline только на Android,
Windows сохраняет DesktopYandexDownloadPipeline. Android workspace находится
в app-private files, canonical path вычисляется до staging. Pipeline:

1. Проверяет возможности встроенного AndroidMediaProcessingBackend56.
2. Открывает workspace и private receipt journal. Для completed receipts
   выполняется только journal.acknowledge с текущей SQLite retention authority;
   pending остаются. Доступа к документам/удаления музыки здесь нет.
3. Создаёт bounded raw pool, anonymous binary transport, общий Yandex downloader,
   preparer56 и coordinator58. Credential reader заимствован у runner.
4. Выполняет recovery прежде нового HTTP. Готовый URI импортируется без raw.
   requiresDownload разрешает resolver/download/decryption/cover/preparation,
   затем SAF publisher55, metadata read и fresh verifier54/atomic import.
5. Закрывает network/coordinator, дренирует принятое чтение, освобождает raw и
   private prepared files, journal и workspace. Ошибка открытия закрывает все
   уже построенные владельцы, включая media backend при отказе capabilities.

## Сбои и границы

Уже существующий verified asset проверяется полным SHA-256 общим checker перед
перепланированием. Повторное обновление не скачивает его снова. Сравнение по
названиям или похожему аудио не добавлено; разные версии/качества не объединяются.

После accepted SAF publication caller cancellation дренирует проверенный импорт;
до публикации можно отменить raw/preparer и повторить явной кнопкой. Потеря
аккаунта, lease или library root всегда запрещает завершение старого владельца.
После SQL rollback receipt восстанавливает полный файл без повторного copy/HTTP.

Частичная/изменённая/неоднозначная SAF запись остаётся изолированной, не удаляется
и не превращается в разрешение скачать копию. Runner прекращает запуск после
первой ошибки и передаёт needsReconciliation в UI. Если повтор не разрешил
состояние, UI просит диагностический отчёт. Автоматическое удаление/починка
partial не входит в59; отмена/завершение процесса во время provider copy может
потребовать отдельного разбора. Приложение не обещает надёжную фоновую загрузку
при принудительном завершении Android. Служба воспроизведения не менялась.

Новые события диагностики содержат только enum indices/bool: checkpoint,
coordination outcome, typed publication/validation/fingerprint status; открытие
pipeline фиксирует typed media/workspace failure. Кнопка внизу экрана Яндекса экспортирует JSON через системный save picker;
пользователь сам выбирает место и решает, отправлять ли файл. Отмена/ошибка
сохранения не показывает private paths. Новых storage permissions нет.
Paths/tags/token/URLs и тексты
исключений в журнал не передаются. Сбой диагностического recorder не влияет на
владение ресурсами. Схема13, lockfile, native codecs/fileops не меняются.

## Проверки

Новые host tests проходят синтетический loopback HTTP, шифрованные MP3/M4A/FLAC,
cover, настоящий qualified FFmpeg и SQLite, file-backed provider с opaque URI,
повторный hash-check без HTTP, SQL rollback/recovery без raw, partial quarantine,
HTTP cancellation/retry, media admission failure и late stop. Это не настоящий
ContentResolver/JNI runtime; нижние native компоненты ранее проверены на Redmi.
Отдельно проверяются сохранение bookmark при restart, fresh grant rejection до
сети, callbacks/drain/ошибки настройки и UI320px/text1.4/блокировки/navigation.

Нужна новая проверка полного пути на физическом Redmi: маленький плейлист из
1–3 треков, обновление, воспроизведение, повтор и перезапуск. Текущий аккаунт,
токены и музыкальные файлы пользователя в автоматических тестах не используются.
После этой квалификации — удобство/автообновление по расписанию и затем дизайн
по роадмапу. Улучшение рекомендаций отложено пользователем.
