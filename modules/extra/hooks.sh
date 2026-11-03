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

# yt-dlp-git and yt-dlp-ejs-anyruntime, its JavaScript challenge solver for
# any runtime (Node.js here: the official yt-dlp-ejs needs Deno), from the
# AUR without their check phase. They replace the official yt-dlp and
# yt-dlp-ejs, which conflict with them: --ask 4 answers yes to removing a
# conflicting package, in the same transaction, which --noconfirm refuses.
install_yt_dlp() {
    log_info "install yt-dlp-git and yt-dlp-ejs-anyruntime from the AUR (check phase skipped)"
    yay -S --needed --noconfirm --ask 4 yt-dlp-ejs-anyruntime yt-dlp-git --mflags --nocheck
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
