# Neovim Setup Design

**Date:** 2026-03-14
**Status:** Approved

## Summary

Add a hand-rolled Neovim config with lazy.nvim to the dotfiles repo. Covers LSP for Python, Go, TypeScript, Rust, and Lua; autocomplete; treesitter syntax highlighting; telescope fuzzy finder; file tree; Tokyo Night colorscheme; and auto-format on save. Config lives in `dotfiles/nvim/` and is symlinked by `bootstrap.sh`.

## Goals

- Full IDE-like experience in the terminal on the cloud VM
- LSP support for all primary languages (Python, Go, TS/JS, Rust)
- Reproducible: `lazy-lock.json` committed to git, language servers managed by Mason
- Minimal and debuggable: no distros, no magic, every plugin intentional
- Matches existing Tokyo Night tmux theme

## Repository Structure

```
dotfiles/
└── nvim/
    ├── init.lua               # entry point, bootstraps lazy.nvim
    ├── lazy-lock.json         # pinned plugin versions (committed to git)
    └── lua/
        ├── options.lua        # editor settings
        ├── keymaps.lua        # all custom keybindings
        └── plugins/
            ├── lsp.lua        # nvim-lspconfig + mason + cmp
            ├── treesitter.lua # syntax highlighting
            ├── telescope.lua  # fuzzy finder
            ├── ui.lua         # colorscheme, statusline, file tree
            └── editor.lua     # autopairs, comments, gitsigns, conform
```

`bootstrap.sh` addition:
```bash
ln -sf ~/zaeem_devbox/dotfiles/nvim ~/.config/nvim
```

`devbox.json` additions: `neovim@latest`, `fd@latest`

## Plugins

| Plugin | Purpose |
|---|---|
| `lazy.nvim` | Plugin manager |
| `nvim-lspconfig` | LSP client config |
| `mason.nvim` + `mason-lspconfig` | Install/manage language servers |
| `nvim-cmp` + sources | Autocomplete (LSP, buffer, path) |
| `nvim-treesitter` | Syntax highlighting + text objects |
| `telescope.nvim` + `fd` | Fuzzy find files, grep, git log |
| `neo-tree.nvim` | File explorer sidebar |
| `tokyonight.nvim` | Colorscheme (matches tmux theme) |
| `lualine.nvim` | Statusline |
| `gitsigns.nvim` | Git diff in gutter |
| `nvim-autopairs` | Auto-close brackets/quotes |
| `Comment.nvim` | `gcc` to toggle line comments |
| `conform.nvim` | Auto-format on save |

## LSP + Language Servers (Mason-managed)

| Language | Server | Formatter |
|---|---|---|
| Python | `pyright` | `black` |
| Go | `gopls` | `gofmt` |
| TypeScript/JS | `ts_ls` | `prettier` |
| Rust | `rust_analyzer` | `rustfmt` |
| Lua | `lua_ls` | `stylua` |

LSP key behaviors:
- Virtual text diagnostics inline
- `K` hover docs, `gd` go to definition, `gr` references
- `<leader>rn` rename, `<leader>ca` code action
- `[d` / `]d` jump between diagnostics
- Format on save via `conform.nvim`

## Key Bindings

`<leader>` = `Space`

| Binding | Action |
|---|---|
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `<leader>fb` | Browse buffers |
| `<leader>fh` | Help tags |
| `<leader>fr` | Recent files |
| `<leader>gc` | Git commits |
| `<leader>gs` | Git status |
| `<leader>e` | Toggle file explorer |
| `<leader>w` | Save file |
| `<leader>q` | Quit |

## Editor Settings

- Relative line numbers + absolute on current line
- 2-space indent default (formatters handle per-language specifics)
- `<Space>` as leader key
