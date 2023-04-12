require "sys"
require "sms"
require "sim"
require "common"
require "log"
require "cc"
require "config"
require "util_notify"


-- 判断号码是否在配置的白名单里
local function isElementInTable(myTable, target)
    for _, value in ipairs(myTable) do
        if value == target then
            return true
        end
    end
    return false
end

local function isAllowNumber(number, sender_number)
    local my_number = sim.getNumber()
    if number == nil then
        return false
    end
    if type(number) ~= "string" then
        return false
    end
    if number:len() < 5 then
        return false
    end
    if number == my_number then
        return false
    end
    if "86" .. number == my_number then
        return false
    end
    if number == sender_number then
        return false
    end
    if "86" .. number == sender_number then
        return false
    end
    isInWhiteList = isElementInTable(config.SMS_ALLOW_NUMBER, sender_number)
    log.info("是否在白名单", isInWhiteList)
    if config.SMS_ALLOW_NUMBER == nil or config.SMS_ALLOW_NUMBER == "" then -- 没设置白名单号码, 允许所有号码触发
        return true
    elseif isInWhiteList then -- 设置了白名单号码, 只允许白名单号码触发
        return true
    else
        return false
    end
end

-- 短信内容匹配
local function smsContentMatcher(sender_number, sms_content)
    sender_number = type(sender_number) == "string" and sender_number or ""
    sms_content = type(sms_content) == "string" and sms_content or ""

    -- 如果短信内容是 `CALL,{called_number}`, 则拨打电话
    local called_number = sms_content:match("^CALL,(%d+)$")
    called_number = called_number or ""

    -- 判断号码符合要求
    if isAllowNumber(called_number, sender_number) then
        log.info("短信内容匹配", "拨打电话", called_number)
        -- 拨打电话
        sys.taskInit(cc.dial, called_number)
        -- 发送通知
        util_notify.send(
            {
                sender_number .. "的短信触发了<拨打电话>",
                "",
                "被叫人号码: " .. called_number,
                "#CONTROL"
            }
        )
        return
    end

    -- 如果短信内容是 `SMS,{receiver_number},{sms_content_to_be_sent}`, 则发送短信
    local receiver_number, sms_content_to_be_sent = sms_content:match("^SMS,(%d+),(.*)$")
    receiver_number = receiver_number or ""
    sms_content_to_be_sent = sms_content_to_be_sent or ""

    -- 判断号码符合要求, 短信内容非空
    if isAllowNumber(receiver_number, sender_number) and sms_content_to_be_sent:len() > 0 then
        -- 防止循环发送短信
        if string.sub(sms_content_to_be_sent, 1, 4) == "SMS," then
            return
        end

        log.info("短信内容匹配", "发送短信给" .. receiver_number .. ": " .. sms_content_to_be_sent)

        -- 发送短信
        sys.taskInit(sms.send, receiver_number, sms_content_to_be_sent)
        -- 发送通知
        util_notify.send(
            {
                sender_number .. "的短信触发了<发送短信>",
                "",
                "收件人号码: " .. receiver_number,
                "短信内容: " .. sms_content_to_be_sent,
                "#CONTROL"
            }
        )
        return
    end
end

-- 收到短信回调
local function smsCallback(sender_number, data, datetime)
    -- 转换短信内容
    local sms_content = common.gb2312ToUtf8(data)
    log.info("收到短信", sender_number, datetime, sms_content)

    -- 发送通知
    util_notify.send(
        {
            sms_content,
            "",
            "发件人号码: " .. sender_number,
            "#SMS"
        }
    )

    -- 短信内容匹配
    sys.taskInit(smsContentMatcher, sender_number, sms_content)
end

-- 设置短信回调
sms.setNewSmsCb(smsCallback)
