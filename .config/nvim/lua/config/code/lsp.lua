
-- https://github.com/neovim/nvim-lspconfig
local mason_lsp_ok, mason_lspconfig = pcall(require, "mason-lspconfig")
if mason_lsp_ok then
    mason_lspconfig.setup({
		ensure_installed = { "clangd" },
	})
end

if vim.fn.executable('pyright') == 1 then
	vim.lsp.config('pyright', {
		on_init = function(client)
			client.config.settings.python.pythonPath = get_python_path()
		end,
		settings = {
			python = {
				analysis = {
					diagnosticMode = "workspace",
					typeCheckingMode = "basic",
					autoSearchPaths = true,
					useLibraryCodeForTypes = true,
				}
			},
		},
	})
end

if vim.fn.executable('clangd') == 1 then
	local function get_dynamic_c_flags()
		local flags = { "-xc" }
		local root_dir = vim.fn.getcwd()
		
		local h_files = vim.fn.globpath(root_dir, '**/*.h', false, true)
		local seen_dirs = {}
		
		for _, file in ipairs(h_files) do
			local dir = vim.fn.fnamemodify(file, ':h')
			if not seen_dirs[dir] then
				table.insert(flags, "-I" .. dir)
				seen_dirs[dir] = true
			end
		end
		
		return flags
	end

	vim.lsp.config('clangd', {
		init_options = {
			fallbackFlags = get_dynamic_c_flags()
		},
		on_attach = function(client, bufnr)
			client.server_capabilities.documentFormattingProvider = false
			client.server_capabilities.documentRangeFormattingProvider = false
		end,
	})
end
