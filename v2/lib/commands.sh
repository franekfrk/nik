# shellcheck shell=bash
# Registry: name, handler, mutation/confirmation flag, usage, description.
declare -A NIK_HANDLERS=() NIK_DESTRUCTIVE=() NIK_USAGE=() NIK_DESCRIPTIONS=()
nik_register() {
    nik_id "$1"
    [[ ! -v NIK_HANDLERS[$1] ]] || nik_die "Powtórzona komenda: $1"
    declare -F "$2" >/dev/null || nik_die "Brak funkcji obsługi: $2"
    NIK_HANDLERS[$1]=$2; NIK_DESTRUCTIVE[$1]=$3; NIK_USAGE[$1]=$4; NIK_DESCRIPTIONS[$1]=$5
}
nik_help() {
    local name=${1:-} cmd
    nik_message 1 title '\n⛏  NIK v2 — polskie komendy Minecraft\n'
    nik_message 1 frame '   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'
    if [[ -n $name ]]; then
        [[ -v NIK_USAGE[$name] ]] || nik_die "Nieznana komenda: $name"
        nik_message 1 command '  nik %s\n' "${NIK_USAGE[$name]}"
        nik_message 1 text '  %s\n' "${NIK_DESCRIPTIONS[$name]}"
    else
        while IFS= read -r cmd; do
            nik_message 1 command '  %-15s ' "$cmd"
            nik_message 1 text '%s\n' "${NIK_DESCRIPTIONS[$cmd]}"
        done < <(printf '%s\n' "${!NIK_HANDLERS[@]}" | sort)
    fi
    nik_message 1 gold '\n  Opcje: --konfiguracja KATALOG, --podglad, --potwierdz, --pomoc, --wersja\n'
    nik_signature
}
# shellcheck disable=SC2153
nik_cmd_players() {
    nik_args 0 "$@"
    local name alias shortcuts
    nik_message 1 title '\nGRACZE\n\n'
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
        if [[ -v NIK_PLACES[$target] ]]; then
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
        lista) (($# <= 1)) || nik_die 'Użycie: miejsce lista'; local name; for name in "${!NIK_PLACES[@]}"; do nik_message 1 command '%-15s  %s\n' "$name" "${NIK_PLACES[$name]}"; done ;;
        dodaj)
            nik_args 6 "$@"; nik_id "$2"; [[ ! -v NIK_PLAYERS[$2] && ! -v NIK_ALIASES[$2] ]] || nik_die 'Nazwa miejsca koliduje z graczem.'; nik_coord "$3"; nik_coord "$4"; nik_coord "$5"; nik_dimension "$6"
            [[ $3 != [~^]* && $4 != [~^]* && $5 != [~^]* && ! -v NIK_PLACES[$2] ]] || nik_die 'Miejsce istnieje lub współrzędne nie są absolutne.'
            if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] zapis miejsca %s\n' "$2"
            else (
                umask 077
                flock -x 9
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
    nik_uint "${3:-30}" 1 1000000; local duration=$REPLY
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
nik_cmd_weather() { nik_args 1 "$@"; local weather; case $1 in czysto|clear) weather=clear ;; deszcz|rain) weather=rain ;; burza|thunder) weather=thunder ;; *) nik_die 'Pogoda: czysto, deszcz, burza.' ;; esac; nik_rcon "weather $weather"; }
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
    nik_message 1 command 'Konfiguracja: OK\nGracze: %s\nMiejsca: %s\nKontener: %s\nLog: %s\n' "${#NIK_PLAYERS[@]}" "${#NIK_PLACES[@]}" "$NIK_CONTAINER" "$NIK_LOG"
    if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] pominięto kontrolę Docker/RCON\n'; return; fi
    nik_check || return "$?"
    nik_rcon list
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
    flock -x 9
    tmp=$(mktemp "${NIK_LOG}.XXXXXX")
    # Lock shared with all writers; rename cannot lose concurrent log entries.
    if awk -v cutoff="$cutoff" '$1 >= cutoff' "$NIK_LOG" > "$tmp" && mv -- "$tmp" "$NIK_LOG"; then return 0; else rm -f -- "$tmp"; return 1; fi
)
nik_registry() {
    nik_register punkt nik_cmd_point 0 'punkt GRACZ NAZWA' 'Zapisz aktualną pozycję gracza jako nazwane miejsce.'
    nik_register plecak nik_cmd_inventory 0 'plecak GRACZ' 'Czytelny podgląd przedmiotów i zaklęć w plecaku.'
    nik_register napis nik_cmd_title 0 'napis GRACZ TREŚĆ...' 'Duży złoty tytuł z podpisem Od Taty ♥.'
    nik_register przywolaj nik_cmd_summon 0 'przywolaj GRACZ STWORZENIE | co' 'Przywołaj jedno stworzenie 2 bloki obok gracza; boss wymaga --potwierdz.'

    nik_register gdzie nik_cmd_where 0 'gdzie GRACZ' 'Pokaż pozycję, wymiar i kierunek gracza online.'
    nik_register powrot nik_cmd_back 0 'powrot GRACZ' 'Wróć do pozycji sprzed ostatniej udanej teleportacji NIK.'
    nik_register tata nik_cmd_dad 0 'tata GRACZ TREŚĆ...' 'Prywatna, kolorowa wiadomość od Taty w czacie gry.'
    nik_register wiadomosc nik_cmd_dad 0 'wiadomosc GRACZ TREŚĆ...' 'Wiadomość od Taty; odpowiednik tata.'

    nik_register zaklnij nik_cmd_enchant_hand 0 'zaklnij GRACZ ZAKLĘCIE[:POZIOM]...' 'Zaklnij przedmiot w głównej ręce; nie daje nowego.'
    nik_register kreatywny nik_cmd_creative 0 'kreatywny GRACZ' 'Tryb kreatywny wskazanego gracza, w tym samym świecie.'
    nik_register przetrwanie nik_cmd_survival 0 'przetrwanie GRACZ' 'Tryb przetrwania wskazanego gracza.'
    nik_register obserwator nik_cmd_spectator 0 'obserwator GRACZ' 'Tryb obserwatora wskazanego gracza.'
    nik_register przygodowy nik_cmd_adventure 0 'przygodowy GRACZ' 'Tryb przygodowy wskazanego gracza.'
    nik_register zestaw nik_cmd_favorite 0 'zestaw lista | pokaz NAZWA | zapisz NAZWA ITEM[=ILOŚĆ]... | GRACZ NAZWA' 'Zapisuj i dawaj ulubione zestawy; zachowuje rzeczy w ekwipunku.'
    nik_register kopia nik_cmd_backup 0 'kopia [utworz|lista]' 'Archiwum świata; krótko zatrzymuje i uruchamia serwer.'
    nik_register przywroc nik_cmd_restore 1 'przywroc ID_KOPII' 'Przywróć świat po kopii bieżącego; wymaga --potwierdz, rozłącza graczy.'

    nik_register daj nik_cmd_give 0 'daj GRACZ ITEM [ILOŚĆ]' 'Daj przedmiot (1–2304 szt.).'
    nik_register encik nik_cmd_enchant 0 'encik GRACZ ITEM ZAKLĘCIE[:POZIOM]... | co' 'Daj nowy zaklęty przedmiot; zaklęcia po polsku lub angielsku.'
    nik_register wyposaz nik_cmd_equip 1 'wyposaz GRACZ [ZESTAW]' 'Nadpisz wskazane sloty zestawu; wymaga --potwierdz.'
    nik_register tp nik_cmd_tp 0 'tp GRACZ CEL | GRACZ X Y Z' 'Teleport do miejsca, gracza lub współrzędnych.'
    nik_register dom nik_cmd_home 0 'dom GRACZ' 'Teleport do domu.'
    nik_register zamek nik_cmd_castle 0 'zamek GRACZ' 'Teleport do zamku.'
    nik_register dolacz nik_cmd_join 0 'dolacz GRACZ GRACZ' 'Teleport do drugiego gracza.'
    nik_register miejsce nik_cmd_place 0 'miejsce lista | dodaj NAZWA X Y Z WYMIAR' 'Lista i zapis miejsc.'
    nik_register efekt nik_cmd_effect 0 'efekt GRACZ EFEKT [CZAS] [POZIOM] | co' 'Dodaj efekt (domyślnie 30 s, poziom I).'
    nik_register usun nik_cmd_remove 0 'usun GRACZ EFEKT' 'Usuń jeden efekt.'
    nik_register wyczysc nik_cmd_clear 1 'wyczysc GRACZ' 'Usuń wszystkie efekty; wymaga --potwierdz.'
    nik_register zdrowie nik_cmd_health 0 'zdrowie GRACZ' 'Ulecz i nasyć gracza.'
    nik_register zamroz nik_cmd_freeze 0 'zamroz GRACZ' 'Zablokuj chodzenie i zwykłe skoki do odmroz.'
    nik_register odmroz nik_cmd_thaw 0 'odmroz GRACZ' 'Usuń blokadę NIK i stare efekty zamrażania.'
    nik_register kick nik_cmd_kick 1 'kick GRACZ [POWÓD...]' 'Wyrzuć gracza; wymaga --potwierdz.'
    nik_register grzmot nik_cmd_lightning 1 'grzmot GRACZ' 'Przywołaj piorun; wymaga --potwierdz.'
    nik_register wybuch nik_cmd_explosion 1 'wybuch GRACZ' 'Przywołaj wybuch; wymaga --potwierdz.'
    nik_register restartmc nik_cmd_restart 1 'restartmc' 'Restart kontenera; wymaga --potwierdz.'
    nik_register zapisz nik_cmd_save 0 'zapisz' 'Zapisz świat.'
    nik_register dzien nik_cmd_day 0 'dzien' 'Ustaw dzień i czystą pogodę.'
    nik_register noc nik_cmd_night 0 'noc' 'Ustaw noc.'
    nik_register pogoda nik_cmd_weather 0 'pogoda czysto|deszcz|burza' 'Zmień pogodę.'
    nik_register burza nik_cmd_storm 0 'burza' 'Rozpocznij burzę.'
    nik_register online nik_cmd_online 0 'online' 'Pokaż graczy online.'
    nik_register status nik_cmd_status 0 'status' 'Sprawdź konfigurację, kontener i RCON.'
    nik_register diagnoza nik_cmd_status 0 'diagnoza' 'Diagnostyka połączenia i konfiguracji.'
    nik_register gracze nik_cmd_players 0 'gracze' 'Lista skonfigurowanych graczy.'
    nik_register gracz_lista nik_cmd_players 0 'gracz_lista' 'Lista skonfigurowanych graczy (zgodność v1).'
    nik_register przedmioty nik_cmd_items 0 'przedmioty' 'Słownik PL → EN.'
    nik_register szukaj nik_cmd_search 0 'szukaj FRAZA' 'Szukaj przedmiotów po PL/EN.'
    nik_register log_rotacja nik_cmd_rotate 1 'log_rotacja' 'Usuń stare wpisy logu; wymaga --potwierdz.'
}
nik_completion_candidates() {
    local command=${1:-} position=${2:-1} current=${3:-} word
    nik_normalize_name "$current"; current=$REPLY
    local -a words=()
    nik_settings
    if [[ $position == 1 ]]; then
        case $command in
            szukaj) nik_item_candidates "$current"; return ;;
            pogoda) words=(czysto deszcz burza) ;;
            kopia) words=(utworz lista) ;;
            przywroc) for word in "$NIK_ROOT"/world-backups/*.json; do [[ -f $word ]] || continue; word=${word##*/}; words+=("${word%.json}"); done ;;
            zestaw) words=(lista pokaz zapisz "${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}") ;;
            przywolaj) words=("${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}" co lista) ;;
            efekt|encik) words=("${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}" co lista) ;;
            *) words=("${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}") ;;
        esac
    elif [[ $position == 2 ]]; then
        case $command in
            przywolaj) words=("${!NIK_CREATURES[@]}" "${!NIK_CREATURE_IDS[@]}" "${!NIK_CREATURE_ALIASES[@]}") ;;
            zaklnij) words=("${!NIK_ENCHANT_NAMES[@]}" "${!NIK_ENCHANT_MAX[@]}") ;;
            daj|encik) nik_item_candidates "$current"; return ;;
            efekt|usun) words=("${!NIK_EFFECTS[@]}") ;;
            tp|dolacz) words=("${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}" "${!NIK_PLACES[@]}") ;;
            zestaw) for word in "$NIK_CONFIG"/favorites/*.tsv; do [[ -f $word ]] || continue; word=${word##*/}; words+=("${word%.tsv}"); done ;;
            wyposaz) for word in "$NIK_CONFIG"/sets/*.tsv; do [[ -f $word ]] || continue; word=${word##*/}; words+=("${word%.tsv}"); done ;;
        esac
    elif [[ $command == zaklnij || $command == encik ]]; then words=("${!NIK_ENCHANT_NAMES[@]}" "${!NIK_ENCHANT_MAX[@]}"); fi
    for word in "${words[@]}"; do if [[ $word == *"$current"* ]]; then printf '%s\n' "$word"; fi; done | LC_ALL=C sort -u
}
nik_main() {
    nik_registry
    local -a args=()
    local help=0 options=1 argument command extension_dir='' extension
    while (($#)); do
        argument=$1; shift
        if ((options)); then
            case $argument in
                --) options=0; continue ;;
                --konfiguracja|--config) (($#)) || nik_die 'Brak katalogu po --konfiguracja.'; NIK_CONFIG=$1; shift; continue ;;
                --rozszerzenia|--extensions) (($#)) || nik_die "Brak katalogu rozszerzeń."; extension_dir=$1; shift; continue ;;
                --podglad|--dry-run) NIK_DRY_RUN=1; continue ;;
                --potwierdz|--confirm) NIK_CONFIRM=1; continue ;;
                --pomoc|--help|-h) help=1; continue ;;
                --wersja|--version) nik_message 1 title 'NIK 2.3.0\n'; return ;;
                --*) nik_die "Nieznana opcja: $argument" ;;
            esac
        fi
        args+=("$argument")
    done
    if [[ -n $extension_dir ]]; then
        [[ -d $extension_dir ]] || nik_die 'Brak katalogu rozszerzeń.'
        for extension in "$extension_dir"/*.sh; do
            [[ -f $extension ]] || continue
            # shellcheck disable=SC1090
            source "$extension"
        done
    fi
    command=${args[0]:-help}
    if [[ $command == help || $command == pomoc || $help == 1 ]]; then if [[ $command == help || $command == pomoc ]]; then nik_help "${args[1]:-}"; else nik_help "$command"; fi; return; fi
    if [[ $command == commands || $command == polecenia ]]; then printf '%s\n' "${!NIK_HANDLERS[@]}" | sort; return; fi
    if [[ $command == __complete ]]; then nik_completion_candidates "${args[@]:1}"; return; fi
    nik_id "$command"
    [[ -v NIK_HANDLERS[$command] ]] || { nik_suggest "$command" "${!NIK_HANDLERS[@]}"; nik_die "Nieznana komenda: $command"; }
    if (( ${NIK_DESTRUCTIVE[$command]} && !NIK_CONFIRM && !NIK_DRY_RUN )); then nik_die 'Ta komenda wymaga --potwierdz. Najpierw możesz użyć --podglad.'; fi
    nik_settings
    "${NIK_HANDLERS[$command]}" "${args[@]:1}"
}
