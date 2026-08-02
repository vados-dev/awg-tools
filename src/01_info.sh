# --> Функции подменю "Инфо" <--
ip_show() {
ip_conn=$(ip -c a | awk '{print "    " $0}')
ip_routes=$(ip -c r | awk '{print "    " $0}')
printf "\n    ${bnc}Соединения:\n%s\n" "$ip_conn"
printf "\n    ${bnc}Маршруты:\n%s\n" "$ip_routes"
printf "${nc}"
}
awg_show() {
awg_all=$(awg show all | awk '{print "    " $0}')
printf "\n    AWG Соединения:\n%s\n" "$awg_all"
printf "${nc}"
}

# --> МЕНЮ: Инфо <--
menu_info() {
    declare mItems=("Местоположение IP" "Просмотр соединений и маршрутов" "Просмотр соединений AWG")
    declare mActions=("ipcheck" "ip_show" "awg_show")
    declare mTitle="Информация"
    declare mDescr=""
    declare mType="section"
    show_menu
}
