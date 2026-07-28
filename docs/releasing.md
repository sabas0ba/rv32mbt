# Releasing

The project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The public surface that versioning covers is the CLI (its options and
exit statuses), the wasm module's export names and signatures, and the
MoonBit package API under `core/`.

## Where the version lives

| Location | Purpose |
|---|---|
| `moon.mod` | package metadata (`version`) |
| `core/version.mbt` | `@core.VERSION`, what the binaries report at runtime; `ci/build_site.sh` also stamps it onto the published page |
| `CHANGELOG.md` | the release entry and its date |
| the `v<version>` git tag | what the release workflow builds from |

`moon.mod` and `core/version.mbt` cannot import each other, so
`ci/run.sh` compares them at the start of every run and fails the build
if they disagree.

## Cutting a release

1. Update `moon.mod` and `core/version.mbt` to the new version.
2. Add the release entry and its date to `CHANGELOG.md`.
3. Run the full regression in the pinned image:
   `podman run --rm -e RUN_LINUX_BOOT=1 -v "$PWD:/work" rv32mbt-dev bash ci/run.sh`
   (build the kernel first — see [linux.md](linux.md) — otherwise the
   boot test has nothing to run).
4. Merge to `main` and wait for CI to go green.
5. Tag and push: `git tag -a v1.0.0 -m 'rv32mbt 1.0.0' && git push origin v1.0.0`.

Pushing the tag triggers `.github/workflows/release.yml`, which builds
the artifacts with `ci/build_dist.sh` in the pinned image and attaches
them to a GitHub Release created from the tag:

- `rv32mbt-linux-x86_64` — the native CLI
- `rv32mbt-vm.wasm` — the wasm-gc VM module
- `rv32mbt-site.tar.gz` — the static web site

The workflow refuses to run if the tag does not match the version in
`moon.mod`, so a mistyped tag fails fast instead of publishing a
mislabelled release.
