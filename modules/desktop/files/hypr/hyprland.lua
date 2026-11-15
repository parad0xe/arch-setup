-- keyboard.lua and keybinds.lua are the variants picked at setup, deployed
-- next to this file (the versions are in conf/keyboard/ and conf/keybinds/)
require("conf.monitors")
require("conf.input")
require("keyboard")
require("conf.layerrules")
require("conf.windowrules")
require("conf.visuals")
require("conf.autostart")
require("keybinds")

-- ~/.cargo/bin holds the tools built from source by the setup hooks
-- (eqtui). SDDM does not source the shell rc files, so the Hyprland session
-- would not have it in PATH; add it for everything Hyprland launches.
hl.env("PATH", (os.getenv("PATH") or "/usr/local/bin:/usr/bin") .. ":" .. (os.getenv("HOME") or "") .. "/.cargo/bin")

local function in_vm()
    local f = io.open("/proc/cpuinfo", "r")
    if not f then
        return false
    end
    local cpuinfo = f:read("a")
    f:close()
    return cpuinfo:find("%f[%w]hypervisor%f[%W]") ~= nil
end

if in_vm() then
    require("conf.vm")
end
