module(..., package.seeall)

-- 用于生成 http 请求的 id
local http_count = 0

--- 对 LuatOS-Air http.request 的封装
-- @param timeout (number) 超时时间
-- @param method (string) 请求方法
-- @param url (string) 请求地址
-- @param headers (table) 请求头
-- @param body (string) 请求体
-- @return (number, table, string) 状态码, 响应头, 响应体
function fetch(timeout, method, url, headers, body)
    timeout = timeout or 1000 * 30

    http_count = http_count + 1
    local id = "http_c" .. http_count

    local function callback(res_result, res_prompt, res_headers, res_body)
        sys.publish(id, { res_result, res_prompt, res_headers, res_body })
    end

    log.info("util_http.fetch", "开始请求", "id:", id)
    http.request(method, url, nil, headers, body, timeout, callback)
    local result, data = sys.waitUntil(id, timeout + 10000)

    if not result or not data then
        log.warn("util_http.fetch", "请求超时", "id:", id)
        return -97
    end

    if data[1] then
        return tonumber(data[2]), data[3] or {}, data[4] or ""
    else
        log.warn("util_http.fetch", "请求失败", "id:", id, "error:", data[2])
        return -98, data[2] or {}, data[3] or ""
    end
end
