#!/bin/sh
# 交互式 shell 里让 apk / curl / uclient-fetch 走 `/etc/config/ponwrt_update` 配置的代理。
# 只对 mode=proxy 生效；direct 不动环境，transparent 由 TUN/redir 接管，也无需环境变量。
[ -x /sbin/uci ] || return 0
[ "$(uci -q get ponwrt_update.settings.mode)" = proxy ] || return 0
p=$(uci -q get ponwrt_update.settings.proxy)
if [ -n "$p" ]; then
	export http_proxy="$p" https_proxy="$p" all_proxy="$p"
fi
