--- 模块功能：系统日志记录,分级别日志工具
-- @module log
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.09.26

module(..., package.seeall)
-- 定义日志级别常量，可在main入口全局指定
-- 例如： LOG_LEVEL=log.LOGLEVEL_WARN
LOG_SILENT = 0x00;
LOGLEVEL_TRACE = 0x01;
LOGLEVEL_DEBUG = 0x02;
LOGLEVEL_INFO = 0x03;
LOGLEVEL_WARN = 0x04;
LOGLEVEL_ERROR = 0x05;
LOGLEVEL_FATAL = 0x06;

-- 定义日志级别标签，分别对应日志级别的1-6
local LEVEL_TAG = {'T', 'D', 'I', 'W', 'E', 'F'}
local PREFIX_FMT = "[%s]-[%s]"

--- 内部函数，支持不同级别的log打印及判断
-- @param level ，日志级别，可选LOGLEVEL_TRACE，LOGLEVEL_DEBUG等
-- @param tag   ，模块或功能名称(标签），作为日志前缀
-- @param ...   ，日志内容，可变参数
-- @return nil
-- @usage _log(LOGLEVEL_TRACE,tag, 'log content')
-- @usage _log(LOGLEVEL_DEBUG,tag, 'log content')
local function _log(level, tag, ...)
    -- INFO 作为默认日志级别
    local OPENLEVEL = LOG_LEVEL and LOG_LEVEL or LOGLEVEL_INFO
    -- 如果日志级别为静默，或设定级别更高，则不输出日志
    if OPENLEVEL == LOG_SILENT or OPENLEVEL > level then return end
    -- 日志打印输出
    local prefix = string.format(PREFIX_FMT, LEVEL_TAG[level], type(tag)=="string" and tag or "")
    print(prefix, ...)

-- TODO，支持hookup，例如对某级别日志做额外处理
-- TODO，支持标签过滤
end

--- 输出trace级别的日志
-- @param tag   ，模块或功能名称，作为日志前缀
-- @param ...   ，日志内容，可变参数
-- @return nil
-- @usage trace('moduleA', 'log content')
function trace(tag, ...)
    _log(LOGLEVEL_TRACE, tag, ...)
end

--- 输出debug级别的日志
-- @param tag   ，模块或功能名称，作为日志前缀
-- @param ...   ，日志内容，可变参数
-- @return nil
-- @usage debug('moduleA', 'log content')
function debug(tag, ...)
    _log(LOGLEVEL_DEBUG, tag, ...)
end

--- 输出info级别的日志
-- @param tag   ，模块或功能名称，作为日志前缀
-- @param ...   ，日志内容，可变参数
-- @return nil
-- @usage info('moduleA', 'log content')
function info(tag, ...)
    _log(LOGLEVEL_INFO, tag, ...)
end

--- 输出warn级别的日志
-- @param tag   ，模块或功能名称，作为日志前缀
-- @param ...   ，日志内容，可变参数
-- @return nil
-- @usage warn('moduleA', 'log content')
function warn(tag, ...)
    _log(LOGLEVEL_WARN, tag, ...)
end

--- 输出error级别的日志
-- @param tag   ，模块或功能名称，作为日志前缀
-- @param ...   ，日志内容，可变参数
-- @return nil
-- @usage error('moduleA', 'log content')
function error(tag, ...)
    _log(LOGLEVEL_ERROR, tag, ...)
end

--- 输出fatal级别的日志
-- @param tag   ，模块或功能名称，作为日志前缀
-- @param ...   ，日志内容，可变参数
-- @return nil
-- @usage fatal('moduleA', 'log content')
function fatal(tag, ...)
    _log(LOGLEVEL_FATAL, tag, ...)
end


--- 开启或者关闭print的打印输出功能
-- @bool v：false或nil为关闭，其余为开启
-- @param uartid：输出Luatrace的端口：nil表示host口，1表示uart1,2表示uart2
-- @number baudrate：number类型，uartid不为nil时，此参数才有意义，表示波特率，默认115200 \
-- 支持1200,2400,4800,9600,10400,14400,19200,28800,38400,57600,76800,115200,230400,460800,576000,921600,1152000,4000000
-- @return nil
-- @usage sys.openTrace(1,nil,921600)
function openTrace(v, uartid, baudrate)
    if uartid then
        if v then
            uart.setup(uartid, baudrate or 115200, 8, uart.PAR_NONE, uart.STOP_1)
        else
            uart.close(uartid)
        end
    end
    rtos.set_trace(v and 1 or 0, uartid)
end
