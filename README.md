# Air724UG 短信转发 & 来电通知 & 语音信箱

## 使用方法

> 底层 CORE 版本：[LuatOS-Air_V4018_RDA8910_TTS_NOLVGL_FLOAT.pac](https://doc.openluat.com/article/1334)

### 1. 修改 `script/config.lua` 配置文件

```lua
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

    -- 其他配置...
}
```

> 推荐使用腾讯云 COS
>
> 配合工作流可以实现自动音频转码、语音识别功能
>
> 可在腾讯云助手微信小程序或 COSBrowser APP，查看录音文件、语音识别结果
>
> ![image](https://user-images.githubusercontent.com/20741439/204080463-061349fd-3b4e-4f36-be8c-b0ad0013a1df.png)

### 3. 烧录脚本

根据 [air724ug.cn](http://air724ug.cn) 官方指引下载 LuaTools 并写入 `script` 目录下文件
