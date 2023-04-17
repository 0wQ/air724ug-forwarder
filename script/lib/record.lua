--- 模块功能：录音处理
-- @module record
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.11.23

require "log"
require "ril"
module(..., package.seeall)


local FILE = '/record.amr'
local recordType = "FILE"
local recording,stoping,recordCb,stopCbFnc

--- 开始录音
-- @number seconds，录音时长，单位：秒
--     流录音模式下，如果想长时间录音，可以将此参数设置为0x7FFFFFFF，相当于录音2147483647秒=24855天
-- @function[opt=nil] cbFnc，录音回调函数：
--     当type参数为"FILE"时，回调函数的调用形式为：
--         cbFnc(result,size)
--               result：录音结果，true表示成功，false或者nil表示失败
--               size：number类型，录音文件的大小，单位是字节，在result为true时才有意义
--     当type参数为"STREAM"时，回调函数的调用形式为：
--         cbFnc(result,size,tag)
--               result：录音结果，true表示成功，false或者nil表示失败
--               size：number类型，每次上报的录音数据流的大小，单位是字节，在result为true时才有意义
--               tag：string类型，"STREAM"表示录音数据流通知，"END"表示录音结束
-- @string[opt="FILE"] type，录音模式
--     "FILE"表示文件录音模式，录音数据自动保存在文件中，录音结束后，执行一次cbFnc函数
--     "STREAM"表示流录音模式，录音数据保存在内存中，每隔一段时间执行一次cbFnc函数去读取录音数据流，录音结束后再执行一次cbFnc函数
-- @number[opt=1] quality，录音质量，0：一般质量 1：中等质量 2：高质量 3：无损质量
-- @number[opt=2] rcdType，录音类型 n:1:mic 2:voice 3:voice_dual
-- @number[opt=3] format，录音格式，1:pcm 2:wav 3:amrnb 4:speex
--      pcm格式：录音质量参数无效，采样率：8000，单声道，采样精度：16 bit，5秒钟录音80KB左右
--      wav格式：录音质量参数无效，比特率：128kbps，5秒钟录音80KB左右
--      amrnb格式：录音质量参数有效
--                 录音质量为0时：比特率：5.15kbps，5秒钟录音3KB多
--                 录音质量为1时：比特率：6.70kbps，5秒钟录音4KB多
--                 录音质量为2时：比特率：7.95kbps，5秒钟录音4KB多
--                 录音质量为3时：比特率：12.2kbps，5秒钟录音7KB多
--      speex格式：录音质量参数无效，pcm格式128kbps后的压缩格式，5秒钟6KB左右
-- @number[opt=nil] streamRptLen，流录音时，每次上报的字节阀值
-- @usage 
-- 文件录音模式，录音5秒，一般质量，amrnb格式，录音结束后执行cbFnc函数：
-- record.start(5,cbFnc)
-- 流录音模式，录音5秒，一般质量，amrnb格式，每隔一段时间执行一次cbFnc函数，录音结束后再执行一次cbFnc函数：
-- record.start(5,cbFnc,"STREAM")
-- 流录音模式，录音5秒，一般质量，amrnb格式，每产生500字节的录音数据执行一次cbFnc函数，录音结束后再执行一次cbFnc函数：
-- record.start(5,cbFnc,"STREAM",nil,nil,500)
function start(seconds, cbFnc, type, quality, rcdType,format, streamRptLen)
    if recording or stoping or seconds <= 0 or ((type~="STREAM") and seconds>50) then
        log.error('record.start', recording, stoping, seconds)
        if cbFnc then cbFnc() end
        return
    end
    delete()

    recordType = type or "FILE"
    if type=="STREAM" then
        --param1: 录音时长 n:单位秒
        --param2: 录音质量 n:0：一般质量 1：中等质量 2：高质量 3：无损质量
        --param3：录音类型 n:1:mic 2:voice 3:voice_dual
        --param4：录音文件类型 n: 1:pcm 2:wav 3:amrnb
        audiocore.streamrecord(seconds,quality or 1,rcdType or 1,format or 3,streamRptLen)
    else
        --param1: 录音保存文件
        --param2: 录音时长 n:单位秒
        --param3: 录音质量 n:0：一般质量 1：中等质量 2：高质量 3：无损质量
        --param4：录音类型 n:1:mic 2:voice 3:voice_dual
        --param5：录音文件类型 n: 1:pcm 2:wav 3:amrnb
        audiocore.record(FILE,seconds,quality or 1,rcdType or 1,format or 3)
    end
    log.info("record.start",seconds,recordType,format or 3)
    recording = true
    recordCb = cbFnc
    return true
end

--- 停止录音
-- @function[opt=nil] cbFnc，停止录音的回调函数(停止结果通过此函数通知用户)，回调函数的调用形式为：
--      cbFnc(result)
--      result：number类型
--              0表示停止成功
--              1表示之前已经发送了停止动作，请耐心等待停止结果的回调
-- @usage record.stop(cb)
function stop(cbFnc)
    if not recording then
        if cbFnc then cbFnc(0) end
        return
    end
    if stoping then
        if cbFnc then cbFnc(1) end
        return
    end
    stopCbFnc = cbFnc
    log.info("record.stop")
    audiocore.stoprecord()
    stoping = true
end

--- 读取录音文件的完整路径
-- @return string 录音文件的完整路径
-- @usage filePath = record.getFilePath()
function getFilePath()
    return FILE
end

--- 读取录音数据
-- @param offset 偏移位置
-- @param len 长度
-- @return data 录音数据
-- @usage data = record.getData(0, 1024)
function getData(offset, len)
    local f = io.open(FILE, "rb")
    if not f then log.error('record.getData', 'open failed') return "" end
    if not f:seek("set", offset) then log.error('record.getData', 'seek failed') f:close() return "" end
    local data = f:read(len)
    f:close()
    log.info("record.getData", data and data:len() or 0)
    return data or ""
end

--- 读取录音文件总长度，录音时长
-- @return fileSize 录音文件大小
-- @return duration 录音时长
-- @usage fileSize, duration = record.getSize()
function getSize()
    local size,duration = io.fileSize(FILE),0
    if size>6 then
        duration = ((size-6)-((size-6)%1600))/1600
    end
    return size, duration
end

--- 删除录音
-- @usage record.delete()
function delete()
    log.info("record.delete")
    audiocore.deleterecord()
    os.remove(FILE)
end

--- 判断是否存在录音
-- @return result true - 有录音 false - 无录音
-- @usage result = record.exists()
function exists()
    return io.exists(FILE)
end

--- 是否正在处理录音
-- @return result true - 正在处理 false - 空闲
-- @usage result = record.isBusy()
function isBusy()
    return recording or stoping
end


rtos.on(rtos.MSG_RECORD,function(msg)
    log.info("record.MSG_RECORD",msg.record_end_ind,msg.record_error_ind,recordType)
    --文件录音，在回调时可以删除录音buf；但是流录音，一定要等buf读取完成后，再删除
    if recordType=="FILE" then audiocore.deleterecord() end
    if msg.record_error_ind then
        delete()
        if recordCb then recordCb(false,0,"END") recordCb = nil end
        recording = false
        stoping = false
        if stopCbFnc then stopCbFnc(0) stopCbFnc=nil end
    end
    if msg.record_end_ind then
        if recordCb then recordCb(true,recordType=="FILE" and io.fileSize(FILE) or 0,"END") recordCb = nil end
        recording = false
        stoping = false
        if stopCbFnc then stopCbFnc(0) stopCbFnc=nil end
    end
end)

rtos.on(rtos.MSG_STREAM_RECORD,function(msg)
    log.info("record.MSG_STREAM_RECORD",msg.wait_read_len)
    if recordCb then recordCb(true,msg.wait_read_len,"STREAM") end
end)

