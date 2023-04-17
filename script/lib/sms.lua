--- 模块功能：短信功能
-- @module sms
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.03.25
require "sys"
require "ril"
require "common"
require "utils"
module(..., package.seeall)

local publish = sys.publish
local req = ril.request

--ready：底层短信功能是否准备就绪
local smsReady, isn, tlongsms, netReady, cpinReady,smsUrcReady = false, 255, {}
local ssub, slen, sformat, smatch = string.sub, string.len, string.format, string.match
local tsend = {}

--[[
函数名：numtobcdnum
功能  ：号码ASCII字符串 转化为 BCD编码格式字符串，仅支持数字和+，例如"+8618126324567" -> 91688121364265f7 （表示第1个字节是0x91，第2个字节为0x68，......）
参数  ：
num：待转换字符串
返回值：转换后的字符串
]]
local function numtobcdnum(num)
    local len, numfix, convnum = slen(num), "81", ""

    if ssub(num, 1, 1) == "+" then
        numfix = "91"
        len = len - 1
        num = ssub(num, 2, -1)
    end

    if len % 2 ~= 0 then --奇数位
        for i = 1, (len - (len % 2)) / 2 do
            convnum = convnum .. ssub(num, i * 2, i * 2) .. ssub(num, i * 2 - 1, i * 2 - 1)
        end
        convnum = convnum .. "F" .. ssub(num, len, len)
    else --偶数位
        for i = 1, (len - (len % 2)) / 2 do
            convnum = convnum .. ssub(num, i * 2, i * 2) .. ssub(num, i * 2 - 1, i * 2 - 1)
        end
    end

    return numfix .. convnum
end

--[[
函数名：bcdnumtonum
功能  ：BCD编码格式字符串 转化为 号码ASCII字符串，仅支持数字和+，例如91688121364265f7 （表示第1个字节是0x91，第2个字节为0x68，......） -> "+8618126324567"
参数  ：
num：待转换字符串
返回值：转换后的字符串
]]
local function bcdnumtonum(num)
    local len, numfix, convnum = slen(num), "", ""

    if len % 2 ~= 0 then
        print("your bcdnum is err " .. num)
        return
    end

    if ssub(num, 1, 2) == "91" then
        numfix = "+"
    end

    len, num = len - 2, ssub(num, 3, -1)

    for i = 1, (len - (len % 2)) / 2 do
        convnum = convnum .. ssub(num, i * 2, i * 2) .. ssub(num, i * 2 - 1, i * 2 - 1)
    end

    if ssub(convnum, len, len) == "f" or ssub(convnum, len, len) == "F" then
        convnum = ssub(convnum, 1, -2)
    end

    return numfix .. convnum
end


--[[
函数名：_send
功能  ：发送短信(内部接口)
参数  ：num,号码
data:短信内容
返回值：true：发送成功，false发送失败
]]
local function _send(num, data)
    local numlen, datalen, pducnt, pdu, pdulen, udhi = sformat("%02X", slen(num)), slen(data) / 2, 1, "", "", ""
    if not smsReady or not netReady then return false end

    --如果发送的数据大于140字节则为长短信
    if datalen > 140 then
        --计算出长短信拆分后的总条数，长短信的每包的数据实际只有134个实际要发送的短信内容，数据的前6字节为协议头
        pducnt = sformat("%d", (datalen + 133) / 134)
        pducnt = tonumber(pducnt)
        --分配一个序列号，范围为0-255
        isn = isn == 255 and 0 or isn + 1
    end

    table.insert(tsend, {sval = pducnt, rval = 0, flg = true})--sval发送的包数，rval收到的包数

    if ssub(num, 1, 1) == "+" then
        numlen = sformat("%02X", slen(num) - 1)
    end

    for i = 1, pducnt do
        --如果是长短信
        if pducnt > 1 then
            local len_mul
            len_mul = (i == pducnt and sformat("%02X", datalen - (pducnt - 1) * 134 + 6) or "8C")
            --udhi：6位协议头格式
            udhi = "050003" .. sformat("%02X", isn) .. sformat("%02X", pducnt) .. sformat("%02X", i)
            log.info(datalen, udhi)
            pdu = "005110" .. numlen .. numtobcdnum(num) .. "000800" .. len_mul .. udhi .. ssub(data, (i - 1) * 134 * 2 + 1, i * 134 * 2)
        --发送短短信
        else
            datalen = sformat("%02X", datalen)
            pdu = "001110" .. numlen .. numtobcdnum(num) .. "000800" .. datalen .. data
        end
        pdulen = slen(pdu) / 2 - 1
        req(sformat("%s%s", "AT+CMGS=", pdulen), pdu)
    end
    return true
end

--[[
函数名：read
功能  ：读短信
参数  ：pos短信位置
返回值：true：读成功，false读失败
]]
function read(pos)
    if not smsReady or pos == nil or pos == 0 then return false end

    req("AT+CMGR=" .. pos)
    return true
end

--[[
函数名：delete
功能  ：删除短信
参数  ：pos短信位置
返回值：true：删除成功，false删除失败
]]
function delete(pos)
    if not smsReady or pos == nil or pos == 0 then return false end
    req("AT+CMGD=" .. pos)
    return true
end

Charmap = {[0] = 0x40, 0xa3, 0x24, 0xa5, 0xe8, 0xE9, 0xF9, 0xEC, 0xF2, 0xC7, 0x0A, 0xD8, 0xF8, 0x0D, 0xC5, 0xE5
    , 0x0394, 0x5F, 0x03A6, 0x0393, 0x039B, 0x03A9, 0x03A0, 0x03A8, 0x03A3, 0x0398, 0x039E, 0x1B, 0xC6, 0xE5, 0xDF, 0xA9
    , 0x20, 0x21, 0x22, 0x23, 0xA4, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F
    , 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F
    , 0xA1, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F
    , 0X50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0xC4, 0xD6, 0xD1, 0xDC, 0xA7
    , 0xBF, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F
    , 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0xE4, 0xF6, 0xF1, 0xFC, 0xE0}

Charmapctl = {[10] = 0x0C, [20] = 0x5E, [40] = 0x7B, [41] = 0x7D, [47] = 0x5C, [60] = 0x5B, [61] = 0x7E
    , [62] = 0x5D, [64] = 0x7C, [101] = 0xA4}

--[[
函数名：gsm7bitdecode
功能  ：7位编码, 在PDU模式中，当使用7位编码时，最多可发160个字符
参数  ：data
longsms
返回值：
]]
function gsm7bitdecode(data, longsms)
    local ucsdata, lpcnt, tmpdata, resdata, nbyte, nleft, ucslen, olddat = "", slen(data) / 2, 0, 0, 0, 0, 0

    if longsms then
        tmpdata = tonumber("0x" .. ssub(data, 1, 2))
        resdata = bit.rshift(tmpdata, 1)
        if olddat == 27 then
            if Charmapctl[resdata] then --特殊字符
                olddat, resdata = resdata, Charmapctl[resdata]
                ucsdata = ssub(ucsdata, 1, -5)
            else
                olddat, resdata = resdata, Charmap[resdata]
            end
        else
            olddat, resdata = resdata, Charmap[resdata]
        end
        ucsdata = ucsdata .. sformat("%04X", resdata)
    else
        tmpdata = tonumber("0x" .. ssub(data, 1, 2))
        resdata = bit.band(bit.bor(bit.lshift(tmpdata, nbyte), nleft), 0x7f)
        if olddat == 27 then
            if Charmapctl[resdata] then --特殊字符
                olddat, resdata = resdata, Charmapctl[resdata]
                ucsdata = ssub(ucsdata, 1, -5)
            else
                olddat, resdata = resdata, Charmap[resdata]
            end
        else
            olddat, resdata = resdata, Charmap[resdata]
        end
        ucsdata = ucsdata .. sformat("%04X", resdata)

        nleft = bit.rshift(tmpdata, 7 - nbyte)
        nbyte = nbyte + 1
        ucslen = ucslen + 1
    end

    for i = 2, lpcnt do
        tmpdata = tonumber("0x" .. ssub(data, (i - 1) * 2 + 1, i * 2))
        if tmpdata == nil then break end
        resdata = bit.band(bit.bor(bit.lshift(tmpdata, nbyte), nleft), 0x7f)
        if olddat == 27 then
            if Charmapctl[resdata] then --特殊字符
                olddat, resdata = resdata, Charmapctl[resdata]
                ucsdata = ssub(ucsdata, 1, -5)
            else
                olddat, resdata = resdata, Charmap[resdata]
            end
        else
            olddat, resdata = resdata, Charmap[resdata]
        end
        ucsdata = ucsdata .. sformat("%04X", resdata)

        nleft = bit.rshift(tmpdata, 7 - nbyte)
        nbyte = nbyte + 1
        ucslen = ucslen + 1

        if nbyte == 7 then
            if olddat == 27 then
                if Charmapctl[nleft] then --特殊字符
                    olddat, nleft = nleft, Charmapctl[nleft]
                    ucsdata = ssub(ucsdata, 1, -5)
                else
                    olddat, nleft = nleft, Charmap[nleft]
                end
            else
                olddat, nleft = nleft, Charmap[nleft]
            end
            ucsdata = ucsdata .. sformat("%04X", nleft)
            nbyte, nleft = 0, 0
            ucslen = ucslen + 1
        end
    end

    return ucsdata, ucslen
end

--[[
函数名：gsm8bitdecode
功能  ：8位编码
参数  ：data
longsms
返回值：
]]
function gsm8bitdecode(data)
    local ucsdata, lpcnt = "", slen(data) / 2

    for i = 1, lpcnt do
        ucsdata = ucsdata .. "00" .. ssub(data, (i - 1) * 2 + 1, i * 2)
    end

    return ucsdata, lpcnt
end

--[[
函数名：rsp
功能  ：AT应答
参数  ：cmd,success,response,intermediate
返回值：无
]]
local function rsp(cmd, success, response, intermediate)
    local prefix = smatch(cmd, "AT(%+%u+)")
    log.info("lib_sms rsp", prefix, cmd, success, response, intermediate)

    --读短信成功
    if prefix == "+CMGR" then
        if not success then publish("SMS_READ_CNF") return end
        local convnum, t, stat, alpha, len, pdu, data, longsms, total, isn, idx = "", ""
        if intermediate then
            stat, alpha, len, pdu = smatch(intermediate, "+CMGR:%s*(%d),(.*),%s*(%d+)\r\n(%x+)")
            len = tonumber(len)--PDU数据长度，不包括短信息中心号码
        end

        --收到的PDU包不为空则解析PDU包
        if pdu and pdu ~= "" then
            local offset, addlen, addnum, flag, dcs, tz, txtlen, fo = 5
            pdu = ssub(pdu, (slen(pdu) / 2 - len) * 2 + 1, -1)--PDU数据，不包括短信息中心号码
            fo = tonumber("0x" .. ssub(pdu, 1, 1))--PDU短信首字节的高4位,第6位为数据报头标志位
            if bit.band(fo, 0x4) ~= 0 then
                longsms = true
            end
            addlen = tonumber(sformat("%d", "0x" .. ssub(pdu, 3, 4)))--回复地址数字个数

            addlen = addlen % 2 == 0 and addlen + 2 or addlen + 3 --加上号码类型2位（5，6）or 加上号码类型2位（5，6）和1位F

            offset = offset + addlen

            addnum = ssub(pdu, 5, 5 + addlen - 1)
            convnum = bcdnumtonum(addnum)

            flag = tonumber(sformat("%d", "0x" .. ssub(pdu, offset, offset + 1)))--协议标识 (TP-PID)
            offset = offset + 2
            dcs = tonumber(sformat("%d", "0x" .. ssub(pdu, offset, offset + 1)))--用户信息编码方式 Dcs=8，表示短信存放的格式为UCS2编码
            offset = offset + 2
            tz = ssub(pdu, offset, offset + 13)--时区7个字节
            offset = offset + 14
            txtlen = tonumber(sformat("%d", "0x" .. ssub(pdu, offset, offset + 1)))--短信文本长度
            offset = offset + 2
            data = ssub(pdu, offset, offset + txtlen * 2 - 1)--短信文本
            if longsms then
                if tonumber("0x" .. ssub(data, 5, 6)) == 3 then
                    isn, total, idx = tonumber("0x" .. ssub(data, 7, 8)), tonumber("0x" .. ssub(data, 9, 10)), tonumber("0x" .. ssub(data, 11, 12))
                    data = ssub(data, 13, -1)--去掉报头6个字节
                elseif tonumber("0x" .. ssub(data, 5, 6)) == 4 then
                    isn, total, idx = tonumber("0x" .. ssub(data, 7, 10)), tonumber("0x" .. ssub(data, 11, 12)), tonumber("0x" .. ssub(data, 13, 14))
                    data = ssub(data, 15, -1)--去掉报头7个字节
                end
            end

            log.info("TP-PID : ", flag, "dcs: ", dcs, "tz: ", tz, "data: ", data, "txtlen", txtlen)

            if dcs == 0x00 then --7bit encode
                local newlen
                data, newlen = gsm7bitdecode(data, longsms)
                if newlen > txtlen then
                    data = ssub(data, 1, txtlen * 4)
                end
                log.info("7bit to ucs2 data: ", data, "txtlen", txtlen, "newlen", newlen)
            elseif dcs == 0x04 then --8bit encode
                data, txtlen = gsm8bitdecode(data)
                log.info("8bit to ucs2 data: ", data, "txtlen", txtlen)
            end

            for i = 1, 7 do
                t = t .. ssub(tz, i * 2, i * 2) .. ssub(tz, i * 2 - 1, i * 2 - 1)

                if i <= 3 then
                    t = i < 3 and (t .. "/") or (t .. ",")
                elseif i <= 6 then
                    t = i < 6 and (t .. ":") or (t .. "+")
                end
            end
        end

        local pos = smatch(cmd, "AT%+CMGR=(%d+)")
        data = data or ""
        alpha = alpha or ""
        publish("SMS_READ_CNF", success, convnum, data, pos, t, alpha, total, idx, isn)
    elseif prefix == "+CMGD" then
        publish("SMS_DELETE_CNF", success)
    elseif prefix == "+CMGS" then
        --如果是短短信，直接发送短信确认消息
        if tsend[1].sval == 1 then --{sval=pducnt,rval=0,flg=true}
            table.remove(tsend, 1)
            publish("SMS_SEND_CNF", success)
        --如果是长短信，所有cmgs之后，才抛出SMS_SEND_CNF,所有cmgs都成功，才true，其余都是false
        else
            tsend[1].rval = tsend[1].rval + 1
            --只要其中有发送失败的短信，则整个长短信将标记为发送失败
            if not success then tsend[1].flg = false end
            if tsend[1].sval == tsend[1].rval then
                publish("SMS_SEND_CNF", tsend[1].flg)
                table.remove(tsend, 1)
            end
        end
    end
end

local function init()
    if cpinReady and smsUrcReady and netReady then
        --使用PDU模式发送
        req("AT+CMGF=0")
        --设置短信TEXT 模式参数
        -- req("AT+CSMP=17,167,0,8")
        --设置AT命令的字符编码是UCS2
        req('AT+CSCS="UCS2"')
        --设置存储区为SM
        req('AT+CPMS="SM"')
        -- 上报消息CMTI
        req("AT+CNMI=2,1,0,0,0")
        --分发短信准备好消息
        publish("SMS_READY")
        --清空已读短信
        req("AT+CMGD=1,3")
    end
end

--[[
函数名：urc
功能  ：主动上报消息处理函数
参数  ：data,prefix
返回值：无
]]
local function urc(data, prefix)
    --短信准备好
    if data == "SMS READY" then
        smsUrcReady = true
        init()
    -- 存储短信
    elseif prefix == "+CMTI" then
        --分发收到新短信消息
        publish("SMS_NEW_MSG_IND", smatch(data, "(%d+)", slen(prefix) + 1))
    end
end

--[[
函数名：getsmsstate
功能  ：获取短消息是否准备好的状态
参数  ：无
返回值：true准备好，其他值：未准备好
]]
function getsmsstate()
    return smsReady
end

--[[
函数名：mergelongsms
功能  ：合并长短信
参数  ：
tag：长短信标记(ISN和总条数的拼接字符串)
返回值：无
]]
local function mergelongsms(tag)
    local data = ""
    --按表中的顺序，一次拼接短消息内容
    for i = 1, tlongsms[tag]["total"] do
        data = data .. (tlongsms[tag]["dat"][i] or "")
    end
    --分发长短信合并确认消息
    publish("LONG_SMS_MERGR_CNF", true, tlongsms[tag]["num"], data, tlongsms[tag]["t"], tlongsms[tag]["nam"])
    log.info("mergelongsms", "num:", tlongsms[tag]["num"], "data", data)
    tlongsms[tag]["dat"], tlongsms[tag] = nil
end

--[[
函数名：longsmsind
功能  ：长短信被拆解后的消息包上报
参数  ：id,num, data,datetime,name,total,idx,isn
返回值：无
]]
local function longsmsind(num, data, datetime, name, total, idx, isn)
    log.info("longsmsind", "isn", isn, "total:", total, "idx:", idx, "data", data)

    if tlongsms[isn .. total] then
        if not tlongsms[isn .. total]["dat"] then tlongsms[isn .. total]["dat"] = {} end
        tlongsms[isn .. total]["dat"][idx] = data
    else
        tlongsms[isn .. total] = {}
        tlongsms[isn .. total]["total"], tlongsms[isn .. total]["num"], tlongsms[isn .. total]["t"], tlongsms[isn .. total]["nam"] = total, num, datetime, name
        tlongsms[isn .. total]["dat"] = {}
        tlongsms[isn .. total]["dat"][idx] = data
    end

    local totalrcv = 0
    for i = 1, tlongsms[isn .. total]["total"] do
        if tlongsms[isn .. total]["dat"][i] then totalrcv = totalrcv + 1 end
    end
    --长短信接收完整
    if tlongsms[isn .. total]["total"] == totalrcv then
        sys.timerStop(mergelongsms, isn .. total)
        mergelongsms(isn .. total)
    else
        --如果2分钟后长短信还没收完整，2分钟后将自动合并已收到的长短信
        sys.timerStart(mergelongsms, 120000, isn .. total)
    end
end

--注册长短信合并处理函数
sys.subscribe("LONG_SMS_MERGE", longsmsind)

ril.regUrc("SMS READY", urc)
ril.regUrc("+CMT", urc)
ril.regUrc("+CMTI", urc)

ril.regRsp("+CMGR", rsp)
ril.regRsp("+CMGD", rsp)
ril.regRsp("+CMGS", rsp)


--短信发送缓冲表最大个数
local SMS_SEND_BUF_MAX_CNT = 10
--短信发送间隔，单位毫秒
local SMS_SEND_INTERVAL = 3000
--短信发送缓冲表
local tsmsnd = {}

--[[
函数名：sndnxt
功能  ：发送短信发送缓冲表中的第一条短信
参数  ：无
返回值：无
]]
local function sndnxt()
    if #tsmsnd > 0 then
        _send(tsmsnd[1].num, tsmsnd[1].data)
    end
end

--[[
函数名：sendcnf
功能  ：SMS_SEND_CNF消息的处理函数，异步通知短信发送结果
参数  ：
result：短信发送结果，true为成功，false或者nil为失败
返回值：无
]]
local function sendcnf(result)
    log.info("sendcnf", result)
    local num, data, cb = tsmsnd[1].num, tsmsnd[1].data, tsmsnd[1].cb
    --从短信发送缓冲表中移除当前短信
    table.remove(tsmsnd, 1)
    --如果有发送回调函数，执行回调
    if cb then cb(result, num, data) end
    --如果短信发送缓冲表中还有短信，则SMS_SEND_INTERVAL毫秒后，继续发送下条短信
    if #tsmsnd > 0 then sys.timerStart(sndnxt, SMS_SEND_INTERVAL) end
end

--- 发送短信
-- @string num，短信接收方号码，ASCII码字符串格式
-- @string data，短信内容，GB2312编码的字符串
--               如果短信内容中只有ascii可见字符，则超过160个字符时，会被拆分为几条长级联短信进行发送
--               如果短信内容中包含除ascii可见字符外的其他字符，例如包含汉字，一个汉字算作一个字符，一个ascii可见字符也算作一个字符，超过70个字符时，会被拆分为几条长级联短信进行发送
-- @function[opt=nil] cbFnc，短信发送结果异步返回时的用户回调函数，回调函数的调用形式为：
--              cbFnc(result,num,data)
--              num：短信接收方的号码，ASCII码字符串格式
--              data：短信内容，unicode大端编码的HEX字符串
-- @number[opt=nil] idx，插入短信发送缓冲表的位置，默认是插入末尾
-- @return result，true表示调用接口成功（并不是短信发送成功，短信发送结果，通过sendcnf返回，如果有cbFnc，会通知cbFnc函数）；返回false，表示调用接口失败
-- @usage sms.send("10086","test",cbFnc)
function send(num, data, cbFnc, idx)
    --号码或者内容非法
    if not num or num == "" or not data or data == "" then if cbFnc then cbFnc(false, num, data) end return end
    --短信发送缓冲表已满
    if #tsmsnd >= SMS_SEND_BUF_MAX_CNT then if cbFnc then cbFnc(false, num, data) end return end
    local dat = string.toHex(common.gb2312ToUcs2be(data))
    --如果指定了插入位置
    if idx then
        table.insert(tsmsnd, idx, {num = num, data = dat, cb = cbFnc})
    --没有指定插入位置，插入到末尾
    else
        table.insert(tsmsnd, {num = num, data = dat, cb = cbFnc})
    end
    --如果短信发送缓冲表中只有一条短信，立即触发短信发送动作
    if #tsmsnd == 1 then _send(num, dat) return true end
end


--短信接收位置表
local tnewsms = {}

--[[
函数名：readsms
功能  ：读取短信接收位置表中的第一条短信
参数  ：无
返回值：无
]]
local function readsms()
    if #tnewsms ~= 0 then
        read(tnewsms[1])
    end
end

--[[
函数名：newsms
功能  ：SMS_NEW_MSG_IND（未读短信或者新短信主动上报的消息）消息的处理函数
参数  ：
pos：短信存储位置
返回值：无
]]
local function newsms(pos)
    --存储位置插入到短信接收位置表中
    table.insert(tnewsms, pos)
    --如果只有一条短信，则立即读取
    if #tnewsms == 1 then
        readsms()
    end
end

--新短信的用户处理函数
local newsmscb

--- 设置新短信的用户处理函数
-- @function cbFnc，新短信的用户处理函数
-- @return nil
-- @usage sms.setNewSmsCb(cbFnc)
function setNewSmsCb(cbFnc)
    newsmscb = cbFnc
end

--[[
函数名：readcnf
功能  ：SMS_READ_CNF消息的处理函数，异步返回读取的短信内容
参数  ：
result：短信读取结果，true为成功，false或者nil为失败
num：短信号码，ASCII码字符串格式
data：短信内容，UCS2大端格式的16进制字符串
pos：短信的存储位置，暂时没用
datetime：短信日期和时间，ASCII码字符串格式
name：短信号码对应的联系人姓名，暂时没用
返回值：无
]]
local function readcnf(result, num, data, pos, datetime, name, total, idx, isn)
    if result then
        --过滤号码中的86和+86
        local d1, d2 = string.find(num, "^([%+]*86)")
        if d1 and d2 then
            num = string.sub(num, d2 + 1, -1)
        end
        --删除短信
        delete(tnewsms[1])
        --从短信接收位置表中删除此短信的位置
        table.remove(tnewsms, 1)
        if total and total > 1 then
            publish("LONG_SMS_MERGE", num, data, datetime, name, total, idx, isn)
            readsms()--读取下一条新短信
            return
        end
        if data then
            --短信内容转换为GB2312字符串格式
            data = common.ucs2beToGb2312(data:fromHex())
            --用户应用程序处理短信
            if newsmscb then newsmscb(num, data, datetime) end
        end
        --继续读取下一条短信
        readsms()
    else
        --删除短信
        delete(tnewsms[1])
        --从短信接收位置表中删除此短信的位置
        table.remove(tnewsms, 1)
        --继续读取下一条短信
        readsms()
    end
end

local function longsmsmergecnf(res, num, data, datetime)
    --log.info("longsmsmergecnf",num,data,datetime)
    if data then
        --短信内容转换为GB2312字符串格式
        data = common.ucs2beToGb2312(data:fromHex())
        --用户应用程序处理短信
        if newsmscb then newsmscb(num, data, datetime) end
    end
end

sys.subscribe("SMS_NEW_MSG_IND", newsms)
sys.subscribe("SMS_READ_CNF", readcnf)
sys.subscribe("SMS_SEND_CNF", sendcnf)
sys.subscribe("SMS_READY",
    function()
        if not smsReady then
            smsReady = true
            if netReady then sndnxt() end
        end
    end
)
sys.subscribe("NET_STATE_REGISTERED",
    function()
        if not netReady then
            netReady = true
            init()
            if smsReady then sndnxt() end
        end
    end
)
sys.subscribe("SIM_IND",
    function(para)
        if para=="RDY" and not cpinReady then
            cpinReady = true
            init()
        end
    end
)

sys.subscribe("LONG_SMS_MERGR_CNF", longsmsmergecnf)

-- 此处为临时AT+CNMI补丁
sys.timerStart(req, 30000, "AT+CNMI=2,1,0,0,0")
