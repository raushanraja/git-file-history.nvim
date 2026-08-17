local config = require("git_file_history.config")
local session = require("git_file_history.session")
local ui = require("git_file_history.ui")

local M = {}

function M.setup(opts)
  config.setup(opts)
  ui.define_highlights()
end

function M.open() session.open() end
function M.close() session.close() end
function M.older() session.older() end
function M.newer() session.newer() end
function M.select() session.select() end
function M.refresh() session.refresh() end
function M.swap() session.swap() end
function M.apply_hunk() session.apply_hunk() end
function M.apply_selection() session.apply_selection() end
function M.apply_file() session.apply_file() end
function M.apply_action() session.apply_action() end
function M.next_action() session.next_action() end
function M.prev_action() session.prev_action() end
function M.focus_actions() session.focus_actions() end
function M.focus_left() session.focus_left() end
function M.focus_right() session.focus_right() end
function M.undo() session.undo() end

function M._on_win_closed(winid)
  session.on_win_closed(winid)
end

function M._define_highlights()
  ui.define_highlights()
end

-- Used by the clickable HISTORY winbar close control. Neovim's statusline /
-- winbar click interface resolves v:lua functions through the global table.
_G.GitFileHistoryCloseClick = function()
  require("git_file_history").close()
end

return M
