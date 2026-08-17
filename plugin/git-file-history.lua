if vim.g.loaded_git_file_history_nvim == 1 then
  return
end
vim.g.loaded_git_file_history_nvim = 1

local history = require("git_file_history")
history.setup()

vim.api.nvim_create_user_command("GitFileHistory", function()
  history.open()
end, { desc = "Compare current file with its Git history" })

vim.api.nvim_create_user_command("GitFileHistoryOlder", function()
  history.older()
end, { desc = "Show an older revision in the history pane" })

vim.api.nvim_create_user_command("GitFileHistoryNewer", function()
  history.newer()
end, { desc = "Show a newer revision in the history pane" })

vim.api.nvim_create_user_command("GitFileHistorySelect", function()
  history.select()
end, { desc = "Select a revision of the current file" })

vim.api.nvim_create_user_command("GitFileHistoryRefresh", function()
  history.refresh()
end, { desc = "Refresh current file Git history" })

vim.api.nvim_create_user_command("GitFileHistorySwap", function()
  history.swap()
end, { desc = "Swap current and history pane sides" })

vim.api.nvim_create_user_command("GitFileHistoryApplyHunk", function()
  history.apply_hunk()
end, { desc = "Apply the historical diff hunk at the history cursor to the current buffer" })

vim.api.nvim_create_user_command("GitFileHistoryApplyFile", function()
  history.apply_file()
end, { desc = "Restore the selected historical file revision into the current buffer" })

vim.api.nvim_create_user_command("GitFileHistoryActions", function()
  history.focus_actions()
end, { desc = "Focus the middle file-history hunk action column" })

vim.api.nvim_create_user_command("GitFileHistoryUndo", function()
  history.undo()
end, { desc = "Undo the last change in the current file" })

vim.api.nvim_create_user_command("GitFileHistoryClose", function()
  history.close()
end, { desc = "Close the file-history comparison" })

local group = vim.api.nvim_create_augroup("GitFileHistoryNvim", { clear = true })
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(args)
    local winid = tonumber(args.match)
    if winid then
      history._on_win_closed(winid)
    end
  end,
})

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    -- `default = true` means a colorscheme can explicitly own these groups.
    history._define_highlights()
  end,
})
