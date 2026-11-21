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

## 归档的两条

1. `build-firmware-manual.yml`
   - 功能被三条入口完全覆盖（单机型编译时它就是把参数透传给同一个 `fw-build.yml`）。
   - 它独有的 `devices=both` 反而违反能力隔离：一个 `.config` 同时编两台机型，`=y`
     的包会同时进两台镜像（例如无无线的 HG5382A 也会带上 `kmod-mt7915e`）。
2. `build-firmware-hg5585f-ct-usb.yml`（"USB 全驱动"）
   - 功能等价于 `fw-usb-wifi.yml` + `bake_usb=true`：`fw-build.yml` 在烘焙模式下会把
     `configs/features/usb.config` 里所有 `=m` 改写成 `=y`，而该片段现在已是旧
     `USB_PKGS` 的超集（旧的 9 个提供者符号 `input-support`、`kmod-rtl8192c-common`、
     `kmod-rtlwifi-usb`、`kmod-rtw88{,-8723d,-8723x,-8821c,-8822c,-usb}` 已补进片段），
     不再有"只在这条工作流里才编得进去"的驱动。

## 怎么恢复

需要临时恢复某条入口时，把对应 yml 从本目录复制回 `.github/workflows/` 并提交即可；
历史 run 与 artifact 一直保留在 Actions 里，不受归档影响。
