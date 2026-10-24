# shellcheck shell=bash
nik_cmd_creative() { nik_args 1 "$@"; nik_player "$1"; nik_rcon "gamemode creative $REPLY"; }
nik_cmd_survival() { nik_args 1 "$@"; nik_player "$1"; nik_rcon "gamemode survival $REPLY"; }
nik_cmd_spectator() { nik_args 1 "$@"; nik_player "$1"; nik_rcon "gamemode spectator $REPLY"; }
nik_cmd_adventure() { nik_args 1 "$@"; nik_player "$1"; nik_rcon "gamemode adventure $REPLY"; }
nik_cmd_enchant_hand() {
    (($# >= 2)) || nik_die 'Użycie: zaklnij GRACZ ZAKLĘCIE[:POZIOM]...'
    nik_player "$1"; local player=$REPLY pair enchant level; shift
    # Validate the whole request before changing anything. The game validates
    # compatibility with the held item and its existing enchantments.
    nik_enchanted enchanted_book "$@"
    for pair in "$@"; do
        nik_enchant_pair "$pair"; enchant=$NIK_PAIR_ENCHANT; level=$NIK_PAIR_LEVEL
        nik_rcon "enchant $player minecraft:$enchant $level" || return "$?"
    done
}
nik_cmd_favorite() {
    local action=${1:-lista} name item count file tmp spec
    local -a commands=()
    case $action in
        lista)
            (($# <= 1)) || nik_die 'Użycie: zestaw lista'
            nik_message 1 title '\nULUBIONE ZESTAWY\n'
            for file in "$NIK_CONFIG"/favorites/*.tsv; do
                [[ -f $file && ! -L $file ]] || continue
                name=${file##*/}; nik_message 1 command '  %s\n' "${name%.tsv}"
            done
            nik_message 1 text 'Zapisz: zestaw zapisz NAZWA ITEM[=ILOŚĆ]...\nDaj: zestaw GRACZ NAZWA\nGotowe wyposażenie: wyposaz GRACZ walka|kopanie|budowniczy --potwierdz\n' ;;
        zapisz)
            (($# >= 3)) || nik_die 'Użycie: zestaw zapisz NAZWA ITEM[=ILOŚĆ]...'
            nik_normalize_name "$2"; name=$REPLY; nik_id "$name"
            [[ $name != lista && $name != zapisz && $name != pokaz && ! -v NIK_PLAYERS[$name] && ! -v NIK_ALIASES[$name] ]] || nik_die 'Nazwa zestawu jest zarezerwowana.'
            file=$NIK_CONFIG/favorites/$name.tsv
            [[ ! -e $file && ! -L $file && ! -L $NIK_CONFIG/favorites ]] || nik_die 'Zestaw już istnieje lub katalog jest dowiązaniem.'
            shift 2
            (($# <= 36)) || nik_die 'Zestaw może zawierać maksymalnie 36 pozycji.'
            for spec in "$@"; do
                item=${spec%%=*}; count=1
                [[ $spec != *=* ]] || count=${spec#*=}
                nik_item "$item"; item=$REPLY
                nik_uint "$count" 1 2304; count=$REPLY
                commands+=("$item"$'\t'"$count")
            done
            if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] zapis zestawu %s (%s pozycji)\n' "$name" "${#commands[@]}"; return; fi
            (
                umask 077
                mkdir -p -- "$NIK_CONFIG/favorites"
                flock -x 9
                [[ ! -e $file && ! -L $file ]] || nik_die 'Zestaw już istnieje.'
                tmp=$(mktemp "$NIK_CONFIG/favorites/.pending.XXXXXX")
                trap 'rm -f -- "$tmp"' EXIT
                printf '%s\n' "${commands[@]}" > "$tmp"
                mv -- "$tmp" "$file"
            ) 9> "$NIK_CONFIG/favorites.lock"
            nik_message 1 success 'Zapisano zestaw: %s\n' "$name" ;;
        *)
            nik_args 2 "$@"
            local player='' extra rows=0
            [[ $action == pokaz ]] || { nik_player "$action"; player=$REPLY; }
            nik_normalize_name "$2"; name=$REPLY; nik_id "$name"
            file=$NIK_CONFIG/favorites/$name.tsv
            [[ -f $file && ! -L $file && ! -L $NIK_CONFIG/favorites ]] || nik_die 'Nieznany zestaw. Zobacz: zestaw lista.'
            while IFS=$'\t' read -r item count extra || [[ -n $item ]]; do
                [[ -n $item && -n $count && -z $extra ]] || nik_die 'Błędna pozycja zestawu.'
                nik_item "$item"; item=$REPLY; nik_uint "$count" 1 2304; count=$REPLY
                commands+=("give $player minecraft:$item $count"); rows=$((rows+1))
                ((rows <= 36)) || nik_die 'Zestaw może zawierać maksymalnie 36 pozycji.'
            done < "$file"
            ((rows)) || nik_die 'Pusty zestaw.'
            if [[ $action == pokaz ]]; then
                nik_message 1 title '\nZESTAW: %s\n' "$name"
                for spec in "${commands[@]}"; do read -r _ item count <<< "$spec"; nik_message 1 command '  %-35s' "${NIK_ITEM_NAMES_BY_ID[${item#minecraft:}]}"; nik_message 1 gold ' × %s\n' "$count"; done
            else for spec in "${commands[@]}"; do nik_rcon "$spec" || return "$?"; done; fi ;;
    esac
}
nik_cmd_backup() {
    local action=${1:-utworz}
    case $action in
        lista) nik_args 1 "$@" ;;
        utworz) (($# <= 1)) || nik_die 'Użycie: kopia [utworz|lista]' ;;
        *) nik_die 'Użycie: kopia [utworz|lista]' ;;
    esac
    nik_world_backup "$action"
}
nik_cmd_restore() { nik_args 1 "$@"; nik_world_backup przywroc "$1"; }
nik_world_backup() {
    command -v python3 >/dev/null || nik_die 'Kopie świata wymagają Python 3.'
    local -a options=()
    ((NIK_DRY_RUN == 0)) || options+=(--dry-run)
    # The helper has no shell interpolation; world paths come from Docker
    # inspection and server.properties, never from a user supplied host path.
    local rc=0
    if [[ $1 != lista ]] && (( !NIK_DRY_RUN )); then nik_log START "świat $*" || return "$?"; fi
    python3 "$NIK_ROOT/tools/world-backup.py" --root "$NIK_ROOT/world-backups" --container "$NIK_CONTAINER" --timeout "$NIK_TIMEOUT" "${options[@]}" "$@" || rc=$?
    if [[ $1 != lista ]] && (( !NIK_DRY_RUN )); then
        if ((rc)); then nik_log ERROR "świat $*" || true; else nik_log OK "świat $*" || return "$?"; fi
    fi
    return "$rc"
}
