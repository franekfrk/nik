# shellcheck shell=bash
nik_location_python() { command -v python3 >/dev/null || nik_die 'Pozycja i powrót wymagają Python 3.'; }
nik_location_capture() {
    local player=$1 pos dimension rotation
    nik_location_python
    nik_rcon "data get entity $player Pos" >/dev/null || return "$?"; pos=$NIK_RCON_RESPONSE
    nik_rcon "data get entity $player Dimension" >/dev/null || return "$?"; dimension=$NIK_RCON_RESPONSE
    nik_rcon "data get entity $player Rotation" >/dev/null || return "$?"; rotation=$NIK_RCON_RESPONSE
    python3 "$NIK_ROOT/tools/location.py" capture "$player" "$NIK_CONTAINER" "$pos" "$dimension" "$rotation"
}
nik_cmd_where() {
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY record point x y z dimension yaw pitch
    if ((NIK_DRY_RUN)); then
        nik_rcon "data get entity $player Pos"; nik_rcon "data get entity $player Dimension"; nik_rcon "data get entity $player Rotation"; return
    fi
    record=$(nik_location_capture "$player") || return "$?"
    # A private temporary file avoids evaluating or sourcing RCON output.
    point=$(umask 077; mktemp) || return "$?"
    printf '%s\n' "$record" > "$point"
    local fields rc=0
    fields=$(python3 "$NIK_ROOT/tools/location.py" read "$point" "$player" "$NIK_CONTAINER") || rc=$?
    rm -f -- "$point"
    ((rc == 0)) || return "$rc"
    IFS=$'\t' read -r x y z dimension yaw pitch <<< "$fields"
    nik_message 1 title '\nPOZYCJA GRACZA: %s\n' "$1"
    nik_message 1 command '  X: %s   Y: %s   Z: %s\n' "$x" "$y" "$z"
    nik_message 1 gold '  Wymiar: %s\n' "$dimension"
    nik_message 1 muted '  Kierunek: %s°   Nachylenie: %s°\n\n' "$yaw" "$pitch"
}
nik_travel_directory() {
    local directory=$NIK_STATE
    [[ ! -L $directory && ! -L $directory/returns ]] || nik_die 'Katalog powrotów nie może być dowiązaniem.'
    umask 077
    mkdir -p -- "$directory/returns" || return "$?"
    chmod 700 -- "$directory" "$directory/returns" || return "$?"
    REPLY=$directory/returns
}
nik_teleport() (
    local player=$1 command=$2 directory record pending moved=0
    if ((NIK_DRY_RUN)); then
        nik_message 1 gold '[podgląd] zapamiętanie pozycji sprzed teleportacji\n'
        nik_rcon "$command"; return
    fi
    nik_location_python
    nik_travel_directory || return "$?"; directory=$REPLY
    record=$directory/$player.json
    [[ ! -L $record && ! -L $directory/$player.uncertain.json && ! -L $directory/$player.lock ]] || nik_die 'Punkt powrotu lub blokada jest dowiązaniem.'
    exec 8> "$directory/$player.lock"
    nik_lock 8 || return "$?"
    # Prepare a validated record on the same filesystem before teleporting.
    pending=$(mktemp "$directory/.pending.XXXXXX") || return "$?"
    trap 'if (( !moved )); then rm -f -- "$pending"; fi' EXIT
    nik_location_capture "$player" > "$pending" || return "$?"
    local rc=0
    nik_rcon "$command" || rc=$?
    if ((rc)); then
        if [[ ${NIK_RCON_UNCERTAIN:-0} == 1 ]]; then
            moved=1
            mv -f -- "$pending" "$directory/$player.uncertain.json" || { nik_message 2 error 'NIK: zachowano awaryjny punkt powrotu w %s.\n' "$pending"; return "$rc"; }
            if [[ -n ${NIK_RESULT_PATH:-} ]]; then
                printf '%s' "${NIK_RCON_ERROR_RESPONSE:-}" | python3 "$NIK_ROOT/tools/result_data.py" error teleport_uncertain 'Wynik teleportacji jest niepewny. Zapisano pozycję wyjściową; po odzyskaniu RCON użyj polecenia powrot.' || true
            fi
            nik_message 2 error 'NIK: wynik teleportacji jest niepewny. Zapisano pozycję wyjściową; po odzyskaniu RCON użyj powrot GRACZ.\n'
        fi
        return "$rc"
    fi
    moved=1
    mv -f -- "$pending" "$record" || { nik_message 2 error 'NIK: teleport wykonany; zachowano punkt odzyskiwania w %s.\n' "$pending"; return 1; }
    rm -f -- "$directory/$player.uncertain.json"
)
nik_cmd_back() (
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY directory record fields x y z dimension yaw pitch
    nik_location_python
    directory=$NIK_STATE/returns; record=$directory/$player.json
    [[ ! -L $NIK_STATE && ! -L $directory && ! -L $record && ! -L $directory/$player.uncertain.json && ! -L $directory/$player.lock ]] || nik_die 'Punkt powrotu jest dowiązaniem.'
    if [[ -f $directory/$player.uncertain.json ]]; then record=$directory/$player.uncertain.json; fi
    [[ -f $record ]] || nik_die 'Brak punktu powrotu. Najpierw teleportuj gracza przez NIK.'
    if (( !NIK_DRY_RUN )); then
        umask 077
        exec 8> "$directory/$player.lock" || return "$?"; nik_lock 8 || return "$?"
    fi
    fields=$(python3 "$NIK_ROOT/tools/location.py" read "$record" "$player" "$NIK_CONTAINER") || return "$?"
    IFS=$'\t' read -r x y z dimension yaw pitch <<< "$fields"
    nik_rcon "execute in $dimension run tp $player $x $y $z $yaw $pitch" || return "$?"
    # Consume only after a confirmed return; errors retain the recovery point.
    if (( !NIK_DRY_RUN )); then rm -f -- "$record" || return "$?"; fi
)
nik_cmd_dad() {
    (($# >= 2)) || nik_die 'Użycie: tata GRACZ TREŚĆ...'
    nik_player "$1"; local player=$REPLY message; shift
    command -v python3 >/dev/null || nik_die 'Wiadomości wymagają Python 3.'
    message=$(python3 "$NIK_ROOT/tools/dad-message.py" chat "$@") || return "$?"
    nik_rcon "tellraw $player $message"
}

# Vanilla selects a valid surface with two free blocks and its teleportable
# block tag. Under 96 avoids the tops of tall End builds and obsidian towers.
nik_tp_end() {
    local player=$1
    nik_message 1 command 'NIK: szukam miejsca do lądowania na głównej wyspie Endu.\n'
    nik_teleport "$player" "execute in minecraft:the_end run spreadplayers 16 0 0 8 under 96 false $player"
}
