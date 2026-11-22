#!/usr/bin/env bash
# Download a pinned xila-package release for the runner and verify its SHA-256. Fails closed.
#
# Environment: XILA_PACKAGE_VERSION, RUNNER_OS, RUNNER_ARCH, RUNNER_TEMP, GITHUB_OUTPUT,
# optional XILA_PACKAGE_RELEASE_URL (base URL, for tests) and XILA_PACKAGE_CHECKSUMS (file).
set -euo pipefail

version="${XILA_PACKAGE_VERSION:?xila-package-version is empty}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "::error::xila-package-version must look like 0.4.0, got '$version'"
  exit 1
fi

case "${RUNNER_OS}/${RUNNER_ARCH}" in
  Linux/X64) target=x86_64-unknown-linux-gnu; extension=tar.gz ;;
  Linux/ARM64) target=aarch64-unknown-linux-gnu; extension=tar.gz ;;
  macOS/ARM64) target=aarch64-apple-darwin; extension=tar.gz ;;
  Windows/X64) target=x86_64-pc-windows-msvc; extension=zip ;;
  *)
    echo "::error::xila-package has no release for ${RUNNER_OS}/${RUNNER_ARCH}"
    exit 1
    ;;
esac

asset="xila-package-${target}.${extension}"
base="${XILA_PACKAGE_RELEASE_URL:-https://github.com/xila-project/package_manager/releases/download}/xila-package-builder-v${version}"
checksums="${XILA_PACKAGE_CHECKSUMS:-${GITHUB_ACTION_PATH:?}/checksums.txt}"

work="$(mktemp -d "${RUNNER_TEMP:?}/xila-package-install.XXXXXX")"
curl --fail --silent --show-error --location --retry 3 --output "$work/$asset" "$base/$asset"
curl --fail --silent --show-error --location --retry 3 --output "$work/$asset.sha256" "$base/$asset.sha256"

digest() {
  if command -v sha256sum > /dev/null; then sha256sum "$1" | cut -d ' ' -f 1; else shasum -a 256 "$1" | cut -d ' ' -f 1; fi
}

actual="$(digest "$work/$asset")"
published="$(cut -d ' ' -f 1 < "$work/$asset.sha256" | tr -d '\r\n' | tr 'A-F' 'a-f')"
if [[ ! "$published" =~ ^[0-9a-f]{64}$ ]]; then
  echo "::error::the release's $asset.sha256 is not a SHA-256 digest"
  exit 1
fi
if [[ "$actual" != "$published" ]]; then
  echo "::error::SHA-256 of $asset ($actual) differs from the release's $asset.sha256 ($published)"
  exit 1
fi

# A pinned digest recorded in this action, when there is one for the version, must match as well.
pinned="$(awk -v version="$version" -v asset="$asset" '$1 == version && $2 == asset { print $3 }' "$checksums")"
if [[ -n "$pinned" && "$actual" != "$pinned" ]]; then
  echo "::error::SHA-256 of $asset ($actual) differs from the digest pinned by this action ($pinned)"
  exit 1
fi
if [[ -z "$pinned" ]]; then
  echo "::warning::no digest of xila-package $version is pinned by this action; only the release's own .sha256 was checked"
fi

tar -xf "$work/$asset" -C "$work"
binary="$work/xila-package"
[[ "$RUNNER_OS" == Windows ]] && binary="$binary.exe"
chmod +x "$binary"
"$binary" --version
echo "executable=$binary" >> "$GITHUB_OUTPUT"
