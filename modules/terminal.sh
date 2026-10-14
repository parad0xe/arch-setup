#!/bin/bash

module "Shell and terminal tools"

# Installs Zsh with Oh My Zsh, its plugins (autosuggestions, syntax
# highlighting), the Starship prompt and the tools the zshrc runs (eza, bat,
# zoxide, fzf, fastfetch).
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

    log_info "Checking for Oh My Zsh..."
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log_warn "Oh My Zsh is already installed."
        return
    fi

    # KEEP_ZSHRC keeps an existing zshrc instead of writing the Oh My Zsh one
    log_info "Installing Oh My Zsh..."
    local script="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    RUNZSH=no CHSH=yes KEEP_ZSHRC=yes sh -c "$(curl -fsSL "$script")"
    log_info "Oh My Zsh installed successfully."
}

# Installs Vim and vim-plug.
_setup_vim() {
    install_pkg "vim"

    log_info "Downloading vim-plug for Vim..."
    curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
        "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
}

# Installs the yazi terminal file manager.
_install_yazi() {
    log_info "Installing yazi..."
    install_pkg "yazi"
}

block shell _setup_shell   "Zsh, Oh My Zsh, Starship, eza, bat, zoxide, fzf, fastfetch"
block vim   _setup_vim     "Vim and vim-plug"
block yazi  _install_yazi  "yazi terminal file manager"

# It sets Vim as the editor (git commit, sudoedit...)
config zshrc .config/zshrc .zshrc "Zsh: Oh My Zsh plugins, aliases, prompt, tools" --block shell \
    --program zsh \
    --needs vim

config starship .config/starship/nerd-font-symbols.toml .config/starship.toml "Starship prompt with Nerd Font symbols" --block shell \
    --program starship

config fastfetch .config/fastfetch .config/fastfetch "fastfetch system summary" --block shell \
    --program fastfetch

config vimrc .config/vimrc .vimrc "Vim settings" --block vim \
    --program vim
