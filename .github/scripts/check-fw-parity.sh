#!/usr/bin/env bash
# 固件基线硬比对（包流程专用）
# ------------------------------------------------------------------------------
# 目的：包流程（incremental / legacy / extra）与固件共用同一份内核源码树，但各自的
#       .config 选择不同。凡是不影响内核 .config 的差异对用户态包无害；凡是影响内核
#       ABI 的差异（内核版本、target config、机型 config、release config、源码 commit）
#       都必须与最近一次成功固件完全一致，否则产物在设备上不可用。
#
# 比对基准：ponwrt-apk-repo/meta/firmware.json（fw-build 每次成功构建覆盖）。
#   字段：ponwrt_commit / kernel_version / config_an7581_sha256 /
#         config_release_sha256 / config_6_18_sha256 / kernel_config_hash
#
# 判定：
#   1) 取不到基线 → 直接失败（没有基线就无法保证同源，不允许“只告警”）
#   2) 本 run 没编内核树 → 直接失败（没有 kernel.release 无法核对）
#   3) 内核版本 / 三个 config 文件 sha256 不一致 → 直接失败
#   4) 本树 commit 与固件基线 commit 不一致（且本次确实对齐过）→ 直接失败
#   5) 内核配置指纹（kernel_config_hash）不一致：
#        · 本 run 产出了 kmod apk → 直接失败（这些 kmod 装不到固件上）
#        · 未产出 kmod → 记录为预期差异（本流程只编用户态，kmod 一律用固件产物）
# ------------------------------------------------------------------------------
set -uo pipefail

FW_URL="https://raw.githubusercontent.com/ufo1cn/ponwrt-apk-repo/repo/meta/firmware.json"
fail=0
ok()  { echo ">>> $*"; }
bad() { echo "::error::$*"; fail=1; }

if ! curl -fsSL --max-time 40 "$FW_URL" -o /tmp/fwmeta.json; then
  echo "::error::取不到固件基线 meta/firmware.json —— 没有基线就无法保证与固件同源，中止"
  exit 1
fi

python3 - <<'PY' > /tmp/fwbase.env
import json
d = json.load(open('/tmp/fwmeta.json', encoding='utf-8'))
for k in ('ponwrt_commit', 'kernel_version', 'config_an7581_sha256',
          'config_release_sha256', 'config_6_18_sha256', 'kernel_config_hash',
          'feature_class', 'devices', 'kmod_vermagic'):
    print('%s=%r' % (k.upper(), d.get(k) or ''))
PY
# shellcheck disable=SC1091
. /tmp/fwbase.env

ok "固件基线：label=${FEATURE_CLASS:-?} commit=${PONWRT_COMMIT:-?} kernel=${KERNEL_VERSION:-?} devices=${DEVICES:-?}"

kver=$(cat build_dir/target-*/linux-*/include/config/kernel.release 2>/dev/null | head -n1 || true)
if [ -z "$kver" ]; then
  bad "本 run 没有内核树（with_kernel=false），拿不到 kernel.release —— 无法核对内核 ABI，产物不保证可安装"
else
  if [ -z "${KERNEL_VERSION:-}" ]; then
    bad "固件基线没有 kernel_version 字段（基线过旧），拒绝放行"
  elif [ "$kver" != "$KERNEL_VERSION" ]; then
    bad "内核版本不一致：固件=${KERNEL_VERSION} / 本树=${kver}"
  else
    ok "内核版本一致：$kver"
  fi
fi

sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
cmp_file() { # $1=名称 $2=路径 $3=基线 sha
  local got; got=$(sha_of "$2")
  if [ -z "$got" ]; then
    bad "$1 缺失：$2"
  elif [ -z "${3:-}" ]; then
    bad "$1 基线未记录（固件基线版本过旧），无法核对 —— 先跑一次固件流程刷新基线"
  elif [ "$got" != "$3" ]; then
    bad "$1 不一致：固件=${3} / 本树=${got}（该文件改过但固件还没重编，先跑固件流程）"
  else
    ok "$1 一致：$got"
  fi
}
cmp_file "target config-6.18" target/linux/airoha/an7581/config-6.18 "${CONFIG_6_18_SHA256:-}"
cmp_file "configs/an7581.config" configs/an7581.config "${CONFIG_AN7581_SHA256:-}"
cmp_file "configs/release.config" configs/release.config "${CONFIG_RELEASE_SHA256:-}"

# 源码 commit：只有在本次确实“对齐到固件 commit”时才硬拦；用本仓 HEAD 的显式覆盖只记录
aligned=$(grep '^aligned_commit=' .ci-source-commit 2>/dev/null | cut -d= -f2 || true)
fwcommit=$(grep '^firmware_commit=' .ci-source-commit 2>/dev/null | cut -d= -f2 || true)
if [ -n "$aligned" ] && [ -n "$fwcommit" ] && [ "$fwcommit" != "none" ]; then
  if [ "$aligned" != "$fwcommit" ]; then
    bad "源码未对齐：本树=${aligned} / 固件=${fwcommit}"
  else
    ok "源码 commit 一致：$aligned"
  fi
else
  ok "本次未做源码对齐（显式用本仓 HEAD），commit 不参与硬拦，只按 config 指纹判定"
fi

khash=$(grep '=[ym]' build_dir/target-*/linux-*/.config.set 2>/dev/null | LC_ALL=C sort | md5sum | awk '{print $1}' || true)
kmcount=$(find bin/packages -type f -name 'kmod-*.apk' 2>/dev/null | wc -l | tr -d ' ')
kmcount=${kmcount:-0}
if [ -n "$khash" ] && [ -n "${KERNEL_CONFIG_HASH:-}" ]; then
  if [ "$khash" = "$KERNEL_CONFIG_HASH" ]; then
    ok "内核配置指纹一致：$khash"
  elif [ "$kmcount" -gt 0 ]; then
    bad "内核配置指纹不一致（固件=${KERNEL_CONFIG_HASH} / 本树=${khash}），但本 run 产出了 ${kmcount} 个 kmod apk —— 这些 kmod 依赖固件指纹，装不上，kmod 只能由固件流程编"
  else
    ok "内核配置指纹与固件不同（固件=${KERNEL_CONFIG_HASH} / 本树=${khash}）：本 run 未产 kmod，属预期差异"
  fi
elif [ "$kmcount" -gt 0 ]; then
  bad "基线与本树都拿不到内核配置指纹，但本 run 产出了 ${kmcount} 个 kmod apk —— 无法证明可安装，拒绝放行"
else
  ok "未取到内核配置指纹（固件基线过旧或本 run 未编内核），kmod 数为 0，跳过该比对"
fi

if [ "$kmcount" -gt 0 ] && [ "$fail" -eq 0 ] && [ -n "$khash" ] && [ "$khash" = "${KERNEL_CONFIG_HASH:-}" ]; then
  ok "本 run 产出 ${kmcount} 个 kmod apk，指纹与固件一致，可随固件使用"
fi

if [ "$fail" -ne 0 ]; then
  echo "::error::固件基线核对失败：本次产物不保证与固件同源，禁止入库/发布"
  exit 1
fi
ok "固件基线核对通过"
