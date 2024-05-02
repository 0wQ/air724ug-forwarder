------------------------------------------------- Config --------------------------------------------------
-- 是否开启录音上传
local record_enable = nvm.get("UPLOAD_URL") and nvm.get("UPLOAD_URL") ~= ""

-- 去除链接最后的斜杠
local function trimSlash(url)
    return string.gsub(url, "/$", "")
end

-- 录音上传接口
local record_upload_url = trimSlash(nvm.get("UPLOAD_URL") or "") .. "/record"

-- 录音格式, 1:pcm 2:wav 3:amrnb 4:speex
local record_format = 2

-- 录音质量, 仅 amrnb 格式有效, 0:一般 1:中等 2:高 3:无损
local record_quality = 3

-- 录音最长时间, 单位秒, 0-50
local record_max_time = 50

-- 通话最长时间, 单位秒
local call_max_time = 300

------------------------------------------------- 初始化及状态记录 --------------------------------------------------

local record_extentions = { [1] = "pcm", [2] = "wav", [3] = "amr", [4] = "speex" }
local record_mime_types = { [1] = "audio/x-pcm", [2] = "audio/wav", [3] = "audio/amr", [4] = "audio/speex" }
local record_extention = record_extentions[record_format]
local record_mime_type = record_mime_types[record_format]

local record_upload_header = { ["Content-Type"] = record_mime_type, ["Connection"] = "keep-alive" }
local record_upload_body = { [1] = { ["file"] = record.getFilePath() } }

CALL_IN = false
CALL_NUMBER = ""

local CALL_CONNECTED_TIME = 0
local CALL_DISCONNECTED_TIME = 0
local CALL_RECORD_START_TIME = 0

local function getCallInAction()
    -- 动作为接听, 但录音上传未开启
    if nvm.get("CALL_IN_ACTION") == 1 and not record_enable then
        return 3
    end
    return nvm.get("CALL_IN_ACTION")
end

-- 更新音频配置
-- 用于实现通话时静音, 通话结束时恢复正常, 需要在 callIncoming / callConnected / callDisconnected 回调中调用
-- 注意:
-- 如果通话音量设为0, 通话录音会没有声音
-- 需要切换音频通道来实现通话静音
-- 需实现:
-- 通话时, 忽略扬声器音量, 使用通话音量 (如果扬声器音量大于通话音量, 则使用扬声器音量)
-- 无论是否静音, 自动接听时, 通话录音中呼叫方声音正常
-- 无论是否静音, 手动接听时, 音量均为正常
local function updateAudioConfig(is_call_connected)
    local output_channel = AUDIO_OUTPUT_CHANNEL_NORMAL
    local input_channel = AUDIO_INPUT_CHANNEL_NORMAL

    local call_volume_normal = 5
    local mic_volume_normal = 7

    local audio_volume = nvm.get("AUDIO_VOLUME") or 0
    local call_volume = nvm.get("CALL_VOLUME") or call_volume_normal
    local mic_volume = nvm.get("MIC_VOLUME") or mic_volume_normal

    audio_volume = type(audio_volume) == "string" and tonumber(audio_volume) or audio_volume
    call_volume = type(call_volume) == "string" and tonumber(call_volume) or call_volume
    mic_volume = type(mic_volume) == "string" and tonumber(mic_volume) or mic_volume

    -- 来电动作 无操作 时, 如果手动接听, 并且原音量为0, 则音量设置到正常值
    if is_call_connected and getCallInAction() == 0 then
        if call_volume <= 0 then
            call_volume = call_volume_normal
            -- 手动接听, 如果 audio_volume > call_volume, 则使用 audio_volume
            call_volume = audio_volume > call_volume and audio_volume or call_volume
        end
        if mic_volume <= 0 then
            mic_volume = mic_volume_normal
        end
    end

    -- 来电动作 接听/接听后挂断 时, 麦克强制静音
    if is_call_connected and (getCallInAction() == 1 or getCallInAction() == 3) then
        mic_volume = 0
    end

    -- 音量 0 时, 切换静音音频通道, 切换正常音量
    if is_call_connected then
        if call_volume <= 0 then
            call_volume = call_volume_normal
            output_channel = AUDIO_OUTPUT_CHANNEL_MUTE
        end
        if mic_volume <= 0 then
            mic_volume = mic_volume_normal
            input_channel = AUDIO_INPUT_CHANNEL_MUTE
        end
    end

    -- 设置音频通道
    audio.setChannel(output_channel, input_channel)

    -- 设置音量
    audio.setCallVolume(call_volume)
    audio.setMicVolume(mic_volume) -- 测试完全没效果

    -- 设置 mic 增益等级, 通话增益建立成功之后设置才有效
    if is_call_connected then
        audio.setMicGain("call", mic_volume)
        -- audio.setMicGain("record", 7)
    end

    log.info("handler_call.updateAudioConfig", "is_call_connected:", is_call_connected)
    log.info("handler_call.updateAudioConfig", "output_channel:", output_channel, "input_channel:", input_channel)
    log.info("handler_call.updateAudioConfig", "audio_volume:", audio_volume, "call_volume:", call_volume, "mic_volume:", mic_volume)
    log.info("handler_call.updateAudioConfig", "getVolume:" .. audio.getVolume(), "getCallVolume:" .. audio.getCallVolume(), "getMicVolume:" .. audio.getMicVolume())
end

------------------------------------------------- 录音上传相关 --------------------------------------------------

local function recordUploadResultNotify(result, url, msg)
    CALL_DISCONNECTED_TIME = CALL_DISCONNECTED_TIME == 0 and rtos.tick() * 5 or CALL_DISCONNECTED_TIME

    local lines = {
        "来电号码: " .. CALL_NUMBER,
        "通话时长: " .. (CALL_DISCONNECTED_TIME - CALL_CONNECTED_TIME) / 1000 .. " S",
        "录音时长: " .. (result and ((CALL_DISCONNECTED_TIME - CALL_RECORD_START_TIME) / 1000) or 0) .. " S",
        "录音结果: " .. (result and "成功" or ("失败, " .. (msg or ""))),
        result and ("录音文件: " .. url) or "",
        "",
        "#CALL #CALL_RECORD",
    }

    util_notify.add(lines)
end

-- 录音上传结果回调
local function customHttpCallback(url, result, prompt, head, body)
    if result and prompt == "200" then
        log.info("handler_call.customHttpCallback", "录音上传成功", url, result, prompt)
        recordUploadResultNotify(true, url)
    else
        log.error("handler_call.customHttpCallback", "录音上传失败", url, result, prompt, head, body)
        recordUploadResultNotify(false, nil, "录音上传失败")
    end
end

-- 录音上传
local function upload()
    local local_file = record.getFilePath()
    local time = os.time()
    local date = os.date("*t", time)
    local date_str = string.format("%04d/%02d/%02d/%02d-%02d-%02d", date.year, date.month, date.day, date.hour, date.min, date.sec)
    -- URL 结构: /record/18888888888/2022/12/12/12-00-00/10086_1668784328.wav
    local url = record_upload_url .. "/"
    url = url .. (sim.getNumber() or "unknown") .. "/"
    url = url .. date_str .. "/"
    url = url .. CALL_NUMBER .. "_" .. time .. "." .. record_extention

    local function httpCallback(...)
        customHttpCallback(url, ...)
    end

    sys.taskInit(http.request, "PUT", url, nil, record_upload_header, record_upload_body, 50000, httpCallback)
end

------------------------------------------------- 录音相关 --------------------------------------------------

-- 录音结束回调
local function recordCallback(result, size)
    -- 先停止所有挂断电话定时器, 再挂断电话
    sys.timerStopAll(cc.hangUp)
    cc.hangUp(CALL_NUMBER)

    -- 如果录音成功, 上传录音文件
    if result then
        log.info("handler_call.recordCallback", "录音成功", "result:", result, "size:", size)
        upload()
    else
        log.error("handler_call.recordCallback", "录音失败", "result:", result, "size:", size)
        recordUploadResultNotify(false, nil, "录音失败 size:" .. (size or "nil"))
    end
end

-- 开始录音
local function recordStart()
    if not record_enable then
        log.info("handler_call.recordStart", "未开启录音")
        return
    end

    if cc.anyCallExist() then
        log.info("handler_call.recordStart", "正在通话中, 开始录音", "result:", result)
        CALL_RECORD_START_TIME = rtos.tick() * 5
        record.start(record_max_time, recordCallback, "FILE", record_quality, 2, record_format)
    else
        log.info("handler_call.recordStart", "通话已结束, 不录音", "result:", result)
        recordUploadResultNotify(false, nil, "呼叫方提前挂断电话, 无录音")
    end
end

------------------------------------------------- TTS 相关 --------------------------------------------------

-- TTS 播放结束回调
local function ttsCallback(result)
    log.info("handler_call.ttsCallback", "result:", result)

    -- 判断来电动作是否为接听后挂断
    if getCallInAction() == 3 then
        -- 如果是接听后挂断, 则不录音, 直接返回
        log.info("handler_call.callIncomingCallback", "来电动作", "接听后挂断")
        cc.hangUp(CALL_NUMBER)
    else
        -- 延迟开始录音, 防止 TTS 播放时主动挂断电话, 会先触发 TTS 结束回调, 再触发挂断电话回调, 导致 recordStart() 判断到正在通话中
        sys.timerStart(recordStart, 300)
    end
end

-- 播放 TTS, 播放结束后开始录音
local function tts()
    log.info("handler_call.tts", "TTS 播放开始")

    if getCallInAction() == 0 then
        log.info("handler_call.tts", "来电动作: 无动作, 不播放 TTS")
        -- ttsCallback("手动触发 ttsCallback 直接开始录音")
        return
    end

    if config.TTS_TEXT and config.TTS_TEXT ~= "" then
        -- 播放 TTS
        audio.setTTSSpeed(60)
        audio.play(7, "TTS", config.TTS_TEXT, 7, ttsCallback)
    else
        -- 播放音频文件
        if getCallInAction() == 3 then
            util_audio.audioStream("/lua/audio_pickup_hangup.amr", ttsCallback)
        else
            util_audio.audioStream("/lua/audio_pickup_record.amr", ttsCallback)
        end
    end
end

------------------------------------------------- 电话回调函数 --------------------------------------------------

-- 电话拨入回调
-- 设备主叫时, 不会触发此回调
local function callIncomingCallback(num)
    -- 来电号码
    CALL_NUMBER = num or "unknown"

    -- 来电动作, 挂断
    if getCallInAction() == 2 then
        log.info("handler_call.callIncomingCallback", "来电动作", "挂断")
        cc.hangUp(num)
        -- 发通知
        util_notify.add({ "来电号码: " .. num, "来电动作: 挂断", "", "#CALL #CALL_IN" })
        return
    end

    -- CALL_IN 从电话接入到挂断都是 true, 用于判断是否为来电中, 本函数会被多次触发
    if CALL_IN then
        return
    end

    -- 更新音频配置
    updateAudioConfig(false)

    -- 来电动作, 无操作 or 接听
    if getCallInAction() == 0 then
        log.info("handler_call.callIncomingCallback", "来电动作", "无操作")
    else
        log.info("handler_call.callIncomingCallback", "来电动作", "接听")
        -- 标记接听来电中
        CALL_IN = true
        -- 延迟接听电话
        local delay = getCallInAction() == 4 and (1000 * 30) or (1000 * 3)
        sys.timerStart(cc.accept, delay, num)
    end

    -- 发送除了 来电动作为挂断 之外的通知
    local action_desc = { [0] = "无操作", [1] = "自动接听", [2] = "挂断", [3] = "自动接听后挂断", [4] = "等待30秒后自动接听" }
    util_notify.add({ "来电号码: " .. num, "来电动作: " .. action_desc[getCallInAction()], "", "#CALL #CALL_IN" })
end

-- 电话接通回调
local function callConnectedCallback(num)
    -- 再次标记接听来电中, 防止设备主叫时, 不触发 `CALL_INCOMING` 回调, 导致 CALL_IN 为 false
    CALL_IN = true
    -- 接通时间
    CALL_CONNECTED_TIME = rtos.tick() * 5
    -- 来电号码
    CALL_NUMBER = num or "unknown"

    CALL_DISCONNECTED_TIME = 0
    CALL_RECORD_START_TIME = 0

    log.info("handler_call.callConnectedCallback", num)

    -- 更新音频配置
    updateAudioConfig(true)

    -- 停止之前的播放
    audio.stop()
    -- 向对方播放留言提醒 TTS
    sys.timerStart(tts, 1000 * 1)

    -- 最大通话时间后, 结束通话
    sys.timerStart(cc.hangUp, call_max_time * 1000, num)
end

-- 电话挂断回调
-- 设备主叫时, 被叫方主动挂断电话或者未接, 也会触发此回调
local function callDisconnectedCallback(discReason)
    -- 标记来电结束
    CALL_IN = false
    -- 通话结束时间
    CALL_DISCONNECTED_TIME = rtos.tick() * 5
    -- 清除所有挂断通话定时器, 防止多次触发挂断回调
    sys.timerStopAll(cc.hangUp)

    log.info("handler_call.callDisconnectedCallback", "挂断原因:", discReason)

    -- 录音结束
    record.stop()
    -- TTS 结束
    -- tts(util_audio.audioStream 播放的音频文件) 在播放中通话被挂断, 然后在 callDisconnectedCallback 中调用 audio.stop() 有时不会触发 ttsCallback 回调
    -- 调用 audiocore.stop() 可以解决这个问题
    audio.stop(function(result)
        log.info("handler_call.callDisconnectedCallback", "audio.stop() callback result:", result)
    end)
    audiocore.stop()

    -- 更新音频配置
    updateAudioConfig(false)
end

-- 注册电话回调
sys.subscribe("CALL_INCOMING", callIncomingCallback)
sys.subscribe("CALL_CONNECTED", callConnectedCallback)
sys.subscribe("CALL_DISCONNECTED", callDisconnectedCallback)

ril.regUrc("RING", function()
    -- 来电铃声
    local vol = nvm.get("AUDIO_VOLUME") or 0
    if vol == 0 then
        return
    end
    audio.play(4, "FILE", "/lua/audio_ring.mp3", vol)
end)

-- 来电中保持 LTE 灯闪烁
sys.taskInit(function()
    while true do
        if CALL_IN or cc.anyCallExist() then
            sys.publish("LTE_LED_UPDATE", false)
            sys.wait(100)
            sys.publish("LTE_LED_UPDATE", true)
            sys.wait(100)
        else
            sys.waitUntil("RING", 1000 * 5)
        end
    end
end)
