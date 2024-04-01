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
        name = "音量",
        func = function()
            local vol = nvm.get("AUDIO_VOLUME") or 0
            vol = vol >= 7 and 0 or vol + 1
            nvm.set("AUDIO_VOLUME", vol)
            tts("音量 " .. vol)
        end,
    },
    {
        name = "静音",
        func = function()
            nvm.set("AUDIO_VOLUME", 0)
        end,
    },
    {
        name = "测试通知",
        func = function()
            util_notify.add("#ALIVE")
            -- for i = 1, 5 do
            --     util_notify.add(string.rep("测试通知", 200) .. i)
            -- end
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
        name = "通话播放",
        func = function()
            nvm.set("CALL_PLAY_TO_SPEAKER_ENABLE", not nvm.get("CALL_PLAY_TO_SPEAKER_ENABLE"))
            tts("通话播放 " .. (nvm.get("CALL_PLAY_TO_SPEAKER_ENABLE") and "开" or "关"))
        end,
    },
    {
        name = "通话麦克风",
        func = function()
            nvm.set("CALL_MIC_ENABLE", not nvm.get("CALL_MIC_ENABLE"))
            tts("通话麦克风 " .. (nvm.get("CALL_MIC_ENABLE") and "开" or "关"))
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
            tts("当前信号 " .. net.getRsrp() - 140 .. "dbm")
            net.csqQueryPoll()
        end,
    },
    {
        name = "查询内存",
        func = function()
            local m = collectgarbage("count")
            m = m > 1024 and string.format("%.2f", m / 1024) .. " M" or string.format("%.2f", m) .. " K"
            tts("已用内存 " .. m)
        end,
    },
    {
        name = "查询电压",
        func = function()
            local id = 5
            local adcval, voltval = adc.read(id)
            if adcval ~= 0xffff then
                log.info("ADC的原始测量数据和电压值:", adcval, voltval)
                tts("当前电压 " .. voltval / 1000)
            end
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
    tts(options[options_select].name)
end)
