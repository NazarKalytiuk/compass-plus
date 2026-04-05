# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MongoCompass (display name "Compass+") is a native macOS MongoDB GUI client built with SwiftUI. It's a Swift Package Manager executable targeting macOS 14+ that uses [MongoKitten](https://github.com/orlandos-nl/MongoKitten) 7.9+ for the MongoDB driver.

## Build & Run

This is a standard SPM executable package — there is no custom build script.

```bash
# Build (debug)
swift build

# Build release
swift build -c release

# Run from terminal (launches GUI)
swift run MongoCompass

# Resolve / update dependencies
swift package resolve
swift package update
```

A prebuilt `.app` bundle lives at `build/MongoCompass.app`. When packaging a release binary into this bundle, the executable goes in `Contents/MacOS/MongoCompass` and `Contents/Info.plist` is already configured (bundle id `com.mongocompass.app`, display name "Compass+").

There are no tests in this project — `swift test` will do nothing useful.

## Architecture

### Single source of truth: `AppViewModel`

The app uses a single `@Observable` view model (`Sources/MongoCompass/ViewModels/AppViewModel.swift`) injected via SwiftUI's `@Environment`. Every view reads state from and calls methods on this one object. It owns all services and all UI state (connection state, database tree, tabs, documents, query log, aggregation, metrics, schema, investigate, etc.).

When adding a feature, the pattern is almost always: add state + a method to `AppViewModel`, then bind the view to it. Do not create per-view view models — that breaks the established pattern.

`MongoCompassApp.swift` creates the single `AppViewModel` and uses `AppDelegate` (`NSApplicationDelegateAdaptor`) to force the SPM executable to activate as a regular GUI app (required for SPM executables on macOS).

### Layered structure

```
MongoCompassApp (entry)
  └── RootView — branches on isConnected
        ├── ConnectView (not connected)
        └── HomeView (connected)
              ├── SidebarView — DB/collection tree + nav sections
              ├── Tab bar
              └── Tab content — switches on activeTab.navSection
```

- **Models/** — pure value types (`ConnectionModel`, `TabState`, `QueryLogEntry`, `SavedQuery`, `PipelineStage`, `SavedPipeline`, `SchemaField`, `ServerMetrics`, `CurrentOp`, `SlowQueryEntry`) and the `NavSection` enum that drives the main tab content switch.
- **Services/** — stateless (or self-contained) components owned by `AppViewModel`:
  - `MongoService` — MongoKitten wrapper. Holds the connection pool and exposes typed operations. Contains the BSON <-> Swift conversion helpers (`parseJSON`, `dictToDocument`, `documentToDict`, `anyToPrimitive`, `primitiveToAny`) — reuse these rather than writing new conversion logic.
  - `StorageService` — `UserDefaults`-backed persistence for connections, query log, saved queries, and saved pipelines. Caps: 10 connections, 500 log entries.
  - `MetricsService` — background polling task (5s interval, 60-point history) for server status. Owns its own `Task`; started/stopped via `AppViewModel.startMetricsPolling()` / `stopMetricsPolling()`.
  - `SchemaService`, `CodeGeneratorService`, `ImportExportService` — pure computation.
  - `DumpRestoreService` — shells out to `mongodump`/`mongorestore`. Looks them up via `which` first, then a hardcoded list of common Homebrew/MacPorts paths in `searchPaths`.
- **Views/** — one file per `NavSection` (Explorer = `DocumentListView`/`DocumentEditorView`, `QueryLogView`, `AggregationView`, `InvestigateView`, `MetricsView`, `DumpRestoreView`, `SchemaView`, `ShellView`) plus `ConnectView`, `HomeView`, `SidebarView`. `ShellView` shells out to `mongosh` (similar path-discovery logic to `DumpRestoreService`).
- **Theme.swift** — design system: MongoDB-green/midnight color palette, plus `cardStyle()`, `pillBadge()`, `.accent` / `.ghost` / `.destructive` button styles, `ThemedTextFieldStyle` (`.themed`), `sectionHeaderStyle()`, `StatusDot`, `ThemedDivider`. Use these rather than adding new styling — the app is uniformly dark-mode (`preferredColorScheme(.dark)` is forced in `MongoCompassApp`).

### Tabs

The app supports up to 8 tabs (`AppViewModel.addTab` enforces the cap). Each `TabState` carries its own `selectedDatabase`, `selectedCollection`, `filter`/`sort`/`projection`, pagination, and `navSection`. **However**, `documents`, `pipelineStages`, `aggregationResults`, `schemaFields`, `indexes`, `slowQueries`, etc. live directly on `AppViewModel` — not on `TabState` — so switching tabs refreshes these from the newly-active tab's database/collection. When adding tab-scoped state, decide consciously whether it belongs on `TabState` or on `AppViewModel`.

### MongoDB connection quirks

`MongoService.connect(uri:)` appends `/admin` to URIs that don't specify a target database, because MongoKitten requires one. The admin database is reused for cross-database operations (`listDatabases`, `currentOp`, `killOp`, `serverStatus`) via `adminDatabase()` → `database(named:).pool[name]`, which reuses the existing connection pool.

Document counts use the `count` command (not `countDocuments`) for speed; `getDatabases()` filters out `admin`/`config`/`local`.

### Concurrency

`AppViewModel` is `@MainActor @Observable`. All Mongo operations are `async` and called from `Task { }` blocks in views or directly awaited in view-model methods. Services are marked `@unchecked Sendable` where they hold mutable connection state (`MongoService`, `MetricsService`).
