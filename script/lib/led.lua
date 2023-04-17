--- 模块功能：LED闪灯模块
-- @module led
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.02.04
module(..., package.seeall)

--- 闪烁指示灯
-- @function ledPin,ledPin(1)用pins.setup注册返回的方法
-- @number light, light-亮灯时间ms
-- @number dark, dark-灭灯时间ms
-- @return nil
-- @usage led.blinkPwm(lenPin,500,500)
-- @usage 调用函数需要使用任务支持
function blinkPwm(ledPin, light, dark)
    ledPin(1)
    sys.wait(light)
    ledPin(0)
    sys.wait(dark)
end
--- 等级指示灯
-- @function ledPin, ledPin(1)用pins.setup注册返回的方法
-- @number bl,亮灯时间ms
-- @number bd,灭灯时间ms
-- @number cnt,重复次数 (等级的级别,亮灭1次算数字1)
-- @number gap,间隔时间 (每次循环周期的间隔)
-- @return nil
-- @usage led.leveled(ledPin,200,200,4,1000)
-- @usage 调用函数需要使用任务支持
function levelLed(ledPin, bl, bd, cnt, gap)    
    if not (ledPin and bl and bd and cnt and gap) then return end
    for i = 1, cnt do blinkPwm(ledPin, bl, bd) end
    sys.wait(gap)
end

--- 呼吸灯
-- @function ledPin, 呼吸灯的ledPin(1)用pins.setup注册返回的方法
-- @return nil
-- @usage led.breateLed(ledPin)
-- @usage 调用函数需要使用任务支持
function breateLed(ledPin)
    -- 呼吸灯的状态、PWM周期
    local bLighting, bDarking, LED_PWM = false, true, 18
    if bLighting then
        for i = 1, LED_PWM - 1 do
            ledPin(0)
            sys.wait(i)
            ledPin(1)
            sys.wait(LED_PWM - i)
        end
        bLighting = false
        bDarking = true
        ledPin(0)
        sys.wait(700)
    end
    if bDarking then
        for i = 1, LED_PWM - 1 do
            ledPin(0)
            sys.wait(LED_PWM - i)
            ledPin(1)
            sys.wait(i)
        end
        bLighting = true
        bDarking = false
        ledPin(1)
        sys.wait(700)
    end
end

