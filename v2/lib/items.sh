# shellcheck shell=bash
declare -A NIK_ITEMS=() NIK_ITEM_IDS=() NIK_ITEM_ALIASES=() NIK_ITEM_NAMES_BY_ID=()
while IFS=$'\t' read -r key value; do
    NIK_ITEMS[$key]=$value; NIK_ITEM_IDS[$value]=1; NIK_ITEM_NAMES_BY_ID[$value]=$key
done < "$NIK_ROOT/data/items.tsv"
while IFS=$'\t' read -r key value; do
    [[ -n $key && -v NIK_ITEM_IDS[$value] && ! -v NIK_ITEMS[$key] && ! -v NIK_ITEM_ALIASES[$key] ]] || nik_die 'Błędny lub kolidujący alias przedmiotu.'
    NIK_ITEM_ALIASES[$key]=$value
done < "$NIK_ROOT/data/item-aliases.tsv"
unset key value
nik_item() {
    nik_normalize_name "$1"
    local item=${REPLY#minecraft:}; nik_id "$item"
    if [[ -v NIK_ITEMS[$item] ]]; then REPLY=${NIK_ITEMS[$item]}
    elif [[ -v NIK_ITEM_ALIASES[$item] ]]; then REPLY=${NIK_ITEM_ALIASES[$item]}
    elif [[ -v NIK_ITEM_IDS[$item] ]]; then REPLY=$item
    else nik_suggest "$item" "${!NIK_ITEMS[@]}" "${!NIK_ITEM_IDS[@]}"; nik_die "Nieznany przedmiot: $1"; fi
}
# One canonical result per item, even when several historical aliases match.
nik_item_candidates() {
    local query=$1 name id
    local -A matches=()
    for name in "${!NIK_ITEMS[@]}"; do
        id=${NIK_ITEMS[$name]}
        if [[ $name == *"$query"* || $id == *"$query"* ]]; then matches[$name]=1; fi
    done
    if [[ -n $query ]]; then
        for name in "${!NIK_ITEM_ALIASES[@]}"; do
            if [[ $name == *"$query"* ]]; then
                id=${NIK_ITEM_ALIASES[$name]}; matches[${NIK_ITEM_NAMES_BY_ID[$id]}]=1
            fi
        done
    fi
    if ((${#matches[@]})); then printf '%s\n' "${!matches[@]}" | LC_ALL=C sort; fi
    return 0
}
nik_item_rows() {
    local name
    while IFS= read -r name; do printf '%s\t%s\n' "$name" "${NIK_ITEMS[$name]}"; done < <(nik_item_candidates "$1")
}
