--- 模块功能：数据链路激活、SOCKET管理(创建、连接、数据收发、状态维护)
-- @module socket
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.9.25
require "link"
require "utils"
module(..., package.seeall)

local sockets = {}
-- 单次发送数据最大值
local SENDSIZE = 11200
-- 缓冲区最大下标
local INDEX_MAX = 256
-- 是否有socket正处在链接
local socketsConnected = 0
--- SOCKET 是否有可用
-- @return 可用true,不可用false
-- socket4G.isReady = link.isReady

local function errorInd(error)
    local coSuspended = {}
    
    for _, c in pairs(sockets) do -- IP状态出错时，通知所有已连接的socket
        c.error = error
        --不能打开如下3行代码，IP出错时，会通知每个socket，socket会主动close
        --如果设置了connected=false，则主动close时，直接退出，不会执行close动作，导致core中的socket资源没释放
        --会引发core中socket耗尽以及socket id重复的问题
        --c.connected = false
        --socketsConnected = c.connected or socketsConnected
        --if error == 'CLOSED' then sys.publish("SOCKET_ACTIVE", socketsConnected) end
        if c.co and coroutine.status(c.co) == "suspended" then
            --coroutine.resume(c.co, false)
            table.insert(coSuspended, c.co)
        end
    end
    
    for k, v in pairs(coSuspended) do
        if v and coroutine.status(v) == "suspended" then
            coroutine.resume(v, false, error)
        end
    end
end

sys.subscribe("IP_ERROR_IND", function()errorInd('IP_ERROR_IND') end)
--sys.subscribe('IP_SHUT_IND', function()errorInd('CLOSED') end)
-- 创建socket函数
local mt = {}
mt.__index = mt
local function socket(protocol, cert, tCoreExtPara)
    local ssl = protocol:match("SSL")
    local co = coroutine.running()
    if not co then
        log.warn("socket.socket: socket must be called in coroutine")
        return nil
    end
    -- 实例的属性参数表
    local o = {
        id = nil,
        protocol = protocol,
        tCoreExtPara = tCoreExtPara,
        ssl = ssl,
        cert = cert,
        co = co,
        input = {},
        output = {},
        wait = "",
        connected = false,
        iSubscribe = false,
        subMessage = nil,
        isBlock = false,
        msg = nil,
        rcvProcFnc = nil,
    }
    return setmetatable(o, mt)
end

--- 创建基于TCP的socket对象
-- @bool[opt=nil] ssl，是否为ssl连接，true表示是，其余表示否
-- @table[opt=nil] cert，ssl连接需要的证书配置，只有ssl参数为true时，此参数才有意义，cert格式如下：
-- {
--     caCert = "ca.crt", --CA证书文件(Base64编码 X.509格式)，如果存在此参数，则表示客户端会对服务器的证书进行校验；不存在则不校验
--     clientCert = "client.crt", --客户端证书文件(Base64编码 X.509格式)，服务器对客户端的证书进行校验时会用到此参数
--     clientKey = "client.key", --客户端私钥文件(Base64编码 X.509格式)
--     clientPassword = "123456", --客户端证书文件密码[可选]
--     insist = 1, --证书中的域名校验失败时，是否坚持连接，默认为1，坚持连接，0为不连接
-- }
-- @number[opt=nil] tCoreExtPara, 建立链接扩展参数
-- {
--     rcvBufferSize = "num" --接收缓冲区大小，默认为0
-- }
-- @return client，创建成功返回socket客户端对象；创建失败返回nil
-- @usage
-- c = socket.tcp()
-- c = socket.tcp(true)
-- c = socket.tcp(true, {caCert="ca.crt"})
-- c = socket.tcp(true, {caCert="ca.crt", clientCert="client.crt", clientKey="client.key"})
-- c = socket.tcp(true, {caCert="ca.crt", clientCert="client.crt", clientKey="client.key", clientPassword="123456"})
function tcp(ssl, cert, tCoreExtPara)
    return socket("TCP" .. (ssl == true and "SSL" or ""), (ssl == true) and cert or nil, tCoreExtPara)
end

--- 创建基于UDP的socket对象
-- @return client，创建成功返回socket客户端对象；创建失败返回nil
-- @usage c = socket.udp()
function udp()
    return socket("UDP")
end

--- 连接服务器
-- @string address 服务器地址，支持ip和域名
-- @param port string或者number类型，服务器端口
-- @number[opt=120] timeout 可选参数，连接超时时间，单位秒
-- @return bool result true - 成功，false - 失败
-- @return string ,id '0' -- '8' ,返回通道ID编号
-- @usage  
-- socketClient = socket.tcp()
-- socketClient:connect("www.baidu.com","80")
function mt:connect(address, port, timeout)
    assert(self.co == coroutine.running(), "socket:connect: coroutine mismatch")
    
    if not link.isReady() then
        log.info("socket.connect: ip not ready")
        return false
    end
    
    self.address = address
    self.port = port
    local tCoreExtPara = self.tCoreExtPara or {}
    -- 默认缓冲区大小
    local rcvBufferSize = tCoreExtPara.rcvBufferSize or 0
    
    local socket_connect_fnc = (type(socketcore.sock_conn_ext)=="function") and socketcore.sock_conn_ext or socketcore.sock_conn
    if self.protocol == 'TCP' then
        self.id = socket_connect_fnc(0, address, port, rcvBufferSize)
    elseif self.protocol == 'TCPSSL' then
        local cert = {hostName = address}
        local insist = 1
        if self.cert then
            if self.cert.caCert then
                if self.cert.caCert:sub(1, 1) ~= "/" then self.cert.caCert = "/lua/" .. self.cert.caCert end
                cert.caCert = io.readFile(self.cert.caCert)
            end
            if self.cert.clientCert then
                if self.cert.clientCert:sub(1, 1) ~= "/" then self.cert.clientCert = "/lua/" .. self.cert.clientCert end
                cert.clientCert = io.readFile(self.cert.clientCert)
            end
            if self.cert.clientKey then
                if self.cert.clientKey:sub(1, 1) ~= "/" then self.cert.clientKey = "/lua/" .. self.cert.clientKey end
                cert.clientKey = io.readFile(self.cert.clientKey)
            end
            insist = self.cert.insist == 0 and 0 or 1
        end
        self.id = socket_connect_fnc(2, address, port, cert, rcvBufferSize, insist, nil, 1)
    else
        self.id = socket_connect_fnc(1, address, port, rcvBufferSize)
    end
    if type(socketcore.sock_conn_ext)=="function" then
        if not self.id or self.id<0 then
            if self.id==-2 then
                require "http"
                --请求腾讯云免费HttpDns解析
                http.request("GET", "119.29.29.29/d?dn=" .. address, nil, nil, nil, 40000,
                    function(result, statusCode, head, body)
                        log.info("socket.httpDnsCb", result, statusCode, head, body)
                        sys.publish("SOCKET_HTTPDNS_RESULT_"..address.."_"..port, result, statusCode, head, body)
                    end)
                local _, result, statusCode, head, body = sys.waitUntil("SOCKET_HTTPDNS_RESULT_"..address.."_"..port)
                
                --DNS解析成功
                if result and statusCode == "200" and body and body:match("^[%d%.]+") then
                    return self:connect(body:match("^([%d%.]+)"),port,timeout)                
                end
            end
            self.id = nil
        end
    end
    if not self.id then
        log.info("socket:connect: core sock conn error", self.protocol, address, port, self.cert)
        return false
    end
    log.info("socket:connect-coreid,prot,addr,port,cert,timeout", self.id, self.protocol, address, port, self.cert, timeout or 120)
    sockets[self.id] = self
    self.wait = "SOCKET_CONNECT"
    self.timerId = sys.timerStart(coroutine.resume, (timeout or 120) * 1000, self.co, false, "TIMEOUT")
    local result, reason = coroutine.yield()
    if self.timerId and reason ~= "TIMEOUT" then sys.timerStop(self.timerId) end
    if not result then
        log.info("socket:connect: connect fail", reason)
		if reason == "RESPONSE" then
            sockets[self.id] = nil
			self.id = nil
		end
        sys.publish("LIB_SOCKET_CONNECT_FAIL_IND", self.ssl, self.protocol, address, port)
        return false
    end
    log.info("socket:connect: connect ok")
    
    if not self.connected then
        self.connected = true
        socketsConnected = socketsConnected+1
        sys.publish("SOCKET_ACTIVE", socketsConnected>0)
    end
    
    return true, self.id
end

--- 异步发送数据
-- @number[opt=nil] keepAlive,服务器和客户端最大通信间隔时间,也叫心跳包最大时间,单位秒
-- @string[opt=nil] pingreq,心跳包的字符串
-- @return boole,false 失败，true 表示成功
-- @usage
-- socketClient = socket.tcp()
-- socketClient:connect("www.baidu.com","80")
-- while socketClient:asyncSelect() do end
function mt:asyncSelect(keepAlive, pingreq)
    assert(self.co == coroutine.running(), "socket:asyncSelect: coroutine mismatch")
    if self.error then
        log.warn('socket.client:asyncSelect', 'error', self.error)
        return false
    end
    
    self.wait = "SOCKET_SEND"
    local dataLen = 0
    --log.info("socket.asyncSelect #self.output",#self.output)
    while #self.output ~= 0 do
        local data = table.concat(self.output)
        dataLen = string.len(data)
        self.output = {}
	local sendSize = self.protocol == "UDP" and 1472 or SENDSIZE
        for i = 1, dataLen, sendSize do
            -- 按最大MTU单元对data分包
            socketcore.sock_send(self.id, data:sub(i, i + sendSize - 1))
            if self.timeout then
                self.timerId = sys.timerStart(coroutine.resume, self.timeout * 1000, self.co, false, "TIMEOUT")
            end
            --log.info("socket.asyncSelect self.timeout",self.timeout)
            local result, reason = coroutine.yield()
            if self.timerId and reason ~= "TIMEOUT" then sys.timerStop(self.timerId) end
            sys.publish("SOCKET_ASYNC_SEND", result)
            if not result then
                sys.publish("LIB_SOCKET_SEND_FAIL_IND", self.ssl, self.protocol, self.address, self.port)
                --log.warn('socket.asyncSelect', 'send error')
                return false
            end
        end
    end
    self.wait = "SOCKET_WAIT"
    --log.info("socket.asyncSelect",dataLen,self.id)
    if dataLen>0 then sys.publish("SOCKET_SEND", self.id, true) end
    if keepAlive and keepAlive ~= 0 then
        if type(pingreq) == "function" then
            sys.timerStart(pingreq, keepAlive * 1000)
        else
            sys.timerStart(self.asyncSend, keepAlive * 1000, self, pingreq or "\0")
        end
    end
    return coroutine.yield()
end

function mt:getAsyncSend()
    if self.error then return 0 end
    return #(self.output)
end
--- 异步缓存待发送的数据
-- @string data 数据
-- @number[opt=nil] timeout 可选参数，发送超时时间，单位秒；为nil时表示不支持timeout
-- @return result true - 成功，false - 失败
-- @usage
-- socketClient = socket.tcp()
-- socketClient:connect("www.baidu.com","80")
-- socketClient:asyncSend("12345678")
function mt:asyncSend(data, timeout)
    if self.error then
        log.warn('socket.client:asyncSend', 'error', self.error)
        return false
    end
    self.timeout = timeout
    table.insert(self.output, data or "")
    --log.info("socket.asyncSend",self.wait)
    if self.wait == "SOCKET_WAIT" then coroutine.resume(self.co, true) end
    return true
end
--- 异步接收数据
-- @return data 表示接收到的数据(如果是UDP，返回最新的一包数据；如果是TCP,返回所有收到的数据)
--              ""表示未收到数据
-- @usage 
-- socketClient = socket.tcp()
-- socketClient:connect("www.baidu.com","80")
-- data = socketClient:asyncRecv()
function mt:asyncRecv()
    if #self.input == 0 then return "" end
    if self.protocol == "UDP" then
        return table.remove(self.input)
    else
        local s = table.concat(self.input)
        self.input = {}
        if self.isBlock then table.insert(self.input, socketcore.sock_recv(self.msg.socket_index, self.msg.recv_len)) end
        return s
    end
end

--- 同步发送数据
-- @string data 数据
--              此处传入的数据长度和剩余可用内存有关，只要内存够用，可以随便传入数据
--              虽然说此处的数据长度没有特别限制，但是调用core中的socket发送接口时，每次最多发送11200字节的数据
--              例如此处传入的data长度是112000字节，则在这个send接口中，会循环10次，每次发送11200字节的数据
-- @number[opt=120] timeout 可选参数，发送超时时间，单位秒
-- @return result true - 成功，false - 失败
-- @usage
-- socketClient = socket.tcp()
-- socketClient:connect("www.baidu.com","80")
-- socketClient:send("12345678")
function mt:send(data, timeout)
    assert(self.co == coroutine.running(), "socket:send: coroutine mismatch")
    if self.error then
        log.warn('socket.client:send', 'error', self.error)
        return false
    end
    log.debug("socket.send", "total " .. string.len(data or "") .. " bytes", "first 30 bytes", (data or ""):sub(1, 30))
    local sendSize = self.protocol == "UDP" and 1472 or SENDSIZE
    for i = 1, string.len(data or ""), sendSize do
        -- 按最大MTU单元对data分包
        self.wait = "SOCKET_SEND"
        socketcore.sock_send(self.id, data:sub(i, i + sendSize - 1))
        self.timerId = sys.timerStart(coroutine.resume, (timeout or 120) * 1000, self.co, false, "TIMEOUT")
        local result, reason = coroutine.yield()
        if self.timerId and reason ~= "TIMEOUT" then sys.timerStop(self.timerId) end
        if not result then
            log.info("socket:send", "send fail", reason)
            sys.publish("LIB_SOCKET_SEND_FAIL_IND", self.ssl, self.protocol, self.address, self.port)
            return false
        end
    end
    return true
end

--- 同步接收数据
-- @number[opt=0] timeout 可选参数，接收超时时间，单位毫秒
-- @string[opt=nil] msg 可选参数，控制socket所在的线程退出recv阻塞状态
-- @bool[opt=nil] msgNoResume 可选参数，控制socket所在的线程退出recv阻塞状态
--                false或者nil表示“在recv阻塞状态，收到msg消息，可以退出阻塞状态”，true表示不退出
--                此参数仅lib内部使用，应用脚本不要使用此参数
-- @return result 数据接收结果
--                true表示成功（接收到了数据）
--                false表示失败（没有接收到数据）
-- @return data 
--                如果result为true，data表示接收到的数据(如果是UDP，返回最新的一包数据；如果是TCP,返回所有收到的数据)
--                如果result为false，超时失败，data为"timeout"
--                如果result为false，msg控制退出，data为msg的字符串
--                如果result为false，socket连接被动断开控制退出，data为"CLOSED"
--                如果result为false，PDP断开连接控制退出，data为"IP_ERROR_IND"
-- @return param 如果是msg控制退出，param的值是msg的参数
-- @usage 
-- socketClient = socket.tcp()
-- socketClient:connect("www.baidu.com","80")
-- result,data = socketClient:recv(60000,"APP_SOCKET_SEND_DATA")
function mt:recv(timeout, msg, msgNoResume)
    assert(self.co == coroutine.running(), "socket:recv: coroutine mismatch")
    if self.error then
        log.warn('socket.client:recv', 'error', self.error)
        return false
    end
    self.msgNoResume = msgNoResume
    if msg and not self.iSubscribe then
        self.iSubscribe = msg
        self.subMessage = function(data)
            --if data then table.insert(self.output, data) end
            if self.wait == "+RECEIVE" and not self.msgNoResume then
                if data then table.insert(self.output, data) end
                coroutine.resume(self.co, 0xAA)
            end
        end
        sys.subscribe(msg, self.subMessage)
    end
    if msg and #self.output > 0 then sys.publish(msg, false) end
    if #self.input == 0 then
        self.wait = "+RECEIVE"
        if timeout and timeout > 0 then
            local r, s = sys.wait(timeout)
            if r == nil then
                return false, "timeout"
            elseif r == 0xAA then
                local dat = table.concat(self.output)
                self.output = {}
                return false, msg, dat
            else
                return r, s
            end
        else
            local r, s = coroutine.yield()
            if r == 0xAA then
                local dat = table.concat(self.output)
                self.output = {}
                return false, msg, dat
            else
                return r, s
            end
        end
    end
    
    if self.protocol == "UDP" then
        local s = table.remove(self.input)
        return true, s
    else
        log.warn("-------------------使用缓冲区---------------")
        local s = table.concat(self.input)
        self.input = {}
        if self.isBlock then table.insert(self.input, socketcore.sock_recv(self.msg.socket_index, self.msg.recv_len)) end
        return true, s
    end
end

--- 主动关闭并且销毁一个socket
-- @return nil
-- @usage
-- socketClient = socket.tcp()
-- socketClient:connect("www.baidu.com","80")
-- socketClient:close()
function mt:close()
    assert(self.co == coroutine.running(), "socket:close: coroutine mismatch")
    if self.iSubscribe then
        sys.unsubscribe(self.iSubscribe, self.subMessage)
        self.iSubscribe = false
    end
    --此处不要再判断状态，否则在连接超时失败时，conneted状态仍然是未连接，会导致无法close
    --if self.connected then
    log.info("socket:sock_close", self.id)
    local result, reason
    
    if self.id then
        socketcore.sock_close(self.id)
        self.wait = "SOCKET_CLOSE"
        while true do
            result, reason = coroutine.yield()
            if reason == "RESPONSE" then break end
        end
    end
    if self.connected then
        self.connected = false
        if socketsConnected>0 then
            socketsConnected = socketsConnected-1
        end
        sys.publish("SOCKET_ACTIVE", socketsConnected>0)
    end
    if self.input then
        self.input = {}
    end
    --end
    if self.id ~= nil then
        sockets[self.id] = nil
    end
end

-- socket接收自定义控制处理
-- @function[opt=nil] rcvCbFnc，socket接收到数据后，执行的回调函数，回调函数的调用形式为：
-- rcvCbFnc(readFnc,socketIndex,rcvDataLen)
-- rcvCbFnc内部，会判断是否读取数据，如果读取，执行readFnc(socketIndex,rcvDataLen)，返回true；否则返回false或者nil
function mt:setRcvProc(rcvCbFnc)
    assert(self.co == coroutine.running(), "socket:setRcvProc: coroutine mismatch")
    self.rcvProcFnc = rcvCbFnc
end

local function on_response(msg)
    local t = {
        [rtos.MSG_SOCK_CLOSE_CNF] = 'SOCKET_CLOSE',
        [rtos.MSG_SOCK_SEND_CNF] = 'SOCKET_SEND',
        [rtos.MSG_SOCK_CONN_CNF] = 'SOCKET_CONNECT',
    }
    if not sockets[msg.socket_index] then
        log.warn('response on nil socket', msg.socket_index, t[msg.id], msg.result)
        return
    end
    if sockets[msg.socket_index].wait ~= t[msg.id] then
        log.warn('response on invalid wait', sockets[msg.socket_index].id, sockets[msg.socket_index].wait, t[msg.id], msg.socket_index)
        return
    end
    log.info("socket:on_response:", msg.socket_index, t[msg.id], msg.result)
    if type(socketcore.sock_destroy) == "function" then
        if (msg.id == rtos.MSG_SOCK_CONN_CNF and msg.result ~= 0) or msg.id == rtos.MSG_SOCK_CLOSE_CNF then
            socketcore.sock_destroy(msg.socket_index)
        end
    end
    coroutine.resume(sockets[msg.socket_index].co, msg.result == 0, "RESPONSE")
end

rtos.on(rtos.MSG_SOCK_CLOSE_CNF, on_response)
rtos.on(rtos.MSG_SOCK_CONN_CNF, on_response)
rtos.on(rtos.MSG_SOCK_SEND_CNF, on_response)
rtos.on(rtos.MSG_SOCK_CLOSE_IND, function(msg)
    log.info("socket.rtos.MSG_SOCK_CLOSE_IND")
    if not sockets[msg.socket_index] then
        log.warn('close ind on nil socket', msg.socket_index, msg.id)
        return
    end
    if sockets[msg.socket_index].connected then
        sockets[msg.socket_index].connected = false
        if socketsConnected>0 then
            socketsConnected = socketsConnected-1
        end
        sys.publish("SOCKET_ACTIVE", socketsConnected>0)
    end
    sockets[msg.socket_index].error = 'CLOSED'
    
    --[[
    if type(socketcore.sock_destroy) == "function" then
        socketcore.sock_destroy(msg.socket_index)
    end]]
    sys.publish("LIB_SOCKET_CLOSE_IND", sockets[msg.socket_index].ssl, sockets[msg.socket_index].protocol, sockets[msg.socket_index].address, sockets[msg.socket_index].port)
    coroutine.resume(sockets[msg.socket_index].co, false, "CLOSED")
end)
rtos.on(rtos.MSG_SOCK_RECV_IND, function(msg)
    if not sockets[msg.socket_index] then
        log.warn('close ind on nil socket', msg.socket_index, msg.id)
        return
    end
    
    -- local s = socketcore.sock_recv(msg.socket_index, msg.recv_len)
    -- log.debug("socket.recv", "total " .. msg.recv_len .. " bytes", "first " .. 30 .. " bytes", s:sub(1, 30))
    log.debug("socket.recv", msg.recv_len, sockets[msg.socket_index].rcvProcFnc)
    if sockets[msg.socket_index].rcvProcFnc then
        sockets[msg.socket_index].rcvProcFnc(socketcore.sock_recv, msg.socket_index, msg.recv_len)
    else
        if sockets[msg.socket_index].wait == "+RECEIVE" then
            coroutine.resume(sockets[msg.socket_index].co, true, socketcore.sock_recv(msg.socket_index, msg.recv_len))
        else -- 数据进缓冲区，缓冲区溢出采用覆盖模式
            if #sockets[msg.socket_index].input > INDEX_MAX then
                log.error("socket recv", "out of stack", "block")
                -- sockets[msg.socket_index].input = {}
                sockets[msg.socket_index].isBlock = true
                sockets[msg.socket_index].msg = msg
            else
                sockets[msg.socket_index].isBlock = false
                table.insert(sockets[msg.socket_index].input, socketcore.sock_recv(msg.socket_index, msg.recv_len))
            end
            sys.publish("SOCKET_RECV", msg.socket_index)
        end
    end
end)

--- 设置TCP层自动重传的参数
-- @number[opt=4] retryCnt，重传次数；取值范围0到12
-- @number[opt=16] retryMaxTimeout，限制每次重传允许的最大超时时间(单位秒)，取值范围1到16
-- @return nil
-- @usage
-- setTcpResendPara(3,8)
-- setTcpResendPara(4,16)
function setTcpResendPara(retryCnt, retryMaxTimeout)
    ril.request("AT+TCPUSERPARAM=6," .. (retryCnt or 4) .. ",7200," .. (retryMaxTimeout or 16))
end

--- 设置域名解析参数
-- 注意：0027以及之后的core版本才支持此功能
-- @number[opt=4] retryCnt，重传次数；取值范围1到8
-- @number[opt=4] retryTimeoutMulti，重传超时时间倍数，取值范围1到5
--                第n次重传超时时间的计算方式为：第n次的重传超时基数*retryTimeoutMulti，单位为秒
--                重传超时基数表为{1, 1, 2, 4, 4, 4, 4, 4}
--                第1次重传超时时间为：1*retryTimeoutMulti 秒
--                第2次重传超时时间为：1*retryTimeoutMulti 秒
--                第3次重传超时时间为：2*retryTimeoutMulti 秒
--                ...........................................
--                第8次重传超时时间为：8*retryTimeoutMulti 秒
-- @return nil
-- @usage
-- socket.setDnsParsePara(8,5)
function setDnsParsePara(retryCnt, retryTimeoutMulti)
    ril.request("AT*DNSTMOUT="..(retryCnt or 4)..","..(retryTimeoutMulti or 4))
end

--- 打印所有socket的状态
-- @return 无
-- @usage socket.printStatus()
function printStatus()
    for _, client in pairs(sockets) do
        for k, v in pairs(client) do
            log.info('socket.printStatus', 'client', client.id, k, v)
        end
    end
end

--- 设置数据传输后，允许进入休眠状态的延时时长
-- 3024版本以及之后的版本才支持此功能
-- 此功能设置的参数，设置成功后，掉电会自动保存
-- @number tm，数据传输后，允许进入休眠状态的延时时长，单位为秒，取值范围1到20
--             注意：此时间越短，允许进入休眠状态越快，功耗越低；但是在某些网络环境中，此时间越短，可能会造成数据传输不稳定
--                   建议在可以接受的功耗范围内，此值设置的越大越好
--                   如果没有设置此参数，此延时时长是和基站的配置有关，一般来说是10秒左右
-- @return nil
-- @usage
-- socket.setLowPower(5)
function setLowPower(tm)
    ril.request("AT*RTIME="..tm)
end

--setDnsParsePara(4,4)
--setTcpResendPara(1,16)
