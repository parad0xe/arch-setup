require("conf.monitors")
-- require("conf.env")
require("conf.input")
require("conf.layerrules")
require("conf.visuals")
require("conf.autostart")
require("conf.keybinds")

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
