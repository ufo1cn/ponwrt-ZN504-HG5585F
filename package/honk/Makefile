#
# OpenWrt package: honk (lightweight runtime framework and dependencies, dynamic core mode)
#

PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
PKG_VERSION:=0.1.0_beta6
PKG_RELEASE:=2

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=eBPF transparent proxy engine (honk-core framework and dependencies)
  URL:=https://github.com/daeuniverse/honk
  LICENSE:=GPL-3.0-only
  DEPENDS:=@(aarch64||x86_64) +kmod-veth +kmod-sched-core +kmod-sched-bpf \
           +kmod-nft-core +kmod-nft-queue +kmod-nfnetlink-queue \
           +kmod-nf-conntrack +bpftool +ip-full +v2ray-geoip +v2ray-geosite \
           +curl +tar +ca-bundle
endef

define Package/honk/description
 honk is an eBPF transparent proxy engine with embedded doona dashboard.
 This package provides runtime dependencies, kernel modules, procd service and configuration skeleton.
 The honk-core binary can be dynamically installed via 'honk-install'.
endef

define Package/honk/conffiles
/etc/config/honk
/etc/honk/config.dae
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/honk/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_DIR)/files/honk-install $(1)/usr/bin/honk-install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_DIR)/files/honk.init $(1)/etc/init.d/honk
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_DIR)/files/honk.config $(1)/etc/config/honk
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_DIR)/files/honk.uci-defaults $(1)/etc/uci-defaults/90-honk-autostart
	$(INSTALL_DIR) $(1)/etc/honk
	$(INSTALL_CONF) $(PKG_DIR)/files/config.dae $(1)/etc/honk/config.dae
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	printf '%s\n' '/etc/honk/data/' '/usr/bin/honk' '/usr/bin/honk-core' > $(1)/lib/upgrade/keep.d/honk
	$(INSTALL_DIR) $(1)/usr/share/honk
	$(LN) ../v2ray/geoip.dat $(1)/usr/share/honk/geoip.dat
	$(LN) ../v2ray/geosite.dat $(1)/usr/share/honk/geosite.dat
endef

$(eval $(call BuildPackage,honk))
