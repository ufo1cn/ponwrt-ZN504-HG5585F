module("luci.controller.blueaudio", package.seeall)

function index()
	local node = entry({"admin", "services", "blueaudio"}, cbi("blueaudio"), _("Blue蓝牙音频"), 70)
	node.dependent = true
	node.icon = "bluetooth"
end
