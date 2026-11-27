include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-audiorec
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_MAINTAINER:=ufo1cn
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=LuCI 音频录音（USB 声卡 → U 盘 / NAS）
LUCI_DESCRIPTION:=用 USB 声卡/麦克风录音，按分钟切片写 U 盘或网络盘，支持试录、开始/停止、过期清理。
LUCI_DEPENDS:=+alsa-utils +ffmpeg +luci-compat
LUCI_PKGARCH:=all

# 脚本必须带执行位，打包后统一纠正一次，避免安装后 init.d 起不来。
# conffiles / postinst 必须在 include luci.mk 之前定义：luci.mk 末尾会
# $(eval $(call BuildPackage,...))，之后再 define 钩子不会生效。
define Package/$(PKG_NAME)/conffiles
/etc/config/audiorec
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
chmod 755 /etc/init.d/audiorec /usr/bin/audiorec-loop /usr/bin/audiorec-ctl 2>/dev/null
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk
