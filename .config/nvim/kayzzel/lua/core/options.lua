local opt = vim.opt
local hl = vim.api.nvim_set_hl

-- file
opt.swapfile = false
opt.undofile = true

-- lines
opt.number = true
opt.relativenumber = true
opt.cursorline = true

-- tabs & indent
opt.tabstop = 4
opt.shiftwidth = 4
opt.autoindent = true
opt.backspace = "indent,eol,start"

-- keep cursor centered vertically while scrolling
opt.scrolloff = 15

-- splits open in a more natural direction
vim.opt.splitright = true -- vertical splits open on the right
vim.opt.splitbelow = true -- horizontal splits open below
vim.opt.termguicolors = true

-- highlight yanked text for 150ms
vim.api.nvim_create_autocmd("TextYankPost", {
    callback = function()
        vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
    end,
})
-- vim.opt.laststatus = 0
hl(0, "StatusLine", { bg = "none" })
hl(0, "StatusLineNC", { bg = "none" })
hl(0, "CursorLine", { bg = "none" })
hl(0, "Visual",     { bg = "#6c4791", blend = 10 })

-- Use treesitter for folding
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldlevel = 99        -- open all folds by default
vim.opt.foldlevelstart = 99

vim.opt.fillchars = { fold = " " }

function _G.custom_foldtext()
  local start = vim.v.foldstart
  local line = vim.fn.getline(start)

  -- Get indentation
  local indent = vim.fn.indent(start)
  local indent_str = string.rep(" ", indent)

  -- Remove leading whitespace from content
  local content = line:gsub("^%s*", "")

  local lines_count = vim.v.foldend - start + 1

  return indent_str .. "󰁂 " .. content .. "  •  " .. lines_count .. " lines"
end

vim.opt.foldtext = "v:lua.custom_foldtext()"

-- lint

local ok, lint = pcall(require, "lint")
if ok then
    if vim.fn.executable("flake8") == 1 then
      lint.linters_by_ft.python = lint.linters_by_ft.python or {}
      table.insert(lint.linters_by_ft.python, "flake8")
    end

    if vim.fn.executable("mypy") == 1 then
      lint.linters_by_ft.python = lint.linters_by_ft.python or {}
      table.insert(lint.linters_by_ft.python, "mypy")

      local mypy = lint.linters.mypy
      mypy.args = vim.list_extend(
          mypy.args or {},
          {
		  "--cache-dir=/dev/null",
		  "--python-executable", get_python_path(),
		  "--strict"
	  }
      )
    end

    vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave", "BufReadPost", "BufNewFile" }, {
      callback = function()
        -- ne lancer lint que si le fichier a un linter configuré
        local ft = vim.bo.filetype
        if lint.linters_by_ft[ft] then
          lint.try_lint()
        end
      end,
    })

    vim.diagnostic.config({
      virtual_text = {
        prefix = "▎"--, "✖"
      },
      signs = true,
      underline = false,
      update_in_insert = false,
      severity_sort = true,
    })

    vim.api.nvim_set_hl(0, "DiagnosticError", { fg = "#ff5555" })
    vim.api.nvim_set_hl(0, "DiagnosticWarn",  { fg = "#ff5555" })
    -- vim.api.nvim_set_hl(0, "DiagnosticWarn",  { fg = "#f1fa8c" })

    vim.api.nvim_set_hl(0, "DiagnosticVirtualTextError", { fg = "#ff6c6b" })
    vim.api.nvim_set_hl(0, "DiagnosticVirtualTextWarn",  { fg = "#ff6c6b" })
    --vim.api.nvim_set_hl(0, "DiagnosticVirtualTextWarn",  { fg = "#ECBE7B" })
end
