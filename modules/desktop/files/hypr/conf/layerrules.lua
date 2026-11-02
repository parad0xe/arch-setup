hl.layer_rule({
    name         = "mako_blur",
    match        = { namespace = "notifications" },
    blur         = true,
    ignore_alpha = 0,
})

hl.layer_rule({
    name         = "rofi_blur",
    match        = { namespace = "rofi" },
    blur         = true,
    ignore_alpha = 0,
})

-- Blurs only the pills (the bar between them is transparent), for the glass
-- Waybar theme
hl.layer_rule({
    name         = "waybar_blur",
    match        = { namespace = "waybar" },
    blur         = true,
    ignore_alpha = 0.2,
})
