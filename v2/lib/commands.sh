# shellcheck shell=bash
# Registry: name, handler, mutation/confirmation flag, usage, description.
# shellcheck disable=SC2153
nik_cmd_players() {
    nik_args 0 "$@"
    local name alias shortcuts
    nik_section 'GRACZE'
    while IFS= read -r name; do
        shortcuts=''
        for alias in "${!NIK_ALIASES[@]}"; do
            [[ ${NIK_ALIASES[$alias]} != "$name" ]] || shortcuts+="${shortcuts:+, }$alias"
        done
        nik_message 1 command '  %-15s ' "$name"
        nik_message 1 gold '(skrót: %s)  ' "$shortcuts"
        nik_message 1 text '%s\n' "${NIK_PLAYERS[$name]}"
    done < <(printf '%s\n' "${!NIK_PLAYERS[@]}" | sort)
    printf '\n'
}
nik_cmd_items() { nik_args 0 "$@"; nik_table "$NIK_ROOT/data/items.tsv" items; }
nik_cmd_search() { nik_args 1 "$@"; nik_normalize_name "$1"; nik_table <(nik_item_rows "$REPLY") items "" "$REPLY"; }
nik_cmd_give() {
    (($# == 2 || $# == 3)) || nik_die 'Użycie: nik daj GRACZ ITEM [ILOŚĆ]'
    nik_player "$1"; local player=$REPLY
    nik_item "$2"; local item=$REPLY
    nik_uint "${3:-1}" 1 2304
    nik_rcon "give $player minecraft:$item $REPLY"
}
nik_cmd_enchant() {
    if [[ ${1:-} == co || ${1:-} == lista ]]; then nik_args 1 "$@"; nik_table <(nik_enchantment_rows) enchantments; return; fi
    (($# >= 3)) || nik_die 'Użycie: nik encik GRACZ ITEM ZAKLĘCIE[:POZIOM]...'
    nik_player "$1"; local player=$REPLY
    nik_item "$2"; local item=$REPLY; shift 2
    nik_enchanted "$item" "$@"
    nik_rcon "give $player $REPLY 1"
}
nik_cmd_tp() {
    (($# == 2 || $# == 4)) || nik_die 'Użycie: nik tp GRACZ CEL lub GRACZ X Y Z'
    nik_player "$1"; local player=$REPLY
    local command
    if (($# == 2)); then
        local target=${2,,} x y z dimension
        nik_id "$target"
        if [[ $target == end ]]; then
            nik_tp_end "$player"; return
        elif [[ -v NIK_PLACES[$target] ]]; then
            read -r x y z dimension <<< "${NIK_PLACES[$target]}"
            command="execute in $dimension run tp $player $x $y $z"
        else nik_player "$target"; command="tp $player $REPLY"; fi
    else
        nik_coord "$2"; nik_coord "$3"; nik_coord "$4"
        local coords="$2 $3 $4"
        if [[ $coords == *'^'* ]]; then [[ $2 == ^* && $3 == ^* && $4 == ^* ]] || nik_die 'Współrzędne ^ muszą wystąpić na wszystkich osiach.'; fi
        command="execute at $player run tp $player $coords"
    fi
    nik_teleport "$player" "$command"
}
nik_cmd_join() { nik_args 2 "$@"; nik_player "$1"; local player=$REPLY; nik_player "$2"; nik_teleport "$player" "tp $player $REPLY"; }
nik_cmd_home() { nik_args 1 "$@"; [[ -v NIK_PLACES[dom] ]] || nik_die 'Brak miejsca dom.'; nik_cmd_tp "$1" dom; }
nik_cmd_castle() { nik_args 1 "$@"; [[ -v NIK_PLACES[zamek] ]] || nik_die 'Brak miejsca zamek.'; nik_cmd_tp "$1" zamek; }
nik_cmd_place() {
    case ${1:-lista} in
        lista) (($# <= 1)) || nik_die 'Użycie: miejsce lista'; nik_places_table ;;
        dodaj)
            nik_args 6 "$@"; nik_id "$2"; [[ ! -v NIK_PLAYERS[$2] && ! -v NIK_ALIASES[$2] ]] || nik_die 'Nazwa miejsca koliduje z graczem.'; nik_coord "$3"; nik_coord "$4"; nik_coord "$5"; nik_dimension "$6"
            [[ $3 != [~^]* && $4 != [~^]* && $5 != [~^]* && ! -v NIK_PLACES[$2] ]] || nik_die 'Miejsce istnieje lub współrzędne nie są absolutne.'
            if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] zapis miejsca %s\n' "$2"
            else (
                umask 077
                nik_lock 9 || return "$?"
                if awk -F '\t' -v name="$2" '$1 == name {found=1} END {exit !found}' "$NIK_CONFIG/places.tsv"; then nik_die 'Miejsce już istnieje.'; fi
                printf '%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" "$6" >> "$NIK_CONFIG/places.tsv"
            ) 9> "$NIK_CONFIG/places.lock"; fi ;;
        *) nik_die 'Użycie: miejsce lista | dodaj NAZWA X Y Z WYMIAR' ;;
    esac
}
nik_cmd_effect() {
    if [[ ${1:-} == co || ${1:-} == lista ]]; then nik_args 1 "$@"; nik_table "$NIK_ROOT/data/effects.tsv" effects; return; fi
    (($# >= 2 && $# <= 4)) || nik_die 'Użycie: efekt GRACZ EFEKT [CZAS] [POZIOM]'
    if [[ $2 == leczenie ]]; then nik_args 2 "$@"; nik_cmd_health "$1"; return; fi
    nik_player "$1"; local player=$REPLY
    nik_effect "$2"; local effect=$REPLY
    nik_duration "${3:-30}" 1 1000000; local duration=$REPLY
    local max_level=256
    [[ $effect != instant_health && $effect != instant_damage ]] || max_level=10
    nik_uint "${4:-1}" 1 "$max_level"; local amplifier=$((REPLY-1))
    nik_rcon "effect give $player minecraft:$effect $duration $amplifier true"
}
nik_cmd_remove() { nik_args 2 "$@"; nik_player "$1"; local player=$REPLY; nik_effect "$2"; nik_rcon "effect clear $player minecraft:$REPLY"; }
nik_cmd_clear() { nik_args 1 "$@"; nik_player "$1"; nik_rcon "effect clear $REPLY"; }
nik_cmd_health() {
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY
    # Instant health uses an integer bit shift in Minecraft; amplifier 255 overflows.
    nik_rcon "effect give $player minecraft:instant_health 1 10 true" || return "$?"
    nik_rcon "effect give $player minecraft:saturation 1 20 true"
}
nik_cmd_freeze() {
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY attribute
    # Remove the legacy implementation and any Jump Boost that bypasses zero
    # jump_strength. No base attributes or unrelated effects are overwritten.
    nik_rcon "effect clear $player minecraft:slowness" || return "$?"
    nik_rcon "effect clear $player minecraft:jump_boost" || return "$?"
    for attribute in movement_speed jump_strength; do
        nik_rcon "attribute $player minecraft:$attribute modifier remove nik:frozen" || return "$?"
        nik_rcon "attribute $player minecraft:$attribute modifier add nik:frozen -1 add_multiplied_total" || return "$?"
    done
}
nik_cmd_thaw() {
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY attribute
    for attribute in movement_speed jump_strength; do
        nik_rcon "attribute $player minecraft:$attribute modifier remove nik:frozen" || return "$?"
    done
    nik_rcon "effect clear $player minecraft:slowness" || return "$?"
    nik_rcon "effect clear $player minecraft:jump_boost"
}
nik_cmd_kick() { (($# >= 1)) || nik_die 'Podaj gracza.'; nik_player "$1"; local player=$REPLY; shift; local reason=${*:-Wyrzucony przez administratora}; nik_rcon "kick $player $reason"; }
nik_cmd_lightning() { nik_args 1 "$@"; nik_player "$1"; nik_rcon "execute at $REPLY run summon minecraft:lightning_bolt"; }
nik_cmd_explosion() { nik_args 1 "$@"; nik_player "$1"; nik_rcon "execute at $REPLY run summon minecraft:creeper ~ ~ ~ {Fuse:0s,ignited:1b}"; }
nik_cmd_day() { nik_args 0 "$@"; nik_rcon 'time set day' || return "$?"; nik_rcon 'weather clear'; }
nik_cmd_night() { nik_args 0 "$@"; nik_rcon 'time set night'; }
nik_cmd_weather() {
    (($# == 1 || $# == 2)) || nik_die 'Użycie: pogoda slonce|deszcz|burza [CZAS]'
    local weather duration=''
    nik_normalize_name "$1"
    case $REPLY in slonce|czysto|clear) weather=clear ;; deszcz|rain) weather=rain ;; burza|thunder) weather=thunder ;; *) nik_die 'Pogoda: slonce, deszcz, burza.' ;; esac
    if (($# == 2)); then nik_duration "$2" 1 1000000; duration=" ${REPLY}s"; fi
    nik_rcon "weather $weather$duration"
}
nik_cmd_storm() { nik_args 0 "$@"; nik_cmd_weather burza; }
nik_cmd_save() { nik_args 0 "$@"; nik_rcon 'save-all flush'; }
nik_cmd_online() { nik_args 0 "$@"; nik_rcon list; }
nik_cmd_restart() {
    nik_args 0 "$@"
    if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] docker restart %s\n' "$NIK_CONTAINER"; return; fi
    nik_log START restart || return "$?"
    local reply
    reply=$(nik_docker restart "$NIK_CONTAINER") || return "$?"
    nik_message 1 success '%s\n' "$reply"
    nik_check || return "$?"
    nik_log OK restart
    nik_message 1 success 'Kontener uruchomiony. Gotowość Minecrafta sprawdź: nik status.\n'
}
nik_cmd_status() {
    nik_args 0 "$@"
    nik_panel 'NIK • PANEL SERWERA' 'Stan połączenia i prywatnej konfiguracji'
    nik_section 'KONFIGURACJA'
    nik_ui_text 'Konfiguracja: OK' success
    nik_ui_text "Gracze: ${#NIK_PLAYERS[@]} | Miejsca: ${#NIK_PLACES[@]}" command
    nik_ui_text "Kontener: $NIK_CONTAINER"
    nik_ui_text "Log: $NIK_LOG" muted
    nik_section 'MINECRAFT'
    if ((NIK_DRY_RUN)); then nik_ui_text '[podgląd] pominięto kontrolę Docker/RCON' gold; return; fi
    nik_check || return "$?"
    nik_rcon list >/dev/null || return "$?"
    nik_ui_text 'Docker: działa • RCON: połączony' success
    nik_ui_text "$NIK_RCON_RESPONSE"
}
nik_cmd_equip() {
    (($# == 1 || $# == 2)) || nik_die 'Użycie: wyposaz GRACZ [ZESTAW]'
    nik_player "$1"; local player=$REPLY preset=${2:-walka}
    nik_id "$preset"
    local file=$NIK_CONFIG/sets/$preset.tsv
    [[ -f $file ]] || nik_die 'Nieznany zestaw.'
    local slot item ench extra spec
    local -a commands=() enchantments=()
    local -A slots=()
    while IFS=$'\t' read -r slot item ench extra || [[ -n $slot ]]; do
        [[ -z $slot || $slot == \#* ]] && continue
        [[ $slot =~ ^(armor\.(head|chest|legs|feet)|weapon\.(mainhand|offhand)|inventory\.([0-9]|1[0-9]|2[0-6])|hotbar\.[0-8])$ && -z $extra && ! -v slots[$slot] ]] || nik_die 'Błędny/powtórzony slot zestawu.'
        slots[$slot]=1
        nik_item "$item"; item=$REPLY
        read -r -a enchantments <<< "$ench"
        if ((${#enchantments[@]})); then nik_enchanted "$item" "${enchantments[@]}"; spec=$REPLY; else spec=minecraft:$item; fi
        commands+=("item replace entity $player $slot with $spec 1")
    done < "$file"
    ((${#commands[@]})) || nik_die 'Pusty zestaw.'
    for spec in "${commands[@]}"; do nik_rcon "$spec" || return "$?"; done
}
nik_cmd_rotate() (
    nik_args 0 "$@"; [[ -f $NIK_LOG ]] || return 0
    if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] rotacja logu\n'; return; fi
    local cutoff tmp
    cutoff=$(date -u -d "-$NIK_LOG_DAYS days" +%FT%TZ)
    umask 077
    exec 9> "${NIK_LOG}.lock"
    nik_lock 9 || return "$?"
    tmp=$(mktemp "${NIK_LOG}.XXXXXX")
    # Lock shared with all writers; rename cannot lose concurrent log entries.
    if awk -v cutoff="$cutoff" '$1 >= cutoff' "$NIK_LOG" > "$tmp" && mv -- "$tmp" "$NIK_LOG"; then return 0; else rm -f -- "$tmp"; return 1; fi
)
