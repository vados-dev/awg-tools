# --> ЗАПУСК <--
# - точка входа в скрипт -
show_menu() {
    local choice
    local index=0
    awg_header
    while true; do
        printf "${blub}╔%s╗${nc}\n" "$(align::center $COLS_NUM "$equals ${mTitle} $equals")"
        printf "${blub}║%s║${nc}\n" "$(align::center $COLS_NUM " ")"
        for idx in ${!mItems[@]}; do
            printf "${blub}║%s║${nc}\n" "$(align::left $COLS_NUM "  $((idx + 1))  -  ${mItems[$idx]}")"
            index=$((index + 1))
        done
        printf "${blub}║ ${und}%s${nc}${blub} ║${nc}\n" "$(align::center $((COLS_NUM-2)) ' ')"
        printf "${magb}║%s║${nc}\n" "$(align::center $COLS_NUM " ")"

        if [[ "$mType" != "main" ]]; then
            printf "${magb}║%s║${nc}\n" "$(align::left $COLS_NUM " 0  -  Назад")"
        fi

        printf "${redb}║%s║${nc}\n" "$(align::left $COLS_NUM " q  -  Выход")"
        printf "${redb}╚%s╝${nc}\n" "$(align::left $((${COLS_NUM})) "$equals")"
        _read_choice choice
        printf "${bnc}"

        if [[ "$mType" != "main" ]] && [[ "$choice" == "0" ]]; then
            printf "\n    ${byel}%s\n${nc}\n" "Возврат."
            return 0
        fi

        if [[ "$choice" == "q" ]]; then
            printf "\n    ${bred}%s\n${nc}\n" "Выход."
            exit 0
        fi

        if [[ "$choice" =~ ^[1-9]+$ ]] && (( choice >= 1 && choice <= ${#mActions[@]} )); then
            "${mActions[choice - 1]}"
        else
            printf "\n    ${bred}%s %d.${nc}\n\n" "Введите число от 1 до " ${index}
        fi
    if [[ "$mType" == "section" ]]; then
        menu_pause
    fi
    awg_header
    done
}

menu_main

printf "    %s\n" "$dashes"

