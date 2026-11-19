include $(TOPDIR)/rules.mk

PKG_NAME:=gensio
PKG_VERSION:=2.4.1
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
# GitHub releases 资产在 CI 上取不到（run 44577422664 的 gensio-bin.log：github.com 403、各镜像 404
# → No more mirrors to try）。改用 codeload 源码包，PKG_FIXUP:=autoreconf 会重新生成 configure，
# hash 为本地实测 codeload tar 的 sha256（解包根目录同为 gensio-2.4.1）。
PKG_SOURCE_URL:=https://codeload.github.com/cminyard/gensio/tar.gz/refs/tags/v$(PKG_VERSION)
PKG_HASH:=d344060af79e73fdd6dd795a7be1ac3f3a898ca68faa1458b26015263008623b

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/gensio
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=General Stream I/O library (for ser2net 4.x)
  DEPENDS:=+libpthread +libopenssl
endef

define Package/gensio/description
  gensio library required by ser2net >=4.0
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/gensio* $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libgensio*.so* $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/gensio.pc $(1)/usr/lib/pkgconfig/
endef

define Package/gensio/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libgensio*.so.* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,gensio))
