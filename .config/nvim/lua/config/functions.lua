
local opts = { noremap = true, silent = true }
function keymap(mode, keybind, command, extended_opts)
    extended_opts = extended_opts or {}
    local final_opts = vim.tbl_extend("force", opts, extended_opts)
    vim.keymap.set(mode, keybind, command, final_opts)
end

local python_path_cache = nil
function get_python_path()
	if python_path_cache then return python_path_cache end

	local cwd = vim.fn.getcwd()

	local is_python_project = vim.fn.glob(cwd .. "/**/*.py") ~= "" 
        or vim.fn.filereadable(cwd .. "/pyproject.toml") == 1 
        or vim.fn.filereadable(cwd .. "/requirements.txt") == 1
        or vim.fn.filereadable(cwd .. "/poetry.lock") == 1

    if not is_python_project then
        return vim.fn.exepath("python3") or vim.fn.exepath("python") or "python3"
    end

	local detected_path = nil
    local method = ""
    
	local venv_names = { ".venv", "venv", "env" }
    local bin_dir = (vim.fn.has("win32") == 1) and "/Scripts/python.exe" or "/bin/python"
    for _, name in ipairs(venv_names) do
        local venv_py = cwd .. "/" .. name .. bin_dir
        if vim.fn.executable(venv_py) == 1 then
			detected_path = venv_py
			method = "local " .. name
			break
        end
    end

	if not detected_path then
		if vim.fn.filereadable(cwd .. "/pyproject.toml") == 1 then
			local poetry_venv = vim.fn.trim(vim.fn.system("poetry env info -p 2>/dev/null"))
			if vim.v.shell_error == 0 and poetry_venv ~= "" then
				local bin = (vim.fn.has("win32") == 1) and "/Scripts/python.exe" or "/bin/python"
				detected_path = poetry_venv .. bin
				method = "poetry"
			end
		end
	end

	if not detected_path then
        detected_path = vim.fn.exepath("python3") or vim.fn.exepath("python") or "python3"
        method = "system"
    end

	vim.defer_fn(function()
        vim.api.nvim_echo({
            { "Python env loaded: ", "Identifier" },
            { method, "Character" },
            { " -> " .. detected_path, "Comment" }
        }, true, {})

        vim.defer_fn(function()
            vim.api.nvim_echo({}, false, {})
        end, 3500)
    end, 200)

	python_path_cache = detected_path
    return python_path_cache
end

function editor_focus()
    vim.schedule(function()
        local win_type = vim.bo.filetype
        if win_type == "NvimTree" then
            vim.cmd("wincmd l")
        end
    end)
end
