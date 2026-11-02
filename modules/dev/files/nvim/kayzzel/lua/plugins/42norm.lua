return {
    "MoulatiMehdi/42norm.nvim",
	enabled = false,

	opts = {
		user = "gabach",
		mail = "gabach@student.42lyon.fr",
	},

    config = function()
        local norm = require("42norm")

        norm.setup({
            header_on_save = true,
            format_on_save = true,
            liner_on_change = true,
        })

        -- Press "F5" key to run the norminette
        vim.keymap.set("n", "<space>nr", function()
            norm.check_norms()
        end, { desc = "Update 42norms diagnostics", noremap = true, silent = true })

        vim.keymap.set("n", "<space>nf", function()
            norm.format()
        end, { desc = "Format buffer on 42norms", noremap = true, silent = true })

        -- create your commands
        vim.api.nvim_create_user_command("Norminette", function()
            norm.check_norms()
        end, {})
        vim.api.nvim_create_user_command("Format", function()
            norm.format()
        end, {})
    end,
}
