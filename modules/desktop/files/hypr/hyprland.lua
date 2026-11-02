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
