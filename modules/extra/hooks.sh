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

install_mutagen() {
    pip install mutagen
}

# Enables MPD as a user service, which starts it with each login, and
# restarts it so that it applies its deployed config. Never the system unit:
# it runs as user mpd with /etc/mpd.conf, cannot reach the user's music or
# PipeWire session, and takes port 6600 so the user service could never
# start. Without a reachable user manager (a chroot install), the service is
# enabled by its link, as systemctl would, and starts at the next login.
start_mpd_user_service() {
    if ! systemctl --user show-environment &> /dev/null; then
        log_info "no user session: enabling mpd for the next login"
        mkdir -p "$HOME/.config/systemd/user/default.target.wants"
        ln -sf /usr/lib/systemd/user/mpd.service "$HOME/.config/systemd/user/default.target.wants/mpd.service"
        return 0
    fi
    log_info "enabling the mpd user service and restarting it on its config"
    systemctl --user enable mpd.service
    systemctl --user restart mpd.service
}
