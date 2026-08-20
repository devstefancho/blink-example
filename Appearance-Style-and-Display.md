# Appearance: Style & Display — Architecture

## Problem

The current Appearance section in Settings has grown into a single monolithic screen covering both visual styling (theme, font, font size, cursor, bold) and display behavior (layout, external display, keycasts). All settings are stored on a single `BLKDefaults` ObjC singleton via NSKeyedArchiver, allowing only one global configuration — no way to have multiple presets or switch styles per session.

## Solution

Split Appearance into two distinct settings sections:

- **Style** — Named presets grouping theme, font, font size, and related visual properties. Multiple styles can exist. Styles can be assigned per session. Shareable with others.
- **Display** — Global terminal display behavior: layout mode, external display/overscan, keycasts, keyboard style. Single instance, not per-session.

Migrate the models to Swift while keeping `BLKDefaults` as a thin bridge so existing ObjC consumers continue working.

---

## Style Model

### TerminalStyle (`Settings/Model/TerminalStyle.swift`)

A named preset referencing existing themes and fonts by name:

```
- id: UUID                          (stable identity, preserved through export/import)
- name: String                      ("Default", "Presentation", "Custom")
- themeName: String                 (reference to BKTheme)
- fontName: String                  (reference to BKFont)
- fontSize: CGFloat
- cursorBlink: Bool
- boldMode: BoldMode                (.auto, .on, .off — three states)
- boldAsBright: Bool
```

Codable, Identifiable, Equatable. `BoldMode` is nested inside `TerminalStyle`.

Default font name comes from `BLINK_APP_FONT` in Info.plist (fallback: "JetBrains Mono"), accessed via `TerminalStyle.defaultFontName`.

### TerminalStyle.Resolved

Nested runtime type produced by `style.resolved()`. Contains actual theme JS content and font CSS content resolved from the name references. If a theme or font is missing, the style is flagged with warnings and falls back to defaults.

### TerminalStyleStore (`Settings/Model/TerminalStyleStore.swift`)

`@objc ObservableObject` managing `[TerminalStyle]` and `selectedStyleID: UUID?`.

**Key design: "Default" is a construct, not stored.** The built-in "Default" style is always computed via `makeBuiltInDefault()` — immutable, can't be deleted/renamed/edited. The store holds only user-created styles. `selectedStyleID = nil` means use built-in Default.

**Creation paths:**
- `createStyle(name:themeName:fontName:...)` — public factory. Store owns UUID generation, name deduplication, persistence. Parameters default to built-in values.
- `addStyle(_:)` — internal, preserves incoming UUID. Used only by the import path where the style already has identity.
- `duplicateStyle(_:)` — creates copy with new UUID.

**Persistence:** Binary plist (`PropertyListEncoder(.binary)`) at `~/.blink/styles`. Not human-editable.

### Session Binding

Sessions can optionally reference a style by ID. If not set, the selected style is used. This enables per-host/per-session styling (e.g., production servers with a red-accented style).

---

## Display Model

Display settings remain on `BLKDefaults` as-is — no migration, no new persistence format. Only the UI splits into its own section. Properties:

```
- layoutMode: BKLayoutMode        (.default, .fill, .cover, .safeFit)
- overscanCompensation             (.scale, .insetBounds, .none, .mirror/stage)
- keycasts: Bool
- keyboardStyle: BKKeyboardStyle  (.dark, .light, .system)
```

---

## Sharing

### .blinkstyle Format (`Settings/Model/TerminalStyleBundle.swift`)

A JSON file that can optionally embed theme/font content for portability:

```json
{
  "style": { "id": "...", "name": "...", "themeName": "...", ... },
  "embeddedThemeName": "Solarized Dark",
  "embeddedThemeContent": "black = '#002b36'; ...",
  "embeddedFontName": "Custom Font",
  "embeddedFontContent": "@font-face { ... }",
  "exportDate": "2026-04-01T...",
  "blinkVersion": "18.5.0"
}
```

- Only custom themes/fonts are embedded (built-in ship with the app, system fonts exist on device).
- On import, UUID is preserved for deduplication — if a style with the same UUID exists, the user is informed.
- Existing theme/font names are detected and skipped with a warning (future UI will ask user on conflicts).

### Sharing Channels

- **Share sheet** — UIActivityViewController with the `.blinkstyle` file. Works with Messages, AirDrop, email, file downloads.
- **URL scheme** — `blink://style/import?url=...` for link-based sharing and QR codes.
- **QR code** — Encodes a URL pointing to a hosted `.blinkstyle` file (content too large for direct QR encoding).
- **Web builder (future)** — A page like `styles.blink.sh` where users build a terminal style visually and export/import via the same `.blinkstyle` infrastructure.

---

## Migration

Uses the existing version-based migration path (`Blink/Migrator/Migrator.swift`):

1. The **"Default"** style is always a computed construct (not stored) using `BLINK_APP_FONT` and BLKDefaults values.
2. If the user had customized theme/font/size on `BLKDefaults`, create a **"Custom"** style from those values and set it as selected.
3. Bridge `BLKDefaults` class methods (`selectedThemeName`, `selectedFontSize`, etc.) to read from `TerminalStyleStore` underneath.

---

## Implementation Plan

### Phase 1 — Swift Models & Persistence ✓
1. `TerminalStyle` struct with nested `BoldMode` and `Resolved` — `Settings/Model/TerminalStyle.swift`
2. `TerminalStyleStore` (ObservableObject) — `Settings/Model/TerminalStyleStore.swift`
3. `TerminalStyleBundle` (.blinkstyle format) — `Settings/Model/TerminalStyleBundle.swift`
4. Bridging header updated — `Blink/Blink-bridge.h`
5. Tests — `BlinkTests/TerminalStyleTests.swift`

### Phase 2 — Migration & Bridge
5. Migration step: BLKDefaults values → "Custom" style if user customized
6. Bridge BLKDefaults class methods to delegate to TerminalStyleStore

### Phase 3 — Display Settings
7. Keep Display on BLKDefaults. Split only the UI layer.

### Phase 4 — SwiftUI Settings UI
8. Style section: list, create/duplicate/delete, edit, live preview
9. Display section: thin SwiftUI wrapper over existing BLKDefaults setters

### Phase 5 — Sharing
10. Register `.blinkstyle` UTI in Info.plist
11. `blink://style/import` URL scheme handler
12. Share sheet export
13. Import flow UI with resource deduplication

---

## Open Questions

- **iCloud sync** — Should `~/.blink/styles` sync across devices? If `~/.blink/` already syncs, it comes for free. Otherwise needs explicit handling.
- **Theme/font conflict policy on import** — Ask user, skip, or auto-rename?
- **Future style properties** — Cursor shape, line spacing, opacity, ligatures — easy to add to the struct later.
