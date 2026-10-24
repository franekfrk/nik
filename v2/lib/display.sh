# shellcheck shell=bash
nik_wrap_text() {
    local text=$1 width=$2 line='' word
    local -a words=()
    read -r -a words <<< "$text"
    for word in "${words[@]}"; do
        if [[ -n $line ]] && ((${#line}+${#word}+1 > width)); then printf '%s\n' "$line"; line=''; fi
        line+="${line:+ }$word"
    done
    printf '%s\n' "$line"
}
nik_table() {
    local file=$1 kind=$2 query=${3:-} empty_query=${4:-${3:-}} key value desc left=5 right=2 count=0 alias_id alias_width=0
    local cyan='' green='' muted='' bold='' text='' gold='' reset='' width=${NIK_WIDTH:-120} col
    if nik_color_enabled 1; then
        cyan=${NIK_PALETTE[command]}; green=${NIK_PALETTE[success]}; muted=${NIK_PALETTE[muted]}
        bold=${NIK_PALETTE[title]}; text=${NIK_PALETTE[text]}; gold=${NIK_PALETTE[gold]}; reset=$'\033[0m'
    fi
    if [[ -t 1 && ! -v NIK_WIDTH ]]; then width=$(tput cols 2>/dev/null) || width=80; fi
    [[ $width =~ ^[0-9]{2,3}$ ]] || width=120
    width=$((10#$width)); ((width >= 40)) || width=40
    local -a names=() values=() descriptions=() aliases=()
    while IFS=$'\t' read -r key value desc alias_id; do
        [[ -z $query || $key == *"$query"* || $value == *"$query"* ]] || continue
        names+=("$key"); values+=("$value"); descriptions+=("$desc"); aliases+=("$alias_id")
        if ((${#alias_id} > alias_width)); then alias_width=${#alias_id}; fi
        if ((${#key} > left)); then left=${#key}; fi
        if ((${#value} > right)); then right=${#value}; fi
    done < <(LC_ALL=C sort -t $'\t' -k1,1 "$file")
    count=${#names[@]}
    if ((count == 0)); then nik_message 1 gold 'Brak wyników dla: %s\n' "$empty_query"; return 0; fi
    local title='PRZEDMIOTY' heading='NAZWA PL' second='ID MINECRAFT'
    case $kind in
        effects) title='EFEKTY' ;;
        enchantments) title='ZAKLĘCIA'; heading='NAZWA PL'; second='MAX' ;;
    esac
    printf '\n  %s%s%s  %s(%s)%s\n\n' "$bold" "$title" "$reset" "$muted" "$count" "$reset"
    local rule i line first desc_width indent
    local -a wrapped=()
    printf -v rule '%*s' "$((width-2))" ''; rule=${rule// /─}
    if [[ $kind == enchantments || $kind == effects ]]; then
        ((right >= ${#second})) || right=${#second}
        # Keep descriptions on the same row; continuation lines align under OPIS.
        if [[ $kind == enchantments ]]; then ((alias_width >= 12)) || alias_width=12; fi
        desc_width=$((width-left-right-6))
        if ((alias_width)); then desc_width=$((desc_width-alias_width-2)); fi
        if ((desc_width < 14)); then
            # A narrow terminal cannot fit three useful columns; use short cards.
            for ((i=0; i<count; i++)); do
                printf '  %s%s%s\n' "$cyan" "${names[i]}" "$reset"
                [[ -z ${aliases[i]} ]] || printf '    %s%s%s\n' "$muted" "${aliases[i]}" "$reset"
                printf '    %s%s: %s%s\n' "$green" "$second" "${values[i]}" "$reset"
                while IFS= read -r line; do printf '    %s%s%s\n' "$text" "$line" "$reset"; done < <(nik_wrap_text "${descriptions[i]}" "$((width-4))")
                printf '\n'
            done
            return 0
        fi
        indent=$((left+right+6))
        printf '  %s%-*s  %*s' "$gold" "$left" "$heading" "$right" "$second"
        if ((alias_width)); then printf '  %-*s' "$alias_width" 'NAZWA EN'; indent=$((indent+alias_width+2)); fi
        printf '  OPIS%s\n' "$reset"
        printf '  %s%s%s\n' "$muted" "$rule" "$reset"
        for ((i=0; i<count; i++)); do
            mapfile -t wrapped < <(nik_wrap_text "${descriptions[i]}" "$desc_width")
            printf '  %s%-*s%s  %s%*s%s' "$cyan" "$left" "${names[i]}" "$reset" "$green" "$right" "${values[i]}" "$reset"
            if ((alias_width)); then printf '  %s%-*s%s' "$muted" "$alias_width" "${aliases[i]}" "$reset"; fi
            printf '  %s%s%s\n' "$text" "${wrapped[0]}" "$reset"
            first=1
            while ((first < ${#wrapped[@]})); do
                printf '%*s%s%s%s\n' "$indent" '' "$text" "${wrapped[first]}" "$reset"
                first=$((first+1))
            done
        done
    else
        col=$left
        if ((col + right + 4 > width)); then col=$((width-right-4)); fi
        ((col >= 12)) || col=12
        printf '  %s%-*s  %s%s\n' "$gold" "$col" "$heading" "$second" "$reset"
        printf '  %s%s%s\n' "$muted" "$rule" "$reset"
        for ((i=0; i<count; i++)); do
            key=${names[i]}; value=${values[i]}
            if ((${#key} > col)); then
                printf '  %s%s%s\n    %s%s%s\n' "$cyan" "$key" "$reset" "$green" "$value" "$reset"
            else
                printf '  %s%-*s%s  %s%s%s\n' "$cyan" "$col" "$key" "$reset" "$green" "$value" "$reset"
            fi
        done
    fi
    printf '\n'
}
