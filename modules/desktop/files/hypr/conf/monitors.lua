-- ==========================================
-- MONITORS
-- ==========================================
-- Auto-detect monitors and set them to their preferred resolution
-- hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.monitor({ output = "eDP-1",    mode = "preferred", position = "0x0",     scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto-up", scale = 1 })

-- Layout saved by hyprmon, outside the dotfiles (see the hyprmon alias in
-- .config/zshrc/default.zsh). Its rules come last, so they override the
-- ones above.
local hyprmon_layout = os.getenv("HOME") .. "/.config/hyprmon/hyprmon.lua"
local f = io.open(hyprmon_layout, "r")
if f then
    f:close()
    dofile(hyprmon_layout)
end
