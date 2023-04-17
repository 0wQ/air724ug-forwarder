module(...)

-------------------------------------------------- 通知相关配置 --------------------------------------------------

-- 通知类型, 支持配置多个
-- NOTIFY_TYPE = {"telegram", "pushdeer", "bark", "dingtalk", "feishu", "wecom", "pushover", "inotify", "next-smtp-proxy", "gotify"}
NOTIFY_TYPE = {"feishu"}

-- telegram 通知配置, https://github.com/0wQ/telegram-notify
-- TELEGRAM_PROXY_API = ""
-- TELEGRAM_TOKEN = ""
-- TELEGRAM_CHAT_ID = ""

-- pushdeer 通知配置, https://www.pushdeer.com/
-- PUSHDEER_API = "https://api2.pushdeer.com/message/push"
-- PUSHDEER_KEY = ""

-- bark 通知配置, https://github.com/Finb/Bark
-- BARK_API = "https://api.day.app"
-- BARK_KEY = ""

-- dingtalk 通知配置, https://open.dingtalk.com/document/robots/custom-robot-access
-- DINGTALK_WEBHOOK = "https://oapi.dingtalk.com/robot/send?access_token=xxx"

-- feishu 通知配置, https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN
FEISHU_WEBHOOK = "https://open.feishu.cn/open-apis/bot/v2/hook/xxx"

-- wecom 通知配置, https://developer.work.weixin.qq.com/document/path/91770
-- WECOM_WEBHOOK = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"

-- pushover 通知配置, https://pushover.net/api
-- PUSHOVER_API_TOKEN = ""
-- PUSHOVER_USER_KEY = ""

-- inotify 通知配置, https://github.com/xpnas/Inotify 或者使用合宙提供的 https://push.luatos.org
-- INOTIFY_API = "https://push.luatos.org/xxx.send"

-- next-smtp-proxy 通知配置, https://github.com/0wQ/next-smtp-proxy
-- NEXT_SMTP_PROXY_API = ""
-- NEXT_SMTP_PROXY_USER = ""
-- NEXT_SMTP_PROXY_PASSWORD = ""
-- NEXT_SMTP_PROXY_HOST = "smtp-mail.outlook.com"
-- NEXT_SMTP_PROXY_PORT = 587
-- NEXT_SMTP_PROXY_FORM_NAME = "Air780E"
-- NEXT_SMTP_PROXY_TO_EMAIL = ""
-- NEXT_SMTP_PROXY_SUBJECT = "来自 Air780E 的通知"

-- gotify 通知配置, https://gotify.net/
-- GOTIFY_API = ""
-- GOTIFY_TITLE = "Air780E"
-- GOTIFY_PRIORITY = 8
-- GOTIFY_TOKEN = ""

-- 定时查询流量间隔, 单位毫秒, 设置为 0 关闭 (建议检查 util_mobile.lua 文件中运营商号码和查询流量代码是否正确, 以免发错短信导致扣费, 收到查询结果短信发送通知会消耗流量)
QUERY_TRAFFIC_INTERVAL = 0

-- 开机通知 (会消耗流量)
BOOT_NOTIFY = true

-- 通知内容追加更多信息 (通知内容增加会导致流量消耗增加)
NOTIFY_APPEND_MORE_INFO = true

-- 通知最大重发次数
NOTIFY_RETRY_MAX = 20

-------------------------------------------------- 录音上传配置 --------------------------------------------------

-- 腾讯云 COS / 阿里云 OSS / AWS S3 等对象存储上传地址, 以下为腾讯云 COS 示例, 请自行修改
-- 存储桶需设置为: <私有读写>
-- 存储桶 Policy 权限: <用户类型: 所有用户> <授权资源: xxx-123456/{录音文件目录}/*> <授权操作: PutObject,GetObject>
-- 提示: 本项目未使用签名认证上传, 请勿泄露自己的地址及目录名
UPLOAD_URL = "http://xxx-123456.cos.ap-nanjing.myqcloud.com/{录音文件目录}"

-------------------------------------------------- 短信来电配置 --------------------------------------------------

-- 允许发短信控制设备的号码, 如果为空, 则允许所有号码
-- 短信内容示例: `SMS,10086,查询剩余流量`, `CALL,10086`
SMS_ALLOW_NUMBER = ""

-- 扬声器 TTS 播放短信内容, 0：关闭(默认)，1：仅验证码，2：全部
SMS_TTS = 0

-- 电话接通后 TTS 语音内容, 在播放完后开始录音, 如果注释掉或者为空则播放 audio_call.amr 文件
-- TTS_TEXT = "您好，请在语音结束后留言，稍后将发送到机主，结束请挂机。"

-- 扬声器播放通话声音
CALL_PLAY_TO_SPEAKER_ENABLE = false

-- 开启通话麦克风
CALL_MIC_ENABLE = false

-- 来电动作, 0：无操作，1：接听(默认)，2：挂断
CALL_IN_ACTION = 1

-------------------------------------------------- 其他配置 --------------------------------------------------

-- 扬声器音量, 0-7
AUDIO_VOLUME = 1

-- 开启 RNDIS 网卡
RNDIS_ENABLE = false
