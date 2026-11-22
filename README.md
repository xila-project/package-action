# Xila package - build and sign Xila application packages in GitHub Actions

[![Test](https://github.com/xila-project/package-action/actions/workflows/test.yml/badge.svg)](https://github.com/xila-project/package-action/actions/workflows/test.yml)

Build, sign and verify a Xila application package (`.xpk`) from your own repository in one step.
The action contains **no packaging logic**: it downloads a pinned release of
[`xila-package`](https://github.com/xila-project/package_manager), verifies its SHA-256 (failing
closed on any difference), and runs it with your inputs. Packaging, signing and verification stay
in `package_manager`.

```yaml
- uses: actions/checkout@v7
- run: cargo build --release --target wasm32-wasip1
- id: package
  uses: xila-project/package-action@v1
  with:
    manifest: xila-package.json
    executable: target/wasm32-wasip1/release/hello.wasm
    executable-path: executables/hello.wasm
    signing-key: ${{ secrets.XILA_SIGNING_KEY }}
- uses: actions/upload-artifact@v7
  with:
    name: package
    path: ${{ steps.package.outputs.package-path }}
```

## Setup

1. Generate a developer key once, locally: `xila-package key generate seed.key public.key`.
   Register `public.key` in [xila-project/registry](https://github.com/xila-project/registry) as
   your developer key; devices trust the repository key, never your developer key directly.
2. Store the seed, base64 encoded (`base64 --wrap 0 seed.key`), as the repository secret
   `XILA_SIGNING_KEY`. Keep the seed out of the repository.
3. Write a developer manifest (`xila-package bundle init` creates one). Its application entry point
   (such as `executables/hello.wasm`) is the `executable-path`.

## Inputs

Give either `input-directory`, or `manifest` with `executable` and `executable-path`.

| Input | Default | |
| --- | --- | --- |
| `input-directory` | | Directory holding `xila-package.json` and every payload file |
| `manifest` | | Developer manifest to package |
| `executable` | | Built executable (such as a `.wasm` file) to ship |
| `executable-path` | | Bundle-relative path of the executable; the manifest's entry point |
| `xila-version` | | Minimum Xila version (`major.minor`) the manifest must declare; the job fails otherwise |
| `signing-key` | | Base64 raw 32-byte Ed25519 seed, from a secret; without it the package is unsigned |
| `output-directory` | `xila-package` | Where the package, public key and registry entry are written |
| `xila-package-version` | `0.4.0` | Release of `xila-package` to download (tag `xila-package-builder-vX.Y.Z`) |
| `registry-entry-url` | | HTTPS address the package will be downloaded from; writes the registry entry JSON |
| `registry-publisher` | | Developer key identifier for the registry entry (needed with `registry-entry-url`) |

The signing key is written to a `0600` file in a private temporary directory, never logged, and
deleted when the action ends, even on failure.

## Outputs

| Output | |
| --- | --- |
| `package-path` | Path of the `.xpk` package (`<name>-<version>-<target>.xpk`) |
| `package-sha256` | SHA-256 of the package |
| `public-key-path` | Raw public key matching `signing-key` (empty when unsigned) |
| `registry-entry-path` | Registry entry JSON (empty without `registry-entry-url`) |

## Examples

Publish a signed package to a release, with its registry entry:

```yaml
on:
  push:
    tags: ["v*"]

jobs:
  package:
    runs-on: ubuntu-24.04
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - run: cargo build --release --target wasm32-wasip1
      - id: package
        uses: xila-project/package-action@v1
        with:
          manifest: xila-package.json
          executable: target/wasm32-wasip1/release/hello.wasm
          executable-path: executables/hello.wasm
          signing-key: ${{ secrets.XILA_SIGNING_KEY }}
          registry-entry-url: https://github.com/${{ github.repository }}/releases/download/${{ github.ref_name }}/hello-${{ github.ref_name }}-wasm32-wasip1.xpk
          registry-publisher: my-developer-key
      - run: gh release upload "$GITHUB_REF_NAME" "$PACKAGE" "$ENTRY"
        env:
          GH_TOKEN: ${{ github.token }}
          PACKAGE: ${{ steps.package.outputs.package-path }}
          ENTRY: ${{ steps.package.outputs.registry-entry-path }}
```

Build from a prepared directory instead:

```yaml
- uses: xila-project/package-action@v1
  with:
    input-directory: package-source
    signing-key: ${{ secrets.XILA_SIGNING_KEY }}
```

## Trust

The `xila-package` archive is checked against the release's `.sha256` asset and, for versions
listed in [`checksums.txt`](checksums.txt), against the digest pinned by this action. Raising
`xila-package-version` to a release without a line there still verifies the release's own digest
and prints a warning. Runners supported: Linux (x64, arm64), macOS (arm64) and Windows (x64); the
tests run on the first three.

Reference the action by a release tag, or by full commit SHA to pin it.

## Development

`tests/run.sh` tests the download and checksum script against a local release directory. CI also
lints the scripts and workflows, then packages a tiny Wasm fixture with a throwaway key generated
in the job and verifies the result with `xila-package`. No private key is ever committed.

Releases are tagged `vX.Y.Z`; the release workflow moves the major tag `vX` to the latest of its
series.

## License

[Apache-2.0](LICENSE).
