module("luci.controller.camlive", package.seeall)

function index()
	local node = entry({"admin", "services", "camlive"}, cbi("camlive"), _("CamLive摄像头推流"), 72)
	node.dependent = true
	node.icon = "camera"
end
