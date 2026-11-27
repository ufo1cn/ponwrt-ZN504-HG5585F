#
# camwatch - 事件录像（人形触发 / 保持时间退出 / 环形清理）
#
# 只编一个 shell 脚本包，运行期依赖 camlive 的快照端点与 ffmpeg 的 copy 录制。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=camwatch
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0
PKG_MAINTAINER:=ufo1cn

include $(INCLUDE_DIR)/package.mk

define Package/camwatch
  SECTION:=utils
  CATEGORY:=Utilities
  SUBMENU:=Multimedia
  TITLE:=CamWatch 事件录像（画面变化 + 判人 + 保持退出）
  # 运行期依赖 camlive（提供 /snapshot.jpg 与 /status.json）。camlive 自己带的
  # +kmod-video-uvc 由包流的 DEPENDS strip 摘掉，固件流已编出该 kmod（usb.config 里 =m），
  # 所以这里可以直接声明 +camlive，包流不会因此拉内核链。
  DEPENDS:=+ffmpeg +curl +jsonfilter +camlive
endef

define Package/camwatch/description
  轮询 camlive 的 /snapshot.jpg 做画面变化检测，命中后可选调用视觉模型判人；
  确认有人即从 RTSP 零转码（-c copy）录制，人离开并保持 N 秒后收尾；
  事件片段按天数与容量环形清理，录像自然带"人出现前"的预录片段。
endef

define Package/camwatch/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/camwatch.sh $(1)/usr/bin/camwatch
	$(INSTALL_DIR) $(1)/usr/share/camwatch
	$(INSTALL_BIN) ./files/detect-openai.sh $(1)/usr/share/camwatch/detect-openai.sh
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/camwatch.init $(1)/etc/init.d/camwatch
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/camwatch.config $(1)/etc/config/camwatch
endef

$(eval $(call BuildPackage,camwatch))
