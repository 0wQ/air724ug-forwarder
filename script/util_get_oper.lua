require "net"
module(..., package.seeall)

function get(is_zh)
    local mcc = net.getMcc()
    local mnc = net.getMnc()

    if mcc ~= "460" then
        return ""
    end

    -- 联通
    if mnc == "1" then
        return is_zh and "中国联通" or "CU"
    end

    -- 移动
    if mnc == "0" then
        return is_zh and "中国移动" or "CM"
    end

    -- 电信
    if mnc == "11" then
        return is_zh and "中国电信" or "CT"
    end

    return ""
end
