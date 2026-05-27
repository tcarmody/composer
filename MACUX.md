# Composer — Mac UI / UX / Accessibility Reference

The rules below distill Apple's Human Interface Guidelines (HIG),
the macOS 26 Liquid Glass design system, and the most-cited
community references into the conventions Composer follows.

**Consult this document before adding any new UX surface** (window,
sheet, panel, menu, toolbar, control). It is faster than re-deriving
the rules from Apple docs each time, and it encodes decisions
already made for this codebase.

External sources, in authority order:

1. [Apple HIG (root)](https://developer.apple.com/design/human-interface-guidelines/) and component pages (`toolbars`, `sidebars`, `menus-and-actions`, `windows`, `settings`, `foundations/accessibility`).
2. [Build an AppKit app with the new design — WWDC25 #310](https://developer.apple.com/videos/play/wwdc2025/310/) and [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).
3. [Macintosh Checklist (Mario Guzman)](https://marioaguzman.github.io/design/macintoshchecklist/) — concrete numerics.
4. [macOS Settings Window Guidelines (usagimaru)](https://zenn.dev/usagimaru/articles/b2a328775124ef?locale=en) — preferences-pane specifics.

The HIG pages are JS-rendered and don't reverse-proxy cleanly to
agent tooling; open them in a browser when in doubt.

Composer is **Mac-first** (see [project_platform_direction.md](../../.claude/projects/-Users-tim-Workspace-composer/memory/project_platform_direction.md)) — the SwiftUI app at [app/Composer/](app/Composer/) is the leading surface, and the React web app at [web/](web/) follows it. This document governs the Mac app.

The deployment target is **macOS 14.0** ([project.yml](app/Composer/project.yml)), not 26 — guard newer SwiftUI APIs with `@available(macOS 15, *)` / `@available(macOS 26, *)` and provide graceful fallbacks. Liquid Glass treatments only kick in on macOS 26; the app must still look right on macOS 14–25.

---

## Core postures

These are non-negotiable for a Mac app — every new surface should
inherit them by default:

- **Menu bar is primary.** Every action a user might reach for
  must be in the menu bar, even when it's also on a toolbar,
  context menu, or keyboard shortcut. Users who can't find a
  feature look in the menu bar before anywhere else. Composer's
  `AppCommands` already wires the five top-level tab switches
  (⌘1–⌘5); new modes need the same treatment.
- **Settings is modeless.** No Save / Cancel / Apply buttons.
  Changes commit immediately via `@AppStorage` / bindings. ⌘,
  opens it; Esc or ⌘W closes it. The LLM key fields are an
  intentional exception — the user types into a draft buffer,
  then presses Save — because the value should not be pushed to
  the backend on every keystroke.
- **Single-instance primary window.** Composer is a workbench, not
  a document app: one `WindowGroup` containing `MainView`, mode
  selected via `app.selectedTab`. Don't introduce
  `WindowGroup(for: URL.self)` for items, notes, or drafts unless
  the user explicitly asks for tear-off windows.
- **Toolbars carry primary actions**, in the titlebar, as real
  `.toolbar { … }` content — not as in-content `HStack`s of
  buttons. On macOS 26 the toolbar is the Liquid Glass plane.
- **Sidebars carry navigation**, not filters or transient state.
  Filters belong in a toolbar picker or `.searchable` scope.
- **Drag-drop is a first-class input** alongside menu / picker
  flows — especially for promoting items into collections,
  drafts, and the side panel. The drop target should give clear
  visual feedback while hovered.
- **System colors only** (`.controlAccentColor`, `.labelColor`,
  `.windowBackgroundColor`, etc.). Hand-picked hex values defeat
  Dark Mode, Increase Contrast, and accent-color personalization.
  The named theme palettes (Manuscript / Noir / Ember / Forest /
  Ocean / Midnight) in [Appearance.swift](app/Composer/Composer/Models/Appearance.swift)
  are the exception — they explicitly opt out of system
  appearance — but the default `Auto` theme stays on system
  colors and must keep doing so.

## Menus

- **Required structure:** App, File, Edit, View, Window, Help.
  App-specific menus go between Edit and View (e.g. Format,
  Insert) or between View and Window (e.g. Document, Tools).
  Composer is not document-based, so the File menu carries
  `New` (the focus-aware `newItemAction` — creates a note,
  draft, or collection depending on the active surface) rather
  than Open/Save.
- **Ellipsis (`…`)** on any item that opens further UI: dialogs,
  sheets, secondary windows, file pickers. No ellipsis on items
  that perform their action immediately.
- **Title case** for menu titles and items. Never ALL CAPS except
  for acronyms.
- **Standard shortcuts** for standard actions: ⌘N New, ⌘W Close,
  ⌘P Print, ⌘F Find, ⌘G Find Next, ⌘Z / ⇧⌘Z Undo / Redo, ⌘Q Quit,
  ⌘, Settings, ⌘? Help. Composer-specific: ⌘1–⌘5 switch the five
  top-level modes; ⌥⌘D toggles the draft side panel; ⌘R refreshes
  the focused list.
- **Avoid system-reserved chords**: `⌃⌘[`, `⌃⌘]`, and similar are
  silently dropped by SwiftUI's `CommandMenu`. Default to
  `⌥⌘<arrow>` or `⇧⌘<letter>` when standard shortcuts don't
  apply.
- **`@CommandsBuilder` has a 10-element cap** per group. Wrap
  longer groups in sub-Views — items past the 10th are silently
  dropped.
- **Disabled items**: gray them out rather than hiding. Hiding
  makes users think the feature was removed. The current
  `newItemAction` / `refreshAction` / draft-panel toggle already
  use `.disabled(…)` correctly when the focused surface has no
  action to offer.
- **Contextual menus** should mirror the items that would
  otherwise be in the menu bar's most-relevant menu, not invent
  new actions. The right-click menu on library list rows
  ([commit 4441be8](app/Composer/Composer/Views/Library/ItemListView.swift))
  is the canonical example.

## Toolbars

- Use `.toolbar { ToolbarItem(placement: …) { … } }` —
  always a real toolbar, never an in-content `HStack`. `MainView`
  hosts a single top-level toolbar with the tab picker and
  primary-action items; per-mode toolbars layer additional items
  via `.toolbar` on the inner view.
- **Placement determines label visibility** — and that's
  intentional, not a bug to work around:
  - `.primaryAction` / `.automatic` (trailing-edge actions like
    Save, Share, Export, "Show Draft Panel") — render icon + label
    by default. Use `Label(_:systemImage:)` and let SwiftUI do
    both. This is what HIG means by "icon + label is the macOS
    default."
  - `.navigation` (leading-edge view toggles like sidebar /
    inspector / pane visibility) — render icon-only by default.
    This is the macOS convention; Mail, Notes, Pages, Xcode,
    and Finder all do it. Don't move pane toggles to
    `.primaryAction` to "fix" the icon-only rendering — the
    icons there are conventional and tooltips + accessibility
    labels carry the meaning.
  - `.principal` is reserved for the tab picker in
    `MainView` — it centers, which is what we want for the
    mode segmented control. Don't co-opt it for other content.
- **Icons** must come from SF Symbols. The `NavTab.systemImage`
  values (`tray.full`, `rectangle.stack`, `note.text`, `doc.text`,
  `sparkle.magnifyingglass`) are the canonical per-mode symbols
  — reuse them anywhere a mode is referenced.
- **Order:** primary actions on the leading edge, search and
  utility on the trailing edge, separators between logical groups.
- **`.help()` tooltip** on every toolbar item — covers users who
  hide labels, and provides VoiceOver text. The draft-panel
  toggle in `MainView` already does this; new items must too.
- **No more than ~5–7 default items** before requiring Customize
  Toolbar. Beyond that, the user can't scan the row.
- **Symbols** must come from SF Symbols, sized via `.imageScale`
  not hard-coded fonts, so they scale with the user's control-size
  preference.

## Sidebars

- Use `NavigationSplitView { sidebar } detail: { … }` for an
  editor-style surface with a tree, or an `HSplitView` with a
  list-style pane for browse surfaces. Composer's top-level shell
  is `HSplitView` (mode area + draft side panel) and each mode
  may compose its own split internally — `LibraryView` and
  `NotesView` use a list/detail split.
- **Width:** min 220pt, ideal 260–280pt, max 320–360pt for
  navigation sidebars. The Macintosh Checklist suggests min
  225–275, max 350–400 — stay in that range. The draft side
  panel uses min 320 / max 800 because it carries an editor,
  not navigation.
- **Collapsible** via a toolbar `Toggle` or the default
  ⌃⌘S sidebar chord. Persist the state via `@AppStorage` or
  `UserDefaults`-backed publisher — `isDraftPanelVisible` in
  `AppState` is the existing pattern, and its width is persisted
  via `@AppStorage("draftPanelWidth")`.
- **Source-list style** (`.listStyle(.sidebar)`) for hierarchical
  navigation; **inset grouped** for flat-list inspectors.
- **Counts as trailing badges**, never as parenthetical text in
  the row label.
- **Sections** use disclosure groups with persisted expand state
  — read once at view init, write via explicit `.onChange`. Avoid
  letting `@AppStorage` participate in a `List(selection:)`
  render loop; it causes selection thrash on macOS 14.

## Windows

- **Title** identifies the surface or document. **Subtitle** (via
  `.navigationSubtitle`) carries transient status (Saving…,
  Unsaved Changes, Save failed: …) — never the title repeated.
  The stale-backend banner in `MainView` is the correct pattern
  for non-transient warnings: an in-app bar, not the subtitle.
- **Minimum size:** ~480×320pt for utility windows, 620×380pt for
  browse surfaces, 900×600pt for the main window. Composer's
  `WindowGroup` sets `minWidth: 900, minHeight: 600` — match
  that floor when adding any new top-level window.
- **Document-edited dot** in the red close button via
  `window.isDocumentEdited = isDirty`. Composer isn't document-
  based, but draft and note editors should still set this for
  the main window when their respective surface has unsaved
  changes — close-with-unsaved should trigger a standard Save /
  Discard Changes / Cancel alert.
- **State restoration** for window position and size is automatic
  from `WindowGroup`; use explicit `@SceneStorage` for per-window
  panel-visibility flags. Cross-window app preferences (theme,
  list density, typeface) belong on `AppState`, backed by
  `UserDefaults`.
- **Full-screen** is supported by default for content windows.
  The draft side panel, if ever broken out, shouldn't follow into
  full-screen.

## Settings

- `Settings { … }` scene, accessible via ⌘,. `SettingsView`
  currently uses a single `Form` with sections — fine for the
  current size, but **once the form has more than ~5 sections it
  should split into a `TabView`** with `.tabItem { Label("Tab",
  systemImage: "…") }` per pane. (Backend + Auth, API Keys,
  Appearance, Editor, Index is already the natural seam.)
- **Both icon AND label** per tab when you do split — required
  for VoiceOver and for the truncation behavior when the window
  narrows.
- **Conventional tab order:** general behavior first, advanced
  / AI last. Restore the last-viewed tab on reopen via
  `@AppStorage`.
- **Centered Form layout** (`.formStyle(.grouped)` — already in
  use) with `Section("…")` headings, right-aligned label column,
  controls on the trailing side. Descriptions go below in a
  `.caption` / `.secondary` foreground (the existing pattern).
- **Fixed width** (~520–540pt). Composer uses `width: 520,
  height: 640`. Height can vary by pane but shouldn't change
  wildly between tabs in the same window — flicker on tab
  switch is jarring.
- **No Save / Cancel / Apply buttons** for plain bindings. The
  API-key and LLM-key fields legitimately have Save because a
  draft buffer is held client-side until submission — every
  other control commits immediately.
- **Keep parity across panes.** A pane that's an order of
  magnitude longer than its siblings should probably split into
  two panes.

## Sheets, panels, alerts

- **Sheets** for window-modal flows that complete a single task:
  metadata editor, bulk-edit, snapshot restore, item promotion
  confirmation. Sheets must have a clear primary action button
  and a Cancel button; Esc cancels.
- **Alerts** (`.alert(…)`) for confirmations and error reporting.
  Destructive actions get the `role: .destructive` button modifier
  for the red text + right-side placement.
- **Confirmation dialogs** (`.confirmationDialog`) for
  multi-choice destructive decisions (Archive / Delete / Cancel).
- **Free-floating panels** (`Window` scene with `.windowStyle`
  configured) for accessory tools that should stay visible across
  app switches — rare in Composer; default to sheets or the
  in-window draft side panel.
- **Progress sheets** show determinate progress when total is
  known; cancellable when the work can be interrupted; surface
  per-item failure lists rather than a generic "some items
  failed." The reindex progress in `SettingsView` is the existing
  pattern — inline, with idle / running / done / error states.

## Search

- **`.searchable(text: $query)`** is the right answer for any
  filter-this-collection interaction in the Library, Collections,
  Notes, and Drafts lists. Lands in the titlebar on macOS 26,
  gets glass treatment, native clear button, ⌘F binding.
- **Avoid custom search capsules.** They look native at first but
  miss the system styling that ships with `.searchable` on macOS
  26 — and they don't participate in keyboard navigation
  out of the box.
- **Scope chips** (`.searchScopes`) for multi-corpus filters
  (e.g. All / Selected Collection / Active Draft).
- **Ask is not search.** The Ask surface is a chat with
  retrieval; its input is a chat composer, not `.searchable`.
  Don't conflate the two.

## Liquid Glass and macOS 26

The new design language landed in macOS 26 Tahoe. Composer ships
to macOS 14+, so adoption must be **opt-in via `@available`** —
the app must still look right on macOS 14 through 25. When
running on macOS 26, several things have to **not** be in the way:

- **Don't paint opaque backgrounds** on the window's root view.
  `Color(nsColor: .windowBackgroundColor)` over the full body
  blocks the floating-glass treatment macOS 26 applies to
  toolbars and sidebars. Let the system render the chrome over
  the content.
- **Don't insert manual `Divider()`s under the toolbar.** macOS 26
  uses the **scroll edge effect** — a fade or hard backing that
  appears automatically as content scrolls under the floating
  toolbar. A manual divider competes with this. On macOS 14–25
  the divider may still be desired; guard with `@available`.
- **Extend content edge-to-edge.** Toolbar and sidebar sample
  through; padding the content away from the window edges
  defeats the effect.
- **Remove legacy `NSVisualEffectView`** from sidebars when you
  encounter them. They block glass.
- **Glass goes only on the navigation layer** (toolbar, sidebar,
  floating controls) — never on content (lists, tables,
  scrollable areas). Avoid stacking glass over glass.
- **Tinting:** use accent only for primary actions. Secondary
  / tertiary controls stay un-tinted. Destructive uses the system
  red role, not a hand-picked color. Named theme palettes
  (Manuscript et al.) remix the accent — they shouldn't replace
  the system red for destructive actions.

## Accessibility

This is an area where Composer has ground to cover — most
icon-only buttons in `MainView` and the per-mode toolbars carry
`.help(…)` but not `.accessibilityLabel(…)`.

- **VoiceOver labels** on every icon-only control. The convention
  is: `.accessibilityLabel("…")` mirrors the `.help("…")` copy.
  `.help` is for sighted-user tooltips; `accessibilityLabel` is
  for VoiceOver. Both are needed.
- **`.accessibilityHint("…")`** for non-obvious actions ("Opens
  the metadata editor for the selected item").
- **Composite rows** use `accessibilityElement(children: .combine)`
  so VoiceOver reads the row as one element rather than walking
  every label, image, and badge separately. Item rows in the
  Library list and chat citations in Ask are the main offenders.
- **Keyboard focus** reaches every interactive surface. Add
  `.focusable()` on custom hit areas (drop zones, custom
  pickers). Tab key should walk the whole UI; focus ring uses
  the system color, never custom.
- **Color contrast:** rely on system colors. They satisfy WCAG
  AA against the matching background by design. The
  Manuscript/Noir/Ember/Forest/Ocean/Midnight palettes in
  `Appearance.swift` are hand-picked — they need explicit
  contrast checks against their `text` / `secondary` values for
  WCAG AA, and ideally Increase Contrast variants.
- **Don't rely on color alone** to convey state. The health
  badge pairs the green/orange/red dot with text — keep that
  pattern. New status indicators (sync, indexing) need text or
  a distinct symbol alongside the color.
- **Reduce Motion** is respected automatically by SwiftUI
  transitions; custom `withAnimation` blocks should check
  `@Environment(\.accessibilityReduceMotion)` for any non-
  decorative motion.
- **Reduce Transparency** falls out of Liquid Glass automatically
  on macOS 26 — glass becomes frostier, no extra code.
- **Increase Contrast** likewise on system colors — they switch
  to high-contrast variants. Hand-picked palettes (Composer's
  themes) need explicit dark / light variants and, ideally,
  contrast-mode variants too.
- **Dynamic Type:** use `Font.system(.body)` / `.title`, never
  hard-coded point sizes. Caption-sized helper text in
  `SettingsView` is the correct pattern; replicate it elsewhere.

## Anti-patterns

- Hamburger menu. The menu bar exists for this.
- iOS-style tab bars (`TabView` rendered as bottom tabs). Composer's
  five-mode picker is a `.principal` toolbar `Picker` with
  `.pickerStyle(.segmented)` — keep it there.
- Buttons styled to look like links.
- Modal-blocking on routine state changes — settings, sort order,
  filter changes should never gate the UI.
- Hidden disabled controls. Show them disabled instead.
- Hand-rolled "preferences sheets" that aren't the `Settings`
  scene. ⌘, must open Apple's standard window.
- Per-app accent overrides that ignore the user's System
  Settings accent. Theme palettes are fine as long as they remix
  the accent rather than replacing it.
- Newer SwiftUI APIs without `@available` guards. Composer must
  build and run on macOS 14; an unguarded macOS 15+ modifier
  will refuse to compile against the deployment target.

## Pre-flight checklist for new UX

Before merging a new window, sheet, panel, toolbar, or menu:

1. **Menu bar:** is there an item to reach this action from the
   menu bar? If no, add one to `AppCommands` or a focus-aware
   command published from the active surface.
2. **Keyboard shortcut:** is the action one users will repeat? If
   yes, give it a shortcut — but only from the standard set or
   `⌥⌘<key>` / `⇧⌘<letter>` range. ⌘1–⌘5 are reserved for the
   five top-level modes.
3. **VoiceOver:** every icon-only button has
   `.accessibilityLabel`. Every composite row uses
   `accessibilityElement(children: .combine)`.
4. **Tab key:** focusable hits reach the surface; Tab walks
   through them in reading order.
5. **Tooltips:** `.help("…")` on toolbar items, icon buttons, and
   non-obvious controls. Same copy as the VoiceOver label.
6. **System colors:** no hard-coded hex. Named theme palette
   accessors in `Appearance.swift` are the exception.
7. **Liquid Glass:** no opaque background paints over the window
   root; no manual dividers under the toolbar. Guard macOS 26
   styling with `@available` so macOS 14–25 still renders.
8. **Ellipsis discipline:** every action that opens further UI
   ends in `…`; immediate-effect actions don't.
9. **Standard shortcuts:** ⌘, opens Settings, ⌘F opens search,
   ⌘W closes the window, Esc cancels modal flows.
10. **Build target:** SwiftUI APIs used are macOS 14+, or are
    `@available`-guarded with a sensible fallback. The deployment
    target is set in [app/Composer/project.yml](app/Composer/project.yml).

When in doubt: open the same surface in Mail, Notes, or Pages
and copy what Apple did. Those three are the most-current
reference implementations of the HIG.
