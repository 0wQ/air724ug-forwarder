--- 模块功能：数据链路激活、SOCKET管理(创建、连接、数据收发、状态维护)
-- @module socket
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.9.25
require "socket4G"
module(..., package.seeall)

socket.isReady = link.isReady
local tSocketModule = nil
local function init()
    tSocketModule = tSocketModule or {
        [link.CELLULAR] = socket4G,
        [link.CH395] = socketCh395,
        [link.W5500] = socketW5500
    }
end
--- 创建基于TCP的socket对象
-- @bool[opt=nil] ssl，是否为ssl连接，true表示是，其余表示否
-- @table[opt=nil] cert，ssl连接需要的证书配置，只有ssl参数为true时，此参数才有意义，cert格式如下：
-- {
--     caCert = "ca.crt", --CA证书文件(Base64编码 X.509格式)，如果存在此参数，则表示客户端会对服务器的证书进行校验；不存在则不校验
--     clientCert = "client.crt", --客户端证书文件(Base64编码 X.509格式)，服务器对客户端的证书进行校验时会用到此参数
--     clientKey = "client.key", --客户端私钥文件(Base64编码 X.509格式)
--     clientPassword = "123456", --客户端证书文件密码[可选]
-- }
-- @table[opt=nil] tCoreExtPara，建立链接扩展参数，4G链接和ch395链接所需扩展参数不一样
-- @return client，创建成功返回socket客户端对象；创建失败返回nil
-- @usage
-- c = socket.tcp()
-- c = socket.tcp(true)
-- c = socket.tcp(true, {caCert="ca.crt"})
-- c = socket.tcp(true, {caCert="ca.crt", clientCert="client.crt", clientKey="client.key"})
-- c = socket.tcp(true, {caCert="ca.crt", clientCert="client.crt", clientKey="client.key", clientPassword="123456"})

function tcp(ssl, cert, tCoreExtPara)
    init()
    return tSocketModule[link.getNetwork()].tcp(ssl, cert, tCoreExtPara)
end
--- 创建基于UDP的socket对象
-- @return client，创建成功返回socket客户端对象；创建失败返回nil
-- @usage c = socket.udp()
function udp()
    init()
    return tSocketModule[link.getNetwork()].udp()
end
--- 设置TCP层自动重传的参数
-- @number[opt=4] retryCnt，重传次数；取值范围0到12
-- @number[opt=16] retryMaxTimeout，限制每次重传允许的最大超时时间(单位秒)，取值范围1到16
-- @return nil
-- @usage
-- setTcpResendPara(3,8)
-- setTcpResendPara(4,16)
function setTcpResendPara(retryCnt, retryMaxTimeout)
    init()
    return tSocketModule[link.getNetwork()].setTcpResendPara(retryCnt, retryMaxTimeout)    
end

--- 设置域名解析参数
-- 注意：0027以及之后的core版本才支持此功能
-- @number[opt=4] retryCnt，重传次数；取值范围1到8
-- @number[opt=4] retryTimeoutMulti，重传超时时间倍数，取值范围1到5
--                第n次重传超时时间的计算方式为：第n次的重传超时基数*retryTimeoutMulti，单位为秒
--                重传超时基数表为{1, 1, 2, 4, 4, 4, 4, 4}
--                第1次重传超时时间为：1*retryTimeoutMulti 秒
--                第2次重传超时时间为：1*retryTimeoutMulti 秒
--                第3次重传超时时间为：2*retryTimeoutMulti 秒
--                ...........................................
--                第8次重传超时时间为：8*retryTimeoutMulti 秒
-- @return nil
-- @usage
-- socket.setDnsParsePara(8,5)
function setDnsParsePara(retryCnt, retryTimeoutMulti)
    init()
    return tSocketModule[link.getNetwork()].setDnsParsePara(retryCnt, retryTimeoutMulti)
end

--- 打印所有socket的状态
-- @return 无
-- @usage socket.printStatus()
function printStatus()
    init()
    return tSocketModule[link.getNetwork()].printStatus()
end

--- 设置数据传输后，允许进入休眠状态的延时时长
-- 3024版本以及之后的版本才支持此功能
-- 此功能设置的参数，设置成功后，掉电会自动保存
-- @number tm，数据传输后，允许进入休眠状态的延时时长，单位为秒，取值范围1到20
--             注意：此时间越短，允许进入休眠状态越快，功耗越低；但是在某些网络环境中，此时间越短，可能会造成数据传输不稳定
--                   建议在可以接受的功耗范围内，此值设置的越大越好
--                   如果没有设置此参数，此延时时长是和基站的配置有关，一般来说是10秒左右
-- @return nil
-- @usage
-- socket.setLowPower(5)
function setLowPower(tm)
    init()
    return tSocketModule[link.getNetwork()].setLowPower(tm)
end

