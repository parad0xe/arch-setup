-- ==========================================
-- WINDOW RULES
-- ==========================================
-- The Wi-Fi and Bluetooth managers (wlctl, bluetui), opened by the wifi and
-- bluetooth scripts in Ghostty windows of their own class (ghostty
-- --class=ghostty.wlctl, ghostty.bluetui), float in the middle of the screen.
hl.window_rule({
    name   = "connectivity_float",
    match  = { class = "^ghostty\\.(wlctl|bluetui)$" },
    float  = true,
    size   = "1100 700",
    center = true,
})
