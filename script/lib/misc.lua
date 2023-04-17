--- 模块功能：配置管理-序列号、IMEI、底层软件版本号、时钟、是否校准、飞行模式、查询电池电量等功能
-- @module misc
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.10.20
require "ril"
local req = ril.request
module(..., package.seeall)
--sn：序列号
--imei：IMEI
--modeltype:模块型号，例如724，720，722等
--calib: 校准标志
--ant: 耦合测试标志位
--temp:模块温度
local sn, imei, calib, ver, muid, ant,modeltype,temp
local setSnCbFnc,setImeiCbFnc,setClkCbFnc,getTemperatureCbFnc

local function timeReport()
    sys.publish("TIME_CLK_IND")
    sys.timerStart(setTimeReport,2000)
end

function setTimeReport()
    sys.timerStart(timeReport,(os.time()%60==0) and 50 or (60-os.time()%60)*1000)
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
    --查询序列号
    if cmd == "AT+WISN?" then
        result = (intermediate~="*CME ERROR: Missing SN")
        if result then
            sn = intermediate
            sys.publish('SN_READY_IND')
        end
        if setSnCbFnc then setSnCbFnc(result) end        
    --查询IMEI
    elseif cmd == "AT+CGSN" then
        imei = intermediate
        if setImeiCbFnc then setImeiCbFnc(true) end
        sys.publish('IMEI_READY_IND')
    --查询模块温度
    elseif cmd =="AT+RFTEMPERATURE?" then
        temp = string.match(intermediate, ':(.+)')
        if getTemperatureCbFnc and type(getTemperatureCbFnc)=="function" then
            if success then
                getTemperatureCbFnc(temp)
            else
                getTemperatureCbFnc("")
            end
        end
    --查询模块型号
    elseif cmd == 'AT+CGMM' then
        modeltype = string.match(intermediate, '"(.+)"')
        if success then
            sys.publish('MODEL_NUMBER_READY_IND')
        end
    elseif cmd == 'AT+VER' then
        ver = intermediate
    elseif prefix == '+CCLK' then
        if success then
            sys.publish('TIME_UPDATE_IND')
            setTimeReport()
        end
        if setClkCbFnc then setClkCbFnc(getClock(),success) end
    elseif cmd:match("AT%+WISN=") then
        if success then
            req("AT+WISN?")
        else
            if setSnCbFnc then setSnCbFnc(false) end
        end
	elseif cmd:match("AT%+CALIBINFO%?") then
		if intermediate then
			local LTE_afc = intermediate:match("LTE_afc:(%d)")
			local LTE_TDD_agc = intermediate:match("LTE_TDD_agc:(%d)")
			local LTE_TDD_apc = intermediate:match("LTE_TDD_apc:(%d)")
			local LTE_FDD_agc = intermediate:match("LTE_FDD_agc:(%d)")
			local LTE_FDD_apc = intermediate:match("LTE_FDD_apc:(%d)")
			local ANT_LTE = intermediate:match("ANT_LTE:(%d)")
			
			calib = (LTE_afc == "1" and LTE_TDD_agc == "1" and LTE_TDD_apc == "1" and LTE_FDD_agc == "1" and LTE_FDD_apc == "1")
			ant = (ANT_LTE == "1")
		end
    elseif cmd:match("AT%*CALINFO%=R") then
		if intermediate then
            local LteTest=intermediate:match("LteTest%,PASS")
            local LteCal=intermediate:match("LteCal%,PASS")
            if LteCal then
            calib=(LteCal=="LteCal,PASS")
            end
            if LteTest then
            ant=(LteTest=="LteTest,PASS")
            end
        end
    elseif cmd:match("AT%+WIMEI=") then
        if success then
            req("AT+CGSN")
        else
            if setImeiCbFnc then setImeiCbFnc(false) end
        end
    elseif cmd:match("AT%+MUID?") then
        if intermediate then muid = intermediate:match("+MUID:%s*(.+)") end
    end
end

--- 获取core固件名
-- @return string version，core固件名
-- @usage
-- local version = misc.getVersion()
-- 如果core为Luat_V0026_RDA8910_TTS_FLOAT，则version为string类型的"Luat_V0026_RDA8910_TTS_FLOAT"
function getVersion()
    return rtos.get_version()
end

--- 设置系统时间
-- @table t,系统时间，格式参考：{year=2017,month=2,day=14,hour=14,min=2,sec=58}
-- @function[opt=nil] cbFnc，设置结果回调函数，回调函数的调用形式为：
--                           cbFnc(time，result)
--                           result为true表示成功，false或者nil为失败
--                           time表示设置之后的系统时间，table类型，例如{year=2017,month=2,day=14,hour=14,min=19,sec=23}
-- @return nil
-- @usage misc.setClock({year=2017,month=2,day=14,hour=14,min=2,sec=58})
function setClock(t,cbFnc)
    if type(t) ~= "table" or (t.year-2000>38) then
        if cbFnc then cbFnc(getClock(),false) end
        return
    end
    setClkCbFnc = cbFnc
    req(string.format("AT+CCLK=\"%02d/%02d/%02d,%02d:%02d:%02d+32\"", string.sub(t.year, 3, 4), t.month, t.day, t.hour, t.min, t.sec), nil, rsp)
end
--- 获取系统时间
-- @return table time,{year=2017,month=2,day=14,hour=14,min=19,sec=23}
-- @usage time = getClock()
function getClock()
    return os.date("*t")
end
--- 获取星期
-- @return number week，1-7分别对应周一到周日
-- @usage week = misc.getWeek()
function getWeek()
    local clk = os.date("*t")
    return ((clk.wday == 1) and 7 or (clk.wday - 1))
end
--- 获取校准标志
-- @return bool calib, true表示已校准，false或者nil表示未校准
-- @usage calib = misc.getCalib()
function getCalib()
    return calib
end

--- 获取耦合测试标志
-- @return bool ant, true表示已耦合测试，false或者nil表示未耦合测试
-- @usage ant = misc.getAnt()
function getAnt()
	return ant
end
--- 设置SN
-- @string s,新sn的字符串
-- @function[opt=nil] cbFnc,设置结果回调函数，回调函数的调用形式为：
-- cnFnc(result)，result为true表示成功，false或者nil为失败
-- @return nil
-- @usage
-- misc.setSn("1234567890")
-- misc.setSn("1234567890",cbFnc)
function setSn(s, cbFnc)
    if s ~= sn then
        setSnCbFnc = cbFnc
        req("AT+WISN=\"" .. s .. "\"") 
    else
        if cbFnc then cbFnc(true) end
    end
end
--- 获取模块序列号
-- @return string sn,序列号，如果未获取到返回""
-- 注意：开机lua脚本运行之后，会发送at命令去查询sn，所以需要一定时间才能获取到sn。开机后立即调用此接口，基本上返回""
-- @usage sn = misc.getSn()
function getSn()
    return sn or ""
end
--- 设置IMEI
-- @string s,新IMEI字符串
-- @function[opt=nil] cbFnc,设置结果回调函数，回调函数的调用形式为：
-- cnFnc(result)，result为true表示成功，false或者nil为失败
-- @return nil
-- @usage misc.setImei(”359759002514931”)
function setImei(s, cbFnc)
    if s ~= imei then
        setImeiCbFnc = cbFnc
        req("AT+WIMEI=\"" .. s .. "\"")
    else
        if cbFnc then cbFnc(true) end
    end
end
--- 获取模块IMEI
-- @return string,IMEI号，如果未获取到返回""
-- 注意：开机lua脚本运行之后，会发送at命令去查询imei，所以需要一定时间才能获取到imei。开机后立即调用此接口，基本上返回""
-- @usage imei = misc.getImei()
function getImei()
    return imei or ""
end
--- 获取模块型号
-- @return string,模块型号，如果未获取到返回""
-- 例如：模块型号为724UG,则返回值为Air724UG;模块型号为722UG,则返回值为Air722UG;模块型号为820UG,则返回值为Air820UG
-- 注意：开机lua脚本运行之后，会发送at命令去查询模块型号，所以需要一定时间才能获取到模块型号。开机后立即调用此接口，基本上返回""
-- @usage modeltype = getModelType()
function getModelType()
    return modeltype or ""
end

-- 获取模块温度
-- @return string,模块温度，如果要对该值进行运算，可以使用带float的固件将该值转为number
-- 例如：模块温度为29.77摄氏度,则返回值为29.77
function getTemperature(cb)
    getTemperatureCbFnc = cb
    ril.request("AT+RFTEMPERATURE?")
end

--- 获取VBAT的电池电压
-- @return number,电池电压,单位mv
-- @usage vb = getVbatt()
function getVbatt()
    if type(pmd.libScriptInit)=="function" then pmd.libScriptInit() end
    local v1, v2, v3, v4, v5 = pmd.param_get()
    return v2
end

--- 获取VBUS连接状态
-- @return boolean，true表示VBUS连接，false表示未连接
-- @usage vbus = getVbus()
function getVbus()
    local v1, v2, v3, v4, v5 = pmd.param_get()
    log.info("misc.getVbus",v1, v2, v3, v4, v5)
    return v4
end

--- 获取模块MUID
-- @return string,MUID号，如果未获取到返回""
-- 注意：开机lua脚本运行之后，会发送at命令去查询muid，所以需要一定时间才能获取到muid。开机后立即调用此接口，基本上返回""
-- @usage muid = misc.getMuid()
function getMuid()
    return muid or ""
end

--- 打开并且配置PWM(支持2路PWM，仅支持输出)
-- @number id，PWM输出通道，仅支持0和1
-- 0使用MODULE_STATUS/GPIO_5引脚
-- 1使用GPIO_13引脚，注意：上电的时候不要把 GPIO_13 拉高到V_GLOBAL_1V8，否则模块会进入校准模式，不正常开机
-- @number para1，
-- 当id为0时，para1表示分频系数，最大值为2047；分频系数和频率的换算关系为：频率=25000000/para1 （Hz）；例如para1为500时，频率为50000Hz
--                                          分频系数和周期的换算关系为：周期=para1/25000000　（ｓ）；例如para1为500时，周期为20ｕｓ
-- 当id为1时，para1表示时钟周期，取值范围为0-7，仅支持整数
--                                         0-7分别对应125、250、500、1000、1500、2000、2500、3000毫秒
-- @number para2，
-- 当id为0时，para2表示占空比计算系数，最大值为1023；占空比计算系数和占空比的计算关系为：占空比=para2/para1
-- 当id为1时，para2表示一个时钟周期内的高电平时间，取值范围为1-15，仅支持整数
--                                                           1-15分别对应15.6、31.2、46.8、62、78、94、110、125、140、156、172、188、200、218、234毫秒
-- @return nil
-- @usage
-- 通道0，频率为50000Hz，占空比为0.2：
-- 频率为50000Hz，表示时钟周期为1/50000=0.00002秒=0.02毫秒=20微秒  
-- 占空比表示在一个时钟周期内，高电平的时长/时钟周期的时长，本例子中的0.2就表示，高电平时长为4微秒，低电平时长为16微秒
-- misc.openPwm(0,500,100)
--
-- 通道1，时钟周期为500ms，高电平时间为125毫秒：
-- misc.openPwm(1,2,8)
function openPwm(id, para1, para2)
    pwm.open(id)
    pwm.set(id,para1,para2)
end

--- 关闭PWM
-- @number id，PWM输出通道，仅支持0和1
-- 0使用MODULE_STATUS/GPIO_5引脚
-- 1使用GPIO_13引脚，注意：上电的时候不要把 GPIO_13 拉高到V_GLOBAL_1V8，否则模块会进入校准模式，不正常开机
-- @return nil
function closePwm(id)
    assert(id == 0 or id == 1, "closepwm id error: " .. id)
    pwm.close(id)
end

--注册以下AT命令的应答处理函数
ril.regRsp("+WISN", rsp)
ril.regRsp("+CGSN", rsp)
ril.regRsp("+RFTEMPERATURE",rsp)
ril.regRsp("+CGMM", rsp)
ril.regRsp("+MUID", rsp)
ril.regRsp("+WIMEI", rsp)
ril.regRsp("+AMFAC", rsp)
--ril.regRsp('+VER', rsp, 4, '^[%w_]+$')
ril.regRsp("+CALIBINFO",rsp)
ril.regRsp("*CALINFO",rsp)
--req('AT+VER')
--查询序列号
req("AT+WISN?")
--查询IMEI
req("AT+CGSN")
req("AT+MUID?")
req("AT*EXINFO?")
--查询模块温度
-- req("AT+RFTEMPERATURE?")
--查询模块型号
if string.match(rtos.get_version(),"ASR1603") then 
    req("AT*CALINFO=R,LteCal")
    req("AT*CALINFO=R,LteTest")
end
req("AT+CGMM")
setTimeReport()
