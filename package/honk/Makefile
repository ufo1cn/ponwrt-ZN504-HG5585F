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

# v2ray-geoip / v2ray-geosite 只是运行期数据包（提供 /usr/share/v2ray/*.dat，
# 本包 install 段仅软链过去），不是编译期必需。写成硬 +v2ray-geoip/+v2ray-geosite
# 时，构建树里没有对应 feed 就会被 kconfig 隐藏整个 honk（连带 luci-app-honk），
# 镜像阶段 apk add 报 no such package。改用 PACKAGE_xxx 条件依赖：有数据包就带上，
# 没有也能照常编译。
define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=eBPF transparent proxy engine (honk-core framework and dependencies)
  URL:=https://github.com/daeuniverse/honk
  LICENSE:=GPL-3.0-only
  # honk 本体走 tc-bpf，不依赖 nfqueue；nft-queue/nfnetlink-queue 改成「有就带」的条件依赖，
  # 否则内核里 NETFILTER_NETLINK_QUEUE 未开时整个 honk 会被 kconfig 隐藏，
  # 镜像阶段 apk add 报「honk (no such package)」（run 45604633144）。
  #
  # bpftool / tar 同样不能写成硬依赖（r38/r41 就是这么整包消失的）：
  #   · 树里 bpftool 只有 bpftool-minimal / bpftool-full 两个真实符号，`bpftool` 只是
  #     PROVIDES 虚拟名，+bpftool 在 kconfig 里指向 PACKAGE_bpftool，两个变体都没开时
  #     该符号不可满足 → honk 与 luci-app-honk 连 `# ... is not set` 行都不生成（查无此包）；
  #   · tar 在本次构建的包索引里根本没有符号（镜像里用 busybox 的 tar applet 即可，
  #     honk-install 只调 `tar -xzf`）。
  # 两者都改成「有就带」：依赖满足才挂上，不满足也不再拖累整包可见性。
  DEPENDS:=@(aarch64||x86_64) +kmod-veth +kmod-sched-core +kmod-sched-bpf \
           +kmod-nft-core \
           +PACKAGE_kmod-nft-queue:kmod-nft-queue +PACKAGE_kmod-nfnetlink-queue:kmod-nfnetlink-queue \
           +kmod-nf-conntrack +ip-full \
           +PACKAGE_bpftool-minimal:bpftool-minimal +PACKAGE_tar:tar \
           +PACKAGE_v2ray-geoip:v2ray-geoip +PACKAGE_v2ray-geosite:v2ray-geosite \
           +curl +ca-bundle
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
