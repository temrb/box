# box/Makefile — host-only convenience wrappers (never COPYd into images).
# Single build home: lib/build.sh (sourced by setup.sh, executed by the
# build-*/clean targets below). The Makefile parses zero pins even for
# `make help/clean`; lib/build.sh loads pins once per build via
# lib/pins.sh. Image tags are computed in lib/build.sh
# (box_image_tag_for_version: box-m:|<ver> / box-o:<ver>, plus -u<uid>-g<gid>).
# `verify-*.sh` stay self-contained (see the GENERATED NOTE in verify-*.sh,
# docs/operations.md §11: delivered via stdin under --shell, cannot source
# shared code — edit verify.d/ partials and run gen-verify.sh instead).
BUNDLE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Tool ids, build-stems, and config names come from the registry (single
# source; zero per-tool lines below). Stems are the launcher suffixes
# (box-m -> m), so `make build-<stem>` tracks registry launchers for current
# and future tools. One bash sources lib/tools.sh and prints all three lists
# as `@`-separated assignments (ids/stems/config names never contain `@`);
# re-split and eval below so the registry loads once, not once per list.
define _TOOL_NL


endef
_TOOL_SEP := @
_TOOL_RAW := $(shell BOX_TOOL=make bash -c 'source "$(BUNDLE_DIR)/lib/tools.sh" >/dev/null 2>&1 && _s="" && _c="" && for _i in $$box_tool_ids; do _l=$$(box_tool_field $$_i launcher); _s="$$_s $${_l#box-}"; _c="$$_c $$(box_tool_field $$_i config_file)"; done && printf "TOOL_IDS :=%s$(_TOOL_SEP)BUILD_STEMS :=%s$(_TOOL_SEP)TOOL_CONFIGS :=%s" "$$box_tool_ids" "$$_s" "$$_c"')
$(eval $(subst $(_TOOL_SEP),$(_TOOL_NL),$(_TOOL_RAW)))
TOOL_IDS := $(strip $(TOOL_IDS))
BUILD_STEMS := $(strip $(BUILD_STEMS))
TOOL_CONFIGS := $(strip $(TOOL_CONFIGS))
ifeq ($(strip $(TOOL_IDS)),)
$(error Cannot load tool ids from lib/tools.sh)
endif
ifeq ($(strip $(BUILD_STEMS)),)
$(error Cannot load build stems from lib/tools.sh)
endif
ifeq ($(strip $(TOOL_CONFIGS)),)
$(error Cannot load tool configs from lib/tools.sh)
endif

# Shell sources covered by bash -n + shellcheck (split lib + launchers +
# harnesses + installer + pin checker + harness/pin generators + pins/build home).
# CI calls `make verify-static` (no duplicated lists there), so this list is
# the single source for lint coverage.
# verify.d/*.sh partials are bash -n checked in verify-static (shellcheck runs
# on the generated harnesses, not fragments).
SHELL_FILES := lib/preflight.sh lib/tools.sh lib/docker.sh lib/launcher.sh lib/run.sh lib/pins.sh lib/build.sh lib/config.sh box-m box-o box-m-login verify-muse.sh verify-opencode.sh setup.sh check-pins.sh gen-verify.sh gen-pins.sh regen-validation.sh

# Docker CLI isolation lives in lib/build.sh via box_docker_cli
# (lib/docker.sh probe): the build/clean targets below never hardcode
# `docker --config/--host`, so ambient DOCKER_HOST/DOCKER_CONFIG/proxy vars
# cannot leak into builds. Run `make setup` first on a fresh host so the
# per-tool CLI configs exist.

.DEFAULT_GOAL := help

.PHONY: help build pin-check verify-static verify-generated verify-pins-generated pins test setup clean regen-validation FORCE

help:
	@echo 'Usage: make [target]'
	@echo '  build          build all images for your UID/GID (needs Engine + runsc)'
	@echo '  build-<stem>   build one image (stem = registry launcher suffix, e.g. build-m, build-o)'
	@echo '  setup          run setup.sh (configs, launchers, networks, all images; see setup.sh --help)'
	@echo '  test           run the bats unit suite (tests/bats/)'
	@echo '  verify-static  bash -n + jq empty + verify-generated + verify-pins-generated + shellcheck + bats (fast-first)'
	@echo '  verify-generated  assert verify-*.sh == gen-verify.sh output (primary check; implies §§1-2/5 sync)'
	@echo '  verify-pins-generated  assert docs/architecture.md §4 == gen-pins.sh output'
	@echo '  pin-check      assert version pins vs Dockerfile vs docs/architecture.md §4'
	@echo '  pins           pin-check + verify-pins-generated over the one pin invariant'
	@echo '  regen-validation  regenerate validation/resolved-config.json (needs Engine + image)'
	@echo '  clean          remove all images for your UID/GID (keeps volumes)'

# One pattern builds every tool: the stem resolves box-<stem> to its
# registry id (fail-closed on unknown stems). FORCE keeps the recipe
# unconditional — .PHONY on the pattern targets would suppress matching.
build-%: FORCE
	_id="$$(BOX_TOOL=make bash -c 'source "$(BUNDLE_DIR)/lib/tools.sh" >/dev/null 2>&1 && box_tool_id_for_launcher "box-$*"')" && [ -n "$$_id" ] && bash "$(BUNDLE_DIR)/lib/build.sh" "$$_id"
FORCE: ;

build: $(addprefix build-,$(BUILD_STEMS))

clean:
	for id in $(TOOL_IDS); do bash "$(BUNDLE_DIR)/lib/build.sh" --clean $$id || true; done

pin-check:
	bash "$(BUNDLE_DIR)/check-pins.sh"

verify-generated:
	bash "$(BUNDLE_DIR)/gen-verify.sh" --check

verify-pins-generated:
	bash "$(BUNDLE_DIR)/gen-pins.sh" --check

pins: pin-check verify-pins-generated

regen-validation:
	bash "$(BUNDLE_DIR)/regen-validation.sh"

test:
	command -v bats >/dev/null || { echo 'bats is required: apt-get install bats (or npm i -g bats)' >&2; exit 1; }
	bats "$(BUNDLE_DIR)/tests/bats/"

verify-static:
	for f in $(SHELL_FILES); do bash -n "$(BUNDLE_DIR)/$$f" || exit 1; done
	for f in verify.d/*.sh; do bash -n "$(BUNDLE_DIR)/$$f" || exit 1; done
	for f in $(TOOL_CONFIGS); do jq empty "$(BUNDLE_DIR)/$$f" >/dev/null || exit 1; done
	bash "$(BUNDLE_DIR)/gen-verify.sh" --check
	bash "$(BUNDLE_DIR)/gen-pins.sh" --check
	shellcheck $(addprefix "$(BUNDLE_DIR)/",$(SHELL_FILES))
	bats "$(BUNDLE_DIR)/tests/bats/"

setup:
	bash "$(BUNDLE_DIR)/setup.sh"
