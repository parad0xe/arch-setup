-- https://github.com/hardyrafael17/norminette42.nvim
local norminette_ok, norminette = pcall(require, "norminette")

if norminette_ok then
    norminette.setup({
		runOnSave = true,
		maxErrorsToShow = 10,
		active = true
	})
end


