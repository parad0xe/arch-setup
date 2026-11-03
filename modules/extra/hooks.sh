create_mpd_folders() {
    log_info "create mpd folders"
    mkdir -p    ~/Music/Playlists/ \
                ~/.local/share/mpd
}

# MPD does not expand ~ in its config: the repository file ships ~ so it
# stays portable, and this hook writes the home folder into the deployed
# copy. Idempotent: nothing left to replace on a second run.
expand_mpd_paths() {
    log_info "expanding ~ to absolute paths in the deployed mpd config"
    sed -i "s|\"~/|\"${HOME}/|g" "$HOME/.config/mpd/mpd.conf"
}

create_getmusic_folders() {
    log_info "create folders for getmusic"
    mkdir -p ~/Music/Playlists \
             ~/.local/share/beets \
             ~/.local/share/getmusic/inbox \
             ~/.local/bin
}

install_yt_dlp_git() {
    log_info "install yt-dlp-git from the AUR (check phase skipped)"
    yay -S --needed --noconfirm yt-dlp-git --mflags --nocheck
}

# Enables and starts MPD as a user service. Never the system unit: it runs
# as user mpd with /etc/mpd.conf, cannot reach the user's music or PipeWire
# session, and takes port 6600 so the user service could never start.
# Without a user session (a TTY install), systemctl --user cannot connect:
# the Hyprland autostart (conf/autostart/music.lua) starts mpd at login.
start_mpd_user_service() {
    if [ -z "${XDG_RUNTIME_DIR-}" ]; then
        log_info "no user session: mpd starts with the next login"
        return 0
    fi
    log_info "enabling the mpd user service"
    systemctl --user enable --now mpd.service
}
