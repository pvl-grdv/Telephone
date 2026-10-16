# Telephone: с чего начать читать код

Это короткая карта проекта для тех, кто изучает Swift. Здесь нет требования
сначала освоить Clean Architecture или MVVM: начни с понятного пользовательского
действия и проследи его до конкретной функции.

## Правило KISS

- **View** (`struct ...: View`) показывает данные и отправляет действия.
- **Состояние** хранится там, где им владеют: локальное — в `@State`,
  разделяемое — в существующем `@Observable`-объекте. Используй `@Bindable`,
  когда дочерней View нужна привязка к полям переданной модели.
- **Доменная логика** не должна зависеть от SwiftUI. Она живёт в `Domain/`,
  `UseCases/` или в предметных сервисах приложения.
- **Протокол** нужен, если он действительно задаёт границу или позволяет
  подменить реализацию (например, для теста); не создавай его ради одного вызова.
- **Factory / Adapter / Presenter** — не цель сами по себе. Если тип только
  возвращает `OtherType(...)` и ничего не добавляет, вызови `OtherType(...)` напрямую.
- Простота не означает убрать проверки безопасности, отмену `Task`,
  `@MainActor`, миграции данных или тесты.

## В каком порядке читать

Начни с файлов в `Telephone/`. Не пытайся читать весь проект по алфавиту.

1. **`TelephoneApp.swift`** — точка входа (`@main`) и SwiftUI-сцены.
   Здесь видно, какие окна и системные команды есть у приложения.
2. **`AccountWindowScene.swift` и `AccountWindowView.swift`** — окно
   SIP-аккаунта, компоновка набора номера и истории звонков.
3. **`CallHistoryScreen.swift`** — список, поиск, фильтры и удаление.
   **`CallHistoryRow.swift`** — отображение одной записи и ответа АТС.
4. **`CallHistoryModel.swift`** — состояние истории (`@Observable`),
   фильтрация записей, выбор, удаление и получение ответов АТС.
5. **`AccountPresentationCoordinator.swift`** — владеет моделью истории,
   соединяет окно и сценарии действий. Это инфраструктура жизненного цикла,
   не сама View.
6. **`CallHistoryViewEventTargetFactory.swift`** создаёт сценарии истории.
   **`PresentationCallHistoryRecord.swift`** преобразует запись для экрана,
   а **`CallHistoryViewPresenter.swift`** доставляет её на MainActor.
   Этот мост между акторами нужен и не является пустой обёрткой.
7. **`CompositionRoot.swift`** — где создаются зависимости. Читай его
   *после* знакомства с несколькими зависимостями, а не первым.

Когда освоишь историю, переходи к `CallDestinationComposer.swift`,
`AccountController.swift`, `CallController.swift` и только затем
к `AKSIPUserAgent.swift` и `PJSUACallbacks.swift`.

## Как течёт одно изменение экрана

Пример: пользователь вводит запрос в поиске истории.

```text
AccountWindowRootView
  → CallHistoryScreen / CallHistoryControls
  → CallHistoryViewModel.query
  → CallHistoryViewModel.rebuildVisibleRecords()
  → CallHistoryResults → CallHistoryRow
```

Обрати внимание: пользовательский ввод **не проходит через фабрику
или UseCase**. Это локальная фильтрация уже загруженных записей.

Когда данные истории поступают из хранилища, путь длиннее:

```text
SQLiteCallHistory (хранение)
  → CallHistoryRecordGetAllUseCase (получить записи)
  → ContactCallHistoryRecordGetAllUseCase (найти контакты)
  → PresentationCallHistoryRecord (подготовить данные для экрана)
  → CallHistoryViewPresenter (ожидаемая доставка на MainActor)
  → CallHistoryViewModel
  → CallHistoryScreen
```

Теперь запись попадает непосредственно в модель, без лишнего класса-посредника.
Оставшиеся мосты стоит упрощать постепенно, не ломая уведомления
об изменении истории и потокобезопасность.

## Какие границы сохранять

| Часть | Почему не стоит слепо удалять слои |
|---|---|
| `AKSIPUserAgent`, `PJSUACallbacks` | Связь Swift и библиотеки PJSIP, жизненный цикл звонков |
| CoreAudio-адаптеры | Системные устройства и ошибки платформы |
| `SQLiteCallHistory` | Хранение данных и миграции |
| `CRMGatewayClient` | Валидация сетевых ответов и граница приватного CRM-шлюза |
| `CallHistoryViewEventTarget` | Уведомления об изменении истории и дате |

Пример действительно лишней обёртки — бывший `PresenterFactory`: он
лишь создавал `SoundIOPresenter(output: view)`. Теперь в
`SoundPreferencesViewEventTarget.swift` эта строка вызывается напрямую.
**Но сам `SoundIOPresenter` пока нужен:** он преобразует модели аудиоустройств
в представление, используемое настройками.

## Полезный первый эксперимент

1. Открой `CallHistoryRow.swift` и найди `CallHistoryRow.body`.
2. Посмотри, как `statusText` превращается в `Text(statusText)`.
3. Открой `CallHistoryModel.swift` и измени поисковый запрос мысленно:
   какие записи останутся в `records`?
4. Запусти `./script/test.sh` и `./script/build.sh Debug` на Mac.
   В CI выполняются те же основные проверки плюс UI smoke-тесты.

**Договорённость для дальнейшей разработки:** удаляем один понятный
лишний слой за раз, сохраняем работающий функционал, проверяем тестами
и не создаём новую «идеальную архитектуру» вместо старой.

## Как читать три больших SwiftUI-экрана

### Набор номера

```text
CallDestinationComposer.swift — действия «Позвонить» и «Перевести»
  → CallDestinationInputView.swift — поле ввода и компактные подсказки
    → CallDestinationInputModel.swift — выбор номера, фокус, Contacts
      → CallDestinationContactIndex.swift — кеш адресной книги и поиск
```

Простой ввод меняет состояние модели, а не вызывает сеть. Поиск подсказок
выполняется асинхронно; здесь важно сохранять отмену старой задачи.

### История звонков

```text
CallHistoryScreen.swift — список, фильтр, удаление, поиск
  → CallHistoryRow.swift — имя, номер, направление и ответ АТС
    → PresentationCallHistoryRecord.swift — данные для отображения
```

Загрузка записей и команды удаления используют существующие UseCases.
Не смешивай отображение строк с логикой хранения и SIP.

### Настройки SIP-аккаунтов

```text
AccountSettingsView.swift — окно, список и подтверждения
  → AccountSettingsEditor.swift — форма SIP-настроек
    → AccountSettingsModel.swift — выбор, автосохранение и Keychain
      → AccountSettingsDraft.swift — преобразование словаря в поля и обратно
```

Редактор остаётся SwiftUI View без отдельной архитектуры. Пароли по-прежнему
обрабатываются через Keychain, а сохранение во время редактирования
контролируется моделью. Оба пути записи пароля (автосохранение и включение
аккаунта) используют один метод `saveChangedCredentials`: сначала записать
новое значение, затем удалить старую запись.


### CRM во время звонка

```text
CRMKeyLookupView.swift — состояние поиска и подтверждение привязки номера
  → CRMManualSearchView.swift — выбор поиска по ключу, email или номеру организации
    → CRMKeyLookupModel.swift — валидация, отмена и защита от устаревших ответов
      → CRMGatewayClient.swift — обмен только с приватным /v1-шлюзом
```

Не отправляй запрос при вводе каждого символа. Форма вызывает метод модели
только по явному нажатию «Найти» или Enter. Выбранный вид поиска сохраняется
при повторном открытии popover.

### Настройки CRM и ошибки

```text
CRMGatewaySettingsView.swift — адрес шлюза, токен, применение настроек
  → CRMGatewayStatusView.swift — проверка соединения и сведения о сборке шлюза
  → CRMGatewayError+Message.swift — тексты ошибок для всего приложения
```

`CRMGatewayError.crmMessage` используется не только в настройках, поэтому
локализованные сообщения вынесены из View. Разделение не меняет API, Keychain
или поведение CRM-запросов.
