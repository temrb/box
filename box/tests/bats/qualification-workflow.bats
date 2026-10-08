# Runner qualification must refuse invalid coordinates without state allocation.
load helpers

@test "qualification runner refuses unknown platforms without allocating state" {
  BOX_QUALIFICATION_ROOT="$PROJ_ROOT" BOX_QUALIFICATION_PLATFORM=invalid run bash -p "$BUNDLE_DIR/tests/native/ci-qualification.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be amd64 or arm64"* ]]
  [ "$(find "$PROJ_ROOT" -maxdepth 1 -name 'box-ci.*' | wc -l)" -eq 0 ]
}

@test "qualification runner refuses missing protected roots and malformed arguments" {
  case "$(uname -m)" in x86_64) platform=amd64 ;; aarch64) platform=arm64 ;; *) skip 'unsupported fixture architecture' ;; esac
  BOX_QUALIFICATION_ROOT="$PROJ_ROOT/missing" BOX_QUALIFICATION_PLATFORM="$platform" run bash -p "$BUNDLE_DIR/tests/native/ci-qualification.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"must already exist"* ]]
  [ ! -e "$PROJ_ROOT/missing" ]
  run bash -p "$BUNDLE_DIR/tests/native/ci-qualification.sh" --unknown
  [ "$status" -eq 2 ]
}

@test "native workflow is manual default-branch-only and uses a protected dedicated runner" {
  run python3 -I - "$BUNDLE_DIR/../.github/workflows/qualify-native.yml" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
assert '  workflow_dispatch:' in text
assert 'pull_request:' not in text and 'pull_request_target:' not in text and '\n  push:' not in text
assert "github.repository == 'temrb/box'" in text
assert 'github.event.repository.default_branch' in text
assert 'environment: box-native-qualification' in text
assert 'self-hosted, linux, box-native' in text
assert 'persist-credentials: false' in text
assert 'secrets.' not in text
assert 'cancel-in-progress: false' in text
PY
  [ "$status" -eq 0 ]
}
