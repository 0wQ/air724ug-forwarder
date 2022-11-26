require "sys"
require "ntp"
require "log"
module(..., package.seeall)

local timeServer = {
    "edu.ntp.org.cn",
    "cn.ntp.org.cn",
    "0.cn.pool.ntp.org",
    "1.cn.pool.ntp.org",
    "ntp.ntsc.ac.cn",
    "ntp.aliyun.com",
    "ntp1.aliyun.com",
    "ntp2.aliyun.com",
    "ntp3.aliyun.com",
    "ntp.tencent.com",
    "ntp1.tencent.com",
    "ntp2.tencent.com",
    "ntp3.tencent.com"
}

local is_time_normal = false

local function ntpSyncTask()
    -- 如果时间正常, 则不同步, 并删除定时器
    if is_time_normal then
        sys.timerStopAll(ntpSyncTask)
        return
    end

    log.info("ntpSync", "开始同步")
    ntp.timeSync(
        nil,
        function(time, result)
            if result and time.year >= 2022 then
                log.info("ntpSync", "时间正常, 结束同步")
                is_time_normal = true
                -- 同步成功, 结束同步
                sys.timerStopAll(ntpSyncTask)
            else
                log.info("ntpSync", "时间异常, 继续同步")
            end
        end
    )
end

ntp.setServers(timeServer)
sys.timerStart(ntp.timeSync, 1000 * 10, 1)
sys.timerLoopStart(ntpSyncTask, 1000 * 20)
