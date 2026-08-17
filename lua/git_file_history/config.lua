local M = {}

M.defaults = {
  -- "latest" starts at the newest commit that touched the file.
  -- A number starts at that history index (1 = newest).
  start = "latest",

  -- Follow file renames while walking history.
  follow = true,

  -- The live/current file is on the right by default, matching the common
  -- side-by-side diff-editor convention: HISTORY -> CURRENT.
  current_side = "right",

  -- Show commit metadata in the history window's winbar.
  winbar = true,

  -- Keep the two panes vertically synchronized while diffing.
  scrollbind = true,

  -- Keep both files fully expanded. Neovim diff mode normally folds unchanged
  -- regions; the history workbench intentionally does not.
  fold_unchanged = false,

  -- Draw one transfer marker for each diff hunk on the history pane. When the
  -- history pane is on the left it is right-aligned against the divider; after
  -- swapping sides it becomes a sign on the inner edge and points left.
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

    -- Pull the historical hunk under the cursor into CURRENT.
    apply_hunk = "p",

    -- Same action, useful when the cursor is sitting on a visible hunk marker.
    apply_hunk_alt = "<CR>",

    -- Pull the entire historical revision into CURRENT.
    apply_file = "P",

    -- In HISTORY, undo the last change made in CURRENT.
    undo = "u",

    close = "q",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  if M.options.current_side ~= "left" and M.options.current_side ~= "right" then
    error("git-file-history.nvim: current_side must be 'left' or 'right'")
  end

  return M.options
end

return M
