# shellcheck shell=bash
_nik_v2_complete() {
    local current=${COMP_WORDS[COMP_CWORD]} word command='' position=0 i next end_options=0
    local -a options=()
    COMPREPLY=()
    if [[ $current == --* ]]; then
        for word in --konfiguracja --podglad --potwierdz --pomoc --wersja --rozszerzenia; do
            [[ $word != "$current"* ]] || COMPREPLY+=("$word")
        done
        return 0
    fi
    if [[ ${COMP_WORDS[0]} != nik ]]; then
        command=${COMP_WORDS[0]}
        case $command in d) command=daj ;; zapiszswiat) command=zapisz ;; gracze) command=online ;; esac
    fi
    for ((i=1; i<COMP_CWORD; i++)); do
        word=${COMP_WORDS[i]}
        if (( !end_options )); then
            case $word in
                --konfiguracja|--config|--rozszerzenia|--extensions)
                    next=$((i+1))
                    if ((next < COMP_CWORD)); then options+=("$word" "${COMP_WORDS[next]}"); i=$next; continue; fi
                    return 0 ;;
                --podglad|--dry-run|--potwierdz|--confirm|--pomoc|--help|-h) continue ;;
                --) end_options=1; continue ;;
            esac
        fi
        if [[ -z $command ]]; then command=$word; else position=$((position+1)); fi
    done
    if [[ -z $command ]]; then
        while IFS= read -r word; do [[ $word != "$current"* ]] || COMPREPLY+=("$word"); done < <(nik "${options[@]}" commands)
    else
        position=$((position+1))
        while IFS= read -r word; do COMPREPLY+=("$word"); done < <(nik "${options[@]}" __complete "$command" "$position" "$current" 2>/dev/null)
    fi
}
nik_skroty() {
    local command
    for command in daj encik dom zamek tp dolacz efekt usun zdrowie wyposaz zapisz \
        szukaj przedmioty online gracz_lista dzien noc burza pogoda zamroz odmroz \
        kick grzmot wybuch restartmc wyczysc zaklnij kreatywny przetrwanie obserwator przygodowy zestaw kopia przywroc gdzie powrot tata wiadomosc; do
        # Expansion at definition time is intentional for this fixed command list.
        # shellcheck disable=SC2139
        alias "$command=nik $command"
        complete -F _nik_v2_complete "$command"
    done
    complete -F _nik_v2_complete d zapiszswiat gracze
    if [[ $- == *i* ]]; then bind 'set show-all-if-ambiguous on'; fi
    alias d='nik daj' zapiszswiat='nik zapisz' listaefektow='nik efekt co' gracze='nik online'
}
complete -F _nik_v2_complete nik
