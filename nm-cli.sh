#!/usr/bin/env bash

#. ./common.sh "NM-Tools" "NetworkManager"
# old cur_dir
#cur_dir=$(cd $(dirname "$0") 2>/dev/null && pwd) || cur_dir=".";

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
#cur_dir=${SELF%/*}
#dir_name=${cur_dir##*/}
#export PATH="${SELF%/*}:$PATH"

. ${SELF%/*}/.nmcli-env

. /root/.bash_func

print_banner "NetworkManager cli";

show_conn() {
_show=$(nmcli -c yes con show | awk '{print "    " $0}')
printf "\n    List connections:${nc}\n%s${nc}\n" "${_show}";
}

#printstr "List connections:\n%s" "$(nmcli c show | grep amneziaw)";
show_devices() {
_show=$(nmcli d show | awk '{print "    " $0}')
printf "${bnc}\n    List connections:\n%s${nc}\n" "${_show}";
}

#_banner "Create connection manually"

menu_info() {
    declare mItems=("Просмотр соединений" "Просмотр девайсов" "Просмотр Окружения")
    declare mActions=("show_connections" "show_devices" "show_environment")
    declare Title="Меню nm-cli Информация"
    declare Descr=""
    declare Type="section"

    awg_header
      while true; do
        show_mItems

        case "$choice" in
#          show_mActions "${mActions[@]}"
            1) show_conn        || { print_warn "Ошибка в разделе $choise[1]"; menu_pause; } ;;
            2) show_devices     || { print_warn "Ошибка в разделе $choise[2]"; menu_pause; } ;;
            3) show_environment || { print_warn "Ошибка в разделе $choise[3]"; menu_pause; } ;;
            0) printf "\n"; echo -e "    ${byel}Возврат.\n${nc}"; echo ""; return 0 ;;
            q) printf "\n    ${bred}Выход.\n${nc}"; exit 0 ;;
            *) print_warn "Введите число от 0 до 4"; menu_pause ;;
        esac
        menu_pause
        awg_header
    done
}

nmcli_import_con() {
ask "Импортировать конфиг из файла:[${nc}${DEF_CONF}${bnc}]?" "" iconf;
[[ -z "$iconf" ]] && iconf="$DEF_CONF"
_imp=$(nmcli c import type amneziawg file ${iconf} | awk '{print "    " $0}')
printf "\n    Импорт конфига $iconf:${byel}\n%s\n${nc}" "${_imp}";
}

nmcli_create_con() {
show_conn
ask "Создать соединение:[${nc}${DEF_NAME}${bnc}]?" "" cname;
[[ -z "$cname" ]] && cname="$DEF_NAME"
_add=$(nmcli c add type vpn ifname '*' vpn-type amneziawg con-name ${cname} | awk '{print "    " $0}')
printf "\n    Создание соединения $cname:${bgrn}\n%s\n${nc}" "${_add}";
}

nmcli_remove_con() {
ask "Удалить соединение:[${nc}${DEF_NAME}${bnc}]?" "" rmname;
[[ -z "$rmname" ]] && rmname="$DEF_NAME"
_del=$(nmcli c del ${rmname} | awk '{print "    " $0}')
printf "\n    Удаление соединения $rmname:${bred}\n%s\n${nc}" "${_del}";
}

# Set interface private key
#nmcli c modify ${NAME} vpn.data "local-private-key=YAnL1JqN5iMHW2kHbNfT9xLqX5vBz1mQWc8p3Kf9R0E="

# Set peer public key
#nmcli c modify ${NAME} vpn.data "peer-1-public-key=XbK2mPw8nR4tY6vLqZ9hF1cJ3sA5gD7eB9uG2pK0M="

# Set peer endpoint
#nmcli c modify ${NAME} vpn.data "peer-1-endpoint='${ENDPOINT}:${ENDPOINT_PORT}'"

# Set peer allowed IPs
#nmcli c modify ${NAME} vpn.data "peer-1-allowed-ips='${ALLOWED_IPS}'"

# Activate the connection
nmcli_up() {
show_conn
ask "Поднять соединение:[${nc}${DEF_NAME}|n${bnc}]?" "" upname;
[[ "$upname" == "n" ]] && return 0;
[[ -z "$upname" ]] && upname="$DEF_NAME"
_up=$(nmcli -c yes con up ${upname} | awk '{print "    " $0}')
printf "\n    Поднимаю соединение $upname:${bgrn}\n%s\n${nc}" "${_up}";
}

# Deactivate the connection
nmcli_down() {
show_conn
ask "Погасить соединение:[${nc}${DEF_NAME}|n${bnc}]?" "" downname;
[[ "$downname" == "n" ]] && return 0;
[[ -z "$downname" ]] && downname="$DEF_NAME"
_down=$(nmcli -c yes con down ${downname} | awk '{print "    " $0}')
printf "\n    Гашу соединение $downname:${bred}\n%s\n${nc}" "${_down}";
}

menu_manage() {
    declare mItems=("Импорт соединения" "Создать соединение" "Удалить соединение" "Поднять соединение" "Погасить соединение")
    declare mActions=("nmcli_import_con" "nmcli_create_con" "nmcli_remove_con" "nmcli_up" "nmcli_down")
    declare Title="Управление"
    declare Descr=""
    declare Type="section"

    awg_header
      while true; do
        show_mItems

        case "$choice" in
#          show_mActions "${mActions[@]}"
            1) nmcli_import_con || { print_warn "Ошибка в разделе $choise[1]"; menu_pause; } ;;
            2) nmcli_create_con || { print_warn "Ошибка в разделе $choise[2]"; menu_pause; } ;;
            3) nmcli_remove_con || { print_warn "Ошибка в разделе $choise[3]"; menu_pause; } ;;
            4) nmcli_up         || { print_warn "Ошибка в разделе $choise[3]"; menu_pause; } ;;
            5) nmcli_down       || { print_warn "Ошибка в разделе $choise[3]"; menu_pause; } ;;
            0) printf "\n"; echo -e "    ${byel}Возврат.\n${nc}"; echo ""; return 0 ;;
            q) printf "\n    ${bred}Выход.\n${nc}"; exit 0 ;;
            *) print_warn "Введите число от 0 до 5"; menu_pause ;;
        esac
        menu_pause
        awg_header
    done
}


menu_main() {
    declare mItems=("Информация" "Управление" "Окружение" "Утилиты")
    declare mActions=("ipcheck" "actionB" "actionC")
    declare Title="NetworkManager command line interface"
    declare Descr=""
    declare Type="section"

    awg_header
      while true; do
        show_mItems
#       printf "${bnc}    %s${bnc}\n" "$(align::left $COLS_NUM "")"
#        printf "${blub}╔%s╗${nc}\n" "$(align::left $COLS_NUM "$equals")"
#        printf "${blub}║%s║${nc}\n" "$(align::left $COLS_NUM " 1  -  Информация")"
#        printf "${blub}║%s║${nc}\n" "$(align::left $COLS_NUM " 2  -  Управление")"
#        printf "${blub}║%s║${nc}\n" "$(align::left $COLS_NUM " 3  -  Окружение")"
#        printf "${blub}║%s║${nc}\n" "$(align::left $COLS_NUM " 4  -  Утилиты")"
#        printf "${blub}║ ${und}%s${nc}${blub} ║${nc}\n" "$(align::center $((COLS_NUM-2)) ' ')"
#        printf "${magb}║%s║${nc}\n" "$(align::center $COLS_NUM " ")"
#        printf "${magb}║%s║${nc}\n" "$(align::left $COLS_NUM " 0  -  Назад")"
#        printf "${redb}║%s║${nc}\n" "$(align::left $COLS_NUM " q  -  Выход")"
#        printf "${redb}╚%s╝${nc}\n" "$(align::left $((${COLS_NUM})) "$equals")"
#        _read_choice choice
#        printf "${bnc}"

        case "$choice" in
            1) menu_info   || { print_warn "Ошибка в разделе $choise[1]"; menu_pause; } ;;
            2) menu_manage || { print_warn "Ошибка в разделе $choise[2]"; menu_pause; } ;;
            3) menu_env    || { print_warn "Ошибка в разделе $choise[3]"; menu_pause; } ;;
            4) menu_utils  || { print_warn "Ошибка в разделе $choise[4]"; menu_pause; } ;;
            0) echo ""; echo "  Выход."; echo ""; exit 0 ;;
            q) printf "\n    ${bred}Выход.\n${nc}"; exit 0 ;;
            *) print_warn "Введите число от 0 до 4"; menu_pause ;;
        esac
        awg_header
    done
}


menu_main


printf "    %s\n" "$dashes"


#while true; do
#    display_menu
#    read -p "Введите номер: " choice
#    case $choice in
#        "Обновить список" | "Очистить кэш" | "Перезагрузить систему"
#            ((current_idx = (current_idx + 1) % ${#options[@]})))
#            eval ${option}  # Выполняем команду
#            ;;
#        "0")
#            echo "Выход из меню."
#            break
#            ;;
#        *)
#            echo "Неверный выбор. Попробуйте снова."
#            ;;
#    esac
#done
#echo ""
#return 1

#while true; do
#    display_menu
#    read -p "Введите номер: " choice
#    case $choice in
#        "Обновить список" | "Очистить кэш" | "Перезагрузить систему"
#            ((current_idx = (current_idx + 1) % ${#options[@]})))
#            eval ${option}  # Выполняем команду
#            ;;
#        "0")
#            echo "Выход из меню."
#            break
#            ;;
#        *)
#            echo "Неверный выбор. Попробуйте снова."
#            ;;
#    esac
#done
#echo ""
#return 1


#View connection details
#nmcli c show "My AmneziaWG VPN"
#Delete connection
#nmcli c delete "My AmneziaWG VP
#nmcli_show
#nmcli_import
#nmcli_show
#ipcheck
#_menu
