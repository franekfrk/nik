# shellcheck shell=bash
nik_player() {
    local name=${1,,}
    nik_id "$name"
    name=${NIK_ALIASES[$name]:-$name}
    [[ -v NIK_PLAYERS[$name] ]] || { nik_suggest "$name" "${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}"; nik_die "Nieznany gracz: $1"; }
    REPLY=${NIK_PLAYERS[$name]}
}
nik_cmd_player_status() {
    (($# <= 2)) || nik_die 'Użycie: stan [GRACZ|lista] [json]'
    local target=${1:-lista} format=${2:-tekst} list player name connected health food mode pos dimension row
    local -a names=() records=()
    [[ $format == json || $format == tekst ]] || nik_die 'Format stanu: tekst lub json.'
    if [[ $target == lista ]]; then
        mapfile -t names < <(printf '%s\n' "${!NIK_PLAYERS[@]}" | LC_ALL=C sort)
    else nik_player "$target"; names=("${NIK_ALIASES[${target,,}]:-${target,,}}"); fi
    command -v python3 >/dev/null || nik_die 'Stan graczy wymaga Python 3.'
    if ((NIK_DRY_RUN)); then
        nik_rcon list
        for name in "${names[@]}"; do
            for row in Health foodLevel playerGameType Pos Dimension; do nik_rcon "data get entity ${NIK_PLAYERS[$name]} $row"; done
        done
        return
    fi
    nik_rcon list >/dev/null || return "$?"; list=$NIK_RCON_RESPONSE
    for name in "${names[@]}"; do
        player=${NIK_PLAYERS[$name]}
        connected=$(python3 "$NIK_ROOT/tools/player-status.py" online "$player" "$list") || return "$?"
        if [[ $connected == false ]]; then
            row=$(python3 "$NIK_ROOT/tools/player-status.py" offline "$name") || return "$?"
        elif nik_rcon "data get entity $player Health" >/dev/null 2>&1 && health=$NIK_RCON_RESPONSE &&
             nik_rcon "data get entity $player foodLevel" >/dev/null 2>&1 && food=$NIK_RCON_RESPONSE &&
             nik_rcon "data get entity $player playerGameType" >/dev/null 2>&1 && mode=$NIK_RCON_RESPONSE &&
             nik_rcon "data get entity $player Pos" >/dev/null 2>&1 && pos=$NIK_RCON_RESPONSE &&
             nik_rcon "data get entity $player Dimension" >/dev/null 2>&1 && dimension=$NIK_RCON_RESPONSE; then
            row=$(python3 "$NIK_ROOT/tools/player-status.py" snapshot "$name" "$health" "$food" "$mode" "$pos" "$dimension") || return "$?"
        else
            row=$(python3 "$NIK_ROOT/tools/player-status.py" error "$name") || return "$?"
        fi
        records+=("$row")
    done
    printf '%s\n' "${records[@]}" | python3 "$NIK_ROOT/tools/player-status.py" collect "$format"
}
