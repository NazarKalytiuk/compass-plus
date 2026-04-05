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

- **Explorer** — browse databases and collections, CRUD on documents, saved queries, pagination.
- **Aggregation pipeline builder** — per-stage previews, operator autocomplete, ~150 MongoDB operators in the completion catalog, `allowDiskUse`, result cap, duplicate/reorder/collapse stages, Cmd+Enter to run.
- **Schema analysis** — BSON-accurate type detection, value statistics (min/max/avg, string lengths, distinct counts, top values), mixed-type warnings, full-scan mode.
- **Investigate** — create/drop indexes, view slow queries, explain plans, profiling level control.
- **Metrics** — live server status, memory/connections/network, current operations.
- **Dump & Restore** — wraps `mongodump`/`mongorestore` when installed.
- **Shell** — embedded `mongosh` session (requires `mongosh` installed locally).
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
