#!/bin/bash

# Installs pyenv for Python version management.
_setup_python() {
	install_pkg "uv"
    install_pkg "pyenv"

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

# Installs nvm from AUR and sets up the latest Node.js version.
_setup_node() {
    install_aur_pkg "nvm"

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

# Installs Rust toolchain via rustup and tree-sitter CLI.
_setup_rust() {
    log_info "Installing rustup and tree-sitter-cli..."
    local pkgs=(
        "rustup"
        "tree-sitter-cli"
    )
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done

    log_info "Configuring default stable Rust toolchain..."
    # Configures cargo and rustc without prompting the user
    rustup default stable
}

_setup_tui_ide() {
	install_pkg "neovim"

	log_info "Downloading vim-plug..."
    local url="https://raw.githubusercontent.com/junegunn"
    url="$url/vim-plug/master/plug.vim"
    
    # For Neovim
    local nvim_dest="${XDG_DATA_HOME:-$HOME/.local/share}"
    nvim_dest="$nvim_dest/nvim/site/autoload/plug.vim"
    curl -fLo "$nvim_dest" --create-dirs "$url"
    
    # For standard Vim
    local vim_dest="$HOME/.vim/autoload/plug.vim"
    curl -fLo "$vim_dest" --create-dirs "$url"

    log_info "Running PlugInstall for Neovim..."
    nvim +PlugInstall +qall > /dev/null 2>&1
}

# Entry point for the development tools module.
setup() {
	run_task "Installing Neovim Environment..." _setup_tui_ide
	run_task "Installing Python Environment..." _setup_python
    run_task "Installing Node.js Environment..." _setup_node
    run_task "Installing Rust Environment..." _setup_rust
}
