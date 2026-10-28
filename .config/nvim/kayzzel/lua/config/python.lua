-- =============================================================
-- Shared: detect the python interpreter of the current project.
-- Used by lua/plugins/lint.lua (mypy) and lua/plugins/lsp.lua
-- (pyright) so both lint and complete against the right venv.
-- Result is cached for the whole Neovim session.
-- =============================================================
local M = {}

local python_path_cache = nil

function M.get_python_path()
	if python_path_cache then
		return python_path_cache
	end

	local cwd = vim.fn.getcwd()

	-- Not a python project? System python is fine.
	local is_python_project = vim.fn.glob(cwd .. "/**/*.py") ~= ""
		or vim.fn.filereadable(cwd .. "/pyproject.toml") == 1
		or vim.fn.filereadable(cwd .. "/requirements.txt") == 1
		or vim.fn.filereadable(cwd .. "/poetry.lock") == 1

	if not is_python_project then
		python_path_cache = vim.fn.exepath("python3") or vim.fn.exepath("python") or "python3"
		return python_path_cache
	end

	-- Look for a local venv in the usual places.
	local bin = "/bin/python" -- (windows would use /Scripts/python.exe)
	for _, name in ipairs({ ".venv", "venv", "env" }) do
		local venv_py = cwd .. "/" .. name .. bin
		if vim.fn.executable(venv_py) == 1 then
			python_path_cache = venv_py
			return python_path_cache
		end
	end

	-- No venv dir, but a poetry project? Ask poetry itself.
	if vim.fn.filereadable(cwd .. "/pyproject.toml") == 1 then
		local poetry_venv = vim.fn.trim(vim.fn.system("poetry env info -p 2>/dev/null"))
		if vim.v.shell_error == 0 and poetry_venv ~= "" then
			python_path_cache = poetry_venv .. bin
			return python_path_cache
		end
	end

	-- Fall back to system python.
	python_path_cache = vim.fn.exepath("python3") or vim.fn.exepath("python") or "python3"
	return python_path_cache
end

return M
