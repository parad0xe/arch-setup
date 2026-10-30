return {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	dependencies = { "nvim-lua/plenary.nvim" },
	config = function()
		local harpoon = require("harpoon")
		harpoon:setup()

		for i = 1, 9 do
			-- Add current buffer to slot i
			vim.keymap.set("n", "<leader>a" .. i, function()
				local list = harpoon:list()
				local bufname = vim.api.nvim_buf_get_name(0)
				if bufname == "" then
					vim.notify("Harpoon: no file in current buffer", vim.log.levels.WARN)
					return
				end
				local item = { value = bufname, context = { row = vim.fn.line("."), col = vim.fn.col(".") } }
				if list.items[i] then
					list.items[i] = item
				else
					for j = #list.items + 1, i do
						list.items[j] = { value = "", context = { row = 1, col = 0 } }
					end
					list.items[i] = item
				end
				harpoon:sync()
				vim.notify("Harpoon: added to slot " .. i, vim.log.levels.INFO)
			end, { desc = "Harpoon: add to slot " .. i })

			-- Delete slot i
			vim.keymap.set("n", "<leader>d" .. i, function()
				local list = harpoon:list()
				if list.items[i] then
					list:remove_at(i)
					vim.notify("Harpoon: removed slot " .. i, vim.log.levels.INFO)
				else
					vim.notify("Harpoon: slot " .. i .. " is empty", vim.log.levels.WARN)
				end
			end, { desc = "Harpoon: delete slot " .. i })

			-- Jump to slot i
			vim.keymap.set("n", "<leader>" .. i, function()
				harpoon:list():select(i)
			end, { desc = "Harpoon: jump to slot " .. i })
		end

		-- Append current buffer (no specific slot)
		vim.keymap.set("n", "<leader>a", function()
			harpoon:list():add()
		end, { desc = "Harpoon: append" })

		-- Clear all slots
		vim.keymap.set("n", "<leader>D", function()
			harpoon:list():clear()
			vim.notify("Harpoon list cleared", vim.log.levels.INFO)
		end, { desc = "Harpoon: clear all" })

		-- Open harpoon saved files in telescope
		local conf = require("telescope.config").values
		local function toggle_telescope(harpoon_files)
			local file_paths = {}
			for _, item in ipairs(harpoon_files.items) do
				table.insert(file_paths, item.value)
			end
			require("telescope.pickers").new({}, {
				prompt_title = "Harpoon",
				finder = require("telescope.finders").new_table({
					results = file_paths,
					entry_maker = function(entry)
						local index = nil
						for i, item in ipairs(harpoon_files.items) do
							if item.value == entry then
								index = i
								break
							end
						end
						return {
							value = entry,
							display = index .. ": " .. entry,
							ordinal = entry,
						}
					end,
				}),
				previewer = conf.file_previewer({}),
				sorter = conf.generic_sorter({}),
			}):find()
		end
		vim.keymap.set("n", "<C-e>", function() toggle_telescope(harpoon:list()) end,
			{ desc = "Open harpoon window" })
	end,
}
