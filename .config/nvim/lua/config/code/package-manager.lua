
-- https://github.com/mason-org/mason.nvim
local mason_ok, mason = pcall(require, "mason")
if mason_ok then
    mason.setup()
end

local mason_tool_installer_ok, tool_installer = pcall(require, "mason-tool-installer")
if mason_tool_installer_ok then
    tool_installer.setup({
        ensure_installed = { "pyright", "yapf", "ruff", "flake8", "mypy" },
        auto_update = false,
        run_on_start = true
    })
end
