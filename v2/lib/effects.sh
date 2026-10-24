# shellcheck shell=bash
declare -A NIK_EFFECTS=() NIK_EFFECT_IDS=()
while IFS=$'\t' read -r key value description; do NIK_EFFECTS[$key]=$value; NIK_EFFECT_IDS[$value]=1; done < "$NIK_ROOT/data/effects.tsv"
unset key value description
nik_effect() {
    nik_normalize_name "$1"
    local effect=${REPLY#minecraft:}; nik_id "$effect"
    if [[ -v NIK_EFFECTS[$effect] ]]; then REPLY=${NIK_EFFECTS[$effect]}
    elif [[ -v NIK_EFFECT_IDS[$effect] ]]; then REPLY=$effect
    else nik_suggest "$effect" "${!NIK_EFFECTS[@]}" "${!NIK_EFFECT_IDS[@]}"; nik_die "Nieznany efekt: $1"; fi
}
