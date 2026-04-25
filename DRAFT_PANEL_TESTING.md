# Draft Panel — Feel & Workflow Test Plan

Things to put hands on after the persistent draft side panel landed (commit `a96d15b`).
Each section: **what to do** → **what to watch for** → **fix to explore** if it
feels wrong. Group is roughly "you'll notice in 10 seconds" → "you'll notice
the third day."

---

## 1. Title-bar density at panel width

The panel reuses `DraftEditorView`'s full title bar: title field + WIP/Final
segmented picker + "Saved/Unsaved" + Save + Assist menu + Export menu + Delete.
At ideal width 420pt that's a lot of chrome.

- **Try:** open the panel, type a long title, switch status, hit Save, open
  the Assist menu, open Export, hover Delete.
- **Watch for:** controls overflowing, the title field truncating to almost
  nothing, the Assist/Export labels clipping, the picker wrapping.
- **Fix to explore:** in the panel context, collapse Assist/Export/Delete
  into a single "⋯" menu and hide the inline "Saved/Unsaved" text (move to
  a subtle dot next to the title). Keep the full bar on the Drafts tab.

## 2. Panel width vs. left-side cramping

Window minimum is 900pt. Panel takes 360–560 (ideal 420). At 900 with panel
open, the left side gets ~480pt — the Library list (min 320) plus an item
detail can feel claustrophobic.

- **Try:** shrink the window to its minimum with the panel open. Browse a
  long item with code blocks or wide tables.
- **Watch for:** horizontal scroll inside item content, the list collapsing
  the second column, toolbar items wrapping or hiding.
- **Fix to explore:** make the panel resizable (drag handle on the divider —
  switch the `HStack` to `HSplitView`); raise window minWidth to 1100 when
  panel is open; auto-hide panel below a threshold width.

## 3. Resizability

Currently the panel has a fixed range and no drag handle. Some users will
want it wider to compose, some narrower to read.

- **Try:** drag the divider between content and panel.
- **Watch for:** nothing happens — that's the current state.
- **Fix to explore:** `HSplitView` with persisted divider position in
  `AppState` (or `@AppStorage`).

**Status:** Addressed in `f6c1ab4`. Outer container is now `HSplitView`;
panel width persists via `@AppStorage("draftPanelWidth")`. Bounds widened
to 320–800 with main content min 480. Still worth exercising drag at
window-min width and after toggling the panel.

## 4. ⌥⌘D toggle

- **Try:** press ⌥⌘D from each tab. From Drafts tab too.
- **Watch for:** menu item title flips between "Hide/Show Draft Panel";
  shortcut disabled on Drafts tab; collision with any system or
  accessibility shortcut on the user's machine.
- **Fix to explore:** if collision, switch to ⌃⌥⌘D or ⌘\\. Apple's HIG
  reserves ⌘⌥S for "Save As" in some contexts — we're not using that, but
  worth picking a shortcut consistent with future inspector panes.

## 5. Toolbar toggle icon

Two SF Symbols — `sidebar.right` (visible state) and `sidebar.squares.right`
(hidden state). The distinction is subtle.

- **Try:** glance at the toolbar from a normal viewing distance, toggle a
  few times.
- **Watch for:** can't tell at a glance whether the panel is currently
  shown.
- **Fix to explore:** use the same icon both ways and rely on `.help`
  tooltip + the panel's own visibility as the visual cue. Or add a subtle
  "filled" variant when active.

## 6. Default-on at first launch

`isDraftPanelVisible` defaults to `true`. A brand-new user with zero drafts
opens the app and sees the empty-state "No current draft" panel taking
~420pt of their window before they've done anything.

- **Try:** launch with a clean db (`make clean && make backend`) and look
  at the first impression.
- **Watch for:** does the panel feel like noise or like a useful invitation
  to compose?
- **Fix to explore:** default `false`, auto-reveal on first quote-as-draft
  or first manual New Draft. Persist user's preference via `@AppStorage`
  so power users keep it open across launches.

## 7. Sticky-across-launches

Within a session, the panel remembers the selected draft (shared
`DraftsModel` lives on `AppState`). On app restart, `editorState` resets
to `.empty` — even if you were mid-edit on draft X yesterday.

- **Try:** edit a draft in the panel, quit, reopen.
- **Watch for:** panel shows empty state, not your last-touched draft.
- **Fix to explore:** persist `selectedId` in `@AppStorage` and re-select
  on launch after `refreshList` returns. Bonus: persist `isDraftPanelVisible`.

## 8. Quote-as-draft flow

The whole point of the redesign. From a Library item or Note, select text,
right-click → Quote as Draft.

- **Try:** select a paragraph in an item and quote-as-draft. Repeat with
  the panel hidden, with the panel already showing a different draft, and
  while on the Drafts tab.
- **Watch for:**
  - Panel reveals if hidden ✓ expected.
  - New draft replaces the previously-shown draft without warning if
    that draft had unsaved changes — `select` does call `saveNow` first,
    but verify the autosave actually completes before swap.
  - On the Drafts tab the panel stays hidden (correct) and the new draft
    appears in the main editor (correct, but worth eyeballing).
  - Cursor focus: does the new draft's editor receive focus, or does the
    user have to click into it?
- **Fix to explore:** programmatically focus the rich-text editor after
  load. Add a brief "Quoted into draft" toast if focus stays on the source.

## 9. Switching drafts via the header menu

The panel header has a chevron menu listing all drafts sorted by
`updatedAt` desc.

- **Try:** with 2+ drafts, switch between them rapidly. Edit in one,
  switch, switch back.
- **Watch for:** unsaved edits flushed before swap; menu list refreshes
  after a new draft is created elsewhere; visual cue for which draft is
  currently active (today there's none).
- **Fix to explore:** show a checkmark next to the current draft in the
  menu; cap the list to ~10 most recent with a "Show all in Drafts tab" footer.

## 10. Draft-list scale

At 50, 200, 500 drafts, the chevron menu becomes unusable as a switcher.

- **Try:** seed 100+ drafts.
- **Watch for:** menu rendering performance, scroll behavior.
- **Fix to explore:** the cap-and-spillover from §9, or a search field in
  the menu.

**Status:** Addressed in `fd20a32`. Menu caps at 10 most-recent drafts
with a "Show all in Drafts tab…" footer when more exist. Search-in-menu
is still open if 10 turns out to be the wrong cutoff.

## 11. Tab switching with unsaved edits

Autosave debounces at 1.2s. Switch tabs faster than that and the editor
view goes away — but the model lives on `AppState`, so autosave should
still fire from the background `Task`.

- **Try:** type in the panel editor, switch to Drafts tab within <1.2s,
  watch for "Saved" indicator in the full editor.
- **Watch for:** save fires; "isDirty" flips to false; reopening doesn't
  show stale text.
- **Fix to explore:** if autosave gets dropped, force-save in
  `MainView.onChange(of: app.selectedTab)`.

**Status:** Addressed defensively in `6f5f961`. `MainView` now calls
`draftsModel.save()` on tab change when `isDirty`. Belt-and-suspenders
on top of the existing background autosave Task; still worth confirming
the race actually closes under <1.2s switches.

## 12. Two views, one model

Panel and Drafts tab can never be on screen at once (panel is hidden on
Drafts), so there's no concurrent-edit risk. But verify state consistency
across the swap.

- **Try:** edit in panel → switch to Drafts tab → see same draft, same
  cursor / scroll position? Edit further → switch back → same state in
  panel?
- **Watch for:** scroll position resets, selection lost, "Saved" indicator
  out of sync.
- **Fix to explore:** scroll/selection can't easily be preserved across
  view destroy/recreate without lifting more state. Probably acceptable.

## 13. Focus traps

The panel editor is a `NSTextView`-backed `RichTextEditor`. The left side
also has text fields (search, list filters).

- **Try:** click the Library search → start typing → does focus jump to
  the panel? Click an item, hit ⌘F → where does focus go?
- **Watch for:** keystrokes landing in the wrong field.
- **Fix to explore:** make focus changes explicit; first-responder hygiene.

## 14. ⌘S in the panel

`DraftEditorView`'s Save button has `.keyboardShortcut("s", modifiers: .command)`.
With the panel visible, ⌘S triggers save when the panel editor is focused.

- **Try:** edit in the panel, press ⌘S. Edit in a Note (Notes tab) — does
  ⌘S there trigger the panel's save instead of the note's?
- **Watch for:** wrong save fires (drafts when you meant notes), or no
  save fires.
- **Fix to explore:** if there's bleed, scope the shortcut to the focused
  editor only — typically by making the Save button unavailable when the
  editor isn't first responder. Or remove the shortcut from the panel
  copy and rely on autosave + the Drafts tab's ⌘S.

## 15. ⌘N on non-Drafts tabs

`focusedSceneValue(\.newItemAction)` is set inside `DraftsView` (and the
other list views), so on Library tab ⌘N creates a new item, not a new
draft. The panel's "+" button still works.

- **Try:** ⌘N on each tab.
- **Watch for:** users expect ⌘N to make a new draft when the panel is
  open. This is currently *not* what happens.
- **Fix to explore:** add a secondary shortcut like ⇧⌘N for "new draft
  from anywhere" that calls `app.draftsModel.create()` and reveals the
  panel.

## 16. Assist sheet from a narrow panel

The Assist sheet ("Replace selection with…") is rendered as a SwiftUI
sheet, attached to the window — should not be width-bound by the panel.

- **Try:** select text in the panel editor → Assist → Polish.
- **Watch for:** sheet renders centered on window (good), or weirdly
  anchored to the panel column (bad). Suggestion text wraps OK.
- **Fix to explore:** if anchored badly, hoist the sheet to `MainView`.

## 17. Empty state CTA

When there is no selected draft but drafts *exist*, the panel says "No
current draft / Start one to compose…" — no hint that drafts already
exist on the Drafts tab.

- **Try:** create 2 drafts on the Drafts tab, switch to Library, ensure
  none are auto-selected, look at the panel.
- **Watch for:** confusion ("but I just made a draft, why is it empty?").
- **Fix to explore:** if drafts exist, change the empty-state copy to
  "No draft loaded — pick one ↑ or start a new one" with the chevron
  picker pulsing once.

## 18. Delete the loaded draft

Delete from the panel via the title-bar Delete button.

- **Try:** delete the currently-loaded draft.
- **Watch for:** panel returns to empty state; list refreshes; no orphan
  selection.
- **Fix to explore:** auto-load the next-most-recent draft instead of
  going empty, since that matches the "sticky" mental model.

## 19. Visual cohesion

Does the panel feel like part of the window or like a glued-on inspector?

- **Try:** look at it next to native Mac apps with sidebars (Notes, Mail).
- **Watch for:** divider color/weight, header padding, background tint
  matching the rest of the window.
- **Fix to explore:** match background to `Color(NSColor.windowBackgroundColor)`,
  consider `.ultraThinMaterial`, give the divider system styling.

## 20. Accessibility

- **Try:** VoiceOver across the toggle button, panel header, picker, New
  Draft, editor.
- **Watch for:** unlabeled buttons (the icon-only "+" and sidebar toggle
  may read as "button"), picker not announcing its purpose.
- **Fix to explore:** add `.accessibilityLabel` to the icon-only buttons;
  give the chevron menu a meaningful label like "Switch draft."

## 21. Window resize during typing

Drag the window edge while the cursor is in the panel editor.

- **Watch for:** layout jank, text reflow stutter, keystrokes dropped
  during the resize.
- **Fix to explore:** usually a SwiftUI/NSTextView issue; defer expensive
  layout work; lower attributed-string conversion frequency.

---

## Things I'm *not* worried about (but flag here so we can confirm)

- `openDraft(id:)` from Ask citations and Collection links still tab-jumps
  — that's intentional ("open this specific draft" implies focusing it).
- Notes `quoteAs` still tab-jumps — only drafts changed by design.
- Two `DraftsModel` instances: there's only one now (lifted to `AppState`).

## Suggested test order

1. §1, §2, §5, §19 — visual sanity, 5 minutes.
2. §8, §9, §11 — core workflow, 15 minutes. (§11 has a fix landed; verify
   it actually closes the race.)
3. §6, §7, §17 — first-impression and onboarding, fresh DB.
4. §13, §14, §15, §20 — keyboard and a11y nits.
5. §3, §10 — fixes landed; exercise drag/resize and the 10+ drafts
   spillover.
6. Defer §16, §18, §21 unless something breaks during 1–5.
