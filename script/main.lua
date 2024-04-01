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

-- 设置音频功放类型
-- CLASSAB: 0
ril.request("AT+SPKPA=0")
-- CLASSD: 1 (默认)
-- ril.request("AT+SPKPA=1")

-- 定时查询温度
sys.timerLoopStart(util_temperature.get, 1000 * 30)
-- 定时查询 信号强度 基站信息
net.startQueryAll(60000, 300000)

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
    sys.wait(1000 * 5)

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
