# shellcheck shell=bash
if ! declare -F nik_message >/dev/null; then
    # shellcheck disable=SC1091
    source "$(dirname -- "${BASH_SOURCE[0]}")/colors.sh"
fi
nik_die() { nik_message 2 error 'NIK: %s\n' "$*"; exit 2; }
nik_unexpected() { nik_message 2 error 'NIK: zakończono z błędem (status %s, linia %s).\n' "$1" "$2"; exit "$1"; }
nik_args() { (( $# == $1 + 1 )) || nik_die 'Nieprawidłowa liczba argumentów. Użyj nik <komenda> --pomoc.'; }
nik_uint() { [[ $1 =~ ^[0-9]{1,8}$ ]] || nik_die 'Wymagana liczba całkowita (maks. 8 cyfr).'; REPLY=$((10#$1)); (( REPLY >= $2 && REPLY <= $3 )) || nik_die "Liczba poza zakresem $2–$3."; }
nik_coord() { [[ $1 =~ ^-?[0-9]{1,8}([.][0-9]{1,6})?$ || $1 =~ ^[\~\^](-?[0-9]{1,8}([.][0-9]{1,6})?)?$ ]] || nik_die 'Nieprawidłowa współrzędna.'; }
nik_id() { [[ $1 =~ ^[a-z][a-z0-9_]*$ ]] || nik_die 'Nieprawidłowa nazwa (a-z, 0-9, _).'; }
nik_dimension() { [[ $1 =~ ^[a-z0-9_.-]+:[a-z0-9_./-]+$ ]] || nik_die 'Wymiar musi mieć format minecraft:overworld.'; }
nik_log() {
    local result=$1 command=$2 dir
    dir=$(dirname -- "$NIK_LOG")
    mkdir -p -- "$dir" || return 1
    (
        umask 077
        flock -x 9 || exit 1
        printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$result" "$command" >> "$NIK_LOG" || exit 1
        chmod 600 -- "$NIK_LOG"
    ) 9> "${NIK_LOG}.lock"
}
nik_normalize_name() {
    local text=${1,,}
    text=${text//ą/a}; text=${text//ć/c}; text=${text//ę/e}; text=${text//ł/l}; text=${text//ń/n}
    text=${text//ó/o}; text=${text//ś/s}; text=${text//ź/z}; text=${text//ż/z}
    text=${text//Ą/a}; text=${text//Ć/c}; text=${text//Ę/e}; text=${text//Ł/l}; text=${text//Ń/n}
    text=${text//Ó/o}; text=${text//Ś/s}; text=${text//Ź/z}; text=${text//Ż/z}
    text=${text// /_}; text=${text//-/_}
    while [[ $text == *__* ]]; do text=${text//__/_}; done
    REPLY=${text#_}; REPLY=${REPLY%_}
}

nik_suggest() {
    local query=$1 suggestion; shift
    command -v python3 >/dev/null || return 0
    while IFS= read -r suggestion; do
        nik_message 2 gold 'Czy chodziło o: %s?\n' "$suggestion"
    done < <(printf '%s\n' "$@" | python3 "$NIK_ROOT/tools/suggest.py" "$query")
}
