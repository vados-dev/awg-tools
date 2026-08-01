# --> Функции подменю "NetworkManager" <--
nmcli_show_conn() {
nm_show_conn=$(nmcli -c yes con show | awk '{print "    " $0}')
printf "\n    List connections:${nc}\n%s${nc}\n" "${nm_show_conn}";
}
nmcli_show_devices() {
nm_show_dev=$(nmcli d show | awk '{print "    " $0}')
printf "${bnc}\n    List connections:\n%s${nc}\n" "${nm_show_dev}";
}

nmcli_import_con() {
ask "Импортировать конфиг из файла:[${nc}${NMCLI_DEF_CONF}${bnc}]?" "" iconf;
[[ -z "$iconf" ]] && iconf="$NMCLI_DEF_CONF"
_imp=$(nmcli c import type amneziawg file ${iconf} | awk '{print "    " $0}')
printf "\n    Импорт конфига $iconf:${byel}\n%s\n${nc}" "${_imp}";
}

nmcli_create_con() {
nmcli_show_conn
ask "Создать соединение:[${nc}${NMCLI_DEF_NAME}${bnc}]?" "" cname;
[[ -z "$cname" ]] && cname="$NMCLI_DEF_NAME"
_add=$(nmcli c add type vpn ifname '*' vpn-type amneziawg con-name ${cname} | awk '{print "    " $0}')
printf "\n    Создание соединения $cname:${bgrn}\n%s\n${nc}" "${_add}";
}

nmcli_remove_con() {
ask "Удалить соединение:[${nc}${NMCLI_DEF_NAME}${bnc}]?" "" rmname;
[[ -z "$rmname" ]] && rmname="$NMCLI_DEF_NAME"
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
nmcli_show_conn
ask "Поднять соединение:[${nc}${NMCLI_DEF_NAME}|n${bnc}]?" "" upname;
[[ "$upname" == "n" ]] && return 0;
[[ -z "$upname" ]] && upname="$NMCLI_DEF_NAME"
_up=$(nmcli -c yes con up ${upname} | awk '{print "    " $0}')
printf "\n    Поднимаю соединение $upname:${bgrn}\n%s\n${nc}" "${_up}";
}

# Deactivate the connection
nmcli_down() {
nmcli_show_conn
ask "Погасить соединение:[${nc}${NMCLI_DEF_NAME}|n${bnc}]?" "" downname;
[[ "$downname" == "n" ]] && return 0;
[[ -z "$downname" ]] && downname="$NMCLI_DEF_NAME"
_down=$(nmcli -c yes con down ${downname} | awk '{print "    " $0}')
printf "\n    Гашу соединение $downname:${bred}\n%s\n${nc}" "${_down}";
}

nmcli_menu() {
    declare mItems=("Просмотр соединений" "Просмотр девайсов" "Просмотр Окружения" "Импорт соединения" "Создать соединение" "Удалить соединение" "Поднять соединение" "Погасить соединение")
    declare mActions=("nmcli_show_conn" "nmcli_show_devices" "nmcli_show_env" "nmcli_import_con" "nmcli_create_con" "nmcli_remove_con" "nmcli_up" "nmcli_down")
    declare mTitle="NetworkManager"
    declare mDescr=""
    declare mType="section"
    show_menu
}
