load helpers

@test "isolated v2 pins load as SHA256 invalidating the registered bundle cache" {
  box_load_all_pins "$BUNDLE_DIR"
  original=$OPENCODE_VERSION
  box_load_pins_file "$BUNDLE_DIR/harnesses/opencode/version-opencode.env" sha-pinned \
    OPENCODE_VERSION OPENCODE_SHA256_AMD64 OPENCODE_SHA256_ARM64
  [ "$OPENCODE_VERSION" = 2.0.6 ]
  [[ "$OPENCODE_SHA256_AMD64" =~ ^[0-9a-f]{64}$ ]]
  [[ "$OPENCODE_SHA256_ARM64" =~ ^[0-9a-f]{64}$ ]]
  [ -z "${_BOX_PINS_LOADED_FOR:-}" ]
  # A normal bundle load restores shipped pins after candidate parsing.
  box_load_all_pins "$BUNDLE_DIR"
  [ "$OPENCODE_VERSION" = "$original" ]
}

@test "v2 SHA256 parser rejects missing and malformed architecture digests" {
  for defect in missing corrupt; do
    cp "$BUNDLE_DIR/harnesses/opencode/version-opencode.env" "$TEST_TMP/version.env"
    if [ "$defect" = missing ]; then
      sed -i '/OPENCODE_SHA256_ARM64=/d' "$TEST_TMP/version.env"
    else
      sed -i 's/^OPENCODE_SHA256_AMD64=.*/OPENCODE_SHA256_AMD64=bad/' "$TEST_TMP/version.env"
    fi
    run box_load_pins_file "$TEST_TMP/version.env" sha-pinned \
      OPENCODE_VERSION OPENCODE_SHA256_AMD64 OPENCODE_SHA256_ARM64
    [ "$status" -ne 0 ]
  done
}

@test "standalone archive rejects corrupt, unsafe layout and wrong architecture" {
  run python3 - "$BUNDLE_DIR/harnesses/opencode/archive.py" "$TEST_TMP" <<'PYTEST'
import importlib.util, io, pathlib, sys, tarfile
spec=importlib.util.spec_from_file_location('archive', sys.argv[1]); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
root=pathlib.Path(sys.argv[2]); path=root/'artifact.tar.gz'
path.write_bytes(b'corrupt')
try: module.validate_archive(path, 'amd64')
except tarfile.TarError: pass
else: raise AssertionError('Corrupt archive accepted')
for name, mode, kind, machine, expected in [('opencode',0o755,tarfile.REGTYPE,62,True), ('../opencode',0o755,tarfile.REGTYPE,62,False), ('opencode',0o644,tarfile.REGTYPE,62,False), ('opencode',0o755,tarfile.SYMTYPE,62,False), ('opencode',0o755,tarfile.REGTYPE,183,False)]:
    data=b'\x7fELF\x02\x01'+b'\0'*12+machine.to_bytes(2,'little')
    with tarfile.open(path,'w:gz') as archive:
        member=tarfile.TarInfo(name); member.mode=mode; member.type=kind; member.size=len(data) if kind==tarfile.REGTYPE else 0
        archive.addfile(member,io.BytesIO(data) if member.size else None)
    try: module.validate_archive(path,'amd64')
    except ValueError: assert not expected
    else: assert expected
PYTEST
  [ "$status" -eq 0 ]
}

@test "shipped native rules preserve asks and exception order" {
  run python3 - "$BUNDLE_DIR/harnesses/opencode/config/opencode.json" <<'PY'
import fnmatch, json, sys
config = json.load(open(sys.argv[1]))
assert config['default_agent'] == 'plan' and config['update'] == 'disable'
assert 'lsp' not in config and 'experimental' not in config
for action in ['read', 'edit']:
    for resource, expected in [('test.env', 'ask'), ('test.env.production', 'ask'),
                               ('test.env.example', 'allow'), ('README.md', 'allow')]:
        effects = [r['effect'] for r in config['permissions']
                   if fnmatch.fnmatchcase(action, r['action']) and
                   fnmatch.fnmatchcase(resource, r['resource'])]
        assert effects[-1] == expected, (action, resource)
assert config['permissions'][-1] == {
    'action': 'external_directory', 'resource': '*', 'effect': 'ask'}
PY
  [ "$status" -eq 0 ]
}

@test "shipped config has eight ordered v2 rules" {
  run jq -e '
    .default_agent == "plan" and .update == "disable"
    and (has("lsp") | not) and (has("permission") | not)
    and (.permissions | length == 8)
    and .permissions[0] == {"action":"*","resource":"*","effect":"allow"}
    and .permissions[7] == {"action":"external_directory","resource":"*","effect":"ask"}
  ' -- "$BUNDLE_DIR/harnesses/opencode/config/opencode.json"
  [ "$status" -eq 0 ]
}

@test "dockerfile consumes three sha pins without npm or nodesource" {
  run grep -Fq 'ARG OPENCODE_VERSION' "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
  run grep -Fq 'ARG OPENCODE_SHA256_AMD64' "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
  run grep -Fq 'ARG OPENCODE_SHA256_ARM64' "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
  run grep -Fq 'sha256sum --check' "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
  run grep -Fq 'opencode v$OPENCODE_VERSION' "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
  run grep -Fiq 'npm pack\|nodesource\|NODE_VERSION' "$BUNDLE_DIR/Dockerfile"
  [ "$status" -ne 0 ]
  run grep -Fq 'LABEL org.opencode.box.version' "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
}

@test "opencode label-mismatch fails closed on integrity labels" {
  unset project
  vf="$TEST_TMP/version-opencode.env"
  make_opencode_version_file "$vf"
  box_load_version_file "$vf" "$(box_tool_field opencode version_format)" $(box_tool_field opencode pin_keys)
  ver=$box_file_version
  log="$TEST_TMP/inspect-calls.txt"
  payload="$TEST_TMP/inspect-payload.txt"
  : >"$log"
  stub="$TEST_TMP/stub-docker-opencode"
  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "$*" >>%q\n' "$log"
    printf 'n=$(wc -l <%q)\n' "$log"
    printf 'if [ "$n" -eq 1 ]; then printf "%%s\\n" %q; else cat -- %q; fi\n' \
      "$host_uid:$host_gid|$ver" "$payload"
  } >"$stub"
  chmod +x -- "$stub"
  printf '%s\n' "${box_file_pin[OPENCODE_SHA256_AMD64]}|${box_file_pin[OPENCODE_SHA256_ARM64]}" >"$payload"
  docker_cmd=("$stub")
  box_assert_image "some-image:tag" "$ver" "$vf" opencode 0
  [ "$(wc -l <"$log")" -eq 2 ]
  second=$(sed -n '2p' -- "$log")
  [[ "$second" == *"org.opencode.box.sha256-amd64"* ]]
  [[ "$second" == *"org.opencode.box.sha256-arm64"* ]]
  : >"$log"
  printf '%s\n' "${box_file_pin[OPENCODE_SHA256_AMD64]}|WRONG" >"$payload"
  run box_assert_image "some-image:tag" "$ver" "$vf" opencode 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"org.opencode.box.sha256-arm64"* ]]
}

@test "opencode update scoping requires explicit version without npm latest" {
  run grep -Fq 'registry.npmjs.org' "$BUNDLE_DIR/harnesses/opencode/update.sh"
  [ "$status" -ne 0 ]
  run grep -Fq 'no latest channel' "$BUNDLE_DIR/harnesses/opencode/update.sh"
  [ "$status" -eq 0 ]
  run grep -Fq 'opencode.ai/files/bin' "$BUNDLE_DIR/harnesses/opencode/update.sh"
  [ "$status" -eq 0 ]
  source "$BUNDLE_DIR/harnesses/opencode/update.sh"
  unset BOX_UPDATE_OPENCODE_VERSION BOX_UPDATE_OPENCODE_SHA256_AMD64 BOX_UPDATE_OPENCODE_SHA256_ARM64
  unset BOX_UPDATE_OPENCODE_NPM_INTEGRITY BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_X64 BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64
  unset BOX_UPDATE_OPENCODE_NODE_VERSION BOX_UPDATE_OPENCODE_NODESOURCE_FINGERPRINT
  declare -A new_pin=()
  OPENCODE_VERSION=$(box_print_pin "$BUNDLE_DIR" OPENCODE_VERSION)
  OPENCODE_SHA256_AMD64=$(box_print_pin "$BUNDLE_DIR" OPENCODE_SHA256_AMD64)
  OPENCODE_SHA256_ARM64=$(box_print_pin "$BUNDLE_DIR" OPENCODE_SHA256_ARM64)
  run box_harness_resolve
  [ "$status" -ne 0 ]
  [[ "$output" == *"no latest channel"* ]]
  BOX_UPDATE_OPENCODE_VERSION=9.9.9
  export BOX_UPDATE_OPENCODE_VERSION
  unset BOX_UPDATE_OPENCODE_SHA256_AMD64 BOX_UPDATE_OPENCODE_SHA256_ARM64
  run box_harness_resolve
  [ "$status" -ne 0 ]
  [[ "$output" == *"Partial OpenCode seed"* ]]
  unset BOX_UPDATE_OPENCODE_VERSION
}

@test "opencode launcher persists config siblings in an isolated v2 volume" {
  [[ -x /usr/bin/docker || -x /usr/local/bin/docker ]] || skip "no Docker CLI on launcher trusted PATH"
  config="$TEST_HOME/opencode.json"
  cp "$BUNDLE_DIR/harnesses/opencode/config/opencode.json" "$config"
  pins="$TEST_HOME/version.env"
  cp "$BUNDLE_DIR/harnesses/opencode/version-opencode.env" "$pins"
  cd "$TEST_PROJ"
  run env BOX_O_CONFIG="$config" BOX_O_VERSION_FILE="$pins" "$BUNDLE_DIR/box-o" --dry-run
  [ "$status" -eq 0 ]
  run python3 - "$output" "$TEST_PROJ" <<'PYTEST'
import hashlib, os, shlex, sys
args=shlex.split(sys.argv[1].splitlines()[-1])
envs=[args[i+1] for i,v in enumerate(args) if v=='--env']
mounts=[args[i+1] for i,v in enumerate(args) if v=='--mount']
tmpfs=[args[i+1] for i,v in enumerate(args) if v=='--tmpfs']
assert 'XDG_CONFIG_HOME=/persist/config' in envs
assert any('dst=/persist/config/opencode/opencode.json,readonly' in mount for mount in mounts)
hash=hashlib.sha256(os.path.realpath(sys.argv[2]).encode()).hexdigest()[:20]
assert 'type=volume,src=box-o-v2-u%d-g%d-%s,dst=/persist' % (os.getuid(),os.getgid(),hash) in mounts
assert not any(mount.startswith(('/persist/config:', '/persist/config/opencode:', '/home/box/.config/opencode:')) for mount in tmpfs)
PYTEST
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_HOME/.config/box-o/docker-cli" ]
}

@test "native classifier requires matched explicit ask deny or completed execution" {
  run python3 - "$BUNDLE_DIR/harnesses/opencode/native-probe.py" <<'PYTEST'
import copy, importlib.util, json, sys
spec=importlib.util.spec_from_file_location('probe',sys.argv[1]); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
op=module.OPERATIONS[0]
def result(status='completed',error=None,path=op['path'],code=0,stderr=''):
    state={'status':status,'input':{'path':path}}
    if error: state['error']=error
    event={'type':'tool_use','part':{'tool':op['tool'],'state':state}}
    return {'bounded':True,'code':code,'stdout':json.dumps(event),'stderr':stderr}
assert module.classify(result(),op)=='allow'
assert module.classify(result('error','Permission denied: read'),op)=='deny'
ask=result('error','The user declined this tool call',code=1,stderr='permission requested: read (test.env); auto-rejecting')
assert module.classify(ask,op)=='ask'
for case in [result('pending'),result('error','provider failure'),result(path='/workspace/other.env'),result(code=1),result('error','The user declined this tool call'),result(stderr='permission requested: read (other.env)')]:
    assert module.classify(case,op)=='unavailable', case
for stdout in ['', 'bad JSON', '{}', '[]', json.dumps({'type':'error','error':{'type':'startup','message':'failed'}})]:
    assert module.classify({'bounded':True,'code':1,'stdout':stdout,'stderr':''},op)=='unavailable'
case=result();case['bounded']=False
assert module.classify(case,op)=='unavailable'
case=result();case['stdout']+='\n{broken'
assert module.classify(case,op)=='unavailable'
case=result();case['stdout']+='\n'+json.dumps({'type':'error','error':{'type':'provider'}})
assert module.classify(case,op)=='unavailable'
title_only={'bounded':True,'code':0,'stdout':json.dumps({'type':'message','part':{'text':'fixture title'}}),'stderr':''}
assert module.classify(title_only,op)=='unavailable'
PYTEST
  [ "$status" -eq 0 ]
}

@test "v2 SQLite credential guard rejects unsafe stores and creates private shell files" {
  root="$TEST_TMP/persist"
  mkdir -p "$root/data/opencode/opencode"
  guard="$TEST_TMP/entrypoint.sh"
  sed "s|/persist|$root|g" "$BUNDLE_DIR/harnesses/opencode/entrypoint.sh" >"$guard"
  cache="$root/data/opencode/opencode/opencode.db"
  for suffix in '' -wal -shm; do
    printf fixture >"$cache$suffix"
    chmod 644 "$cache$suffix"
    run env BOX_OPENCODE_SHELL=1 bash "$guard" -c 'exit 0'
    [ "$status" -ne 0 ]
    [[ "$output" == *'unsafe native OpenCode authentication cache'* ]]
    chmod 600 "$cache$suffix"
  done
  rm "$cache"
  ln -s "$TEST_TMP/missing" "$cache"
  run env BOX_OPENCODE_SHELL=1 bash "$guard" -c 'exit 0'
  [ "$status" -ne 0 ]
  rm "$cache"
  mkdir "$cache"
  run env BOX_OPENCODE_SHELL=1 bash "$guard" -c 'exit 0'
  [ "$status" -ne 0 ]
  rmdir "$cache"
  run env BOX_OPENCODE_SHELL=1 bash "$guard" -c 'touch "$1"' _ "$TEST_TMP/private-file"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$TEST_TMP/private-file")" = 600 ]
  mv "$root/data/opencode/opencode" "$root/data/opencode/redirected"
  ln -s "$root/data/opencode/redirected" "$root/data/opencode/opencode"
  run env BOX_OPENCODE_SHELL=1 bash "$guard" -c 'exit 0'
  [ "$status" -ne 0 ]
  [[ "$output" == *'redirected native OpenCode cache parent'* ]]
}
