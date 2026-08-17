local config = require("git_file_history.config")
local session = require("git_file_history.session")
local ui = require("git_file_history.ui")

local M = {}

function M.setup(opts)
  config.setup(opts)
  ui.define_highlights()
end

function M.open()
  session.open()
end

function M.close()
  session.close()
end

function M.older()
  session.older()
end

function M.newer()
  session.newer()
end

function M.select()
  session.select()
end

function M.refresh()
  session.refresh()
end

function M.swap()
  session.swap()
end

function M._on_win_closed(winid)
  session.on_win_closed(winid)
end

function M._define_highlights()
  ui.define_highlights()
end

return M
