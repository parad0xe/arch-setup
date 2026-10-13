-- ==========================================
-- VISUALS & ANIMATIONS
-- ==========================================

-- Cursor theme (installed by modules/03_graphical.sh)
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        background_color        = "rgb(11111b)",
    },

    general = {
        gaps_in     = 3,
        gaps_out    = 8,
        border_size = 1,
        col = {
            active_border   = "rgba(89b4faff)",
            inactive_border = "rgba(1e1e2eaa)",
        },
        layout = "dwindle",
    },

    group = {
        col = {
            border_active   = "rgba(89b4faff)",
            border_inactive = "rgba(1e1e2eaa)",
        },
    },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
    },

    decoration = {
        rounding = 10,
        blur = {
            enabled           = true,
            size              = 3,
            passes            = 1,
            new_optimizations = true,
            ignore_opacity    = true,
        },
    },

    animations = {
        enabled = true,
    },
})

hl.curve("myBezier", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 7,  bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7,  bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border",     enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6,  bezier = "default" })
