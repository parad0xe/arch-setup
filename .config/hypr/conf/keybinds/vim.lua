-- ==========================================
-- HYPRLAND KEYBINDINGS
-- ==========================================
-- Ported from skhd + yabai config with multi-monitor support
-- mainMod = SUPER  |  navigation uses ALT (like skhd alt)

local terminal = "ghostty"
local mainMod  = "SUPER"

-- ==========================================
-- APPLICATIONS
-- ==========================================
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + W",      hl.dsp.exec_cmd("brave"))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd("thunar"))
hl.bind(mainMod .. " + L",      hl.dsp.exec_cmd("~/.config/hypr/scripts/lock.sh"))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("~/.config/hypr/scripts/logout.sh"))
hl.bind("CTRL + Space",         hl.dsp.exec_cmd("~/.config/hypr/scripts/wall-selector.sh"))
hl.bind("CTRL + SHIFT + Space", hl.dsp.exec_cmd("wofi --show drun --no-actions"))
hl.bind(mainMod .. " + Space",  hl.dsp.exec_cmd("wofi --show drun --no-actions"))
hl.bind(mainMod .. " + P",      hl.dsp.exec_cmd("wofi --show run"))

-- Cycle focus between floating windows
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())

-- Screenshot
hl.bind(mainMod .. " + S",         hl.dsp.exec_cmd([[mkdir -p ~/Pictures/screenshot && grim - | tee ~/Pictures/screenshot/screenshot-$(date +%Y%m%d-%H%M%S).png | wl-copy]]))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd([[mkdir -p ~/Pictures/screenshot && grim -g "$(slurp)" - | tee ~/Pictures/screenshot/screenshot-$(date +%Y%m%d-%H%M%S).png | wl-copy]]))
hl.bind(mainMod .. " + CTRL + S",  hl.dsp.exec_cmd([[mkdir -p ~/Pictures/screenshot && grim -g "$(slurp)" - | satty --filename - --output-filename ~/Pictures/screenshot/screenshot-$(date +%Y%m%d-%H%M%S).png]]))

-- ==========================================
-- WINDOW MANAGEMENT
-- ==========================================
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind("SHIFT + ALT + M", hl.dsp.window.fullscreen())
hl.bind("SHIFT + ALT + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SHIFT + ALT + E", hl.dsp.layout("orientationnext"))

-- Rotate / mirror layout  (skhd: shift+alt-r / y / x)
hl.bind("SHIFT + ALT + R", hl.dsp.layout("orientationnext"))
hl.bind("SHIFT + ALT + Y", hl.dsp.layout("swapsplit"))
hl.bind("SHIFT + ALT + X", hl.dsp.layout("orientationcycle"))

-- ==========================================
-- WINDOW FOCUS  (skhd: alt - h/j/k/l)
-- ==========================================
hl.bind("ALT + H", hl.dsp.focus({ direction = "left" }))
hl.bind("ALT + J", hl.dsp.focus({ direction = "down" }))
hl.bind("ALT + K", hl.dsp.focus({ direction = "up" }))
hl.bind("ALT + L", hl.dsp.focus({ direction = "right" }))

-- ==========================================
-- FOCUS BETWEEN DISPLAYS  (skhd: alt - s/d/f/g)
-- ==========================================
hl.bind("ALT + S", hl.dsp.focus({ monitor = "-1" }))
hl.bind("ALT + D", hl.dsp.focus({ monitor = "+1" }))

-- ==========================================
-- SWAP WINDOWS  (skhd: shift+alt - h/j/k/l)
-- ==========================================
hl.bind("SHIFT + ALT + H", hl.dsp.window.swap({ direction = "left" }))
hl.bind("SHIFT + ALT + J", hl.dsp.window.swap({ direction = "down" }))
hl.bind("SHIFT + ALT + K", hl.dsp.window.swap({ direction = "up" }))
hl.bind("SHIFT + ALT + L", hl.dsp.window.swap({ direction = "right" }))

-- ==========================================
-- WARP / MOVE WINDOWS  (skhd: ctrl+alt - h/j/k/l)
-- ==========================================
hl.bind("CTRL + ALT + H", hl.dsp.window.move({ direction = "left" }))
hl.bind("CTRL + ALT + J", hl.dsp.window.move({ direction = "down" }))
hl.bind("CTRL + ALT + K", hl.dsp.window.move({ direction = "up" }))
hl.bind("CTRL + ALT + L", hl.dsp.window.move({ direction = "right" }))

-- ==========================================
-- RESIZE WINDOWS  (skhd: ctrl+shift - h/j/k/l)
-- ==========================================
hl.bind("CTRL + SHIFT + ALT + H", hl.dsp.window.resize({ x = -30, y = 0,   relative = true }), { repeating = true })
hl.bind("CTRL + SHIFT + ALT + J", hl.dsp.window.resize({ x = 0,   y = 30,  relative = true }), { repeating = true })
hl.bind("CTRL + SHIFT + ALT + K", hl.dsp.window.resize({ x = 0,   y = -30, relative = true }), { repeating = true })
hl.bind("CTRL + SHIFT + ALT + L", hl.dsp.window.resize({ x = 30,  y = 0,   relative = true }), { repeating = true })

-- ==========================================
-- MOVE FLOATING WINDOW (keyboard)
-- ==========================================
hl.bind(mainMod .. " + ALT + H", hl.dsp.window.move({ x = -30, y = 0,   relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + J", hl.dsp.window.move({ x = 0,   y = 30,  relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + K", hl.dsp.window.move({ x = 0,   y = -30, relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + L", hl.dsp.window.move({ x = 30,  y = 0,   relative = true }), { repeating = true })

-- ==========================================
-- MOVE WINDOW TO DISPLAY  (skhd: shift+alt - s/g)
-- ==========================================
hl.bind("SHIFT + ALT + S", hl.dsp.window.move({ monitor = "-1" }))
hl.bind("SHIFT + ALT + D", hl.dsp.window.move({ monitor = "+1" }))

-- ==========================================
-- CROSS-MONITOR WORKSPACE / WINDOW MOVES
-- ==========================================

-- Move entire current workspace to the other monitor
hl.bind("CTRL + SHIFT + S", hl.dsp.workspace.move({ monitor = "-1" }))
hl.bind("CTRL + SHIFT + D", hl.dsp.workspace.move({ monitor = "+1" }))

-- Move focused window to new empty workspace on the other monitor
local function move_to_empty_workspace_on(monitor)
    return function()
        hl.dispatch(hl.dsp.window.move({ monitor = monitor }))
        hl.dispatch(hl.dsp.window.move({ workspace = "emptynm" }))
    end
end

hl.bind("CTRL + ALT + S", move_to_empty_workspace_on("-1"))
hl.bind("CTRL + ALT + D", move_to_empty_workspace_on("+1"))

-- ==========================================
-- WORKSPACES — NAVIGATE (same monitor, vim motions)
-- ==========================================
hl.bind("CTRL + H", hl.dsp.focus({ workspace = "m-1" }))
hl.bind("CTRL + L", hl.dsp.focus({ workspace = "m+1" }))

-- ==========================================
-- WORKSPACES — MOVE WINDOW + FOLLOW (same monitor)
-- ==========================================
hl.bind("CTRL + SHIFT + H", hl.dsp.window.move({ workspace = "m-1" }))
hl.bind("CTRL + SHIFT + L", hl.dsp.window.move({ workspace = "m+1" }))

-- ==========================================
-- DYNAMIC WORKSPACES
-- ==========================================

-- Create and move to a new empty workspace on the current monitor
hl.bind("CTRL + N", hl.dsp.focus({ workspace = "emptynm" }))

-- Move focused window to a new empty workspace on the current monitor
hl.bind("CTRL + SHIFT + N", hl.dsp.window.move({ workspace = "emptynm" }))

-- ==========================================
-- WORKSPACES — SWITCH BY NUMBER
-- CTRL + 1-0 to switch, CTRL + SHIFT + 1-0 to move the window (0 = 10)
-- 1-5: laptop screen  |  6-10: external screen
-- ==========================================
for i = 1, 10 do
    local key = i % 10
    hl.bind("CTRL + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind("CTRL + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- ==========================================
-- PRESELECT SPLIT DIRECTION
-- ==========================================
local function preselect(direction, message)
    return function()
        hl.dispatch(hl.dsp.layout("preselect " .. direction))
        hl.exec_cmd('notify-send -t 1200 -h string:x-canonical-private-synchronous:preselect "' .. message .. '"')
    end
end

hl.bind(mainMod .. " + SHIFT + L", preselect("r", "▐  Next window right"))
hl.bind(mainMod .. " + SHIFT + H", preselect("l", "▌  Next window left"))
hl.bind(mainMod .. " + SHIFT + K", preselect("u", "▀  Next window up"))
hl.bind(mainMod .. " + SHIFT + J", preselect("d", "▄  Next window down"))

hl.bind(mainMod .. " + SHIFT + Space", function()
    hl.dispatch(hl.dsp.layout("preselect cancel"))
    hl.exec_cmd("makoctl dismiss")
end)

-- ==========================================
-- MULTIMEDIA KEYS
-- ==========================================
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/system/volume.sh up"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/system/volume.sh down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("~/.config/hypr/scripts/system/volume.sh mute"), { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),  { locked = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"),                          { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),                                { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),                            { locked = true })

hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("~/.config/hypr/scripts/system/brightness.sh up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/hypr/scripts/system/brightness.sh down"), { locked = true, repeating = true })

-- ==========================================
-- SYSTEM MENUS
-- ==========================================
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("~/.config/hypr/scripts/system/wifi.sh"))

-- ==========================================
-- MOUSE — move & resize floating windows
-- ==========================================
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
