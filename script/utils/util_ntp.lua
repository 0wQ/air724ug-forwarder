module(..., package.seeall)

-- 同步时间, 上传录音文件需要正确的时间作为路径名
function sync()
    -- 如果时间正常, 则不同步, 并删除定时器
    if os.date("*t").year >= 2023 then
        log.info("util_ntp.sync", "时间正常, 无需同步")
        sys.timerStopAll(sync)
        return
    end
    log.info("util_ntp.sync", "开始同步")
    ntp.timeSync(1, function(time, result)
        if result and time.year >= 2023 then
            log.info("util_ntp.sync", "同步完成, 时间正常")
            sys.timerStopAll(sync)
            return
        end
        log.info("util_ntp.sync", "同步完成, 时间异常")
    end)
end
