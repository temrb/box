# Upgrades

Version synchronization for the pinned Muse and OpenCode releases. The single
pin source is the version files (`version-muse.env`, `version-opencode.env`)
threaded by `lib/pins.sh`; the human-readable mirror is the §4 pin table in
`architecture.md` (verified by `make pin-check`). `setup.sh` preserves
already-installed version pins when they differ from the bundle — synchronize
them with the procedures below.

### 12. Upgrade & Version Synchronization Procedures

#### Bump checklist (every pin change — versions, hashes, Node toolchain)
The version files are the single source, but three generated/pinned
consumers carry the resolved values as literals and must move with them:
1. `version-muse.env` / `version-opencode.env` (all values together, per the
   per-tool procedures below).
2. `verify.d/40-readiness-<id>.sh` binary-version literals — then regenerate
   the delivered harnesses with `bash gen-verify.sh` (never hand-edit
   `verify-*.sh`; `make verify-generated` asserts they match).
3. `docs/architecture.md` §4 pin table — regenerate with `bash gen-pins.sh`
   (`make verify-pins-generated` asserts it matches).
4. `tests/bats/pins.bats` + `tests/bats/version.bats` hardcoded literals
   (intentional tripwires: they fail until updated to the new pins).
5. Installed copies in `~/.config/box-m/` / `~/.config/box-o/` (`cmp` them
   against the bundle per the per-tool steps).
`gen-pins.sh --check` fails closed when the harness versions or the muse
safety keys drift from the version files / seed; `make pins && make test`
is the final gate before committing.

#### Muse
1. Obtain the new version string (e.g., `0.2.0-R810.1`) and SHA-256 integrity hashes for amd64 and arm64.
2. Rebuild the container image with the updated pins (`make build-m`
   threads them from `version-muse.env` via `lib/pins.sh` — point to the
   `make` target, no manual `docker build` block is kept here):
   ```bash
   bundle_dir=/path/to/box
   new_version="0.2.0-R810.1"
   new_sha_amd64="<64_hex_digits>"
   new_sha_arm64="<64_hex_digits>"

   # Write the pins first (all three values together), then build:
   {
     printf '# Pinned Meta Muse Code release used by build commands and launchers.\n'
     printf '# Update all three values together via the documented upgrade procedure.\n'
     printf 'MUSE_VERSION=%s\n' "$new_version"
     printf 'MUSE_SHA256_AMD64=%s\n' "$new_sha_amd64"
     printf 'MUSE_SHA256_ARM64=%s\n' "$new_sha_arm64"
   } > "$bundle_dir/version-muse.env"
   make -C "$bundle_dir" build-m
   ```
3. Test the new image:
   ```bash
   BOX_M_IMAGE="box-m:${new_version}-u$(id -u)-g$(id -g)" box-m --version
   ```
4. Synchronize `version-muse.env` across the repository bundle and user configuration (atomic rename, so readers never see a half-written file):
   ```bash
   tmp=$(mktemp "$HOME/.config/box-m/.version-muse.env.tmp.XXXXXX")
   cp -- "$bundle_dir/version-muse.env" "$tmp"
   chmod 644 -- "$tmp"
   mv -f -- "$tmp" "$HOME/.config/box-m/version-muse.env"
   cmp "$bundle_dir/version-muse.env" "$HOME/.config/box-m/version-muse.env" && echo "Versions synchronized."
   ```
5. Finish the bump checklist above (harness literals + `gen-verify.sh`, pin table + `gen-pins.sh`, bats literals), then `make pins && make test`.

#### OpenCode
1. Obtain the new version (e.g., `1.19.0`) and its npm `dist.integrity` pins:
   ```bash
   new_version="1.19.0"
   npm view "opencode-ai@${new_version}" dist.integrity
   npm view "opencode-linux-x64@${new_version}" dist.integrity
   npm view "opencode-linux-arm64@${new_version}" dist.integrity
   ```
2. Rebuild (`make build-o` threads the same pins from
   `version-opencode.env` via `lib/pins.sh` — point to the `make` target, no
   manual `docker build` block is kept here): update `version-opencode.env`
   (all six values together: `OPENCODE_VERSION`, the three `dist.integrity`
   pins, plus `NODE_VERSION` / `NODESOURCE_FINGERPRINT` when rotating the
   toolchain), then `make -C "$bundle_dir" build-o`.
3. Test: `BOX_O_IMAGE="box-o:${new_version}-u$(id -u)-g$(id -g)" box-o --version`, then update `version-opencode.env` (all six values) in the bundle + `~/.config/box-o/` and `cmp` them.
4. Finish the bump checklist above (harness literals + `gen-verify.sh`, pin table + `gen-pins.sh`, bats literals), then `make pins && make test`.

> Migration note: installs predating the Phase 5 pin unification carry a
> four-value `version-opencode.env` (no `NODE_VERSION` /
> `NODESOURCE_FINGERPRINT`). The strict parser fails closed on them
> (`Invalid NODE_VERSION in .../version-opencode.env`). Re-sync the installed
> file from the bundle with step 3 above (`setup.sh` never overwrites a
> differing installed pin file on its own — installed pins win on re-run).

#### NodeSource APT key rotation (`keys/nodesource.asc`)
The vendored key is long-lived with no expiry; the fail-closed fingerprint
assert (`NODESOURCE_FINGERPRINT` in `version-opencode.env`, checked by
`check-pins.sh` and enforced in `Dockerfile --target opencode`) means a stale
key fails the build, never silently trusts. To rotate (upstream rollover or
scheduled hygiene):
```bash
bundle_dir=/path/to/box
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodesource-new.asc
gpg --show-keys --with-colons /tmp/nodesource-new.asc | grep -c '^fpr:' # expect 2 (primary + subkey)
gpg --show-keys --with-colons /tmp/nodesource-new.asc | awk -F: '/^fpr:/ {print $10; exit}' # primary -> NODESOURCE_FINGERPRINT
# Verify the fingerprint out-of-band (NodeSource docs / second channel).
# If upstream changes the key structure (count != 2), update the
# `fpr_count` assert in `Dockerfile --target opencode` together with
# `check-pins.sh` (it locks the count) and this procedure.
# then replace the vendored key (LF-only) and update the pin (all six
# version-opencode.env values together when rotating Node with it):
cp /tmp/nodesource-new.asc "$bundle_dir/keys/nodesource.asc"
# ... edit NODESOURCE_FINGERPRINT in "$bundle_dir/version-opencode.env" ...
make -C "$bundle_dir" build-o && make -C "$bundle_dir" pins
```
Record the live-key date in the commit message (same convention as the
Debian `# pin-date:` in the `Dockerfile`).

#### Model pins (`settings.json`; `opencode.json` carries none)
`opencode.json` pins only `permission` (no `model`, no provider block):
opencode auths natively via `/connect` and the model is user-chosen, so
there is no model pin to bump — change the permission shape by editing the
bundle config, running `gen-pins.sh --check` (fails closed when
`verify.d/40-readiness-opencode.sh` no longer mirrors it), reinstalling via
`setup.sh` (a customized installed config is backed up to `*.bak`), and
re-running the `verify-opencode.sh` harness. `settings.json` (`model:
muse-spark-1.3`) is instead a seed default for fresh installs — muse owns
its copy in `~/.config/box-m/muse-config/` and in-container `/models`
changes persist there. Bump the default by editing the bundle config (keep
the `lib/tools.sh` registry `model` and the `architecture.md` snippet in
sync), running `gen-pins.sh --check` (fails closed on endpoint drift),
reinstalling via `setup.sh` (refreshes the seed source; persisted user
settings are kept — delete `muse-config/settings.json` to adopt the new
default), and re-running the `verify-muse.sh` harness.
