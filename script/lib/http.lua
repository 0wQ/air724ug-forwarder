--- 模块功能：HTTP客户端
-- @module http
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.10.23
require"socket"
require"utils"
module(..., package.seeall)

local function response(client,cbFnc,result,prompt,head,body)
    if not result then log.error("http.response",result,prompt) end
    if cbFnc then cbFnc(result,prompt,head,body) end
    if client then client:close() end
end

local function receive(client,timeout,cbFnc,result,prompt,head,body)
    local res,data = client:recv(timeout)
    if not res then
        response(client,cbFnc,result,prompt or "receive timeout",head,body)
    end
    return res,data
end

local function getFileBase64Len(s)
    if s then return (io.fileSize(s)+2)/3*4 end
end

local function taskClient(method,protocal,auth,host,port,path,cert,head,body,timeout,cbFnc,rcvFilePath,tCoreExtPara)
    log.info("http path",path)
    while not socket.isReady() do
        if not sys.waitUntil("IP_READY_IND",timeout) then return response(nil,cbFnc,false,"network not ready") end
    end

    --计算body长度
    local bodyLen = 0
    if body then
        if type(body)=="string" then
            bodyLen = body:len()
        elseif type(body)=="table" then
            for i=1,#body do
                bodyLen = bodyLen + (type(body[i])=="string" and string.len(body[i]) or getFileBase64Len(body[i].file_base64) or io.fileSize(body[i].file))
            end
        end
    end

    --重构head
    local heads = head or {}
    if not heads.Host then heads["Host"] = host end
    if not heads.Connection then heads["Connection"] = "short" end
    if bodyLen>0 and bodyLen~=tonumber(heads["Content-Length"] or "0") then heads["Content-Length"] = bodyLen end
    if auth~="" and not heads.Authorization then heads["Authorization"] = ("Basic "..crypto.base64_encode(auth,#auth)) end
    local headStr = ""
    for k,v in pairs(heads) do
        headStr = headStr..k..": "..v.."\r\n"
    end
    headStr = headStr.."\r\n"

    local client = socket.tcp(protocal=="https",cert,tCoreExtPara)
    if not client then return response(nil,cbFnc,false,"create socket error") end
    if not client:connect(host,port,timeout/1000) then
        return response(client,cbFnc,false,"connect fail")
    end

    --发送请求行+请求头+string类型的body
    if not client:send(method.." "..path.." HTTP/1.1".."\r\n"..headStr..(type(body)=="string" and body or "")) then
        return response(client,cbFnc,false,"send head fail")
    end

    --发送table类型的body
    if type(body)=="table" then
        for i=1,#body do
            if type(body[i])=="string" then
                if not client:send(body[i]) then
                    return response(client,cbFnc,false,"send body fail")
                end
            else
                local file = io.open(body[i].file or body[i].file_base64,"rb")
                if file then
                    while true do
                        local dat = file:read(body[i].file and 11200 or 8400)
                        if not dat then
                            io.close(file)
                            break
                        end
                        if body[i].file_base64 then dat=crypto.base64_encode(dat,#dat) end
                        if not client:send(dat) then
                            io.close(file)
                            return response(client,cbFnc,false,"send file fail")
                        end
                    end
                else
                    return response(client,cbFnc,false,"send file open fail")
                end
            end
        end
    end

    local rcvCache,rspHead,rspBody,d1,d2,result,data,statusCode,rcvChunked,contentLen = "",{},{}
    --接收数据，解析状态行和头
    while true do
        result,data = receive(client,timeout,cbFnc,false,nil,rspHead,rcvFilePath or table.concat(rspBody))
        if not result then return end
        rcvCache = rcvCache..data
        d1,d2 = rcvCache:find("\r\n\r\n")
        if d2 then
            --状态行
            _,d1,statusCode = rcvCache:find("%s(%d+)%s.-\r\n")
            if not statusCode then
                return response(client,cbFnc,false,"parse received status error",rspHead,rcvFilePath or table.concat(rspBody))
            end
            --应答头
            for k,v in string.gmatch(rcvCache:sub(d1+1,d2-2),"(.-):%s*(.-)\r\n") do
                rspHead[k] = v
                if (string.upper(k)==string.upper("Transfer-Encoding")) and (string.upper(v)==string.upper("chunked")) then rcvChunked = true end
            end
            if not rcvChunked then
                contentLen = tonumber(rspHead["Content-Length"] or "2147483647")
            end
			if method == "HEAD" then 
				contentLen = 0
			end
            --未处理的body数据
            rcvCache = rcvCache:sub(d2+1,-1)
            break
        end
    end

    --解析body
    if rcvChunked then
        local chunkSize
        --循环处理每个chunk
        while true do
            --解析chunk size
            if not chunkSize then
                d1,d2,chunkSize = rcvCache:find("(%x+)\r\n")
                if chunkSize then
                    chunkSize = tonumber(chunkSize,16)
                    rcvCache = rcvCache:sub(d2+1,-1)
                else
                    result,data = receive(client,timeout,cbFnc,false,nil,rspHead,rcvFilePath or table.concat(rspBody))
                    if not result then return end
                    rcvCache = rcvCache..data
                end
            end

            --log.info("http.taskClient chunkSize",chunkSize)

            --解析chunk data
            if chunkSize then
                if rcvCache:len()<chunkSize+2 then
                    result,data = receive(client,timeout,cbFnc,false,nil,rspHead,rcvFilePath or table.concat(rspBody))
                    if not result then return end
                    rcvCache = rcvCache..data
                else
                    if chunkSize>0 then
                        local chunkData = rcvCache:sub(1,chunkSize)
                        --保存到文件中
                        if type(rcvFilePath)=="string" then
                            local file = io.open(rcvFilePath,"a+")
                            if not file then return response(client,cbFnc,false,"receive: open file error",rspHead,rcvFilePath or table.concat(rspBody)) end
                            if not file:write(chunkData) then response(client,cbFnc,false,"receive: write file error",rspHead,rcvFilePath or table.concat(rspBody)) end
                            file:close()
                        elseif type(rcvFilePath)=="function" then  --保存到缓冲区中
                            local userResult = rcvFilePath(data,rspHead["Content-Range"] and tonumber((rspHead["Content-Range"]):match("/(%d+)")) or contentLen,statusCode)
                            if userResult~=nil then
                                return response(client,cbFnc,userResult,userResult and statusCode or "receive: user process error",rspHead)
                            end
                        else
                            table.insert(rspBody,chunkData)
                        end
                        rcvCache = rcvCache:sub(chunkSize+3,-1)
                        chunkSize = nil
                    elseif chunkSize==0 then
                        return response(client,cbFnc,true,statusCode,rspHead,rcvFilePath or table.concat(rspBody))
                    end
                end
            end
        end
    else
        local rmnLen = contentLen
        while true do
            data = rcvCache:len()<=rmnLen and rcvCache or rcvCache:sub(1,rmnLen)
            if type(rcvFilePath)=="string" then
                if data:len()>0 then
                    local file = io.open(rcvFilePath,"a+")
                    if not file then return response(client,cbFnc,false,"receive: open file error",rspHead,rcvFilePath or table.concat(rspBody)) end
                    if not file:write(data) then response(client,cbFnc,false,"receive: write file error",rspHead,rcvFilePath or table.concat(rspBody)) end
                    file:close()
                end
            elseif type(rcvFilePath)=="function" then
                local userResult = rcvFilePath(data,rspHead["Content-Range"] and tonumber((rspHead["Content-Range"]):match("/(%d+)")) or contentLen,statusCode)
                if userResult~=nil then
                    return response(client,cbFnc,userResult,userResult and statusCode or "receive: user process error",rspHead)
                end
            else
                table.insert(rspBody,data)
            end
            rmnLen = rmnLen-data:len()
            if rmnLen==0 then break end
                result,rcvCache = receive(client,timeout,cbFnc,contentLen==0x7FFFFFFF,contentLen==0x7FFFFFFF and statusCode or nil,rspHead,rcvFilePath or table.concat(rspBody))
            if not result then return end
        end
        return response(client,cbFnc,true,statusCode,rspHead,rcvFilePath or table.concat(rspBody))
    end
end

--- 发送HTTP请求
-- @string method HTTP请求方法
-- 支持"GET"，"HEAD"，"POST"，"OPTIONS"，"PUT"，"DELETE"，"TRACE"，"CONNECT"
-- @string url HTTP请求url
-- url格式(除hostname外，其余字段可选；目前的实现不支持hash),url中如果包含UTF8编码中文，则需要调用string.rawurlEncode转换成RFC3986编码。
-- |------------------------------------------------------------------------------|
-- | protocol |||   auth    |      host       |           path            | hash  |
-- |----------|||-----------|-----------------|---------------------------|-------|
-- |          |||           | hostname | port | pathname |     search     |       |
-- |          |||           |----------|------|----------|----------------|       |
-- " http[s]  :// user:pass @ host.com : 8080   /p/a/t/h ?  query=string  # hash  "
-- |          |||           |          |      |          |                |       |
-- |------------------------------------------------------------------------------|
-- @table[opt=nil] cert，table或者nil类型，ssl证书，当url为https类型时，此参数才有意义。cert格式如下：
-- {
--     caCert = "ca.crt", --CA证书文件(Base64编码 X.509格式)，如果存在此参数，则表示客户端会对服务器的证书进行校验；不存在则不校验
--     clientCert = "client.crt", --客户端证书文件(Base64编码 X.509格式)，服务器对客户端的证书进行校验时会用到此参数
--     clientKey = "client.key", --客户端私钥文件(Base64编码 X.509格式)
--     clientPassword = "123456", --客户端证书文件密码[可选]
-- }
-- @table[opt=nil] head，nil或者table类型，自定义请求头
--      http.lua会自动添加Host: XXX、Connection: short、Content-Length: XXX三个请求头
--      如果这三个请求头满足不了需求，head参数传入自定义请求头，如果自定义请求头中存在Host、Connection、Content-Length三个请求头，将覆盖http.lua中自动添加的同名请求头
--      head格式如下：
--          如果没有自定义请求头，传入nil或者{}；否则传入{head1="value1", head2="value2", head3="value3"}，value中不能有\r\n
-- @param[opt=nil] body，nil、string或者table类型，请求实体
--      如果body仅仅是一串数据，可以直接传入一个string类型的body即可
--
--      如果body的数据比较复杂，包括字符串数据和文件，则传入table类型的数据，格式如下：
--      {
--          [1] = "string1",
--          [2] = {file="/ldata/test.jpg"},
--          [3] = "string2"
--      }
--      例如上面的这个body，索引必须为连续的数字(从1开始)，实际传输时，先发送字符串"string1"，再发送文件/ldata/test.jpg的内容，最后发送字符串"string2"
--
--      如果传输的文件内容需要进行base64编码再上传，请把file改成file_base64，格式如下：
--      {
--          [1] = "string1",
--          [2] = {file_base64="/ldata/test.jpg"},
--          [3] = "string2"
--      }
--      例如上面的这个body，索引必须为连续的数字(从1开始)，实际传输时，先发送字符串"string1"，再发送文件/ldata/test.jpg经过base64编码后的内容，最后发送字符串"string2"
-- @number[opt=30000] timeout，http请求应答整个过程中，每个子过程的超时时间，单位毫秒，默认为30秒，子过程包括如下两种：
--                             1、pdp数据网络激活的超时时间
--                             2、http请求发送成功后，分段接收服务器的应答数据，每段数据接收的超时时间
-- @function[opt=nil] cbFnc，执行HTTP请求的回调函数(请求发送结果以及应答数据接收结果都通过此函数通知用户)，回调函数的调用形式为：
--      cbFnc(result,prompt,head,body)
--      result：true或者false，true表示成功收到了服务器的应答，false表示请求发送失败或者接收服务器应答失败
--      prompt：string类型，result为true时，表示服务器的应答码；result为false时，表示错误信息
--      head：table或者nil类型，表示服务器的应答头；result为true时，此参数为{head1="value1", head2="value2", head3="value3"}，value中不包含\r\n；result为false时，此参数为nil
--      body：string类型，如果调用request接口时传入了rcvFileName，此参数表示下载文件的完整路径；否则表示接收到的应答实体数据
-- @string[opt=nil] rcvFileName，string类型时，保存“服务器应答实体数据”的文件名，可以传入完整的文件路径，也可以传入单独的文件名，如果是文件名，http.lua会自动生成一个完整路径，通过cbFnc的参数body传出
--                               function类型时，rcvFileName(stepData,totalLen,statusCode)
--                               stepData: 本次服务器应答实体数据
--                               totalLen: 实体数据的总长度
--                               statusCode：服务器的应答码   
-- @table[opt=nil] tCoreExtPara,table类型{rcvBufferSize=0}修改缓冲空间大小，解决窗口满连接超时问题，单位:字节
-- @return string rcvFilePath，如果传入了rcvFileName，则返回对应的完整路径；其余情况都返回nil
-- @usage
-- http.request("GET","www.lua.org",nil,nil,nil,30000,cbFnc)
-- http.request("GET","http://www.lua.org",nil,nil,nil,30000,cbFnc)
-- http.request("GET","http://www.lua.org:80",nil,nil,nil,30000,cbFnc,"download.bin")
-- http.request("GET","www.lua.org/about.html",nil,nil,nil,30000,cbFnc)
-- http.request("GET","www.lua.org:80/about.html",nil,nil,nil,30000,cbFnc)
-- http.request("GET","http://wiki.openluat.com/search.html?q=123",nil,nil,nil,30000,cbFnc)
-- http.request("POST","www.test.com/report.html",nil,{Head1="ValueData1"},"BodyData",30000,cbFnc)
-- http.request("POST","www.test.com/report.html",nil,{Head1="ValueData1",Head2="ValueData2"},{[1]="string1",[2] ={file="/ldata/test.jpg"},[3]="string2"},30000,cbFnc)
-- http.request("GET","https://www.baidu.com",{caCert="ca.crt"})
-- http.request("GET","https://www.baidu.com",{caCert="ca.crt",clientCert = "client.crt",clientKey = "client.key"})
-- http.request("GET","https://www.baidu.com",{caCert="ca.crt",clientCert = "client.crt",clientKey = "client.key",clientPassword = "123456"})
function request(method,url,cert,head,body,timeout,cbFnc,rcvFileName,tCoreExtPara)
    local protocal,auth,hostName,port,path,d1,d2,offset,rcvFilePath
    d1,d2,protocal = url:find("^(%a+)://")
    if not protocal then protocal = "http" end
    offset = d2 or 0

    d1,d2,auth = url:find("(.-:.-)@",offset+1)
    offset = d2 or offset

    if url:match("^[^/]+:(%d+)",offset+1) then
        d1,d2,hostName,port = url:find("^([^/]+):(%d+)",offset+1)
    else
        d1,d2,hostName = url:find("(.-)/",offset+1)
        if hostName then
            d2 = d2-1
        else
            hostName = url:sub(offset+1,-1)
            offset = url:len()
        end
    end

    if not hostName then return response(nil,cbFnc,false,"Invalid url, can't get host") end
    if port=="" or not port then port = (protocal=="https" and 443 or 80) end
    offset = d2 or offset

    path = url:sub(offset+1,-1)

    sys.taskInit(taskClient,method,protocal,auth or "",hostName,port,path=="" and "/" or path,cert,head,body or "",timeout or 30000,cbFnc,rcvFileName,tCoreExtPara)
    if type(rcvFileName) == "string" then
        return rcvFileName
    end
end

