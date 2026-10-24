# shellcheck shell=bash
# Shared terminal palette. Machine-readable completion/resolver output stays plain.
declare -A NIK_PALETTE=(
    [title]=$'\033[1;92m' [command]=$'\033[36m' [success]=$'\033[32m'
    [gold]=$'\033[1;33m' [error]=$'\033[1;31m' [text]=$'\033[37m'
    [muted]=$'\033[2m' [frame]=$'\033[32m'
)
nik_color_enabled() {
    [[ ${NIK_COLOR:-auto} == always || ( ${NIK_COLOR:-auto} == auto && -t $1 && ${TERM:-dumb} != dumb && ! -v NO_COLOR ) ]]
}
nik_message() {
    local stream=$1 style=$2 format=$3 color='' reset=''; shift 3
    if nik_color_enabled "$stream"; then color=${NIK_PALETTE[$style]}; reset=$'\033[0m'; fi
    printf '%s' "$color" >&"$stream"
    # The format strings are supplied only by NIK's own code, never user input.
    # shellcheck disable=SC2059
    printf "$format" "$@" >&"$stream"
    printf '%s' "$reset" >&"$stream"
}
nik_signature() {
    local letter code index=0
    local -a letters=(D l a ' ' F r a n k a ' ' '♥' ' ' T a t a)
    local -a colors=(91 93 92 96 94 95)
    printf '\n  '
    if nik_color_enabled 1; then
        for letter in "${letters[@]}"; do
            if [[ $letter == ' ' ]]; then printf ' '; continue; fi
            code=${colors[index % ${#colors[@]}]}
            [[ $letter != '♥' ]] || code=91
            printf '\033[1;%sm%s' "$code" "$letter"
            index=$((index+1))
        done
        printf '\033[0m\n\n'
    else printf 'Dla Franka ♥ Tata\n\n'; fi
}
