-- ==========================================
-- VIRTUAL MACHINE
-- ==========================================
-- Loaded only inside a VM (see hyprland.lua).
-- Packages used here are installed by modules/06_virtualization.sh.

hl.on("hyprland.start", function()
    -- Clipboard sharing with the host (SPICE). Hyprland starts neither
    -- XDG autostart entries nor graphical-session.target, so start it here.
    hl.exec_cmd("spice-vdagent")
end)
