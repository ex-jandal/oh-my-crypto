#!/usr/bin/env bash
set -euo pipefail

pkg="omc-${TAG}-${ARCH}"
bin="zig-out/bin/omc"

skip_pattern='ld-linux|libc\.so|libpthread|libdl\.so|librt\.so|libm\.so|linux-vdso|libresolv|libnss_|libGL\.so|libEGL|libglx|libxcb-glx|libgpg-error|libsystemd|libudev'

collect_deps() {
  local out_dir="$1"
  shift
  local -a queue=("$@")
  local -a missing=()

  while ((${#queue[@]})); do
    local cur="${queue[0]}"
    queue=("${queue[@]:1}")

    local deps
    deps="$(ldd "$cur" 2>/dev/null || true)"

    while IFS= read -r line; do
      local lib path
      if [[ "$line" =~ (.+)' => '(.+)' (' ]]; then
        lib="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
      elif [[ "$line" == *'not found'* ]]; then
        missing+=("$line")
        continue
      else
        continue
      fi

      if [[ "$lib" =~ $skip_pattern ]]; then
        continue
      fi

      local name
      name="$(basename "$path")"
      if [[ ! -e "$out_dir/$name" ]]; then
        cp -L "$path" "$out_dir/$name"
        queue+=("$out_dir/$name")
      fi
    done <<<"$deps"
  done

  if ((${#missing[@]})); then
    echo "ERROR: unresolved dependencies:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
  fi
}

rm -rf "$pkg"
mkdir -p "$pkg/lib" "$pkg/plugins"
cp "$bin" "$pkg/omc"

if [[ -n "${QT_PLUGIN_DIR:-}" ]]; then
  plugin_dir="$QT_PLUGIN_DIR"
elif command -v qtpaths6 >/dev/null 2>&1; then
  plugin_dir="$(qtpaths6 --plugin-dir 2>/dev/null || true)"
fi
if [[ -z "${plugin_dir:-}" ]]; then
  plugin_dir="/usr/lib/x86_64-linux-gnu/qt6/plugins"
fi

cp -r "$plugin_dir"/* "$pkg/plugins/"

qt_lib_dir=""
if [[ -n "${QT_PLUGIN_DIR:-}" ]]; then
  qt_lib_dir="$(dirname "$(dirname "$QT_PLUGIN_DIR")")/lib"
fi
if [[ -d "$qt_lib_dir" ]]; then
  cp -L "$qt_lib_dir"/libQt6*.so* "$pkg/lib/"
fi

collect_deps "$pkg/lib" "$pkg/omc" "$pkg"/plugins/*/*.so "$pkg"/lib/*

patchelf --set-rpath '$ORIGIN/lib' "$pkg/omc"
patchelf --set-rpath '$ORIGIN/../../lib' "$pkg"/plugins/*/*.so

tar czf "$pkg.tar.gz" "$pkg"
