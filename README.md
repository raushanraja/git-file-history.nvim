# git-file-history.nvim

A focused Neovim 0.12+ Git history viewer for the **current file**.

The layout is intentionally simple:

```text
┌──────────────────────────────┬──────────────────────────────┐
│ CURRENT                      │ HISTORY                      │
│                              │                              │
│ Your real current buffer     │ Read-only Git snapshot      │
│ stays the CURRENT pane.      │                              │
│                              │ [g / H  older               │
│ Unsaved edits are included   │ ]g / L  newer               │
│ in the comparison.           │ s       select commit       │
│                              │ r       refresh              │
│                              │ p       apply diff hunk      │
│                              │ P       restore whole file   │
│                              │ x       swap sides           │
│                              │ q       close                │
└──────────────────────────────┴──────────────────────────────┘
```

The current pane is never replaced. By default it starts on the left and history starts on the right. Press `x` (or use `:GitFileHistorySwap`) to exchange their positions; the real current buffer and selected historical revision remain exactly the same. Both panes use Neovim's native diff mode, but diff folding is disabled so the complete current and historical files are always visible.

## Features

- Current working buffer is always the real editable buffer.
- Historical Git snapshot is always read-only.
- Swap current/history between left and right without recreating either pane.
- Move older/newer without opening more windows.
- `git log --follow` traces history across file renames.
- Current unsaved buffer changes are compared too.
- Built-in Neovim diff highlighting with unchanged regions always expanded (no automatic diff folds).
- Apply the historical hunk under the cursor to the live buffer with `p`.
- Visually select a historical range and press `p` to apply only that range.
- Restore the entire selected historical revision into the live buffer with `P`.
- Restores edit the normal current buffer, so ordinary Neovim `u` can undo them.
- Scroll-bound panes.
- Commit hash/date/author/subject in the history winbar.
- `vim.ui.select()` commit picker.
- Read-only scratch buffer for history; your Git tree is never modified.
- No hard-coded colors. Plugin highlights use standard Neovim highlight links and therefore inherit your colorscheme.
- Uses native `vim.system`; no Lua Git dependency.

## Requirements

- Neovim 0.12+
- Git

## Native `vim.pack`

Once the plugin is in a Git repository:

```lua
vim.pack.add({
  "https://github.com/YOURNAME/git-file-history.nvim",
})

require("git_file_history").setup()
```

For a local Git repository:

```lua
vim.pack.add({
  {
    src = "file:///absolute/path/to/git-file-history.nvim",
    name = "git-file-history.nvim",
  },
})
```

## Usage

Open history while your cursor is in a file:

```vim
:GitFileHistory
```

The right pane starts at the newest commit that touched the file.

### History-pane mappings

| Mapping | Action |
|---|---|
| `[g` | Older revision |
| `]g` | Newer revision |
| `H` | Older revision |
| `L` | Newer revision |
| `s` | Select a commit |
| `r` | Refresh history |
| `p` | Apply historical diff hunk under cursor to current buffer |
| Visual `p` | Apply selected historical diff range to current buffer |
| `P` | Restore the complete selected historical revision into current buffer |
| `x` | Swap current/history sides |
| `q` | Close history |

Because the panes are real Neovim diff windows, the standard diff-navigation keys also work:

| Mapping | Action |
|---|---|
| `]c` | Next changed hunk |
| `[c` | Previous changed hunk |

A typical restore loop is therefore `]c` → inspect → `p` → `]c`.

### Commands

```text
:GitFileHistory
:GitFileHistoryOlder
:GitFileHistoryNewer
:GitFileHistorySelect
:GitFileHistoryRefresh
:GitFileHistorySwap
:GitFileHistoryApplyHunk
:GitFileHistoryApplyFile
:GitFileHistoryClose
```


## Restore workflow

The history buffer is a read-only source. Applying history never edits Git and never changes the historical snapshot itself.

```text
CURRENT (live buffer)                 HISTORY (selected commit)
───────────────────────────────       ───────────────────────────────
new implementation                    old implementation
        ▲                                      │
        └──────────── p: current hunk ──────────┘
        └──── Visual p: selected range ─────────┘
        └──────────── P: whole file ────────────┘
```

After an apply, Neovim recomputes the diff immediately and keeps both files fully expanded. The live buffer becomes modified normally; use `u` in the current buffer if you want to undo the restore.

## Configuration

```lua
require("git_file_history").setup({
  start = "latest",
  follow = true,
  winbar = true,
  scrollbind = true,

  mappings = {
    older = "[g",
    newer = "]g",
    older_alt = "H",
    newer_alt = "L",
    select = "s",
    refresh = "r",
    swap = "x",
    apply_hunk = "p",
    apply_file = "P",
    close = "q",
  },
})
```

You can also start on a specific history index:

```lua
require("git_file_history").setup({
  start = 2, -- second-newest revision
})
```

## Colors / QuietDark

The plugin deliberately defines no fixed colors. Its custom groups default-link to standard groups:

```text
GitFileHistoryTitle   -> Title
GitFileHistoryIndex   -> Special
GitFileHistoryHash    -> Identifier
GitFileHistoryMeta    -> Comment
GitFileHistoryAbsent  -> WarningMsg
```

A colorscheme can override those groups directly. Diff contents use Neovim's normal `DiffAdd`, `DiffChange`, `DiffDelete`, `DiffText`, etc., so QuietDark already controls the important comparison colors.

## Notes

The right side represents the selected commit exactly. If the file did not exist at a selected commit (for example a deletion commit), the snapshot is represented as an empty file and the winbar shows `[file absent]`.

Binary files are intentionally rejected.

## Health check

```vim
:checkhealth git_file_history
```
