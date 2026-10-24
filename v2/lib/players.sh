# shellcheck shell=bash
nik_player() {
    local name=${1,,}
    nik_id "$name"
    name=${NIK_ALIASES[$name]:-$name}
    [[ -v NIK_PLAYERS[$name] ]] || { nik_suggest "$name" "${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}"; nik_die "Nieznany gracz: $1"; }
    REPLY=${NIK_PLAYERS[$name]}
}
