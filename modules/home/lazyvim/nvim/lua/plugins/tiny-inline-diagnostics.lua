return {
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    opts = {
      -- preset = "powerline",
      options = {
        show_source = true,
        throttle = 0,
        multilines = {
          enabled = true,
          always_show = true,
        },
        multiple_diag_under_cursor = true,
        enable_on_insert = true,
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = { diagnostics = { virtual_text = false } },
  },
}
