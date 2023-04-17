module(..., package.seeall)

local temperature = "-99"

-- 模块温度返回回调函数
-- @temperature: srting类型，如果要对该值进行运算，可以使用带float的固件将该值转为number
local function getTemperatureCb(_temperature)
    if _temperature ~= nil then
        temperature = _temperature:gsub("%s+", "")
    end
end

function get()
    -- 获取模块温度
    misc.getTemperature(getTemperatureCb)
    return temperature
end

get()
