#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Expand OpenWrt kernel-package DEPENDS into a complete CONFIG_PACKAGE_kmod-* closure.

Why this exists
---------------
The firmware workflows never run kconfig resolution over the symbols they append
(`make defconfig` runs once, then every selection is sed/printf-ed into `.config`
and defconfig is deliberately not run again). kconfig is therefore never given a
chance to pull in a package's `DEPENDS`, which for kernel modules live in
`package/kernel/linux/modules/*.mk` (and in external feeds). The build only sees
the symbols we wrote, and `gen-dependencies.sh` then fails with
"Package kmod-x is missing dependencies for the following libraries: ...".

This script reads those `KernelPackage/<name>` definitions plus the
`AddDepends/<macro>` helpers, walks the `+kmod-*` edges transitively, and writes
out the extra `CONFIG_PACKAGE_kmod-y=m` lines needed for a given fragment.

Dedup rules (important):
  * nodes are held in a set, so a dependency reached twice is only emitted once;
  * seeds (symbols already present in the fragment) are never re-emitted, even
    when they are also a dependency of another seed;
  * symbols that do not exist in the current `.config` are dropped (with a
    warning) instead of being written blind - a non-existent package symbol
    would silently never be built;
  * output is sorted, so repeated runs on the same tree are byte-identical.

Usage
-----
  python3 scripts/kmod-closure.py \
      --root . \
      --fragment configs/features/kmod-repo.config \
      --check-config .config \
      --out .ci-gen/kmod-repo-closure.config
"""

import argparse
import os
import re
import sys

KMOD_PREFIX = "kmod-"

DEF_KERNEL_PKG = re.compile(r"^\s*define\s+KernelPackage/([A-Za-z0-9._+-]+)\s*$")
DEF_ADDDEP = re.compile(r"^\s*define\s+AddDepends/([A-Za-z0-9._+-]+)\s*$")
ENDEF = re.compile(r"^\s*endef\s*$")
# `+kmod-x` and the conditional form `+COND:kmod-x` (e.g. +USE_RFKILL:kmod-rfkill)
TOKEN_DEP = re.compile(r"\+\s*(?:[A-Za-z_][A-Za-z0-9_]*:)?(kmod-[A-Za-z0-9._+-]+)")
ADD_DEP_CALL = re.compile(r"\$\(call\s+AddDepends/([A-Za-z0-9._+-]+)((?:,[^)]*)?)\)")
VAR_REF = re.compile(r"\$[({]")

SKIP_DIRS = {
    ".git", "tmp", "dl", "build_dir", "staging_dir", "output",
    "build_dir_host", ".ci-gen", "node_modules",
}


def iter_makefiles(root):
    """Yield every *.mk / Makefile that may declare a KernelPackage."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        rel = os.path.relpath(dirpath, root).replace(os.sep, "/")
        if rel.count("/") > 6:
            dirnames[:] = []
            continue
        for fn in filenames:
            if fn.endswith(".mk") or fn == "Makefile":
                yield os.path.join(dirpath, fn)


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            return fh.read()
    except OSError:
        return ""


def split_blocks(text, header_re):
    """Yield (name, block_text) for every `define X/<name>` ... `endef` block."""
    lines = text.splitlines()
    i = 0
    n = len(lines)
    while i < n:
        m = header_re.match(lines[i])
        if not m:
            i += 1
            continue
        name = m.group(1)
        body = []
        i += 1
        while i < n and not ENDEF.match(lines[i]):
            body.append(lines[i])
            i += 1
        i += 1
        yield name, body


def block_deps(body):
    """Extract +kmod-* deps and referenced AddDepends macros from a block."""
    deps = set()
    macros = set()
    joined = " ".join(line.rstrip("\\").strip() for line in body)
    for name, args in ADD_DEP_CALL.findall(joined):
        macros.add((name, args.strip().lstrip(",").strip()))
    # Only DEPENDS assignments carry package requirements; KCONFIG/FILES etc
    # must not be mined for `+name` tokens.
    for seg in joined.split(";"):
        if "DEPENDS" not in seg:
            continue
        for tok in TOKEN_DEP.findall(seg):
            # skip `+kmod-nls-$(cp)`-style variable refs and truncated names
            if VAR_REF.search(tok) or tok.endswith(("-", "/")):
                continue
            deps.add(tok)
    return deps, macros


def block_kconfig(body):
    """Bare kernel KCONFIG symbols declared by a KernelPackage block.

    Symbols written as `CONFIG_X=y` carry their own value and are ignored;
    only the value-less ones can end up without a default and hang syncconfig
    in a non-TTY CI job.
    """
    joined = " ".join(line.rstrip("\\").strip() for line in body)
    m = re.search(
        r"KCONFIG\s*:?=\s*(.*?)\s*(?:\b(?:TITLE|DEPENDS|FILES|AUTOLOAD|SUBMENU|"
        r"PROVIDES|MODPARAMS|EXTRA_KCONFIG|PKGFLAGS)\s*:?=|\Z)",
        joined)
    if not m:
        return set()
    syms = set()
    for tok in m.group(1).split():
        if "=" in tok or VAR_REF.search(tok):
            continue
        if re.fullmatch(r"CONFIG_[A-Z0-9_]+", tok):
            syms.add(tok)
    return syms


def load_metadata(root):
    """Return (pkg_deps, pkg_macros, macro_deps, pkg_kconfig)."""
    pkg_deps = {}
    pkg_macros = {}
    macro_deps = {}
    pkg_kconfig = {}
    for path in iter_makefiles(root):
        text = read_text(path)
        if "KernelPackage/" in text:
            for name, body in split_blocks(text, DEF_KERNEL_PKG):
                # `$(eval $(call KernelPackage,fs-cifs))` produces the package
                # `kmod-fs-cifs`, so graph nodes carry the kmod- prefix.
                pkg = name if name.startswith(KMOD_PREFIX) else KMOD_PREFIX + name
                deps, macros = block_deps(body)
                pkg_deps.setdefault(pkg, set()).update(deps)
                if macros:
                    pkg_macros.setdefault(pkg, set()).update(macros)
                pkg_kconfig.setdefault(pkg, set()).update(block_kconfig(body))
        if "AddDepends/" in text:
            for name, body in split_blocks(text, DEF_ADDDEP):
                deps, _ = block_deps(body)
                macro_deps.setdefault(name, set()).update(deps)
    return pkg_deps, pkg_macros, macro_deps, pkg_kconfig


def macro_expand(mac, args, macro_deps, unknown):
    """Expand `$(call AddDepends/<mac>[,args])` into kmod dependency names."""
    names = set(macro_deps.get(mac, ()))
    # AddDepends/nls takes the character-set list as its first argument and
    # the body only carries `+kmod-nls-base $(foreach cp,$(1),+kmod-nls-$(cp))`,
    # which cannot be evaluated here - expand the argument list explicitly.
    if mac == "nls":
        names.add("kmod-nls-base")
        for a in args.replace(",", " ").split():
            a = a.strip()
            if a and not VAR_REF.search(a):
                names.add("kmod-nls-" + a)
        return names
    if mac not in macro_deps:
        unknown.add("AddDepends/" + mac)
    return names


def closure(seeds, pkg_deps, pkg_macros, macro_deps):
    """BFS over +kmod-* edges; returns (reached, unknown)."""
    reached = set()
    unknown = set()
    queue = []

    def push(pkg):
        queue.extend(pkg_deps.get(pkg, ()))
        for mac, args in pkg_macros.get(pkg, ()):
            queue.extend(macro_expand(mac, args, macro_deps, unknown))

    for s in seeds:
        push(s)
    while queue:
        name = queue.pop()
        if name in reached or name in seeds:
            continue
        reached.add(name)
        if name not in pkg_deps:
            unknown.add(name)
            continue
        push(name)
    return reached, unknown


def seeds_from_fragment(path):
    """Read CONFIG_PACKAGE_kmod-xxx=y|m seeds from a config fragment."""
    seeds = set()
    for raw in read_text(path).splitlines():
        line = raw.strip()
        if not line.startswith("CONFIG_PACKAGE_"):
            continue
        if "=" not in line:
            continue
        sym, val = line.split("=", 1)
        if val not in ("y", "m"):
            continue
        name = sym[len("CONFIG_PACKAGE_"):]
        if name.startswith(KMOD_PREFIX):
            seeds.add(name)
    return seeds


def config_symbols(path):
    """Return the set of CONFIG_PACKAGE_* names present in a .config (any value)."""
    syms = set()
    for raw in read_text(path).splitlines():
        line = raw.strip()
        if line.startswith("CONFIG_PACKAGE_"):
            name = line[len("CONFIG_PACKAGE_"):].split("=", 1)[0]
        elif line.startswith("# CONFIG_PACKAGE_") and line.endswith("is not set"):
            name = line[len("# CONFIG_PACKAGE_"):].split(" is not set", 1)[0]
        else:
            continue
        syms.add(name.replace("# ", "").strip())
    return syms


def kernel_symbols(path):
    """Return the set of CONFIG_* kernel symbols known to a kernel .config.

    A symbol that is neither `CONFIG_X=...` nor `# CONFIG_X is not set` has no
    default value, and `make syncconfig` in a non-TTY CI job will hang on it.
    """
    syms = set()
    for raw in read_text(path).splitlines():
        line = raw.strip()
        if not line.startswith("CONFIG_"):
            if not line.startswith("# CONFIG_"):
                continue
            line = line[2:]
        syms.add(line.split("=", 1)[0].split(" is not set", 1)[0].strip())
    return syms


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".", help="OpenWrt source tree root")
    ap.add_argument("--fragment", required=True, help="config fragment with seed symbols")
    ap.add_argument("--out", required=True, help="output closure config path")
    ap.add_argument("--check-config", default="", help=".config used to drop non-existent symbols")
    ap.add_argument("--kernel-config", default="",
                    help="kernel .config; symbols missing there are reported as no-default")
    ap.add_argument("--value", default="m", choices=["m", "y"], help="value for emitted symbols")
    ap.add_argument("--dry-run", action="store_true", help="print closure instead of writing")
    args = ap.parse_args()

    seeds = seeds_from_fragment(args.fragment)
    if not seeds:
        print("::warning::no CONFIG_PACKAGE_kmod-* seeds in %s" % args.fragment)
        return 0

    pkg_deps, pkg_macros, macro_deps, pkg_kconfig = load_metadata(args.root)
    reached, unknown = closure(seeds, pkg_deps, pkg_macros, macro_deps)
    known = config_symbols(args.check_config) if args.check_config else None
    kknown = kernel_symbols(args.kernel_config) if args.kernel_config else None

    emitted = sorted(n for n in reached if n not in seeds and (known is None or n in known))
    dropped = sorted(n for n in reached if n not in seeds and known is not None and n not in known)

    lines = ["CONFIG_PACKAGE_%s=%s" % (n, args.value) for n in emitted]
    header = [
        "# generated by scripts/kmod-closure.py from %s (seeds=%d, deps=%d)"
        % (args.fragment, len(seeds), len(emitted)),
    ]
    content = "\n".join(header + lines) + "\n"

    if args.dry_run:
        sys.stdout.write(content)
    else:
        outdir = os.path.dirname(args.out)
        if outdir and not os.path.isdir(outdir):
            os.makedirs(outdir)
        with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)

    # ---- report: every unresolved / value-less symbol on its own log line,
    #      so the next fix round can pick a value for each of them ----------
    print("[kmod-closure] fragment=%s value=%s seeds=%d closure=%d emitted=%d "
          "dropped=%d unresolved=%d" % (args.fragment, args.value, len(seeds),
                                         len(reached), len(emitted), len(dropped), len(unknown)))
    for name in emitted:
        print("[kmod-closure:emit] CONFIG_PACKAGE_%s=%s" % (name, args.value))
    for name in dropped:
        print("[kmod-closure:missing-symbol] CONFIG_PACKAGE_%s 不存在于 .config，"
              "需在 features 片段显式写值" % name)
    for name in sorted(unknown):
        print("[kmod-closure:unresolved] %s 缺少 KernelPackage 定义或 AddDepends 宏" % name)

    # kernel KCONFIG symbols of the seeds + the pulled-in packages
    targets = sorted(set(seeds) | set(reached))
    no_default = []
    candidates = []
    for pkg in targets:
        for sym in sorted(pkg_kconfig.get(pkg, ())):
            if kknown is None:
                candidates.append((sym, pkg))
            elif sym not in kknown:
                no_default.append((sym, pkg))
    for sym, pkg in no_default:
        print("[kmod-closure:no-default] %s (由 %s 引入) 在内核 .config 中无任何取值，"
              "必须在 features 片段显式定值" % (sym, pkg))
    if kknown is None:
        for sym, pkg in candidates:
            print("[kmod-closure:kconfig] %s (由 %s 引入) 为无值内核符号，"
                  "建议显式定值" % (sym, pkg))
    elif not args.kernel_config:
        print("[kmod-closure] 未提供 --kernel-config，无法判定无默认值符号")

    if dropped:
        print("::warning::%d 个闭包符号在 .config 中不存在：%s"
              % (len(dropped), " ".join(dropped)))
    if unknown:
        print("::warning::%d 个依赖无法解析：%s"
              % (len(unknown), " ".join(sorted(unknown))))
    if no_default:
        print("::warning::%d 个内核符号无默认值（syncconfig 有卡死风险）：%s"
              % (len(no_default), " ".join(sorted(s for s, _ in no_default))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
