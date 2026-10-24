# shellcheck shell=bash
nik_play_python() { command -v python3 >/dev/null || nik_die 'Ta funkcja wymaga Python 3.'; }
nik_hud() {
    local player=$1 message
    shift
    message=$(python3 "$NIK_ROOT/tools/play.py" hud "$@") || return "$?"
    nik_rcon "title $player actionbar $message"
}
nik_cmd_guide() (
    (($# == 2 || $# == 3)) || nik_die 'Użycie: prowadz GRACZ MIEJSCE [CZAS, domyślnie 60s]'
    nik_player "$1"; local player=$REPLY name x y z dimension duration record result arrived message start
    nik_normalize_name "$2"; name=$REPLY; nik_id "$name"
    [[ -v NIK_PLACES[$name] ]] || nik_die 'Nieznane miejsce. Zobacz: punkt lista.'
    read -r x y z dimension <<< "${NIK_PLACES[$name]}"
    nik_duration "${3:-60s}" 1 600; duration=$REPLY
    nik_play_python
    if ((NIK_DRY_RUN)); then
        nik_message 1 gold '[podgląd] prowadzenie do %s przez maks. %s s, odczyt co 2 s\n' "$name" "$duration"
        nik_hud "$player" "Cel: $name | kierunek i odległość"; return
    fi
    nik_family_dir guidance "$NIK_STATE" || return "$?"
    [[ ! -L $REPLY/$player.lock ]] || nik_die 'Blokada prowadzenia jest dowiązaniem.'
    exec 8> "$REPLY/$player.lock"; flock -n 8 || nik_die 'Ten gracz ma już aktywne prowadzenie.'
    nik_message 1 success 'Prowadzenie do %s. Ctrl+C zatrzymuje; maksymalnie %s s.\n' "$name" "$duration"
    start=$SECONDS
    while :; do
        record=$(nik_location_capture "$player") || return "$?"
        result=$(printf '%s\n' "$record" | python3 "$NIK_ROOT/tools/play.py" guide "$player" "$NIK_CONTAINER" "$x" "$y" "$z" "$dimension") || return "$?"
        IFS=$'\t' read -r arrived message <<< "$result"
        nik_hud "$player" "$name: $message" || return "$?"
        if [[ $arrived == 1 ]]; then nik_message 1 success 'Cel w pobliżu. Sprawdź wysokość podaną w grze.\n'; return; fi
        ((SECONDS-start+2 < duration)) || break
        sleep 2
    done
    nik_message 1 muted 'Zakończono prowadzenie. Możesz uruchomić je ponownie.\n'
)
nik_cmd_countdown() {
    (($# >= 2)) || nik_die 'Użycie: odliczanie GRACZ SEKUNDY [TEKST, domyślnie Start!]'
    nik_player "$1"; local player=$REPLY seconds text json i
    nik_uint "$2" 1 60; seconds=$REPLY; shift 2
    text=${*:-Start!}; nik_play_python
    json=$(python3 "$NIK_ROOT/tools/play.py" hud "$text") || return "$?"
    nik_rcon "title $player times 0 25 0" || return "$?"
    # Clear an earlier subtitle before starting a new title sequence.
    nik_rcon "title $player subtitle {\"text\":\"\"}" || return "$?"
    for ((i=seconds; i>0; i--)); do
        nik_rcon "title $player title {\"text\":\"$i\",\"color\":\"gold\",\"bold\":true}" || return "$?"
        if (( !NIK_DRY_RUN )); then sleep 1; fi
    done
    nik_rcon "title $player times 0 60 10" || return "$?"
    nik_rcon "title $player title $json"
}
nik_cmd_random() {
    nik_args 1 "$@"; nik_player "$1"
    local file=$NIK_CONFIG/challenges.txt text
    nik_play_python
    if [[ ! -e $file && ! -L $file ]]; then file=$NIK_ROOT/data/challenges.txt; fi
    text=$(python3 "$NIK_ROOT/tools/play.py" challenge "$file") || return "$?"
    nik_message 1 gold 'Wylosowane wyzwanie: %s\n' "$text"
    nik_cmd_quest "$1" "$text"
}
nik_reward_file() {
    nik_normalize_name "$1"; local name=$REPLY
    nik_id "$name"
    REPLY=$NIK_CONFIG/rewards/$name.tsv
    [[ ! -L $NIK_CONFIG/rewards ]] || nik_die 'Katalog nagród jest dowiązaniem.'
    if [[ ! -e $REPLY && ! -L $REPLY ]]; then REPLY=$NIK_ROOT/data/rewards/$name.tsv; fi
}
nik_reward_names() {
    local file
    for file in "$NIK_ROOT"/data/rewards/*.tsv "$NIK_CONFIG"/rewards/*.tsv; do
        [[ -f $file && ! -L $file ]] || continue
        file=${file##*/}; printf '%s\n' "${file%.tsv}"
    done | LC_ALL=C sort -u
}
nik_cmd_reward() {
    if [[ ${1:-} == lista ]]; then nik_args 1 "$@"; nik_section 'NAGRODY OD TATY'; nik_reward_names; return; fi
    nik_args 2 "$@"; nik_player "$1"; local player=$REPLY rows item count title name
    nik_normalize_name "$2"; name=$REPLY
    nik_reward_file "$name"; nik_play_python
    # Validate every row before the first give; failure cannot give a partial invalid preset.
    rows=$(python3 "$NIK_ROOT/tools/play.py" rewards "$REPLY" "$NIK_ROOT/data/items.tsv") || return "$?"
    title=$(python3 "$NIK_ROOT/tools/dad-message.py" title "Brawo! Nagroda: ${name//_/ }") || return "$?"
    while IFS=$'\t' read -r item count; do nik_rcon "give $player minecraft:$item $count" || return "$?"; done <<< "$rows"
    nik_rcon "title $player times 10 80 20" || return "$?"
    nik_rcon "title $player subtitle {\"text\":\"Od Taty ♥\",\"color\":\"aqua\"}" || return "$?"
    nik_rcon "title $player title $title"
}
nik_cmd_recipe() {
    nik_args 1 "$@"; nik_item "$1"; local item=$REPLY lines line
    nik_play_python
    lines=$(python3 "$NIK_ROOT/tools/play.py" recipe "$NIK_ROOT" "$item") || return "$?"
    nik_panel "RECEPTURA: ${NIK_ITEM_NAMES_BY_ID[$item]}" 'Minecraft Java 26.3 • receptury podstawowej gry'
    while IFS= read -r line; do
        if [[ -z $line ]]; then printf '\n'; else nik_ui_text "$line"; fi
    done <<< "$lines"
}
