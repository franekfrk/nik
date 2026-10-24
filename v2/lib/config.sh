# shellcheck shell=bash
NIK_CONFIG=${NIK_CONFIG:-$NIK_ROOT/config}
NIK_CONTAINER=minecraft
NIK_TIMEOUT=10
NIK_LOG=${XDG_STATE_HOME:-$HOME/.local/state}/nik/nik.log
NIK_COMPONENTS=modern
NIK_LOG_DAYS=30
NIK_DRY_RUN=0
NIK_CONFIRM=0
NIK_ERROR_PATTERN="^(unknown|incorrect argument|invalid |no player|no entity|no entities|could not |unable to |incompatible|cannot |can't |nothing changed|not a valid|not supported|does not support|too high|failed|an unexpected error|expected |unrecognized|entity .* has no attribute|attribute .* has no modifier|modifier .* already present|target .*doesn't have|target has no effects|.* is higher than the maximum|.* is not holding any item|.* cannot support that enchantment|.* is not a valid entity for this command|found no elements|out of world|not loaded|you do not have permission|i'm sorry|nie znaleziono|nieprawidł|nieznan)"
declare -A NIK_PLAYERS=() NIK_ALIASES=() NIK_PLACES=()
nik_settings() {
    local key value extra
    [[ -f $NIK_CONFIG/config.env ]] || nik_die "Brak $NIK_CONFIG/config.env; skopiuj config.example."
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z $line || $line == \#* ]] && continue
        [[ $line == *=* ]] || nik_die 'Błędna linia config.env.'
        key=${line%%=*}; value=${line#*=}
        [[ -n $value && $value != *$'\r'* ]] || nik_die "Pusta/błędna wartość $key."
        case $key in
            CONTAINER) NIK_CONTAINER=$value ;;
            TIMEOUT) nik_uint "$value" 1 300; NIK_TIMEOUT=$REPLY ;;
            LOG) NIK_LOG=$value ;;
            COMPONENTS) [[ $value == modern || $value == legacy ]] || nik_die 'COMPONENTS: modern lub legacy.'; NIK_COMPONENTS=$value ;;
            LOG_DAYS) nik_uint "$value" 1 3650; NIK_LOG_DAYS=$REPLY ;;
            *) nik_die "Nieznany klucz konfiguracji: $key" ;;
        esac
    done < "$NIK_CONFIG/config.env"
    [[ $NIK_CONTAINER =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || nik_die 'Nieprawidłowa nazwa kontenera.'
    [[ $NIK_LOG == /* && $NIK_LOG != *$'\n'* ]] || nik_die 'LOG musi być ścieżką absolutną.'
    [[ -f $NIK_CONFIG/players.tsv && -f $NIK_CONFIG/places.tsv ]] || nik_die 'Brak players.tsv lub places.tsv.'
    local name alias nick
    while IFS=$'\t' read -r name alias nick extra || [[ -n $name ]]; do
        [[ -z $name || $name == \#* ]] && continue
        nik_id "$name"; nik_id "$alias"
        [[ $name != co && $name != lista && $alias != co && $alias != lista ]] || nik_die 'Nazwa lub skrót gracza są zarezerwowane: co/lista.'
        [[ -z $extra && $nick =~ ^\.?[a-zA-Z0-9_]{1,16}$ ]] || nik_die 'Błędny wpis gracza.'
        [[ ! -v NIK_PLAYERS[$name] && ! -v NIK_ALIASES[$name] && ! -v NIK_PLAYERS[$alias] && ! -v NIK_ALIASES[$alias] && $name != "$alias" ]] || nik_die 'Konflikt nazw lub skrótów graczy.'
        for value in "${NIK_PLAYERS[@]}"; do [[ ${value,,} != "${nick,,}" ]] || nik_die 'Powtórzony nick Minecraft.'; done
        NIK_PLAYERS[$name]=$nick; NIK_ALIASES[$alias]=$name
    done < "$NIK_CONFIG/players.tsv"
    ((${#NIK_PLAYERS[@]})) || nik_die 'Lista graczy jest pusta.'
    local x y z dimension
    while IFS=$'\t' read -r name x y z dimension extra || [[ -n $name ]]; do
        [[ -z $name || $name == \#* ]] && continue
        nik_id "$name"; [[ ! -v NIK_PLAYERS[$name] && ! -v NIK_ALIASES[$name] ]] || nik_die 'Nazwa miejsca koliduje z graczem.'; nik_coord "$x"; nik_coord "$y"; nik_coord "$z"; nik_dimension "$dimension"
        [[ -z $extra && ! -v NIK_PLACES[$name] && $x != [~^]* && $y != [~^]* && $z != [~^]* ]] || nik_die 'Błędne lub powtórzone miejsce.'
        NIK_PLACES[$name]="$x $y $z $dimension"
    done < "$NIK_CONFIG/places.tsv"
}
