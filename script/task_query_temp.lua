require "sys"
require "misc"

CPU_TEMP = "-99"

-- 模块温度返回回调函数
-- @temp: srting类型，如果要对该值进行运算，可以使用带float的固件将该值转为number
local function getTemperatureCb(temp)
    if temp ~= nil then
        CPU_TEMP = temp:gsub("%s+", "")
    end
end

-- 开机后延迟几秒查询模块温度
sys.timerStart(
    function()
        misc.getTemperature(getTemperatureCb)
    end,
    1000 * 5
)
-- 循环查询模块温度
sys.timerLoopStart(misc.getTemperature, 1000 * 30, getTemperatureCb)
