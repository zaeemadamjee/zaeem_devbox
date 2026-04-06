return {
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install({
        "lua", "python", "go", "typescript", "javascript",
        "tsx", "rust", "json", "yaml", "toml", "bash", "markdown",
      })
    end,
  },
}
