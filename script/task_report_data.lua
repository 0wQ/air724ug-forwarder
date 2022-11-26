require "http"
require "net"
require "sim"
require "misc"
require "log"
require "config"
require "util_get_oper"
module(..., package.seeall)

local enable = config.REPORT_DATA_INTERVAL and config.REPORT_DATA_INTERVAL > 1000 * 10

local old_data = {}

local function buildData()
    local rsrp = net.getRsrp()
    return {
        time = os.time(),
        mcc = net.getMcc(),
        mnc = net.getMnc(),
        lac = tonumber(net.getLac(), 16),
        ci = tonumber(net.getCi(), 16),
        rsrp_dbm = rsrp - 140,
        rsrp_asu = rsrp,
        rssi = net.getRssi(),
        temp = CPU_TEMP,
        number = sim.getNumber(),
        band = net.getBand(),
        oper = util_get_oper.get(),
        imei = misc.getImei(),
        module_type = misc.getModelType(),
        cell_info_ext = net.getCellInfoExt(),
        fs_free_size = rtos.get_fs_free_size(),
        ram_free_size = collectgarbage("count")
    }
end

-- HTTP 回调
local function httpCallback(result, prompt, head, body)
    if result and prompt == "200" then
        log.info("HTTP回调", "上报数据成功", result, prompt)
    else
        log.error("HTTP回调", "上报数据失败", result, prompt, head, body)
    end
end

-- Data diff
local function getDiff(new_data)
    local diff = {}
    for k, v in pairs(new_data) do
        if v ~= old_data[k] then
            diff[k] = v
        end
    end
    return diff
end

local function _run()
    log.info("上报数据")
    local url = "http://localhost/api/save"
    local header = {
        ["content-type"] = "application/json"
    }

    local new_data = buildData()
    local diff = getDiff(new_data)
    old_data = new_data

    -- diff 为空则不上报
    if next(diff) == nil then
        log.info("数据无变化, 不上报")
        return
    end

    local json_data =
        json.encode(
        {
            key = "imei_" .. misc.getImei(),
            value = diff
        }
    )
    log.info("上报数据内容", json_data)
    sys.taskInit(http.request, "POST", url, nil, header, json_data, 30000, httpCallback, nil)
end

function run()
    log.info("上报数据")
    if config.UPLOAD_URL == nil then
        log.error("上报数据", "未配置上传地址")
        return
    end
    if not enable then
        return
    end

    local url = config.UPLOAD_URL .. "/data/" .. sim.getNumber() .. ".json"
    local header = {
        ["content-type"] = "application/json",
        ["Connection"] = "keep-alive"
    }

    local data = buildData()
    local json_data = json.encode(data)

    log.info("上报数据内容", json_data)
    sys.taskInit(http.request, "PUT", url, nil, header, json_data, 30000, httpCallback, nil)
end

if enable then
    sys.timerLoopStart(run, config.REPORT_DATA_INTERVAL)
end
