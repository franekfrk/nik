# shellcheck shell=bash
declare -A NIK_CREATURES=() NIK_CREATURE_IDS=() NIK_CREATURE_ALIASES=()
while IFS=$'\t' read -r key value; do NIK_CREATURES[$key]=$value; NIK_CREATURE_IDS[$value]=1; done < "$NIK_ROOT/data/creatures.tsv"
while IFS=$'\t' read -r key value; do NIK_CREATURE_ALIASES[$key]=$value; done < "$NIK_ROOT/data/creature-aliases.tsv"
unset key value
nik_creature() {
    nik_normalize_name "$1"; local creature=${REPLY#minecraft:}; nik_id "$creature"
    if [[ -v NIK_CREATURES[$creature] ]]; then REPLY=${NIK_CREATURES[$creature]}
    elif [[ -v NIK_CREATURE_ALIASES[$creature] ]]; then REPLY=${NIK_CREATURE_ALIASES[$creature]}
    elif [[ -v NIK_CREATURE_IDS[$creature] ]]; then REPLY=$creature
    else nik_suggest "$creature" "${!NIK_CREATURES[@]}" "${!NIK_CREATURE_IDS[@]}"; nik_die "Nieznane stworzenie: $1"; fi
}
nik_cmd_summon() {
    if [[ ${1:-} == co || ${1:-} == lista ]]; then nik_args 1 "$@"; nik_table "$NIK_ROOT/data/creatures.tsv" creatures; return; fi
    nik_args 2 "$@"; nik_player "$1"; local player=$REPLY creature
    nik_creature "$2"; creature=$REPLY
    if [[ $creature == wither || $creature == ender_dragon ]] && (( !NIK_CONFIRM && !NIK_DRY_RUN )); then nik_die 'Przywołanie bossa wymaga --potwierdz. Najpierw możesz użyć --podglad.'; fi
    nik_rcon "execute at $player run summon minecraft:$creature ~2 ~ ~"
}
nik_cmd_point() {
    if [[ ${1:-} == lista ]]; then nik_args 1 "$@"; nik_cmd_place lista; return; fi
    if [[ ${1:-} == usun ]]; then nik_cmd_point_delete "$@"; return; fi
    nik_args 2 "$@"; nik_player "$1"; local player=$REPLY name record fields x y z dimension yaw pitch
    nik_normalize_name "$2"; name=$REPLY; nik_id "$name"
    [[ ! -v NIK_PLACES[$name] && ! -v NIK_PLAYERS[$name] && ! -v NIK_ALIASES[$name] ]] || nik_die 'Miejsce już istnieje lub nazwa koliduje z graczem.'
    if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] odczyt pozycji gracza i zapis punktu %s\n' "$name"; return; fi
    record=$(nik_location_capture "$player") || return "$?"
    fields=$(printf '%s\n' "$record" | python3 "$NIK_ROOT/tools/location.py" fields "$player" "$NIK_CONTAINER") || return "$?"
    IFS=$'\t' read -r x y z dimension yaw pitch <<< "$fields"
    nik_cmd_place dodaj "$name" "$x" "$y" "$z" "$dimension" || return "$?"
    nik_message 1 success 'Zapisano punkt: %s\n' "$name"
    nik_message 1 command 'Teleport: tp %s %s\n' "$1" "$name"
}
nik_cmd_title() {
    (($# >= 2)) || nik_die 'Użycie: napis GRACZ TREŚĆ...'
    nik_player "$1"; local player=$REPLY message; shift
    command -v python3 >/dev/null || nik_die 'Napisy wymagają Python 3.'
    message=$(python3 "$NIK_ROOT/tools/dad-message.py" title "$@") || return "$?"
    # Configure timing and subtitle before displaying a new title.
    nik_rcon "title $player times 10 80 20" || return "$?"
    nik_rcon "title $player subtitle {\"text\":\"Od Taty ♥\",\"color\":\"aqua\",\"bold\":false}" || return "$?"
    nik_rcon "title $player title $message"
}
nik_cmd_inventory() {
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY rows
    command -v python3 >/dev/null || nik_die 'Podgląd plecaka wymaga Python 3.'
    if ((NIK_DRY_RUN)); then nik_rcon "data get entity $player Inventory"; return; fi
    nik_rcon "data get entity $player Inventory" >/dev/null || return "$?"
    rows=$(printf '%s\n' "$NIK_RCON_RESPONSE" | python3 "$NIK_ROOT/tools/inventory.py") || return "$?"
    nik_inventory_table "$1" "$rows"
}
nik_inventory_table() {
    local player=$1 rows=$2 heading=${3:-PLECAK GRACZA} empty=${4:-Plecak i pasek są puste.} slot name count details part width=${NIK_WIDTH:-120} name_width
    if [[ -t 1 && ! -v NIK_WIDTH ]]; then width=$(tput cols 2>/dev/null) || width=80; fi
    [[ $width =~ ^[0-9]{2,3}$ ]] || width=120
    width=$((10#$width)); ((width >= 40)) || width=40
    name_width=$((width-23))
    nik_section "$heading: $player"
    if [[ -z $rows ]]; then nik_message 1 muted '  %s\n\n' "$empty"; return; fi
    nik_message 1 gold '  %-12s  %-*s  %5s\n' 'SLOT' "$name_width" 'PRZEDMIOT' 'ILOŚĆ'
    while IFS=$'\t' read -r slot name count details; do
        part=${name:0:name_width}; name=${name:name_width}
        nik_message 1 muted '  %-12s  ' "$slot"
        nik_message 1 command '%-*s  ' "$name_width" "$part"
        nik_message 1 success '%5s\n' "$count"
        while [[ -n $name ]]; do part=${name:0:name_width}; name=${name:name_width}; nik_message 1 command '                %s\n' "$part"; done
        if [[ -n $details ]]; then
            while IFS= read -r part; do nik_message 1 gold '                %s\n' "$part"; done < <(nik_wrap_text "$details" "$((width-16))")
        fi
    done <<< "$rows"
    printf '\n'
}
