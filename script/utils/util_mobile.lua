module(..., package.seeall)

-- 运营商数据
local oper_data = {
    -- 中国移动
    ["46000"] = {"CM", "中国移动", {"10086", "CXLL"}},
    ["46002"] = {"CM", "中国移动", {"10086", "CXLL"}},
    ["46007"] = {"CM", "中国移动", {"10086", "CXLL"}},
    -- 中国联通
    ["46001"] = {"CU", "中国联通", {"10010", "2082"}},
    ["46006"] = {"CU", "中国联通", {"10010", "2082"}},
    ["46009"] = {"CU", "中国联通", {"10010", "2082"}},
    -- 中国电信
    ["46003"] = {"CT", "中国电信", {"10001", "108"}},
    ["46005"] = {"CT", "中国电信", {"10001", "108"}},
    ["46011"] = {"CT", "中国电信", {"10001", "108"}},
    -- 中国广电
    ["46015"] = {"CB", "中国广电"}
}

--- 获取 MCC 和 MNC
-- @return (string) MCCMNC 代码
function getMccMnc()
    return net.getMcc() .. net.getMnc()
end

--- 获取运营商
-- @param is_zh (boolean) 是否返回中文运营商名称
-- @return (string) 运营商名称, 未知运营商返回 MCCMNC 代码
function getOper(is_zh)
    local mcc_mnc = getMccMnc()

    local oper = oper_data[mcc_mnc]
    if oper then
        return is_zh and oper[2] or oper[1]
    else
        return mcc_mnc
    end
end

--- 发送查询流量短信
function queryTraffic()
    local mcc_mnc = getMccMnc()

    local oper = oper_data[mcc_mnc]
    if oper and oper[3] then
        sms.send(oper[3][1], oper[3][2])
    else
        log.warn("util_mobile.queryTraffic", "查询流量代码未配置")
    end
end
