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

return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      ["*"] = {
        keys = {
          -- Add a keymap
          {
            "]]",
            function()
              goto_diagnostic_priority("next")
            end,
            desc = "Next diagnostics",
          },
          -- Change an existing keymap
          {
            "[[",
            function()
              goto_diagnostic_priority("prev")
            end,
            desc = "Previous diagnostics",
          },
        },
      },
    },
  },
}
