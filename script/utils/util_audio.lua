module(..., package.seeall)

function play(priority, type, path, vol, cbFnc, dup, dupInterval)
    if cc.anyCallExist() then
        log.info("util_audio.play", "正在通话中, 不播放")
        return
    end
    if vol == nil then
        vol = nvm.get("AUDIO_VOLUME") or 1
    end
    if vol == 0 then
        log.info("util_audio.play", "音量为 0, 不播放")
        return
    end
    audio.play(priority, type, path, vol, cbFnc, dup, dupInterval)
end

function audioStream(path, callback)
    if callback == nil then
        callback = function()
        end
    end

    sys.taskInit(function()
        while true do
            streamType = audiocore.AMR
            log.info("util_audio.audioStream", "AudioStreamPlay Start", streamType)

            local fileHandle = io.open(path, "rb")
            if not fileHandle then
                log.error("util_audio.audioStream", "Open file error")
                return callback(false)
            end

            while true do
                local data = fileHandle:read(1024)
                if not data then
                    fileHandle:close()
                    while audiocore.streamremain() ~= 0 do
                        sys.wait(20)
                    end
                    sys.wait(20)
                    audiocore.stop() -- 添加 audiocore.stop() 接口, 否则再次播放会播放不出来
                    log.warn("util_audio.audioStream", "AudioStreamPlay Over")
                    return callback(true)
                end

                local data_len = string.len(data)
                local curr_len = 1
                while true do
                    if not cc.anyCallExist() then
                        log.warn("util_audio.audioStream", "不在通话中, 停止播放")
                        audiocore.stop()
                        return callback(false)
                    end
                    curr_len = curr_len + audiocore.streamplay(streamType, string.sub(data, curr_len, -1), audiocore.PLAY_VOLTE)
                    if curr_len >= data_len then
                        break
                    elseif curr_len == 0 then
                        log.error("util_audio.audioStream", "AudioStreamPlay Error", streamType)
                        return callback(false)
                    end
                    sys.wait(10)
                end
                sys.wait(10)
            end
        end
    end)
end
