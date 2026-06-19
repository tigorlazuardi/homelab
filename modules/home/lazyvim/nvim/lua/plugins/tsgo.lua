return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      vtsls = { enabled = false },
      tsgo = { enabled = true },
    },
  },
}
