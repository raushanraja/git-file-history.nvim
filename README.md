# git-file-history.nvim

A focused Neovim 0.12+ file-history workbench: browse an older Git revision beside the **real current buffer**, then pull individual historical hunks back into the file you are editing.

By default it deliberately follows the familiar diff-editor direction:

```text
HISTORY (read-only)                         CURRENT (live/editable)
┌──────────────────────────────────────┬──────────────────────────────────────┐
│ old revision                         │ your real current buffer             │
│                                      │                                      │
│ changed historical block         →   │ changed current block                │
│                                      │                                      │
│ another historical hunk          →   │ another current hunk                 │
│                                      │                                      │
│ [g/H older      ]g/L newer            │ unsaved edits stay here              │
│ p/<CR> pull hunk                      │ u undoes a pulled change              │
│ P whole file     x swap               │                                      │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

The files stay **fully expanded**. Neovim's native diff highlighting/filler rows are used, but its normal automatic folding of unchanged regions is disabled.

## Features

- **CURRENT is on the right by default.**
- CURRENT is always your actual editable Neovim buffer, including unsaved changes.
- HISTORY is a read-only Git snapshot of the same file.
- Visible `→` transfer markers identify diff hunks when HISTORY is on the left.
- `p` or `<CR>` on a historical hunk pulls only that hunk into CURRENT.
- Visual-select historical lines + `p` pulls only that selected diff range.
- `P` restores the entire selected historical revision into CURRENT.
- Normal `u` in CURRENT undoes a pulled/restored change.
- `[g` / `]g` (or `H` / `L`) move only HISTORY backward/forward through file history.
- `x` swaps HISTORY/CURRENT while preserving both buffers and the selected revision.
- After swapping, the transfer direction automatically becomes `←` toward CURRENT.
- `git log --follow` traces history across renames.
- Full-file side-by-side diff: unchanged regions are never automatically folded.
- Hunk markers recompute when CURRENT changes while the workbench is open.
- Native Neovim `DiffAdd`, `DiffChange`, `DiffDelete`, `DiffText`, etc.
- No hard-coded colors; custom plugin highlights link to standard highlight groups.
- Native `vim.system`; no Git Lua dependency.

## Requirements

- Neovim 0.12+
- Git

## Install with native `vim.pack`

```lua
vim.pack.add({
  "https://github.com/raushanraja/git-file-history.nvim",
})

require("git_file_history").setup()
```

Then:

```vim
:GitFileHistory
```

## Default workflow

HISTORY gets focus when the workbench opens, while CURRENT stays on the right.

| Mapping | Action |
|---|---|
| `[g` | Older file revision |
| `]g` | Newer file revision |
| `H` | Older file revision |
| `L` | Newer file revision |
| `s` | Pick any revision |
| `r` | Refresh history |
| `<Tab>` | Next changed hunk |
| `<S-Tab>` | Previous changed hunk |
| `]c` | Next changed hunk (native diff key) |
| `[c` | Previous changed hunk (native diff key) |
| `p` | Pull the historical hunk under the cursor into CURRENT |
| `<CR>` | Same as `p` |
| Visual `p` | Pull only the selected historical diff range |
| `P` | Restore the complete historical revision into CURRENT |
| `x` | Swap HISTORY/CURRENT sides |
| `u` | Undo last change made in CURRENT |
| `e` | Focus CURRENT for manual editing |
| `q` | Close the workbench |

A typical selective-restore loop is:

```text
Tab  → inspect hunk → p → Tab → inspect hunk → p
```

The visible arrow is intentionally a **hunk action marker**: position the cursor on that changed block and press `p` or `<CR>` to pull only that historical change into the live file.

## Commands

```text
:GitFileHistory
:GitFileHistoryOlder
:GitFileHistoryNewer
:GitFileHistorySelect
:GitFileHistoryRefresh
:GitFileHistorySwap
:GitFileHistoryApplyHunk
:GitFileHistoryApplyFile
:GitFileHistoryEdit
:GitFileHistoryUndo
:GitFileHistoryClose
```

## Configuration

```lua
require("git_file_history").setup({
  start = "latest",
  follow = true,

  -- "right" is the default: HISTORY -> CURRENT.
  current_side = "right",

  winbar = true,
  scrollbind = true,
  fold_unchanged = false,

  hunk_actions = true,
  hunk_indicators = {
    right = "→",
    left = "←",
  },

  mappings = {
    older = "[g",
    newer = "]g",
    older_alt = "H",
    newer_alt = "L",
    select = "s",
    refresh = "r",
    swap = "x",
    next_hunk = "<Tab>",
    prev_hunk = "<S-Tab>",
    apply_hunk = "p",
    apply_hunk_alt = "<CR>",
    apply_file = "P",
    undo = "u",
    focus_current = "e",
    close = "q",
  },
})
```

If you prefer CURRENT on the left:

```lua
require("git_file_history").setup({
  current_side = "left",
})
```

You can still press `x` at any time to swap temporarily.

## How hunk transfer works

The plugin does not copy arbitrary line numbers between files. It keeps both panes in native Neovim diff mode and performs a semantic:

```text
HISTORY hunk  ────────→  CURRENT
```

using `:diffput` / `:diffget` against the actual CURRENT buffer. This means insertions, deletions, and replacements are handled as diff changes rather than naive text copies.

The current buffer becomes normally modified after a transfer, so saving and undoing work exactly as they do during ordinary editing.

## Colors / QuietDark

There are no fixed RGB values in the plugin. Custom groups default-link to normal Neovim semantics:

```text
GitFileHistoryTitle   -> Title
GitFileHistoryIndex   -> Special
GitFileHistoryHash    -> Identifier
GitFileHistoryMeta    -> Comment
GitFileHistoryAbsent  -> WarningMsg
GitFileHistoryAction  -> DiffText
```

The actual comparison continues to use `DiffAdd`, `DiffChange`, `DiffDelete`, `DiffText`, and related groups, so QuietDark automatically owns the visual appearance.

## Rename history

The history query uses `git log --follow --name-only`. When a file was renamed, HISTORY switches to the pathname that existed at the selected commit instead of stopping at the rename.

## Health check

```vim
:checkhealth git_file_history
```
