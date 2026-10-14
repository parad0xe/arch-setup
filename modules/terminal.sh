#!/bin/bash

# Installs Zsh with Oh My Zsh, its plugins (autosuggestions, syntax
# highlighting), the Starship prompt and the tools the zshrc runs (eza, bat,
# zoxide, fzf, fastfetch), and links the zshrc, Starship and fastfetch
# configs.
_setup_shell() {
    local pkgs=(
        "zsh"
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
        "starship"
        "eza"
        "bat"
        "zoxide"
        "fzf"
        "fastfetch"
    )

    log_info "Installing Zsh and its tools..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done

    log_info "Linking zshrc, Starship and fastfetch configs..."
    link_config "$SETUP_DIR/.config/zshrc" "$HOME/.zshrc"
    link_config "$SETUP_DIR/.config/starship/nerd-font-symbols.toml" "$HOME/.config/starship.toml"
    link_config "$SETUP_DIR/.config/fastfetch" "$HOME/.config/fastfetch"

    log_info "Checking for Oh My Zsh..."
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log_warn "Oh My Zsh is already installed."
        return
    fi

    # KEEP_ZSHRC keeps the linked zshrc instead of writing the Oh My Zsh one
    log_info "Installing Oh My Zsh..."
    local script="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    RUNZSH=no CHSH=yes KEEP_ZSHRC=yes sh -c "$(curl -fsSL "$script")"
    log_info "Oh My Zsh installed successfully."
}

# Installs Vim with its vimrc and vim-plug.
_setup_vim() {
    install_pkg "vim"

    log_info "Linking vimrc..."
    link_config "$SETUP_DIR/.config/vimrc" "$HOME/.vimrc"

    log_info "Downloading vim-plug for Vim..."
    curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
        "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
}

# Installs the yazi terminal file manager.
_install_yazi() {
    log_info "Installing yazi..."
    install_pkg "yazi"
}

# The zshrc sets Vim as the editor (git commit, sudoedit...)
block shell _setup_shell "Zsh, Oh My Zsh, Starship, eza, bat, zoxide, fzf, fastfetch and their configs" \
    --needs vim

block vim  _setup_vim    "Vim with its vimrc and vim-plug"
block yazi _install_yazi "yazi terminal file manager"
