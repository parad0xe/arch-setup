# Path to your oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="robbyrussell" 

# Plugins (fzf is often managed manually, but git is essential)
plugins=(git z)

source $ZSH/oh-my-zsh.sh

# --- CUSTOM ALIASES ---
alias ls="eza --icons always --group-directories-first"
alias ll="eza -lah --icons always --group-directories-first"
alias cat="bat -p"
alias tree="tree -a --dirsfirst -I .git/"
alias cdmk="cd $(mktemp -d)"
alias py="python3"
if command -v nvim > /dev/null; then
    alias vim="nvim"
fi
# hyprmon saves the monitor layout here instead of in the dotfiles
# (loaded by .config/hypr/conf/monitors.lua)
alias hyprmon='HYPRLAND_CONFIG="$HOME/.config/hyprmon/hyprland.lua" hyprmon'

export PATH="/usr/local/go/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

export EDITOR="vim"
export VISUAL="vim"
export SUDO_EDITOR="vim"

# --- PYENV ---
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv > /dev/null; then
    eval "$(pyenv init -)"
fi

# --- NVM ---
if [ -f /usr/share/nvm/init-nvm.sh ]; then
    source /usr/share/nvm/init-nvm.sh
fi

# --- TOOL INITIALIZATION ---
# Initialize zoxide (smart cd)
eval "$(zoxide init zsh)"

# Enable fzf keybindings and fuzzy completion
source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh

# Activer l'auto-suggestion (historique en gris clair)
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# Initialiser le moteur de thème Starship
eval "$(starship init zsh)"

# Activer la coloration syntaxique (commandes en vert/rouge)
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# glg (.config/local/bin) instead of the git plugin's alias, with git log
# completion
if [ -f "$HOME/.local/bin/glg" ]; then
    unalias glg 2> /dev/null
    compdef _git glg=git-log
fi

fastfetch

if [ -f "$HOME/.local/bin/env" ]; then
    . "$HOME/.local/bin/env"
fi
