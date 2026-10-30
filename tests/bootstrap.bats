#!/usr/bin/env bats
# bootstrap.sh: installs git when missing, downloads and checks the released
# binary, clones the repository and starts the setup with the arguments.

load test_helper

setup() {
    untraced sandbox_setup
    BOOTSTRAP="$REPO_DIR/bootstrap.sh"
    export SETUP_DIR="$SANDBOX/dotfiles" SETUP_BIN_DIR="$SANDBOX/local-bin"
    # The "release": a script printing its arguments, served by the fake curl
    export FAKE_RELEASE="$SANDBOX/release"
    printf '#!/bin/bash\necho "setup $*"\n' > "$FAKE_RELEASE"
    fake_curl
    fake_git
}

# curl -o <file> <url>: writes the release for a binary URL, its checksum for
# a .sha256 URL (a wrong one with FAKE_CURL_BAD_SUM).
fake_curl() {
    cat > "$FAKE_BIN/curl" <<'EOF2'
#!/bin/bash
echo "curl $*" >> "$FAKE_LOG"
out="" url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift ;;
        -*) ;;
        *) url="$1" ;;
    esac
    shift
done
[ "${FAKE_CURL_STATUS:-0}" -eq 0 ] || exit "$FAKE_CURL_STATUS"
case "$url" in
    *.sha256)
        sum=$(sha256sum "$FAKE_RELEASE" | cut -d' ' -f1)
        [ -z "${FAKE_CURL_BAD_SUM-}" ] || sum="0000000000000000000000000000000000000000000000000000000000000000"
        name="${url##*/}"
        printf '%s  %s\n' "$sum" "${name%.sha256}" > "$out" ;;
    *) cat "$FAKE_RELEASE" > "$out" ;;
esac
EOF2
    chmod +x "$FAKE_BIN/curl"
}

# git clone creates the folder; every call is logged.
fake_git() {
    cat > "$FAKE_BIN/git" <<'EOF2'
#!/bin/bash
echo "git $*" >> "$FAKE_LOG"
if [ "$1" = clone ]; then
    mkdir -p "${!#}/.git"
fi
exit "${FAKE_GIT_STATUS:-0}"
EOF2
    chmod +x "$FAKE_BIN/git"
}

@test "bootstrap: downloads and checks the binary, clones, starts the setup with the arguments" {
    run bash "$BOOTSTRAP" profile demo --dry-run
    [ "$status" -eq 0 ]
    assert_output_contains "setup --repo $SETUP_DIR profile demo --dry-run"
    [ -x "$SETUP_BIN_DIR/setup" ]
    assert_fake_called "releases/latest/download/setup-x86_64"
    assert_fake_called "setup-x86_64.sha256"
    assert_fake_called "git clone --quiet --branch main https://github.com/parad0xe/arch-setup.git $SETUP_DIR"
    assert_fake_not_called "pacman"
    [ -d "$SETUP_DIR/.git" ]
}

@test "bootstrap: installs git with pacman when it is missing" {
    # No real git on the PATH: the fakes, and the coreutils the bootstrap uses
    mv "$FAKE_BIN/git" "$FAKE_BIN/git.installed"
    mkdir -p "$SANDBOX/tools"
    local tool
    for tool in id sha256sum cut mktemp install mkdir rm cat cp; do
        ln -s "$(command -v "$tool")" "$SANDBOX/tools/$tool"
    done
    # pacman "installs" git: the fake appears
    cat > "$FAKE_BIN/pacman" <<EOF2
#!/bin/bash
echo "pacman \$*" >> "\$FAKE_LOG"
case " \$* " in
    *" git "*) cp "$FAKE_BIN/git.installed" "$FAKE_BIN/git" ;;
esac
EOF2
    chmod +x "$FAKE_BIN/pacman"
    run env PATH="$FAKE_BIN:$SANDBOX/tools" /bin/bash "$BOOTSTRAP"
    [ "$status" -eq 0 ]
    assert_output_contains "Installing git."
    assert_fake_called "sudo pacman -Syu --needed --noconfirm git"
    assert_fake_called "git clone"
    assert_output_contains "setup --repo $SETUP_DIR"
}

@test "bootstrap: a wrong checksum stops it before anything else" {
    run env FAKE_CURL_BAD_SUM=1 bash "$BOOTSTRAP"
    [ "$status" -eq 1 ]
    assert_output_contains "checksum of setup-x86_64 does not match"
    [ ! -e "$SETUP_BIN_DIR/setup" ]
    assert_fake_not_called "git clone"
}

@test "bootstrap: a failed download stops it" {
    run env FAKE_CURL_STATUS=22 bash "$BOOTSTRAP"
    [ "$status" -eq 1 ]
    assert_output_contains "Could not download"
}

@test "bootstrap: an existing clone is brought up to date, a release is picked by SETUP_VERSION" {
    mkdir -p "$SETUP_DIR/.git"
    run env SETUP_VERSION=v0.1.0 bash "$BOOTSTRAP"
    [ "$status" -eq 0 ]
    assert_fake_called "releases/download/v0.1.0/setup-x86_64"
    assert_fake_called "git -C $SETUP_DIR pull --ff-only --quiet"
    assert_fake_not_called "git clone"
    assert_output_contains "setup --repo $SETUP_DIR"
}

@test "bootstrap: SETUP_REPO clones another repository of modules, the binary still comes from the releases" {
    run env SETUP_REPO=me/my-setup bash "$BOOTSTRAP"
    [ "$status" -eq 0 ]
    assert_fake_called "git clone --quiet --branch main https://github.com/me/my-setup.git $SETUP_DIR"
    assert_fake_called "github.com/parad0xe/arch-setup/releases/latest/download/setup-x86_64"
}

@test "bootstrap: a folder in the way that is not a clone is refused" {
    mkdir -p "$SETUP_DIR"
    run bash "$BOOTSTRAP"
    [ "$status" -eq 1 ]
    assert_output_contains "is not a git repository"
}

@test "bootstrap: refuses root and unknown architectures" {
    printf '#!/bin/bash\necho 0\n' > "$FAKE_BIN/id"
    chmod +x "$FAKE_BIN/id"
    run bash "$BOOTSTRAP"
    [ "$status" -eq 1 ]
    assert_output_contains "not root"
    rm "$FAKE_BIN/id"
    run env FAKE_ARCH=riscv64 bash "$BOOTSTRAP"
    [ "$status" -eq 1 ]
    assert_output_contains "Unsupported architecture riscv64"
    assert_fake_not_called "curl"
}
