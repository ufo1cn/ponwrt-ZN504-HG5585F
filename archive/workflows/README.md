# 归档的固件构建工作流

这里是从 `.github/workflows/` 移出来的旧入口，**只作备份与追溯，GitHub 不会执行本目录下的文件**。

## 为什么归档

固件编译已经统一到「按机型能力拆分」的三条入口，都调用同一个 reusable 工作流
`.github/workflows/fw-build.yml`：

| 入口 | 机型 | 能力 |
|---|---|---|
| `fw-usb-wifi.yml` | fiberhome_hg5585f-ct | usb + wifi（默认 `bake_usb=true`） |
| `fw-usb.yml` | nokia_xg-040g-md-ubi | usb |
| `fw-plain.yml` | fiberhome_hg5382a | 无 |

能力定义唯一来源是 `configs/device-features.txt`，能力片段在 `configs/features/`。

## 归档清单

### 1. `build-firmware-manual.yml`
- 功能被三条入口完全覆盖（单机型编译时它就是把参数透传给同一个 `fw-build.yml`）。
- 它独有的 `devices=both` 反而违反能力隔离：一个 `.config` 同时编两台机型，`=y`
  的包会同时进两台镜像（例如无无线的 HG5382A 也会带上 `kmod-mt7915e`）。

### 2. `build-firmware-hg5585f-ct-usb.yml`（"USB 全驱动"）
- 功能等价于 `fw-usb-wifi.yml` + `bake_usb=true`：`fw-build.yml` 在烘焙模式下会把
  `configs/features/usb.config` 里所有 `=m` 改写成 `=y`，而该片段现在已是旧
  `USB_PKGS` 的超集（旧的 9 个提供者符号 `input-support`、`kmod-rtl8192c-common`、
  `kmod-rtlwifi-usb`、`kmod-rtw88{,-8723d,-8723x,-8821c,-8822c,-usb}` 已补进片段），
  不再有"只在这条工作流里才编得进去"的驱动。

### 3. `build-zn504.yml`（旧入口，只读）
- 一次编 `ZN504XG-D` + `HG5585F` 两台的老入口，配置合并、设备锁定、产物组织都是
  `fw-build.yml` 的前身；与三条入口并存会让同名产物、缓存 key、Release tag 互相打架。
- **归档后的缺口**：ZN504XG-D 目前没有对应入口。要编这台机型时，把本文件复制回
  `.github/workflows/` 临时用，或在 `fw-build.yml` 的入口里新增一条 label（推荐后者，
  但需先确认它的能力集合与 `device-features.txt` 一致）。

### 4. `release.yml`（旧入口，只读）
- 按手动输入的 `tag` 对 `an7581` / `an7583` 做全量矩阵编译并发布正式 Release，
  属"发正式版"用途，与日常迭代的三条入口重复（后者已经带 Release 上传）。
- 归档后正式发版改由：三条入口编出固件 → `fw-publish.yml` 搬进 apk-repo 并写
  `meta/fw/<device>.json`，需要对外正式 Release 时按 tag 手动建 Release 并挂接产物。

## 怎么恢复

需要临时恢复某条入口时，把对应 yml 从本目录复制回 `.github/workflows/` 并提交即可；
历史 run 与 artifact 一直保留在 Actions 里，不受归档影响。
