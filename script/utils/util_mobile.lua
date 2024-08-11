module(..., package.seeall)

-- 运营商代码 & 流量查询短信
local oper_data = {
    -- 中国移动
    ["46000"] = { "CM", "中国移动", { "10086", "CXLL" } },
    ["46002"] = { "CM", "中国移动", { "10086", "CXLL" } },
    ["46007"] = { "CM", "中国移动", { "10086", "CXLL" } },
    -- 中国联通
    ["46001"] = { "CU", "中国联通", { "10010", "2082" } },
    ["46006"] = { "CU", "中国联通", { "10010", "2082" } },
    ["46009"] = { "CU", "中国联通", { "10010", "2082" } },
    -- 中国电信
    ["46003"] = { "CT", "中国电信", { "10001", "108" } },
    ["46005"] = { "CT", "中国电信", { "10001", "108" } },
    ["46011"] = { "CT", "中国电信", { "10001", "108" } },
    -- 中国广电
    ["46015"] = { "CB", "中国广电" },
}

--- 验证 pin 码
function util_mobile.pinVerify()
    local pin_code = nvm.get("PIN_CODE")
    if type(pin_code) ~= "string" or pin_code == "" then
        log.warn("util_mobile.pinVerify", "PIN_CODE 未配置")
        return
    end

    pin_code = tostring(pin_code or "")
    if #pin_code < 4 or #pin_code > 8 then
        log.warn("util_mobile.pinVerify", "PIN_CODE 长度错误")
        return
    end

    ril.request("AT+CPIN=\"" .. pin_code .. "\"")
end

--- 获取 MCC 和 MNC
-- @return (string) MCCMNC 代码
function getMccMnc()
    local mcc = net.getMcc()
    local mnc = net.getMnc()

    -- 有可能是 1 位数，需要补 0
    if #mnc == 1 then
        mnc = "0" .. mnc
    end

    return mcc .. mnc
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
        -- 发短信之前要先把内容转码成 GB2312
        local sms_content_to_be_sent_gb2312 = common.utf8ToGb2312(oper[3][2])
        -- 发送短信
        sys.taskInit(sms.send, oper[3][1], sms_content_to_be_sent_gb2312)
    else
        log.warn("util_mobile.queryTraffic", "查询流量代码未配置")
    end
end

--- 获取本机号码, 没有则使用 ICCID
-- @return (string) 本机号码
function getNumber()
    -- 本机号码
    local number = sim.getNumber()
    if number and number ~= "" then
        number = number:gsub("^86", "")
        return number
    end

    -- ICCID
    local iccid = sim.getIccid()
    if iccid and iccid ~= "" then
        return iccid
    end

    return "unknown"
end
