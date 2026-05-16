# Compass+

A native macOS GUI for MongoDB — fast, dark, and built with SwiftUI.

Connect to any MongoDB URI, explore databases and collections, build and preview aggregation pipelines with autocomplete, analyze schemas with value statistics, watch live server metrics, and open a real `mongosh` shell.

## Install

Download the latest release from the [Releases page](../../releases/latest):

- **`MongoCompass.dmg`** — drag `MongoCompass.app` into the `Applications` folder.
- **`MongoCompass.zip`** — unzip and move the `.app` wherever you like.

Releases are **ad-hoc signed**, not notarized. On first launch, macOS Gatekeeper will block the app. To open it:

1. Right-click `MongoCompass.app` in Finder → **Open**
2. Confirm in the dialog that appears

After that, double-click works normally.

## Features

- **Connect** — any MongoDB URI (`mongodb://`, `mongodb+srv://`). On failure the screen shows a real DNS/TLS/Auth diagnose pass with phase-by-phase timings. Recents are grouped by favourite environment color.
- **Explorer** — browse databases and collections, CRUD on documents, saved queries, pagination. Three view modes: **Tree** (collapsible KV), **Table** (sticky header, type-tinted cells), **JSON** (one bulk codeBg block with line-number gutter). Auto-detected status tags (`tier · pro`, `2FA pending`, `trialing`, …) per document.
- **Document editor** — schema-driven lint that reads `$jsonSchema` validators (required / bsonType / enum / additionalProperties) with a type-heuristic fallback. **Insert & clone** keeps the modal open between inserts. Dynamic UTF-8/LF pills track the actual buffer.
- **Aggregation pipeline builder** — per-stage previews, operator autocomplete (~150 MongoDB operators), drag-and-drop reordering, **per-stage timing & index** via executionStats explain, slow-stage hints with index suggestions, toolbar **Explain** sheet, `allowDiskUse`, result cap, Cmd+Enter to run.
- **Schema analysis** — BSON-accurate type detection, value statistics (min/max/avg, string lengths, distinct counts, top values), mixed-type warnings, full-scan mode, deepest-path indicator, sparse-fields preview, **sample diff** ("+N new since last sample") persisted per `db.collection`.
- **Investigate** — create/drop indexes, aggregated slow queries (mean / p99 / count / last seen), R/W locks column on current ops, **Filter…** (namespace / op-type / min-duration) and **Lower threshold…** popovers, JSON **Export report** via fileExporter, sidebar badge of slow + long-running ops.
- **Metrics** — live server status with 6 KPI sparklines (Ops · Connections · Resident mem · Net I/O · Cache hit · **Replication lag**), Memory chart includes a WT cache line, real **PNG export** via `ImageRenderer` @ 2x.
- **Query Log** — every operation logged with `examined / plan / client / errorMessage`. Custom time-range via `DatePicker`. Advanced search syntax: `op:aggregate OR slow >= 1000ms`, `coll:users`, `plan:IXSCAN`, with substring fallback.
- **Dump & Restore** — wraps `mongodump` / `mongorestore` with all the flags you actually want (`--oplog`, `--excludeIndexes`, `--numParallelCollections`, `--oplogReplay`, `--noIndexRestore`, `--maintainInsertionOrder`, `--noObjcheck`, `--stopOnError`). Restore strategies: **Drop + restore** / **Merge** / **Skip existing**. **Dry run** prints the full command. **Save preset** stores the form per name. Estimated size is real (via `collStats`).
- **Shell** — embedded `mongosh` session with multi-line input (Enter = newline, ⌘↵ = submit), syntax-highlighted output (`ObjectId(…)`, `ISODate(…)`, `$keys`, numbers, strings), blinking caret. Requires `mongosh` installed locally.
- **Sidebar** — count-badges on Query Log / Investigate / Schema rows, **⌘K** focuses the search field.
- **Multi-tab** — up to 8 tabs, each with its own database/collection/filter state.

## Build from source

Requires macOS 14+ and Swift 5.9+.

```bash
git clone https://github.com/<user>/compass-plus.git
cd compass-plus
swift run MongoCompass
```

To build a release `.app` bundle locally:

```bash
bash Scripts/build-app.sh     # produces .dist/MongoCompass.app
bash Scripts/make-dmg.sh      # produces .dist/MongoCompass.dmg
bash Scripts/make-zip.sh      # produces .dist/MongoCompass.zip
```

## Releases

Tagged pushes (`v*`) trigger the release workflow which builds a universal binary (arm64 + x86_64), packages it as a DMG and ZIP, and attaches both to a new GitHub release.

```bash
git tag v0.2.0
git push origin v0.2.0
```
