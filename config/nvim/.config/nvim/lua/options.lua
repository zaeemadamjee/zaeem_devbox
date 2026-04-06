local opt = vim.opt

-- Line numbers: relative + absolute on current line
opt.number = true
opt.relativenumber = true

-- Indentation (formatters handle per-language specifics)
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = false

-- UI
opt.termguicolors = true
opt.signcolumn = "yes"   -- always show; prevents layout shift on LSP diagnostics
opt.cursorline = true
opt.scrolloff = 8        -- keep 8 lines visible above/below cursor
opt.wrap = true
opt.linebreak = true          -- wrap at word boundaries, not mid-word
opt.list = true               -- show invisible characters
opt.listchars = {
  tab      = "→ ",
  lead     = "·",
  trail    = "•",
  nbsp     = "␣",
  extends  = "›",
  precedes = "‹",
}

-- Split behavior
opt.splitbelow = true
opt.splitright = true

-- Clipboard: not set — this is a headless SSH VM with no X display.
-- tmux-yank handles clipboard integration via tmux (see tmux.conf).

-- No swap/backup files; use persistent undo instead
opt.swapfile = false
opt.backup = false
opt.undofile = true

-- Faster CursorHold events (used by gitsigns, LSP hover)
opt.updatetime = 250
