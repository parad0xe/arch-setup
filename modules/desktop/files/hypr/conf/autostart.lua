-- ==========================================
-- AUTOSTART
-- ==========================================
hl.on("hyprland.start", function()
    hl.exec_cmd("killall waybar; waybar")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("~/.config/hypr/scripts/change-wall.sh")
    hl.exec_cmd("~/.config/hypr/scripts/system/clipboard.sh")
    hl.exec_cmd("~/.config/hypr/scripts/system/battery.sh")
    hl.exec_cmd("~/.config/hypr/scripts/system/monitor-hotplug.sh")
    hl.exec_cmd("~/.config/hypr/scripts/system/ssh-agent.sh")
end)
