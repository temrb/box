# state.bats — authoritative state descriptors: identity, paths, and
# domain isolation. Read-only: no Docker, no locks, no credential reads.
load helpers

@test "project hash is stable and alias-preserving; moves change identity" {
  h1=$(box_state_project_hash "$project")
  [[ "$h1" =~ ^[0-9a-f]{20}$ ]]
  [ "$(box_state_project_hash "$project")" = "$h1" ]
  alias_dir="$PROJ_ROOT/alias-proj"
  ln -s "$project" "$alias_dir"
  [ "$(box_state_project_hash "$alias_dir")" = "$h1" ]
  moved="$PROJ_ROOT/moved-proj"
  mkdir -p -- "$moved"
  [ "$(box_state_project_hash "$moved")" != "$h1" ]
}

@test "production volume names keep the existing formula" {
  hash=$(box_state_project_hash "$project")
  [ "$(box_state_volume_name muse "$host_uid" "$host_gid" "$hash")" = "box-m-u${host_uid}-g${host_gid}-$hash" ]
  [ "$(box_state_volume_name opencode "$host_uid" "$host_gid" "$hash")" = "box-o-v2-u${host_uid}-g${host_gid}-$hash" ]
  [ "$(box_state_volume_name codex "$host_uid" "$host_gid" "$hash")" = "box-c-u${host_uid}-g${host_gid}-$hash" ]
  run box_state_volume_name muse "$host_uid" "$host_gid" short
  [ "$status" -ne 0 ]
  run box_state_volume_name muse 0 "$host_gid" "$hash"
  [ "$status" -ne 0 ]
}

@test "global auth ignores the project; project auth isolates it" {
  g1=$(box_auth_object_dir muse global "$host_uid")
  g2=$(BOX_AUTH_SCOPE=project box_auth_object_dir muse global "$host_uid")
  [ "$g1" = "$g2" ]
  [[ "$g1" == */muse/u"$host_uid"/global ]]
  other="$PROJ_ROOT/other-proj"
  mkdir -p -- "$other"
  h1=$(box_state_project_hash "$project")
  h2=$(box_state_project_hash "$other")
  p1=$(box_auth_object_dir codex project "$host_uid" "$h1")
  p2=$(box_auth_object_dir codex project "$host_uid" "$h2")
  [ "$p1" != "$p2" ]
  [[ "$p1" == */codex/u"$host_uid"/projects/"$h1" ]]
  run box_auth_object_dir codex project "$host_uid" short
  [ "$status" -ne 0 ]
}

@test "uid separates identities; gid changes do not" {
  h=$(box_state_project_hash "$project")
  [ "$(box_auth_object_dir muse global 1001)" != "$(box_auth_object_dir muse global 1002)" ]
  run box_auth_object_dir muse global 0
  [ "$status" -ne 0 ]
  [ "$(box_auth_object_dir muse global "$host_uid")" != "$(box_auth_object_dir opencode global "$host_uid")" ]
  [ "$(box_auth_object_dir opencode global "$host_uid")" != "$(box_auth_object_dir codex global "$host_uid")" ]
}

@test "test auth stays inside the disposable namespace" {
  task=$(mktemp -d "$TEST_TMP/task.XXXXXX")
  ns=t-aaaabbbbcccc
  tglobal=$(BOX_TEST_STATE_NS=$ns BOX_TEST_TASK_ROOT=$task box_auth_object_dir muse global "$host_uid")
  [ "$tglobal" = "$task/$ns/auth/muse/u$host_uid/global" ]
  h=$(box_state_project_hash "$project")
  tproj=$(BOX_TEST_STATE_NS=$ns BOX_TEST_TASK_ROOT=$task box_auth_object_dir codex project "$host_uid" "$h")
  [ "$tproj" = "$task/$ns/auth/codex/u$host_uid/projects/$h" ]
  # Production roots are untouched: nothing created outside the task root.
  [ ! -e "$HOME/.config/box/auth" ]
}

@test "descriptor validation rejects malformed and cross-domain descriptors" {
  desc="$TEST_TMP/desc.txt"
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir muse global "$host_uid")
  printf 'domain=production\nharness=muse\nstate=auth\nclass=auth\nscope=global\nuid=%s\ngid=%s\nproject_hash=%s\nproject=%s\npath=%s\nruntime=/run/box-auth\nadapter=harnesses/muse/auth.sh\nschema_version=1\nvolume=\n' \
    "$host_uid" "$host_gid" "$h" "$project" "$dir" >"$desc"
  run box_state_validate_descriptor "$desc"
  [ "$status" -eq 0 ]
  printf 'domain=production\nharness=muse\nstate=auth\nclass=auth\nscope=global\nuid=%s\ngid=%s\nproject_hash=%s\nproject=%s\npath=\nruntime=/run/box-auth\nadapter=harnesses/muse/auth.sh\nschema_version=1\nvolume=\n' \
    "$host_uid" "$host_gid" "$h" "$project" >"$desc"
  run box_state_validate_descriptor "$desc"
  [ "$status" -ne 0 ]
  printf 'domain=test\nharness=muse\nstate=auth\nclass=auth\nscope=global\nuid=%s\ngid=%s\nproject_hash=%s\nproject=%s\npath=%s\nruntime=/run/box-auth\nadapter=harnesses/muse/auth.sh\nschema_version=1\nvolume=\n' \
    "$host_uid" "$host_gid" "$h" "$project" "$dir" >"$desc"
  BOX_TEST_TASK_ROOT="$TEST_TMP/elsewhere" run box_state_guard_operation plan "$desc"
  [ "$status" -ne 0 ]
}

@test "unsafe roots and comma paths fail before mutation" {
  run box_plan_directory "$project/inner-state"
  [ "$status" -ne 0 ]
  BOX_AUTH_ROOT=relative/path run box_auth_root
  [ "$status" -ne 0 ]
  BOX_AUTH_ROOT="$HOME/.config/box,auth" run box_auth_root
  [ "$status" -ne 0 ]
}
