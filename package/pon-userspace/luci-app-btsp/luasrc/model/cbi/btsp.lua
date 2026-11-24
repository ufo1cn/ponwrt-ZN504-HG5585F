local sys = require "luci.sys"
local fs  = require "nixio.fs"

local m = Map("btsp", translate("BTSP 蓝牙串口透传"),
    translate("把蓝牙 SPP 串口设备（HC-05 / JDY-31 之类）绑定成本机 /dev/rfcomm0，再由 Ser2net 暴露成 TCP 端口。"
        .. "本页负责配对和 rfcomm 绑定，TCP 监听请在「服务 > Ser2net」里加一条 device=/dev/rfcomm0 的规则。"))

local s = m:section(TypedSection, "main", translate("蓝牙设备"),
    translate("填蓝牙 MAC 与 RFCOMM 通道；启用后开机自动 rfcomm bind（首次读写时才真正发起 SPP 连接）。"))
s.anonymous = true
s.addremove = false

local o = s:option(Flag, "enable", translate("启用"))
o.rmempty = false
o.description = translate("关闭时 /etc/init.d/btsp 只做 rfcomm release，不绑定设备")

o = s:option(Value, "mac", translate("蓝牙 MAC 地址"))
o.placeholder = "AA:BB:CC:DD:EE:FF"
o.datatype = "macaddr"
o.rmempty = true
o.description = translate("对端蓝牙串口模块的 MAC（点下面的「开始扫描」能看到）")

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

local function esc(t)
    return (t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function grab(cmd)
    local out = sys.exec(cmd .. " 2>&1") or ""
    if out:gsub("%s", "") == "" then
        return translate("（无输出）")
    end
    return esc(out)
end

local notice = ""

local function status_html()
    local body = "rfcomm -a:\n" .. grab("rfcomm -a")
        .. "\n\nbluetoothctl devices Paired:\n" .. grab("bluetoothctl devices Paired")
    if fs.access("/tmp/btsp-scan.log") then
        body = body .. "\n\n扫描日志 /tmp/btsp-scan.log（最近 30 行）:\n"
            .. grab("tail -n 30 /tmp/btsp-scan.log")
    end
    local head = ""
    if notice ~= "" then
        head = "<strong class=\"cbi-error\">" .. esc(notice) .. "</strong><br />"
    end
    return head .. "<pre style=\"white-space:pre-wrap;margin:0\">" .. body .. "</pre>"
end

o = s:option(DummyValue, "_status", translate("当前状态"))
o.rawhtml = true
o.value = status_html()

local st = o
local function refresh()
    st.value = status_html()
end

local function field_val(key, dflt)
    local v = m:formvalue("cbid.btsp.main." .. key) or dflt or ""
    return (v:gsub("%s", ""))
end

-- 操作按钮：点一下就在本次请求里执行，然后把状态区刷成最新结果
o = s:option(Button, "_scan", translate("扫描设备"))
o.inputtitle = translate("开始扫描")
o.inputstyle = "apply"
o.description = translate("约 7 秒，结果写进 /tmp/btsp-scan.log 并显示在下面状态区")
function o.write()
    notice = ""
    sys.exec("( /etc/init.d/btsp scan ) >/dev/null 2>&1")
    refresh()
end

o = s:option(Button, "_pair", translate("配对并绑定"))
o.inputtitle = translate("配对并绑定")
o.inputstyle = "apply"
o.description = translate("用上面填的 MAC 配对 + trust，然后 rfcomm bind 到设备节点")
function o.write(self, section)
    notice = ""
    local mac = field_val("mac"):upper()
    if not mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        notice = translate("MAC 地址格式不对，应为 AA:BB:CC:DD:EE:FF；已跳过配对")
        refresh()
        return
    end
    self.map.uci:set("btsp", "main", "mac", mac)
    self.map.uci:commit("btsp")
    sys.exec("( /etc/init.d/btsp pair " .. mac .. " ) >/dev/null 2>&1")
    sys.exec("( /etc/init.d/btsp bind " .. mac .. " ) >/dev/null 2>&1")
    refresh()
end

o = s:option(Button, "_release", translate("解除绑定"))
o.inputtitle = translate("解除绑定")
o.inputstyle = "reset"
o.description = translate("release 掉当前的 rfcomm 绑定（等价于停掉服务）")
function o.write()
    notice = ""
    sys.exec("( /etc/init.d/btsp release ) >/dev/null 2>&1")
    refresh()
end

return m
