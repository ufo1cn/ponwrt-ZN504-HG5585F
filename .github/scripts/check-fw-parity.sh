#!/usr/bin/env bash
# 固件基线核对（包流程专用）
# ------------------------------------------------------------------------------
# 现行架构（用户定调）：包流程只编用户态应用，kmod 一律由固件流程编。
# 因此本脚本的判定分两种情况：
#
#   A) 本 run 产出了 kmod apk（越界行为）——按“必须与固件同源”严格核对，
#      任何一项不一致即失败，因为这些 .ko 一定装不到固件上：
#        · 必须有内核树（没有 kernel.release 就无法证明 ABI）
#        · 内核版本一致
#        · config-6.18 / configs/an7581.config / configs/release.config 三个 sha256 一致
#        · 若本次做过源码对齐，commit 必须等于固件基线 commit
#        · 内核配置指纹（kernel_config_hash）一致
#
#   B) 本 run 没有产 kmod（正常情况）——只记录，不拦：
#      包流程的内核选项本来就不需要与固件一致，只要不产 kmod 就不会有装不上的问题。
#
# 基线：ponwrt-apk-repo/meta/firmware.json（fw-build 每次成功构建覆盖）
# ------------------------------------------------------------------------------
set -uo pipefail

FW_URL="https://raw.githubusercontent.com/ufo1cn/ponwrt-apk-repo/repo/meta/firmware.json"
fail=0
ok()  { echo ">>> $*"; }
bad() { echo "::error::$*"; fail=1; }

if ! curl -fsSL --max-time 40 "$FW_URL" -o /tmp/fwmeta.json; then
  echo "::error::取不到固件基线 meta/firmware.json —— 无法核对产物归属，中止"
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

kmcount=$(find bin/packages -type f -name 'kmod-*.apk' 2>/dev/null | wc -l | tr -d ' ')
kmcount=${kmcount:-0}
kver=$(cat build_dir/target-*/linux-*/include/config/kernel.release 2>/dev/null | head -n1 || true)
ok "固件基线：label=${FEATURE_CLASS:-?} commit=${PONWRT_COMMIT:-?} kernel=${KERNEL_VERSION:-?}；本 run 编出 kmod apk ${kmcount} 个，内核树 $([ -n "$kver" ] && echo "$kver" || echo 无)"

if [ "$kmcount" -eq 0 ]; then
  ok "本 run 未产 kmod（符合“包流程只编应用”的约定），内核选项无需与固件一致，放行"
  exit 0
fi

# ---- 以下为“产出了 kmod”的严格核对 -------------------------------------------
bad "本 run 产出了 ${kmcount} 个 kmod apk —— kmod 只能由固件流程编，包流程产出的 .ko 装不到固件上"

if [ -z "$kver" ]; then
  bad "本 run 没有内核树（with_kernel=false），拿不到 kernel.release —— 无法证明 ABI 与固件一致"
elif [ -z "${KERNEL_VERSION:-}" ]; then
  bad "固件基线没有 kernel_version 字段（基线过旧），拒绝放行"
elif [ "$kver" != "$KERNEL_VERSION" ]; then
  bad "内核版本不一致：固件=${KERNEL_VERSION} / 本树=${kver}"
else
  ok "内核版本一致：$kver"
fi

sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
cmp_file() { # $1=名称 $2=路径 $3=基线 sha
  local got; got=$(sha_of "$2")
  if [ -z "$got" ]; then
    bad "$1 缺失：$2"
  elif [ -z "${3:-}" ]; then
    bad "$1 基线未记录（固件基线过旧），无法核对"
  elif [ "$got" != "$3" ]; then
    bad "$1 不一致：固件=${3} / 本树=${got}（该文件改过但固件还没重编）"
  else
    ok "$1 一致：$got"
  fi
}
cmp_file "target config-6.18" target/linux/airoha/an7581/config-6.18 "${CONFIG_6_18_SHA256:-}"
cmp_file "configs/an7581.config" configs/an7581.config "${CONFIG_AN7581_SHA256:-}"
cmp_file "configs/release.config" configs/release.config "${CONFIG_RELEASE_SHA256:-}"

aligned=$(grep '^aligned_commit=' .ci-source-commit 2>/dev/null | cut -d= -f2 || true)
fwcommit=$(grep '^firmware_commit=' .ci-source-commit 2>/dev/null | cut -d= -f2 || true)
if [ -n "$aligned" ] && [ -n "$fwcommit" ] && [ "$fwcommit" != "none" ]; then
  if [ "$aligned" != "$fwcommit" ]; then
    bad "源码未对齐：本树=${aligned} / 固件=${fwcommit}"
  else
    ok "源码 commit 一致：$aligned"
  fi
else
  ok "本次未做源码对齐，commit 只记录不拦"
fi

khash=$(grep '=[ym]' build_dir/target-*/linux-*/.config.set 2>/dev/null | LC_ALL=C sort | md5sum | awk '{print $1}' || true)
if [ -n "$khash" ] && [ -n "${KERNEL_CONFIG_HASH:-}" ]; then
  if [ "$khash" = "$KERNEL_CONFIG_HASH" ]; then
    ok "内核配置指纹一致：$khash"
  else
    bad "内核配置指纹不一致（固件=${KERNEL_CONFIG_HASH} / 本树=${khash}），这些 kmod 装不上"
  fi
else
  bad "拿不到内核配置指纹（固件基线过旧或本 run 未编内核），无法证明 kmod 可安装"
fi

if [ "$fail" -ne 0 ]; then
  echo "::error::固件基线核对失败：产物不保证与固件同源，禁止入库/发布"
  exit 1
fi
ok "固件基线核对通过（${kmcount} 个 kmod 与固件同源）"
