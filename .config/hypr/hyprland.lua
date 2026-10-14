-- Loads the variant of a choice picked at setup (its selected.lua link, see
-- choose_variant in modules/core.sh), or its default variant when none was
-- picked.
local function require_choice(name)
    if package.searchpath(name .. ".selected", package.path) then
        require(name .. ".selected")
    else
        require(name .. ".default")
    end
end

require("conf.monitors")
require("conf.input")
require_choice("conf.keyboard")
require("conf.layerrules")
require("conf.visuals")
require("conf.autostart")
require_choice("conf.keybinds")

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
