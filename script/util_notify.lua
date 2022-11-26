require "http"
require "net"
require "sim"
require "log"
require "config"
require "util_get_oper"
module(..., package.seeall)

local function urlencodeTab(params)
    local msg = {}
    for k, v in pairs(params) do
        table.insert(msg, string.urlEncode(k) .. "=" .. string.urlEncode(v))
        table.insert(msg, "&")
    end
    table.remove(msg)
    return table.concat(msg)
end

-- 发送到 PushDeer
local function notifyToPushDeer(msg, httpCallback)
    if config.PUSHDEER_KEY == "" then
        log.error("未配置 `config.PUSHDEER_KEY`")
        return
    end

    local header = {
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }
    local body = {
        pushkey = config.PUSHDEER_KEY or "",
        type = "text",
        text = msg
    }
    local url = "https://api2.pushdeer.com/message/push"

    http.request("POST", url, nil, header, urlencodeTab(body), 30000, httpCallback, nil)
end

-- 发送到 BARK
local function notifyToBark(msg, httpCallback)
    if config.BARK_KEY == "" then
        log.error("未配置 `config.BARK_KEY`")
        return
    end

    local header = {
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }
    local body = {
        body = msg
    }
    local url = "https://api.day.app/" .. config.BARK_KEY or ""

    http.request("POST", url, nil, header, urlencodeTab(body), 30000, httpCallback, nil)
end

-- 发送到 Telegram
local function notifyToTelegram(msg, httpCallback)
    if config.TELEGRAM_PROXY_API == nil or config.TELEGRAM_PROXY_API == "" then
        log.error("未配置 `config.TELEGRAM_PROXY_API`")
        return
    end

    local header = {
        ["content-type"] = "text/plain",
        ["x-disable-web-page-preview"] = "1",
        ["x-chat-id"] = config.TELEGRAM_CHAT_ID or "",
        ["x-token"] = config.TELEGRAM_TOKEN or ""
    }

    http.request("POST", config.TELEGRAM_PROXY_API, nil, header, msg, 30000, httpCallback, nil)
end

-- 带通知内容和重发计数的 HTTP 回调
local function customHttpCallback(msg, retry_count, result, prompt, head, body)
    if result and prompt == "200" then
        log.info("HTTP回调", "发送通知成功", result, prompt)
    else
        log.error("HTTP回调", "发送通知失败", result, prompt, head, body)

        -- 重发
        retry_count = retry_count + 1
        if msg and retry_count <= 5 then
            log.info("HTTP重发", "重发次数:", retry_count)
            -- 开头加上 `#RETRY\n`
            sys.timerStart(util_notify.send, 5000, "#RETRY\n" .. msg, retry_count)
        else
            log.warn("HTTP重发", "重发次数:", retry_count, "次数过多放弃重发")
        end
    end
end

function send(msg, retry_count)
    -- 如果是 0, 表示不是重发
    retry_count = retry_count or 0

    if type(msg) == "table" then
        msg = table.concat(msg, "\n")
    end
    if type(msg) ~= "string" then
        log.error("发送通知失败", "参数类型错误", type(msg))
        return
    end

    log.info("发送通知", config.NOTIFY_TYPE)

    -- 如果是 0, 表示不是重发, 不在尾部追加设备信息
    if retry_count == 0 then
        local rsrp = net.getRsrp()
        local rsrp_dbm = rsrp - 140
        local rsrp_asu = rsrp

        msg = msg .. "\n\n本机号码: " .. sim.getNumber():gsub("^86", "")
        msg = msg .. "\n运营商: " .. util_get_oper.get(true)
        msg = msg .. "\n信号: " .. rsrp_dbm .. "dBm " .. rsrp_asu .. "asu " .. net.getRssi()
        msg = msg .. "\n频段: B" .. net.getBand()
        msg = msg .. "\n温度: " .. CPU_TEMP .. "℃"
    end

    local function httpCallback(...)
        customHttpCallback(msg, retry_count, ...)
    end

    if config.NOTIFY_TYPE == "pushdeer" then
        sys.taskInit(notifyToPushDeer, msg, httpCallback)
        return
    end
    if config.NOTIFY_TYPE == "bark" then
        sys.taskInit(notifyToBark, msg, httpCallback)
        return
    end
    if config.NOTIFY_TYPE == "telegram" then
        sys.taskInit(notifyToTelegram, msg, httpCallback)
        return
    end
end
