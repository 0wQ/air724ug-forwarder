--- 模块功能：开机键功能配置
-- @module powerKey
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.06.13

require"sys"
module(..., package.seeall)

--[[
sta：按键状态，IDLE表示空闲状态，PRESSED表示已按下状态，LONGPRESSED表示已经长按下状态
longprd：长按键判断时长，默认3秒；按下大于等于3秒再弹起判定为长按键；按下后，在3秒内弹起，判定为短按键
longcb：长按键处理函数
shortcb：短按键处理函数
]]
local sta,longprd,longcb,shortcb = "IDLE",3000

local function longtimercb()
    log.info("keypad.longtimercb")
    sta = "LONGPRESSED"	
end

local function keyMsg(msg)
    log.info("keyMsg",msg.key_matrix_row,msg.key_matrix_col,msg.pressed)
    if msg.pressed then
        sta = "PRESSED"
        sys.timerStart(longtimercb,longprd)
    else
        sys.timerStop(longtimercb)
        if sta=="PRESSED" then
            if shortcb then shortcb() end
        elseif sta=="LONGPRESSED" then
            (longcb or rtos.poweroff)()
		end
		sta = "IDLE"
	end
end

--- 配置开机键长按弹起和短按弹起的功能.
-- 如何定义长按键和短按键，例如长按键判断时长为3秒：
-- 按下大于等于3秒再弹起判定为长按键；
-- 按下后，在3秒内弹起，判定为短按键
-- @number[opt=3000] longPrd，长按键判断时长，单位毫秒
-- @function[opt=nil] longCb，长按弹起时的回调函数，如果为nil，使用默认的处理函数，会自动关机
-- @function[opt=nil] shortCb，短按弹起时的回调函数
-- @return nil
-- @usage
-- powerKey.setup(nil,longCb,shortCb)
-- powerKey.setup(5000,longCb)
-- powerKey.setup()
function setup(longPrd,longCb,shortCb)
    longprd,longcb,shortcb = longPrd or 3000,longCb,shortCb
end

rtos.on(rtos.MSG_KEYPAD,keyMsg)
rtos.init_module(rtos.MOD_KEYPAD,0,0,0)
