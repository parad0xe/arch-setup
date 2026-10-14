#!/bin/bash

# Installs pyenv with tk (for Python's tkinter; the other libraries it
# builds Python with come with the base system), the latest stable Python as
# the global version, uv, and the pyright, flake8 and mypy tools.
_setup_python() {
    local pkgs=(
        "tk"
        "uv"
        "pyenv"
    )

    log_info "Installing pyenv, uv and tk..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done

    log_info "Detecting latest stable Python version..."
    # Filter to get only numbers and avoid rc/dev versions
    local version=$(pyenv install --list | grep -v -E "[a-z]" | tail -1 | xargs)

    if ! pyenv versions | grep -q "$version"; then
        log_info "Installing Python $version (compilation may take time)..."
        pyenv install "$version"
        pyenv global "$version"
    else
        log_warn "Python $version is already installed."
    fi

    log_info "Installing Python dev tools (pyright, flake8, mypy)..."
    local tools=("pyright" "flake8" "mypy")
    for tool in "${tools[@]}"; do
        uv tool install "$tool"
    done
}

# Installs nvm and the latest Node.js as the default version.
_setup_node() {
    install_pkg "nvm"

    log_info "Configuring nvm and installing the latest Node.js..."
    source /usr/share/nvm/init-nvm.sh

    if ! command -v node > /dev/null 2>&1; then
        log_info "Node.js not found. Installing the latest version..."
        nvm install node
        nvm use node
        nvm alias default node
    else
        log_warn "Node.js is already installed ($(node -v))."
    fi
}

# Installs the Rust toolchain via rustup (stable by default).
_setup_rust() {
    log_info "Installing rustup..."
    install_pkg "rustup"

    log_info "Configuring default stable Rust toolchain..."
    # Configures cargo and rustc without prompting the user
    rustup default stable
}

# Installs Neovim with the tools its config runs: lazygit (<space>lg),
# ripgrep (Telescope live grep), tree-sitter-cli (Treesitter parsers) and
# unzip (Mason packages), links its config, then installs vim-plug and the
# plugins. Mason installs the language servers and linters with Python and
# npm.
_setup_neovim() {
    local pkgs=(
        "neovim"
        "lazygit"
        "ripgrep"
        "tree-sitter-cli"
        "unzip"
    )

    log_info "Installing Neovim and the tools its config runs..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done

    log_info "Linking Neovim config..."
    link_config "$SETUP_DIR/.config/nvim" "$HOME/.config/nvim"

    log_info "Downloading vim-plug for Neovim..."
    local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
    curl -fLo "$data_dir/nvim/site/autoload/plug.vim" --create-dirs \
        "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"

    log_info "Running PlugInstall for Neovim..."
    nvim +PlugInstall +qall > /dev/null 2>&1
}

block python _setup_python "Python via pyenv, uv, pyright, flake8, mypy"
block node   _setup_node   "nvm and the latest Node.js"
block rust   _setup_rust   "Rust toolchain via rustup"

# Mason installs the language servers and linters of the config with pip
# (Python) and npm (Node.js)
block neovim _setup_neovim "Neovim with its config, plugins and the tools they run" \
    --needs python \
    --needs node
