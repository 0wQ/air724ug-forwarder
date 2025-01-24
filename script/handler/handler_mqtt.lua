require "mqtt"
require "misc"
require "util_mobile"
require "handler_call"
require "util_notify"

module(..., package.seeall)

-- MQTT 客户端实例
local mqttc

-- 初始化 MQTT 客户端
local function init()
    -- MQTT 客户端配置
    mqttc = mqtt.client(
        config.MQTT_CLIENT_ID .. misc.getImei(),  -- 客户端ID
        config.MQTT_KEEPALIVE or 300  -- keepAlive时间（秒）
    )
end

-- 处理收到的消息
local function handleMessage(packet)
    log.info("MQTT", "收到消息", packet.topic, packet.payload)
    local messageJson = json.decode(packet.payload)
    local topic = config.MQTT_CLIENT_ID .. misc.getImei()

    if packet.topic == topic then
        -- 处理命令消息
        if messageJson.command == "call" then
            log.info("MQTT", "收到拨打电话命令")
            if messageJson.sendSms and messageJson.sendSms == "true" then
                -- 发送短信
                util_mobile.sendSms(messageJson.phone, messageJson.message)
            end
            handler_call.dialAndPlayTts(messageJson.phone, messageJson.message)
            
        elseif messageJson.command == "queryTraffic" then
            log.info("MQTT", "收到查询流量命令")
            util_mobile.queryTraffic()
        elseif messageJson.command == "queryBalance" then
            log.info("MQTT", "收到查询话费余额命令")
            util_mobile.queryBalance()
        elseif messageJson.command == "sendSms" then
            log.info("MQTT", "收到发送短信命令")
            util_mobile.sendSms(messageJson.phone, messageJson.message)

        elseif messageJson.command == "status" then
            log.info("MQTT", "收到状态通知")
            mqttc:publish(topic.."/status", "#BOOT_" .. rtos.poweron_reason()..util_notify.BuildDeviceInfo(), 1) 
        end
    elseif packet.topic == "device/config" then
        -- 处理配置消息
    end
end

-- 连接 MQTT 服务器
local function connect()
    -- MQTT 连接
    local connected = mqttc:connect(
        config.MQTT_HOST,
        config.MQTT_PORT,
        "tcp"  -- 传输协议
    )

    if connected then
        log.info("MQTT", "连接成功")
        -- 订阅主题
        local topic = config.MQTT_CLIENT_ID .. misc.getImei()
        log.info("MQTT", "订阅主题", topic)
        
        mqttc:subscribe({
            [topic] = 0,  -- QoS 0
        })

        -- 发送上线消息 
        if nvm.get("BOOT_NOTIFY") then
            log.info("MQTT", "上线通知")
            mqttc:publish(topic.."/status", "#BOOT_" .. rtos.poweron_reason()..util_notify.BuildDeviceInfo(), 1) 
        end

        -- 循环接收消息
        while true do
            local result, packet = mqttc:receive(2000)  -- 2秒超时
            if result then
                handleMessage(packet)
            end
        end
    end
end

-- 启动 MQTT 客户端
sys.taskInit(function()
    if config.MQTT_ENABLE then
        log.info("MQTT", "MQTT 初始化")
        -- 等待网络就绪
        sys.waitUntil("IP_READY_IND", 1000 * 60 * 2)
        
        -- 初始化客户端
        init()
        
        -- 连接服务器
        connect()

    end
end)