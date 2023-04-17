--- 模块功能：完善luat的c库接口
-- @module clib
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.9.20
local uartReceiveCallbacks = {}
local uartSentCallbacks = {}

--- 注册串口事件的处理函数
-- @number id 串口ID: 1表示串口1，2表示串口2，uart.ATC表示虚拟AT口
-- @string event 串口事件:
-- "recieve"表示串口收到数据，注意：使用uart.setup配置串口时，第6个参数设置为nil或者0，收到数据时，才会产生"receive"事件
-- "sent"表示串口数据发送完成，注意：使用uart.setup配置串口时，第7个参数设置为1，调用uart.write接口发送数据之后，才会产生"sent"事件
-- @function[opt=nil] callback 串口事件的处理函数
-- @return nil
-- @usage
-- uart.on(1,"receive",rcvFnc)
-- uart.on(1,"sent",sentFnc)
uart.on = function(id, event, callback)
    if event == "receive" then
        uartReceiveCallbacks[id] = callback
    elseif event == "sent" then
        uartSentCallbacks[id] = callback
    end
end

rtos.on(rtos.MSG_UART_RXDATA, function(id, length)
    if uartReceiveCallbacks[id] then
        uartReceiveCallbacks[id](id, length)
    end
end)

rtos.on(rtos.MSG_UART_TX_DONE, function(id)
    if uartSentCallbacks[id] then
        uartSentCallbacks[id](id)
    end
end)
