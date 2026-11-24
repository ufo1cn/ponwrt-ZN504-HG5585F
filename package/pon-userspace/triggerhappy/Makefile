#
# Triggerhappy —— 全局热键守护进程（thd），附带蓝牙 HID 默认按键映射
#
# 上游 wertarbyte/triggerhappy 用普通 Makefile 构建（无 autotools），
# 本包定义只编 thd / th-cmd 两个目标，跳过 man（pod2man 在构建环境里不需要）。
#
# Copyright (C) 2026
include $(TOPDIR)/rules.mk

PKG_NAME:=triggerhappy
PKG_VERSION:=0.5.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/wertarbyte/triggerhappy.git
PKG_SOURCE_VERSION:=b822888066129350e51ad79f1cf307fa38dae4f7

PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING
PKG_MAINTAINER:=Self

include $(INCLUDE_DIR)/package.mk

define Package/triggerhappy
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Global hotkey daemon (thd) + 蓝牙 HID 按键映射
  URL:=https://github.com/wertarbyte/triggerhappy
  DEPENDS:=+kmod-input-evdev
endef

define Package/triggerhappy/description
 Triggerhappy 监听 /dev/input/event*，按键事件按 /etc/triggerhappy/triggers.d/*.conf
 的规则执行命令。适合无显示的无线路由器：蓝牙键盘、遥控器、HID 小键盘的按键
 可直接映射成脚本/ubus 调用。默认规则全部走 /usr/bin/bt-keyaction，动作对应的
 实际命令在 /etc/config/bt-keys 里按 section 名配置（默认只写日志，安全无副作用）。
endef

define Package/triggerhappy/conffiles
/etc/config/bt-keys
/etc/triggerhappy/triggers.d/bt-hid.conf
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CPPFLAGS="$(TARGET_CPPFLAGS)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		thd th-cmd
endef

define Package/triggerhappy/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/thd $(1)/usr/sbin/thd
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/th-cmd $(1)/usr/sbin/th-cmd

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/bt-keyaction $(1)/usr/bin/bt-keyaction

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/triggerhappy.init $(1)/etc/init.d/triggerhappy

	$(INSTALL_DIR) $(1)/etc/hotplug.d/input
	$(INSTALL_BIN) ./files/20-triggerhappy-add $(1)/etc/hotplug.d/input/20-triggerhappy-add

	$(INSTALL_DIR) $(1)/etc/triggerhappy/triggers.d
	$(INSTALL_DATA) ./files/bt-hid.conf $(1)/etc/triggerhappy/triggers.d/bt-hid.conf

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/bt-keys.config $(1)/etc/config/bt-keys
endef

$(eval $(call BuildPackage,triggerhappy))
