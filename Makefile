# The checks and the builds of the setup. `make check` runs everything the CI
# runs; the other targets split it by language, or build and start the
# binary. Arguments for the binary go through ARGS:
#
#   make run ARGS="--config waybar"
#   make dry-run ARGS="profile parad0xe"

SCRIPTS := bootstrap.sh $(wildcard lib/*.sh modules/*/hooks.sh) tests/test_helper.bash
MANIFEST := --manifest-path tui/Cargo.toml
BINARY := tui/target/release/setup
ARGS ?=

.PHONY: check lint test lint-bash lint-rust test-bash test-rust build run dry-run clean

check: lint test

lint: lint-bash lint-rust

test: test-bash test-rust

# shellcheck and a syntax check of every script
lint-bash:
	shellcheck -x -s bash $(SCRIPTS)
	for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done

# Formatting and clippy of the Rust workspace, warnings refused
lint-rust:
	cargo fmt $(MANIFEST) --all --check
	cargo clippy $(MANIFEST) --workspace --all-targets -- -D warnings

# The bats tests of the bash library and the bootstrap
test-bash:
	bats tests

# The tests of every crate, the binary's end to end in a sandbox
test-rust:
	cargo test $(MANIFEST) --workspace

# The release binary
build:
	cargo build $(MANIFEST) --release

# The screens, then the run (ARGS go to the binary)
run: build
	$(BINARY) $(ARGS)

# The screens, then a dry run that changes nothing
dry-run: build
	$(BINARY) --dry-run $(ARGS)

# The build output of the workspace
clean:
	cargo clean $(MANIFEST)
