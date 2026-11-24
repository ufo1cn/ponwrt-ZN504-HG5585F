include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-btsp
PKG_VERSION:=1.0
PKG_RELEASE:=4
PKG_MAINTAINER:=Self
PKG_LICENSE:=GPLv3

LUCI_TITLE:=BTSP 蓝牙串口透传
LUCI_DEPENDS:=+ser2net +bluez-daemon +bluez-utils +kmod-bluetooth +luci-compat
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
