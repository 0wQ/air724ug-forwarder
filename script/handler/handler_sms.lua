--- 判断一个元素是否在一个表中
-- @param myTable (table) 待查找的表
-- @param target (any) 待查找的元素
-- @return (boolean) 如果元素在表中则返回 true，否则返回 false
local function isElementInTable(myTable, target)
    for _, value in ipairs(myTable) do
        if value == target then
            return true
        end
    end
    return false
end

--- 判断号码是否符合触发短信控制的条件
-- @param number (string) 待判断的号码
-- @param sender_number (string) 短信发送者号码
-- @return (boolean) 如果号码符合条件则返回 true，否则返回 false
local function isAllowNumber(number, sender_number)
    local my_number = sim.getNumber()

    -- 判断号码是否符合要求
    if number == nil or type(number) ~= "string" then
        return false
    end
    -- 号码长度必须大于等于 5 位
    if number:len() < 5 then
        return false
    end
    -- 不允许给本机号码发短信
    if number == my_number or "86" .. number == my_number then
        return false
    end
    -- 不允许给短信发送者发短信
    if number == sender_number or "86" .. number == sender_number then
        return false
    end

    -- 判断如果未设置白名单号码, 允许所有号码触发
    if type(config.SMS_CONTROL_WHITELIST_NUMBERS) ~= "table" or #config.SMS_CONTROL_WHITELIST_NUMBERS == 0 then
        return true
    end

    -- 已设置白名单号码, 判断是否在白名单中
    local isInWhiteList = isElementInTable(config.SMS_CONTROL_WHITELIST_NUMBERS, sender_number)
    log.info("handler_sms.isAllowNumber", "是否在白名单", isInWhiteList)
    return isInWhiteList
end

--- 根据规则匹配短信内容是否符合要求
-- @param sender_number (string) 短信发送者号码
-- @param sms_content (string) 短信内容
local function smsContentMatcher(sender_number, sms_content)
    sender_number = type(sender_number) == "string" and sender_number or ""
    sms_content = type(sms_content) == "string" and sms_content or ""

    -- 如果短信内容是 `CALL,{called_number}`, 则拨打电话
    local called_number = sms_content:match("^CALL,(%d+)$")
    called_number = called_number or ""

    -- 判断号码符合要求
    if isAllowNumber(called_number, sender_number) then
        log.info("handler_sms.smsContentMatcher", "拨打电话", called_number)
        -- 拨打电话
        sys.taskInit(cc.dial, called_number)
        -- 发送通知
        util_notify.add(
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

        log.info("handler_sms.smsContentMatcher", "发送短信给" .. receiver_number .. ": " .. sms_content_to_be_sent)

        -- 发送短信
        sys.taskInit(sms.send, receiver_number, sms_content_to_be_sent)
        -- 发送通知
        util_notify.add(
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

--- 短信回调函数，处理接收到的短信
-- @param sender_number (string) 短信发送者号码
-- @param sms_content (string) 短信内容
-- @param datetime (string) 短信接收时间
local function smsCallback(sender_number, sms_content, datetime)
    log.info("handler_sms.smsCallback", sender_number, datetime, sms_content)

    -- 发送通知
    util_notify.add(
        {
            sms_content,
            "",
            "发件号码: " .. sender_number,
            "发件时间: " .. datetime,
            "#SMS"
        }
    )
    -- 短信内容匹配
    sys.taskInit(smsContentMatcher, sender_number, sms_content)

    -- 判断音量
    if nvm.get("AUDIO_VOLUME") == 0 or nvm.get("AUDIO_VOLUME") == nil then
        return
    end

    -- 短信提示音
    util_audio.play(4, "FILE", "/lua/audio_new_sms.mp3")

    -- 判断 SMS_TTS 开关
    if type(nvm.get("SMS_TTS")) ~= "number" or nvm.get("SMS_TTS") == 0 then
        return
    end

    -- TTS 仅播报验证码
    if nvm.get("SMS_TTS") >= 1 then
        if sms_content:match("验证码") or sms_content:match("校验码") or sms_content:match("取件码") then
            -- 提取发送者
            local sender_name = sms_content:match("【(.+)】")
            sender_name = sender_name or ""

            -- 提取验证码 (至少4位数字)
            local code = sms_content:match("%d%d%d%d+")

            if code then
                audio.setTTSSpeed(65)
                sys.timerStart(util_audio.play, 1000 * 2, 5, "TTS", "[n1]收到" .. sender_name .. "验证码 " .. code)
                return
            end
        end
    end

    -- TTS 播报全部短信内容
    if nvm.get("SMS_TTS") == 2 then
        audio.setTTSSpeed(70)
        sys.timerStart(util_audio.play, 1000 * 2, 5, "TTS", "[n1]收到来自" .. sender_number .. "的短信，" .. sms_content)
    end
end

-- 设置短信回调
sms.setNewSmsCb(smsCallback)

--  设置 urc 回调
-- (URC) 事件控制指示：+CIEV
local function urc(data, prefix)
    data = type(data) == "string" and data or ""
    -- 判断彩信
    if string.find(data, "MMS") then
        -- 发送通知
        util_notify.add({ "收到一条彩信, 但设备不支持接收", "", "发件号码: Unknown", "#SMS #ERROR" })
        ril.request("AT+CNMI=2,1,0,0,0")
        log.info("handler_sms.urc", "收到彩信", prefix, data)
        return
    end
    -- 判断短信存储满
    if string.find(data, "SMSFULL") then
        ril.request("AT+CMGD=1,4")
        ril.request("AT+CNMI=2,1,0,0,0")
        log.info("handler_sms.urc", "短信存储满", prefix, data)
        return
    end
end

ril.regUrc("+CIEV", urc)
