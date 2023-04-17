--- 模块功能：虚拟串口AT命令交互管理
-- @module ril
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.02.13

require "uart"
require "rtos"
require "sys"
require "log"
module(..., package.seeall)

--加载常用的全局函数至本地
local vwrite = uart.write
local vread = uart.read

--是否为透传模式，true为透传模式，false或者nil为非透传模式
--默认非透传模式
local transparentmode
--透传模式下，虚拟串口数据接收的处理函数
local rcvfunc

--执行AT命令后1分钟无反馈，判定at命令执行失败，则重启软件
local TIMEOUT = 60000*3

--AT命令的应答类型
--NORESULT：收到的应答数据当做urc通知处理，如果发送的AT命令不处理应答或者没有设置类型，默认为此类型
--NUMBERIC：纯数字类型；例如发送AT+CGSN命令，应答的内容为：862991527986589\r\nOK，此类型指的是862991527986589这一部分为纯数字类型
--SLINE：有前缀的单行字符串类型；例如发送AT+CSQ命令，应答的内容为：+CSQ: 23,99\r\nOK，此类型指的是+CSQ: 23,99这一部分为单行字符串类型
--MLINE：有前缀的多行字符串类型；例如发送AT+CMGR=5命令，应答的内容为：+CMGR: 0,,84\r\n0891683108200105F76409A001560889F800087120315123842342050003590404590D003A59\r\nOK，此类型指的是OK之前为多行字符串类型
--STRING：无前缀的字符串类型，例如发送AT+ATWMFT=99命令，应答的内容为：SUCC\r\nOK，此类型指的是SUCC
--SPECIAL：特殊类型，需要针对AT命令做特殊处理，例如CIPSEND、CIPCLOSE、CIFSR
local NORESULT, NUMBERIC, SLINE, MLINE, STRING, SPECIAL = 0, 1, 2, 3, 4, 10

--AT命令的应答类型表，预置了如下几项
local RILCMD = {
    ["+CSQ"] = 2,
    ["+CESQ"] = 2,
    ["+CGMM"] = 2,
    ["+RFTEMPERATURE"] =2,
    ["+MUID"] = 2,
    ["+CGSN"] = 1,
    ["+WISN"] = 4,
    ["+CIMI"] = 1,
    ["+ICCID"] = 2,
    ["+SIMCROSS"] = 2,
    ["+CGATT"] = 2,
    ["+CCLK"] = 2,
    ['+CNUM'] = 3,
    --["+ATWMFT"] = 4,
    ["+CMGR"] = 3,
    ["+CMGS"] = 2,
    ["+CPBF"] = 3,
    ["+CPBR"] = 3,
    ['+CLCC'] = 3,
    ["+CTFSGETID"] = 2,
    ["+CTFSDECRYPT"] = 2,
    ["+CTFSAUTH"] = 2,
    ["+CGDATA"] = 10,
    ["+CIND"] = 2,
    --["+CGDCONT"] = 3,
	["+CGACT"] = 3,
	["+CALIBINFO"] = 4,
    ["*CALINFO"] = 3,
}

--radioready：AT命令通道是否准备就绪
--delaying：执行完某些AT命令前，需要延时一段时间，才允许执行这些AT命令；此标志表示是否在延时状态
local radioready, delaying = false

--AT命令队列
local cmdqueue = {
    "ATE0",
    "AT+CMEE=0",
}
--当前正在执行的AT命令,参数,反馈回调,延迟执行时间,命令头,类型,反馈格式
local currcmd, currarg, currsp, curdelay, cmdhead, cmdtype, rspformt
--反馈结果,中间信息,结果信息
local result, interdata, respdata

--ril会出现三种情况:
--发送AT命令，收到应答
--发送AT命令，命令超时没有应答
--底层软件主动上报的通知，下文我们简称为urc
--[[
函数名：atimeout
功能  ：发送AT命令，命令超时没有应答的处理
参数  ：无
返回值：无
]]
local function atimeout()
    --重启软件
    sys.restart("ril.atimeout_" .. (currcmd or ""))
end

--[[
函数名：defrsp
功能  ：AT命令的默认应答处理。如果没有定义某个AT的应答处理函数，则会走到本函数
参数  ：
cmd：此应答对应的AT命令
success：AT命令执行结果，true或者false
response：AT命令的应答中的执行结果字符串
intermediate：AT命令的应答中的中间信息
返回值：无
]]
local function defrsp(cmd, success, response, intermediate)
    log.info("ril.defrsp", cmd, success, response, intermediate)
end

--AT命令的应答处理表
local rsptable = {}
setmetatable(rsptable, {__index = function() return defrsp end})

--自定义的AT命令应答格式表，当AT命令应答为STRING格式时，用户可以进一步定义这里面的格式
local formtab = {}

---注册某个AT命令应答的处理函数
-- @param head  此应答对应的AT命令头，去掉了最前面的AT两个字符
-- @param fnc   AT命令应答的处理函数
-- @param typ   AT命令的应答类型，取值范围NORESULT,NUMBERIC,SLINE,MLINE,STRING,SPECIAL
-- @param formt typ为STRING时，进一步定义STRING中的详细格式
-- @return bool ,成功返回true，失败false
-- @usage ril.regRsp("+CSQ", rsp)
function regRsp(head, fnc, typ, formt)
    --没有定义应答类型
    if typ == nil then
        rsptable[head] = fnc
        return true
    end
    --定义了合法应答类型
    if typ == 0 or typ == 1 or typ == 2 or typ == 3 or typ == 4 or typ == 10 then
        --如果AT命令的应答类型已存在，并且与新设置的不一致
        if RILCMD[head] and RILCMD[head] ~= typ then
            return false
        end
        --保存
        RILCMD[head] = typ
        rsptable[head] = fnc
        formtab[head] = formt
        return true
    else
        return false
    end
end



local app_rilcb=nil
--[[
函数名：setrilcb
功能  ：AT命令的应答处理(含请求结果码和非请求结果码,返回到应用层)
参数  ：无
返回值：无
]]
function setrilcb(cb)
    app_rilcb =cb
end


--[[
函数名：rsp
功能  ：AT命令的应答处理
参数  ：无
返回值：无
]]
local function rsp()
    --停止应答超时定时器
    sys.timerStopAll(atimeout)
    --如果发送AT命令时已经同步指定了应答处理函数
    if currsp then
        currsp(currcmd, result, respdata, interdata)
    --用户注册的应答处理函数表中找到处理函数
    else
        rsptable[cmdhead](currcmd, result, respdata, interdata)
    end
    --重置全局变量
    currcmd, currarg, currsp, curdelay, cmdhead, cmdtype, rspformt = nil
    result, interdata, respdata = nil
end

--[[
函数名：defurc
功能  ：urc的默认处理。如果没有定义某个urc的应答处理函数，则会走到本函数
参数  ：
data：urc内容
返回值：无
]]
local function defurc(data)
    log.info("ril.defurc", data)
end

--urc的处理表
local urctable = {}
setmetatable(urctable, {__index = function() return defurc end})

--- 注册某个urc的处理函数
-- @param prefix    urc前缀，最前面的连续字符串，包含+、大写字符、数字的组合
-- @param handler   urc的处理函数
-- @return 无
-- @usage ril.regUrc("+CREG", neturc)
function regUrc(prefix, handler)
    urctable[prefix] = handler
end

--- 解注册某个urc的处理函数
-- @param prefix    urc前缀，最前面的连续字符串，包含+、大写字符、数字的组合
-- @return 无
-- @usage deRegUrc("+CREG")
function deRegUrc(prefix)
    urctable[prefix] = nil
end

--“数据过滤器”，虚拟串口收到的数据时，首先需要调用此函数过滤处理一下
local urcfilter

--[[
函数名：urc
功能  ：urc处理
参数  ：
data：urc数据
返回值：无
]]
local function urc(data)
    --AT通道准备就绪
    if data == "RDY" then
        radioready = true
    else
        local prefix = string.match(data, "([%+%^%*]*[%u%d& ]+)")
        --执行prefix的urc处理函数，返回数据过滤器
        urcfilter = urctable[prefix](data, prefix)
    end
end

--[[
函数名：procatc
功能  ：处理虚拟串口收到的数据
参数  ：
data：收到的数据
返回值：无
]]
local function procatc(data)
    --if data:match("^%+EEMLTEINTER") or data:match("^%+EEMLTEINTRA") or data:match("^%+EEMUMTSINTER") or data:match("^%+EEMUMTSINTRA") then return end
    -- log.info("ril.proatc", data)
    --如果命令的应答是多行字符串格式
    if interdata and cmdtype == MLINE then
        --不出现OK\r\n，则认为应答还未结束
        if data ~= "OK\r\n" then
            --去掉最后的\r\n
            if string.find(data, "\r\n", -2) then
                data = string.sub(data, 1, -3)
            end
            --拼接到中间数据
            interdata = interdata .. "\r\n" .. data
            return
        end
    end
    --如果存在“数据过滤器”
    if urcfilter then
        data, urcfilter = urcfilter(data)
    end
    --去掉最后的\r\n
    if string.find(data, "\r\n", -2) then
        data = string.sub(data, 1, -3)
    end
    --数据为空
    if data == "" then
        return
    end

    if data:match("^%+EEMLTEINTER") or data:match("^%+EEMLTEINTRA") or data:match("^%+EEMUMTSINTER") or data:match("^%+EEMUMTSINTRA") then
        
    else
        log.info("ril.proatc", data)
    end

    --当前无命令在执行则判定为urc
    if currcmd == nil then
        urc(data)
        return
    end

    local isurc = false

    --一些特殊的错误信息，转化为ERROR统一处理
    if data:match("^%+CMS ERROR:") or data:match("^%+CME ERROR:") then
        data = "ERROR"
    end
    --执行成功的应答
    if data == "OK" or data == "SHUT OK" then
        result = true
        respdata = data
    --执行失败的应答
    elseif data == "ERROR" or data == "NO ANSWER" or data == "NO DIALTONE" then
        result = false
        respdata = data
    --需要继续输入参数的AT命令应答
    elseif data == "> " then
        --发送短信
        if cmdhead == "+CMGS" then
            log.info("ril.procatc.send", currarg)
            vwrite(uart.ATC, currarg, "\026")
        else
            log.error("error promot cmd:", currcmd)
        end
    else
        --无类型
        if cmdtype == NORESULT then
            isurc = true
        --全数字类型
        elseif cmdtype == NUMBERIC then
            local numstr = data:match("(%x+)")
            if numstr == data then
                interdata = data
            else
                isurc = true
            end
        --字符串类型
        elseif cmdtype == STRING then
            --进一步检查格式
            if data:match(rspformt or "^.+$") and not data:match("^%+CPIN:") then
                interdata = data
            else
                isurc = true
            end
        elseif cmdtype == SLINE or cmdtype == MLINE then
            if interdata == nil and string.find(data, cmdhead) == 1 then
                interdata = data
            else
                isurc = true
            end
        --CGDATA 返回CONNECT或者ERROR
        elseif cmdhead == "+CGDATA" then
            if string.find(data, "CONNECT") == 1 then
                result = true
                respdata = data
            else
                isurc = true
            end
        else
            isurc = true
        end
    end
    --urc处理
    if isurc then
        urc(data)
    --应答处理
    elseif result ~= nil then
        rsp()
    end
end

--是否在读取虚拟串口数据
local readat = false

--[[
函数名：getcmd
功能  ：解析一条AT命令
参数  ：
item：AT命令
返回值：当前AT命令的内容
]]
local function getcmd(item)
    local cmd, arg, rsp, delay
    --命令是string类型
    if type(item) == "string" then
        --命令内容
        cmd = item
    --命令是table类型
    elseif type(item) == "table" then
        --命令内容
        cmd = item.cmd
        --命令参数
        arg = item.arg
        --命令应答处理函数
        rsp = item.rsp
        --命令延时执行时间
        delay = item.delay
    else
        log.info("ril.getcmd", "getpack unknown item")
        return
    end
    --命令前缀
    local head = string.match(cmd, "AT([%+%*%^]*%u+)")

    if head == nil then
        log.error("ril.getcmd", "request error cmd:", cmd)
        return
    end
    --这两个命令必须有参数
    if head == "+CMGS" or head == "+CIPSEND" then -- 必须有参数
        if arg == nil or arg == "" then
            log.error("ril.getcmd", "request error no arg", head)
            return
        end
    end

    --赋值全局变量
    currcmd = cmd
    currarg = arg
    currsp = rsp
    curdelay = delay
    cmdhead = head
    cmdtype = RILCMD[head] or NORESULT
    rspformt = formtab[head]

    return currcmd
end

--[[
函数名：sendat
功能  ：发送AT命令
参数  ：无
返回值：无
]]
local function sendat()
    --AT通道未准备就绪、正在读取虚拟串口数据、有AT命令在执行或者队列无命令、正延时发送某条AT
    if not radioready or readat or currcmd ~= nil or delaying then
        return
    end

    local item

    while true do
        --队列无AT命令
        if #cmdqueue == 0 then
            return
        end
        --读取第一条命令
        item = table.remove(cmdqueue, 1)
        --解析命令
        getcmd(item)
        --需要延迟发送
        if curdelay then
            --启动延迟发送定时器
            sys.timerStart(delayfunc, curdelay)
            --清除全局变量
            currcmd, currarg, currsp, curdelay, cmdhead, cmdtype, rspformt = nil
            item.delay = nil
            --设置延迟发送标志
            delaying = true
            --把命令重新插入命令队列的队首
            table.insert(cmdqueue, 1, item)
            return
        end

        if currcmd ~= nil then
            break
        end
    end
    --启动AT命令应答超时定时器
    sys.timerStart(atimeout, TIMEOUT)

    log.info("ril.sendat", currcmd)
    --向虚拟串口中发送AT命令
    if currcmd:match("^AT%+POC=") then
        vwrite(uart.ATC, currcmd .. "\r\n")
    else
        vwrite(uart.ATC, currcmd .. "\r")
    end
end

-- 延时执行某条AT命令的定时器回调
-- @return 无
-- @usage ril.delayfunc()
function delayfunc()
    --清除延时标志
    delaying = nil
    --执行AT命令发送
    sendat()
end

--[[
函数名：atcreader
功能  ：“AT命令的虚拟串口数据接收消息”的处理函数，当虚拟串口收到数据时，会走到此函数中
参数  ：无
返回值：无
]]
local function atcreader()
    local s

    if not transparentmode then readat = true end
    --循环读取虚拟串口收到的数据
    while true do
        --每次读取一行
        s = vread(uart.ATC, "*l", 0)
        if string.len(s) ~= 0 then
            if transparentmode then
                --透传模式下直接转发数据
                rcvfunc(s)
            else
                --非透传模式下处理收到的数据
                procatc(s)

                if app_rilcb ~=nil then app_rilcb(s)  end
            end
        else
            break
        end
    end
    if not transparentmode then
        readat = false
        --数据处理完以后继续执行AT命令发送
        sendat()
    end
end

--- 发送AT命令到底层软件
-- @param cmd   AT命令内容
-- @param arg   AT命令参数，例如AT+CMGS=12命令执行后，接下来会发送此参数；AT+CIPSEND=14命令执行后，接下来会发送此参数
-- @param onrsp AT命令应答的处理函数，只是当前发送的AT命令应答有效，处理之后就失效了
-- @param delay 延时delay毫秒后，才发送此AT命令
-- @return 无
-- @usage ril.request("AT+CENG=1,1")
-- @usage ril.request("AT+CRSM=214,28539,0,0,12,\"64f01064f03064f002fffff\"", nil, crsmResponse)
function request(cmd, arg, onrsp, delay)
    if transparentmode then return end
    --插入缓冲队列
    if arg or onrsp or delay or formt then
        table.insert(cmdqueue, {cmd = cmd, arg = arg, rsp = onrsp, delay = delay})
    else
        table.insert(cmdqueue, cmd)
    end
    --执行AT命令发送
    sendat()
end

--[[
函数名：setransparentmode
功能  ：AT命令通道设置为透传模式
参数  ：
fnc：透传模式下，虚拟串口数据接收的处理函数
返回值：无
注意：透传模式和非透传模式，只支持开机的第一次设置，不支持中途切换
]]
function setransparentmode(fnc)
    transparentmode, rcvfunc = true, fnc
end

--[[
函数名：sendtransparentdata
功能  ：透传模式下发送数据
参数  ：
data：数据
返回值：成功返回true，失败返回nil
]]
function sendtransparentdata(data)
    if not transparentmode then return end
    vwrite(uart.ATC, data)
    return true
end

--注册“AT命令的虚拟串口数据接收消息”的处理函数
uart.on(uart.ATC, "receive", atcreader)
