#!/usr/bin/env bash
# Run xila-package with the action's inputs. All packaging, signing and verification logic is
# xila-package's; this script only stages files, decodes the signing key and passes arguments.
#
# Environment: XILA_PACKAGE_EXECUTABLE (binary), INPUT_* (the action inputs), RUNNER_TEMP,
# GITHUB_OUTPUT.
set -euo pipefail
umask 077

xila_package="${XILA_PACKAGE_EXECUTABLE:?}"
manifest="${INPUT_MANIFEST:-}"
executable="${INPUT_EXECUTABLE:-}"
executable_path="${INPUT_EXECUTABLE_PATH:-}"
input_directory="${INPUT_INPUT_DIRECTORY:-}"
output_directory="${INPUT_OUTPUT_DIRECTORY:-xila-package}"
xila_version="${INPUT_XILA_VERSION:-}"
registry_entry_url="${INPUT_REGISTRY_ENTRY_URL:-}"
registry_publisher="${INPUT_REGISTRY_PUBLISHER:-}"
key_directory="${RUNNER_TEMP:?}/xila-package-action-key"

fail() {
  echo "::error::$*"
  exit 1
}

if [[ -n "$input_directory" ]]; then
  [[ -z "$manifest$executable$executable_path" ]] || fail "input-directory excludes manifest, executable and executable-path"
  [[ -f "$input_directory/xila-package.json" ]] || fail "input-directory must contain xila-package.json"
  source_directory="$input_directory"
else
  [[ -n "$manifest" && -n "$executable" && -n "$executable_path" ]] || fail "set input-directory, or manifest with executable and executable-path"
  [[ -f "$manifest" ]] || fail "manifest '$manifest' is not a file"
  [[ -f "$executable" ]] || fail "executable '$executable' is not a file"
  case "$executable_path" in
    /* | ../* | */../* | */.. | .. | "") fail "executable-path must be a relative path inside the package" ;;
  esac
  source_directory="$(mktemp -d "$RUNNER_TEMP/xila-package-source.XXXXXX")"
  cp "$manifest" "$source_directory/xila-package.json"
  mkdir -p "$source_directory/$(dirname "$executable_path")"
  cp "$executable" "$source_directory/$executable_path"
fi

manifest_file="$source_directory/xila-package.json"
if [[ -n "$xila_version" ]]; then
  declared="$(jq --raw-output '.xila_version' "$manifest_file")"
  [[ "$declared" == "$xila_version" ]] || fail "the manifest declares xila_version $declared, expected $xila_version"
fi

# The signing key is a base64 raw 32-byte Ed25519 seed. It only ever lives in a private file.
signing_arguments=()
public_key=""
cleanup() { rm -f "$key_directory/seed"; }
trap cleanup EXIT
if [[ -n "${XILA_PACKAGE_SIGNING_KEY:-}" ]]; then
  mkdir -p "$key_directory"
  chmod 700 "$key_directory"
  rm -f "$key_directory/seed" "$key_directory/public.key"
  (set +x; printf '%s' "$XILA_PACKAGE_SIGNING_KEY" | base64 --decode > "$key_directory/seed") || fail "signing-key is not valid base64"
  chmod 600 "$key_directory/seed"
  "$xila_package" key public "$key_directory/seed" "$key_directory/public.key"
  public_key="$key_directory/public.key"
  signing_arguments=(--signing-key "$key_directory/seed")
fi

name="$(jq --raw-output '.name' "$manifest_file")"
version="$(jq --raw-output '.version' "$manifest_file")"
target="$(jq --raw-output '.target' "$manifest_file")"
filename="$name-$version-$target.xpk"

bundle="$(mktemp -d "$RUNNER_TEMP/xila-package-bundle.XXXXXX")/bundle"
mkdir -p "$output_directory"
package="$output_directory/$filename"
[[ ! -e "$package" ]] || fail "$package already exists"

"$xila_package" bundle build "$source_directory" "$bundle" ${signing_arguments[@]+"${signing_arguments[@]}"}
if [[ -n "$public_key" ]]; then
  "$xila_package" bundle verify "$bundle" --public-key "$public_key"
else
  "$xila_package" bundle verify "$bundle"
fi
"$xila_package" bundle archive "$bundle" "$package"
[[ -z "$public_key" ]] || "$xila_package" verify "$package" "$public_key"

if command -v sha256sum > /dev/null; then
  sha256="$(sha256sum "$package" | cut -d ' ' -f 1)"
else
  sha256="$(shasum -a 256 "$package" | cut -d ' ' -f 1)"
fi

registry_entry_path=""
if [[ -n "$registry_entry_url" ]]; then
  [[ -n "$public_key" ]] || fail "registry-entry-url needs a signing-key"
  [[ -n "$registry_publisher" ]] || fail "registry-entry-url needs registry-publisher"
  registry_entry_path="$package.registry-entry.json"
  "$xila_package" registry entry "$package" "$public_key" "$registry_publisher" "$registry_entry_url" "$registry_entry_path"
fi

if [[ -n "$public_key" ]]; then
  cp "$public_key" "$package.pub"
  public_key="$package.pub"
fi

{
  echo "package-path=$package"
  echo "package-sha256=$sha256"
  echo "public-key-path=$public_key"
  echo "registry-entry-path=$registry_entry_path"
} >> "$GITHUB_OUTPUT"
echo "Packaged $package (SHA-256 $sha256)"
