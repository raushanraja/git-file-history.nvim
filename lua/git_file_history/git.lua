local M = {}

local function trim(s)
  return (s or ""):gsub("%s+$", "")
end

local function command(cwd, args, opts)
  opts = opts or {}

  local cmd = { "git", "-C", cwd }
  vim.list_extend(cmd, args)

  local result = vim.system(cmd, {
    text = opts.text ~= false,
  }):wait()

  if result.code ~= 0 then
    return nil, trim(result.stderr ~= "" and result.stderr or result.stdout)
  end

  return result.stdout or ""
end

function M.root_for(path)
  local dir = vim.fs.dirname(path)
  local out, err = command(dir, { "rev-parse", "--show-toplevel" })
  if not out then
    return nil, err
  end
  return trim(out)
end

function M.relative_path(root, path)
  root = vim.fs.normalize(root)
  path = vim.fs.normalize(path)

  if vim.fs.relpath then
    local rel = vim.fs.relpath(root, path)
    if rel then
      return rel
    end
  end

  local prefix = root
  if prefix:sub(-1) ~= "/" then
    prefix = prefix .. "/"
  end

  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end

  return path
end

local RECORD = "@@GFH@@"
local FIELD = string.char(31)

local function parse_history(stdout, fallback_path)
  local entries = {}
  local current = nil
  local last_path = fallback_path

  local function finish()
    if not current then
      return
    end

    current.path = current.path or last_path or fallback_path
    if current.path then
      last_path = current.path
    end

    entries[#entries + 1] = current
    current = nil
  end

  for line in (stdout .. "\n"):gmatch("(.-)\n") do
    if vim.startswith(line, RECORD) then
      finish()

      local payload = line:sub(#RECORD + 1)
      local fields = vim.split(payload, FIELD, { plain = true })

      current = {
        hash = fields[1] or "",
        short = fields[2] or "",
        author = fields[3] or "",
        date = fields[4] or "",
        subject = fields[5] or "",
      }
    elseif current and line ~= "" then
      -- `git log --follow --name-only` reports the filename as it existed
      -- at each point in history. This is what makes renamed files work.
      current.path = current.path or line
    end
  end

  finish()
  return entries
end

function M.history(root, relpath, follow)
  local args = {
    "log",
    "--date=short",
    "--format=" .. RECORD .. "%H%x1f%h%x1f%an%x1f%ad%x1f%s",
    "--name-only",
  }

  if follow ~= false then
    table.insert(args, "--follow")
  end

  vim.list_extend(args, { "--", relpath })

  local out, err = command(root, args)
  if not out then
    return nil, err
  end

  return parse_history(out, relpath)
end

function M.show(root, entry)
  local spec = entry.hash .. ":" .. entry.path

  -- A deletion commit legitimately has no blob at HASH:path. Represent it as
  -- an empty file so diff mode shows the current file as entirely added.
  local exists = command(root, { "cat-file", "-e", spec })
  if not exists then
    return "", true
  end

  local out, err = command(root, { "show", spec })
  if not out then
    return nil, false, err
  end

  if out:find("\0", 1, true) then
    return nil, false, "Binary files are not supported"
  end

  return out, false
end

return M
