local function tts(text, vol)
    if cc.anyCallExist() then
        log.info("handler_powerkey.tts", "正在通话中, 不播放")
        return
    end
    vol = vol or nvm.get("AUDIO_VOLUME") or 1
    vol = vol == 0 and 1 or vol
    audio.setTTSSpeed(90)
    util_audio.play(0, "TTS", text, vol)
end

local options = {
    {
        name = "扬声器音量",
        func = function()
            local vol = nvm.get("AUDIO_VOLUME") or 0
            vol = vol >= 7 and 0 or vol + 1
            nvm.set("AUDIO_VOLUME", vol)
            tts("音量 " .. vol)
        end,
    },
    {
        name = "扬声器静音",
        func = function()
            nvm.set("AUDIO_VOLUME", 0)
        end,
    },
    {
        name = "通话音量",
        func = function()
            local vol = nvm.get("CALL_VOLUME") or 0
            vol = vol >= 7 and 0 or vol + 1
            nvm.set("CALL_VOLUME", vol)
            tts("音量 " .. vol)
        end,
    },
    {
        name = "麦克音量",
        func = function()
            local vol = nvm.get("MIC_VOLUME") or 0
            vol = vol >= 15 and 0 or vol + 5
            nvm.set("MIC_VOLUME", vol)
            tts("音量 " .. vol)
        end,
    },
    {
        name = function()
            local number = "无"
            if type(CALL_NUMBER) == "string" and CALL_NUMBER ~= "" then
                number = CALL_NUMBER
            end
            return "回拨电话 " .. number
        end,
        func = function()
            if type(CALL_NUMBER) == "string" and CALL_NUMBER ~= "" then
                -- 修改来电动作为无操作, 等待挂断后再修改回去
                sys.taskInit(function()
                    local old_call_in_action = nvm.get("CALL_IN_ACTION")
                    nvm.set("CALL_IN_ACTION", 0)
                    sys.waitUntil("CALL_DISCONNECTED", 1000 * 30)
                    nvm.set("CALL_IN_ACTION", old_call_in_action)
                    log.info("handler_powerkey", "恢复来电动作配置项", old_call_in_action)
                end)
                tts("正在拨打")
                sys.timerStart(cc.dial, 3000, CALL_NUMBER)
            else
                tts("无来电号码")
            end
        end,
    },
    {
        name = "测试通知",
        func = function()
            util_notify.add("#ALIVE")
        end,
    },
    {
        name = "短信播报",
        func = function()
            local options = { "关闭", "仅验证码", "全部" }
            local currentOptionIndex = nvm.get("SMS_TTS") or 0
            currentOptionIndex = currentOptionIndex >= #options - 1 and 0 or currentOptionIndex + 1
            nvm.set("SMS_TTS", currentOptionIndex)
            tts(options[currentOptionIndex + 1])
        end,
    },
    {
        name = "来电动作",
        func = function()
            local options = { "无操作", "接听", "挂断", "接听后挂断" }
            local currentOptionIndex = nvm.get("CALL_IN_ACTION") or 0
            currentOptionIndex = currentOptionIndex >= #options - 1 and 0 or currentOptionIndex + 1
            nvm.set("CALL_IN_ACTION", currentOptionIndex)
            tts(options[currentOptionIndex + 1])
        end,
    },
    {
        name = "开机通知",
        func = function()
            nvm.set("BOOT_NOTIFY", not nvm.get("BOOT_NOTIFY"))
            tts("开机通知 " .. (nvm.get("BOOT_NOTIFY") and "开" or "关"))
        end,
    },
    {
        name = "网卡",
        func = function()
            nvm.set("RNDIS_ENABLE", not nvm.get("RNDIS_ENABLE"))
            if nvm.get("RNDIS_ENABLE") then
                ril.request("AT+RNDISCALL=1,0")
            else
                ril.request("AT+RNDISCALL=0,0")
            end
            tts("网卡 " .. (nvm.get("RNDIS_ENABLE") and "开" or "关"))
        end,
    },
    {
        name = "查询流量",
        func = function()
            util_mobile.queryTraffic()
        end,
    },
    {
        name = "查询温度",
        func = function()
            tts("当前温度 " .. util_temperature.get())
        end,
    },
    {
        name = "查询时间",
        func = function()
            local date = os.date("*t", time)
            tts(table.concat({ date.year, "年", date.month, "月", date.day, "日", date.hour, "时", date.min, "分", date.sec, "秒" }, ""))
        end,
    },
    {
        name = "查询信号",
        func = function()
            tts(net.getRsrp() - 140 .. "dbm")
            net.csqQueryPoll()
        end,
    },
    {
        name = "查询内存",
        func = function()
            local m = collectgarbage("count")
            m = m > 1024 and string.format("%.2f", m / 1024) .. " M" or string.format("%.2f", m) .. " K"
            tts("已用 " .. m)
        end,
    },
    {
        name = "查询电压",
        func = function()
            local vbatt = misc.getVbatt()
            if vbatt and vbatt ~= "" then
                tts("当前电压 " .. vbatt / 1000)
            end
        end,
    },
    {
        name = "查询卡号",
        func = function()
            local num = sim.getNumber()
            num = num ~= "" and num or sim.getIccid()
            tts(num)
        end,
    },
    {
        name = "重启",
        func = function()
            sys.timerStart(sys.restart, 2000, "powerkey")
        end,
    },
    {
        name = "关机",
        func = function()
            sys.timerStart(rtos.poweroff, 2000)
        end,
    },
}

local options_select = 0

powerKey.setup(1000 * 0.5, function()
    if cc.anyCallExist() then
        local cc_state = cc.getState(CALL_NUMBER)
        if cc_state == cc.INCOMING or cc_state == cc.WAITING or cc_state == cc.HOLD then
            log.info("handler_powerkey", "手动接听")
            cc.accept(CALL_NUMBER)
            return
        end
        if cc_state == cc.CONNECTED or cc_state == cc.DIALING or cc_state == cc.ALERTING then
            log.info("handler_powerkey", "手动挂断")
            cc.hangUp(CALL_NUMBER)
            return
        end
        log.info("handler_powerkey", "正在通话中, 不响应操作")
        return
    end
    if options_select == 0 then
        return
    end
    options[options_select].func()
end, function()
    if cc.anyCallExist() then
        log.info("handler_powerkey", "正在通话中, 不响应操作")
        return
    end
    if options_select >= #options then
        options_select = 1
    else
        options_select = options_select + 1
    end
    if type(options[options_select].name) == "function" then
        tts(options[options_select].name())
    else
        tts(options[options_select].name)
    end
end)
