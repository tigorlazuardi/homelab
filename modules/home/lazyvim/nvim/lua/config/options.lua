-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

if vim.g.neovide then
  vim.g.neovide_opacity = 0.7
  vim.g.neovide_window_blurred = true
  vim.g.experimental_layer_grouping = true
end

-- Enable this option to avoid conflicts with Prettier.
vim.g.lazyvim_prettier_needs_config = true

vim.opt.tabstop = 4

vim.opt.clipboard = "unnamedplus"

if vim.env.SSH_CLIENT or vim.env.HERDR_ENV then
  local function my_paste(reg)
    return function(lines)
      --[ 返回 “” 寄存器的内容，用来作为 p 操作符的粘贴物 ]
      local content = vim.fn.getreg('"')
      return vim.split(content, "\n")
    end
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
      ["+"] = my_paste("+"),
      ["*"] = my_paste("*"),
    },
  }
end
