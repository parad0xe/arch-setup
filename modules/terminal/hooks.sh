#!/bin/bash
# Hooks of modules/terminal.toml, run by lib/hook.sh.

# Makes a shell the login shell of the user, when it is not yet. chsh asks
# for a password, which a background step cannot give: sudo changes it.
#
# Args:
#   shell: The program name (zsh, fish).
_login_shell() {
    local shell user
    shell=$(command -v "$1")
    user=$(id -un)
    if [ "$(getent passwd "$user" | cut -d: -f7)" != "$shell" ]; then
        log_info "Making $1 the login shell of $user..."
        sudo chsh -s "$shell" "$user"
    fi
}

# Makes fish the login shell.
setup_fish() {
    _login_shell fish
}

# Makes Zsh the login shell and installs Oh My Zsh.
setup_zsh() {
    _login_shell zsh

    if [ -d "$HOME/.oh-my-zsh" ]; then
        log_info "Oh My Zsh is already installed."
        return 0
    fi

    # KEEP_ZSHRC keeps the deployed zshrc instead of writing the Oh My Zsh one
    log_info "Installing Oh My Zsh..."
    local installer
    installer=$(mktemp)
    curl -fsSL -o "$installer" "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$installer"
    rm -f "$installer"
}

# Downloads vim-plug for Vim.
install_vim_plug() {
    log_info "Downloading vim-plug for Vim..."
    curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
        "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
}
