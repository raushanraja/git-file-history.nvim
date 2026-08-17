local M = {}

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
  }

  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { default = true, link = target })
  end
end

function M.history_buffer(left_buf, relpath)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  local ft = vim.bo[left_buf].filetype
  if ft ~= "" then
    vim.bo[buf].filetype = ft
  end

  pcall(vim.api.nvim_buf_set_name, buf, "git-history://" .. relpath)
  return buf
end

function M.set_content(buf, content, absent)
  local lines

  if absent then
    lines = {}
  elseif content == "" then
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

function M.set_winbar(win, entry, index, total, absent)
  local parts = {
    "%#GitFileHistoryTitle# HISTORY ",
    "%#GitFileHistoryIndex#" .. escape_statusline(index .. "/" .. total) .. " ",
    "%#GitFileHistoryHash#" .. escape_statusline(entry.short) .. " ",
    "%#GitFileHistoryMeta#" .. escape_statusline(entry.date),
    "  ",
    escape_statusline(entry.author),
    "  •  ",
    escape_statusline(entry.subject),
  }

  if absent then
    parts[#parts + 1] = "  %#GitFileHistoryAbsent#[file absent]"
  end

  parts[#parts + 1] = "%*"
  vim.wo[win].winbar = table.concat(parts)
end

function M.open_right(buf)
  vim.cmd("rightbelow vsplit")
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

return M
