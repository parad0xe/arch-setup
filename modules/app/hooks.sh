#!/bin/bash
# Hooks of modules/app.toml, run by lib/hook.sh.

# Builds Ghostty from the AUR (ghostty-git): not packaged for ARM, where the
# unit runs this hook (x86_64 installs the ghostty package). The PKGBUILD is
# fixed first:
#   - zig 0.16 extracts the fetched packages into zig-pkg/ in the sources
#     and only keeps their archives in the cache where the PKGBUILD looks;
#   - ncurses already ships the "ghostty" terminfo entry, so only
#     "xterm-ghostty" is packaged, like the official ghostty-terminfo.
build_ghostty() {
    if command -v ghostty &> /dev/null; then
        log_warn "Ghostty is already installed."
        return 0
    fi

    log_info "Ghostty is not packaged for ARM, building it from the AUR (ghostty-git)..."

    log_info "Installing pandoc-bin (provides pandoc-cli, needed to build Ghostty)..."
    install_aur_pkg "pandoc-bin"

    local build_dir="$HOME/.cache/ghostty-git-build"
    rm -rf "$build_dir"

    log_info "Downloading the ghostty-git PKGBUILD..."
    git clone https://aur.archlinux.org/ghostty-git.git "$build_dir"
    cd "$build_dir" || exit

    log_info "Fixing the PKGBUILD (zig 0.16 package path, terminfo conflict with ncurses)..."
    # shellcheck disable=SC2016  # the variables are the PKGBUILD's
    sed -i 's|"$srcdir/zig-global-cache/p"|"$srcdir/$_pkgbase/zig-pkg"|' PKGBUILD
    sed -i 's|build/usr/share/terminfo/\*|build/usr/share/terminfo/x|' PKGBUILD

    log_info "Building Ghostty, this takes several minutes..."
    makepkg -s --noconfirm

    # Installs the terminal and its dependencies, not the Nautilus extension
    log_info "Installing ghostty-git, ghostty-shell-integration-git and ghostty-terminfo-git..."
    local pkgs
    mapfile -t pkgs < <(makepkg --packagelist | grep -E '/ghostty-(shell-integration-|terminfo-)?git-[0-9]')
    sudo pacman -U --noconfirm "${pkgs[@]}"

    log_info "Removing the build directory..."
    cd "$HOME" || exit
    rm -rf "$build_dir"

    log_success "Ghostty built and installed."
}

# Makes GNOME Files the default application for folders.
set_default_file_manager() {
    log_info "Making Files the default application for folders..."
    gio mime inode/directory org.gnome.Nautilus.desktop
}
