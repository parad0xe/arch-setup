# The fish config of the fish unit: the tools of the shell unit, and the same
# habits as the zshrc. Copied into the home: its edits stay out of the
# repository.

if status is-interactive
    set -gx EDITOR vim
    set -gx SUDO_EDITOR vim

    alias ls "eza --icons always --group-directories-first"
    alias ll "eza -lah --icons always --group-directories-first"
    alias cat "bat -p"

    type -q zoxide; and zoxide init fish | source
    type -q fzf; and fzf --fish | source
    type -q starship; and starship init fish | source
    type -q fastfetch; and fastfetch
end
