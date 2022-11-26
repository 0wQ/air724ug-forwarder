require "sys"
require "sms"
require "log"
require "config"
require "util_get_oper"
module(..., package.seeall)

function run()
    local oper = util_get_oper.get()

    if oper then
        log.info("正在查询流量", "Oper:", oper)
    else
        log.warn("不支持查询流量", "Oper:", oper)
        return
    end

    -- 联通
    if oper == "CU" then
        sys.taskInit(sms.send, "10010", "1071")
        return
    end

    -- 移动
    if oper == "CM" then
        sys.taskInit(sms.send, "10086", "cxll")
        return
    end

    -- 电信
    if oper == "CT" then
        sys.taskInit(sms.send, "10001", "108")
        return
    end
end

if config.QUERY_TRAFFIC_INTERVAL and config.QUERY_TRAFFIC_INTERVAL > 1000 * 60 then
    sys.timerLoopStart(run, config.QUERY_TRAFFIC_INTERVAL)
end
