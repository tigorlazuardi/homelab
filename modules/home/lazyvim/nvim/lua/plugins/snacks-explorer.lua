return {
  "folke/snacks.nvim",
  opts = {
    explorer = {
      replace_netrw = true,
    },
    picker = {
      sources = {
        explorer = {
          hidden = true,
          ignored = true,
          filter = function(item)
            local name = item.name or item.file and vim.fn.fnamemodify(item.file, ":t")
            if not name then
              return true
            end
            return name ~= "node_modules" and name ~= ".direnv"
          end,
        },
      },
    },
  },
}
