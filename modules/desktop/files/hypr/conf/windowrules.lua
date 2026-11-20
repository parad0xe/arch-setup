-- ==========================================
-- WINDOW RULES
-- ==========================================
-- The Wi-Fi, Bluetooth, sound and equalizer managers (wlctl, bluetui,
-- wiremix, eqtui), opened by the wifi, bluetooth, sound and eq scripts in
-- Ghostty windows of their own class (ghostty --class=ghostty.wlctl,
-- ghostty.bluetui, ghostty.wiremix, ghostty.eqtui), float in the middle of
-- the screen.
hl.window_rule({
    name   = "connectivity_float",
    match  = { class = "^ghostty\\.(wlctl|bluetui|wiremix|eqtui)$" },
    float  = true,
    size   = "1200 800",
    center = true,
})

-- The music player (rmpc), opened by scripts/system/music.sh in a Ghostty
-- window of its own class, floats centered like the connectivity managers.
hl.window_rule({
    name   = "music_float",
    match  = { class = "^ghostty\\.rmpc$" },
    float  = true,
    size   = "1200 800",
    center = true,
})
