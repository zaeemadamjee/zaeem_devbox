return {
  -- Auto-close brackets, quotes, parens
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = true,
  },

  -- gcc to toggle line comment, gc in visual mode
  {
    "numToStr/Comment.nvim",
    event = "VeryLazy",
    config = true,
  },

  -- Git diff indicators in the sign column
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("gitsigns").setup({
        signs = {
          add          = { text = "▎" },
          change       = { text = "▎" },
          delete       = { text = "" },
          topdelete    = { text = "" },
          changedelete = { text = "▎" },
        },
      })
    end,
  },

  -- Auto-format on save via external formatters
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          python              = { "black" },
          go                  = { "gofmt" },
          javascript          = { "prettier" },
          typescript          = { "prettier" },
          javascriptreact     = { "prettier" },
          typescriptreact     = { "prettier" },
          json                = { "prettier" },
          lua                 = { "stylua" },
          rust                = { "rustfmt" },
        },
        format_on_save = {
          timeout_ms = 500,
          lsp_format = "fallback",
        },
      })
    end,
  },
}
