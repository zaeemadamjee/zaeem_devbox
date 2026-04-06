return {
  -- Mason: installs and manages LSP binaries
  {
    "williamboman/mason.nvim",
    config = true,
  },

  -- Auto-install servers via mason-lspconfig
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "pyright",       -- Python
          "gopls",         -- Go
          "ts_ls",         -- TypeScript / JavaScript
          "rust_analyzer", -- Rust
          "lua_ls",        -- Lua (for editing this config)
        },
        automatic_installation = true,
      })
    end,
  },

  -- LSP client configuration
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- Keymaps attached when LSP connects to a buffer
      local on_attach = function(_, bufnr)
        local map = function(keys, func, desc)
          vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
        end
        map("K",           vim.lsp.buf.hover,          "Hover docs")
        map("gd",          vim.lsp.buf.definition,     "Go to definition")
        map("gr",          vim.lsp.buf.references,     "Find references")
        map("gI",          vim.lsp.buf.implementation, "Go to implementation")
        map("<leader>rn",  vim.lsp.buf.rename,         "Rename symbol")
        map("<leader>ca",  vim.lsp.buf.code_action,    "Code action")
        map("[d",          vim.diagnostic.goto_prev,   "Prev diagnostic")
        map("]d",          vim.diagnostic.goto_next,   "Next diagnostic")
      end

      -- Configure each server with shared capabilities + on_attach (nvim 0.11 API)
      local servers = { "pyright", "gopls", "ts_ls", "rust_analyzer", "lua_ls" }
      for _, server in ipairs(servers) do
        vim.lsp.config(server, {
          capabilities = capabilities,
          on_attach    = on_attach,
        })
      end
      vim.lsp.enable(servers)

      -- Inline diagnostic virtual text
      vim.diagnostic.config({
        virtual_text     = true,
        signs            = true,
        underline        = true,
        update_in_insert = false,
      })
    end,
  },

  -- Autocomplete engine
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",  -- LSP completions
      "hrsh7th/cmp-buffer",    -- completions from open buffers
      "hrsh7th/cmp-path",      -- file path completions
      "L3MON4D3/LuaSnip",      -- snippet engine
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      local cmp     = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-n>"]     = cmp.mapping.select_next_item(),
          ["<C-p>"]     = cmp.mapping.select_prev_item(),
          ["<C-b>"]     = cmp.mapping.scroll_docs(-4),
          ["<C-f>"]     = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"]      = cmp.mapping.confirm({ select = true }),
          ["<Tab>"]     = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"]   = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },
}
