# Provenance refusals must happen before executing a supplied native binary.
setup() {
  fixture_source="$BATS_TEST_DIRNAME/../native/codex-auth-fixture.py"
  scratch=$(mktemp -d)
  mkdir -p "$scratch/bundle/tests/native" "$scratch/bundle/lib"
  cp "$fixture_source" "$scratch/bundle/tests/native/"
  fixture="$scratch/bundle/tests/native/codex-auth-fixture.py"
  cat > "$scratch/binary" <<'SH'
#!/bin/sh
touch "$(dirname "$0")/executed"
echo 'incorrect version'
SH
  chmod 700 "$scratch/binary"
  python3 -I - "$scratch" <<'PY'
import io, pathlib, sys, tarfile
root = pathlib.Path(sys.argv[1])
with tarfile.open(root / 'package.tar.gz', 'w:gz') as archive:
    data = (root / 'binary').read_bytes()
    member = tarfile.TarInfo('bin/codex')
    member.size, member.mode = len(data), 0o755
    archive.addfile(member, io.BytesIO(data))
PY
  local checksum
  checksum=$(sha256sum "$scratch/package.tar.gz")
  checksum=${checksum%% *}
  cat > "$scratch/bundle/lib/pins.sh" <<SH
box_print_pin() {
  case \$2 in
    CODEX_SHA256_*) printf '%s' '$checksum';;
    CODEX_VERSION) printf '%s' 'fixture-version';;
    *) return 1;;
  esac
}
SH
}

teardown() {
  rm -rf -- "$scratch"
}

@test "Codex fixture requires explicit binary and archive inputs" {
  run python3 -I "$fixture" --scratch-root "$scratch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--binary"*"--archive"* ]]
  [ ! -e "$scratch/executed" ]
}

@test "Codex fixture rejects an unpinned package before native execution" {
  printf 'corruption' >> "$scratch/package.tar.gz"
  run python3 -I "$fixture" --binary "$scratch/binary" --archive "$scratch/package.tar.gz" --scratch-root "$scratch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match the pinned artifact"* ]]
  [ ! -e "$scratch/executed" ]
}

@test "Codex fixture rejects a substituted executable before native execution" {
  printf '\n# substituted\n' >> "$scratch/binary"
  run python3 -I "$fixture" --binary "$scratch/binary" --archive "$scratch/package.tar.gz" --scratch-root "$scratch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"differs from the verified package"* ]]
  [ ! -e "$scratch/executed" ]
}

@test "Codex fixture checks native version only after package and executable match" {
  run python3 -I "$fixture" --binary "$scratch/binary" --archive "$scratch/package.tar.gz" --scratch-root "$scratch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires the pinned Codex version"* ]]
  [ -e "$scratch/executed" ]
  run bash -c 'compgen -G "$1/codex-auth-fixture-*"' fixture "$scratch"
  [ "$status" -ne 0 ]
}
