# shellcheck shell=bash
nik_completion_candidates() {
    local command=${1:-} position=${2:-1} current=${3:-} word
    nik_normalize_name "$current"; current=$REPLY
    local -a words=()
    nik_settings
    if [[ $position == 1 ]]; then
        case $command in
            przepis|szukaj) nik_item_candidates "$current"; return ;;
            nagroda) words=(lista "${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}") ;;
            pogoda) words=(slonce czysto deszcz burza) ;;
            ochrona) words=(status budowanie wylacz) ;;
            punkt) words=(lista usun "${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}") ;;
            kopia) words=(utworz lista) ;;
            przywroc) for word in "$NIK_ROOT"/world-backups/*.json; do [[ -f $word ]] || continue; word=${word##*/}; words+=("${word%.json}"); done ;;
            zestaw) words=(lista pokaz zapisz "${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}") ;;
            przywolaj) words=("${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}" co lista) ;;
            efekt|encik) words=("${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}" co lista) ;;
            *) words=("${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}") ;;
        esac
    elif [[ $position == 2 ]]; then
        case $command in
            nagroda) while IFS= read -r word; do words+=("$word"); done < <(nik_reward_names) ;;
            prowadz|ratunek) words=("${!NIK_PLACES[@]}") ;;
            punkt) words=("${!NIK_PLACES[@]}") ;;
            zadanie) words=(pokaz ksiazka gotowe usun) ;;
            przywolaj) words=("${!NIK_CREATURES[@]}" "${!NIK_CREATURE_IDS[@]}" "${!NIK_CREATURE_ALIASES[@]}") ;;
            zaklnij) words=("${!NIK_ENCHANT_NAMES[@]}" "${!NIK_ENCHANT_MAX[@]}") ;;
            daj|encik) nik_item_candidates "$current"; return ;;
            efekt|usun) words=("${!NIK_EFFECTS[@]}") ;;
            tp|dolacz) words=("${!NIK_PLAYERS[@]}" "${!NIK_ALIASES[@]}" "${!NIK_PLACES[@]}") ;;
            zestaw) for word in "$NIK_CONFIG"/favorites/*.tsv; do [[ -f $word ]] || continue; word=${word##*/}; words+=("${word%.tsv}"); done ;;
            wyposaz) for word in "$NIK_CONFIG"/sets/*.tsv; do [[ -f $word ]] || continue; word=${word##*/}; words+=("${word%.tsv}"); done ;;
        esac
    elif [[ $command == przywolaj && $position == 3 ]]; then words=(1 2 3 4 5 6 8 10 16 32 64)
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
                --wersja|--version) nik_message 1 title 'NIK 2.6.2\n'; return ;;
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
    nik_registry_validate
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
