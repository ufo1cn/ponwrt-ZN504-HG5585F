include $(TOPDIR)/rules.mk

PKG_NAME:=ser2net
PKG_VERSION:=4.6.0
PKG_RELEASE:=1

# 上游 v4.6.0 的 Release 里只有 Ser2Net-4.6.0-windows.exe，没有 ser2net-4.6.0.tar.gz，
# 所以 releases/download 直链 404、各 mirror 也都没有（run 44660310636 第 15 步 ser2net.log）：
#   curl: (22) The requested URL returned error: 404 ... Download failed.
#   No more mirrors to try - giving up.
#   make[2]: *** [Makefile:44: .../dl/ser2net-4.6.0.tar.gz] Error 2
# 改用 codeload 的 tag 源码包（与 gensio 同一手法），PKG_HASH 按实际 tarball 重算。
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/cminyard/ser2net/tar.gz/refs/tags
PKG_SOURCE_URL_FILE:=v$(PKG_VERSION)
PKG_HASH:=859ffa1e1f08b7bf13134016fed00acfee64c1cc376cc3e1739d2832fd33ef94

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

# ser2net 4.x 的配置是 yaml，configure 里 yaml.h 是硬性检查（run 44666977648 第 15 步 ser2net.log）：
#   checking for yaml.h... no
#   configure: error: yaml.h not found, please install libyaml dev package
# libyaml 由 feeds 的 libs/yaml 提供（PKG_NAME:=yaml，包名 libyaml，Build/InstallDev 会铺 yaml.h + libyaml*.so*），
# 所以这里把 +libyaml 补进 DEPENDS，并让编译前先把它 InstallDev 到 staging。
define Package/ser2net
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Serial to TCP proxy (ser2net 4.x, yaml config)
  DEPENDS:=+gensio +libpthread +libyaml
endef

define Package/ser2net/description
  ser2net 4.x, uses yaml configuration, supports telnet/tcp raw
endef

define Package/ser2net/conffiles
/etc/ser2net.yaml
/etc/config/ser2net
endef

define Package/ser2net/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(CP) $(PKG_INSTALL_DIR)/usr/bin/ser2net $(1)/usr/bin/
	$(CP) $(PKG_INSTALL_DIR)/usr/bin/ser2netctl $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/ser2net.init $(1)/etc/init.d/ser2net
	$(INSTALL_DIR) $(1)/etc
	$(CP) ./files/ser2net.yaml.template $(1)/etc/ser2net.yaml.template
endef

$(eval $(call BuildPackage,ser2net))
