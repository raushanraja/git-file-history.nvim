local M = {}

local action_ns = vim.api.nvim_create_namespace("git_file_history_action_column")

local function escape_statusline(text)
  return tostring(text or ""):gsub("%%", "%%%%")
end

local function win_topline(win)
  if not vim.api.nvim_win_is_valid(win) then
    return 1
  end

  return vim.api.nvim_win_call(win, function()
    return vim.fn.line("w0")
  end)
end

local function content_top_screen_row(win)
  local topline = win_topline(win)
  local pos = vim.fn.screenpos(win, topline, 1)
  if type(pos) == "table" and (pos.row or 0) > 0 then
    return pos.row
  end

  local winpos = vim.api.nvim_win_get_position(win)
  return winpos[1] + 1
end

local function screen_row_for_line(win, line)
  if not vim.api.nvim_win_is_valid(win) or not line or line < 1 then
    return nil
  end

  local count = math.max(vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)), 1)
  line = math.max(1, math.min(line, count))
  local pos = vim.fn.screenpos(win, line, 1)
  if type(pos) ~= "table" or (pos.row or 0) <= 0 then
    return nil
  end
  return pos.row
end

function M.define_highlights()
  local links = {
    GitFileHistoryTitle = "Title",
    GitFileHistoryIndex = "Special",
    GitFileHistoryHash = "Identifier",
    GitFileHistoryMeta = "Comment",
    GitFileHistoryAbsent = "WarningMsg",
    GitFileHistoryClose = "DiagnosticError",

    -- No fixed colors: active colorscheme owns the workbench visual language.
    GitFileHistoryAction = "DiffText",
    GitFileHistoryActionNormal = "Normal",
    GitFileHistoryActionCursor = "CursorLine",
  }

  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { default = true, link = target })
  end
end

function M.history_buffer(current_buf, relpath)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  local ft = vim.bo[current_buf].filetype
  if ft ~= "" then
    vim.bo[buf].filetype = ft
  end

  pcall(vim.api.nvim_buf_set_name, buf, "git-history://" .. relpath)
  return buf
end

function M.action_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.bo[buf].filetype = "git-file-history-actions"
  pcall(vim.api.nvim_buf_set_name, buf, "git-file-history://actions")
  return buf
end

function M.set_content(buf, content, absent)
  local lines

  if absent or content == "" then
    lines = {}
  else
    lines = vim.split(content, "\n", { plain = true })
    if content:sub(-1) == "\n" and lines[#lines] == "" then
      table.remove(lines)
    end
  end

  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].endofline = absent or content:sub(-1) == "\n"
  vim.bo[buf].modified = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
end

function M.set_winbar(win, entry, index, total, absent, show_metadata)
  local parts = {}

  if show_metadata ~= false then
    vim.list_extend(parts, {
      "%#GitFileHistoryTitle# HISTORY ",
      "%#GitFileHistoryIndex#" .. escape_statusline(index .. "/" .. total) .. " ",
      "%#GitFileHistoryHash#" .. escape_statusline(entry.short) .. " ",
      "%#GitFileHistoryMeta#" .. escape_statusline(entry.date),
      "  ",
      escape_statusline(entry.author),
      "  •  ",
      escape_statusline(entry.subject),
    })

    if absent then
      parts[#parts + 1] = "  %#GitFileHistoryAbsent#[file absent]"
    end
  else
    parts[#parts + 1] = "%#GitFileHistoryTitle# HISTORY"
  end

  -- The close control is always present. With 'mouse' enabled it is clickable;
  -- q/:GitFileHistoryClose remain available for keyboard-only use.
  parts[#parts + 1] = "%="
  parts[#parts + 1] = "%#GitFileHistoryClose#%@v:lua.GitFileHistoryCloseClick@ × Close %T"
  parts[#parts + 1] = "%*"
  vim.wo[win].winbar = table.concat(parts)
end

function M.open_history(buf, current_side)
  if current_side == "right" then
    -- Keep the original/live window on the right and create HISTORY on the left.
    vim.cmd("leftabove vsplit")
  else
    vim.cmd("rightbelow vsplit")
  end

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  return win
end

function M.apply_history_window_options(win)
  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "yes"
  vim.wo[win].wrap = false
  vim.wo[win].winfixwidth = false
end

local function action_geometry(session, width)
  if not vim.api.nvim_win_is_valid(session.current_win)
    or not vim.api.nvim_win_is_valid(session.history_win) then
    return nil
  end

  local left_win = session.history_side == "left" and session.history_win or session.current_win
  local current_top = content_top_screen_row(session.current_win)
  local history_top = content_top_screen_row(session.history_win)
  local start_row = math.max(current_top, history_top)

  local current_end = current_top + vim.api.nvim_win_get_height(session.current_win) - 1
  local history_end = history_top + vim.api.nvim_win_get_height(session.history_win) - 1
  local end_row = math.min(current_end, history_end)
  local height = math.max(1, end_row - start_row + 1)

  local left_pos = vim.api.nvim_win_get_position(left_win)
  local left_width = vim.api.nvim_win_get_width(left_win)
  local col = left_pos[2] + left_width - math.floor(width / 2)

  return {
    row = start_row - 1,
    col = math.max(0, col),
    width = width,
    height = height,
    start_screen_row = start_row,
    end_screen_row = end_row,
  }
end

local function set_action_window_options(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = table.concat({
    "Normal:GitFileHistoryActionNormal",
    "CursorLine:GitFileHistoryActionCursor",
  }, ",")
end

function M.ensure_action_window(session, opts)
  if opts.enabled == false then
    M.close_action_window(session)
    return nil
  end

  local geometry = action_geometry(session, opts.width or 3)
  if not geometry then
    return nil
  end

  if not vim.api.nvim_buf_is_valid(session.action_buf) then
    session.action_buf = M.action_buffer()
  end

  local cfg = {
    relative = "editor",
    row = geometry.row,
    col = geometry.col,
    width = geometry.width,
    height = geometry.height,
    style = "minimal",
    focusable = true,
    zindex = 80,
    noautocmd = true,
  }

  if vim.api.nvim_win_is_valid(session.action_win) then
    pcall(vim.api.nvim_win_set_config, session.action_win, cfg)
  else
    session.action_win = vim.api.nvim_open_win(session.action_buf, false, cfg)
    set_action_window_options(session.action_win)
  end

  session.action_geometry = geometry
  return session.action_win
end

function M.close_action_window(session)
  if session and vim.api.nvim_win_is_valid(session.action_win) then
    pcall(vim.api.nvim_win_close, session.action_win, true)
  end
  if session then
    session.action_win = nil
  end
end

local function hunk_anchor(session, hunk)
  -- Choose a real line on whichever side actually owns the changed rows.
  -- This is what lets an arrow sit on a HISTORY filler/deleted row: when
  -- HISTORY has zero lines, CURRENT's corresponding line supplies the screen
  -- coordinate, while the action column itself remains independently focusable.
  if hunk.history_count == 0 and hunk.current_count > 0 then
    local line = hunk.current_start + math.floor((hunk.current_count - 1) / 2)
    return session.current_win, line
  end

  if hunk.current_count == 0 and hunk.history_count > 0 then
    local line = hunk.history_start + math.floor((hunk.history_count - 1) / 2)
    return session.history_win, line
  end

  if hunk.history_count > 0 then
    local line = hunk.history_start + math.floor((hunk.history_count - 1) / 2)
    return session.history_win, line
  end

  if hunk.current_count > 0 then
    local line = hunk.current_start + math.floor((hunk.current_count - 1) / 2)
    return session.current_win, line
  end
end

function M.render_action_column(session, hunks, opts)
  local win = M.ensure_action_window(session, opts)
  if not win or not session.action_geometry then
    return
  end

  local geometry = session.action_geometry
  local lines = {}
  for _ = 1, geometry.height do
    lines[#lines + 1] = ""
  end

  local indicator = session.history_side == "left" and opts.right or opts.left
  local pad = math.max(0, math.floor((geometry.width - vim.fn.strdisplaywidth(indicator)) / 2))
  local display = string.rep(" ", pad) .. indicator
  session.action_line_to_hunk = {}
  session.visible_action_lines = {}

  for i, hunk in ipairs(hunks) do
    local source_win, source_line = hunk_anchor(session, hunk)
    local row = source_win and screen_row_for_line(source_win, source_line) or nil

    if row and row >= geometry.start_screen_row and row <= geometry.end_screen_row then
      local action_line = row - geometry.start_screen_row + 1
      lines[action_line] = display
      session.action_line_to_hunk[action_line] = i
      session.visible_action_lines[#session.visible_action_lines + 1] = action_line
    end
  end

  vim.bo[session.action_buf].modifiable = true
  vim.bo[session.action_buf].readonly = false
  vim.api.nvim_buf_set_lines(session.action_buf, 0, -1, false, lines)
  vim.bo[session.action_buf].modified = false
  vim.bo[session.action_buf].modifiable = false
  vim.bo[session.action_buf].readonly = true

  vim.api.nvim_buf_clear_namespace(session.action_buf, action_ns, 0, -1)
  for _, line in ipairs(session.visible_action_lines) do
    vim.api.nvim_buf_set_extmark(session.action_buf, action_ns, line - 1, 0, {
      end_col = #display,
      hl_group = "GitFileHistoryAction",
      priority = 230,
    })
  end

  -- Keep the action cursor on a real action when possible.
  if vim.api.nvim_get_current_win() == session.action_win and #session.visible_action_lines > 0 then
    local cursor = vim.api.nvim_win_get_cursor(session.action_win)[1]
    if not session.action_line_to_hunk[cursor] then
      local best = session.visible_action_lines[1]
      for _, line in ipairs(session.visible_action_lines) do
        if math.abs(line - cursor) < math.abs(best - cursor) then
          best = line
        end
      end
      pcall(vim.api.nvim_win_set_cursor, session.action_win, { best, 0 })
    end
  end
end

return M
