config = {
    -- 通知类型 pushdeer, bark, telegram
    NOTIFY_TYPE = "pushdeer",

    -- PushDeer 通知配置, https://www.pushdeer.com
    PUSHDEER_KEY = "",

    -- Bark 通知配置, https://github.com/Finb/Bark
    BARK_KEY = "",

    -- Telegram 通知配置, https://github.com/0wQ/telegram-notify
    TELEGRAM_PROXY_API = "",
    TELEGRAM_TOKEN = "",
    TELEGRAM_CHAT_ID = "",

    -- 腾讯云 COS / 阿里云 OSS / AWS S3 等对象存储上传地址
    -- 存储桶需设置为 <私有读写>, 并授权 <所有用户> <指定目录> 的 <PutObject> 操作
    UPLOAD_URL = "http://xxx-123456.cos.ap-nanjing.myqcloud.com/this-is-the-path",

    -- 定时查询流量间隔, 单位为毫秒, 设置为 0 关闭
    QUERY_TRAFFIC_INTERVAL = 1000 * 60 * 60 * 6,

    -- 定时上传设备数据到对象存储间隔, 单位为毫秒, 设置为 0 关闭
    REPORT_DATA_INTERVAL = 1000 * 60 * 30,

    -- 开机通知
    BOOT_NOTIFY = true,

    -- 开启 RNDIS 网卡
    RNDIS_ENABLE = false,

    -- TTS 语音内容, 在播放完后开始录音
    TTS_TEXT = "您好，机主当前无法接听电话，请在语音结束后留言，稍后将发送到机主，结束请挂机。",

    -- 允许发短信控制设备的号码, 如果为空, 则允许所有号码
    SMS_ALLOW_NUMBER = "",
}
