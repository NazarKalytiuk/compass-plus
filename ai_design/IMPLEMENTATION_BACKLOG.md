# MongoCompass — Implementation Backlog

> Згенеровано: 2026-05-16
> Джерело: gap-аналіз дизайну (`ai_design/Прототип-·-5_15_2026/`) vs. поточної реалізації після UI-рідизайну.

## Статус-легенда

- `[ ]` — todo
- `[~]` — in progress (взято в роботу)
- `[x]` — done
- `[!]` — blocked (вказати причину)
- `[?]` — потребує дизайн-рішення від користувача
- Інлайн-нотатка після `—` коментує що зроблено / на чому застрягло

## Конвенції

- **Файли:** абсолютні шляхи від кореня проєкту, з line ranges де доречно
- **Складність:** **S** (~15 хв, локальний edit), **M** (~1 год, кілька файлів + проста логіка), **L** (~2-3 год, новий model-field / новий service / нова view-секція)
- **[P]** — таску можна виконувати паралельно з іншими `[P]` тасками з ІНШИХ файлів
- Після кожної таски: `swift build` має бути чистим
- Дотримуватись `Theme.swift` токенів і single-`AppViewModel`-патерну (див. `CLAUDE.md`)

---

## P1 — High impact (почати тут)

### Dump / Restore

- [x] **1. Пробросити `--oplog` / `--excludeIndexes` / `numParallelCollections` в `mongodump`** — **S**
  - Файли: `Sources/MongoCompass/Services/DumpRestoreService.swift:68-97`, `Sources/MongoCompass/Views/DumpRestoreView.swift:560-580` (runDump)
  - Розширити `dump(...)` параметрами `oplog: Bool, numParallel: Int, excludeIndexes: Bool`. Передати з view-стейту (`dumpOplog`, `dumpParallel`, `dumpExcludeIndexes`).
  - Аналогічно для `restore(...)`: `oplogReplay: Bool, numParallel: Int, noIndexRestore: Bool, maintainInsertionOrder: Bool`.

- [x] **2. Реалізувати Restore Strategy `Merge` / `Skip existing`** — **S**
  - Файли: `Sources/MongoCompass/Services/DumpRestoreService.swift:102-129`, `Sources/MongoCompass/Views/DumpRestoreView.swift:610-625`
  - `drop=true` (Drop+restore), `--noObjcheck` для Merge, `--stopOnError` + skip для Skip existing. Замінити поточний boolean `drop` на enum.

### Document Explorer

- [x] **3. Реалізувати Table-режим у DocumentListView** [P] — **L** — note: sticky header через Section pinnedViews + type-tinted cells (string/number/bool/null), bool через violet pillBadge
  - Файли: `Sources/MongoCompass/Views/DocumentListView.swift` (де знаходиться `viewMode` segmented)
  - Створити `tableModeBody` з flat-сітки (`LazyVGrid` або `Table`): колонки auto-detected з union усіх top-level ключів першої сторінки. Mono-cells, type-tinted (string=success, number=warning, bool=violet, null=neutral). Sticky header. Reuse `pillBadge` для типів.

- [x] **4. Реалізувати JSON-режим у DocumentListView** [P] — **S**
  - Файли: `Sources/MongoCompass/Views/DocumentListView.swift`
  - `jsonModeBody`: повний codeBg ScrollView з `JSONSerialization.data(withJSONObject:options:.prettyPrinted)` для `viewModel.documents`. Один великий блок з line-numbers gutter.

### Metrics

- [x] **5. Додати Replication Lag KPI + chart** — **M** — note: 6-та KPI-картка з sparkline (danger color); chart-only-card не додавався, бо backlog згадує лише KPI
  - Файли: `Sources/MongoCompass/Services/MetricsService.swift`, `Sources/MongoCompass/Models/ServerMetrics.swift`, `Sources/MongoCompass/Views/MetricsView.swift`
  - У `MetricsService.poll()` додати `db.adminCommand({replSetGetStatus: 1})` (через `mongoService.adminDatabase()`). Парсити `members[].optimeDate` diff від PRIMARY. Зберігати в новому полі `ServerMetrics.replLagMs: Int?`. Додати 6-й KPI card "Repl lag" з danger color.

- [x] **6. Реальний PNG-export через `ImageRenderer`** — **S**
  - Файли: `Sources/MongoCompass/Views/MetricsView.swift` (`exportSnapshot()`)
  - Використати `ImageRenderer(content: chartsGrid)` + `cgImage` + `NSImage` → save panel. Replace stub.

### Investigate

- [x] **7. Nav-badge для Investigate (slow + active ops count)** — **S**
  - Файли: `Sources/MongoCompass/Views/SidebarView.swift`, `Sources/MongoCompass/ViewModels/AppViewModel.swift`
  - Computed property `investigateBadgeCount: Int` = `slowQueries.count + currentOps.filter { $0.duration > 1000 }.count`. Pill `is-danger` на nav-row якщо > 0.

### Query Log

- [x] **8. Розширити `QueryLogEntry` `examined`, `plan`, `client`, `errorMessage`** — **M** — note: plan/examined через `explainFind` (best-effort, не throws); error log entries додано для всіх 5 ops; client = "compass+" коли запит йде з нас
  - Файли: `Sources/MongoCompass/Models/QueryLogEntry.swift`, `Sources/MongoCompass/ViewModels/AppViewModel.swift` (де створюються entries в `loadDocuments`/`replayQuery`/etc.), `Sources/MongoCompass/Views/QueryLogView.swift` (`summaryLine`, `statusPill`, detail tabs)
  - Додати поля з default-значеннями для backward compat. У `mongoService` методах extract з MongoKitten cursor metadata (`stats.totalKeysExamined`, `executionStats`). Summary line: `examined N / returned M · plan: IXSCAN`. Detail-tab `Explain` показує plan tree.

---

## P2 — Medium impact

### Connect

- [x] **9. Реальна діагностика (DNS / TLS / Auth) при error** — **M** — note: DNS через Foundation.Host; TLS probe через NWConnection з 6s deadline; auth через ping-after-connect
  - Файли: `Sources/MongoCompass/Services/MongoService.swift`, `Sources/MongoCompass/Views/ConnectView.swift:251-280`
  - Перед `connect(uri:)` запустити: (1) `Host.lookup` для DNS + час, (2) `NWConnection` TLS handshake probe + парсинг version, (3) auth attempt. Зберегти результат у `ConnectionDiagnostics` struct з `dnsMs/tlsVersion/authError`. Замінити hard-coded значення в `diagRow`.

- [x] **10. Toggle "Save connection" реально гейтує `addConnection`** — **S**
  - Файли: `Sources/MongoCompass/ViewModels/AppViewModel.swift:108-130` (`connect(uri:name:)`), `Sources/MongoCompass/Views/ConnectView.swift:331`
  - `connect` приймає `save: Bool = true`. View передає `saveConnection`-стейт.

### Aggregation

- [x] **11. Drag-and-drop пайплайн-стейджів** [P] — **M** — note: custom `.onDrag`/`.onDrop` через DropDelegate, NSItemProvider з UUID; зберігся card-look
  - Файли: `Sources/MongoCompass/Views/AggregationView.swift` (де рендериться `pipelineColumn`)
  - Перейти з `VStack` на `List` з `.onMove { source, destination in viewModel.movePipelineStage(from: source, to: destination) }`. Або custom `.onDrag/.onDrop` для збереження стилю карток.

- [x] **12. Per-stage timing (`8.4 ms · index used`)** — **L** — note: single full-pipeline explain з executionStats verbosity, парситься $cursor + non-$cursor stages; запускається автоматично після runAggregation
  - Файли: `Sources/MongoCompass/Services/MongoService.swift`, `Sources/MongoCompass/Models/PipelineStage.swift`, `Sources/MongoCompass/ViewModels/AppViewModel.swift`, `Sources/MongoCompass/Views/AggregationView.swift` (stage-meta row)
  - Реалізувати `runPipelineIncrementally`: для кожного prefix-pipeline робити `aggregate().explain()` + timing. Store per-stage `outCount: Int`, `ms: Double`, `usedIndex: String?` на `PipelineStage`. Рендерити в `stageMeta` рядку: dot color (success якщо < 100ms, warning > 100ms), `Out: N docs`, `Mms · index used`.

- [x] **13. "Slow stage" hint з пропозицією індексу** — **S**
  - Файли: `Sources/MongoCompass/Views/AggregationView.swift`
  - На stage-meta: якщо `ms > 100`, показати warning-card з "Consider index hint on `{field: 1}`". Поле детектується з `$match`-stage JSON.
  - Залежність: задача №12.

### Document Editor

- [x] **14. "Insert & clone" footer button** — **S**
  - Файли: `Sources/MongoCompass/Views/DocumentEditorView.swift` (footer section)
  - Кнопка між Cancel і Insert document. Поведінка: викликати `viewModel.insertDocument(...)`, після успіху clear `_id` field, тримати модал відкритим. Disabled у edit-mode (тільки insert).

- [x] **15. Schema-based lint з `$jsonSchema` validator** — **L** — note: listCollections для validator; fallback на type-heuristic коли validator nil; additionalProperties: false також підтримано
  - Файли: `Sources/MongoCompass/Services/MongoService.swift` (новий метод `getValidator(database:collection:)`), `Sources/MongoCompass/Services/SchemaService.swift`, `Sources/MongoCompass/Views/DocumentEditorView.swift` (де `lintEngine`)
  - Запит `db.runCommand({listCollections: 1, filter: {name: <coll>}})` → парсити `options.validator.$jsonSchema`. Передати в lint як `expectedTypes: [String: BSONType]`, `enums: [String: [String]]`, `requiredFields: Set<String>`. Замінити type-heuristic секцію.

### Schema

- [x] **16. "Re-sample" toolbar button** — **S** — note: button уже існував; додано progress-pill "Sampling…" поряд
  - Файли: `Sources/MongoCompass/Views/SchemaView.swift` (toolbar)
  - Primary CTA праворуч від segmented sample-size. Викликає `viewModel.analyzeSchema(sampleSize: selectedSize)` повторно з progress-pill під час виконання.

- [x] **17. "Deepest path" + sparse delta в stat cards** — **M** — note: deepest path вже був; sparse meta тепер показує "watch X, Y, Z" з топ-3 sparse шляхами
  - Файли: `Sources/MongoCompass/Services/SchemaService.swift`, `Sources/MongoCompass/Views/SchemaView.swift`
  - У `analyzeSchema(...)` додати computed: `deepestFieldPath: String`, `sparseFields: [String]`. У cards: max-depth → "deepest: profile.address.geo.lat", sparse → "watch trial.*" (топ-3 sparse fields з префіксом).

### Investigate

- [x] **18. Slow queries: `Mean ms` + `P99 ms` + `Count` + `Last seen` колонки** — **L** — note: post-process aggregation у Swift (group by op+ns+plan); nearest-rank p99
  - Файли: `Sources/MongoCompass/Models/SlowQueryEntry.swift`, `Sources/MongoCompass/Services/MongoService.swift` (`getSlowQueries`), `Sources/MongoCompass/Views/InvestigateView.swift`
  - `SlowQueryEntry` додати: `meanMs`, `p99Ms`, `count`, `lastSeen`. Сервіс aggregates slow queries з system.profile або поточного in-memory queryLog (group by query pattern hash). View: 4 додаткові колонки.

- [x] **19. Locks колонка `R 2 / W 0` у Current Operations** — **S**
  - Файли: `Sources/MongoCompass/Models/CurrentOp.swift`, `Sources/MongoCompass/Services/MongoService.swift` (`getCurrentOps`), `Sources/MongoCompass/Views/InvestigateView.swift`
  - Додати `readLocks: Int`, `writeLocks: Int` з `currentOp.locks.acquireCount.r/w`. Mono-cell у таблиці.

### Shell

- [x] **20. Multi-line input (axis: .vertical, lineLimit 1...6)** — **S** — note: arrow-history підпорядкована: ↑/↓ ігноруються коли input уже багаторядковий (caret-нав), ⌘↵ submit лишається
  - Файли: `Sources/MongoCompass/Views/ShellView.swift:307-323` (термінальний input)
  - Замінити single-line TextField на multi-line з `axis: .vertical`. Enter → newline, ⌘↵ → submit. Update placeholder.

---

## P3 — Косметика та nice-to-have

### Connect

- [x] **21. "Read the URI guide ↗" відкриває MongoDB docs** [P] — **S**
  - Файли: `Sources/MongoCompass/Views/ConnectView.swift:570-583` (helpText)
  - Обгорнути в `Link` → `https://www.mongodb.com/docs/manual/reference/connection-string/`.

- [x] **22. Favorite color сортує/групує recent connections** [P] — **S**
  - Файли: `Sources/MongoCompass/Views/ConnectView.swift`
  - Якщо `environment` selected, recent-row з тією env робити sticky зверху (через окремий VStack section).

### Document Explorer

- [x] **23. Auto-detected content tags на doc-cards** [P] — **M** — note: tier/role/status/verified вже були; додано `trialEndsAt > now` → "trialing" info
  - Файли: `Sources/MongoCompass/Views/DocumentListView.swift` (de doc-card head)
  - Function `detectTags(doc: [String: Any]) -> [(String, BadgeKind)]`:
    - `tier == "pro"` → "tier · pro" accent
    - `verified == false` → "2FA pending" warning
    - `trialEndsAt > Date()` → "trialing" info
    - `status == "active"` → "active" success
  - Рендерити максимум 3 pills на documenti.

- [x] **24. doc-meta рядок "14 fields · 1.2 KB · indexed"** [P] — **S**
  - Файли: `Sources/MongoCompass/Views/DocumentListView.swift`
  - У doc-head: `\(doc.keys.count) fields · \(estimatedBSONSize) · \(indexed ? "indexed" : "no index")`. BSON size: rough estimate з JSONSerialization byte count.

- [x] **25. Streaming skeleton "loading…" doc-card між сторінками** [P] — **M** — note: 2 skeleton cards внизу під час isLoading коли є попередні docs (page transition); cold-load → loadingView
  - Файли: `Sources/MongoCompass/Views/DocumentListView.swift`, `Sources/MongoCompass/ViewModels/AppViewModel.swift`
  - При `loadMore()` показувати 1-2 skeleton cards з muted dot-pattern замість значень. Розчиняти при готовості.

### Aggregation

- [x] **26. Toolbar "Explain" button** [P] — **S** — note: sheet з prettyprinted explain output + copy
  - Файли: `Sources/MongoCompass/Views/AggregationView.swift` (toolbar)
  - Кнопка біля Run. Викликає `viewModel.explainPipeline()` → показує result в codeBg modal/popover з expand tree.

### Schema

- [x] **27. Sample-diff: "+3 new fields since last sample"** — **L** — note: snapshot stored as flat path list per db.collection в UserDefaults; meta показує "+N new · -M gone since last sample"
  - Файли: `Sources/MongoCompass/Models/SchemaField.swift`, `Sources/MongoCompass/Services/SchemaService.swift`, `Sources/MongoCompass/Services/StorageService.swift`
  - Persisting попереднього snapshot per `db.collection` в UserDefaults. При re-sample обчислити diff (added/removed/changed). Stat-card delta.

### Investigate

- [x] **28. "Filter…" над Current Ops + "Lower threshold…" над Slow Queries** [P] — **M** — note: filter — namespace/op-type/min-duration; threshold персист в AppStorage
  - Файли: `Sources/MongoCompass/Views/InvestigateView.swift`
  - Popover з: filter по namespace/op-type/min-duration. Threshold-popover: number stepper в ms, persist в `AppStorage`.

- [x] **29. "Export report" реально експортує JSON** [P] — **S**
  - Файли: `Sources/MongoCompass/Views/InvestigateView.swift`
  - `fileExporter` з `InvestigateReportDocument` (struct з currentOps + slowQueries + indexRecommendations + timestamp).

### Metrics

- [x] **30. Memory chart: додати WT cache line** — **S**
  - Файли: `Sources/MongoCompass/Models/ServerMetrics.swift`, `Sources/MongoCompass/Services/MetricsService.swift`, `Sources/MongoCompass/Views/MetricsView.swift`
  - Додати `wtCacheMB: Double` зі `serverStatus.wiredTiger.cache."bytes currently in the cache"`. Dual-line chart у Memory.

### Dump / Restore

- [x] **31. "Dry run" реально показує команду без запуску** [P] — **S**
  - Файли: `Sources/MongoCompass/Views/DumpRestoreView.swift`
  - Кнопка Dry run: побудувати full command-line (`mongodump --uri ... --out ...`) і показати в нижньому log як info-line, без `process.run()`.

- [x] **32. "Save preset…" зберігає форму в UserDefaults** [P] — **M** — note: DumpPreset model + sheet з name + Presets menu в toolbar (load/delete)
  - Файли: `Sources/MongoCompass/Models/DumpPreset.swift` (новий), `Sources/MongoCompass/Services/StorageService.swift`, `Sources/MongoCompass/Views/DumpRestoreView.swift`
  - Sheet з name input. Зберігати всі toggle/path/extras state. Завантажувати через Menu в toolbar.

- [x] **33. Real "Est. size" через `collStats`** [P] — **M** — note: для All-scope сумує collStats по всіх collections; gzip × 0.25
  - Файли: `Sources/MongoCompass/Services/MongoService.swift`, `Sources/MongoCompass/Views/DumpRestoreView.swift`
  - При зміні DB/collection: `db.runCommand({collStats: <coll>})` → `size` field. Якщо `gzip` → estimate × 0.25. Замінити placeholder "320 MB".

### Shell

- [x] **34. Syntax highlighting в output через `AttributedString`** — **L** — note: regex passes для strings/BSON wrappers/$-keys/numbers/bool, AttributedString.Index via UTF-16 offset
  - Файли: `Sources/MongoCompass/Views/ShellView.swift` (terminalLineView)
  - Простий lexer: regex для `"strings"`, numbers, `ObjectId/ISODate/UUID` keywords, `$keys`, brackets. Build `AttributedString` per output line з кольорами з Theme (`codeKey/codeString/codeNumber/codeKeyword`).

- [x] **35. Blinking caret animation** [P] — **S**
  - Файли: `Sources/MongoCompass/Views/ShellView.swift` (`liveTail`)
  - `@State private var caretVisible = true` + `Timer` 600ms. Або `withAnimation(.linear(duration: 0.5).repeatForever()) { opacity }`.

### Query Log

- [x] **36. `DatePicker` для time-range custom** [P] — **M**
  - Файли: `Sources/MongoCompass/Views/QueryLogView.swift` (timeRangeBlock)
  - При `quickRange == .custom`: показати 2 нативні `DatePicker(.compact)` замість readonly text. Зберегти в `@State customRangeStart/End`.

- [x] **37. Advanced search syntax (`$lookup OR slow >= 1000ms`)** [P] — **L** — note: OR-grouped tokens; field:value (op/coll/db/plan/client); slow </> <= >= Nms; fallback на substring
  - Файли: `Sources/MongoCompass/Views/QueryLogView.swift` (filtering logic)
  - Mini parser: токени `field:value`, `>=`, `<`, `OR`, `AND`, plain text. Підтримати `slow >= Nms`, `op:aggregate`, `coll:users`. Fallback на substring якщо parse fails.

### Sidebar

- [x] **38. Count-badges на nav-rows** [P] — **S** — note: queryLog/investigate уже були; додано Schema (count detected fields)
  - Файли: `Sources/MongoCompass/Views/SidebarView.swift`
  - Query Log: `\(viewModel.queryLog.count.formatted())`. Investigate: див. таску №7. Schema: count detected fields (опціонально).

- [x] **39. ⌘K registered hotkey для search-field focus** [P] — **S**
  - Файли: `Sources/MongoCompass/Views/SidebarView.swift`, `Sources/MongoCompass/MongoCompassApp.swift`
  - `Button("") { ... }.keyboardShortcut("k", modifiers: .command).hidden()` в hierarchy. Action: focus search через `@FocusState`.

### Document Editor

- [x] **40. Charset / line-ending hint dynamic** [P] — **S**
  - Файли: `Sources/MongoCompass/Views/DocumentEditorView.swift` (UTF-8/LF pills)
  - Реально детектувати з `documentContent`: contains `\r\n` → "CRLF", else "LF". `data(using: .utf8)` success → "UTF-8". Trivial computed.

---

## P4 — Backend prerequisites (нерозблоковано без)

> Виконати **перед** залежними тасками з P1-P3.

- [x] **41. Розширити `ConnectionDiagnostics` struct + `MongoService.diagnose(uri:)` method**
  - Розблоковує: №9.

- [x] **42. Додати `oplog/parallel/extras` параметри в `DumpRestoreService` API** — done as part of #1, #2
  - Розблоковує: №1, №2 (фактично частина №1).

- [x] **43. `MetricsService` запит `replSetGetStatus`** — done as part of #5
  - Розблоковує: №5.

- [x] **44. `QueryLogEntry` нові поля `examined/plan/client/errorMessage`** — done as part of #8
  - Розблоковує: №8, №18, №37.

- [x] **45. `PipelineStage` нові поля `outCount/ms/usedIndex`**
  - Розблоковує: №12, №13.

---

## Прогрес

| Tier | Total | Done | In progress | Blocked |
|------|------:|-----:|------------:|--------:|
| P1   |     8 |    8 |           0 |       0 |
| P2   |    12 |   12 |           0 |       0 |
| P3   |    20 |   20 |           0 |       0 |
| P4   |     5 |    5 |           0 |       0 |
| **Total** | **45** | **45** | **0** | **0** |

---

## Нотатки виконавцю

- **Не торкатись** `Theme.swift` — токени готові. Якщо потрібен новий колір — спочатку обговорити.
- **Не виносити** state з `AppViewModel` у per-view ViewModels. Якщо state суто-UI (наприклад, `expandedEntryId`) — лишити в view як `@State`. Якщо share-able або persists — на `AppViewModel`.
- **При додаванні модельних полів** з backward-compat: давати default-значення, аби існуючий JSON у `UserDefaults` (через `StorageService`) не валив декодинг.
- **Конкурентність:** усі нові методи в `MongoService` мають бути `async throws`. `MetricsService` task — `@unchecked Sendable`.
- **Перевірка візуалу:** після кожної UI-таски запропонувати користувачу `swift run MongoCompass` (не запускати самому, бо це блокує сесію).
