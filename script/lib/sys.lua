--- 模块功能：Luat协程调度框架
-- @module sys
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.9.13
require "utils"
require "log"
require "patch"
module(..., package.seeall)

-- lib脚本版本号，只要lib中的任何一个脚本做了修改，都需要更新此版本号
SCRIPT_LIB_VER = "2.4.3"

-- TaskID最大值
local TASK_TIMER_ID_MAX = 0x1FFFFFFF
-- msgId 最大值(请勿修改否则会发生msgId碰撞的危险)
local MSG_TIMER_ID_MAX = 0x7FFFFFFF

-- 任务定时器id
local taskTimerId = 0
-- 消息定时器id
local msgId = TASK_TIMER_ID_MAX
-- 定时器id表
local timerPool = {}
local taskTimerPool = {}
--消息定时器参数表
local para = {}
--定时器是否循环表
local loop = {}


-- 启动GSM协议栈。例如在充电开机未启动GSM协议栈状态下，如果用户长按键正常开机，此时调用此接口启动GSM协议栈即可
-- @return 无
-- @usage sys.powerOn()
function powerOn()
    rtos.poweron(1)
end

--- 软件重启
-- @string r 重启原因，用户自定义，一般是string类型，重启后的trace中会打印出此重启原因
-- @return 无
-- @usage sys.restart('程序超时软件重启')
function restart(r)
    assert(r and r ~= "", "sys.restart cause null")
    if errDump and errDump.appendErr and type(errDump.appendErr) == "function" then errDump.appendErr("restart[" .. r .. "];") end
    log.warn("sys.restart", r)
    rtos.restart()
end


--- task任务延时函数
-- 只能直接或者间接的被task任务主函数调用，如果定时器创建成功，则本task会挂起
-- @number ms，延时时间，单位毫秒，最小1，最大0x7FFFFFFF
--             实际上支持的最小超时时间是5毫秒，小于5毫秒的时间都会被转化为5毫秒
-- @return result，分为如下三种情况：
--             1、如果定时器创建失败，本task不会被挂起，直接返回nil
--             2、如果定时器创建成功，本task被挂起，超时时间到达后，会激活本task，返回nil
--             3、如果定时器创建成功，本task被挂起，在超时时间到达之前，其他业务逻辑主动激活本task，
--                返回激活时携带的可变参数（如果不是故意为之，可能是写bug了）
-- @usage
-- task延时5秒：
-- sys.taskInit(function()
--     sys.wait(5000)
-- end)
function wait(ms)
    -- 参数检测，参数不能为负值
    assert(ms > 0, "The wait time cannot be negative!")
    --4G底层不支持小于5ms的定时器
    if ms < 5 then ms = 5 end
    -- 选一个未使用的定时器ID给该任务线程
    if taskTimerId >= TASK_TIMER_ID_MAX then taskTimerId = 0 end
    taskTimerId = taskTimerId + 1
    local timerid = taskTimerId
    taskTimerPool[coroutine.running()] = timerid
    timerPool[timerid] = coroutine.running()
    -- 调用core的rtos定时器
    if 1 ~= rtos.timer_start(timerid, ms) then log.debug("rtos.timer_start error") return end
    -- 挂起调用的任务线程
    local message = {coroutine.yield()}
    if #message ~= 0 then
        rtos.timer_stop(timerid)
        taskTimerPool[coroutine.running()] = nil
        timerPool[timerid] = nil
        return unpack(message)
    end
end


--- task任务条件等待函数（支持事件消息和定时器消息）
-- 只能直接或者间接的被task任务主函数调用，调用本接口的task会挂起
-- @string id，消息ID，建议使用string类型
-- @number[opt=nil] ms，延时时间，单位毫秒，最小1，最大0x7FFFFFFF
--             实际上支持的最小超时时间是5毫秒，小于5毫秒的时间都会被转化为5毫秒
-- @return result,data，分为如下三种情况：
--             1、如果存在超时时间参数：
--                (1)、在超时时间到达之前，如果收到了等待的消息ID，则result为true，data为消息ID携带的参数（可能是多个参数）
--                (2)、在超时时间到达之前，如果没收到等待的消息ID，则result为false，data为nil
--             2、如果不存在超时时间参数：如果收到了等待的消息ID，则result为true，data为消息ID携带的参数（可能是多个参数）
--                (1)、如果收到了等待的消息ID，则result为true，data为消息ID携带的参数（可能是多个参数）
--                (2)、如果没收到等待的消息ID，则task一直挂起
--             3、还存在一种特殊情况，本task挂起时，可能被task的外部应用逻辑给主动激活（如果不是故意为之，可能是写bug了）
-- @usage
-- task延时120秒或者收到"SIM_IND"消息：
-- sys.taskInit(function()
--     local result, data = sys.waitUntil("SIM_IND",120000)
-- end)
function waitUntil(id, ms)
    subscribe(id, coroutine.running())
    local message = ms and {wait(ms)} or {coroutine.yield()}
    unsubscribe(id, coroutine.running())
    return message[1] ~= nil, unpack(message, 2, #message)
end

--- Task任务的条件等待函数扩展（包括事件消息和定时器消息等条件），只能用于任务函数中。
-- @param id 消息ID
-- @number ms 等待超时时间，单位ms，最大等待126322567毫秒
-- @return message 接收到消息返回message，超时返回false
-- @return data 接收到消息返回消息参数
-- @usage result, data = sys.waitUntilExt("SIM_IND", 120000)
function waitUntilExt(id, ms)
    subscribe(id, coroutine.running())
    local message = ms and {wait(ms)} or {coroutine.yield()}
    unsubscribe(id, coroutine.running())
    if message[1] ~= nil then return unpack(message) end
    return false
end

--- 创建一个任务并且运行该任务
-- @param fun 任务主函数，激活task时使用
-- @param ... 任务主函数fun的可变参数
-- @return co  返回该任务的线程ID
-- @usage sys.taskInit(task1,'a','b')
function taskInit(fun, ...)
    local co = coroutine.create(fun)
    coroutine.resume(co, ...)
    return co
end

--- Luat平台初始化
-- @param mode 充电开机是否启动GSM协议栈，1不启动，否则启动
-- @param lprfnc 用户应用脚本中定义的“低电关机处理函数”，如果有函数名，则低电时，本文件中的run接口不会执行任何动作，否则，会延时1分钟自动关机
-- @return 无
-- @usage sys.init(1,0)
function init(mode, lprfnc)
    -- 用户应用脚本中必须定义PROJECT和VERSION两个全局变量，否则会死机重启，如何定义请参考各个demo中的main.lua
    assert(PROJECT and PROJECT ~= "" and VERSION and VERSION ~= "", "Undefine PROJECT or VERSION")
    collectgarbage("setpause", 80)

    -- 设置AT命令的虚拟串口
    uart.setup(uart.ATC, 0, 0, uart.PAR_NONE, uart.STOP_1)
    log.info("poweron reason:", rtos.poweron_reason(), PROJECT, VERSION, SCRIPT_LIB_VER, rtos.get_version())
    pcall(rtos.set_lua_info,"\r\n"..rtos.get_version().."\r\n"..(_G.PROJECT or "NO PROJECT").."\r\n"..(_G.VERSION or "NO VERSION"))
    if type(rtos.get_build_time)=="function" then log.info("core build time", rtos.get_build_time()) end
    if mode == 1 then
        -- 充电开机
        if rtos.poweron_reason() == rtos.POWERON_CHARGER then
            -- 关闭GSM协议栈
            rtos.poweron(0)
        end
    end
end

------------------------------------------ rtos消息回调处理部分 ------------------------------------------
--[[
函数名：cmpTable
功能  ：比较两个table的内容是否相同，注意：table中不能再包含table
参数  ：
t1：第一个table
t2：第二个table
返回值：相同返回true，否则false
]]
local function cmpTable(t1, t2)
    if not t2 then return #t1 == 0 end
    if #t1 == #t2 then
        for i = 1, #t1 do
            if unpack(t1, i, i) ~= unpack(t2, i, i) then
                return false
            end
        end
        return true
    end
    return false
end

--- 关闭sys.timerStart和sys.timerLoopStart创建的定时器
-- 有两种方式可以唯一标识一个定时器：
-- 1、定时器ID
-- 2、定时器回调函数和可变参数
-- @param val，有两种形式：
--             1、为number类型时，表示定时器ID
--             2、为function类型时，表示定时器回调函数
-- @param ... 可变参数，当val为定时器回调函数时，此可变参数才有意义，表示定时器回调函数的可变回调参数
-- @return nil
-- @usage
-- 通过定时器ID关闭一个定时器：
-- local timerId = sys.timerStart(publicTimerCbFnc,8000,"second")
-- sys.timerStop(timerId)
-- 通过定时器回调函数和可变参数关闭一个定时器：
-- sys.timerStart(publicTimerCbFnc,8000,"first")
-- sys.timerStop(publicTimerCbFnc,"first")
function timerStop(val, ...)
    -- val 为定时器ID
	local arg={ ... }
    if type(val) == 'number' then
        timerPool[val], para[val], loop[val] = nil
        rtos.timer_stop(val)
    else
        for k, v in pairs(timerPool) do
            -- 回调函数相同
            if type(v) == 'table' and v.cb == val or v == val then
                -- 可变参数相同
                if cmpTable(arg, para[k]) then
                    rtos.timer_stop(k)
                    timerPool[k], para[k], loop[val] = nil
                    break
                end
            end
        end
    end
end

--- 关闭sys.timerStart和sys.timerLoopStart创建的某个回调函数的所有定时器
-- @function fnc， 定时器回调函数
-- @return nil
-- @usage 
-- 关闭回调函数为publicTimerCbFnc的所有定时器
-- local function publicTimerCbFnc(tag)
--     log.info("publicTimerCbFnc",tag)
-- end
-- 
-- sys.timerStart(publicTimerCbFnc,8000,"first")
-- sys.timerStart(publicTimerCbFnc,8000,"second")
-- sys.timerStart(publicTimerCbFnc,8000,"third")

-- sys.timerStopAll(publicTimerCbFnc)
function timerStopAll(fnc)
    for k, v in pairs(timerPool) do
        if type(v) == "table" and v.cb == fnc or v == fnc then
            rtos.timer_stop(k)
            timerPool[k], para[k], loop[k] = nil
        end
    end
end

--- 创建并且启动一个单次定时器
-- 有两种方式可以唯一标识一个定时器：
-- 1、定时器ID
-- 2、定时器回调函数和可变参数
-- @param fnc 定时器回调函数，必须存在，不允许为nil
--            当定时器超时时间到达时，回调函数的调用形式为fnc(...)，其中...为回调参数
-- @number ms 定时器超时时间，单位毫秒，最小1，最大0x7FFFFFFF
--                                      实际上支持的最小超时时间是5毫秒，小于5毫秒的时间都会被转化为5毫秒
-- @param ... 可变参数，回调函数fnc的回调参数
-- @return number timerId，创建成功返回定时器ID；创建失败返回nil
-- @usage
-- 创建一个5秒的单次定时器，回调函数打印"timerCb"，没有可变参数：
-- sys.timerStart(function() log.info("timerCb") end, 5000)
-- 创建一个5秒的单次定时器，回调函数打印"timerCb"和"test"，可变参数为"test"：
-- sys.timerStart(function(tag) log.info("timerCb",tag) end, 5000, "test")
function timerStart(fnc, ms, ...)
    --回调函数和时长检测
	local arg={ ... }
	local argcnt=0
	for i, v in pairs(arg) do
		argcnt = argcnt+1
	end
    assert(fnc ~= nil, "sys.timerStart(first param) is nil !")
    assert(ms > 0, "sys.timerStart(Second parameter) is <= zero !")
    --4G底层不支持小于5ms的定时器
    if ms < 5 then ms = 5 end
    -- 关闭完全相同的定时器
    if argcnt == 0 then
        timerStop(fnc)
    else
        timerStop(fnc, ...)
    end
    -- 为定时器申请ID，ID值 1-0X1FFFFFFF 留给任务，0X1FFFFFFF-0x7FFFFFFF留给消息专用定时器
    while true do
        if msgId >= MSG_TIMER_ID_MAX then msgId = TASK_TIMER_ID_MAX end
        msgId = msgId + 1
        if timerPool[msgId] == nil then
            timerPool[msgId] = fnc
            break
        end
    end
    --调用底层接口启动定时器
    if rtos.timer_start(msgId, ms) ~= 1 then log.debug("rtos.timer_start error") return end
    --如果存在可变参数，在定时器参数表中保存参数
    if argcnt ~= 0 then
        para[msgId] = arg
    end
    --返回定时器id
    return msgId
end

--- 创建并且启动一个循环定时器
-- 有两种方式可以唯一标识一个定时器：
-- 1、定时器ID
-- 2、定时器回调函数和可变参数
-- @param fnc 定时器回调函数，必须存在，不允许为nil
--            当定时器超时时间到达时，回调函数的调用形式为fnc(...)，其中...为回调参数
-- @number ms 定时器超时时间，单位毫秒，最小1，最大0x7FFFFFFF
--                                      实际上支持的最小超时时间是5毫秒，小于5毫秒的时间都会被转化为5毫秒
-- @param ... 可变参数，回调函数fnc的回调参数
-- @return number timerId，创建成功返回定时器ID；创建失败返回nil
-- @usage
-- 创建一个5秒的循环定时器，回调函数打印"timerCb"，没有可变参数：
-- sys.timerLoopStart(function() log.info("timerCb") end, 5000)
-- 创建一个5秒的循环定时器，回调函数打印"timerCb"和"test"，可变参数为"test"：
-- sys.timerLoopStart(function(tag) log.info("timerCb",tag) end, 5000, "test")
function timerLoopStart(fnc, ms, ...)
    local tid = timerStart(fnc, ms, ...)
    if tid then loop[tid] = (ms<5 and 5 or ms) end
    return tid
end

--- 判断“通过timerStart或者timerLoopStart创建的定时器”是否处于激活状态
-- @param val，定时器标识，有两种表示形式
--                         1、number类型，通过timerStart或者timerLoopStart创建定时器时返回的定时器ID，此情况下，不需要传入回调参数...就能唯一标识一个定时器
--                         2、function类型，通过timerStart或者timerLoopStart创建定时器时的回调函数，此情况下，如果存在回调参数，需要传入回调参数...才能唯一标识一个定时器
-- @param ... 回调参数，和“通过timerStart或者timerLoopStart创建定时器”的回调参数保持一致
-- @return status，定时器激活状态；根据val的表示形式，有不同的返回值：
--                         1、val为number类型时：如果处于激活状态，则返回function类型的定时器回调函数；否则返回nil
--                         2、val为function类型时：如果处于激活状态，则返回bool类型的true；否则返回nil
-- @usage
-- 定时器ID形式标识定时器的使用参考：
-- local timerId1 = sys.timerStart(function() end,5000)
-- 
-- sys.taskInit(function()
--     sys.wait(3000)
--     log.info("after 3 senonds, timerId1 isActive?",sys.timerIsActive(timerId1))
--     
--     sys.wait(3000)
--     log.info("after 6 senonds, timerId1 isActive?",sys.timerIsActive(timerId1))
-- end)
--
--
-- 回调函数和回调参数标识定时器的使用参考：
-- local function timerCbFnc2(tag)
--     log.info("timerCbFnc2",tag)
-- end
-- 
-- sys.timerStart(timerCbFnc2,5000,"test")
-- 
-- sys.taskInit(function()
--     sys.wait(3000)
--     log.info("after 3 senonds, timerCbFnc2 test isActive?",sys.timerIsActive(timerCbFnc2,"test"))
--     
--     sys.wait(3000)
--     log.info("after 6 senonds, timerCbFnc2 test isActive?",sys.timerIsActive(timerCbFnc2,"test"))
-- end)
function timerIsActive(val, ...)
	local arg={ ... }
    if type(val) == "number" then
        return timerPool[val]
    else
        for k, v in pairs(timerPool) do
            if v == val then
                if cmpTable(arg, para[k]) then return true end
            end
        end
    end
end


------------------------------------------ LUA应用消息订阅/发布接口 ------------------------------------------
-- 订阅者列表
local subscribers = {}
--内部消息队列
local messageQueue = {}

--- 订阅消息
-- @param id 消息id
-- @param callback 消息回调处理
-- @usage subscribe("NET_STATUS_IND", callback)
function subscribe(id, callback)
    if type(id) ~= "string" or (type(callback) ~= "function" and type(callback) ~= "thread") then
        log.warn("warning: sys.subscribe invalid parameter", id, callback)
        return
    end
    if not subscribers[id] then subscribers[id] = {count = 0} end
    if not subscribers[id][callback] then
        subscribers[id].count = subscribers[id].count + 1
        subscribers[id][callback] = true
    end
end

--- 取消订阅消息
-- @param id 消息id
-- @param callback 消息回调处理
-- @usage unsubscribe("NET_STATUS_IND", callback)
function unsubscribe(id, callback)
    if type(id) ~= "string" or (type(callback) ~= "function" and type(callback) ~= "thread") then
        log.warn("warning: sys.unsubscribe invalid parameter", id, callback)
        return
    end
    -- 取消订阅时将对应取消的函数赋值为false，不能直接赋值为nil，否则可能触发lua invalid key to 'next'异常
    if subscribers[id] then
        if subscribers[id][callback] then
            subscribers[id].count = subscribers[id].count - 1
            subscribers[id][callback] = false
        end
    end
end

--- 发布内部消息，存储在内部消息队列中
-- @param ... 可变参数，用户自定义
-- @return 无
-- @usage publish("NET_STATUS_IND")
function publish(...)
	local arg = { ... }
    table.insert(messageQueue, arg)
end

-- 分发消息
local function dispatch()
    while true do
        if #messageQueue == 0 then
            -- 当在同一个task内sys.waitUntil()不同的消息，并且没有任何消息publish时，会造成内存泄漏。
            -- 例如：sys.waitUntil("1", 500)、sys.waitUntil("2", 500)、...、sys.waitUntil("n", 500)
            for k, v in pairs(subscribers) do
                if v.count == 0 then subscribers[k] = nil end
            end
            break
        end
        local message = table.remove(messageQueue, 1)
        if subscribers[message[1]] then
            for callback, flag in pairs(subscribers[message[1]]) do
                if flag then
                    if type(callback) == "function" then
                        callback(unpack(message, 2, #message))
                    elseif type(callback) == "thread" then
                        coroutine.resume(callback, unpack(message))
                    end
                end
            end
            -- 当某个subscribe的消息的回调取消订阅时，在这里将它赋值为nil，回收内存
            if subscribers[message[1]] then
                for callback, flag in pairs(subscribers[message[1]]) do
                    if not flag then
                        subscribers[message[1]][callback] = nil
                    end
                end
                --当所有subscribe消息的回调都取消订阅时，在这里清空对应消息的表，回收内存
                if subscribers[message[1]].count == 0 then
                    subscribers[message[1]] = nil
                end
            end
        end
    end
end

-- rtos消息回调
local handlers = {}
setmetatable(handlers, {__index = function() return function() end end, })

--- 注册rtos消息回调处理函数
-- @number id 消息类型id
-- @param handler 消息处理函数
-- @return 无
-- @usage rtos.on(rtos.MSG_KEYPAD, function(param) handle keypad message end)
rtos.on = function(id, handler)
    handlers[id] = handler
end

------------------------------------------ Luat 主调度框架  ------------------------------------------
--- run()从底层获取core消息并及时处理相关消息，查询定时器并调度各注册成功的任务线程运行和挂起
-- @return 无
-- @usage sys.run()
function run()
    while true do
        -- 分发内部消息
        dispatch()
        -- 阻塞读取外部消息
        local msg, param = rtos.receive(rtos.INF_TIMEOUT)
        -- 判断是否为定时器消息，并且消息是否注册
        if msg == rtos.MSG_TIMER and timerPool[param] then
            if param <= TASK_TIMER_ID_MAX then
                local taskId = timerPool[param]
                timerPool[param] = nil
                if taskTimerPool[taskId] == param then
                    taskTimerPool[taskId] = nil
                    coroutine.resume(taskId)
                end
            else
                local cb = timerPool[param]
                --如果不是循环定时器，从定时器id表中删除此定时器
                if not loop[param] then timerPool[param] = nil end
                if para[param] ~= nil then
                    cb(unpack(para[param]))
                    if not loop[param] then para[param] = nil end
                else
                    cb()
                end
                --如果是循环定时器，继续启动此定时器
                if loop[param] then rtos.timer_start(param, loop[param]) end
            end
        --其他消息（音频消息、充电管理消息、按键消息等）
        elseif type(msg) == "number" then
            handlers[msg](param)
        else
            handlers[msg.id](msg)
        end
    end
end

require "clib"

if type(rtos.openSoftDog)=="function" then
    rtos.openSoftDog(60000)
    sys.timerLoopStart(rtos.eatSoftDog,20000)
end
