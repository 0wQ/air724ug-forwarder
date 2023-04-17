--- 模块功能：GPIO 功能配置，包括输入输出IO和上升下降沿中断IO
-- @module pins
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.09.23 11:34
require "sys"
module(..., package.seeall)
local interruptCallbacks = {}
local dirs = {}
--- 配置GPIO模式
-- @number pin，GPIO ID
-- GPIO 0到GPIO 31表示为pio.P0_0到pio.P0_31
-- GPIO 32到GPIO XX表示为pio.P1_0到pio.P1_(XX-32)，例如GPIO33 表示为pio.P1_1
-- GPIO 64到GPIO XX表示为pio.P2_0到pio.P2_(XX-64)，例如GPIO65 表示为pio.P2_1
-- @param val，number、nil或者function类型
-- 配置为输出模式时，为number类型，表示默认电平，0是低电平，1是高电平
-- 配置为输入模式时，为nil
-- 配置为中断模式时，为function类型，表示中断处理函数
-- @param pull, number, pio.PULLUP：上拉模式 。pio.PULLDOWN：下拉模式。pio.NOPULL：高阻态
-- 如果没有设置此参数，默认的上下拉参考模块的硬件设计说明书
-- @return function
-- 配置为输出模式时，返回的函数，可以设置IO的电平
-- 配置为输入或者中断模式时，返回的函数，可以实时获取IO的电平
-- @usage setOutputFnc = pins.setup(pio.P1_1,0)，配置GPIO 33，输出模式，默认输出低电平；
--执行setOutputFnc(0)可输出低电平，执行setOutputFnc(1)可输出高电平
-- @usage getInputFnc = pins.setup(pio.P1_1,intFnc)，配置GPIO33，中断模式
-- 产生中断时自动调用intFnc(msg)函数：上升沿中断时：msg为cpu.INT_GPIO_POSEDGE；下降沿中断时：msg为cpu.INT_GPIO_NEGEDGE
-- 执行getInputFnc()即可获得当前电平；如果是低电平，getInputFnc()返回0；如果是高电平，getInputFnc()返回1
-- @usage getInputFnc = pins.setup(pio.P1_1),配置GPIO33，输入模式
--执行getInputFnc()即可获得当前电平；如果是低电平，getInputFnc()返回0；如果是高电平，getInputFnc()返回1
-- @usage
--有些GPIO需要打开对应的ldo电压域之后，才能正常配置工作，电压域和对应的GPIO关系如下
--pmd.ldoset(x,pmd.LDO_VSIM1) -- GPIO 29、30、31
--pmd.ldoset(x,pmd.LDO_VLCD) -- GPIO 0、1、2、3、4
--pmd.ldoset(x,pmd.LDO_VMMC) -- GPIO 24、25、26、27、28
--x=0时：关闭LDO
--x=1时：LDO输出1.716V
--x=2时：LDO输出1.828V
--x=3时：LDO输出1.939V
--x=4时：LDO输出2.051V
--x=5时：LDO输出2.162V
--x=6时：LDO输出2.271V
--x=7时：LDO输出2.375V
--x=8时：LDO输出2.493V
--x=9时：LDO输出2.607V
--x=10时：LDO输出2.719V
--x=11时：LDO输出2.831V
--x=12时：LDO输出2.942V
--x=13时：LDO输出3.054V
--x=14时：LDO输出3.165V
--x=15时：LDO输出3.177V
--除了上面列举出的GPIO外，其余的GPIO不需要打开特定的电压域，可以直接配置工作
function setup(pin, val, pull)
    -- 关闭该IO
    pio.pin.close(pin)
    -- 中断模式配置
    if type(val) == "function" then
        pio.pin.setdir(pio.INT, pin)
        if pull then pio.pin.setpull(pull or pio.PULLUP, pin) end
        --注册引脚中断的处理函数
        interruptCallbacks[pin] = val
        dirs[pin] = false
        return function()
            return pio.pin.getval(pin)
        end
    end
    -- 输出模式初始化默认配置
    if val ~= nil then
        dirs[pin] = true
        pio.pin.setdir(val == 1 and pio.OUTPUT1 or pio.OUTPUT, pin)
    else
        -- 输入模式初始化默认配置
        dirs[pin] = false
        pio.pin.setdir(pio.INPUT, pin)
        if pull then pio.pin.setpull(pull or pio.PULLUP, pin) end
    end
    -- 返回一个自动切换输入输出模式的函数
    return function(val)
        val = tonumber(val)
        if (not val and dirs[pin]) or (val and not dirs[pin]) then
            pio.pin.close(pin)
            pio.pin.setdir(val and (val == 1 and pio.OUTPUT1 or pio.OUTPUT) or pio.INPUT, pin)
            if not val and pull then pio.pin.setpull(pull or pio.PULLUP, pin) end
            dirs[pin] = val and true or false
            return val or pio.pin.getval(pin)
        end
        if val then
            pio.pin.setval(val, pin)
            return val
        else
            return pio.pin.getval(pin)
        end
    end
end

--- 关闭GPIO模式
-- @number pin，GPIO ID
--
-- GPIO 0到GPIO 31表示为pio.P0_0到pio.P0_31
--
-- GPIO 32到GPIO XX表示为pio.P1_0到pio.P1_(XX-32)，例如GPIO33 表示为pio.P1_1
-- @usage pins.close(pio.P1_1)，关闭GPIO33
function close(pin)
    pio.pin.close(pin)
end

rtos.on(rtos.MSG_INT, function(msg)
    if interruptCallbacks[msg.int_resnum] == nil then
        log.warn('pins.rtos.on', 'warning:rtos.MSG_INT callback nil', msg.int_resnum)
        return
    end
    interruptCallbacks[msg.int_resnum](msg.int_id)
end)
