include $(TOPDIR)/rules.mk

PKG_NAME:=gensio
PKG_VERSION:=2.4.1
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
# GitHub releases 资产在 CI 上取不到（run 44577422664 的 gensio-bin.log：github.com 403、各镜像 404
# → No more mirrors to try）。改用 codeload 源码包，PKG_FIXUP:=autoreconf 会重新生成 configure，
# hash 为本地实测 codeload tar 的 sha256（解包根目录同为 gensio-2.4.1）。
# 注意：download.pl 会拼成 "<PKG_SOURCE_URL>/<PKG_SOURCE_URL_FILE>"，
# 因此 codeload 的 refs/tags 段单独放进 PKG_SOURCE_URL_FILE，避免生成 .../v2.4.1/gensio-2.4.1.tar.gz 这种 404。
PKG_SOURCE_URL:=https://codeload.github.com/cminyard/gensio/tar.gz/refs/tags
PKG_SOURCE_URL_FILE:=v$(PKG_VERSION)
PKG_HASH:=d344060af79e73fdd6dd795a7be1ac3f3a898ca68faa1458b26015263008623b

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

# CI 交叉编译时 configure 会误用 staging 的 host python3 去链接 target 库，报
#   checking for python3... staging_dir/host/bin/python3
#   Could not link test program to Python   -> .configured Error 1（run 44617103575 第 15 步）
# 本包只需要 C 库给 ser2net 用，python/tcl/swig/go/mdns/openipmi/sctp 语言绑定一律显式关掉。
# 注意必须放在 include 语句之后且用 +=：
# package-defaults.mk 第 81 行用 `CONFIGURE_ARGS = ...` 重新定义，写在 include 之前会被整段覆盖
# （上一轮写成 := 放 include 前，因此这一版仍去探测 python 并失败）。
CONFIGURE_ARGS += \
	--with-glib=no \
	--with-cplusplus=no \
	--without-python \
	--without-tcl \
	--without-swig \
	--without-go \
	--without-mdns \
	--without-openipmi \
	--without-sctp
# run 44637532192 第 15 步 gensio 编译/安装都过了，卡在打包依赖校验：
#   Package gensio is missing dependencies for the following libraries:
#   libglib-2.0.so.0 / libgthread-2.0.so.0 / libstdc++.so.6
# 原因是 configure 在 staging 里探测到 glib 与 C++ 就编了 glib/c++ 包装库。ser2net 只用 C 版
# libgensio，这两个包装库用不上：显式关掉，既不新增 libglib2/libstdcpp 依赖，也不动校验本身。

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
