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

--- 判断号码是否符合要求
-- @param number (string) 待判断的号码
-- @return (boolean) 如果号码符合条件则返回 true，否则返回 false
local function checkNumber(number)
    if number == nil or type(number) ~= "string" then
        return false
    end
    -- 号码长度必须大于等于 5 位
    if number:len() < 5 then
        return false
    end

    return true
end

--- 判断白名单号码是否符合触发短信控制的条件
-- @param sender_number (string) 短信发送者号码
-- @return (boolean) 如果号码符合条件则返回 true，否则返回 false
local function isWhiteListNumber(sender_number)
    -- 判断如果未设置白名单号码, 禁止所有号码触发
    if type(config.SMS_CONTROL_WHITELIST_NUMBERS) ~= "table" or #config.SMS_CONTROL_WHITELIST_NUMBERS == 0 then
        return false
    end
    -- 已设置白名单号码, 判断是否在白名单中
    return isElementInTable(config.SMS_CONTROL_WHITELIST_NUMBERS, sender_number)
end

--- 根据规则匹配短信内容是否符合要求
-- @param sender_number (string) 短信发送者号码
-- @param sms_content (string) 短信内容
local function smsContentMatcher(sender_number, sms_content)
    sender_number = type(sender_number) == "string" and sender_number or ""
    sms_content = type(sms_content) == "string" and sms_content or ""

    -- 判断发送者是否为白名单号码
    if not isWhiteListNumber(sender_number) then
        log.info("handler_sms.smsContentMatcher", "非白名单号码")
        return
    end

    -- 如果短信内容是 `SIMSWITCH`, 则切换SIM
    if sms_content == "SIMSWITCH" then
        log.info("handler_sms.smsContentMatcher", "匹配成功: <切换SIM>")

        local action_name = sim.getId() == 0 and "主卡槽优先 -> 副卡槽优先" or "副卡槽优先 -> 主卡槽优先"

        -- 发送通知
        util_notify.add({ sender_number .. " 的短信触发了 <切换SIM>", action_name, "正在重启...", "#CONTROL" })

        sim.setId(sim.getId() == 0 and 1 or 0)

        -- 重启
        sys.timerStart(sys.restart, 5000, "SIMSWITCH")
        return
    else
        log.info("handler_sms.smsContentMatcher", "匹配失败: <切换SIM>")
    end

    -- 如果短信内容是 `CCFC,?`, 则查询所有呼转状态
    if sms_content == "CCFC,?" then
        log.info("handler_sms.smsContentMatcher", "匹配成功: <查询所有呼转状态>")

        -- 查询所有呼叫前转状态
        ril.request("AT+CCFC=4,2")

        -- 发送通知
        util_notify.add({ sender_number .. " 的短信触发了 <查询所有呼转状态>", "", "#CONTROL" })

        return
    else
        log.info("handler_sms.smsContentMatcher", "匹配失败: <查询所有呼转状态>")
    end

    -- 如果短信内容是 `CCFC,{ccfc_number}`, 则设置无条件呼转, 当 ccfc_number=="0" 时，关闭所有呼转
    local ccfc_number = sms_content:match("^CCFC,(%d+)$")
    -- 判断号码
    if checkNumber(ccfc_number) or ccfc_number == "0" then
        local is_disable = ccfc_number == "0"
        local action_name = is_disable and "关闭所有呼转" or "设置无条件呼转"

        log.info("handler_sms.smsContentMatcher", "匹配成功: <" .. action_name .. "无条件呼转>", ccfc_number)

        -- 注册无条件呼转: AT+CCFC=0,3,18888888888
        -- 删除所有呼叫前转: AT+CCFC=4,4,0
        local at_command = is_disable and "AT+CCFC=4,4,0" or ("AT+CCFC=0,3," .. ccfc_number)

        -- 关闭/设置呼转
        ril.request(at_command, nil, function(cmd, result)
            log.info("handler_sms.smsContentMatcher", action_name, result)
            util_notify.add({ action_name .. (result and "成功" or "失败"), "", "#CONTROL" })
        end)

        -- 发送通知
        util_notify.add({ sender_number .. " 的短信触发了 <" .. action_name .. ">", "", "呼转号码: " .. ccfc_number, "#CONTROL" })

        return
    else
        log.info("handler_sms.smsContentMatcher", "匹配失败: <关闭/设置呼转>")
    end

    -- 如果短信内容是 `CALL,{called_number}`, 则拨打电话
    local called_number = sms_content:match("^CALL,(%d+)$")
    -- 判断号码
    if checkNumber(called_number) then
        log.info("handler_sms.smsContentMatcher", "匹配成功: <拨打电话>", called_number)

        -- 拨打电话
        sys.taskInit(cc.dial, called_number)

        -- 发送通知
        util_notify.add({ sender_number .. " 的短信触发了 <拨打电话>", "", "被叫人号码: " .. called_number, "#CONTROL" })

        return
    else
        log.info("handler_sms.smsContentMatcher", "匹配失败: <拨打电话>")
    end

    -- 如果短信内容是 `SMS,{receiver_number},{sms_content_to_be_sent}`, 则发送短信
    local receiver_number, sms_content_to_be_sent = sms_content:match("^SMS,(%d+),(.*)$")
    -- 判断号码, 短信长度
    if checkNumber(receiver_number) and type(sms_content_to_be_sent) == "string" and sms_content_to_be_sent:len() > 0 then
        -- 防止循环发送短信
        if string.sub(sms_content_to_be_sent, 1, 4) == "SMS," then
            return
        end

        log.info("handler_sms.smsContentMatcher", "匹配成功: <发送短信>", receiver_number, sms_content_to_be_sent)

        -- 发送短信
        sys.taskInit(sms.send, receiver_number, sms_content_to_be_sent)

        -- 发送通知
        util_notify.add({ sender_number .. " 的短信触发了 <发送短信>", "", "收件人号码: " .. receiver_number, "短信内容: " .. sms_content_to_be_sent, "#CONTROL" })

        return
    else
        log.info("handler_sms.smsContentMatcher", "匹配失败: <发送短信>")
    end
end

--- 短信回调函数，处理接收到的短信
-- @param sender_number (string) 短信发送者号码
-- @param sms_content (string) 短信内容
-- @param datetime (string) 短信接收时间
local function smsCallback(sender_number, sms_content, datetime)
    log.info("handler_sms.smsCallback", sender_number, datetime, sms_content)

    LATEST_SMS = sms_content

    -- 写入U盘
    local str = datetime .. "\t" .. sender_number .. "\t" .. util_mobile.getNumber() .. "\t" .. sms_content:gsub("\r", "\\r"):gsub("\n", "\\n") .. "\n"
    usbmsc.write("/usbmsc0/sms_history.txt", str)

    -- 发送通知
    util_notify.add({ sms_content, "", "发件号码: " .. sender_number, "发件时间: " .. datetime, "#SMS" })
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
        audio.setTTSSpeed(80)
        sys.timerStart(util_audio.play, 1000 * 2, 5, "TTS", "[n1]收到来自" .. sender_number .. "的短信，" .. sms_content)
    end
end

-- 设置短信回调
sms.setNewSmsCb(smsCallback)

ril.regUrc("+CIEV", function(data, prefix)
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
end)

ril.regUrc("+CCFC", function(data, prefix)
    log.info("查询呼转状态", data, prefix)

    -- https://www.openluat.com/Product/file/rda8955/AirM2M%20无线模块AT命令手册V3.96.pdf
    -- AT+CCFC=<reason>,<mode>[,<number>[,<type>[,<class>[,<subaddr>[,<atype>[,<time>]]]]]]
    -- 如果<mode>等于2，并且命令成功（限定<reason>等于0~3，也就是说如果<mode>等于2，<reason>不能等于4或5）
    -- 对于已经开通呼叫转移的用户，则返回
    -- +CCFC:<status>,<class1>[,<number>,<type>[,<subaddr>,<satype>[,<time>]]]
    -- 如果没有注册过呼叫转移的用户，则返回: +CCFC:<status>,<class>

    local status = string.find(data, "^%+CCFC:1")

    -- 发送通知
    util_notify.add({ "呼转状态查询结果: " .. (status and "已设置" or "未设置"), data, "", "#CONTROL" })
end)
