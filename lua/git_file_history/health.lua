local M = {}

function M.check()
  vim.health.start("git-file-history.nvim")

  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim 0.12+ detected")
  else
    vim.health.error("Neovim 0.12+ is required")
  end

  if vim.fn.executable("git") == 1 then
    local result = vim.system({ "git", "--version" }, { text = true }):wait()
    local version = (result.stdout or ""):gsub("%s+$", "")
    vim.health.ok(version ~= "" and version or "Git is available")
  else
    vim.health.error("Git executable was not found in PATH")
  end
end

return M
