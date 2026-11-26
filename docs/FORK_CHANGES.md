# Fork 变更说明

上游：`wuziwei/ponwrt-ZN504-HG5585F`（master）→ 源 `pbs05/ponwrt`
本仓库：`ufo1cn/ponwrt-ZN504-HG5585F`（编译与发布用）
包仓库：`ufo1cn/ponwrt-apk-repo`（索引分支 `repo`，实验分支 `repo-wed`）
旧仓库：`ufo1cn/PonWrt-HG5382A`（已停用，仅存档）

本文件只记录**本仓库相对上游的差异**，以及每条差异解决什么问题。上游的 `configs/`、`.github/workflows/` 口径一律不采纳。

---

## 一、构建入口

| 工作流 | 作用 | 备注 |
| --- | --- | --- |
| `fw-all.yml` | 唯一固件入口，一次 `make` 编五台机型 | 调 `fw-build.yml`，`label=all` |
| `fw-build.yml` | 真正的编译体（内核 + kmod + 镜像 + kmod apk） | 按 `configs/devices/*.config` 装机型包；`apk_repo_branch` 决定镜像里的源分支 |
| `fw-publish.yml` | 把固件搬进 apk-repo 的 Release 并写 `meta/fw/<device>.json` | 供 `luci-app-ponwrt-update` 检查更新；`idx_branch=repo` 发主线五台（源 `master` / label `all`），`repo-wed` 发 WED 两台 HG5585F（源 `feat/wed-npu-offload-6.18` / label `wed`） |
| `pkg-publish.yml` | 把三条包工作流的 apk + 固件流程的 kmod apk 归入 apk-repo 并重建签名索引 | `idx_branch` 选索引分支（`repo` 只收 label `all`、`repo-wed` 只收 label `wed`，写错直接失败）；与 `fw-publish` / reindex 共用写锁 `apk-repo-write-<索引分支>` |
| `build-packages-incremental.yml` / `-legacy` / `-extra` | 用户态包、旧板包、额外包 | 只编非 kmod 的用户态包，不含内核树步骤；kmod 全由 `fw-build` 编 |

已删除、不得复活：`fw-usb-wifi.yml`、`fw-usb.yml`、`fw-plain.yml`、`configs/device-features.txt`、`build-firmware-manual.yml`。`PonWrt1.yml`（run 391191043）永不修改。

## 二、机型与能力

| Device | 能力 | 预装口径 |
| --- | --- | --- |
| `fiberhome_hg5585f-ct` | usb wifi bt | 全量 USB/WiFi/BT 预装 + `block-mount` + `zram`（honk 不预装，见第五节） |
| `fiberhome_hg5585f-ct-usb-sfp` | usb wifi bt | 同上，另加 `kmod-phy-maxlinear` |
| `nokia_xg-040g-md-ubi` | usb bt | USB/BT 预装 + `zram`（honk 不预装） |
| `znxt_zn504xg-d` | usb | USB 预装（去 `kmod-mt7915e`/`kmod-mt7916-firmware`）+ `zram`（honk 不预装） |
| `fiberhome_hg5382a` | 无 | 只装 `kmod-zram zram-swap`（plain 基线） |

能力只写一处：`configs/devices/<board>.config` 的 `DEVICE_CAPS`；装包清单写 `DEVICE_PREINSTALL`。工作流按能力表校验，能力表与清单不一致会直接失败。

## 三、内核与板级补丁

- `target/linux/airoha/patches-6.18` 共 181 个，含 9xx 板级（930/931/932/947/951-01/951-02/980/999）、748 usb-hsgmii、762 RTL8221B LED、913 PCIe HB reset、310-xx GDM3/4 与 AIROHA PCS/phylink、941-xx NPU fw 信息、915 flowtable 卸载 —— 这些上游与我们都已有。
- WED / NPU 硬件卸载不在 master，单独放在 `feat/wed-npu-offload-6.18`：
  - `952-net-mediatek-wed-allow-airoha-ops-only.patch`、`953-net-airoha-add-an7581-wed-v1-tx-offload.patch`、`954-net-airoha-npu-mt7916-rx-and-hostadpt.patch`
  - `dts/an7581-npu-mt7916.dtsi`（新增）、`dts/an7581-fiberhome-hg5585f-common.dtsi`（加一行 include）
  - `package/kernel/mt76/patches/120-mt76-npu-connac2-compat.patch`、`121-mt7915-add-airoha-npu-rx-and-double-pcie-wed.patch`
  - 带上了上游把 NPU 保留内存搬到 high DRAM 的早启动修复；该分支 `fw-all.yml` 只编两台 HG5585F，`label=wed`，镜像 apk 源指向 `repo-wed`；发布时 `fw-publish` 用 `idx_branch=repo-wed` 把 WED 固件写进 `repo-wed` 的 Release 与 `meta/fw`，不碰主线 `repo`。

## 四、全锥 NAT（fullcone2）

- 内核 hack：`target/linux/generic/hack-6.18/982-add-bcm-fullconenat-support.patch`、`983-add-bcm-fullconenat-to-nft.patch`、`984-netfilter-reserve-unconfirmed-nat-tuples.patch`、`985-netfilter-bcm-fullcone-reserve-expectation-early.patch`
- 用户态：`package/libs/libnftnl/patches/002-libnftnl-add-masquerade-fullcone-flag.patch`、`package/network/utils/nftables/patches/103-nftables-add-masquerade-fullcone-flag.patch`、`package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch`
- 这些补丁在编译时自动应用，不需要改 `.config`。**默认不启用**：需要 `uci set firewall.@defaults[0].fullcone='1'` 才生效。

## 五、honk 透明代理

- `package/honk`：Makefile、`honk.init`、`honk.config`、`honk-install`（运行时安装 honk-core，镜像只带框架）、`honk.uci-defaults`、`files/config.dae`
- `package/luci-app-honk`：内嵌 UI、中文菜单与 i18n、ACL
- `files/usr/bin/sb` + `files/etc/nftables.d/30-sidestore.nft`：nft 侧分流规则
- `package/luci-app-airoha-npu/root/usr/libexec/rpcd/luci.airoha_npu` 只摘了"按信道频率归频段统计站点"那段；上游整体版本缺 `fw_version` 读取，整体覆盖会让 NPU 面板回到 `Unknown`，故不覆盖。
- **不预装进任何机型镜像**（`release.config` 里只写 `CONFIG_PACKAGE_honk=m` / `luci-app-honk=m`，`m` 只出 apk 不装机），需要时 `apk add honk luci-app-honk`；`luci-app-honk` 依赖的 `luci-lib-daeuniverse` 在树内、随包自动编出。
- `honk` 的 `DEPENDS` 里 `bpftool` / `tar` 必须是「有就带」条件依赖（`+PACKAGE_bpftool-minimal:bpftool-minimal`、`+PACKAGE_tar:tar`）：`bpftool` 只是 `PROVIDES` 虚拟名（真实符号是 `bpftool-minimal` / `bpftool-full`，两个都没开时不可满足），`tar` 在本树包索引里没有符号，任一写成硬依赖都会让 kconfig 把 honk 连 `# ... is not set` 行都不生成，镜像与 apk 双双消失（此即 r38/r41 的成因）。
- `build-packages-extra.yml` 的 Configure 自检里带 `CONFIG_PACKAGE_honk` / `CONFIG_PACKAGE_luci-app-honk`，符号被吞会直接失败而不是静默跳过。

## 六、运行时调优

| 文件 | 内容 |
| --- | --- |
| `files/etc/sysctl.d/99-custom-net-optimization.conf` | 4MB socket 缓冲、BBR + fq、conntrack 收紧、`bridge-nf-call-*` 关闭、vm 调优 |
| `files/etc/sysctl.d/99-memory-optimized.conf` | 内存回收水位 |
| `files/etc/sysctl.d/99-bt-ppe-tuning.conf` | BT PPE sysctl |
| `files/etc/hotplug.d/net/98-pppoe-rps` | PPPoE / `phy0-ap0` / `lan*` / `pon0` 的 RPS 与 `rps_flow_cnt` |
| `files/etc/rc.local` | txqueuelen 5000、LLDP 放行、`airoha_eth` 硬中断分核、governor 锁 performance、PPE `bind_rate=5`、airoha-pond `oom_score_adj=-1000`、honk cgroup `memory.high`、zram 场景下 `vm.swappiness=20` |
| `files/etc/sysupgrade.conf` | 保留 honk / tailscale / 自定义配置路径 |

上游 `rc.local` 里"非 PPPoE 时强插 `fe80::1` 走 br-lan"那段已删除：会污染多机型拓扑。

## 七、zram

- 树里原本就设了 `system.zram_size_mb=256` + `zram_comp_algo=zstd` + 每日 `compact` cron，但 `CONFIG_PACKAGE_kmod-zram` 与 `zram-swap` 都没编，等于一堆死配置（上游因此把它们删掉）。
- 现在反过来：`kmod-zram` + `zram-swap` 预装进**全部五台**机型，配置因此真正生效。`zram-swap` 的 init 默认容量是 `MemTotal/2048`（约半个 RAM），本树显式写成 256MB，压缩后实际占用约几十 MB；`vm.swappiness=20` 避免 page cache 被提前赶进压缩区。
- 只有内核 swap 打开才有意义：`CONFIG_KERNEL_SWAP=y`（已确认）。

## 八、软件仓库与分支

- 固件镜像里的 apk 源由 `fw-build.yml` 生成，分支由输入 `apk_repo_branch` 决定（默认 `repo`）；目录结构 `ponwrt-k<内核版本>/<common|usb|wifi|bt>/packages.adb`。
- 多机型构建时不在构建期写死源，而是把「机型→能力」表与源前缀装进镜像，首次启动由 `96-ponwrt-apk-repos` 按 `board_name` 生成 `90-ponwrt-apk-repo.list`。
- `pkg-publish.yml` 的 `idx_branch` 决定写哪个索引分支；`repo-wed` 从 `repo` 拉出，专供 WED 分支固件，避免实验 kmod 混进主线。
- 签名：全仓库只用同一把 `APK_SIGNING_PRIVATE_KEY`，公钥指纹 `d557dca1a8b8d30b48f7e4b910908342789d389a52db3d7225c6b72840eda4ed`；`fw-build` 与 `pkg-publish` 都会断言。

- 写 apk-repo 的三条流（`fw-publish.yml`、`pkg-publish.yml`、apk-repo 的 `reindex-apk-repo.yml`）共用同一把写锁 `apk-repo-write-<索引分支>`（`cancel-in-progress: false`）。三者都往同一分支 commit，串行排队比各自 rebase 撞运气可靠；写不同分支（`repo` / `repo-wed`）互不阻塞。
- `reindex-apk-repo.yml` 只作兜底：matrix 跑 `repo` 与 `repo-wed` 两条分支，每 2 小时一次（原 `*/10` 已降频）。正常入库由 `pkg-publish` 自己重签索引，reindex 负责修「手工塞进仓的包 / 发布中断留下的索引漂移」并补签；某分支还没有任何包时只告警跳过，不报错。
- kmods 分组：`pkg-publish --groups kmods` 直接取固件 artifact 的 `kmods/`，按 `configs/pon-feature-packages.txt` 归类到 common/usb/wifi/bt，所以从更新页装包时 kmod 依赖不再“取不到”。

- Gitee 只读镜像：`reindex-apk-repo.yml` 每 2 小时重建索引后，把 `repo` / `repo-wed` 各做一份**单提交快照**强推到 Gitee（内容变了才推，用 `.snapshot-id` 比对；未配 `secrets.GITEE_USER` / `GITEE_TOKEN` 与变量 `GITEE_REPO` 时只告警跳过）。Gitee 侧分支永远只有 1 个 commit，体积 ≈ 当前文件量，不会因历史累积撞上 500MB 上限；GitHub 仍是唯一写入源。
- 固件双源：设置仓库变量 `APK_GITEE_BASE`（如 `https://gitee.com/<owner>/ponwrt-apk-repo/raw`）后，镜像内 `/etc/ponwrt-repo-mirror.txt` 记录 Gitee 前缀，`96-ponwrt-apk-repos` 在能力源之后追加同一组 Gitee 源（同内容、同一把私钥签名；`apk` 按版本取最高那份）。变量留空时镜像里只有 GitHub 源，行为与之前一致。

## 九、软件包（不进镜像）

- `tailscale` 加入 `configs/pon-userspace-packages.txt`，作为独立 apk 由包工作流产出、经 `pkg-publish` 入仓库；不预装进任何机型镜像。依赖的 `kmod-tun` 已在 `configs/an7581.config` 里常年 `=y`。
- `honk` 三件套（`honk` / `luci-app-honk` / `luci-i18n-honk-zh-cn`）、`lyaml` / `libyaml` / `libuci-lua`（passwall2 依赖链）、OpenClash、SQM 全套（`sqm-scripts` / `luci-app-sqm` / i18n / `tc-tiny` / `nftables-json`）都只进 `pon-extra-packages.txt`，由 extra 流编成 apk，经 `pkg-publish` 入 apk-repo；`honk` 不再预装进镜像。
- 已入库的一批可查 `pkgs-extra-hg5585f-ct-r34`（2026-11-26，含上述 honk 三件套与 lyaml/libyaml/libuci-lua）与 apk-repo `repo` 分支同一批 20 个 apk。
- 三条包工作流的 kmod 口径：`Configure` 之后先删掉 `.config` 里全部 `CONFIG_PACKAGE_kmod-*` 与 `gpio-button-hotplug` 选择并断言剩余为 0，然后由预检扫描 `configs/pon-*.txt` 清单内每个 Makefile，凡出现 `$(LINUX_DIR)`、`${LINUX_DIR}`、`$(LINUX_KARCH)`、`vmlinux`、`KERNEL_MAKE` 直接失败。这类包（eBPF CO-RE、`perf`、`bpftool` 生成 `vmlinux.h` 等）的产物把内核结构体偏移和私有头锈进二进制，换内核 config 即失效，只能随固件一起编。

## 十、明确不做

- 不采纳上游 `configs/`（`an7581.config`、`release.config` 的改法）与任何上游 workflow（`build-zn504.yml` 等）。
- 不做 plain 机型的全量预装（按能力预装）。
- `bake_usb` 已废弃，不再用 usb 驱动是否预装来区分入口。
