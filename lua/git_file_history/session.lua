local config = require("git_file_history.config")
local git = require("git_file_history.git")
local ui = require("git_file_history.ui")

local M = {}
local sessions = {}

local SAVED_WINDOW_OPTIONS = {
  "diff",
  "scrollbind",
  "cursorbind",
  "wrap",
  "foldmethod",
  "foldcolumn",
  "foldenable",
  "foldlevel",
}

local function tabkey(tab)
  return tostring(tab)
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "git-file-history.nvim" })
end

local function current_session()
  local tab = vim.api.nvim_get_current_tabpage()
  return sessions[tabkey(tab)], tab
end

local function save_window_options(win)
  local saved = {}
  for _, name in ipairs(SAVED_WINDOW_OPTIONS) do
    saved[name] = vim.wo[win][name]
  end
  return saved
end

local function restore_window_options(win, saved)
  if not saved or not vim.api.nvim_win_is_valid(win) then
    return
  end

  for name, value in pairs(saved) do
    pcall(function()
      vim.wo[win][name] = value
    end)
  end
end

local function set_diff(win)
  vim.api.nvim_win_call(win, function()
    vim.cmd("diffthis")
    -- Diff mode normally folds unchanged regions. This plugin is a full-file
    -- history workbench, so both panes stay expanded at all times.
    vim.wo.foldenable = false
  end)
end

local function keep_expanded(session)
  for _, win in ipairs({ session.left_win, session.right_win }) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].foldenable = false
    end
  end
end

local function update_diff(session)
  if not vim.api.nvim_win_is_valid(session.left_win) then
    return
  end

  vim.api.nvim_win_call(session.left_win, function()
    vim.cmd("silent! diffupdate")
  end)

  keep_expanded(session)
end

local function install_buffer_mappings(buf)
  local maps = config.options.mappings
  local map_opts = { buffer = buf, silent = true, nowait = true }

  local function map(lhs, rhs, desc)
    if lhs and lhs ~= "" then
      vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", map_opts, { desc = desc }))
    end
  end

  map(maps.older, function()
    require("git_file_history").older()
  end, "Older file revision")

  map(maps.newer, function()
    require("git_file_history").newer()
  end, "Newer file revision")

  map(maps.older_alt, function()
    require("git_file_history").older()
  end, "Older file revision")

  map(maps.newer_alt, function()
    require("git_file_history").newer()
  end, "Newer file revision")

  map(maps.select, function()
    require("git_file_history").select()
  end, "Select file revision")

  map(maps.refresh, function()
    require("git_file_history").refresh()
  end, "Refresh file history")

  map(maps.swap, function()
    require("git_file_history").swap()
  end, "Swap current/history sides")

  map(maps.apply_hunk, function()
    require("git_file_history").apply_hunk()
  end, "Apply historical diff hunk to current file")

  map(maps.apply_file, function()
    require("git_file_history").apply_file()
  end, "Restore entire historical revision into current file")

  if maps.apply_hunk and maps.apply_hunk ~= "" then
    vim.keymap.set("x", maps.apply_hunk, function()
      require("git_file_history").apply_selection()
    end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Apply selected historical diff range to current file",
    })
  end

  map(maps.close, function()
    require("git_file_history").close()
  end, "Close file history")
end

local function load_index(session, index)
  if index < 1 or index > #session.entries then
    return false
  end

  local entry = session.entries[index]
  local content, absent, err = git.show(session.root, entry)
  if content == nil then
    notify(err or "Could not read historical file", vim.log.levels.ERROR)
    return false
  end

  if not vim.api.nvim_buf_is_valid(session.history_buf) then
    return false
  end

  ui.set_content(session.history_buf, content, absent)
  session.index = index
  session.absent = absent

  vim.b[session.history_buf].git_file_history_hash = entry.hash
  vim.b[session.history_buf].git_file_history_path = entry.path
  vim.b[session.history_buf].git_file_history_index = index

  if config.options.winbar and vim.api.nvim_win_is_valid(session.right_win) then
    ui.set_winbar(session.right_win, entry, index, #session.entries, absent)
  end

  update_diff(session)

  if vim.api.nvim_win_is_valid(session.right_win) then
    local left_cursor = { 1, 0 }
    if vim.api.nvim_win_is_valid(session.left_win) then
      left_cursor = vim.api.nvim_win_get_cursor(session.left_win)
    end

    local line_count = math.max(vim.api.nvim_buf_line_count(session.history_buf), 1)
    left_cursor[1] = math.min(left_cursor[1], line_count)
    pcall(vim.api.nvim_win_set_cursor, session.right_win, left_cursor)
  end

  return true
end

function M.open()
  local existing = current_session()
  if existing then
    if vim.api.nvim_win_is_valid(existing.right_win) then
      vim.api.nvim_set_current_win(existing.right_win)
      return
    end
    M.close()
  end

  local left_win = vim.api.nvim_get_current_win()
  local left_buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(left_buf)

  if path == "" then
    notify("Current buffer has no file path", vim.log.levels.ERROR)
    return
  end

  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))

  local root, root_err = git.root_for(path)
  if not root then
    notify(root_err ~= "" and root_err or "File is not inside a Git repository", vim.log.levels.ERROR)
    return
  end

  local relpath = git.relative_path(root, path)
  local entries, history_err = git.history(root, relpath, config.options.follow)

  if not entries then
    notify(history_err or "Could not read Git history", vim.log.levels.ERROR)
    return
  end

  if #entries == 0 then
    notify("No Git history found for " .. relpath, vim.log.levels.WARN)
    return
  end

  local history_buf = ui.history_buffer(left_buf, relpath)
  local right_win = ui.open_right(history_buf)
  ui.apply_history_window_options(right_win)
  install_buffer_mappings(history_buf)

  local tab = vim.api.nvim_get_current_tabpage()
  local session = {
    tab = tab,
    left_win = left_win,
    left_buf = left_buf,
    right_win = right_win,
    history_buf = history_buf,
    root = root,
    relpath = relpath,
    entries = entries,
    index = 1,
    left_options = save_window_options(left_win),
    swapped = false,
    closing = false,
  }

  sessions[tabkey(tab)] = session

  set_diff(left_win)
  set_diff(right_win)

  if config.options.scrollbind then
    vim.wo[left_win].scrollbind = true
    vim.wo[right_win].scrollbind = true
  end

  local start = config.options.start
  local start_index = type(start) == "number" and start or 1
  start_index = math.max(1, math.min(start_index, #entries))
  load_index(session, start_index)

  vim.api.nvim_set_current_win(right_win)
end

function M.close(tab, from_autocmd)
  local session

  if tab then
    session = sessions[tabkey(tab)]
  else
    session, tab = current_session()
  end

  if not session or session.closing then
    return
  end

  session.closing = true
  sessions[tabkey(session.tab)] = nil

  restore_window_options(session.left_win, session.left_options)

  if not from_autocmd and vim.api.nvim_win_is_valid(session.right_win) then
    pcall(vim.api.nvim_win_close, session.right_win, true)
  end

  if vim.api.nvim_win_is_valid(session.left_win) then
    pcall(vim.api.nvim_set_current_win, session.left_win)
  end
end

function M.older()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  if session.index >= #session.entries then
    notify("Already at the oldest revision")
    return
  end

  load_index(session, session.index + 1)
end

function M.newer()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  if session.index <= 1 then
    notify("Already at the newest revision")
    return
  end

  load_index(session, session.index - 1)
end

function M.select()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  local items = {}
  for i, entry in ipairs(session.entries) do
    items[i] = {
      index = i,
      label = string.format("%3d  %s  %s  %-16s  %s", i, entry.short, entry.date, entry.author, entry.subject),
      entry = entry,
    }
  end

  vim.ui.select(items, {
    prompt = "File history: " .. session.relpath,
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      load_index(session, choice.index)
    end
  end)
end

function M.refresh()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  local current_hash = session.entries[session.index] and session.entries[session.index].hash
  local entries, err = git.history(session.root, session.relpath, config.options.follow)

  if not entries then
    notify(err or "Could not refresh Git history", vim.log.levels.ERROR)
    return
  end

  if #entries == 0 then
    notify("No Git history found", vim.log.levels.WARN)
    return
  end

  session.entries = entries

  local index = 1
  if current_hash then
    for i, entry in ipairs(entries) do
      if entry.hash == current_hash then
        index = i
        break
      end
    end
  end

  load_index(session, index)
end

local function apply_history_range(session, start_line, end_line)
  if not vim.api.nvim_win_is_valid(session.left_win)
    or not vim.api.nvim_win_is_valid(session.right_win)
    or not vim.api.nvim_buf_is_valid(session.left_buf)
    or not vim.api.nvim_buf_is_valid(session.history_buf) then
    notify("File-history windows are no longer valid", vim.log.levels.WARN)
    return false
  end

  if not vim.bo[session.left_buf].modifiable then
    notify("Current buffer is not modifiable", vim.log.levels.ERROR)
    return false
  end

  local target = tostring(session.left_buf)
  local command

  if start_line and end_line then
    start_line = math.max(0, start_line)
    end_line = math.max(start_line, end_line)
    command = string.format("silent %d,%ddiffput %s", start_line, end_line, target)
  else
    command = "silent diffput " .. target
  end

  local ok, err = pcall(vim.api.nvim_win_call, session.right_win, function()
    vim.cmd(command)
  end)

  if not ok then
    notify("Could not apply historical change: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  update_diff(session)
  return true
end

function M.apply_hunk()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  apply_history_range(session)
end

function M.apply_selection()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  -- Called by the visual-mode mapping in the history buffer. `v` is the
  -- opposite end of the active Visual selection and `.` is the cursor end.
  local first = vim.fn.line("v")
  local last = vim.fn.line(".")
  if first > last then
    first, last = last, first
  end

  apply_history_range(session, first, last)
end

function M.apply_file()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  if not vim.api.nvim_win_is_valid(session.left_win)
    or not vim.api.nvim_win_is_valid(session.right_win)
    or not vim.api.nvim_buf_is_valid(session.left_buf) then
    notify("File-history windows are no longer valid", vim.log.levels.WARN)
    return
  end

  if not vim.bo[session.left_buf].modifiable then
    notify("Current buffer is not modifiable", vim.log.levels.ERROR)
    return
  end

  -- Neovim's diff help defines 0,$+1 as the complete diff range, including
  -- deleted lines that do not have a normal buffer line number.
  local target = tostring(session.left_buf)
  local ok, err = pcall(vim.api.nvim_win_call, session.right_win, function()
    vim.cmd("silent 0,$+1diffput " .. target)
  end)

  if not ok then
    notify("Could not restore historical revision: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  update_diff(session)
end

function M.swap()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  if not vim.api.nvim_win_is_valid(session.left_win)
    or not vim.api.nvim_win_is_valid(session.right_win) then
    notify("File-history windows are no longer valid", vim.log.levels.WARN)
    return
  end

  -- Preserve which pane the user is currently focused in. nvim_win_set_config()
  -- moves the existing split window itself, so buffers and window-local options
  -- stay attached to their semantic panes.
  local focused = vim.api.nvim_get_current_win()
  local target_side = session.swapped and "right" or "left"

  local ok, err = pcall(vim.api.nvim_win_set_config, session.right_win, {
    split = target_side,
    win = session.left_win,
  })

  if not ok then
    notify("Could not swap file-history panes: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  session.swapped = not session.swapped

  if focused == session.left_win or focused == session.right_win then
    pcall(vim.api.nvim_set_current_win, focused)
  end

  update_diff(session)
end

function M.on_win_closed(winid)
  for _, session in pairs(sessions) do
    if not session.closing then
      if session.right_win == winid then
        -- The history pane is already gone; only restore the current pane.
        M.close(session.tab, true)
        return
      elseif session.left_win == winid then
        -- The current pane disappeared, so tear down the still-open history pane.
        M.close(session.tab, false)
        return
      end
    end
  end
end

function M.get_session()
  return current_session()
end

return M
