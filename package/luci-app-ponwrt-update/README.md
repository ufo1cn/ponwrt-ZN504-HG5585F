# luci-app-ponwrt-update

PonWrt 固件更新的图形界面：`系统 → 固件更新`。

## 做什么

1. 读本机 `/etc/ponwrt-version`（构建时写入的版本戳：机型、能力类别、commit、run）。
2. 拉 `<仓库索引地址>/<机型>.json`（默认指向 `ufo1cn/ponwrt-apk-repo` 的 `repo` 分支 `meta/fw/`），
   用 `run` 比较判断是否有新固件。
3. 有更新时后台下载镜像到 `/tmp/ponwrt-fw/`，用索引里的 `sha256` 校验，页面实时显示进度。
4. 校验通过后调用 `sysupgrade` 刷写（可选 `-n` 不保留配置）。

## 三种出站方式

| 方式 | 行为 | 适用 |
| --- | --- | --- |
| 直连（direct） | `curl --noproxy '*'`，显式绕过任何环境变量里的代理 | 设备本来就能直连 GitHub |
| 使用代理（proxy） | `curl --proxy <地址>`，只作用于本 app 的请求 | mihomo/sing-box 只开了 mixed/http 端口 |
| 透明代理（transparent） | 不传代理参数，靠 TUN 或 nftables redir 接管出站 | 已开 TUN / 透明重定向；LuCI 的 apk 操作也只有这种才能被代理 |

> 说明：`direct` 和 `transparent` 都按直连发请求，区别只在语义——前者代表"真的直连"，
> 后者代表"链路上已经有透明代理，不用再配"。设置里改完立即生效，不需要重启。

## 仓库地址

`仓库索引地址` 是目录形式，实际请求 `<地址>/<机型>.json`。
换成自建镜像（例如 `https://mirror.example.com/ponwrt/meta/fw`）即可，只要索引里的
`sysupgrade.url` 指向你的镜像地址。

## 命令行

```
ponwrt-update status              # 本机版本 + 当前设置
ponwrt-update check               # 检查是否有新固件（同 ponwrt-fw-check）
ponwrt-update download            # 后台下载并按索引 sha256 校验
ponwrt-update apply [--wipe]      # 刷写
```

## 文件

- `root/usr/bin/ponwrt-update`：全部逻辑（CLI + JSON 两种入口）
- `root/usr/bin/ponwrt-fw-check`：`ponwrt-update check` 的薄壳
- `root/usr/libexec/rpcd/luci.ponwrt_update`：LuCI 后端，转发到上面那份脚本
- `root/etc/config/ponwrt_update`：UCI 配置（mode / proxy / index_base）
- `root/etc/profile.d/ponwrt-proxy.sh`：`mode=proxy` 时给交互式 shell 导出代理，便于 `apk update`
