PROJECT = "air724ug-forwarder"
VERSION = "1.0.0"

require "log"
LOG_LEVEL = log.LOGLEVEL_INFO
require "config"
require "nvm"
nvm.init("config.lua")
require "audio"
audio.setStrategy(1)
require "cc"
require "common"
require "http"
require "misc"
require "net"
require "netLed"
require "ntp"
require "powerKey"
require "record"
require "ril"
require "sim"
require "sms"
require "sys"
require "util_mobile"
require "util_audio"
require "util_http"
require "util_notify"
require "util_temperature"
require "util_ntp"
require "handler_call"
require "handler_powerkey"
require "handler_sms"

-- 输出音频通道选项, 0:听筒 1:耳机 2:喇叭
-- 输入音频通道选项, 0:主mic 3:耳机mic

-- 静音音频通道
AUDIO_OUTPUT_CHANNEL_MUTE = 0
AUDIO_INPUT_CHANNEL_MUTE = 3
-- 正常音频通道
AUDIO_OUTPUT_CHANNEL_NORMAL = 2
AUDIO_INPUT_CHANNEL_NORMAL = 0

audio.setChannel(AUDIO_OUTPUT_CHANNEL_NORMAL, AUDIO_INPUT_CHANNEL_NORMAL)

-- 配置内部 PA 类型 audiocore.CLASS_AB, audiocore.CLASS_D
audiocore.setpa(audiocore.CLASS_AB)
-- 配置外部 PA
-- pins.setup(pio.P0_14, 0)
-- audiocore.pa(pio.P0_14, 1, 0, 0)
-- audio.setChannel(1)

-- 定时查询温度
sys.timerLoopStart(util_temperature.get, 1000 * 60)
-- 定时查询 信号强度 基站信息
net.startQueryAll(1000 * 60, 1000 * 60 * 10)

-- RNDIS
ril.request("AT+RNDISCALL=" .. (nvm.get("RNDIS_ENABLE") and 1 or 0) .. ",0")

-- NET 指示灯, LTE 指示灯
pmd.ldoset(2, pmd.LDO_VLCD)
netLed.setup(true, pio.P0_1)
netLed.updateBlinkTime("SCK", 50, 50)
netLed.updateBlinkTime("GPRS", 200, 2000)

-- 开机查询本机号码
sys.timerStart(ril.request, 3000, "AT+CNUM")

sys.taskInit(function()
    -- 等待网络就绪
    sys.waitUntil("IP_READY_IND", 1000 * 60 * 2)

    -- 等待获取 Band 值
    -- sys.wait(1000 * 5)

    -- 开机通知
    if nvm.get("BOOT_NOTIFY") then
        util_notify.add("#BOOT")
    end

    -- 定时查询流量
    if config.QUERY_TRAFFIC_INTERVAL and config.QUERY_TRAFFIC_INTERVAL >= 1000 * 60 then
        sys.timerLoopStart(util_mobile.queryTraffic, config.QUERY_TRAFFIC_INTERVAL)
    end

    -- 开机同步时间
    util_ntp.sync()
    sys.timerLoopStart(util_ntp.sync, 1000 * 30)
end)

-- 系统初始化
sys.init(0, 0)
sys.run()
