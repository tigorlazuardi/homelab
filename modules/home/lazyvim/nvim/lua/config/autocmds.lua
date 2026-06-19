-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Disable diagnostics for .env files
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { ".env", ".env.*", "*.env" },
  callback = function()
    vim.diagnostic.enable(false, { bufnr = 0 })
  end,
})

-- Disable diagnostics for certail filetypes
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "dockerfile" },
  callback = function()
    vim.diagnostic.enable(false, { bufnr = 0 })
  end,
})

-- ============================================
-- Mouse enhancements
-- ============================================

-- Copy to clipboard on mouse selection release
vim.keymap.set("v", "<LeftRelease>", '"+ygv', { silent = true, desc = "Copy to clipboard on mouse select" })

-- Middle-click paste from clipboard
vim.keymap.set("n", "<MiddleMouse>", '"+p', { silent = true, desc = "Paste from clipboard" })
vim.keymap.set("i", "<MiddleMouse>", "<C-r>+", { silent = true, desc = "Paste from clipboard" })
vim.keymap.set("v", "<MiddleMouse>", '"+p', { silent = true, desc = "Paste from clipboard" })

-- Ctrl+click go to definition (like VSCode)
vim.keymap.set(
  "n",
  "<C-LeftMouse>",
  "<LeftMouse><cmd>lua vim.lsp.buf.definition()<CR>",
  { silent = true, desc = "Go to definition" }
)

-- Left click release shows hover documentation if available (with VSCode-like delay)
-- vim.keymap.set("n", "<LeftRelease>", function()
--   if #vim.lsp.get_clients({ bufnr = 0 }) > 0 then
--     local pos = vim.api.nvim_win_get_cursor(0)
--     local bufnr = vim.api.nvim_get_current_buf()
--     vim.defer_fn(function()
--       -- Only show hover if cursor hasn't moved
--       if vim.api.nvim_get_current_buf() == bufnr then
--         local new_pos = vim.api.nvim_win_get_cursor(0)
--         if pos[1] == new_pos[1] and pos[2] == new_pos[2] then
--           vim.lsp.buf.hover()
--         end
--       end
--     end, 500)
--   end
-- end, { silent = true, desc = "Click and show hover" })

-- Double-click select word and copy
vim.keymap.set("n", "<2-LeftMouse>", 'viw"+y', { silent = true, desc = "Select word and copy" })

-- Triple-click select line and copy
vim.keymap.set("n", "<3-LeftMouse>", '"+yy', { silent = true, desc = "Select line and copy" })

-- Right-click context menu
vim.keymap.set("n", "<RightMouse>", function()
  vim.cmd([[popup PopUp]])
end, { silent = true, desc = "Context menu" })
vim.keymap.set("v", "<RightMouse>", function()
  vim.cmd([[popup PopUp]])
end, { silent = true, desc = "Context menu" })

-- Alt+scroll for horizontal scrolling
vim.keymap.set("n", "<A-ScrollWheelUp>", "4zh", { silent = true, desc = "Scroll left" })
vim.keymap.set("n", "<A-ScrollWheelDown>", "4zl", { silent = true, desc = "Scroll right" })

-- Scroll unfocused splits (mousefocus enables this)
vim.opt.mousefocus = true

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.expandtab = true
  end,
})
