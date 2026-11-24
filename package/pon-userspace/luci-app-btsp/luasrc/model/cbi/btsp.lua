local sys = require "luci.sys"

local m = Map("btsp", translate("BTSP 蓝牙串口透传"),
    translate("把蓝牙 SPP 串口设备（HC-05 / JDY-31 之类）绑定成本机 /dev/rfcomm0，再由 Ser2net 暴露成 TCP 端口。"
        .. "本页只负责配对和 rfcomm 绑定，TCP 监听请在「服务 > Ser2net」里加一条 device=/dev/rfcomm0 的规则。"))

local s = m:section(TypedSection, "main", translate("蓝牙设备"),
    translate("填蓝牙 MAC 与 RFCOMM 通道；启用后开机自动 rfcomm bind（首次读写时才真正发起 SPP 连接）。"))
s.anonymous = true
s.addremove = false

local o = s:option(Flag, "enable", translate("启用"))
o.rmempty = false
o.description = translate("关闭时 /etc/init.d/btsp 只做 rfcomm release，不绑定设备")

o = s:option(Value, "mac", translate("蓝牙 MAC 地址"))
o.placeholder = "AA:BB:CC:DD:EE:FF"
o.description = translate("对端蓝牙串口模块的 MAC（bluetoothctl devices 能看到）")

o = s:option(Value, "channel", translate("RFCOMM 通道"))
o.datatype = "range(1,30)"
o.default = "1"
o.description = translate("SPP 一般是 1；不确定就留 1")

o = s:option(Value, "dev", translate("绑定到的设备节点"))
o.default = "/dev/rfcomm0"
o.rmempty = false
o.description = translate("Ser2net 里填同一个节点")

o = s:option(Flag, "autopair", translate("启动时自动配对并信任"))
o.default = "1"
o.description = translate("已配对会跳过；配对失败只是不建立连接，不会让服务起不来")

o = s:option(DummyValue, "_status", translate("当前状态"))
o.rawhtml = true
local function esc(t)
    return (t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function grab(cmd)
    local out = sys.exec(cmd .. " 2>&1")
    if not out or out:gsub("%s", "") == "" then
        return translate("（无输出）")
    end
    return esc(out)
end

local rfcomm_out = grab("rfcomm -a")
local paired_out = grab("bluetoothctl devices Paired")

o.value = "<pre style=\"white-space:pre-wrap;margin:0\">"
    .. "rfcomm -a:\n" .. rfcomm_out .. "\n\n"
    .. "bluetoothctl devices Paired:\n" .. paired_out
    .. "</pre>"

return m
