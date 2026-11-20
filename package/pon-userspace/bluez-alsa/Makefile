#
# BlueALSA —— 蓝牙音频 ALSA 后端（自建包定义）
#
# 说明：标准 feeds（immortalwrt/packages、openwrt/packages）都没有 bluez-alsa，
#       之前用的是第三方仓库 bluealsa4openwrt 的包定义；这里改为由本仓库自己
#       从上游源码（arkq/bluez-alsa）构建，锁定版本、不依赖任何第三方包仓库。
#
# 产物：/usr/bin/bluealsa（守护进程）、/usr/bin/bluealsa-aplay（A2DP/SCO 转发到本机声卡）、
#       /usr/bin/bluealsa-cli（诊断）
#
# Copyright (C) 2026
#
include $(TOPDIR)/rules.mk

PKG_NAME:=bluez-alsa
PKG_VERSION:=4.3.1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/arkq/bluez-alsa.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1
# configure 需要 gdbus-codegen（由 host 版 glib2 提供）。不声明这条时，
# 只会编 cross 版 glib2，staging_dir/host/bin/gdbus-codegen 不存在 →
#   checking for gdbus-codegen... no
#   configure: error: gdbus-codegen not found   (legacy run 44752208306 实测)
PKG_BUILD_DEPENDS:=glib2/host
PKG_LICENSE:=LGPL-2.1-or-later
PKG_MAINTAINER:=Self

include $(INCLUDE_DIR)/package.mk

define Package/bluez-alsa
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=Bluetooth Audio ALSA Backend
  URL:=https://github.com/arkq/bluez-alsa
  DEPENDS:=+alsa-lib +bluez-libs +sbc +glib2 +libdbus +libpthread +librt
endef

define Package/bluez-alsa/description
 BlueALSA 把蓝牙音频设备（A2DP source/sink、HFP/HSP）暴露为 ALSA PCM，
 由 bluealsa 守护进程 + bluealsa-aplay 转发到本机声卡。
endef

# 只启用在路由上真正需要的部分：守护进程 + aplay + cli。
# systemd / upower / man / test / 其它工具全部关闭，避免引入额外依赖。
CONFIGURE_ARGS += \
	--with-bluealsauser=root \
	--with-bluealsaaplayuser=root \
	--with-alsaplugindir=/usr/lib/alsa-lib \
	--disable-systemd \
	--disable-upower \
	--disable-manpages \
	--disable-test \
	--disable-a2dpconf \
	--disable-hcitop \
	--disable-rfcomm \
	--enable-aplay \
	--enable-cli

define Package/bluez-alsa/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa-aplay $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa-cli $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/lib/alsa-lib
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/lib/alsa-lib/libasound_module_pcm_bluealsa.so $(1)/usr/lib/alsa-lib/
endef

$(eval $(call BuildPackage,bluez-alsa))
