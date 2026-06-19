return {
  "folke/noice.nvim",
  opts = {
    routes = {
      -- Suppress "No information available" from LSP hover (tailwindcss-lsp)
      {
        filter = {
          event = "notify",
          find = "No information available",
        },
        opts = { skip = true },
      },
      {
        filter = {
          event = "lsp",
          kind = "message",
          find = "No information available",
        },
        opts = { skip = true },
      },
    },
  },
}
