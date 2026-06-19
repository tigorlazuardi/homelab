return {
  "folke/noice.nvim",
  opts = {
    routes = {
      {
        filter = {
          event = "notify",
          min_height = 15,
        },
        view = "split",
      },
    },
  },
}
