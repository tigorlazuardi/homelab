return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gopls = {
          settings = {
            gopls = {
              usePlaceholders = false,
              hints = {
                assignVariableTypes = false,
                compositeLiteralFields = false,
                compositeLiteralTypes = false,
                constantValues = false,
                functionTypeParameters = false,
                parameterNames = false,
                rangeVariableTypes = false,
              },
              analyses = {
                -- disable shadow check (variable shadowing)
                shadow = false,
                -- disable all style/cosmetic checks (ST1xxx)
                ST1000 = false, -- package comment
                ST1003 = false, -- naming convention
                ST1005 = false, -- error strings capitalization
                ST1006 = false, -- receiver name
                ST1012 = false, -- error var prefix
                ST1016 = false, -- receiver name consistency
                ST1017 = false, -- yoda conditions
                ST1018 = false, -- string constant whitespace
                ST1019 = false, -- duplicate imports
                ST1020 = false, -- exported function comment
                ST1021 = false, -- exported type comment
                ST1022 = false, -- exported var comment
                ST1023 = false, -- redundant type declaration
              },
            },
          },
        },
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      -- disable golangci-lint integrated by lazyvim
      opts = opts or {}
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.go = {}
      return opts
    end,
  },
  {
    "edolphin-ydf/goimpl.nvim",
    ft = { "go" },
    dependencies = {
      "nvim-telescope/telescope.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      require("telescope").load_extension("goimpl")
    end,
  },
}
