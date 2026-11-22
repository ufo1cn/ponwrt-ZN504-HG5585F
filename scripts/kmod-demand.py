#!/usr/bin/env python3
"""列出用户态包需要的 kmod，并对照固件配置判断是否已内置/已出 apk。

包流程（legacy / incremental / extra）只编用户态包：kmod 一律由固件流程
fw-build.yml 在同一次构建里编成 apk（build/src/ABI 才能对上）。但用户态包若
DEPENDS 里有 kmod-x，staging 里没有对应包时编译期会硬失败。所以这里在编译前
把 kmod 需求列出来，标出固件是否已经提供，交给人/固件流程补清单。

用法：
  python3 scripts/kmod-demand.py --root . \
      --manifest configs/pon-legacy-packages.txt \
      --only all --extra "" \
      --fwconfig configs/an7581.config configs/release.config \
                 configs/features/kmod-repo.config
输出前缀 [kmod-demand]，退出码恒为 0（只提示，不拦编译）。
"""
import argparse
import os
import re
import sys

KMOD_RE = re.compile(r'kmod-[A-Za-z0-9][A-Za-z0-9\-]*')


def logical_lines(text):
    """把 Makefile 的反斜杠续行拼成逻辑行。"""
    out, buf = [], ''
    for raw in text.split('\n'):
        line = raw.rstrip()
        if line.endswith('\\'):
            buf += line[:-1].rstrip() + ' '
            continue
        out.append(buf + line)
        buf = ''
    if buf:
        out.append(buf)
    return out


def parse_makefile(path):
    """返回 {package_name: set(kmod 依赖)}。"""
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        return {}
    lines = logical_lines(text)
    result, cur, in_block = {}, None, False
    for line in lines:
        m = re.match(r'^define\s+Package/(\S+)', line)
        if m:
            cur, in_block = m.group(1), True
            result.setdefault(cur, set())
            continue
        if in_block and re.match(r'^endef\s*$', line):
            cur, in_block = None, False
            continue
        if in_block and cur and re.match(r'^\s*(PKG_)?DEPENDS\s*[:+]?=', line):
            rhs = line.split('=', 1)[1] if '=' in line else ''
            if '$(call AddDepends' in rhs:
                continue
            for tok in rhs.split():
                tok = tok.lstrip('+')
                if ':' in tok:
                    tok = tok.rsplit(':', 1)[1]
                if tok.startswith('@'):
                    continue
                for k in KMOD_RE.findall(tok):
                    result[cur].add(k)
    return result


def index_packages(root):
    idx = {}
    for base, dirs, files in os.walk(os.path.join(root, 'package')):
        dirs[:] = [d for d in dirs if d not in ('.git', 'build_dir', 'staging_dir')]
        if 'Makefile' not in files:
            continue
        path = os.path.join(base, 'Makefile')
        try:
            head = open(path, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        if 'define Package/' not in head:
            continue
        for name, kmods in parse_makefile(path).items():
            if name in idx:
                idx[name][1].update(kmods)
            else:
                idx[name] = (path, set(kmods))
    return idx


def fw_provides(paths):
    prov = {}
    for p in paths:
        if not os.path.isfile(p):
            print('[kmod-demand] 配置缺失: %s' % p)
            continue
        for line in open(p, encoding='utf-8', errors='replace'):
            m = re.match(r'^CONFIG_PACKAGE_(kmod-\S+)=([ym])$', line.strip())
            if m:
                prev = prov.get(m.group(1))
                # =y 优先于 =m
                if prev != 'y':
                    prov[m.group(1)] = m.group(2)
    return prov


def read_selection(manifests, only, extra):
    wanted = []
    for manifest in manifests:
        if not manifest or not os.path.isfile(manifest):
            continue
        for line in open(manifest, encoding='utf-8', errors='replace'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('|')
            if len(parts) >= 2:
                wanted.append(parts[1].strip())
    for e in (extra or '').split(','):
        e = e.strip()
        if e:
            wanted.append(e)
    only = (only or 'all').strip()
    if only and only != 'all':
        names = [x.strip() for x in only.split(',') if x.strip()]
        wanted = [w for w in wanted if w in names] or names
    return wanted


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='.')
    ap.add_argument('--manifest', nargs='*', default=[])
    ap.add_argument('--only', default='all')
    ap.add_argument('--extra', default='')
    ap.add_argument('--fwconfig', nargs='*', default=[])
    args = ap.parse_args()

    wanted = read_selection(args.manifest, args.only, args.extra)
    print('[kmod-demand] 选中 %d 个包' % len(wanted))
    idx = index_packages(args.root)
    prov = fw_provides(args.fwconfig)

    needed, missing, unknown = {}, [], []
    for name in wanted:
        if name not in idx:
            unknown.append(name)
            continue
        path, kmods = idx[name]
        if not kmods:
            print('[kmod-demand] %s 无 kmod 依赖' % name)
            continue
        for k in sorted(kmods):
            needed.setdefault(k, []).append(name)

    for k, users in sorted(needed.items()):
        state = prov.get(k)
        if state == 'y':
            note = '固件已内置 =y（插上即用，不进 apk 仓库）'
        elif state == 'm':
            note = '固件流程出 apk（=m，开机后 opkg/apk 装）'
        else:
            note = '固件未提供 → 需在 fw-build 片段清单里补'
            missing.append(k)
        print('[kmod-demand] %s 需要 %s -> %s  （%s）' % (k, ','.join(users), k, note))

    if unknown:
        print('[kmod-demand] 以下包在源码树里没找到 Makefile（清单拼错或需要额外 feed）: %s'
              % ','.join(unknown))
    print('>>> kmod 需求清单（由固件流程编译）: %s' % (','.join(sorted(needed)) or '（无）'))
    if missing:
        print('::warning::以下 kmod 固件流程没提供，包流程可能因缺依赖失败: %s'
              % ','.join(sorted(missing)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
