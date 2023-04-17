# Air724UG 短信转发 & 来电通知 & 语音信箱

## 使用方法

> 底层 CORE 版本：[LuatOS-Air_V4018_RDA8910_TTS_NOLVGL_FLOAT.pac](https://doc.openluat.com/article/1334)

### 1. 按注释修改 `script/config.lua` 配置文件

> 推荐使用腾讯云 COS, 可在腾讯云助手微信小程序或 COSBrowser APP，查看录音文件、语音识别结果
>
> ![存储桶 Policy 权限配置](https://user-images.githubusercontent.com/20741439/232460879-1947e725-5791-4b9e-8cf5-f2d99fcfe77c.png)
>
> 配合工作流可以实现自动音频转码、语音识别功能 (⚠️付费功能)
>
> ![工作流配置](https://user-images.githubusercontent.com/20741439/204080463-061349fd-3b4e-4f36-be8c-b0ad0013a1df.png)

### 2. 烧录脚本

根据 [air724ug.cn](http://air724ug.cn) 官方指引下载 LuaTools 并写入 `script` 目录下文件
