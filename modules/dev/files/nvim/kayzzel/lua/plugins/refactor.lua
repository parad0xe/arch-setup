return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
	"lewis6991/async.nvim",
  },
  lazy = false,

  keys = {
    { "<leader>re", mode = { "n", "x" }, desc = "Extract Function" },
    { "<leader>rE", mode = { "n", "x" }, desc = "Extract Function To File" },
    { "<leader>rv", mode = { "n", "x" }, desc = "Extract Variable" },
    { "<leader>ri", mode = { "n", "x" }, desc = "Inline Variable" },
    { "<leader>rI", mode = { "n" },      desc = "Inline Function" },
    { "<leader>rb", mode = { "n", "x" }, desc = "Extract Block" },
    { "<leader>rB", mode = { "n", "x" }, desc = "Extract Block To File" },
    { "<leader>rr", mode = { "n", "x" }, desc = "Select Refactor (Telescope)" },
    { "<leader>rp", mode = { "n" },      desc = "Debug: Printf above" },
    { "<leader>rP", mode = { "n" },      desc = "Debug: Printf below" },
    { "<leader>rd", mode = { "n", "x" }, desc = "Debug: Print Var" },
    { "<leader>rc", mode = { "n" },      desc = "Debug: Cleanup prints" },
  },

	config = function()
	  require("refactoring").setup({
		show_success_message = true,
		prompt_func_return_type = { go = true, cpp = true, c = true, java = true },
		prompt_func_param_type  = { go = true, cpp = true, c = true, java = true },
	  })

	  -- ── Refactoring ───────────────────────────────────────────────────────
	  vim.keymap.set({ "n", "x" }, "<leader>re",
		function() return require("refactoring").refactor("Extract Function") end,
		{ expr = true, desc = "Refactor: Extract Function" })

	  vim.keymap.set({ "n", "x" }, "<leader>rE",
		function() return require("refactoring").refactor("Extract Function To File") end,
		{ expr = true, desc = "Refactor: Extract Function To File" })

	  vim.keymap.set({ "n", "x" }, "<leader>rv",
		function() return require("refactoring").refactor("Extract Variable") end,
		{ expr = true, desc = "Refactor: Extract Variable" })

	  vim.keymap.set({ "n", "x" }, "<leader>ri",
		function() return require("refactoring").refactor("Inline Variable") end,
		{ expr = true, desc = "Refactor: Inline Variable" })

	  vim.keymap.set("n", "<leader>rI",
		function() return require("refactoring").refactor("Inline Function") end,
		{ expr = true, desc = "Refactor: Inline Function" })

	  vim.keymap.set({ "n", "x" }, "<leader>rb",
		function() return require("refactoring").refactor("Extract Block") end,
		{ expr = true, desc = "Refactor: Extract Block" })

	  vim.keymap.set({ "n", "x" }, "<leader>rB",
		function() return require("refactoring").refactor("Extract Block To File") end,
		{ expr = true, desc = "Refactor: Extract Block To File" })

	  -- ── Telescope picker ──────────────────────────────────────────────────
	  vim.keymap.set({ "n", "x" }, "<leader>rr", function()
		require("telescope").load_extension("refactoring")
		require("telescope").extensions.refactoring.refactors()
	  end, { desc = "Refactor: Select (Telescope)" })

	  -- ── Debug ─────────────────────────────────────────────────────────────
	  vim.keymap.set("n", "<leader>rp",
		function() require("refactoring").debug.printf({ below = false }) end,
		{ desc = "Debug: Printf (above)" })

	  vim.keymap.set("n", "<leader>rP",
		function() require("refactoring").debug.printf({ below = true }) end,
		{ desc = "Debug: Printf (below)" })

	  vim.keymap.set({ "n", "x" }, "<leader>rd",
		function() require("refactoring").debug.print_var() end,
		{ desc = "Debug: Print Var" })

	  vim.keymap.set("n", "<leader>rc",
		function() require("refactoring").debug.cleanup({}) end,
		{ desc = "Debug: Cleanup prints" })
	end,
}
