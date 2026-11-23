# This is free software, licensed under the MIT License.

include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT

LUCI_TITLE:=PonWrt 固件更新（检查 / 下载 / 刷写）
LUCI_DESCRIPTION:=在 LuCI 里检查自建 apk 仓库 meta/fw 索引，按当前运行号判断是否有新固件，\
	下载到 /tmp 并用索引里的 sha256 校验，然后调用 sysupgrade 刷写。\
	支持三种出站方式：直连、指定 HTTP 代理、透明代理（TUN / nftables redir 已生效，无需配置）；\
	仓库索引地址可在页面上改（自建镜像 / 私有源都能用）。
LUCI_DEPENDS:=+luci-base +curl +jsonfilter +rpcd
LUCI_PKGARCH:=all

define Package/luci-app-ponwrt-update/conffiles
/etc/config/ponwrt_update
endef

# git 不记录可执行位（内容 API 塞进来的文件一律 0644），装完统一补一遍。
# 注意：出镜像时 postinst 是在 IPKG_INSTROOT 指定的根目录里跑的，所以 chmod
# 必须带 $${IPKG_INSTROOT} 前缀——以前只在 IPKG_INSTROOT 为空时才 chmod，
# 结果镜像里 /usr/libexec/rpcd/luci.ponwrt_update 仍是 0644，rpcd 起不来这个对象，
# LuCI 就会报 “RPC call to luci.ponwrt_update/status failed: Object not found”。
define Package/luci-app-ponwrt-update/postinst
for f in /usr/bin/ponwrt-update /usr/bin/ponwrt-fw-check \
	/usr/libexec/rpcd/luci.ponwrt_update /etc/profile.d/ponwrt-proxy.sh \
	/etc/uci-defaults/95-ponwrt-version-label; do
	[ -e "$${IPKG_INSTROOT}$$f" ] && chmod 0755 "$${IPKG_INSTROOT}$$f"
done
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
