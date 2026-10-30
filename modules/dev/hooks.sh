#!/bin/bash
# Hooks of modules/dev.toml, run by lib/hook.sh.

# Installs the latest stable Python with pyenv as the global version, and
# the pyright, flake8 and mypy tools with uv.
setup_python() {
    log_info "Detecting the latest stable Python version..."
    # Numbers only: no rc or dev versions
    local version
    version=$(pyenv install --list | grep -v -E "[a-z]" | tail -1 | xargs)

    if ! pyenv versions | grep -q "$version"; then
        log_info "Installing Python $version (compilation may take time)..."
        pyenv install "$version"
        pyenv global "$version"
    else
        log_warn "Python $version is already installed."
    fi

    log_info "Installing the Python dev tools (pyright, flake8, mypy)..."
    local tool
    for tool in pyright flake8 mypy; do
        uv tool install "$tool"
    done
}

# Installs the latest Node.js with nvm as the default version.
setup_node() {
    log_info "Configuring nvm and installing the latest Node.js..."
    source /usr/share/nvm/init-nvm.sh

    if command -v node > /dev/null 2>&1; then
        log_warn "Node.js is already installed ($(node -v))."
        return 0
    fi

    log_info "Installing the latest Node.js..."
    nvm install node
    nvm use node
    nvm alias default node
}

# Makes stable the default Rust toolchain.
setup_rust() {
    log_info "Configuring the default stable Rust toolchain..."
    rustup default stable
}

# Downloads vim-plug and installs the plugins of the Neovim config. Mason
# then installs its language servers and linters with pip (Python) and npm
# (Node.js).
install_nvim_plugins() {
    log_info "Downloading vim-plug for Neovim..."
    local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
    curl -fLo "$data_dir/nvim/site/autoload/plug.vim" --create-dirs \
        "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"

    # Headless: Neovim runs without its interface, its output goes to the
    # log of the step
    log_info "Running PlugInstall for Neovim..."
    nvim --headless +PlugInstall +qall
}
