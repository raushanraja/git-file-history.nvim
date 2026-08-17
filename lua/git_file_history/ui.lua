local M = {}

local hunk_ns = vim.api.nvim_create_namespace("git_file_history_hunk_actions")

local function escape_statusline(text)
  return tostring(text or ""):gsub("%%", "%%%%")
end

function M.define_highlights()
  local links = {
    GitFileHistoryTitle = "Title",
    GitFileHistoryIndex = "Special",
    GitFileHistoryHash = "Identifier",
    GitFileHistoryMeta = "Comment",
    GitFileHistoryAbsent = "WarningMsg",
    GitFileHistoryClose = "DiagnosticError",

    -- No colors are hard-coded. The active colorscheme owns the visual language.
    -- QuietDark, for example, already styles DiffText as a strong diff accent.
    GitFileHistoryAction = "DiffText",
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

function M.clear_hunk_actions(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, hunk_ns, 0, -1)
  end
end

--- Render transfer markers on HISTORY.
---
--- HISTORY left  : marker is right-aligned so it sits visually next to CURRENT.
--- HISTORY right : marker is a sign on the left edge and points back to CURRENT.
function M.render_hunk_actions(buf, hunks, history_side, indicators)
  M.clear_hunk_actions(buf)

  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local line_count = math.max(vim.api.nvim_buf_line_count(buf), 1)
  local indicator = history_side == "left" and indicators.right or indicators.left

  for i, hunk in ipairs(hunks) do
    local line = math.max(1, math.min(hunk.marker_line, line_count))
    local opts = {
      id = 10000 + i,
      priority = 220,
    }

    if history_side == "left" then
      opts.hl_mode = "combine"
      opts.virt_text = { { " " .. indicator .. " ", "GitFileHistoryAction" } }
      opts.virt_text_pos = "right_align"
    else
      opts.sign_text = indicator
      opts.sign_hl_group = "GitFileHistoryAction"
    end

    pcall(vim.api.nvim_buf_set_extmark, buf, hunk_ns, line - 1, 0, opts)
  end
end

return M
