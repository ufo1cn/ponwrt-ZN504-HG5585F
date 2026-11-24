#
# luci-app-iptvscan —— IPTV 频道扫描（抓 IGMP 组播生成 rtp2httpd 播放列表）
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-iptvscan
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=ufo1cn

LUCI_TITLE:=LuCI IPTV channel scanner (IGMP -> rtp2httpd playlist)
LUCI_DESCRIPTION:=Scan IGMP multicast groups on the IPTV interface and build an m3u playlist for rtp2httpd
LUCI_DEPENDS:=+luci-base +rpcd-mod-file +tcpdump
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/iptvscan
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
