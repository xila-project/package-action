#!/usr/bin/env bash
# Test scripts/install.sh against a local release directory: it must accept a matching archive
# and fail closed when the release's .sha256 or the digest pinned by the action differs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

version=9.9.9
asset=xila-package-x86_64-unknown-linux-gnu.tar.gz
release="$work/release/xila-package-builder-v$version"
mkdir -p "$release" "$work/archive"
printf '#!/usr/bin/env bash\necho "xila-package %s"\n' "$version" > "$work/archive/xila-package"
tar -czf "$release/$asset" -C "$work/archive" xila-package
good="$(sha256sum "$release/$asset" | cut -d ' ' -f 1)"
printf '%s  %s\n' "$good" "$asset" > "$release/$asset.sha256"

run_install() {
  local checksums="$1" output="$work/output"
  : > "$output"
  RUNNER_OS=Linux RUNNER_ARCH=X64 RUNNER_TEMP="$work" GITHUB_OUTPUT="$output" \
    XILA_PACKAGE_VERSION="$version" XILA_PACKAGE_RELEASE_URL="file://$work/release" \
    XILA_PACKAGE_CHECKSUMS="$checksums" "$root/scripts/install.sh" > "$work/log" 2>&1
}

expect_failure() {
  if run_install "$1"; then
    echo "FAIL: $2 was accepted"
    cat "$work/log"
    exit 1
  fi
  grep --quiet "differs" "$work/log" || { echo "FAIL: $2 failed for another reason"; cat "$work/log"; exit 1; }
  echo "ok: $2 is rejected"
}

: > "$work/empty.txt"
run_install "$work/empty.txt"
grep --quiet '^executable=' "$work/output"
"$(sed 's/^executable=//' "$work/output")" --version | grep --quiet "xila-package $version"
echo "ok: a matching archive is installed"

printf '%s %s %s\n' "$version" "$asset" "$good" > "$work/pinned.txt"
run_install "$work/pinned.txt"
echo "ok: a matching pinned digest is accepted"

printf '%s %s %s\n' "$version" "$asset" "$(printf '0%.0s' $(seq 64))" > "$work/wrong.txt"
expect_failure "$work/wrong.txt" "a digest differing from the pinned one"

printf '%s  %s\n' "$(printf 'f%.0s' $(seq 64))" "$asset" > "$release/$asset.sha256"
expect_failure "$work/empty.txt" "an archive differing from the release's .sha256"

echo "all install tests passed"
