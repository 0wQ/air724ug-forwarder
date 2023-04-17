---模块功能：网络管理、信号查询、GSM网络状态查询、网络指示灯控制、临近小区信息查询
-- @module net
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.02.17

require "sys"
require "ril"
require "pio"
require "sim"
require "log"
require "utils"
module(..., package.seeall)

--加载常用的全局函数至本地
local publish = sys.publish

--netmode define
NetMode_noNet=   0
NetMode_GSM=     1--2G
NetMode_EDGE=    2--2.5G
NetMode_TD=      3--3G
NetMode_LTE=     4--4G
NetMode_WCDMA=   5--3G
local netMode = NetMode_noNet

--网络状态：
--INIT：开机初始化中的状态
--REGISTERED：注册上GSM网络
--UNREGISTER：未注册上GSM网络
local state = "INIT"
--SIM卡状态：true为异常，false或者nil为正常
local simerrsta
-- 飞行模式状态
flyMode = false

--lac：位置区ID
--ci：小区ID
--rssi：信号强度
--rsrp：信号接收功率
local lac, ci, rssi, rsrp, band = "", "", 0, 0, ""

--cellinfo：当前小区和临近小区信息表
--multicellcb：获取多小区的回调函数
local cellinfo, multicellcb = {}
local curCellSeted

local function cops(data)
    --+COPS: 0,2,"46000",7
    local fmt,oper = data:match('COPS:%s*%d+%s*,(%d+)%s*,"(%d+)"')
    log.info("cops",fmt,oper,curCellSeted)
    if fmt=="2" and not curCellSeted then
        cellinfo[1].mcc = tonumber(oper:sub(1,3),16)
        cellinfo[1].mnc = tonumber(oper:sub(4,5),16)
    end
end

--[[
函数名：creg
功能  ：解析CREG信息
参数  ：data：CREG信息字符串，例如+CREG: 2、+CREG: 1,"18be","93e1"、+CREG: 5,"18a7","cb51"
返回值：无
]]
local function creg(data)
    local p1, s,act
    local prefix = (netMode == NetMode_LTE) and "+CEREG: " or (netMode == NetMode_noNet and "+CREG: " or "+CGREG: ")
    log.info("net.creg1",netMode,prefix)
    if not data:match(prefix) then
        --log.info("net.creg2",prefix)
        if prefix=="+CREG: " then
            --log.info("net.creg3")
            prefix = "+CGREG: "
            if not data:match("+CGREG: ") then
                log.warn("net.creg1","no match",data)
                return
            end
        elseif prefix=="+CGREG: " then
            --log.info("net.creg4")
            prefix = "+CREG: "
            if not data:match("+CREG: ") then
                log.warn("net.creg2","no match",data)
                return
            end
        end        
    end
    --获取注册状态
    _, _, p1 = data:find(prefix .. "%d,(%d+)")
    --log.info("net.creg5",p1 == nil)
    if p1 == nil then
        _, _, p1 = data:find(prefix .. "(%d+)")
        --log.info("net.creg6",p1 == nil)
        if p1 == nil then return end
        act = data:match(prefix .. "%d+,.-,.-,(%d+)")
    else
        act = data:match(prefix .. "%d,%d+,.-,.-,(%d+)")
    end
    
    log.info("net.creg7",p1,act)

    --设置注册状态
    s = (p1=="1" or p1=="5") and "REGISTERED" or "UNREGISTER"
    
    --log.info("net.creg8",s,state)
    if prefix=="+CGREG: " and s=="UNREGISTER" then
        log.info("net.creg9 ignore!!!")
        return
    end
    --注册状态发生了改变
    if s ~= state then
        --临近小区查询处理
        if s == "REGISTERED" then
            --产生一个内部消息NET_STATE_CHANGED，表示GSM网络注册状态发生变化
            publish("NET_STATE_REGISTERED")
            cengQueryPoll()
        end
        state = s
    end
    --已注册并且lac或ci发生了变化
    if state == "REGISTERED" then
        p2, p3 = data:match("\"(%x+)\",\"(%x+)\"")
        if p2 and p3 and (lac ~= p2 or ci ~= p3) then
            lac = p2
            ci = p3
            --产生一个内部消息NET_CELL_CHANGED，表示lac或ci发生了变化
            publish("NET_CELL_CHANGED")
            --cellinfo[1].mcc = tonumber(sim.getMcc(),16)
            --cellinfo[1].mnc = tonumber(sim.getMnc(),16)
            cellinfo[1].lac = tonumber(lac,16)
            cellinfo[1].ci = tonumber(ci,16)
            cellinfo[1].rssi = 28
        end

        if act then
            if act=="0" then
                UpdNetMode("^MODE: 3,1")
            elseif act=="1" then
                UpdNetMode("^MODE: 3,2")
            elseif act=="3" then
                UpdNetMode("^MODE: 3,3")
            elseif act=="7" then
                UpdNetMode("^MODE: 17,17")
            else
                UpdNetMode("^MODE: 5,7")
            end
        end
    end
end

--[[
函数名：resetcellinfo
功能  ：重置当前小区和临近小区信息表
参数  ：无
返回值：无
]]
local function resetCellInfo()
    local i
    cellinfo.cnt = 11 --最大个数
    for i = 1, cellinfo.cnt do
        cellinfo[i] = {}
        cellinfo[i].mcc, cellinfo[i].mnc = nil
        cellinfo[i].lac = 0
        cellinfo[i].ci = 0
        cellinfo[i].rssi = 0
        cellinfo[i].ta = 0
    end
end

--[[
函数名：eemMgInfoSvc
功能  ：解析4G网络，当前小区和临近小区信息
参数  ：
data：当前小区和临近小区信息字符串，例如下面中的每一行：
+EEMLTESVC:xx,xx,...
返回值：无
]]
local function eemLteSvc(data)
    local mcc,mnc,lac,ci,rssi,svcData
    if data:match("%+EEMLTESVC:%s*%d+,%s*%d+,%s*%d+,%s*.+") then
        svcData = string.match(data, "%+EEMLTESVC:(.+)")
        --log.info("eemLteSvc",svcData)
        if svcData then
            svcDataT = string.split(svcData, ', ')
            --log.info("eemLteSvc1",svcDataT[1],svcDataT[3],svcDataT[4],svcDataT[10],svcDataT[15])
            if not(svcDataT[1] and svcDataT[3] and svcDataT[4] and svcDataT[10] and svcDataT[15]) then
                svcDataT = string.split(svcData, ',')
                log.info("eemLteSvc2",svcDataT[1],svcDataT[3],svcDataT[4],svcDataT[10],svcDataT[15])
            end
            mcc = svcDataT[1]
            mnc = svcDataT[3]
            lac = svcDataT[4]
            ci = svcDataT[10]
			band = svcDataT[8]
            rssi = (tonumber(svcDataT[15])-(tonumber(svcDataT[15])%3))/3
            if rssi>31 then rssi=31 end
            if rssi<0 then rssi=0 end
        end
        log.info("eemLteSvc1",lac,ci,mcc,mnc)
        if lac and lac~="0" and ci and ci ~= "0" and mcc and mnc then
            --如果是第一条，清除信息表
            resetCellInfo()
            curCellSeted = true
            --保存mcc、mnc、lac、ci、rssi、ta
            cellinfo[1].mcc = mcc
            cellinfo[1].mnc = mnc
            cellinfo[1].lac = tonumber(lac)
            cellinfo[1].ci = tonumber(ci)
            cellinfo[1].rssi = tonumber(rssi)
            --cellinfo[id + 1].ta = tonumber(ta or "0")
            --产生一个内部消息CELL_INFO_IND，表示读取到了新的当前小区和临近小区信息
            if multicellcb then multicellcb(cellinfo) end
            publish("CELL_INFO_IND", cellinfo)
        end
    elseif data:match("%+EEMLTEINTER") or data:match("%+EEMLTEINTRA") or data:match("%+EEMLTEINTERRAT") then
        --data = "+EEMLTEINTRA: 0, 98, 39148, 51, 21, 1120, 0, 6311, 25418539"
        --data = "+EEMLTEINTERRAT:0,16,1120,0,6213,26862,627,1,-77"
        data = data:gsub(" ","")

        if data:match("%+EEMLTEINTERRAT") then
            mcc,mnc,lac,ci,rssi = data:match("[-]*%d+,[-]*%d+,([-]*%d+),([-]*%d+),([-]*%d+),([-]*%d+),[-]*%d+,[-]*%d+,([-]*%d+)")
        else
            rssi,mcc,mnc,lac,ci = data:match("[-]*%d+,[-]*%d+,[-]*%d+,([-]*%d+),[-]*%d+,([-]*%d+),([-]*%d+),([-]*%d+),([-]*%d+)")
        end
        
        --print(mcc,mnc,lac,ci,rssi)

        if rssi then
            rssi = (rssi-(rssi%3))/3
            if rssi>31 then rssi=31 end
            if rssi<0 then rssi=0 end
        end
        if lac~="0" and lac~="-1" and ci~="0" and ci~="-1" then
            for i = 1, cellinfo.cnt do
                --print("cellinfo["..i.."].lac="..cellinfo[i].lac)
                if cellinfo[i].lac==0 then
                    cellinfo[i] = 
                    {
                        mcc = mcc,
                        mnc = mnc,
                        lac = tonumber(lac),
                        ci = tonumber(ci),
                        rssi = tonumber(rssi)
                    }
                    break
                end
            end
        end
    end
end
--[[
函数名：eemMgInfoSvc
功能  ：解析2G网络，当前小区
参数  ：
data：当前小区信息字符串，例如下面中的每一行：
+EEMGINFOSVC:xx,xx,...
返回值：无
]]
local function eemGsmInfoSvc(data)
	--只处理有效的CENG信息
	if string.find(data, "%+EEMGINFOSVC:%s*%d+,%s*%d+,%s*%d+,%s*.+") then
		local mcc,mnc,lac,ci,ta,rssi
		local svcData = string.match(data, "%+EEMGINFOSVC:(.+)")
		if svcData then
			svcDataT = string.split(svcData, ', ')
			mcc = svcDataT[1]
			mnc = svcDataT[2]
			lac = svcDataT[3]
			ci = svcDataT[4]
			ta = svcDataT[10]
			rssi = svcDataT[12]
			if tonumber(rssi) >31
				then rssi = 31
			end
			if tonumber(rssi) < 0
				then rssi = 0
			end
		end
		if lac and lac~="0" and ci and ci ~= "0" and mcc and mnc then
			--如果是第一条，清除信息表
			resetCellInfo()
         curCellSeted = true
			--保存mcc、mnc、lac、ci、rssi、ta
			cellinfo[1].mcc = mcc
			cellinfo[1].mnc = mnc
			cellinfo[1].lac = tonumber(lac)
			cellinfo[1].ci = tonumber(ci)
			cellinfo[1].rssi = (tonumber(rssi) == 99) and 0 or tonumber(rssi)
			cellinfo[1].ta = tonumber(ta or "0")
			--产生一个内部消息CELL_INFO_IND，表示读取到了新的当前小区和临近小区信息
			if multicellcb then multicellcb(cellinfo) end
			publish("CELL_INFO_IND", cellinfo)
		end
	end
end
--[[
函数名：eemMgInfoSvc
功能  ：解析2G网络，临近小区信息
参数  ：
data：当前小区和临近小区信息字符串，例如下面中的每一行：
+EEMGINFOSVC:xx,xx,...
返回值：无
]]
local function eemGsmNCInfoSvc(data)
	if string.find(data, "%+EEMGINFONC: %d+, %d+, %d+, .+") then
		local mcc,mnc,lac,ci,ta,rssi,id
		local svcData = string.match(data, "%+EEMGINFONC:(.+)")
		if svcData then
			svcDataT = string.split(svcData, ', ')
			id = svcDataT[1]
			mcc = svcDataT[2]
			mnc = svcDataT[3]
			lac = svcDataT[4]
			ci = svcDataT[6]
			rssi = svcDataT[7]
			if tonumber(rssi) >31
				then rssi = 31
			end
			if tonumber(rssi) < 0
				then rssi = 0
			end
		end
		if lac and ci and mcc and mnc then
			--保存mcc、mnc、lac、ci、rssi、ta
			cellinfo[id + 2].mcc = mcc
			cellinfo[id + 2].mnc = mnc
			cellinfo[id + 2].lac = tonumber(lac)
			cellinfo[id + 2].ci = tonumber(ci)
			cellinfo[id + 2].rssi = (tonumber(rssi) == 99) and 0 or tonumber(rssi)
			--cellinfo[id + 1].ta = tonumber(ta or "0")
		end
	end
end
--[[
函数名：eemMgInfoSvc
功能  ：解析3G网络，当前小区和临近小区信息
参数  ：
data：当前小区和临近小区信息字符串，例如下面中的每一行：
+EEMUMTSSVC:xx,xx,...
返回值：无
]]
local function eemUMTSInfoSvc(data)
	--只处理有效的CENG信息
	if string.find(data, "%+EEMUMTSSVC: %d+, %d+, %d+, .+") then
		local mcc,mnc,lac,ci,rssi
		local svcData = string.match(data, "%+EEMUMTSSVC:(.+)")
		local cellMeasureFlag, cellParamFlag = string.match(data, "%+EEMUMTSSVC:%d+, (%d+), (%d+), .+")
		local svcDataT = string.split(svcData, ', ')
		local offset = 4
		if svcData and svcDataT then
			if tonumber(cellMeasureFlag) ~= 0 then
				offset = offset + 2
				rssi = svcDataT[offset]
				offset = offset + 4
			else 
				offset = offset + 2
				rssi = svcDataT[offset]
				offset = offset + 2
			end

			if tonumber(cellParamFlag) ~= 0 then
				offset = offset + 3
				mcc = svcDataT[offset]
				mnc = svcDataT[offset + 1]
				lac = svcDataT[offset + 2]
				ci  = svcDataT[offset + 3]
				offset = offset + 3
			end
		end
		if lac and lac~="0" and ci and ci ~= "0" and mcc and mnc and rssi then
			--如果是第一条，清除信息表
			resetCellInfo()
         curCellSeted = true   
			--保存mcc、mnc、lac、ci、rssi、ta
			cellinfo[1].mcc = mcc
			cellinfo[1].mnc = mnc
			cellinfo[1].lac = tonumber(lac)
			cellinfo[1].ci = tonumber(ci)
			cellinfo[1].rssi = tonumber(rssi)
			--产生一个内部消息CELL_INFO_IND，表示读取到了新的当前小区和临近小区信息
			if multicellcb then multicellcb(cellinfo) end
			publish("CELL_INFO_IND", cellinfo)
		end
	end
end

--[[
函数名：UpdNetMode
功能  ：解析NetMode
参数  ：data：NetMode信息字符串，例如"^MODE: 17,17"
返回值：无
]]
function UpdNetMode(data)
	local _, _, SysMainMode,SysMode = string.find(data, "(%d+),(%d+)")
	local netMode_cur
	log.info("net.UpdNetMode",netMode_cur,netMode, SysMainMode,SysMode)
	if SysMainMode and SysMode then
		if SysMainMode=="3" then
			netMode_cur = NetMode_GSM
		elseif SysMainMode=="5" then
			netMode_cur = NetMode_WCDMA
		elseif SysMainMode=="15" then
			netMode_cur = NetMode_TD
		elseif SysMainMode=="17" then
			netMode_cur = NetMode_LTE
		else
			netMode_cur = NetMode_noNet
		end
		
		if SysMode=="3" then
			netMode_cur = NetMode_EDGE
		end
	end
  
	if netMode ~= netMode_cur then
		netMode = netMode_cur
		publish("NET_UPD_NET_MODE",netMode)
		log.info("net.NET_UPD_NET_MODE",netMode)   
		ril.request("AT+COPS?")
		if netMode == NetMode_LTE then 
			ril.request("AT+CEREG?")  
		elseif netMode == NetMode_noNet then 
			ril.request("AT+CREG?")  
		else
			ril.request("AT+CGREG?")  
		end
	end
end

--[[
函数名：neturc
功能  ：本功能模块内“注册的底层core通过虚拟串口主动上报的通知”的处理
参数  ：
data：通知的完整字符串信息
prefix：通知的前缀
返回值：无
]]
local function neturc(data, prefix)
    if prefix=="+COPS" then
        cops(data)
    elseif prefix == "+CREG" or prefix == "+CGREG" or prefix == "+CEREG" then
        --收到网络状态变化时,更新一下信号值
        csqQueryPoll()
        --解析creg信息
        creg(data)
    elseif prefix == "+EEMLTESVC" or prefix == "+EEMLTEINTRA" or prefix == "+EEMLTEINTER" or prefix=="+EEMLTEINTERRAT" then
        eemLteSvc(data)
    elseif prefix == "+EEMUMTSSVC" then
        eemUMTSInfoSvc(data)
    elseif prefix == "+EEMGINFOSVC" then
        eemGsmInfoSvc(data)
    elseif prefix == "+EEMGINFONC" then
        eemGsmNCInfoSvc(data)   
    elseif prefix == "^MODE" then
        UpdNetMode(data)
    end
end

--- 设置飞行模式
-- 注意：如果要测试飞行模式的功耗，开机后不要立即调用此接口进入飞行模式
-- 在模块注册上网络之前，调用此接口进入飞行模式不仅无效，还会导致功耗数据异常
-- 详情参考：http://doc.openluat.com/article/488/0
-- @bool mode，true:飞行模式开，false:飞行模式关
-- @return nil
-- @usage net.switchFly(mode)
function switchFly(mode)
	if flyMode == mode then return end
	flyMode = mode
	-- 处理飞行模式
	if mode then
		ril.request("AT+CFUN=0")
	-- 处理退出飞行模式
	else
		ril.request("AT+CFUN=1")
		--处理查询定时器
		csqQueryPoll()
		cengQueryPoll()
		--复位GSM网络状态
		neturc("2", "+CREG")
	end
end

--- 获取netmode
-- @return number netMode,注册的网络类型
-- 0：未注册
-- 1：2G GSM网络
-- 2：2.5G EDGE数据网络
-- 3：3G TD网络
-- 4：4G LTE网络
-- 5：3G WCDMA网络
-- @usage net.getNetMode()
function getNetMode()
	return netMode
end

--- 获取网络注册状态
-- @return string state,GSM网络注册状态，
-- "INIT"表示正在初始化
-- "REGISTERED"表示已注册
-- "UNREGISTER"表示未注册
-- @usage net.getState()
function getState()
	return state
end

--- 获取当前小区的mcc
-- @return string mcc,当前小区的mcc，如果还没有注册GSM网络，则返回sim卡的mcc
-- @usage net.getMcc()
function getMcc()
	return cellinfo[1].mcc and string.format("%x",cellinfo[1].mcc) or sim.getMcc()
end

--- 获取当前小区的mnc
-- @return string mcn,当前小区的mnc，如果还没有注册GSM网络，则返回sim卡的mnc
-- @usage net.getMnc()
function getMnc()
	return cellinfo[1].mnc and string.format("%x",cellinfo[1].mnc) or sim.getMnc()
end

--- 获取当前位置区ID
-- @return string lac,当前位置区ID(16进制字符串，例如"18be")，如果还没有注册GSM网络，则返回""
-- @usage net.getLac()
function getLac()
	return lac
end

--- 获取当前注册的网络频段
-- @return string band,当前注册的网络频段，如果还没有注册网络，则返回""
-- @usage net.getBand()
function getBand()
	return band
end

--- 获取当前小区ID
-- @return string ci,当前小区ID(16进制字符串，例如"93e1")，如果还没有注册GSM网络，则返回""
-- @usage net.getCi()
function getCi()
	return ci
end

--- 获取信号强度
-- 当前注册的是2G网络，就是2G网络的信号强度
-- 当前注册的是4G网络，就是4G网络的信号强度
-- @return number rssi,当前信号强度(取值范围0-31)
-- @usage net.getRssi()
function getRssi()
	return rssi
end

--- 4G网络信号接收功率
-- @return number rsrp,当前信号接收功率(取值范围-140 - -40)
-- @usage net.getRsrp()
function getRsrp()
	return rsrp
end

function getCell()
	local i,ret = 1,""
	for i=1,cellinfo.cnt do
		if cellinfo[i] and cellinfo[i].lac and cellinfo[i].lac ~= 0 and cellinfo[i].ci and cellinfo[i].ci ~= 0 then
			ret = ret..cellinfo[i].ci.."."..cellinfo[i].rssi.."."
		end
	end
	return ret
end

--- 获取当前和临近位置区、小区以及信号强度的拼接字符串
-- @return string cellInfo,当前和临近位置区、小区以及信号强度的拼接字符串，例如："6311.49234.30;6311.49233.23;6322.49232.18;"
-- @usage net.getCellInfo()
function getCellInfo()
	local i, ret = 1, ""
	for i = 1, cellinfo.cnt do
		if cellinfo[i] and cellinfo[i].lac and cellinfo[i].lac ~= 0 and cellinfo[i].ci and cellinfo[i].ci ~= 0 then
			ret = ret .. cellinfo[i].lac .. "." .. cellinfo[i].ci .. "." .. cellinfo[i].rssi .. ";"
		end
	end
	return ret
end

--- 获取当前和临近位置区、小区、mcc、mnc、以及信号的拼接字符串
-- @bool[opt=nil] rssi，信号是否拼接功率，true表示功率，false或者nil表示强度
--                      表示强度时，信号的取值范围是0到31
--                      表示功率时，信号的计算公式为 强度*2-113，取值范围为-113dB到-51dB
-- @return string cellInfo,当前和临近位置区、小区、mcc、mnc、以及信号的拼接字符串，例如：
--                      当rssi参数为true时，"460.01.6311.49234.-73;460.01.6311.49233.-67;460.02.6322.49232.-77;"
--                      当rssi参数为false或者nil时，"460.01.6311.49234.30;460.01.6311.49233.23;460.02.6322.49232.18;"
-- @usage net.getCellInfoExt()
function getCellInfoExt(rssi)
	local i, ret = 1, ""
	for i = 1, cellinfo.cnt do
		if cellinfo[i] and cellinfo[i].mcc and cellinfo[i].mnc and cellinfo[i].lac and cellinfo[i].lac ~= 0 and cellinfo[i].ci and cellinfo[i].ci ~= 0 then
			ret = ret .. string.format("%x",cellinfo[i].mcc) .. "." .. string.format("%x",cellinfo[i].mnc) .. "." .. cellinfo[i].lac .. "." .. cellinfo[i].ci .. "." .. (rssi and (cellinfo[i].rssi*2-113) or cellinfo[i].rssi) .. ";"
		end
	end
	return ret
end

--- 获取TA值
-- @return number ta,TA值
-- @usage net.getTa()
function getTa()
	return cellinfo[1].ta
end

--[[
函数名：rsp
功能  ：本功能模块内“通过虚拟串口发送到底层core软件的AT命令”的应答处理
参数  ：
cmd：此应答对应的AT命令
success：AT命令执行结果，true或者false
response：AT命令的应答中的执行结果字符串
intermediate：AT命令的应答中的中间信息
返回值：无
]]
local function rsp(cmd, success, response, intermediate)
	local prefix = string.match(cmd, "AT(%+%u+)")
	
	if intermediate ~= nil then
		if prefix == "+CSQ" then
			local s = string.match(intermediate, "+CSQ:%s*(%d+)")
			if s ~= nil then
				rssi = tonumber(s)
				rssi = rssi == 99 and 0 or rssi
				--产生一个内部消息GSM_SIGNAL_REPORT_IND，表示读取到了信号强度
				publish("GSM_SIGNAL_REPORT_IND", success, rssi)
			end
		elseif prefix == "+CESQ" then
	        local s = string.match(intermediate, "+CESQ: %d+,%d+,%d+,%d+,%d+,(%d+)")
			if s ~= nil then
				rsrp = tonumber(s)
			end
		elseif prefix == "+CENG" then end
	end
    if prefix == "+CFUN" then
        if success then publish("FLYMODE", flyMode) end
    end
end

--- 实时读取“当前和临近小区信息”
-- @function cbFnc，回调函数，当读取到小区信息后，会调用此回调函数，回调函数的调用形式为：
-- cbFnc(cells)，其中cells为string类型，格式为：当前和临近位置区、小区、mcc、mnc、以及信号强度的拼接字符串，例如："460.01.6311.49234.30;460.01.6311.49233.23;460.02.6322.49232.18;"
-- @return nil
function getMultiCell(cbFnc)
	multicellcb = cbFnc
	--发送AT+CENG?查询
	ril.request("AT+EEMGINFO?")
end

--- 发起查询基站信息(当前和临近小区信息)的请求
-- @number period 查询间隔，单位毫秒
-- @return bool result, true:查询成功，false:查询失败
-- @usage net.cengQueryPoll() --查询1次
-- @usage net.cengQueryPoll(60000) --每分钟查询1次
function cengQueryPoll(period)
	-- 不是飞行模式 并且 工作模式为完整模式
	if not flyMode then
		--发送AT+CENG?查询
		ril.request("AT+EEMGINFO?")
	else
		log.warn("net.cengQueryPoll", "flymode:", flyMode)
	end
	if nil ~= period then
		--启动定时器
		sys.timerStopAll(cengQueryPoll)
		sys.timerStart(cengQueryPoll, period, period)
	end
	return not flyMode
end

--- 发起查询信号强度的请求
-- @number period 查询间隔，单位毫秒
-- @return bool , true:查询成功，false:查询停止
-- @usage net.csqQueryPoll() --查询1次
-- @usage net.csqQueryPoll(60000) --每分钟查询1次
function csqQueryPoll(period)
    --不是飞行模式 并且 工作模式为完整模式
    if not flyMode then        
        --发送AT+CSQ查询
        ril.request("AT+CSQ")
        ril.request("AT+CESQ")
    else
        log.warn("net.csqQueryPoll", "flymode:", flyMode)
    end
    if nil ~= period then
        --启动定时器
        sys.timerStopAll(csqQueryPoll)
        sys.timerStart(csqQueryPoll, period, period)
    end
    return not flyMode
end


--- 设置查询信号强度和基站信息的间隔
-- @number ... 查询周期,参数可变，参数为nil只查询1次，参数1是信号强度查询周期，参数2是基站查询周期
-- @return bool ，true：设置成功，false：设置失败
-- @usage net.startQueryAll()
-- @usage net.startQueryAll(60000) -- 1分钟查询1次信号强度，只立即查询1次基站信息
-- @usage net.startQueryAll(60000,600000) -- 1分钟查询1次信号强度，10分钟查询1次基站信息
function startQueryAll(...)
	local arg = { ... }
    csqQueryPoll(arg[1])
    cengQueryPoll(arg[2])
    if flyMode then        
        log.info("sim.startQuerAll", "flyMode:", flyMode)
    end
    return true
end

--- 停止查询信号强度和基站信息
-- @return 无
-- @usage net.stopQueryAll()
function stopQueryAll()
    sys.timerStopAll(csqQueryPoll)
    sys.timerStopAll(cengQueryPoll)
end

local sEngMode
--- 设置工程模式
-- @number[opt=1] mode，工程模式，目前仅支持0和1
-- mode为0时，不支持临近小区查询，休眠时功耗较低
-- mode为1时，支持临近小区查询，但是休眠时功耗较高
-- @return nil
-- @usage
-- net.setEngMode(0)
function setEngMode(mode)
    sEngMode = mode or 1
    ril.request("AT+EEMOPT="..sEngMode,nil,function(cmd,success)
            function retrySetEngMode()
                setEngMode(sEngMode)
            end
            if success then
                sys.timerStop(retrySetEngMode)
            else
                sys.timerStart(retrySetEngMode,3000)
            end
        end)
end

-- 处理SIM卡状态消息，SIM卡工作不正常时更新网络状态为未注册
sys.subscribe("SIM_IND", function(para)
	log.info("SIM.subscribe", simerrsta, para)
	if simerrsta ~= (para ~= "RDY") then
		simerrsta = (para ~= "RDY")
	end
	--sim卡工作不正常
	if para ~= "RDY" then
		--更新GSM网络状态
		state = "UNREGISTER"
		--产生内部消息NET_STATE_CHANGED，表示网络状态发生变化
		publish("NET_STATE_UNREGISTER")
	else
		--state = "INIT"
	end
end)

--注册+CREG和+CENG通知的处理函数
ril.regUrc("+COPS", neturc)
ril.regUrc("+CREG", neturc)
ril.regUrc("+CGREG", neturc)
ril.regUrc("+CEREG", neturc)
--ril.regUrc("+CENG", neturc)
ril.regUrc("+EEMLTESVC", neturc)
ril.regUrc("+EEMLTEINTER", neturc)
ril.regUrc("+EEMLTEINTRA", neturc)
ril.regUrc("+EEMLTEINTERRAT", neturc)
ril.regUrc("+EEMGINFOSVC", neturc)
ril.regUrc("+EEMGINFONC", neturc)
ril.regUrc("+EEMUMTSSVC", neturc)
ril.regUrc("^MODE", neturc)
--ril.regUrc("+CRSM", neturc)
--注册AT+CCSQ和AT+CENG?命令的应答处理函数
ril.regRsp("+CSQ", rsp)
ril.regRsp("+CESQ",rsp)
--ril.regRsp("+CENG", rsp)
ril.regRsp("+CFUN", rsp)-- 飞行模式
--发送AT命令
ril.request("AT+COPS?")
ril.request("AT+CREG=2")
ril.request("AT+CGREG=2")
ril.request("AT+CEREG=2")
ril.request("AT+CREG?")
ril.request("AT+CGREG?")
ril.request("AT+CEREG?")
ril.request("AT+CALIBINFO?")
ril.request("AT*BAND?")
setEngMode(1)
--重置当前小区和临近小区信息表
resetCellInfo()
