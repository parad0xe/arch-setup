hl.layer_rule({
    name         = "mako_blur",
    match        = { namespace = "notifications" },
    blur         = true,
    ignore_alpha = 0,
})

hl.layer_rule({
    name         = "wofi_blur",
    match        = { namespace = "wofi" },
    blur         = true,
    ignore_alpha = 0,
})
