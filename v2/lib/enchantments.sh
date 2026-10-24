# shellcheck shell=bash
declare -A NIK_ENCHANT_MAX=() NIK_ENCHANT_DESC=() NIK_ENCHANT_ITEMS=() NIK_ENCHANT_CONFLICTS=() NIK_ENCHANT_NAMES=() NIK_ENCHANT_POLISH=()
while IFS=$'\t' read -r key value desc; do NIK_ENCHANT_MAX[$key]=$value; NIK_ENCHANT_DESC[$key]=$desc; done < "$NIK_ROOT/data/enchantments.tsv"
while IFS=$'\t' read -r key value; do NIK_ENCHANT_ITEMS[$key:$value]=1; done < "$NIK_ROOT/data/enchantment-items.tsv"
while IFS=$'\t' read -r key value; do NIK_ENCHANT_CONFLICTS[$key:$value]=1; NIK_ENCHANT_CONFLICTS[$value:$key]=1; done < "$NIK_ROOT/data/enchantment-conflicts.tsv"
while IFS=$'\t' read -r key value; do NIK_ENCHANT_NAMES[$key]=$value; NIK_ENCHANT_POLISH[$value]=$key; done < "$NIK_ROOT/data/enchantment-names.tsv"
unset key value desc
nik_enchantment_rows() {
    local enchant
    for enchant in "${!NIK_ENCHANT_MAX[@]}"; do
        printf '%s\t%s\t%s\t%s\n' "${NIK_ENCHANT_POLISH[$enchant]}" "${NIK_ENCHANT_MAX[$enchant]}" "${NIK_ENCHANT_DESC[$enchant]}" "$enchant"
    done
}
nik_enchanted() {
    local item=$1; shift
    local pair enchant level previous entries='' separator='' component=enchantments
    local -A seen=()
    [[ $item != enchanted_book ]] || component=stored_enchantments
    for pair in "$@"; do
        nik_enchant_pair "$pair"; enchant=$NIK_PAIR_ENCHANT; level=$NIK_PAIR_LEVEL
        [[ ! -v seen[$enchant] ]] || nik_die "Powtórzone zaklęcie: $enchant"
        [[ $item == enchanted_book || -v NIK_ENCHANT_ITEMS[$enchant:$item] ]] || nik_die "Zaklęcie $enchant nie pasuje do $item (reguły gry)."
        for previous in "${!seen[@]}"; do
            [[ ! -v NIK_ENCHANT_CONFLICTS[$enchant:$previous] ]] || nik_die "Konflikt zaklęć: $enchant / $previous"
        done
        seen[$enchant]=1
        entries+="$separator\"minecraft:$enchant\":$level"; separator=,
    done
    [[ -n $entries ]] || nik_die 'Podaj przynajmniej jedno zaklęcie.'
    if [[ $NIK_COMPONENTS == modern ]]; then REPLY="minecraft:${item}[minecraft:$component={$entries}]"
    else REPLY="minecraft:${item}[minecraft:$component={levels:{$entries}}]"; fi
}

nik_enchant_pair() {
    local pair=$1 enchant level=1
    enchant=${pair%%:*}; [[ $pair != *:* ]] || level=${pair#*:}
    nik_normalize_name "$enchant"; enchant=$REPLY; nik_id "$enchant"
    if [[ -v NIK_ENCHANT_NAMES[$enchant] ]]; then enchant=${NIK_ENCHANT_NAMES[$enchant]}; fi
    [[ -v NIK_ENCHANT_MAX[$enchant] ]] || { nik_suggest "$enchant" "${!NIK_ENCHANT_NAMES[@]}" "${!NIK_ENCHANT_MAX[@]}"; nik_die "Nieznane zaklęcie: $enchant"; }
    nik_uint "$level" 1 "${NIK_ENCHANT_MAX[$enchant]}"
    NIK_PAIR_ENCHANT=$enchant; NIK_PAIR_LEVEL=$REPLY
}
