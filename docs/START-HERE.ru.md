# Telephone: с чего начать читать код

Это короткая карта Telephone 2 для тех, кто изучает Swift: начни с
**действия пользователя**, а не с названий архитектурных шаблонов.
Приложение использует SwiftUI и Swift 6 со строгой проверкой конкурентности,
рассчитано на Apple silicon и macOS 26+.
Установка и сборка описаны в [README](../README.md).

## 1. С каких файлов начать

1. [`TelephoneApp.swift`](../Telephone/TelephoneApp.swift) — точка входа
   `@main`, сцены и системные команды.
2. [`AccountWindowView.swift`](../Telephone/AccountWindowView.swift) —
   экран SIP-аккаунта, набор номера и история.
3. [`CallHistoryScreen.swift`](../Telephone/CallHistoryScreen.swift) —
   SwiftUI-список, фильтры, поиск и действия.
4. [`CallHistoryModel.swift`](../Telephone/CallHistoryModel.swift) —
   `@Observable`-состояние, выбор и фильтрация.
5. [`CompositionRoot.swift`](../Telephone/CompositionRoot.swift) —
   создание зависимостей. Читай его **после** нескольких сценариев ниже.

[`AccountWindowScene.swift`](../Telephone/AccountWindowScene.swift)
создаёт SwiftUI-сцену, а
[`AccountPresentationCoordinator.swift`](../Telephone/AccountPresentationCoordinator.swift)
управляет жизненным циклом окна и владеет историей.

## 2. Пять пользовательских сценариев

### Набор номера

```text
CallDestinationInputView → CallDestinationInputModel
  → CallDestinationComposer → AccountController → SIP
```

[`CallDestinationInputView.swift`](../Telephone/CallDestinationInputView.swift)
отображает поле и подсказки;
[`CallDestinationInputModel.swift`](../Telephone/CallDestinationInputModel.swift)
владеет вводом, выбором и отменяемым поиском.
[`CallDestinationContactIndex.swift`](../Telephone/CallDestinationContactIndex.swift)
читает и кеширует Contacts.
[`CallDestinationComposer.swift`](../Telephone/CallDestinationComposer.swift)
отправляет команду через
[`AccountController.swift`](../Telephone/AccountController.swift).

Ввод текста **не инициирует SIP-вызов**. Устаревшие результаты подсказок
не должны заменять результаты более нового поиска.

### Входящий звонок

```text
AKSIPCallEventSource → CallSession → CallPresentationCoordinator
  → CallWindowModel → CallWindowView
```

[`CallPresentationCoordinator.swift`](../Telephone/CallPresentationCoordinator.swift)
управляет ответом, DTMF, переводом и задачами окна;
[`CallWindowView.swift`](../Telephone/CallWindowView.swift)
отображает их через SwiftUI.
[`AKSIPUserAgent.swift`](../Telephone/AKSIPUserAgent.swift)
и [`PJSUACallbacks.swift`](../Telephone/PJSUACallbacks.swift)
соединяют Swift с PJSIP: изучай их после интерфейса.
Задачи автозакрытия, повторного набора и статуса должны
**отменяться независимо**.

### История звонков

Обычный поиск работает только с уже полученными записями:

```text
CallHistoryScreen → CallHistoryViewModel.query
  → rebuildVisibleRecords() → CallHistoryRow
```

Сеть и UseCase в этом пути не участвуют. Найди `Text(statusText)` в
[`CallHistoryRow.swift`](../Telephone/CallHistoryRow.swift).

Загрузка из базы проходит через реальные границы:

```text
SQLiteCallHistory → CallHistoryRecordGetAllUseCase
  → ContactCallHistoryRecordGetAllUseCase
  → CallHistoryViewPresenter → CallHistoryViewModel → CallHistoryScreen
```

[`CallHistoryViewEventTargetFactory.swift`](../Telephone/CallHistoryViewEventTargetFactory.swift)
собирает сценарии;
[`CallHistoryViewPresenter.swift`](../Telephone/CallHistoryViewPresenter.swift)
готовит `PresentationCallHistoryRecord` и доставляет данные на `MainActor`;
[`CallHistoryViewEventTarget.swift`](../Telephone/CallHistoryViewEventTarget.swift)
реагирует на обновления истории и смену дня.

Для **видимых входящих звонков, не отвеченных на этом Mac**, история
может дополнительно запросить ответ АТС. Локально принятый SIP-звонок
с положительной длительностью имеет приоритет над удалённым ответом.
Ответы для неизменённых записей повторно используются; ручное обновление
отправляет запрос снова.
[Контракт ответа АТС](CRM-gateway.md#incoming-call-answer-lookup-ats).

### Настройки SIP-аккаунта

```text
AccountSettingsView → AccountSettingsEditor
  → AccountSettingsModel → Settings / Keychain
```

[`AccountSettingsEditor.swift`](../Telephone/AccountSettingsEditor.swift)
показывает форму;
[`AccountSettingsModel.swift`](../Telephone/AccountSettingsModel.swift)
управляет черновиком, сохранением и Keychain;
[`AccountSettingsDraft.swift`](../Telephone/AccountSettingsDraft.swift)
преобразует поля и настройки.

Сохранение и включение SIP-аккаунта используют `saveCredentialChanges`:
сначала записать новый секрет, затем удалить старый. Операции Keychain
не перекрываются; ошибки удаления нельзя игнорировать.

### CRM во время звонка и без звонка

```text
CRMKeyLookupView / CRMManualSearchView
  → CRMKeyLookupModel → CRMGatewayClient → /v1 Gateway
```

[`CRMKeyLookupModel.swift`](../Telephone/CRMKeyLookupModel.swift)
управляет запросами и защитой от устаревших результатов.
[`CRMWorkspaceScene.swift`](../Telephone/CRMWorkspaceScene.swift)
открывает отдельное окно **CRM → Search organization…** (⇧⌘K).
[`CRMCustomerInventoryView.swift`](../Telephone/CRMCustomerInventoryView.swift)
показывает ключи, программы и версии с локальной фильтрацией.
[`CRMGatewayClient.swift`](../Telephone/CRMGatewayClient.swift)
отправляет типизированные запросы на приватный `/v1`-шлюз.

Поиск по ключу, email или регистрационному номеру отправляется по
«Найти» / Enter, не на каждый символ. Привязка телефонного номера
требует подходящего звонка, явного подтверждения и проверки шлюзом.
Сведения CRM не сохраняются в локальной истории.
[Протокол Gateway с примерами JSON](CRM-gateway.md).

## 3. Где KISS действительно помогает

- **View** показывает данные и действия. Локальное состояние — в `@State`,
  разделяемое — в `@Observable`; `@Bindable` нужен для привязки
  к полям переданной модели.
- **Доменная логика** не зависит от SwiftUI: см. `Domain/`, `UseCases/`
  и предметные сервисы.
- **Протокол / Factory / Adapter / Presenter** нужен ради настоящей
  границы, преобразования или тестовой подмены, а не одного конструктора.
- **Coordinator** оправдан владением сеансом, окном и отменяемыми задачами.
- Не упрощай за счёт проверок PJSIP/CoreAudio и Gateway, миграций SQLite,
  `@MainActor`, отмены `Task`, Keychain или тестов.

## 4. Первый эксперимент

1. Проследи поле поиска в [`CallHistoryScreen.swift`](../Telephone/CallHistoryScreen.swift)
   до `CallHistoryViewModel.query` и `rebuildVisibleRecords()`.
2. Найди `Text(statusText)` в [`CallHistoryRow.swift`](../Telephone/CallHistoryRow.swift).
3. Предскажи, какие строки останутся после фильтрации, и проверь
   [тесты модели истории](../TelephoneTests/CallHistoryViewModelTests.swift).
4. На Mac выполни:

   ```sh
   ./script/test.sh
   ./script/build.sh Debug
   ```

CI дополнительно проверяет собранный пакет и UI smoke-тесты.
Удаляй один лишний слой за раз и проверяй работающий функционал.

## 5. Дополнительные документы

- [`README.md`](../README.md) — установка, сборка, ограничения, Shortcuts.
- [`AGENTS.md`](../AGENTS.md) — обязательные правила разработки и CI.
- [`CRM-gateway.md`](CRM-gateway.md) — все маршруты, JSON, права и ошибки.
- [`CHANGELOG.md`](../CHANGELOG.md) и история Git — выполненные KISS-изменения,
  которые не нужно изучать перед первым чтением кода.
