# shellcheck shell=bash
nik_duration() {
    local input=${1,,} amount multiplier=1
    [[ $input =~ ^([0-9]{1,8})([smh]?)$ ]] || nik_die 'Czas: liczba sekund albo np. 30s, 10m, 1h.'
    amount=$((10#${BASH_REMATCH[1]}))
    case ${BASH_REMATCH[2]} in m) multiplier=60 ;; h) multiplier=3600 ;; esac
    REPLY=$((amount*multiplier))
    ((REPLY >= $2 && REPLY <= $3)) || nik_die "Czas poza zakresem $2–$3 sekund."
}
nik_cmd_rescue() {
    (($# == 1 || $# == 2)) || nik_die 'Użycie: ratunek GRACZ [MIEJSCE]'
    nik_player "$1"; local player=$REPLY place=${2:-dom}
    nik_normalize_name "$place"; place=$REPLY; nik_id "$place"
    [[ -v NIK_PLACES[$place] ]] || nik_die 'Brak miejsca ratunku. Zapisz bezpieczny punkt przez punkt GRACZ NAZWA.'
    nik_rcon "effect give $player minecraft:fire_resistance 30 0 true" || return "$?"
    nik_cmd_health "$1" || return "$?"
    nik_cmd_tp "$1" "$place" || return "$?"
    nik_cmd_thaw "$1" || return "$?"
    nik_message 1 success 'Ratunek: miejsce %s, leczenie i ochrona przed ogniem na 30 s.\n' "$place"
}
nik_cmd_repair() {
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY result
    command -v python3 >/dev/null || nik_die 'Naprawa wymaga Python 3.'
    if (( !NIK_DRY_RUN )); then
        nik_rcon "data get entity $player SelectedItem" >/dev/null || return "$?"
        result=$(printf '%s\n' "$NIK_RCON_RESPONSE" | python3 "$NIK_ROOT/tools/inventory.py" --damage) || return "$?"
        if [[ $result == 0 ]]; then nik_message 1 muted 'Przedmiot nie ma zapisanych uszkodzeń.\n'; return; fi
    fi
    nik_rcon "item modify entity $player weapon.mainhand {type:\"minecraft:set_damage\",damage:1.0,add:false}"
}
nik_cmd_ender() {
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY rows
    command -v python3 >/dev/null || nik_die 'Podgląd Ender Chest wymaga Python 3.'
    if ((NIK_DRY_RUN)); then nik_rcon "data get entity $player EnderItems"; return; fi
    nik_rcon "data get entity $player EnderItems" >/dev/null || return "$?"
    rows=$(printf '%s\n' "$NIK_RCON_RESPONSE" | python3 "$NIK_ROOT/tools/inventory.py" --ender) || return "$?"
    nik_inventory_table "$1" "$rows" 'SKRZYNIA ENDERA' 'Skrzynia Endera jest pusta.'
}
nik_cmd_fireworks() {
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY color
    nik_rcon "execute at $player run particle minecraft:firework ~ ~3 ~ 1 1 1 0.15 60 force $player" || return "$?"
    for color in '1.0,0.2,0.2' '0.2,1.0,0.3' '0.3,0.5,1.0'; do
        nik_rcon "execute at $player run particle minecraft:dust{color:[$color],scale:1.5} ~ ~3 ~ 1.2 1.2 1.2 0 30 force $player" || return "$?"
    done
    nik_rcon "execute at $player run playsound minecraft:entity.firework_rocket.blast master $player ~ ~ ~ 0.7 1" || return "$?"
    nik_rcon "execute at $player run playsound minecraft:entity.firework_rocket.twinkle master $player ~ ~ ~ 0.5 1.2"
}
nik_family_dir() {
    local name=$1 base=$2
    [[ ! -L $base && ! -L $base/$name ]] || nik_die 'Katalog danych nie może być dowiązaniem.'
    umask 077
    mkdir -p -- "$base/$name" || return "$?"
    chmod 700 -- "$base/$name" || return "$?"
    REPLY=$base/$name
}
nik_cmd_quest() (
    (($# >= 1)) || nik_die 'Użycie: zadanie GRACZ [TREŚĆ | pokaz | ksiazka | gotowe | usun]'
    nik_player "$1"; local player=$REPLY action=${2:-pokaz} file directory pending fields status text book rc=0
    command -v python3 >/dev/null || nik_die 'Zadania wymagają Python 3.'
    file=$NIK_CONFIG/quests/$player.json
    [[ ! -L $NIK_CONFIG/quests && ! -L $file ]] || nik_die 'Zadanie nie może być dowiązaniem.'
    case $action in pokaz|ksiazka|gotowe|usun) (($# <= 2)) || nik_die 'Za dużo argumentów zadania.' ;; *) action=nowe ;; esac
    if [[ $action != nowe ]]; then [[ -f $file ]] || nik_die 'Brak zapisanego zadania.'; fi
    if [[ $action == usun ]] && (( !NIK_CONFIRM && !NIK_DRY_RUN )); then nik_die 'Usunięcie zadania wymaga --potwierdz.'; fi
    if (( !NIK_DRY_RUN )); then
        nik_family_dir quests "$NIK_CONFIG" || return "$?"; directory=$REPLY
        [[ ! -L $directory/$player.lock ]] || nik_die 'Blokada zadania jest dowiązaniem.'
        exec 8> "$directory/$player.lock" || return "$?"; nik_lock 8 || return "$?"
    fi
    if [[ $action == nowe ]]; then
        if [[ -f $file ]]; then
            fields=$(python3 "$NIK_ROOT/tools/family-state.py" task-read "$file" "$player" "$NIK_CONTAINER") || return "$?"
            [[ $fields != aktywne$'\t'* ]] || nik_die 'Gracz ma aktywne zadanie. Oznacz je jako gotowe albo usuń.'
        fi
        shift
        text=$(python3 "$NIK_ROOT/tools/family-state.py" task-new "$player" "$NIK_CONTAINER" "$@") || return "$?"
        if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] zapis zadania i książka Zadanie od Taty\n'; return; fi
        pending=$(mktemp "$directory/.pending.XXXXXX"); trap 'rm -f -- "$pending"' EXIT
        printf '%s\n' "$text" > "$pending"
        book=$(python3 "$NIK_ROOT/tools/family-state.py" task-book "$pending" "$player" "$NIK_CONTAINER") || return "$?"
        nik_rcon "give $player $book 1" || return "$?"
        mv -f -- "$pending" "$file" || return "$?"
        nik_message 1 success 'Zapisano zadanie. Książkę można otworzyć w grze.\n'; return
    fi
    fields=$(python3 "$NIK_ROOT/tools/family-state.py" task-read "$file" "$player" "$NIK_CONTAINER") || return "$?"
    IFS=$'\t' read -r status text <<< "$fields"
    case $action in
        pokaz) nik_section 'ZADANIE OD TATY'; nik_message 1 gold '  Status: %s\n' "$status"; nik_ui_text "$text" ;;
        ksiazka) book=$(python3 "$NIK_ROOT/tools/family-state.py" task-book "$file" "$player" "$NIK_CONTAINER") || return "$?"; nik_rcon "give $player $book 1" ;;
        gotowe)
            if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] oznaczenie zadania jako gotowe\n'; return; fi
            pending=$(mktemp "$directory/.pending.XXXXXX"); trap 'rm -f -- "$pending"' EXIT
            python3 "$NIK_ROOT/tools/family-state.py" task-done "$file" "$player" "$NIK_CONTAINER" > "$pending" || rc=$?
            ((rc == 0)) || return "$rc"
            mv -f -- "$pending" "$file"; nik_message 1 success 'Zadanie oznaczone jako gotowe. Brawo!\n' ;;
        usun)
            if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] usunięcie zadania\n'; else rm -f -- "$file"; nik_message 1 success 'Usunięto zadanie z konfiguracji.\n'; fi ;;
    esac
)
nik_cmd_protection() (
    (($# <= 1)) || nik_die 'Użycie: ochrona [status | budowanie | wylacz]'
    local action=${1:-status} directory file pending key value raw snapshot fields rc=0 existing=0
    local -a keys=(mob_griefing fire_spread_radius_around_player tnt_explodes projectiles_can_break_blocks) replies=()
    local -A target=([mob_griefing]=false [fire_spread_radius_around_player]=0 [tnt_explodes]=false [projectiles_can_break_blocks]=false)
    [[ $action == status || $action == budowanie || $action == wylacz ]] || nik_die 'Ochrona: status, budowanie lub wylacz.'
    command -v python3 >/dev/null || nik_die 'Ochrona wymaga Python 3.'
    file=$NIK_STATE/protection/$NIK_CONTAINER.json
    [[ ! -L $NIK_STATE && ! -L $NIK_STATE/protection && ! -L $file ]] || nik_die 'Profil ochrony jest dowiązaniem.'
    if [[ $action != status ]] && (( !NIK_CONFIRM && !NIK_DRY_RUN )); then nik_die 'Zmiana reguł całego świata wymaga --potwierdz.'; fi
    if [[ $action == wylacz ]]; then
        [[ -f $file ]] || nik_die 'Brak zapisanych reguł sprzed włączenia ochrony.'
        fields=$(python3 "$NIK_ROOT/tools/family-state.py" rules-read "$file" "$NIK_CONTAINER") || return "$?"
        while IFS=$'\t' read -r key value; do target[$key]=$value; done <<< "$fields"
    fi
    if ((NIK_DRY_RUN)); then
        if [[ $action == status ]]; then for key in "${keys[@]}"; do nik_rcon "gamerule minecraft:$key"; done
        else for key in "${keys[@]}"; do nik_rcon "gamerule minecraft:$key ${target[$key]}"; done; fi
        return
    fi
    nik_family_dir protection "$NIK_STATE" || return "$?"; directory=$REPLY
    [[ ! -L $directory/$NIK_CONTAINER.lock ]] || nik_die 'Blokada ochrony jest dowiązaniem.'
    exec 8> "$directory/$NIK_CONTAINER.lock" || return "$?"; nik_lock 8 || return "$?"
    if [[ $action == wylacz ]]; then
        fields=$(python3 "$NIK_ROOT/tools/family-state.py" rules-read "$file" "$NIK_CONTAINER") || return "$?"
        while IFS=$'\t' read -r key value; do target[$key]=$value; done <<< "$fields"
    fi
    if [[ $action == status ]]; then
        nik_section 'OCHRONA ŚWIATA'
        for key in "${keys[@]}"; do nik_rcon "gamerule minecraft:$key" >/dev/null || return "$?"; replies+=("$NIK_RCON_RESPONSE"); done
        fields=$(python3 "$NIK_ROOT/tools/family-state.py" rules-values "$NIK_CONTAINER" "${replies[@]}") || return "$?"
        while IFS=$'\t' read -r key value; do
            case $key in
                mob_griefing) raw='Niszczenie przez moby' ;;
                fire_spread_radius_around_player) raw='Zasięg ognia' ;;
                tnt_explodes) raw='Wybuchy TNT' ;;
                projectiles_can_break_blocks) raw='Niszczenie pociskami' ;;
            esac
            case $value in true) value=włączone ;; false) value=wyłączone ;; esac
            nik_ui_text "$raw: $value" command
        done <<< "$fields"
        [[ ! -f $file ]] || nik_message 1 gold 'Zachowano reguły sprzed włączenia ochrony.\n'
        return
    fi
    if [[ $action == budowanie && -f $file ]]; then nik_die 'Profil już zapisany. Sprawdź ochrona status lub przywróć przez ochrona wylacz.'; fi
    if [[ $action == budowanie ]]; then
        for key in "${keys[@]}"; do nik_rcon "gamerule minecraft:$key" >/dev/null || return "$?"; replies+=("$NIK_RCON_RESPONSE"); done
        snapshot=$(python3 "$NIK_ROOT/tools/family-state.py" rules-capture "$NIK_CONTAINER" "${replies[@]}") || return "$?"
        pending=$(mktemp "$directory/.pending.XXXXXX"); trap 'rm -f -- "$pending"' EXIT
        printf '%s\n' "$snapshot" > "$pending"; mv -f -- "$pending" "$file"
    fi
    for key in "${keys[@]}"; do
        if nik_rcon "gamerule minecraft:$key ${target[$key]}"; then :; else rc=$?; break; fi
    done
    if ((rc)); then
        nik_message 2 error 'Zachowano reguły do odzyskania: ochrona wylacz --potwierdz.\n'
        return "$rc"
    fi
    if [[ $action == wylacz ]]; then rm -f -- "$file"; nik_message 1 success 'Przywrócono poprzednie reguły świata.\n'
    else nik_message 1 success 'Ochrona budowania włączona dla świata.\n'; fi
)
nik_cmd_point_delete() (
    nik_args 2 "$@"; nik_normalize_name "$2"; local name=$REPLY pending
    nik_id "$name"; [[ -v NIK_PLACES[$name] ]] || nik_die 'Nieznany punkt.'
    if (( !NIK_CONFIRM && !NIK_DRY_RUN )); then nik_die 'Usunięcie punktu wymaga --potwierdz.'; fi
    if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] usunięcie punktu %s\n' "$name"; return; fi
    [[ ! -L $NIK_CONFIG/places.tsv && ! -L $NIK_CONFIG/places.lock ]] || nik_die 'Plik miejsc lub blokada jest dowiązaniem.'
    umask 077
    exec 9> "$NIK_CONFIG/places.lock"; nik_lock 9 || return "$?"
    pending=$(mktemp "$NIK_CONFIG/.places.XXXXXX"); trap 'rm -f -- "$pending"' EXIT
    awk -F '\t' -v name="$name" '$1 != name' "$NIK_CONFIG/places.tsv" > "$pending" || return "$?"
    mv -f -- "$pending" "$NIK_CONFIG/places.tsv" || return "$?"
    nik_message 1 success 'Usunięto punkt: %s\n' "$name"
)
nik_places_table() {
    local name line x y z dimension
    nik_section 'ZAPISANE MIEJSCA'
    if ((${#NIK_PLACES[@]} == 0)); then nik_ui_text 'Brak punktów. Dodaj: punkt GRACZ NAZWA' muted; return; fi
    while IFS= read -r name; do
        read -r x y z dimension <<< "${NIK_PLACES[$name]}"
        nik_ui_text "$name" command
        nik_ui_text "  X $x   Y $y   Z $z | $dimension" muted
    done < <(printf '%s\n' "${!NIK_PLACES[@]}" | LC_ALL=C sort)
}
