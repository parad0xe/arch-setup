# Oh My Zsh, the prompt being drawn by Starship
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git)
source "$ZSH/oh-my-zsh.sh"

# --- ALIASES ---
alias ls="eza --icons always --group-directories-first"
alias ll="eza -lah --icons always --group-directories-first"
alias cat="bat -p"
# hyprmon saves the monitor layout here instead of in the dotfiles
# (loaded by .config/hypr/conf/monitors.lua)
alias hyprmon='HYPRLAND_CONFIG="$HOME/.config/hyprmon/hyprland.lua" hyprmon'

export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

export EDITOR="vim"
export VISUAL="vim"
export SUDO_EDITOR="vim"

# --- PYENV AND NVM (python and node blocks) ---
if command -v pyenv > /dev/null; then
    eval "$(pyenv init -)"
fi
if [ -f /usr/share/nvm/init-nvm.sh ]; then
    source /usr/share/nvm/init-nvm.sh
fi

# --- TOOLS ---
eval "$(zoxide init zsh)"
source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
eval "$(starship init zsh)"
# Sourced last, as zsh-syntax-highlighting requires
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

command -v fastfetch > /dev/null && fastfetch
