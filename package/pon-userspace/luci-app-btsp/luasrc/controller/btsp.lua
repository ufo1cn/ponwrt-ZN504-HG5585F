module("luci.controller.btsp", package.seeall)

function index()
	local node = entry({"admin", "services", "btsp"}, cbi("btsp"), _("BTSP蓝牙串口透传"), 71)
	node.dependent = true
	node.icon = "bluetooth"
end
