local sys  = require "luci.sys"
local fs   = require "nixio.fs"

local m = Map("audiorec", translate("音频录音"),
	translate("用 USB 声卡/麦克风录音，按固定时长切片写到 U 盘或 NAS。"
		.. "改完参数先点「保存并应用」，再点「开始录音」。"))

local s = m:section(TypedSection, "main", translate("录音设置"))
s.addremove = false
s.anonymous = true

local o = s:option(Flag, "enabled", translate("开机自动录音"))
o.default = "0"
o.rmempty = false
o.description = translate("打开后开机自启；手动「开始录音」不受此开关限制")

o = s:option(Value, "dev", translate("录音设备"))
o.default = "plughw:1,0"
o.rmempty = false
o.description = translate("arecord -D 的值。先点下面「列出音频设备」看序号，USB 声卡一般是 plughw:1,0")

o = s:option(ListValue, "rate", translate("采样率"))
o:value("8000", "8000 Hz（语音最省空间）")
o:value("16000", "16000 Hz（语音推荐）")
o:value("44100", "44100 Hz")
o:value("48000", "48000 Hz")
o.default = "16000"

o = s:option(ListValue, "channels", translate("声道"))
o:value("1", translate("单声道"))
o:value("2", translate("立体声"))
o.default = "1"

o = s:option(ListValue, "format", translate("保存格式"))
o:value("wav", "WAV（无压缩，最稳）")
o:value("flac", "FLAC（无损压缩，约省一半）")
o.default = "flac"
o.description = translate("FLAC 走 ffmpeg 的 flac 编码器；如果转码失败会自动保留 WAV，不会丢录音")

o = s:option(Value, "segment", translate("每段时长（秒）"))
o.default = "600"
o.datatype = "range(30,7200)"
o.rmempty = false
o.description = translate("600 = 10 分钟一段；16kHz 单声道 10 分钟约 19 MB，48kHz 立体声 10 分钟约 115 MB，注意 U 盘/NAS 空间")

o = s:option(Value, "outdir", translate("保存目录"))
o.default = "/mnt/sda1/rec"
o.rmempty = false
o.description = translate("U 盘写 /mnt/sdaX/rec；NAS 先挂载好再填挂载点下的目录，例如 /mnt/nas/rec")

o = s:option(Value, "keep_days", translate("保留天数（0=不清理）"))
o.default = "7"
o.datatype = "range(0,365)"
o.rmempty = false

local notice = ""

local function shq(s)
	return "'" .. tostring(s or ""):gsub("'", [['\''']]) .. "'"
end

local function esc(t)
	return (tostring(t or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function grab(cmd)
	local out = sys.exec(cmd .. " 2>&1") or ""
	if out:gsub("%s", "") == "" then
		return translate("（无输出）")
	end
	return esc(out)
end

local function status_html()
	local body = ""

	local pidfile = "/var/run/audiorec.pid"
	if fs.access(pidfile) and sys.call("kill -0 $(cat " .. pidfile .. ") >/dev/null 2>&1") == 0 then
		body = translate("录音进程：运行中") .. "\n"
		local cur = (sys.exec("cat /tmp/audiorec-state 2>/dev/null") or ""):gsub("%s", "")
		if cur ~= "" then
			body = body .. translate("当前写入：") .. cur .. "\n"
		end
	else
		body = body .. translate("录音进程：已停止") .. "\n"
	end

	local outdir = (m.uci:get("audiorec", "main", "outdir") or ""):gsub("%s", "")
	if outdir ~= "" then
		body = body .. "\n" .. translate("保存目录：") .. outdir
		if fs.access(outdir) then
			body = body .. translate("（可访问）") .. "\n\n" .. translate("最近文件：") .. "\n"
				.. grab("ls -lt " .. shq(outdir) .. " 2>/dev/null | head -n 12")
		else
			body = body .. translate("（目录不存在，开始录音时会尝试创建）") .. "\n"
		end
	end

	body = body .. "\n\n" .. translate("音频设备（arecord -l）：") .. "\n"
		.. grab("arecord -l")

	body = body .. "\n\n" .. translate("录音日志（/tmp/audiorec.log 最近 20 行）：") .. "\n"
		.. grab("tail -n 20 /tmp/audiorec.log")

	local head = ""
	if notice ~= "" then
		head = "<strong class=\"cbi-error\">" .. esc(notice) .. "</strong><br />"
	end
	return head .. "<pre style=\"white-space:pre-wrap;margin:0\">" .. body .. "</pre>"
end

local st = s:option(DummyValue, "_status", translate("当前状态"))
st.rawhtml = true
st.value = status_html()

local function refresh()
	st.value = status_html()
end

o = s:option(Button, "_devices", translate("列出音频设备"))
o.inputtitle = translate("刷新设备列表")
o.inputstyle = "apply"
o.description = translate("执行 arecord -l，结果出现在下面状态区")
function o.write()
	notice = ""
	refresh()
end

o = s:option(Button, "_test", translate("试录 5 秒"))
o.inputtitle = translate("试录 5 秒")
o.inputstyle = "apply"
o.description = translate("按当前参数录到 /tmp/audiorec-test.wav 并显示文件大小；先确认设备名对不对")
function o.write()
	notice = ""
	local out = sys.exec("audiorec-ctl test 5 2>&1") or ""
	if out:gsub("%s", "") == "" then
		notice = translate("试录没有输出，检查 arecord 是否存在、设备名是否正确")
	else
		notice = out
	end
	refresh()
end

o = s:option(Button, "_start", translate("开始录音"))
o.inputtitle = translate("开始录音")
o.inputstyle = "apply"
o.description = translate("后台启动录音循环，按「每段时长」切片；参数改动请先保存并应用")
function o.write()
	notice = ""
	sys.exec("( /etc/init.d/audiorec start ) >/dev/null 2>&1")
	notice = translate("已请求启动录音；几秒后刷新本页看状态")
	refresh()
end

o = s:option(Button, "_stop", translate("停止录音"))
o.inputtitle = translate("停止录音")
o.inputstyle = "reset"
o.description = translate("停止录音循环，已写好的片段保留")
function o.write()
	notice = ""
	sys.exec("( /etc/init.d/audiorec stop ) >/dev/null 2>&1")
	notice = translate("已请求停止录音")
	refresh()
end

-- 「开机自动录音」只控制 /etc/rc.d 链接
local was_enabled = (m.uci:get("audiorec", "main", "enabled") == "1")
m.on_after_commit = function()
	local now = ((sys.exec("uci -q get audiorec.main.enabled 2>/dev/null") or ""):gsub("%s", "") == "1")
	if now == was_enabled then return end
	if now then
		sys.call("/etc/init.d/audiorec enable >/dev/null 2>&1")
	else
		sys.call("/etc/init.d/audiorec disable >/dev/null 2>&1")
	end
	was_enabled = now
end

return m
