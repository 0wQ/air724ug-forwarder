--- 模块功能：数据链路激活(创建、连接、状态维护)
-- @module link
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.9.20
-- 4G网络下不手动激活pdp，注册上网后发cgdcont?等默认承载激活后上报IP_READY_IND，
-- 2G网络下，先cgact?查询有任一一路pdp激活，则直接上报IP_READY_IND，否则cgact激活cid_manual
require "net"

module(..., package.seeall)

local publish = sys.publish
local request = ril.request
local ipAddr = ""
local gprsAttached
local cid_manual = 5
local readyTable = {false, false, false}
-- 链路层网络类型：
-- 蜂窝模组数据网络
CELLULAR = 1
-- ch395以太网
CH395 = 2
-- w5500以太网
W5500 = 3
local network = CELLULAR

function setReady(mode, state)
    readyTable[mode] = state
end
function getIp()
    return ipAddr
end
function isReady()
    return readyTable[network]
end

-- apn，用户名，密码
local apnname, username, password
local dnsIP
local authProt, authApn, authUser, authPassword

function setAPN(apn, user, pwd)
    apnname, username, password = apn, user, pwd
end

function setDnsIP(ip1, ip2)
    dnsIP = "\"" .. (ip1 or "") .. "\",\"" .. (ip2 or "") .. "\""
end

local function setCgdf()
    request("AT+AUTOAPN=0")
    request('AT*CGDFLT=1,"IP","' .. authApn .. '",,,,,,,,,,,,,,,,,,1')
    request('AT*CGDFAUTH=1,' .. authProt .. ',"' .. authUser .. '","' .. authPassword .. '"', nil, function(cmd, result)
        if result then
            sys.restart("CGDFAUTH")
        else
            sys.timerStart(setCgdf, 5000)
        end
    end)
end

--- 设置专网卡APN(注意：在main.lua中，尽可能靠前的位置调用此接口)
-- 第一次设置成功之后，软件会自动重启，因为重启后才能生效
-- @number[opt=0] prot，加密方式， 0:不加密  1:PAP  2:CHAP
-- @string[opt=""] apn，apn名称
-- @string[opt=""] user，apn用户名
-- @string[opt=""] pwd，apn密码
-- @return nil
-- @usage
-- c = link.setAuthApn(2,"MYAPN","MYNAME","MYPASSWORD")
function setAuthApn(prot, apn, user, pwd)
    --[[
    local coreVer = rtos.get_version()
    local verNo = coreVer:match("Luat_V(%d+)_ASR1802_")
    if verNo and tonumber(verNo)>=27 then
        request("AT+AUTOAPN=0")]]
    -- 0：保存并重启生效
    -- 1：不保存立即生效
    -- 2：保存并立即生效
    -- 3：删除保存的文件
    request('AT+CPNETAPN=2,"' .. apn .. '","' .. user .. '","' .. pwd .. '",' .. prot)
    --[[else
        authProt,authApn,authUser,authPassword = prot or 0,apn or "",user or "",pwd or ""
        request("AT*CGDFLT?")
        ril.regUrc("*CGDFLT", function(data)
            local dftApn = data:match("CGDFLT:%s*\"%w*\",\"(.-)\"")
            if dftApn~=authApn then
                setCgdf()
            end
        end)
    end]]
end

local function Pdp_Act()
    log.info("link.Pdp_Act", readyTable[CELLULAR], net.getNetMode(), gprsAttached)
    if readyTable[CELLULAR] then
        request("AT+CGDCONT?", nil, cgdcontRsp)
        return
    end
    if net.getNetMode() == net.NetMode_LTE then
        if not gprsAttached then
            gprsAttached = true
            sys.publish("GPRS_ATTACH", true)
        end
        if not apnname then
            sys.timerStart(pdpCmdCnf, 1000, "SET_PDP_4G_WAITAPN", true)
        else
            request("AT+CGDCONT?", nil, cgdcontRsp)
            -- request(string.format('AT*CGDFLT=0,"IP","%s"', apnname), nil, pdpCmdCnf)
        end
    else
        request('AT+CGATT?')
    end
end

local function procshut(curCmd, result, respdata, interdata)
    if network~=CELLULAR then
        return
    end
    if IsCidActived(cid_manual, interdata) then
        ril.request(string.format('AT+CGACT=0,%d', cid_manual), nil, function(cmd, result)
            if result then
                readyTable[CELLULAR] = false
                sys.publish('IP_ERROR_IND')

                if net.getState() ~= 'REGISTERED' then
                    return
                end
                sys.timerStart(Pdp_Act, 2000)
            end
        end)
    else
        readyTable[CELLULAR] = false
        sys.publish('IP_ERROR_IND')

        if net.getState() ~= 'REGISTERED' then
            return
        end
        sys.timerStart(Pdp_Act, 2000)
    end
end
--[[
如果是默认承载，是去激活不了的，
如果是手动激活的pdp，去激活cid_manual后也还是有默认承载存在，
所以如果上层在去激活后要发起socket是能连上的，所以这里直接上报IP_ERROR_IND，由上层自己管理shut之后的逻辑
]]
function shut()
    if network~=CELLULAR then
        return
    end
    -- ril.request("AT+CGACT?",nil,procshut)
    readyTable[CELLULAR] = false
    sys.publish('IP_ERROR_IND')

    if net.getState() ~= 'REGISTERED' then
        return
    end
    sys.timerStart(Pdp_Act, 2000)
end

function analysis_cgdcont(data)
    local tmp, loc, result
    while data do
        _, loc = string.find(data, "\r\n")
        if loc then
            tmp = string.sub(data, 1, loc)
            data = string.sub(data, loc + 1, -1)
            log.info("analysis_cgdcont ", tmp, loc, data)
        else
            tmp = data
            data = nil
            log.info("analysis_cgdcont end", tmp, loc, data)
        end
        if tmp then
            local cid, pdptyp, apn, addr = string.match(tmp, "(%d+),(.+),(.+),[\"\'](.+)[\"\']")
            if not cid or not pdptyp or not apn or not addr then
                log.info("analysis_cgdcont CGDCONT is empty")
                ipAddr = ""
                result = false
            else
                log.info("analysis_cgdcont ", cid, pdptyp, apn, addr)
                if addr:match("%d+%.%d+%.%d+%.%d") then
                    ipAddr = addr
                    return true
                else
                    log.info("analysis_cgdcont CGDCONT is empty1")
                    ipAddr = ""
                    return false
                end
            end
        else
            ipAddr = ""
            log.info("analysis_cgdcont tmp is empty")
        end
    end

    return result
end

function IsCidActived(cid, data)
    if not data then
        return
    end
    for k, v in string.gfind(data, "(%d+),%s*(%d)") do
        log.info("iscidactived ", k, v)
        if cid == tonumber(k) and v == '1' then
            return true
        end
    end

    return
end

function IsExistActivedCid(data)
    if not data then
        return
    end
    for k, v in string.gfind(data, "(%d+),%s*(%d)") do
        if v == '1' then
            log.info("ExistActivedCid ", k, v)
            return true
        end
    end
    return
end

local cgdcontResult

function cgdcontRsp()
    if cgdcontResult then
        pdpCmdCnf("CONNECT_DELAY", true)
    end
end

function pdpCmdCnf(curCmd, result, respdata, interdata)
    log.info("link.pdpCmdCnf", curCmd, result, respdata, interdata)
    if string.find(curCmd, "CGDCONT%?") then
        if result and interdata then
            result = analysis_cgdcont(interdata)
        else
            result = false
        end
    end

    if result then
        cgdcontResult = false
        if string.find(curCmd, "CGDCONT=") then
            request(string.format('AT+CGACT=1,%d', cid_manual), nil, pdpCmdCnf)
        elseif string.find(curCmd, "CGDCONT%?") then
            -- sys.timerStart(pdpCmdCnf, 100, "CONNECT_DELAY",true)
            cgdcontResult = true
        elseif string.find(curCmd, "CONNECT_DELAY") and network == CELLULAR then
            log.info("publish IP_READY_IND")
            readyTable[CELLULAR] = true
            publish("IP_READY_IND")
        elseif string.find(curCmd, "CGACT=") then
            request("AT+CGDCONT?", nil, cgdcontRsp)
        elseif string.find(curCmd, "CGACT%?") then
            if IsExistActivedCid(interdata) then
                sys.timerStart(pdpCmdCnf, 100, "CONNECT_DELAY", true)
            else
                request(string.format('AT+CGDCONT=%d,"IP","%s"', cid_manual, authApn or apnname), nil, pdpCmdCnf)
            end
        elseif string.find(curCmd, "CGDFLT") then
            request("AT+CGDCONT?", nil, cgdcontRsp)
        elseif string.find(curCmd, "SET_PDP_4G_WAITAPN") then
            if not apnname then
                sys.timerStart(pdpCmdCnf, 100, "SET_PDP_4G_WAITAPN", true)
            else
                request("AT+CGDCONT?", nil, cgdcontRsp, 1000)
                --   request(string.format('AT*CGDFLT=0,"IP","%s"', apnname), nil, pdpCmdCnf)
            end
        end
    else
        if net.getState() ~= 'REGISTERED' then
            return
        end
        if net.getNetMode() == net.NetMode_LTE then
            request("AT+CGDCONT?", nil, cgdcontRsp, 1000)
        else
            request("AT+CGATT?", nil, nil, 1000)
        end
    end
end

-- SIM卡 IMSI READY以后自动设置APN
sys.subscribe("IMSI_READY", function()
    if not apnname then -- 如果未设置APN设置默认APN
        local mcc, mnc = tonumber(sim.getMcc(), 16), tonumber(sim.getMnc(), 16)
        apnname, username, password = apn and apn.get_default_apn(mcc, mnc) -- 如果存在APN库自动获取运营商的APN
        if not apnname or apnname == '' or apnname == "CMNET" then -- 默认情况，如果联通卡设置为联通APN 其他都默认为CMIOT
            apnname = (mcc == 0x460 and (mnc == 0x01 or mnc == 0x06)) and 'UNINET' or 'CMIOT'
        end
    end
    username = username or ''
    password = password or ''
end)

ril.regRsp('+CGATT', function(a, b, c, intermediate)
    local attached = (intermediate == "+CGATT: 1")
    if gprsAttached ~= attached then
        gprsAttached = attached
        sys.publish("GPRS_ATTACH", attached)
    end

    if readyTable[CELLULAR] then
        return
    end

    if attached then
        log.info("pdp active", apnname, username, password)
        request("AT+CGACT?", nil, pdpCmdCnf, 1000)
    elseif net.getState() == 'REGISTERED' then
        sys.timerStart(request, 2000, "AT+CGATT=1")
        sys.timerStart(request, 2000, "AT+CGATT?")
    end
end)

rtos.on(rtos.MSG_PDP_DEACT_IND, function()
    if network~=CELLULAR then
        return
    end
    readyTable[CELLULAR] = false
    sys.publish('IP_ERROR_IND')

    if net.getState() ~= 'REGISTERED' then
        return
    end
    sys.timerStart(Pdp_Act, 2000)
end)

-- 网络注册成功 :AT+CGDCONT?查询默认承载是否激活
--            2/3G发起GPRS附着状态查询
sys.subscribe("NET_STATE_REGISTERED", Pdp_Act)

local function cindCnf(cmd, result)
    if not result then
        request("AT+CIND=1", nil, cindCnf, 1000)
    end
end

local function cgevurc(data)
    if network~=CELLULAR then
        return
    end
    local cid = 0
    log.info("link.cgevurc", data)

    if string.match(data, "DEACT") then
        cid = string.match(data, "DEACT,(%d)")
        cid = tonumber(cid)

        if cid == cid_manual then
            request("AT+CFUN?")
            readyTable[CELLULAR] = false
            sys.publish('IP_ERROR_IND')
            sys.publish('PDP_DEACT_IND')
            if net.getState() ~= 'REGISTERED' then
                return
            end
            sys.timerStart(Pdp_Act, 2000)
        end
    end

end

request("AT+CIND=1", nil, cindCnf)
ril.regUrc("*CGEV", cgevurc)
ril.regUrc("+CGDCONT", function(data)
    pdpCmdCnf("AT+CGDCONT?", true, "OK", data)
end)

--- 打开链路层网络类型
-- 注意：设置网络类型后，并不会关机保存，下次开机会自动恢复为默认的link.CELLULAR类型
-- @number[opt=link.CELLULAR] mode，取值如下：
--              link.CELLULAR：蜂窝模组数据网络
--              link.CH395：CH395以太网络
--              link.W5500：W5500以太网络
-- @table[opt=nil] para，取值如下：
--                 当mode为link.CELLULAR时，参数para无意义，可以直接传入nil
--                 当mode为link.CH395，para为table类型，表示以太网的配置参数，参数结构如下：
--                para= {
--                     mode = 1,      --1表示客户端；2表示服务器；默认为1
--                     intPin = pio.P0_22,      --以太网芯片中断通知引脚
--                     rstPin = pio.P0_23,      --复位以太网芯片引脚
--                     spiCs = pio.P0_23,      --spi片选
--                     serverAddr = "192.168.1.112",      --做服务器应用时，本机的地址
--                     serverPort = 1888,      --做服务器应用时，本机的端口
--                     serverGateway = "192.168.1.1",      --做服务器应用时，本机的网关地址
--                     powerFunc=function(state) end           --控制以太网模块的供电开关函数，ret为true开启供电，false关闭供电
--                     spi = {spi.SPI_1,0,0,8,800000},      --SPI通道参数，id,cpha,cpol,dataBits,clock，默认spi.SPI_1,0,0,8,800000
--                 }
-- @return true/false,执行成功返回true,失败返回false。
-- @usage
-- 设置为蜂窝数据网络：
-- c = link.setNetwork(link.CELLULAR, para)
-- 设置为CH395以太网络：
-- link.setNetwork(link.CH395, para)
-- 设置为w5500以太网络：
-- link.setNetwork(link.W5500, para)
function openNetwork(mode, para)
    local tSocketModule = {
        [CH395] = socketCh395,
        [W5500] = socketW5500
    }
    local md = mode or CELLULAR
        closeNetWork()
        network = md
        if network == CELLULAR then
            net.switchFly(false)
            return true
        else
            ipAddr=tSocketModule[network].open(para)
            if ipAddr~="" then
                return true
            else
                log.info('link','open CH395 err')
                return false
            end
        end
        return false
end

--- 关闭链路层网络类型
-- 注意：关闭链路层网络类型，不会改变链路层网络类型，需要打开链路层网络类型配置才能切换。
-- @return true/false,执行成功返回true,失败返回false。
-- @usage
-- 关闭链路层网络类型：
-- link.closeNetWork()
function closeNetWork()
    local tSocketModule =  {
        [CH395] = socketCh395,
        [W5500] = socketW5500
    }

    if network == CELLULAR then
        -- 飞行模式
        net.switchFly(true)
        return true
    else
        return tSocketModule[network].close()
    end
    return false
end

--- 获取链路层网络类型
-- @return network，number类型，取值如下：
--              link.CELLULAR：蜂窝模组数据网络
--              link.CH395：CH395以太网络
--              link.W5500：W5500以太网络
-- @usage
-- 获取数据网络类型：
-- mode = link.getNetwork()
function getNetwork()
    return network
end
