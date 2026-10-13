-- ==========================================
-- HYPRLAND KEYBINDINGS
-- ==========================================

local terminal = "ghostty"
local mainMod  = "SUPER"

-- --- APPLICATIONS ---
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + W",      hl.dsp.exec_cmd("brave"))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd("thunar"))
hl.bind(mainMod .. " + L",      hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + Escape", hl.dsp.exit())
hl.bind("CTRL + Space",         hl.dsp.exec_cmd("~/.config/hypr/scripts/wall-selector.sh"))
hl.bind("CTRL + SHIFT + Space", hl.dsp.exec_cmd("wofi --show drun --no-actions"))
hl.bind(mainMod .. " + Space",  hl.dsp.exec_cmd("wofi --show drun --no-actions"))
hl.bind(mainMod .. " + P",      hl.dsp.exec_cmd("wofi --show run"))

-- --- WINDOW MANAGEMENT ---
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))

hl.bind("ALT + Shift_L", hl.dsp.exec_cmd("hyprctl switchxkblayout current next"))
hl.bind("SUPER + Print", hl.dsp.exec_cmd([[sh -c 'grim -g "$(slurp)" - | tee ~/Pictures/capture_$(date +"%Y-%m-%d_%H-%M-%S").png | wl-copy']]))

-- --- FOCUS (ALT + Arrows) ---
hl.bind("ALT + left",  hl.dsp.focus({ direction = "left" }))
hl.bind("ALT + right", hl.dsp.focus({ direction = "right" }))
hl.bind("ALT + up",    hl.dsp.focus({ direction = "up" }))
hl.bind("ALT + down",  hl.dsp.focus({ direction = "down" }))

-- --- RESIZE WINDOWS (CTRL + SHIFT + Arrows) ---
hl.bind("CTRL + SHIFT + left",  hl.dsp.window.resize({ x = -30, y = 0,   relative = true }), { repeating = true })
hl.bind("CTRL + SHIFT + right", hl.dsp.window.resize({ x = 30,  y = 0,   relative = true }), { repeating = true })
hl.bind("CTRL + SHIFT + up",    hl.dsp.window.resize({ x = 0,   y = -30, relative = true }), { repeating = true })
hl.bind("CTRL + SHIFT + down",  hl.dsp.window.resize({ x = 0,   y = 30,  relative = true }), { repeating = true })

-- --- WORKSPACES ---
-- Switch workspaces with mainMod + [1-4]
-- Move active window to a workspace with mainMod + SHIFT + [1-4]
for i = 1, 4 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Scroll through workspaces
hl.bind(mainMod .. " + left",  hl.dsp.focus({ workspace = "-1" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ workspace = "+1" }))

-- --- SWAP WINDOWS (CTRL + ALT + Arrows) ---
hl.bind("CTRL + ALT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind("CTRL + ALT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind("CTRL + ALT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind("CTRL + ALT + down",  hl.dsp.window.move({ direction = "down" }))

-- --- PRESELECT (Visual notifications) ---
local function preselect(direction, message)
    return function()
        hl.dispatch(hl.dsp.layout("preselect " .. direction))
        hl.exec_cmd('notify-send -t 1200 -h string:x-canonical-private-synchronous:preselect "' .. message .. '"')
    end
end

hl.bind(mainMod .. " + SHIFT + right", preselect("r", "◨  Next window right"))
hl.bind(mainMod .. " + SHIFT + left",  preselect("l", "◧  Next window left"))
hl.bind(mainMod .. " + SHIFT + up",    preselect("u", "⬒  Next window up"))
hl.bind(mainMod .. " + SHIFT + down",  preselect("d", "⬓  Next window down"))

-- Cancel preselect (closes the notification instantly)
hl.bind(mainMod .. " + SHIFT + Space", function()
    hl.dispatch(hl.dsp.layout("preselect cancel"))
    hl.exec_cmd("makoctl dismiss")
end)

-- hl.bind(mainMod .. " + SHIFT + right", hl.dsp.layout("preselect r"))
-- hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.layout("preselect l"))
-- hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.layout("preselect u"))
-- hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.layout("preselect d"))
-- hl.bind(mainMod .. " + SHIFT + Space", hl.dsp.layout("preselect cancel"))

-- --- MULTIMEDIA KEYS ---
-- Volume
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/system/volume.sh up"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/system/volume.sh down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("~/.config/hypr/scripts/system/volume.sh mute"), { locked = true })

hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })

hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("~/.config/hypr/scripts/system/brightness.sh up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/hypr/scripts/system/brightness.sh down"), { locked = true, repeating = true })

-- --- SYSTEM MENUS ---
-- Wifi
hl.bind("SUPER + N", hl.dsp.exec_cmd("~/.config/hypr/scripts/system/wifi.sh"))
