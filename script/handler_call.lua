require "sys"
require "log"
require "cc"
require "audio"
require "record"
require "http"
require "sim"
require "misc"
require "config"
require "util_notify"

------------------------------------------------- Config --------------------------------------------------

-- 录音上传接口
local record_upload_url = config.UPLOAD_URL .. "/record"

-- 录音格式, 1:pcm 2:wav 3:amrnb 4:speex
local record_format = 2

-- 录音质量, 仅 amrnb 格式有效, 0：一般 1：中等 2：高 3：无损
local record_quality = 3

-- 录音最长时间, 单位秒, <=50
local record_max_time = 50

------------------------------------------------- 初始化及状态记录 --------------------------------------------------
local record_extentions = {
    [1] = "pcm",
    [2] = "wav",
    [3] = "amr",
    [4] = "speex"
}
local record_mime_types = {
    [1] = "audio/x-pcm",
    [2] = "audio/wav",
    [3] = "audio/amr",
    [4] = "audio/speex"
}
local record_extention = record_extentions[record_format]
local record_mime_type = record_mime_types[record_format]

local record_upload_header = {["Content-Type"] = record_mime_type, ["Connection"] = "keep-alive"}
local record_upload_body = {[1] = {["file"] = record.getFilePath()}}

audio.setCallVolume(7)

-- CALL_IN 从 CALL_INCOMING - CALL_DISCONNECTED 都是 true
local CALL_IN = false
local CALL_NUMBER = ""
local CALL_CONNECTED_TIME = 0
-- 以下变量 CALL_CONNECTED 时需要重新初始化
local CALL_DISCONNECTED_TIME = 0
local CALL_RECORD_START_TIME = 0

------------------------------------------------- 录音上传相关 --------------------------------------------------
local function recordUploadResultNotify(result, url, msg)
    local current_time = os.time()

    CALL_DISCONNECTED_TIME = CALL_DISCONNECTED_TIME == 0 and current_time or CALL_DISCONNECTED_TIME
    CALL_RECORD_START_TIME = CALL_RECORD_START_TIME == 0 and current_time or CALL_RECORD_START_TIME

    local lines = {
        "来电号码: " .. CALL_NUMBER,
        "通话时长: " .. (CALL_DISCONNECTED_TIME or current_time) - (CALL_CONNECTED_TIME or current_time) .. " S",
        "录音时长: " .. (CALL_DISCONNECTED_TIME or current_time) - (CALL_RECORD_START_TIME or current_time) .. " S",
        "录音结果: " .. (result and "成功" or ("失败, " .. (msg or ""))),
        "",
        "#CALL #CALL_RECORD"
    }

    util_notify.send(lines)
end

-- 录音上传结果回调
local function customHttpCallback(url, result, prompt, head, body)
    if result and prompt == "200" then
        log.info("HTTP回调", "录音上传成功", url, result, prompt)
        recordUploadResultNotify(true, url)
    else
        log.error("HTTP回调", "录音上传失败", url, result, prompt, head, body)
        recordUploadResultNotify(false, nil, "录音上传失败")
    end
end

-- 录音上传
local function upload()
    local local_file = record.getFilePath()
    local time = os.time()
    local date = os.date("*t", time)
    local date_str =
        table.concat(
        {
            date.year .. "/",
            string.format("%02d", date.month) .. "/",
            string.format("%02d", date.day) .. "/",
            string.format("%02d", date.hour) .. "-",
            string.format("%02d", date.min) .. "-",
            string.format("%02d", date.sec)
        },
        ""
    )
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
    -- 先停止所有挂断电话定时器，再挂断电话
    sys.timerStopAll(cc.hangUp)
    cc.hangUp(CALL_NUMBER)

    -- 如果录音成功, 上传录音文件
    if result then
        -- 判断录音时长
        if os.time() - CALL_RECORD_START_TIME >= 2 then
            log.info("录音结束回调", "录音成功, 时长满足要求", "result:", result, "size:", size, io.fileSize(record.getFilePath()))
            upload()
        else
            log.info("录音结束回调", "录音成功, 时长不满足要求", "result:", result, "size:", size, io.fileSize(record.getFilePath()))
            recordUploadResultNotify(false, nil, "录音时长过短")
        end
    else
        log.error("录音结束回调", "录音失败", "result:", result, "size:", size, io.fileSize(record.getFilePath()))
        recordUploadResultNotify(false, nil, "录音失败 size:" .. size)
    end
end

-- 开始录音
local function reacrdStart()
    if (CALL_IN and cc.CONNECTED) then
        log.info("reacrdStart", "正在通话中, 开始录音", "result:", result)
        CALL_RECORD_START_TIME = os.time()
        record.start(record_max_time, recordCallback, "FILE", record_quality, 2, record_format)
    else
        log.info("reacrdStart", "通话已结束, 不录音", "result:", result)
        recordUploadResultNotify(false, nil, "呼叫方提前挂断电话, 无录音")
    end
end

------------------------------------------------- TTS 相关 --------------------------------------------------
-- TTS 播放结束回调
local function ttsCallback(result)
    log.info("TTS 播放结束回调", "result:", result)

    -- 延迟开始录音, 防止 TTS 播放时主动挂断电话, 会先触发 TTS 结束回调, 再触发挂断电话回调, 导致reacrdStart()判断到正在通话中
    sys.timerStart(reacrdStart, 500)
end

-- 播放 TTS，播放结束后开始录音
local function tts()
    log.info("TTS 播放开始")

    audio.setTTSSpeed(60)
    audio.play(7, "TTS", config.TTS_TEXT, 7, ttsCallback)
end

------------------------------------------------- 电话回调函数 --------------------------------------------------
-- 电话拨入回调
-- 设备主叫时, 不会触发此回调
local function callIncomingCallback(num)
    log.info("电话拨入回调", num)

    -- CALL_IN 从电话拨入到挂断都是 true, 也就是说只要在通话中，就不会接通其他电话
    if not CALL_IN then
        -- 标记接听来电中
        CALL_IN = true
        -- 接听电话
        cc.accept(num)

        -- 发通知
        util_notify.send(
            {
                "来电号码: " .. num,
                "状态: 通话中",
                "",
                "#CALL #CALL_IN"
            }
        )
    end
end

-- 电话接通回调
local function callConnectedCallback(num)
    -- 再次标记接听来电中, 防止设备主叫时, 不触发 `CALL_INCOMING` 回调, 导致 CALL_IN 为 false
    CALL_IN = true
    -- 接通时间
    CALL_CONNECTED_TIME = os.time()
    -- 来电号码
    CALL_NUMBER = num or "unknown"
    -- 重新初始化以下变量
    CALL_DISCONNECTED_TIME = 0
    CALL_RECORD_START_TIME = 0

    log.info("电话接通回调", num)

    -- 向对方播放留言提醒 TTS
    sys.timerStart(tts, 1000 * 2)
    -- 定时结束通话
    sys.timerStart(cc.hangUp, 1000 * 60 * 2, num)
end

-- 电话挂断回调
-- 设备主叫时, 被叫方主动挂断电话或者未接, 也会触发此回调
local function callDisconnectedCallback(discReason)
    -- 标记来电结束
    CALL_IN = false
    -- 通话结束时间
    CALL_DISCONNECTED_TIME = os.time()
    -- 清除所有挂断通话定时器, 防止多次触发挂断回调
    sys.timerStopAll(cc.hangUp)

    log.info("电话挂断回调", "挂断原因:", discReason)

    -- 录音结束
    record.stop()
    -- TTS 结束
    audio.stop()
end

-- 注册电话回调
sys.subscribe("CALL_INCOMING", callIncomingCallback)
sys.subscribe("CALL_CONNECTED", callConnectedCallback)
sys.subscribe("CALL_DISCONNECTED", callDisconnectedCallback)
