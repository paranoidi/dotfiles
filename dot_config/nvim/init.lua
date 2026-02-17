-- ─── Global Defaults ─────────────────────────────────────────────
vim.opt.expandtab = true      -- Always use spaces, never tabs
vim.opt.tabstop = 4           -- A tab counts for 4 spaces
vim.opt.shiftwidth = 4        -- Indent size
vim.opt.softtabstop = 4       -- Tab key feels like 4 spaces

-- Disable mouse integration
vim.opt.mouse = ""

-- Show relative line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- ─── Filetype Specific ───────────────────────────────────────────
-- Python: 4 spaces (PEP 8 standard)
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
  end,
})

-- YAML / JSON / HTML / CSS / JavaScript / TypeScript: 2 spaces
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "yaml", "json", "html", "css", "javascript", "typescript" },
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
  end,
})

-- Lua: 2 spaces (Neovim convention)
vim.api.nvim_create_autocmd("FileType", {
  pattern = "lua",
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
  end,
})

-- Makefiles: MUST use real tabs
vim.api.nvim_create_autocmd("FileType", {
  pattern = "make",
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 8
    vim.opt_local.shiftwidth = 8
    vim.opt_local.softtabstop = 0
  end,
})

-- Go: uses tabs by convention (but displayed as width 4)
vim.api.nvim_create_autocmd("FileType", {
  pattern = "go",
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 0
  end,
})

-- Markdown: 2 spaces
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
  end,
})

-- Use system clipboard for all yank, delete, change, put operations
vim.opt.clipboard = "unnamedplus"

-- Line number colors (standard terminal colors)
vim.cmd [[
  highlight LineNr ctermfg=DarkGrey
  highlight CursorLineNr ctermfg=Grey cterm=bold
]]

-- ─── Plugin Management (lazy.nvim) ──────────────────────────────
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  { "numToStr/Comment.nvim", opts = {} },
})

