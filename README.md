# PonWrt 6.18 for 五款 Airoha AN7581 光猫（ZN504XG-D / HG5585F CT / HG5585F CT-USB-SFP / HG5382A / Nokia XG-040G-MD）

简体中文 | [English](README_en.md)

[![GitHub Actions Build Status](https://img.shields.io/github/actions/workflow/status/ufo1cn/ponwrt-ZN504-HG5585F/fw-all.yml?branch=master&style=flat-square&logo=github)](https://github.com/ufo1cn/ponwrt-ZN504-HG5585F/actions)
[![Latest Release](https://img.shields.io/github/v/release/ufo1cn/ponwrt-ZN504-HG5585F?style=flat-square&logo=github)](https://github.com/ufo1cn/ponwrt-ZN504-HG5585F/releases)
[![Target](https://img.shields.io/badge/SoC-Airoha%20AN7581-blue?style=flat-square)](https://github.com/ufo1cn/ponwrt-ZN504-HG5585F)
[![Device](https://img.shields.io/badge/Device-5%20models-green?style=flat-square)](https://github.com/ufo1cn/ponwrt-ZN504-HG5585F)
[![Kernel](https://img.shields.io/badge/Kernel-Linux%206.18-informational?style=flat-square)](https://github.com/ufo1cn/ponwrt-ZN504-HG5585F)
[![License](https://img.shields.io/badge/License-GPL--2.0-orange?style=flat-square)](LICENSE)

本项目基于上游 [PonWrt](https://github.com/pbs05/ponwrt)（ImmortalWrt / Linux `6.18`），针对采用 **达发 Airoha AN7581 (4核 Cortex-A53 @ 1.2GHz + 8核 RISC-V NPU)** 主控的五款光猫进行深度工程化定制、硬件驱动加速与内核网络栈增强，一次 `fw-all` 构建同时产出全部机型：

| 机型 | profile | 硬件/能力 |
| :--- | :--- | :--- |
| 兆能 ZN504XG-D | `znxt_zn504xg-d` | 纯有线 2.5G（EN8811H + 3×千兆），USB |
| 烽火 HG5382A | `fiberhome_hg5382a` | plain 基线（仅 `kmod-zram` + `zram-swap`） |
| 烽火 HG5585F 电信版 | `fiberhome_hg5585f-ct` | MT7916D DBDC AX3000 + USB 2.0 + BT |
| 烽火 HG5585F 电信版（USB/SFP 版） | `fiberhome_hg5585f-ct-usb-sfp` | 同上 + `usb_pcs`（2.5G 口走 usb_pcs 的 2500base-X）；`kmod-phy-maxlinear` 由 `an7581.config` 的 `CONFIG_MODULE_DEFAULT_kmod-phy-maxlinear=y` 装进全部五机型，不是本机型独有 |
| 诺基亚 XG-040G-MD UBI | `nokia_xg-040g-md-ubi` | USB + BT |

预装范围只由 `configs/devices/<board>.config` 的 `DEVICE_CAPS` / `DEVICE_PREINSTALL` 决定；应用类软件（OpenClash / SQM / honk / passwall2 等）不进镜像，统一走独立 apk（见「独立软件包与 apk 仓库」）。

---

## 💡 一、本项目与上游/公版核心差异对比矩阵

下表系统梳理了本项目（PonWrt 聚合增强版）相比官方上游 PonWrt / ImmortalWrt 公版及社区常见第三方固件的技术代差：

| 核心功能 / 优化维度 | 上游公版 & 社区现状 (痛点) | 本项目聚合增强版 (独家根治与实测收益) |
| :--- | :--- | :--- |
| **IPTV 1302 鉴权根治** | ❌ 组播口与业务口共用网桥，动态 MAC 学习引发 FDB 翻转单播黑洞；社区多仅重启或转单播 | ✅ **独家补丁 `03-pon-userspace-iptv`**：组播口 `learning=0` + 动态探测业务口 BNG MAC 并静态固化，**彻底根除 1302 超时与黑洞，切台秒开** |
| **HG5585F 满血 Wi-Fi 6** | ❌ 缺 EEPROM 提取与射频校准；软中断挤死 Core 0（跑满即 100% 单核假死），测速仅 500~670M | ✅ **MT7916D 满血驱动 + 独家 4 核中断亲和调度**：`pin-wifi-cpus.sh` 将收发与 NAPI 线程精准均衡至 4 核，突破单核瓶颈，**实测 5G 突破 770~1100+ Mbps**，软中断零积压 |
| **PON 参数跨固件防丢** | ❌ 升级固件默认冲刷覆盖 `/etc/config/pon`，未手动保存直接失联变砖；社区需登录 SSH 手动备份 | ✅ **内置一键备份/还原脚本**，开机自动生成并注入系统升级白名单，**无感保留 LOID、SN、MAC 与宽带账号**，升级零丢配置 |
| **NNdroid OLT 局端防掉线** | ❌ 缺激光冷机防抖，偶发误报 `SYS_TX_READY` 被局端秒踢；华为等 OLT 报 `reason=0x01` 难以定位 | ✅ **集成 EN7572 激光冷启动 8 次采样闭锁保护**；支持 Web 自由切换 LOID 补零；状态页直显 16 进制报文，**冷启动 100% 稳出光** |
| **QWRT 16MB 网络缓冲** | ⚠️ 内核默认 2MB 缓冲，队列深度低，高并发 BT/多任务时交换芯片 CDM 队列易溢出丢包 | ✅ **对齐 QWRT 16MB (`16777216`) TCP/UDP 核心缓冲**，队列深度扩至 16384，内存防碎片，**彻底消除 CDM 突发溢出丢包** |
| **广播免跟踪 (NOTRACK)** | ❌ UPnP SSDP 与 Windows WSD 广播泛滥进入 conntrack 状态表，导致查表开销剧增与队列膨胀 | ✅ **预置 SSDP (`239.255.255.250:1900`) 与 WSD (`3702`) 全链路 `NOTRACK` 规则**，阻断局域网广播风暴污染连接跟踪表 |
| **开箱即用 br-iptv 代理** | ❌ 无预置网桥与代理，需自行抓包建桥；旧版单栈 udpxy 易引发二层组播环路反射与端口占用 | ✅ **预置隔离网桥 `br-iptv`（`isolate=1, learning=0`）**，集成 `rtp2httpd` 端口 4022 多核并发零拷贝，附带 Web 播放器，**全屋网页秒开** |
| **双栈硬件流卸载 (PPE)** | ⚠️ 常见固件缺少网桥卸载补丁导致下行卸载率仅 17%；IPv6 PPPoE 严重丢包卡死，迫使用户关闭加速 | ✅ **独家补丁 931/932 修复 AN7581 PPE 缺陷与网桥从端口卸载**：实现 IPv4+IPv6 双栈 100% 直转，**千兆满速 CPU 仅 ~4%，下行硬件卸载率飙升至 90%+** |
| **纯净硬件加解密优化** | ⚠️ 保留 SafeXcel / EIP-93 协处理器驱动，诱发 Crypto API 优先级霸凌、DMA 性能倒挂与锁争用 | ✅ **彻底剔除 `kmod-crypto-hw-eip93` 负优化**，释放 4 核 1.2GHz ARMv8 NEON 向量直算，**小包 DMA 刷脏归零，WireGuard/Sing-Box 吞吐更稳** |
| **Sing-Box 原生 NFQUEUE & Honk eBPF** | ❌ 缺 `kmod-nft-queue` / `kmod-veth` 驱动，开透明代理必崩；靠易冲突的自定义脚本 | ✅ **镜像内置 `kmod-veth` / `kmod-sched-bpf` / `kmod-nf-conntrack`，`sing-box 1.15.0-alpha.13` 直接编进镜像**；NFQUEUE 侧 `kmod-nft-queue` 以**独立 apk** 下发，`kmod-nfnetlink-queue` 则由镜像内 `release.config` 的 `kmod-ipt-nfqueue=y` 依赖带入（r41 镜像实测已含）；`honk 0.1.0-beta.6`（`honk` + `luci-app-honk` + 中文 i18n，`honk-core` 由 `honk-install` 运行时装）同样以**独立 apk** 交付，**原生 TUN 与 eBPF 双路透明网关按需启用** |
| **现代化 CI/CD 流水线** | ⚠️ 基础单任务无编译器指纹匹配，依赖易超时，编译动辄 2~4 小时且网络波动易断流 | ✅ **Ubuntu 24.04 + CCACHE 编译器指纹匹配**，5GB 增量编译缓存与多镜像测速回退，**构建大幅缩短至 20~35 分钟，成功率 99%+** |

---

## 🚀 二、本项目独家新功能与深度优化拆解

### 1. 🌟 独家根治：电信 IPTV 1302 鉴权超时与网桥 MAC 表翻转黑洞

#### ① 故障特征与困境
使用电信/联通原装 4K/8K 机顶盒（中兴、华为、创维等）连接单线复用光猫时，常遇到诡异问题：
* **开机正常**：EPG 界面顺利加载，直播频道起初能流畅播放；
* **规律性报错**：观看 5~15 分钟或遥控器切台、点播时，画面突然冻结并报错：**“错误代码: 1302 / 认证失败 / 平台交互超时 / 网络连接异常”**；
* **重启治标不治本**：重启光猫或重新插拔网线后机顶盒又能看几分钟，随后必定准时复现。

#### ② 深度机理解剖：为什么组播流会“吞噬”单播鉴权包？
在典型的运营商 IPTV 网络中，机顶盒与前端交互存在两个逻辑平面：
* **业务平面（单播 VLAN，如 301 / 41）**：负责 DHCP 获取 IPTV 专网 IP、HTTP 鉴权、心跳保活、EPG 导航、时移回看及 VOD 点播（业务口 `ct-iptv-svc`）；
* **组播平面（组播 VLAN，如 302 / 45 / 50）**：负责下行高码率 UDP 组播流及 IGMP 协议（组播口 `ct-iptv-mc`）。

当光猫使用网桥（如 `br-iptv`）将业务口、组播口与机顶盒 LAN 口桥接时，隐藏在以太网二层的冲突爆发：

```
       [ 运营商 BNG / 接入汇聚交换机 ]
        (拥有单一固定的 MAC 地址: BNG_MAC)
               /               \
       业务 VLAN (301)       组播 VLAN (302)
             /                   \
        (单播数据通道)         (仅下行组播流/IGMP)
           /                       \
   +---------------------------------------+
   |          光猫 Linux 网桥 (br-iptv)     |
   |                                       |
   |  ct-iptv-svc            ct-iptv-mc    |
   |  (业务口)                (组播口)      |
   +---------------------------------------+
                      |
                   lan2 / lan3
                      |
              [ 电信 4K 机顶盒 ]
```

1. **上游 BNG 相同 MAC 特征**：运营商机房为了降低设备成本，其 BNG 路由器的单播网关接口与组播分发接口，或者下级二层汇聚交换机，**往往共用完全相同的物理源 MAC 地址 (`BNG_MAC`)**；
2. **Linux 网桥动态学习特性 (MAC Learning)**：Linux 网桥各端口默认开启 `learning=1` 动态 MAC 学习。网桥根据接收到的以太网数据帧源 MAC，自动在内核 FDB（Forwarding Database）转发表中记录“该 MAC 属于哪个端口”；
3. **MAC 表频繁翻转与单播黑洞生成**：
   - 机顶盒开机发起单播鉴权请求，BNG 单播回复从 `ct-iptv-svc` 到达，网桥 FDB 记录：`BNG_MAC -> ct-iptv-svc`，鉴权成功，开始播台；
   - 随后，高码率组播流（或 IGMP 周期查询）从组播口 `ct-iptv-mc` 持续涌入，其数据帧源 MAC 恰好也是 `BNG_MAC`；
   - Linux 网桥转发表**瞬间被强行覆盖翻转**：`BNG_MAC -> ct-iptv-mc`！
   - 5~15 分钟后，机顶盒向上游鉴权服务器发送定期的 HTTP 鉴权心跳或租约续期请求，目的 MAC 正是 `BNG_MAC`；
   - 网桥查表发现 `BNG_MAC` 当前在 `ct-iptv-mc`，**毫不犹豫地将机顶盒的单播鉴权心跳包直接丢进了组播口 `ct-iptv-mc`**；
   - **单播静默丢弃黑洞**：运营商在组播 VLAN 上实施了严格的安全策略（仅允许组播下行或特定 IGMP，上行单播无对应路由或被 ACL 阻断）。发往组播口的单播包被机房**无声丢弃（Silent Drop）**；
   - 机顶盒连续多次重发超时，判定网络中断或会话失效，在屏幕上赫然抛出 **Error 1302**！

#### ③ 为什么传统手段无法根治？
* **重启设备**：仅暂时清空了内存中的 FDB 表，只要组播包再次下发，几十毫秒内就会重新被篡改；
* **仅配置端口隔离 (`isolate='1'`)**：`isolate` 只能阻止同一网桥内从属端口之间的直接二层横向转发，无法阻止入站报文更新网桥全局 FDB 转发表；
* **修改 IP / 单播代理**：以太网二层桥接只根据目标 MAC 转发，IP 层设置无法阻止二层错误路由。

#### ④ 本项目独家工程化根治体系 (`03-pon-userspace-iptv-bridge-mac-fix.patch`)

```
[机顶盒发送单播心跳] ---> [br-iptv]
                             |
                   查表: BNG_MAC 固定在 ct-iptv-svc (永久静态条目)
                             |
                  [100% 走业务口 ct-iptv-svc 发送] ===> 鉴权成功 (零丢包!)

[组播口 ct-iptv-mc 收到数据] ---> [learning='0' 彻底关闭学习] ===> 绝不污染 FDB 转发表!
```

本项目研发了 **双重锁定根治体系**：
1. **第一重锁：组播口物理级阻断学习 (`learning='0'`)**：
   在网桥与接口配置中，对组播端口（如 `ct-iptv-mc` / `pon0.50`）与 IGMP 端口永久关闭 MAC 学习：
   ```uci
   set network.luci_iptv_mc_port=bridge-port
   set network.luci_iptv_mc_port.device='ct-iptv-mc'
   set network.luci_iptv_mc_port.learning='0'
   set network.luci_iptv_mc_port.isolate='1'
   ```
   并在运行时通过内核 Sysfs 与 `bridge link` 双重强化：
   ```bash
   bridge link set dev ct-iptv-mc learning off
   echo 0 > /sys/class/net/br-iptv/brif/ct-iptv-mc/learning
   ```
   彻底切断组播流量污染网桥 FDB 转发表的物理链路。
2. **第二重锁：上游 BNG 网关 MAC 动态探测与静态固化 (Static FDB Pinning)**：
   在网络启动与接口就绪时，脚本自动向业务口 `ct-iptv-svc` 探测真实网关 BNG MAC 地址，并直接写入内核网桥转发表**永久静态条目 (master static)**：
   ```bash
   bng_mac="$(bridge fdb show dev ct-iptv-svc 2>/dev/null | awk '/master br-iptv/ && !/permanent/ && !/self/ {print $1; exit}')"
   [ -z "$bng_mac" ] && bng_mac="$(ip neigh show dev ct-iptv-svc 2>/dev/null | awk '/lladdr/ {print $5; exit}')"
   if [ -n "$bng_mac" ]; then
       bridge fdb replace "$bng_mac" dev ct-iptv-svc master static
   fi
   ```
3. **验证指令**：
   ```bash
   # 1. 验证组播口 learning 是否已成功关闭（输出应为 0）
   cat /sys/class/net/br-iptv/brif/ct-iptv-mc/learning

   # 2. 验证 BNG MAC 是否已作为 permanent / static 焊死在 ct-iptv-svc 上
   bridge fdb show dev ct-iptv-svc | grep -E "static|permanent"
   ```

---

### 2. ⚡ 烽火 HG5585F Wi-Fi 6 满血驱动与独家 4 核中断亲和调度机制

* **MT7916D 满血驱动与 NPU 辅助支持**：完整预置 `en7581_MT7916_npu_rv32.bin` 与 `en7581_MT7916_npu_data.bin` 等 NPU 辅助固件，协同主控底层处理。针对当前开源主线 AN7581 与 mt76 尚未打通纯硬件 WED 直转的现状，独创采用四核智能中断亲和架构，彻底破解开源公版“单核软中断被打满、测速被卡在 500~600M”的瓶颈。
* **工厂 EEPROM 校准自动提取**：内置 `/etc/hotplug.d/firmware/10-mt7916-an-eeprom` 与 `/etc/init.d/mt7916-an-eeprom`（在 `kmodloader` 加载驱动前于 `START=08` 执行），开机自动从 UBI `factory` 分区的 `0x1000` 偏移处提取 4KB 射频校准数据，校验 `0x7916` 硬件魔数并无缝提供给驱动。
* **独立 MAC 地址算号机制**：内置 `/lib/preinit/07_an7581_bsp_wifi_mac`，开机预初始化阶段自动从 `factory` 分区读取基准 MAC 并计算 2.4G (`base + 6`) 与 5G (`base + 7`) 独立合法硬件地址。
* **射频功率校准表**：预置 `SingleSKU` 与 `mt7916-sku.dat` / `mt7916-sku-bf.dat` 波束成形数据。
* **Wi-Fi 四核收发线程精准绑核 (`/usr/sbin/pin-wifi-cpus.sh` + `/etc/hotplug.d/net/99-wifi-affinity`)**：
  - 发送线程 `mt76-tx*` 独占绑定至 `CPU3`；
  - 6 个 `napi/phy0-0` 收包线程按 `0,0,0,1,2,2` 均衡分布至 `CPU0 / CPU1 / CPU2`；
  - 有线以太网硬中断精准绑定：`IRQ 17 -> CPU1`、`IRQ 21 -> CPU2`；
  - 实测 HG5585F 5G Wi-Fi iPerf3 5 线程稳定 **1144 Mbps 下行 / 1200 Mbps 上行**（峰值 **1314+ Mbps**），4 核软中断彻底解脱。
* **异步无线扫描防卡死机制**：集成 `rpcd` 异步信道扫描补丁（`133-rpcd-async-scan.patch`），将长耗时的 Wi-Fi 信道扫描任务从主事件循环解耦并放入子进程与延迟请求队列，彻底杜绝在 LuCI 界面点击扫描周围无线 AP 时造成的 Web 控制台无响应与 504 Gateway Timeout。

---

### 3. 🛡️ PON 认证参数与透明代理订阅跨固件升级自动备份还原

* **一键提取与恢复脚本**：内置 `/usr/sbin/backup-fiberhome-pon.sh` 与 `/usr/sbin/restore-fiberhome-pon.sh`，一键提取并校验 `FHTT`、`HG5585FV1.0`、LOID、PON SN 及设备标识。
* **开机自动守护**：首次启动或配置变更时，系统自动维护 `/etc/sysupgrade.conf` 白名单，将 `/etc/config/pon`、`/etc/fiberhome_pon_backup.uci`、Sing-Box/Honk 配置文件与管理脚本永久纳入保护清单。
* **升级零丢失**：后续无论通过 Web 界面还是 SSH 命令行执行 `sysupgrade`，原有的运营商认证信息与透明代理规则均完整保留，告别刷机后断网变砖。

---

### 4. 🔍 特殊局端 OLT（华为/中兴）认证兼容性增强

* **达发 EN7572 激光冷启动防抖与闭锁保护**：集成 8 次连续硬件采样确认（140ms 稳定期），彻底修复光猫冷启动上电瞬间激光器未完全出光而偶发误报 `SYS_TX_READY` 导致被局端 OLT 秒踢下线的顽疾。
* **LOID 补零方向可调**：支持在 Web 界面自由选择 24 字节 LOID 的填充方向（左对齐 / 右对齐），完美解决部分省份华为 OLT 因 0x00 填充位置不同而报 `reason=0x01` 认证失败的问题。
* **链路原始报文字节 (Wire Bytes) 可视化**：在 LuCI 状态页直接展示上报给局端光纤的 16 进制原始报文及 ASCII 字符（含 `CTC ONU SN (0xC7/0x0001)` 与实际发送的 `LOID`），免去抓包痛苦。
* **Web 界面一键覆盖 PON MAC**：支持在页面直接克隆旧光猫的 PON MAC 地址，用于通过局端 MAC 绑定校验。

---

### 5. 🚀 QWRT 16MB 网络核心缓冲区、16384 netdev 队列与页面防碎片分配

* **16MB TCP/UDP 套接字大缓冲区**：
  统一对齐 `net.core.rmem_max=16777216`、`net.core.wmem_max=16777216`、`net.ipv4.tcp_rmem` 与 `net.ipv4.tcp_wmem`，消除万兆大带宽长肥管道瓶颈与突发丢包。
* **高通量网络队列扩容**：
  `netdev_max_backlog=16384`、`netdev_budget=600`、`dev_weight=128`，单次软中断轮询处理预算提升至 600 个包，极速释放 QDMA 环形缓冲区，彻底杜绝 P2P 与多设备突发流量下的 CPU CDM1 交换队列瞬时丢包。
* **内存防碎片调度优化**：
  移植 QWRT 核心参数 `vm.percpu_pagelist_high_fraction = 128`，深度优化单核 page 列表阈值，彻底杜绝 4 核并发高吞吐下的物理内存碎片与分配延迟。
* **SSDP / WSD NOTRACK 免连接跟踪**：
  预置 SSDP (`239.255.255.250:1900`) 与 Windows WSD (`3702`) 全链路 `NOTRACK` 规则，广播包彻底绕过 conntrack 表与交换芯片队列，避免连接跟踪表被广播风暴撑爆。
* **达发 AN7581 PPE 硬件流卸载 IPv4+IPv6 双栈全线速直转与 UI 可选配置**：
  默认全开启 `flow_offloading='1'` 与 `flow_offloading_hw='1'`。集成独家内核补丁 `931-net-airoha-fix-wan-ipv6-pppoe-flow-offload.patch`，彻底解决达发 AN7581 硬件流卸载长期存在的 3 大隐蔽缺陷（L3 IPv6 路由误绑定 L2 subflow 覆写 PPPoE ID、NPU stats 重写导致硬件流水线死锁、1518 字节 MTU 越界硬件丢包）；在 LuCI Web「网络 - 防火墙 - 常规设置」中预置流卸载选择项（无 / 软件流卸载 / 硬件流卸载），用户可随心切换；实现 IPv4 与 IPv6 均由 PPE 芯片硬件卸载加速，千兆双栈线速转发 CPU 占用低至 ~4%，夸克 App、阿里 CDN 与各类网盘秒级满速响应；同时保持 `packet_steering='0'` 避免 Wi-Fi 4 核绑定被冲刷。
* **第一性原理纯净加解密流水线**：
  遵循 ImmortalWrt 官方最新实践 (`da63f7d`)，彻底剔除 `kmod-crypto-hw-eip93` 协处理器负优化，消除小包 DMA 刷脏与硬中断颠簸；WireGuard (ChaCha20-Poly1305) 与 Sing-Box 纯 Go-assembly NEON 直算，延迟更低、吞吐更稳。

---

### 6. 📺 开箱即用 br-iptv 异 VLAN 端口隔离桥接与 rtp2httpd (4022) 双栈组播转单播

* **异 VLAN 隔离网桥 `br-iptv`**：预置 `pon0.45`（IGMP 加组）+ `pon0.50`（组播视频流），启用原生 `bridge-port isolate='1'` 与 `learning='0'`，兼顾双向收发并完全杜绝二层环路反射。
* **新一代 C 语言代理 `rtp2httpd`**：
  - 纯端口号 `listen='4022'` 监听，同时支持 IPv4/IPv6 双栈；
  - 启用 4 Worker `SO_REUSEPORT` 多核并发、16384 零拷贝缓冲池与 2MB UDP 接收缓存；
  - 自带 Web 状态监控面板 (`:4022/status`) 与现代 Web 播放器 (`:4022/player`)。
* **全平台免配置订阅**：内置广东深圳电信全分类 `/www/iptv.m3u`，通过 `95-iptv-m3u-ip` 脚本随路由器 LAN IP 自动同步。

---

### 7. ⚙️ 现代化 CI/CD 构建流水线 (吸收 1018ji/build-ponwrt-daily 精华)

* **Ccache 编译器指纹持久化机制**：
  配置 `CCACHE_COMPILERCHECK: '%compiler% -dumpmachine; %compiler% -dumpversion'`，严格锁定交叉编译器的 target machine 与真实版本号指纹，杜绝不同 Runner 之间微小时间戳差异导致的 ccache 命中失效。
* **5GB 增量编译高速缓存复用**：
  设定 `CCACHE_MAXSIZE: 5G`，结合 `actions/cache/restore@v4` 与 `actions/cache/save@v4` 对 `.ccache` 目录实现精准跨 Commit 复用，使二次构建命中率提升至 80%~95%，编译时长由 2~3 小时锐减至 20~35 分钟。
* **DL 共享依赖缓存池**：
  对 `dl/` 依赖下载目录进行深度缓存，并基于 `feeds.conf.default` 与 `configs/*.config` 动态计算 Key，规避境外源网络拉取失败。
* **Ubuntu 24.04 镜像源动态探活与测速回退**：
  构建启动时自动探测 Kernel.org、US Archive、Rackspace、Princeton、Ubuntu Archive、Azure 等多组权威镜像站，以并发毫秒级探活选取最快存活源自动改写 `sources.list`，彻底终结 GitHub Actions 偶发 APT 更新超时报错。
* **yq 现代化 YAML/JSON 处理工具链集成**：
  原生集成 `yq` 工具，无缝支持 IPTV 业务配置文件、Honk/Sing-box 订阅复杂语法的动态改写与自动化转换。

---

## 📦 固件下载 (Releases)

请前往 [GitHub Releases](https://github.com/ufo1cn/ponwrt-ZN504-HG5585F/releases) 获取实机验收过的固件。一次 `fw-all` 构建产出**五台机型**的产物，每个 Release 共 32 个资产：10 个镜像（5 台 × `squashfs-sysupgrade` + `initramfs-recovery`）及其 10 个 `.sha256`、4 份 `manifest-*.json` 及其 4 个 `.sha256`（`ct` 与 `ct-usb-sfp` 共用一份 manifest）、`config-all.txt` 与 `build-info.txt` 各带一个 `.sha256`。

| 机型 | 镜像名前缀 | 适用场景 |
| :--- | :--- | :--- |
| 兆能 ZN504XG-D | `ponwrt-airoha-an7581-znxt_zn504xg-d-` | `*-squashfs-sysupgrade.itb` 平滑升级（保留配置）；`*-initramfs-recovery.itb` U-Boot Web 恢复 |
| 烽火 HG5382A | `ponwrt-airoha-an7581-fiberhome_hg5382a-` | 同上（plain 基线） |
| 烽火 HG5585F 电信版 | `ponwrt-airoha-an7581-fiberhome_hg5585f-ct-` | 同上（USB + Wi-Fi + BT） |
| 烽火 HG5585F 电信版（USB/SFP） | `ponwrt-airoha-an7581-fiberhome_hg5585f-ct-usb-sfp-` | 同上（含 `usb_pcs`；`kmod-phy-maxlinear` 五机型默认装） |
| 诺基亚 XG-040G-MD UBI | `ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-` | 同上（USB + BT） |

版本标签规则 `v<日期>-<时间>-<label>-r<run>`。固件入口统一在 master 的 `fw-all.yml`，派发时可选 `targets`（`all`=主线+WED，默认；`mainline`=仅主线五台；`wed`=仅 WED 两台）与 `devices`（`all` 或空格/逗号分隔的 board，按分支能力自动取交集）。主线走 `label=all`、源码树 `master`；WED 走 `label=wed`（只有 HG5585F CT / CT-USB-SFP）、源码树 `feat/wed-npu-offload-6.18`（由 `fw-build` 的 `source_ref` 指定 checkout ref），产物同样发 `v<日期>-<时间>-wed-r<run>` 与 `kmods-wed-r<run>`，其 kmod 只能进 `repo-wed`。wed 分支不再保留自己的 `fw-all.yml`，编 WED 就用 master 这个入口、`targets=wed`。kmod 与独立软件包另发预发布：`kmods-all-r<run>`、`pkgs-extra-<device>-r<run>`。

> WED 分支维护口径：`feat/wed-npu-offload-6.18` 与 `master` 完全同步，只额外保留 WED/NPU 相关补丁、`an7581-npu-mt7916.dtsi` 与 `an7581-fiberhome-hg5585f-common.dtsi` 里那一行 include（不再保留自己的 `fw-all.yml`）。开关是本分支显式开的：`an7581/config-6.18` 打开 `CONFIG_NET_VENDOR_MEDIATEK=y` + `CONFIG_NET_MEDIATEK_SOC_WED=y`；`mt76/Makefile` 在 `CONFIG_TARGET_airoha` 下给 `kmod-mt7915e` 传 `CONFIG_MT7915_NPU=y` + `-DCONFIG_MT7915_NPU`（这个符号全树没有 Kconfig，只能走 make 变量）。历史上的 `wed-r39` 固件只带 NPU RX（`954`），TX 侧 WED 因开关未开没有进内核。

---

## 🧩 独立软件包与 apk 仓库

固件镜像只装「机型能力 + 基线」包，应用类软件一律以 apk 形式另发，装不装由用户决定：

- **内核 kmod**：与固件同树同配置编译，发布在 `kmods-all-r<run>`（578 个 apk + `public-key.pem` 及其 `.sha256`），vermagic 与镜像一致。
- **kmod 生命周期**：kmod 的 `kernel=<内核版本>~<内核 config 指纹>-r<rev>` 与固件内核 config 绑定。`pkg-publish` 收到 `groups=kmods`（或 `all`）时，先删掉仓库 `ponwrt-k<内核版本>/` 下该批的全部旧 `kmod-*.apk` 再写入本次产物，索引按仓库真实存在的目录重建——所以换了内核 config 后不适用的旧 kmod 不会残留在软件仓（固件 Release 里的 `kmods-*-r<run>` 归档不受影响，可回溯）。
- **独立应用包**：`pkgs-extra-<device>-r<run>`，含 OpenClash、SQM 全套（`sqm-scripts` / `luci-app-sqm` / `luci-i18n-sqm-zh-cn` / `tc-tiny` / `nftables-json`）、`bash`、`ruby` + `ruby-yaml`、`unzip`、`honk` + `luci-app-honk` + `luci-i18n-honk-zh-cn`、passwall2 依赖链（`lyaml` / `libyaml` / `libuci-lua`）等。
- **在线源**：`ufo1cn/ponwrt-apk-repo`，索引分支 `repo`（主线五台，只收 `label=all` 产物）；WED 分支固件用 `repo-wed`（默认收 `label=wed` 的固件与 kmod；`pkg-publish` 的 `fw_labels` 可显式改，例如在 master 上一次写 `all,wed` 把两分支产物都发出去，与默认值不同只告警不失败）。发布入口不再锁源分支：`fw-publish` / `pkg-publish` 都可以从 `master` 触发，`fw-publish` 用 `src_branch` 指定源分支（留空按 `idx_branch` 推断，`repo-wed` 默认 `feat/wed-npu-offload-6.18`）。目录 `aarch64_cortex-a53/ponwrt-k<内核版本>/<common|usb|wifi|bt>/`；镜像首次启动按机型能力自动生成 `/etc/apk/repositories.d/90-ponwrt-apk-repo.list`。固件更新索引 `meta/fw/<device>.json` 也在同一分支：构建时按 `apk_repo_branch` 把 `luci-app-ponwrt-update` 的 `index_base` 改写成 `.../<分支>/meta/fw`，所以主线固件只读 `repo`、WED 固件只读 `repo-wed`。
- **签名**：全仓库共用同一把固定私钥，公钥指纹 `d557dca1a8b8d30b48f7e4b910908342789d389a52db3d7225c6b72840eda4ed`，构建流与发布流都会断言。

`honk` 与 `luci-app-honk` **不预装进任何机型镜像**（`honk` 走 tc-bpf，`bpftool` / `tar` 为「有就带」条件依赖，避免 kconfig 把整包隐藏），按需安装：

```sh
apk update
apk add honk luci-app-honk
```

---

## 🛠️ 刷机与升级指南

> [!IMPORTANT]
> **关于光猫认证参数保护（特别提醒）**：
> 接入运营商网络通常使用的是**克隆的原电信烽火（FiberHome / FHTT）光猫认证参数**（包含 `vendor_id='FHTT'`、`hardware_version='HG5585FV1.0'`、LOID 与 SN）。
> 升级前**切勿清空配置恢复出厂**，应直接使用保留配置升级，或在终端执行 `/usr/sbin/backup-fiberhome-pon.sh` 生成认证备份！

### 方式一：SSH 命令行保留配置安全升级（强烈推荐）

在已有系统的设备上升级，可完整保留光猫认证信息（SN、LOID、VLAN 41）与宽带账号密码：

```bash
# 1. 将 sysupgrade 固件上传至光猫的 /tmp 目录
scp -O <firmware-name>-squashfs-sysupgrade.itb root@192.168.1.1:/tmp/sysupgrade.bin

# 2. SSH 登录并校验固件完整性
ssh root@192.168.1.1 "sysupgrade -T /tmp/sysupgrade.bin"

# 3. 执行保留配置刷入（切勿使用 -n 参数，否则会清除所有参数）
ssh root@192.168.1.1 "sysupgrade -v -c /tmp/sysupgrade.bin"
```

等待设备自动刷写并重启（通常约 1~2 分钟），即可无缝恢复拨号并上线。

### 方式二：LuCI Web 升级

1. 登录 LuCI 管理后台（默认 `http://192.168.1.1`）；
2. 进入 **系统 (System) -> 备份/升级 (Backup / Flash Firmware)**；
3. 选择对应的 `squashfs-sysupgrade.itb` 镜像；
4. 勾选 **“保留配置 (Keep settings)”** 后点击上传并确认刷写。

### 方式三：U-Boot Web 恢复刷机

若因误操作导致系统无法启动：
1. 断开电源，按住机身背部 **Reset 键** 并重新插电；
2. 保持按住约 8~10 秒，待指示灯闪烁后松开；
3. 电脑网线直连 LAN 口，设置电脑静态 IP 为 `192.168.1.2` / `255.255.255.0`；
4. 浏览器访问 `http://192.168.1.1` 进入 U-Boot Web 界面；
5. 上传对应的 `initramfs-recovery.itb` 镜像刷入恢复。

---

## 📖 兆能 ZN504XG-D PON 上线与 OLT 注册通关指南 (含踩坑实录)

将**兆能 ZN504XG-D**（达发 Airoha AN7581）替换电信原装光猫（如华为 HS8145X6、烽火 HG5585F 等）并直连光纤上线，是发挥这台光猫 2.5G 性能的核心场景。

许多机友在换猫时常遇到**“状态在 O1~O5 反复跌落”、“光猫注册瞬时断开”、“PPPoE 无法获取报文”**等难题。以下整理自实机反复抓包与验证的完整通关配置与避坑血泪总结。

### 1. 换猫前必须提取的“原光猫 4 要素”

在拔下原运营商光猫前，务必登录原光猫后台或拍照记录以下核心参数：

| 参数项 | 说明 | 示例 (以电信原猫为例) |
| :--- | :--- | :--- |
| **PON SN (序列号)** | 原光猫机身背部标签或后台显示的 PON 序列号（前 4 位通常为厂商代码，后 8 位为十六进制） | `48575443XXXXXXXX` (`HWTC` 华为) 或 `FHTTXXXXXXXX` |
| **宽带 LOID** | 电信逻辑 ID (逻辑识别码)，部分地区装维工单上称为“宽带识别码/逻辑认证码” | 手机号或 `SZ10000XXXXXX` (若有密码一并记录，无密码留空) |
| **设备厂商与型号** | 原光猫设备型号代码与硬件版本号 | 厂商: `HWTC` 或 `FHTT`，型号: `HS8145X6` 或 `HG5585FV1.0` |
| **上网 VLAN ID** | 原光猫网络配置中“Internet”业务绑定的 VLAN Tag（关键！） | 深圳电信常用 `41`，部分地区为 `43` 或 `46`，组播通常为 `45` |
| **宽带账号与密码** | PPPoE 拨号账号与密码 | `0755XXXXXXXX@163.gd` |

---

### 2. ZN504 Web 界面与配置文件对照

登录 ZN504 后台（默认 `http://192.168.1.1`），进入 **网络 (Network) -> PON 设置 (PON Configuration)**：

#### ① 基础线路配置 (Line 0)
- **物理接口 (Device)**: `pon0`
- **链路制式 (Mode)**: **`xgpon`**（绝大多数电信 10G 光纤为 XG-PON；若是千兆 GPON 则选 `gpon`，若是联通/移动 10G-EPON 则选 `epon`）
- **PON 序列号 (Serial Number)**: 填入原光猫的完整 16 位 SN（如 `48575443XXXXXXXX`）

#### ② OMCI 协议认证参数 (Line 0 OMCI)
- **厂商代码 (Vendor ID)**: **`FHTT`**（⚠️ 见后文核心避坑 1，即使原猫是华为也强烈推荐填 `FHTT`）
- **设备标识 (Equipment ID)**: **`HS8145X6 (PON ONT)`**（⚠️ 见后文核心避坑 2，必须带括号）
- **硬件版本 (Hardware Version)**: `HG5585FV1.0`
- **软件版本 (Software Version)**: `RP0100`
- **宽带识别码 (LOID)**: 填入你的真实电信 LOID（如 `SZXXXXXXXXX`）
- **运营商标识 (Operator ID)**: `CTC`（中国电信）

#### 配置文件底层对应 (`/etc/config/pon`)：
```uci
config xpon 'line0'
	option device 'pon0'
	option serial_number '48575443XXXXXXXX'
	option mode 'xgpon'

config omci 'line0_omci'
	option line 'line0'
	option device 'omci0'
	option omcc_version '0x86'
	option vendor_id 'FHTT'
	option equipment_id 'HS8145X6 (PON ONT)'
	option hardware_version 'HG5585FV1.0'
	option software_version 'RP0100'
	option loid 'SZXXXXXXXXXXXXX'
	option operator_id 'CTC'
```

---

### 3. ⚠️ 核心避坑实录（高频翻车点详解）

#### 🛑 避坑一：局端 OLT 是华为时，千万不要把 Vendor ID 填成 `HWTC`！
* **翻车现象**：许多机友认为“原猫是华为，我肯定要一模一样填 `HWTC`”。结果光猫能瞬时冲到 O5 状态，但在 **100 毫秒内就会被局端断开**（内核报 `Deactivate_ONU-ID`），在 `O1 -> O2 -> O4 -> O5 -> O2` 之间死循环跌落掉线。
* **技术真相（抓包逆向）**：
  局端华为 OLT 面对上报为“华为自家设备（`HWTC`）”的光猫时，会触发极其严苛的**华为闭源私有校验（连续下发 ME Class 350 分区指纹与 Class 373 硬件校验）**。开源 PonWrt 并不包含华为闭源系统的专有应答，华为 OLT 校验失败后立刻判定该设备为“非法假冒华为光猫”，随即发送指令强行断开。
* **破局妙招（降维兼容）**：
  运营商机房的华为 OLT 必须兼容全网第三方设备。将 `vendor_id` 填为 **`FHTT`（烽火）** 时，华为 OLT 会判定接入的是第三方设备，**自动关闭华为专属私有探测，退回到标准中国电信 CTC / ITU-T G.988 开放规范**，直接通过 LOID 顺利认证并下发数据通道！

#### 🛑 避坑二：设备标识 (Equipment ID) 必须带有完整后缀 `(PON ONT)`
* **翻车现象**：只填 `HS8145X6` 或只填 `HG5585F`，光纤握手成功但机房始终不下发 GEM Port 业务通道。
* **解决办法**：机房 ITMS / OLT 数据库中录入的设备全称格式是 **`HS8145X6 (PON ONT)`**（注意带空格和半角括号），完整填写后机房才会匹配对应的业务模板下发 VLAN。

#### 🛑 避坑三：PPPoE 拨号必须绑定 VLAN 接口，切勿直接绑 `pon0`
* **翻车现象**：光路已经顺利进入稳定 O5，但创建的 WAN 拨号永远发 PADI 超时无响应。
* **技术真相**：电信光纤宽带在 OLT 端全部划分了业务 VLAN。上网业务不是运行在纯二层物理网卡 `pon0` 上的，而是承载在对应 VLAN 的虚拟子接口上。
* **正确操作**：在 **网络 -> 接口** 中，将 WAN 的物理设备指定为 **`pon0.41`**（若当地上网 VLAN 是 41），或者在设备列表中创建名为 `pon0.41` 的 802.1q VLAN 接口再进行 PPPoE 拨号。

#### 🛑 避坑四：原光猫会话锁定（BRAS 28103012 错误）
* **翻车现象**：PPPoE 握手成功但鉴权失败，日志报错：
  > `Remote message: 28103012: check user-name in black list. failed! / PAP authentication failed`
* **技术真相**：原光猫未点击“断开连接”直接拔掉光纤，电信机房 BRAS 的在线会话（Session）未超时释放，认为该账号存在双拨行为触发风控拉黑。
* **解决办法**：换猫前建议在老光猫后台点击“断开网络”；若已拔掉，只需静置拔光纤状态等待 3~5 分钟，让电信机房自动释放旧会话即可恢复拨号。

#### 🛑 避坑五：固件升级导致 `/etc/config/pon` 丢失变砖
* **翻车现象**：好不容易调通上线，后续更新系统时一旦刷写清除了配置，开机直接失联。
* **解决方案**：本项目固件已深度内置保护脚本，终端执行一次：
  ```bash
  /usr/sbin/backup-fiberhome-pon.sh
  ```
  该脚本会自动备份参数至 `/etc/fiberhome_pon_backup.uci` 并永久写入 `/etc/sysupgrade.conf` 白名单。升级后若遇异常，执行 `/usr/sbin/restore-fiberhome-pon.sh` 秒级回滚恢复。

---

### 4. 链路诊断与成功标志（如何确认已完美 O5）

在终端执行以下指令可快速验证光纤注册全貌：

```bash
# 查看 PON 守护进程状态
pondctl status --line line0
```

**✅ 完美成功输出标志**：
```json
{
  "channel_available": true,
  "loid_configured": true,
  "authentication_status": 1,
  "authentication_meaning": "accepted",
  "olt_vendor_id": "HWTC",
  "backend_state": "applied",
  "vlan_ids": [1, 41, 45]
}
```
* `authentication_meaning`: 显示 **`"accepted"`** 表示认证通过；
* `backend_state`: 显示 **`"applied"`** 表示电信机房已成功下发通道；
* `vlan_ids`: 列表中包含 **`41`**（上网）和 **`45`**（IPTV）等 VLAN，说明光猫已具备完整通网能力！

---

## 📱 三、客户端 IPTV 订阅链接与管理入口（开箱即用）

在同一局域网内的电视盒子（APTV / TiviMate / Kodi / 电视家类自定义壳）、电脑（PotPlayer / VLC / IINA）或手机浏览器中，可直接填入以下地址（若改过路由器 LAN IP，请把 `192.168.1.1` 替换为你的网关 IP）：

* **推荐订阅链接（`rtp2httpd` 动态列表，自动生成可播放单播地址）**：  
  `http://192.168.1.1:4022/playlist.m3u`
* **静态内置订阅链接（网关 uHTTPd 托管的 `/www/iptv.m3u`，已由热插拔脚本自动同步网关 IP）**：  
  `http://192.168.1.1/iptv.m3u`
* **Web 状态监控面板**（实时查看在线客户端、码率、FCC/组播状态）：  
  `http://192.168.1.1:4022/status`
* **免装软件网页直接看电视**（内置现代 Web 播放器，自动解析 M3U 频道列表）：  
  `http://192.168.1.1:4022/player`
* **单频道兼容格式**（完全兼容传统 `udpxy` / `msd_lite` 路径）：  
  `http://192.168.1.1:4022/rtp/239.77.0.174:5146`

---

## 🚀 四、Sing-Box 原生 `auto-redirect` 配置规范

固件内置的 `nfnetlink_queue` 驱动可直接支持 Sing-Box 的原生透明重定向。依照 [Sing-Box 官方规范](https://deepwiki.com/SagerNet/sing-box)，`auto_redirect` 必须配合 `auto_route: true` 运行：

```json
{
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "address": [
        "172.19.0.1/30"
      ],
      "auto_route": true,
      "strict_route": false,
      "auto_redirect": true
    }
  ]
}
```

启动后执行 `sing-box run`，即可看到：
```text
INFO[0000] inbound/tun[tun-in]: started at tun0
INFO[0001] inbound/tun[tun-in]: inbound redirect connection from 192.168.1.xxx:xxxxx
```
流量无需额外配置复杂的 nftables 规则即可全自动完成分流与代理！

---

## 🏗️ 五、源码编译指南

### 1. 准备环境
推荐在 Ubuntu 22.04 / 24.04 LTS 环境下进行：
```bash
sudo bash -c 'bash <(curl -s https://build-scripts.immortalwrt.org/init_build_environment.sh)'
```

### 2. 克隆代码与更新 Feeds
```bash
git clone https://github.com/ufo1cn/ponwrt-ZN504-HG5585F.git
cd ponwrt-ZN504

./scripts/feeds update -a
./scripts/feeds install -a
bash ./scripts/customize.sh
```

### 3. 应用 AN7581 增强配置
```bash
./scripts/kconfig.pl + configs/an7581.config configs/release.config > .config
make defconfig
```

### 4. 开始多线程编译
```bash
make download -j$(nproc)
make -j$(nproc) || make -j1 || make -j1 V=s
```

固件输出目录：`bin/targets/airoha/an7581/`

---

## ⚠️ 六、免责声明

1. 本项目为开源固件项目，旨在用于技术交流与网络设备功能研究。
2. 刷写第三方固件具有一定风险，操作前请务必使用 `backup-fiberhome-pon.sh` 备份好克隆的烽火 PON 认证数据（LOID、SN、Vendor ID）与宽带认证信息。
3. 请严格遵守当地电信运营商的相关管理规定，严禁用于任何非法网络活动。

---

## 🙏 七、引用致谢 (Acknowledgements & Credits)

本项目凝聚了开源社区众多前驱开发者与项目的智慧结晶，特此对以下项目及贡献者表达诚挚感谢与崇高敬意：

- **[pbs05/ponwrt](https://github.com/pbs05/ponwrt)**：PonWrt 创始人，奠定达发 Airoha AN7581 / AN7583 PON 光猫开源架构与驱动的坚实底座，本项目核心源码基石。
- **[1018ji/build-ponwrt-daily](https://github.com/1018ji/build-ponwrt-daily)**：现代化 CI 构建流水线开创者，提供基于编译器版本指纹的 Ccache 高速缓存持久化（`CCACHE_COMPILERCHECK`）、5GB 增量缓存复用与镜像源动态测速回退的架构灵感。
- **[LeoooChen/PonWRT-TYFZA1](https://github.com/LeoooChen/PonWRT-TYFZA1)**：硬件流量转发与 16MB 环形缓冲区调优先驱，贡献 XG-PON 线路与 PPPoE 线速流量硬件卸载（4.5% 超低 CPU 占用）实践及 `rpcd` 异步无线扫描防卡死机制。
- **[Kahen/PonWrt-CI-UBI](https://github.com/Kahen/PonWrt-CI-UBI)**：提供 AN7581 SoC 精确温度遥测方案 (`temperature-rpc.uc` 与 LuCI RPC 联动) 及 MTD 读写保护 (`kmod-mtd-rw`)。
- **[ImmortalWrt](https://github.com/immortalwrt/immortalwrt) & QWRT 项目团队**：为 Linux 网络内核调优、EIP-93 硬件协处理器剔除性能倒挂实践、PPE 硬件流表加速与网络调优提供深度参考与优秀范例。
- **[NNdroid](https://github.com/NNdroid)**：提供 EN7572 激光冷启动防抖确认补丁、LOID 填充方向调节及 CTC 原始报文分析回显工具链。
- **[OpenWrt Project](https://github.com/openwrt/openwrt)**：为全球网络设备提供坚实、可扩展的嵌入式 Linux 操作系统底座。
- **[stackia/rtp2httpd](https://github.com/stackia/rtp2httpd)**：高性能零拷贝 4K/8K IPTV 组播转单播、FCC 快速切台与 RTSP 代理引擎，附带现代 Web 播放器与状态监控面板。
- **[SagerNet/sing-box](https://github.com/SagerNet/sing-box)**：新一代高性能网络代理核心。
- **[daeuniverse/honk](https://github.com/daeuniverse/honk)** 与 **[daeuniverse/openwrt-packages](https://github.com/daeuniverse/openwrt-packages)**：高性能 Linux eBPF 零拷贝透明代理引擎与 LuCI Web 控制面板。
- **[rchen14b/luci-app-airoha-npu](https://github.com/rchen14b/luci-app-airoha-npu)**：达发 AN7581 独立 8 核 RISC-V NPU / PPE 运行状态与硬件流表监控看板。
- **[VizzleTF/luci-theme-footstrap](https://github.com/VizzleTF/luci-theme-footstrap)**：专为 PonWrt 适配的清爽现代响应式主题。
- **[oenhu](https://github.com/oenhu)**：贡献 PR #116 优化，避免 DHCP 网络冗余生成 `wan6` 接口引起的路由竞争。
