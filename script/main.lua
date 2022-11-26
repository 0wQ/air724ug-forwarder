PROJECT = "air724ug-forwarder"
VERSION = "1.0.0"

require "log"
LOG_LEVEL = log.LOGLEVEL_INFO

-- 用户配置
require "config"

require "sys"
require "ril"
require "net"
require "netLed"
require "sim"
require "powerKey"

-- 开机原因
sys.taskInit(
    function()
        sys.wait(3000)
        reason = rtos.poweron_reason()
        log.info("开机原因", reason)
    end
)

-- 定时查询 (信号强度, 基站信息)
net.startQueryAll(35000, 55000)

-- RNDIS
if not config.RNDIS_ENABLE then
    ril.request("AT+RNDISCALL=0,1")
end

-- NET 指示灯, LTE 指示灯
pmd.ldoset(2, pmd.LDO_VLCD)
netLed.setup(true, pio.P0_1)
netLed.updateBlinkTime("SCK", 50, 50)
netLed.updateBlinkTime("GPRS", 200, 2000)

-- 开机先查询本机号码
ril.request("AT+CNUM")

-- 加载功能模块
require "handler_call"
require "handler_sms"
require "task_ntp_sync"
require "task_query_temp"
require "task_query_traffic"
require "task_report_data"

-- 开机通知
require "util_notify"
if config.BOOT_NOTIFY then
    sys.timerStart(util_notify.send, 1000 * 15, "#BOOT")
end

-- 设置电源键
local last_press_time = 0
powerKey.setup(
    1000 * 5,
    task_query_traffic.run,
    function()
        local now = os.time()
        if now - last_press_time >= 20 then
            last_press_time = now
            log.info("短按, 发送alive")
            -- 发送 #ALIVE 通知
            util_notify.send("#ALIVE")
            -- 上报数据
            task_report_data.run()
            return
        end
        log.info("短按, 距上次按下时间过短:", now - last_press_time)
    end
)

-- 系统初始化
sys.init(0, 0)
sys.run()
