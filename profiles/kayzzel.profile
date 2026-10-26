# kayzzel's setup: vim keybindings, US layout with Caps Lock as Escape

block app.ghostty
block app.discord
block app.brave
block app.nautilus
block app.krita
block app.jetbrains
block app.yubico

block desktop*
block fonts
block wallpapers*

# dev
block neovim
block node
block python
block rust
block utils

# terminal
block shell
block tmux
block vim
block yazi

# settings
block git
block ssh
block timezone

# hardware
block audio
block bluetooth
block network
block nvidia
block securitykey

# virtualization
block qemu
block vm-guest

block dualboot*

config *

choice .config/hypr/conf/keybinds vim
choice .config/hypr/conf/keyboard vim
choice .config/waybar default
choice .config/zshrc kayzzel
choice .config/vimrc kayzzel
choice .config/nvim kayzzel
choice .config/tmux default
choice .config/local/bin kayzzel
