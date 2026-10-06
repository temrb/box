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
_TOOL_RAW := $(shell BOX_TOOL=make bash -c 'source "$(BUNDLE_DIR)/lib/tools.sh" >/dev/null 2>&1 && _s="" && for _i in $$box_tool_ids; do _l=$$(box_tool_field $$_i launcher); _s="$$_s $${_l#box-}"; done && _c=$$(box_config_sources | tr "\n" " ") && printf "TOOL_IDS :=%s$(_TOOL_SEP)BUILD_STEMS :=%s$(_TOOL_SEP)TOOL_CONFIGS :=%s" "$$box_tool_ids" "$$_s" "$$_c"')
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

# Discover shell sources, extensionless launchers, and verification harnesses.
# New libraries/entry scripts/launchers are covered without list maintenance.
# verify.d/*.sh partials are bash -n checked in verify-static (shellcheck runs
# on the generated harnesses, not fragments).
SHELL_FILES := $(sort $(patsubst $(BUNDLE_DIR)/%,%,$(shell find $(BUNDLE_DIR) -type f -name '*.sh' ! -path '*/verify.d/*') $(wildcard $(BUNDLE_DIR)/box-*)))
PARTIAL_FILES := $(patsubst $(BUNDLE_DIR)/%,%,$(shell find $(BUNDLE_DIR) -type f -path '*/verify.d/*.sh'))
PYTHON_FILES := $(sort $(patsubst $(BUNDLE_DIR)/%,%,$(shell find $(BUNDLE_DIR) -type f -name '*.py')))
CONFIG_FILES := $(sort $(TOOL_CONFIGS))

# Docker CLI isolation lives in lib/build.sh via box_docker_cli
# (lib/docker.sh probe): the build/clean targets below never hardcode
# `docker --config/--host`, so ambient DOCKER_HOST/DOCKER_CONFIG/proxy vars
# cannot leak into builds. Run `make setup` first on a fresh host so the
# per-tool CLI configs exist.

.DEFAULT_GOAL := help

.PHONY: help build pin-check verify-static verify-native verify-config verify-shell verify-python verify-generated verify-pins-generated pins test test-live setup clean regen-validation update update-check FORCE

help:
	@echo 'Usage: make [target]'
	@echo '  build          build all images for your UID/GID (needs Engine + runsc)'
	@echo '  build-<stem>   build one image (stem = registry launcher suffix, e.g. build-m, build-o)'
	@echo '  setup          run setup.sh (configs, launchers, networks, all images; see setup.sh --help)'
	@echo '  test           run the bats unit suite (tests/bats/; daemon-free)'
	@echo '  test-live      run the live-daemon bats suite (tests/bats-live/; needs Engine)'
	@echo '  verify-static  syntax + configs + generated + pins + shellcheck + bats (fast-first)'
	@echo '  verify-native-opencode  production OpenCode runsc/runc policy and state checks'
	@echo '  verify-native  disposable runsc/runc native evidence; fails on unmet account/policy gates'
	@echo '  verify-config  validate JSON/TOML configuration documents'
	@echo '  verify-shell   bash -n over shell sources and verification partials'
	@echo '  verify-python  py_compile over Python native helpers and tests'
	@echo '  verify-generated  assert verify-*.sh == gen-verify.sh output (primary check; implies §§1-2/5 sync)'
	@echo '  verify-pins-generated  assert docs/architecture.md §4 == gen-pins.sh output'
	@echo '  pin-check      assert version pins vs Dockerfile vs docs/architecture.md §4'
	@echo '  pins           pin-check + verify-pins-generated over the one pin invariant'
	@echo '  update         fetch latest CLI pins, regen, rebuild, sync (see update-pins.sh --help)'
	@echo '  sync-pins-<stem>  validate the bundled image and atomically sync installed pins'
	@echo '  update-check   report current -> latest per tool; change nothing'
	@echo '  regen-validation  regenerate validation/resolved-config.json (needs Engine + image)'
	@echo '  clean          remove all images for your UID/GID (keeps volumes)'

# One pattern builds every tool: the stem resolves box-<stem> to its
# registry id (fail-closed on unknown stems). FORCE keeps the recipe
# unconditional — .PHONY on the pattern targets would suppress matching.
build-%: FORCE
	_id="$$(BOX_TOOL=make bash -c 'source "$(BUNDLE_DIR)/lib/tools.sh" >/dev/null 2>&1 && box_tool_id_for_launcher "box-$*"')" && [ -n "$$_id" ] && bash "$(BUNDLE_DIR)/lib/build.sh" "$$_id"
sync-pins-%: FORCE
	bash "$(BUNDLE_DIR)/sync-pins.sh" "box-$*"

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

update:
	bash "$(BUNDLE_DIR)/update-pins.sh"

update-check:
	bash "$(BUNDLE_DIR)/update-pins.sh" --check

regen-validation:
	bash "$(BUNDLE_DIR)/regen-validation.sh"

test:
	command -v bats >/dev/null || { echo 'bats is required: apt-get install bats (or npm i -g bats)' >&2; exit 1; }
	bats "$(BUNDLE_DIR)/tests/bats/"

test-live:
	command -v bats >/dev/null || { echo 'bats is required: apt-get install bats (or npm i -g bats)' >&2; exit 1; }
	bats "$(BUNDLE_DIR)/tests/bats-live/"

verify-shell:
	for f in $(SHELL_FILES); do bash -n "$(BUNDLE_DIR)/$$f" || exit 1; done
	for f in $(PARTIAL_FILES); do bash -n "$(BUNDLE_DIR)/$$f" || exit 1; done

verify-python:
	python3 -m py_compile $(addprefix "$(BUNDLE_DIR)/",$(PYTHON_FILES))

verify-config:
	BOX_TOOL=make bash -c 'source "$(BUNDLE_DIR)/lib/preflight.sh" && source "$(BUNDLE_DIR)/lib/config-file.sh" && source "$(BUNDLE_DIR)/lib/tools.sh" && box_validate_registry "$(BUNDLE_DIR)" && for f in "$$@"; do box_config_validate "$(BUNDLE_DIR)/$$f" || exit 1; done' _ $(CONFIG_FILES)

verify-static:
	$(MAKE) verify-shell
	$(MAKE) verify-python
	$(MAKE) verify-config
	bash "$(BUNDLE_DIR)/gen-verify.sh" --check
	bash "$(BUNDLE_DIR)/gen-pins.sh" --check
	bash "$(BUNDLE_DIR)/check-pins.sh"
	shellcheck $(addprefix "$(BUNDLE_DIR)/",$(SHELL_FILES))
	bats "$(BUNDLE_DIR)/tests/bats/"

setup:
	bash "$(BUNDLE_DIR)/setup.sh"

verify-native:
	bash "$(BUNDLE_DIR)/tests/native/acceptance.sh"

.PHONY: verify-native-opencode
verify-native-opencode:
	bash "$(BUNDLE_DIR)/tests/native/acceptance.sh" --only opencode
