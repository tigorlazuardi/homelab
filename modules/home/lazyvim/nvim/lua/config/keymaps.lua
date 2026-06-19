-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set({ "n", "v", "s", "x", "o", "i", "l", "c", "t" }, "<C-S-v>", function()
  vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
end, { noremap = true, silent = true })

-- Diagnostic navigation with priority: error -> warn -> info -> hint
local function goto_diagnostic_priority(direction)
  local severity_order = {
    vim.diagnostic.severity.ERROR,
    vim.diagnostic.severity.WARN,
    vim.diagnostic.severity.INFO,
    vim.diagnostic.severity.HINT,
  }

  local goto_fn = direction == "next" and vim.diagnostic.goto_next or vim.diagnostic.goto_prev

  for _, severity in ipairs(severity_order) do
    local diagnostics = vim.diagnostic.get(0, { severity = severity })
    if #diagnostics > 0 then
      goto_fn({ severity = severity, wrap = true })
      return
    end
  end

  -- Fallback: no diagnostics found
  vim.notify("No diagnostics found", vim.log.levels.INFO)
end

vim.keymap.set("n", "]]", function()
  goto_diagnostic_priority("next")
end, { noremap = true, silent = true, desc = "Next diagnostic (error>warn>info)" })

vim.keymap.set("n", "[[", function()
  goto_diagnostic_priority("prev")
end, { noremap = true, silent = true, desc = "Prev diagnostic (error>warn>info)" })

-- Neovide font size adjustment
if vim.g.neovide then
  local function adjust_font_size(delta)
    local guifont = vim.o.guifont
    local font, size = guifont:match("(.+):h(%d+)")
    if font and size then
      local new_size = math.max(1, tonumber(size) + delta)
      vim.o.guifont = font .. ":h" .. new_size
    end
  end

  vim.keymap.set({ "n", "v", "i" }, "<C-=>", function()
    adjust_font_size(1)
  end, { noremap = true, silent = true, desc = "Increase font size" })

  vim.keymap.set({ "n", "v", "i" }, "<C-->", function()
    adjust_font_size(-1)
  end, { noremap = true, silent = true, desc = "Decrease font size" })
end
