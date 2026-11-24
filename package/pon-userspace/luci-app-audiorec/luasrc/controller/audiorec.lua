module("luci.controller.audiorec", package.seeall)

function index()
	local page = entry({"admin", "services", "audiorec"}, cbi("audiorec"), _("音频录音"), 61)
	page.dependent = true
end
