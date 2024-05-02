local function tts(text, vol)
    if type(text) ~= "string" or text == "" or vol == 0 then
        return
    end
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
        name = function()
            return "扬声器音量 " .. (nvm.get("AUDIO_VOLUME") or 0)
        end,
        func = function()
            local vol = nvm.get("AUDIO_VOLUME") or 0
            vol = vol >= 6 and 0 or vol + 1
            nvm.set("AUDIO_VOLUME", vol)
            tts("音量 " .. vol)
        end,
    },
    {
        name = function()
            return "通话音量 " .. (nvm.get("CALL_VOLUME") or 0)
        end,
        func = function()
            local vol = nvm.get("CALL_VOLUME") or 0
            vol = vol >= 7 and 0 or vol + 1
            vol = vol == 1 and 3 or vol
            vol = vol == 2 and 3 or vol
            nvm.set("CALL_VOLUME", vol)
            tts("音量 " .. vol)
        end,
    },
    {
        name = function()
            return "麦克音量 " .. (nvm.get("MIC_VOLUME") or 0)
        end,
        func = function()
            local vol = nvm.get("MIC_VOLUME") or 0
            vol = vol >= 7 and 0 or vol + 1
            vol = vol == 1 and 3 or vol
            vol = vol == 2 and 3 or vol
            nvm.set("MIC_VOLUME", vol)
            tts("音量 " .. vol)
        end,
    },
    {
        name = "全部静音",
        func = function()
            nvm.set("AUDIO_VOLUME", 0)
            nvm.set("CALL_VOLUME", 0)
            nvm.set("MIC_VOLUME", 0)
        end,
    },
    {
        name = "来电动作",
        func = function()
            local options = { "无操作", "自动接听", "挂断", "自动接听后挂断", "等待30秒后自动接听" }
            local currentOptionIndex = nvm.get("CALL_IN_ACTION") or 0
            currentOptionIndex = currentOptionIndex >= #options - 1 and 0 or currentOptionIndex + 1
            nvm.set("CALL_IN_ACTION", currentOptionIndex)
            tts(options[currentOptionIndex + 1])
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
                    log.info("handler_powerkey", "临时修改来电动作配置项", 0)
                    nvm.set("CALL_IN_ACTION", 0)
                    sys.waitUntil("CALL_DISCONNECTED", 1000 * 60 * 2)
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
        name = "历史短信",
        func = function()
            if LATEST_SMS and LATEST_SMS ~= "" then
                tts("[n1]" .. LATEST_SMS)
            else
                tts("无短信")
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
    -- {
    --     name = "查询温度",
    --     func = function()
    --         tts("当前温度 " .. util_temperature.get())
    --     end,
    -- },
    -- {
    --     name = "查询时间",
    --     func = function()
    --         local date = os.date("*t", time)
    --         tts(table.concat({ date.year, "年", date.month, "月", date.day, "日", date.hour, "时", date.min, "分", date.sec, "秒" }, ""))
    --     end,
    -- },
    -- {
    --     name = "查询内存",
    --     func = function()
    --         local m = collectgarbage("count")
    --         m = m > 1024 and string.format("%.2f", m / 1024) .. " M" or string.format("%.2f", m) .. " K"
    --         tts("已用 " .. m)
    --     end,
    -- },
    {
        name = "查询卡号",
        func = function()
            tts(util_mobile.getNumber())
        end,
    },
    {
        name = function()
            net.csqQueryPoll()
            return "信号" .. (net.getRsrp() - 140)
        end,
        func = function()
            net.csqQueryPoll()
            tts("信号" .. (net.getRsrp() - 140))
        end,
    },
    {
        name = function()
            local vbatt = misc.getVbatt()
            if vbatt and vbatt ~= "" then
                return "电压 " .. (vbatt / 1000)
            end
        end,
        func = function()
            local vbatt = misc.getVbatt()
            if vbatt and vbatt ~= "" then
                tts("电压 " .. (vbatt / 1000))
            end
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
        name = "状态指示灯",
        func = function()
            local state = not nvm.get("LED_ENABLE")
            pmd.ldoset(state and 1 or 0, pmd.LDO_VLCD)
            nvm.set("LED_ENABLE", state)
            tts("指示灯 " .. (state and "开" or "关"))
        end,
    },
    {
        name = "开关飞行模式",
        func = function()
            net.switchFly(true)
            sys.timerStart(net.switchFly, 500, false)
        end,
    },
    {
        name = "切换卡槽",
        func = function()
            local sim_id = sim.getId() == 0 and 1 or 0
            sim.setId(sim_id)
            tts(sim_id == 0 and "主卡槽优先" or "副卡槽优先")
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
local last_short_press_time = rtos.tick() * 5
local double_press_interval = 250

-- 长时间未按下重置菜单选项
sys.timerLoopStart(function()
    if rtos.tick() * 5 - last_short_press_time > 1000 * 60 * 10 then
        options_select = 0
    end
end, 1000 * 10)

local function switchMenu(is_prev)
    if is_prev then
        if options_select <= 1 then
            options_select = #options
        else
            options_select = options_select - 1
        end
    else
        if options_select >= #options then
            options_select = 1
        else
            options_select = options_select + 1
        end
    end

    if type(options[options_select].name) == "function" then
        tts(options[options_select].name())
    else
        tts(options[options_select].name)
    end
end

local function shortCb()
    if cc.anyCallExist() then
        log.info("handler_powerkey", "正在通话中, 不响应操作")
        return
    end

    -- 判断双击
    local now = rtos.tick() * 5
    local is_double_press = now - last_short_press_time < double_press_interval
    last_short_press_time = now

    -- 切换菜单选项
    if is_double_press then
        sys.timerStop(switchMenu, false)
        switchMenu(true)
    else
        sys.timerStart(switchMenu, double_press_interval, false)
    end
end

local function longCb()
    if cc.anyCallExist() then
        local cc_state = cc.getState(CALL_NUMBER)
        if cc_state == cc.INCOMING or cc_state == cc.WAITING or cc_state == cc.HOLD then
            -- 当 CALL_IN_ACTION 为30秒后自动接听, 此时手动接听, 需更改 CALL_IN_ACTION 为无操作, 等待挂断后再修改回去
            if nvm.get("CALL_IN_ACTION") == 4 then
                sys.taskInit(function()
                    log.info("handler_powerkey", "临时修改来电动作配置项", 0)
                    nvm.set("CALL_IN_ACTION", 0)
                    sys.waitUntil("CALL_DISCONNECTED", 1000 * 60 * 2)
                    nvm.set("CALL_IN_ACTION", 4)
                    log.info("handler_powerkey", "恢复来电动作配置项", 4)
                end)
            end
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
    if type(options[options_select].func) == "function" then
        options[options_select].func()
    end
end

powerKey.setup(500, longCb, shortCb)
