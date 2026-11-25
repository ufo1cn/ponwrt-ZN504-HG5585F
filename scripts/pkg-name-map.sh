#!/bin/sh
# 包流专用：清单名 → 真实 kconfig 符号 / 真实 apk 文件名（fw-build.yml 不引用本文件）
#
# configs/pon-*-packages.txt 的第二列写的是「产物 apk 文件名」，但两者与 kconfig 符号并不总同名：
#   · ABI_VERSION 会写进 apk 文件名：libnl-core200 / libpcap1 / libncurses6，
#     对应符号仍是 libnl-core / libpcap / libncurses；
#   · PROVIDES 虚拟名不产生独立 apk：libncursesw 由 libncurses 提供，产物是 libncurses6；
#   · 个别清单名写的是源码目录名：package/feeds/packages/ksmbd-tools 里实际包定义是
#     ksmbd-server（另有 ksmbd-hotplug / ksmbd-avahi-service），luci-app-ksmbd 也依赖 ksmbd-server。
#
# 契约：清单改名落地（需随固件流一起重派）之后，本文件即可删除。

pkg_sym_for() {
	_b=$(printf '%s' "$1" | sed -E 's/[0-9]+$//')
	case "$1" in
		libnl-core200) echo "libnl-core" ;;
		libnl-genl200) echo "libnl-genl" ;;
		libncurses|libncursesw) echo "libncurses" ;;
		libpcap1) echo "libpcap" ;;
		ksmbd-tools) echo "ksmbd-server" ;;
		*)
			if [ "$_b" != "$1" ] && grep -qE "^config PACKAGE_${_b}([[:space:]]|$)" tmp/.config-package.in 2>/dev/null; then
				echo "$_b"
			else
				echo "$1"
			fi
			;;
	esac
}

pkg_apk_for() {
	case "$1" in
		libncurses|libncursesw) echo "libncurses6" ;;
		ksmbd-tools) echo "ksmbd-server" ;;
		*) echo "$1" ;;
	esac
}
