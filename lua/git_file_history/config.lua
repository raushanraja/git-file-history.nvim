local M = {}

M.defaults = {
  -- "latest" starts at the newest commit that touched the file.
  -- A number starts at that history index (1 = newest).
  start = "latest",

  -- Follow file renames while walking history.
  follow = true,

  -- Show commit metadata in the history window's winbar.
  winbar = true,

  -- Keep the two panes vertically synchronized while diffing.
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
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  return M.options
end

return M
