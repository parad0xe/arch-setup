-- ==========================================
-- VISUALS & ANIMATIONS
-- ==========================================

-- Cursor theme (installed by the desktop.cursor block, modules/desktop.sh)
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "20")

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        background_color        = "rgb(11111b)",
    },

    general = {
        gaps_in     = 3,
        gaps_out    = 18,
        border_size = 1,                                  -- was 1
        col = {
            active_border   = "rgba(6a0dadff)",
            inactive_border = "rgba(666666ff)",
        },
        layout = "dwindle",
    },

    group = {
        col = {
            border_active   = "rgba(6a0dadff)",
            border_inactive = "rgba(666666ff)",
        },
    },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
    },

    decoration = {
        rounding         = 0,
        inactive_opacity = 0.77,                           -- new: dims unfocused windows
        blur = {
            enabled           = true,
            size              = 5,                          -- was 3
            passes            = 2,                          -- was 1
            new_optimizations = true,
            ignore_opacity    = true,
            popups            = true,                        -- new: blurred app menus
        },
        shadow = {
            enabled        = true,                          -- new block
            range          = 25,
            render_power   = 3,
            color          = "rgba(11111bff)",
            color_inactive = "rgba(11111b44)",              -- inactive = weaker shadow
        },
    },
})

hl.curve("myBezier", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("smoothSpring", { type = "spring", mass = 1, stiffness = 200, damping = 25 })

hl.animation({ leaf = "windows", enabled = true, speed = 7, spring = "smoothSpring" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7,  bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border",     enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6,  bezier = "default" })
