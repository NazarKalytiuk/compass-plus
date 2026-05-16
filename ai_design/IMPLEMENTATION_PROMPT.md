# Промпт для нового агента: імплементація MongoCompass backlog

> Скопіюй текст нижче в нову сесію Claude Code, відкриту в директорії
> `/Users/nazarkalituk/Documents/desktop_apps/MongoCompass`.

---

## ПРОМПТ (скопіюй цей блок)

Ти підхоплюєш MongoCompass implementation backlog. **Перше — прочитай `ai_design/IMPLEMENTATION_BACKLOG.md` повністю.** Там 45 тасок розбитих на P1 (high-impact, 8 шт), P2 (medium, 12), P3 (косметика, 20), P4 (backend-prereqs, 5).

### Контекст проєкту

- Native macOS SwiftUI app (Compass+) — MongoDB GUI. Swift Package executable, macOS 14+, MongoKitten 7.9.
- Архітектура: single `@MainActor @Observable` `AppViewModel` ін'єктується через `@Environment`. Усі state і services — на ньому. Per-view view-models не створюємо.
- Дизайн-source: `ai_design/Прототип-·-5_15_2026/styles.css` + 12 HTML-екранів. Theme-токени вже змаплені в `Sources/MongoCompass/Theme.swift`.
- Конвенції (тонувальне лейерування, soft shadows, surface0..surface3, codeBg, pillBadge): `CLAUDE.md` у корені + перші рядки `Theme.swift`.
- Білд: `swift build` (без тестів). Має бути чистий після кожної таски.

### Workflow для кожної таски

1. **Pick:** Відкрий backlog, візьми перший `[ ]` у P1 (або резюмуй `[~]` якщо сесія перервалась). Зміни його на `[~]` через Edit. Не бери одночасно більше одної задачі під свою прямі руки.

2. **Explore (якщо треба):** Якщо file paths/line ranges в таску застаріли або не сходяться зі станом коду — **спавни Explore subagent** ("medium" breadth) з конкретним питанням. Не читай папками самостійно. Приклад:
   ```
   Agent({ subagent_type: "Explore", description: "Locate viewMode segmented",
     prompt: "Find where `viewMode` enum and segmented picker are declared in
     Sources/MongoCompass/Views/DocumentListView.swift. Return file:line range." })
   ```

3. **Plan (для L-tasks і всіх з P4):** Перед кодом — **спавни Plan subagent** з:
   - вмістом відповідного HTML з `screens/`
   - поточним кодом view/service
   - конкретним питанням: "What's the minimal change to support X?"
   Очікуй короткий step-by-step. Не делегуй plan для S-tasks — там code-edit очевидний.

4. **Implement:** Прямі правки через Edit/Write. Дотримуйся `Theme.swift` токенів (ніколи raw RGB), pillBadge для бейджів, `cardStyle()` для карток, `surface3` для well-ів. Якщо потрібен новий model-field — дай default-value для backward compat зі збереженим JSON у `UserDefaults`.

5. **Build:** Після кожної таски — `swift build` (бекграунд OK, але дочекайся результату перед наступною). Якщо помилка — fix відразу, не накопичуй.

6. **Mark done:** `[~]` → `[x]`. Якщо результат не очевидний (наприклад, обрали альтернативу) — допиши 1-line note після назви: `[x] N. Назва — note: pojednu enum замість Bool за пропозицією Plan-agent`.

7. **Update прогрес-таблицю** внизу backlog кожні 5 закритих тасок.

### Паралелізація через subagents

- Таски з міткою `[P]` (parallelizable) працюють з **різними** файлами. Якщо такі стоять поряд — спавни кілька **general-purpose** агентів в одному message з конкретним брифом кожному (файл, що змінити, які рядки, що очікувати). Приклад:
  ```
  // Single message with two Agent calls:
  Agent({ subagent_type: "general-purpose", description: "Task #21: URI guide link",
    prompt: "Implement task #21 from ai_design/IMPLEMENTATION_BACKLOG.md.
    Wrap the 'Read the URI guide ↗' text in ConnectView.swift line ~570 with
    SwiftUI Link to https://www.mongodb.com/docs/manual/reference/connection-string/.
    Report exact diff." })
  Agent({ subagent_type: "general-purpose", description: "Task #38: nav badges", ... })
  ```
- **НЕ паралелізуй:**
  - Таски з тих самих файлів (merge conflict).
  - Таски з P4 (backend prereq) — вони послідовні і потрібні в певному порядку.
  - Будь-яку таску що змінює `AppViewModel.swift` — він load-bearing.

### Reporting

- Після кожної P-тіри (P1, P2, P3) — **звіт на 2-3 речення**: що змінено, що ще лишилось, чи є blockers. Не дублюй вміст backlog.
- Якщо таска blocked (наприклад, потрібен method у MongoKitten що недоступний на 7.9): `[!]` + 1-line чому. Переходь до наступної.
- Якщо щось потребує дизайн-рішення від користувача (UX-розгалуження): `[?]` + питання. Зупинись і запитай у chat.

### Перевірка візуалу

- Перед кожною UI-таскою — **перечитай відповідний HTML** з `ai_design/Прототип-·-5_15_2026/screens/` (тільки той що стосується таски). Не читай усі підряд.
- Після візуальної таски — **запропонуй користувачу** запустити `swift run MongoCompass` (НЕ запускай сам — це блокує сесію). Чекай 'ok' або фідбек, тоді переходь далі.

### Заборонено

- Торкатись `Theme.swift` без явного "ok" від користувача (токени уже стабілізовані).
- Створювати per-view ViewModels (порушує single-`AppViewModel` патерн).
- Робити git commit без явної інструкції "закомить" від користувача.
- Запускати `swift run` у foreground (блокує).
- `--no-verify`, `--force` flag-и для будь-чого.

### Старт

Розпочни з **таски №1** (P1 — Dump/Restore флаги). Перед кодом — Explore subagent, щоб впевнитись що signatures `dump/restore` в `DumpRestoreService.swift` не змінились від останньої сесії. Працюй послідовно через P1 (там 8 тасок), потім стоп і дай мені звіт перед переходом до P2.

Поточна дата: 2026-05-16. Працюємо в `main` бранчі. Build має бути чистим. Поїхали.

---

## КІНЕЦЬ ПРОМПТУ
