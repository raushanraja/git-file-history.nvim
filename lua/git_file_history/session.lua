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

local function opposite(side)
  return side == "left" and "right" or "left"
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
    if config.options.fold_unchanged == false then
      -- Keep the complete file visible. Diff highlighting and filler lines stay
      -- active; only the automatic folding of unchanged regions is disabled.
      vim.wo.foldenable = false
    end
  end)
end

local function keep_expanded(session)
  if config.options.fold_unchanged ~= false then
    return
  end

  for _, win in ipairs({ session.current_win, session.history_win }) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].foldenable = false
    end
  end
end

local function buffer_text(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return ""
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")

  if vim.bo[buf].endofline then
    text = text .. "\n"
  end

  return text
end

local function diff_index_options()
  -- Keep our visible action markers as close as possible to Neovim's actual
  -- diff hunks by mirroring the relevant parts of 'diffopt'.
  local items = {}
  for item in (vim.o.diffopt or ""):gmatch("[^,]+") do
    items[item] = true
  end

  local algorithm = "myers"
  local linematch
  for item in pairs(items) do
    algorithm = item:match("^algorithm:(.+)$") or algorithm
    linematch = tonumber(item:match("^linematch:(%d+)$")) or linematch
  end

  local opts = {
    result_type = "indices",
    algorithm = algorithm,
    indent_heuristic = items["indent-heuristic"] == true,
    ignore_blank_lines = items.iblank == true,
    ignore_whitespace = items.iwhiteall == true,
    ignore_whitespace_change = items.iwhite == true,
    ignore_whitespace_change_at_eol = items.iwhiteeol == true,
  }

  if linematch then
    opts.linematch = linematch
  end

  return opts
end

local function compute_hunks(session)
  if not vim.api.nvim_buf_is_valid(session.history_buf)
    or not vim.api.nvim_buf_is_valid(session.current_buf) then
    return {}
  end

  local history_text = buffer_text(session.history_buf)
  local current_text = buffer_text(session.current_buf)

  local ok, raw = pcall(vim.text.diff, history_text, current_text, diff_index_options())

  if not ok or type(raw) ~= "table" then
    return {}
  end

  local hunks = {}

  for _, values in ipairs(raw) do
    hunks[#hunks + 1] = {
      history_start = values[1],
      history_count = values[2],
      current_start = values[3],
      current_count = values[4],
    }
  end

  return hunks
end

local function refresh_action_column(session)
  local opts = config.options.action_column or {}
  if opts.enabled == false then
    ui.close_action_window(session)
    session.hunks = {}
    session.action_line_to_hunk = {}
    session.visible_action_lines = {}
    return
  end

  local hunks = compute_hunks(session)
  session.hunks = hunks
  ui.render_action_column(session, hunks, opts)
end

local function update_diff(session)
  if not vim.api.nvim_win_is_valid(session.current_win) then
    return
  end

  vim.api.nvim_win_call(session.current_win, function()
    vim.cmd("silent! diffupdate")
  end)

  keep_expanded(session)
  refresh_action_column(session)
end

local function schedule_diff_refresh(session)
  session.diff_generation = (session.diff_generation or 0) + 1
  local generation = session.diff_generation

  vim.defer_fn(function()
    if session.closing or generation ~= session.diff_generation then
      return
    end

    if sessions[tabkey(session.tab)] ~= session then
      return
    end

    update_diff(session)
  end, 80)
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
  end, "Pull historical hunk into current file")

  map(maps.apply_hunk_alt, function()
    require("git_file_history").apply_hunk()
  end, "Pull historical hunk into current file")

  map(maps.apply_file, function()
    require("git_file_history").apply_file()
  end, "Restore entire historical revision into current file")

  map(maps.focus_actions, function()
    require("git_file_history").focus_actions()
  end, "Focus Git history hunk actions")

  map(maps.undo, function()
    require("git_file_history").undo()
  end, "Undo last change in current file")

  if maps.apply_hunk and maps.apply_hunk ~= "" then
    vim.keymap.set("x", maps.apply_hunk, function()
      require("git_file_history").apply_selection()
    end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Pull selected historical diff range into current file",
    })
  end

  map(maps.close, function()
    require("git_file_history").close()
  end, "Close file history")
end

local function install_action_mappings(buf)
  local maps = config.options.mappings
  local opts = { buffer = buf, silent = true, nowait = true }

  local function map(lhs, rhs, desc)
    if lhs and lhs ~= "" then
      vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
    end
  end

  map("j", function()
    require("git_file_history").next_action()
  end, "Next visible Git history hunk")

  map("]c", function()
    require("git_file_history").next_action()
  end, "Next visible Git history hunk")

  map("k", function()
    require("git_file_history").prev_action()
  end, "Previous visible Git history hunk")

  map("[c", function()
    require("git_file_history").prev_action()
  end, "Previous visible Git history hunk")

  map(maps.apply_hunk, function()
    require("git_file_history").apply_action()
  end, "Pull selected historical hunk into current file")

  map(maps.apply_hunk_alt, function()
    require("git_file_history").apply_action()
  end, "Pull selected historical hunk into current file")

  map(maps.undo, function()
    require("git_file_history").undo()
  end, "Undo last change in current file")

  map(maps.older, function() require("git_file_history").older() end, "Older file revision")
  map(maps.newer, function() require("git_file_history").newer() end, "Newer file revision")
  map(maps.older_alt, function() require("git_file_history").older() end, "Older file revision")
  map(maps.newer_alt, function() require("git_file_history").newer() end, "Newer file revision")
  map(maps.select, function() require("git_file_history").select() end, "Select file revision")
  map(maps.refresh, function() require("git_file_history").refresh() end, "Refresh file history")
  map(maps.swap, function() require("git_file_history").swap() end, "Swap current/history sides")
  map(maps.close, function() require("git_file_history").close() end, "Close file history")

  map("h", function() require("git_file_history").focus_left() end, "Focus left diff pane")
  map("l", function() require("git_file_history").focus_right() end, "Focus right diff pane")
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

  if vim.api.nvim_win_is_valid(session.history_win) then
    ui.set_winbar(session.history_win, entry, index, #session.entries, absent, config.options.winbar)
  end

  update_diff(session)

  if vim.api.nvim_win_is_valid(session.history_win) then
    local current_cursor = { 1, 0 }
    if vim.api.nvim_win_is_valid(session.current_win) then
      current_cursor = vim.api.nvim_win_get_cursor(session.current_win)
    end

    local line_count = math.max(vim.api.nvim_buf_line_count(session.history_buf), 1)
    current_cursor[1] = math.min(current_cursor[1], line_count)
    pcall(vim.api.nvim_win_set_cursor, session.history_win, current_cursor)
  end

  return true
end

local function install_session_autocmds(session)
  local group = vim.api.nvim_create_augroup(
    "GitFileHistorySession" .. tostring(session.tab),
    { clear = true }
  )
  session.augroup = group

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    buffer = session.current_buf,
    callback = function()
      schedule_diff_refresh(session)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = session.current_buf,
    callback = function()
      schedule_diff_refresh(session)
    end,
  })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function()
      if not session.closing then
        vim.schedule(function()
          if not session.closing and sessions[tabkey(session.tab)] == session then
            refresh_action_column(session)
          end
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if not session.closing then
        vim.schedule(function()
          if not session.closing and sessions[tabkey(session.tab)] == session then
            refresh_action_column(session)
          end
        end)
      end
    end,
  })
end

function M.open()
  local existing = current_session()
  if existing then
    if vim.api.nvim_win_is_valid(existing.history_win) then
      vim.api.nvim_set_current_win(existing.history_win)
      return
    end
    M.close()
  end

  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(current_buf)

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

  local current_side = config.options.current_side
  local history_side = opposite(current_side)

  local history_buf = ui.history_buffer(current_buf, relpath)
  local history_win = ui.open_history(history_buf, current_side)
  ui.apply_history_window_options(history_win)
  install_buffer_mappings(history_buf)

  local tab = vim.api.nvim_get_current_tabpage()
  local session = {
    tab = tab,

    current_win = current_win,
    current_buf = current_buf,
    current_side = current_side,

    history_win = history_win,
    history_buf = history_buf,
    history_side = history_side,

    root = root,
    relpath = relpath,
    entries = entries,
    index = 1,
    current_options = save_window_options(current_win),
    closing = false,
    hunks = {},
    action_buf = ui.action_buffer(),
    action_win = nil,
    action_line_to_hunk = {},
    visible_action_lines = {},
  }

  sessions[tabkey(tab)] = session

  set_diff(current_win)
  set_diff(history_win)
  install_action_mappings(session.action_buf)

  if config.options.scrollbind then
    vim.wo[current_win].scrollbind = true
    vim.wo[history_win].scrollbind = true
  end

  install_session_autocmds(session)

  local start = config.options.start
  local start_index = type(start) == "number" and start or 1
  start_index = math.max(1, math.min(start_index, #entries))
  load_index(session, start_index)

  -- History gets focus so revision navigation and transfer mappings work
  -- immediately, while CURRENT remains visually on the configured side.
  vim.api.nvim_set_current_win(history_win)
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

  ui.close_action_window(session)

  if session.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, session.augroup)
  end

  restore_window_options(session.current_win, session.current_options)

  if not from_autocmd and vim.api.nvim_win_is_valid(session.history_win) then
    pcall(vim.api.nvim_win_close, session.history_win, true)
  end

  if vim.api.nvim_win_is_valid(session.current_win) then
    pcall(vim.api.nvim_set_current_win, session.current_win)
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
  if not vim.api.nvim_win_is_valid(session.current_win)
    or not vim.api.nvim_win_is_valid(session.history_win)
    or not vim.api.nvim_buf_is_valid(session.current_buf)
    or not vim.api.nvim_buf_is_valid(session.history_buf) then
    notify("File-history windows are no longer valid", vim.log.levels.WARN)
    return false
  end

  if not vim.bo[session.current_buf].modifiable then
    notify("Current buffer is not modifiable", vim.log.levels.ERROR)
    return false
  end

  local target = tostring(session.current_buf)
  local command

  if start_line and end_line then
    start_line = math.max(0, start_line)
    end_line = math.max(start_line, end_line)
    command = string.format("silent %d,%ddiffput %s", start_line, end_line, target)
  else
    command = "silent diffput " .. target
  end

  local ok, err = pcall(vim.api.nvim_win_call, session.history_win, function()
    vim.cmd(command)
  end)

  if not ok then
    notify("Could not pull historical change: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  update_diff(session)
  return true
end

local function apply_hunk_index(session, index)
  local hunk = session.hunks and session.hunks[index]
  if not hunk then
    notify("No diff hunk selected", vim.log.levels.WARN)
    return false
  end

  if not vim.bo[session.current_buf].modifiable then
    notify("Current buffer is not modifiable", vim.log.levels.ERROR)
    return false
  end

  local ok, err

  if hunk.current_count > 0 then
    local line_count = math.max(vim.api.nvim_buf_line_count(session.current_buf), 1)
    local line = math.max(1, math.min(hunk.current_start, line_count))
    pcall(vim.api.nvim_win_set_cursor, session.current_win, { line, 0 })
    ok, err = pcall(vim.api.nvim_win_call, session.current_win, function()
      vim.cmd("silent diffget " .. tostring(session.history_buf))
    end)
  elseif hunk.history_count > 0 then
    local line_count = math.max(vim.api.nvim_buf_line_count(session.history_buf), 1)
    local line = math.max(1, math.min(hunk.history_start, line_count))
    pcall(vim.api.nvim_win_set_cursor, session.history_win, { line, 0 })
    ok, err = pcall(vim.api.nvim_win_call, session.history_win, function()
      vim.cmd("silent diffput " .. tostring(session.current_buf))
    end)
  else
    return false
  end

  if not ok then
    notify("Could not pull historical change: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  update_diff(session)
  return true
end

local function action_lines(session)
  local lines = vim.deepcopy(session.visible_action_lines or {})
  table.sort(lines)
  return lines
end

local function move_action_cursor(session, direction)
  if not vim.api.nvim_win_is_valid(session.action_win) then
    return
  end

  local lines = action_lines(session)
  if #lines == 0 then
    notify("No visible diff actions")
    return
  end

  local current = vim.api.nvim_win_get_cursor(session.action_win)[1]
  local target

  if direction > 0 then
    for _, line in ipairs(lines) do
      if line > current then
        target = line
        break
      end
    end
    target = target or lines[1]
  else
    for i = #lines, 1, -1 do
      if lines[i] < current then
        target = lines[i]
        break
      end
    end
    target = target or lines[#lines]
  end

  pcall(vim.api.nvim_win_set_cursor, session.action_win, { target, 0 })
end

function M.apply_action()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  if not vim.api.nvim_win_is_valid(session.action_win) then
    notify("Hunk action column is not available", vim.log.levels.WARN)
    return
  end

  local line = vim.api.nvim_win_get_cursor(session.action_win)[1]
  local index = session.action_line_to_hunk and session.action_line_to_hunk[line]
  if not index then
    notify("Move to an arrow before applying a change", vim.log.levels.WARN)
    return
  end

  apply_hunk_index(session, index)
end

function M.next_action()
  local session = current_session()
  if not session then
    return
  end
  move_action_cursor(session, 1)
end

function M.prev_action()
  local session = current_session()
  if not session then
    return
  end
  move_action_cursor(session, -1)
end

function M.focus_actions()
  local session = current_session()
  if not session or not vim.api.nvim_win_is_valid(session.action_win) then
    notify("Hunk action column is not available", vim.log.levels.WARN)
    return
  end

  vim.api.nvim_set_current_win(session.action_win)
  local lines = action_lines(session)
  if #lines > 0 then
    pcall(vim.api.nvim_win_set_cursor, session.action_win, { lines[1], 0 })
  end
end

function M.focus_left()
  local session = current_session()
  if not session then
    return
  end
  local win = session.history_side == "left" and session.history_win or session.current_win
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

function M.focus_right()
  local session = current_session()
  if not session then
    return
  end
  local win = session.history_side == "right" and session.history_win or session.current_win
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

function M.undo()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  if not vim.api.nvim_win_is_valid(session.current_win) then
    return
  end

  local ok, err = pcall(vim.api.nvim_win_call, session.current_win, function()
    vim.cmd("silent undo")
  end)

  if not ok then
    notify("Nothing to undo: " .. tostring(err), vim.log.levels.WARN)
    return
  end

  update_diff(session)
end

function M.apply_hunk()
  local session = current_session()
  if not session then
    notify("No active file-history session", vim.log.levels.WARN)
    return
  end

  -- The action is always semantically HISTORY -> CURRENT. If invoked while the
  -- cursor is in CURRENT, use :diffget; otherwise use :diffput from HISTORY.
  local focused = vim.api.nvim_get_current_win()

  if focused == session.current_win then
    if not vim.bo[session.current_buf].modifiable then
      notify("Current buffer is not modifiable", vim.log.levels.ERROR)
      return
    end

    local ok, err = pcall(vim.api.nvim_win_call, session.current_win, function()
      vim.cmd("silent diffget " .. tostring(session.history_buf))
    end)

    if not ok then
      notify("Could not pull historical change: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    update_diff(session)
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

  -- Called by the visual-mode mapping in HISTORY. `v` is the opposite end of
  -- the active selection and `.` is the cursor end.
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

  if not vim.api.nvim_win_is_valid(session.current_win)
    or not vim.api.nvim_win_is_valid(session.history_win)
    or not vim.api.nvim_buf_is_valid(session.current_buf) then
    notify("File-history windows are no longer valid", vim.log.levels.WARN)
    return
  end

  if not vim.bo[session.current_buf].modifiable then
    notify("Current buffer is not modifiable", vim.log.levels.ERROR)
    return
  end

  -- 0,$+1 includes diff filler rows, so this also handles lines that exist on
  -- only one side of the comparison.
  local target = tostring(session.current_buf)
  local ok, err = pcall(vim.api.nvim_win_call, session.history_win, function()
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

  if not vim.api.nvim_win_is_valid(session.current_win)
    or not vim.api.nvim_win_is_valid(session.history_win) then
    notify("File-history windows are no longer valid", vim.log.levels.WARN)
    return
  end

  local focused = vim.api.nvim_get_current_win()
  local target_side = session.history_side == "left" and "right" or "left"

  local ok, err = pcall(vim.api.nvim_win_set_config, session.history_win, {
    split = target_side,
    win = session.current_win,
  })

  if not ok then
    notify("Could not swap file-history panes: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  session.history_side = target_side
  session.current_side = opposite(target_side)

  if focused == session.current_win or focused == session.history_win then
    pcall(vim.api.nvim_set_current_win, focused)
  end

  update_diff(session)
end

function M.on_win_closed(winid)
  for _, session in pairs(sessions) do
    if not session.closing then
      if session.history_win == winid then
        -- HISTORY is already gone; only restore CURRENT and close ACTIONS.
        M.close(session.tab, true)
        return
      elseif session.current_win == winid then
        -- CURRENT disappeared, so tear down the remaining workbench windows.
        M.close(session.tab, false)
        return
      elseif session.action_win == winid then
        -- Closing the action gutter is treated as closing the workbench.
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
