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
