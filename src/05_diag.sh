# --> Функции подменю "Диагностика" <--

awg_lsmod() {
    if ! lsmod | grep amneziawg >/dev/null 2>&1; then
        log_warn "Модуль amneziawg не загружен. Его можно добавить в автозагрузку, в меню \"Установка\"."
        return 1
    else
        log "Модуль amneziawg загружен."
        return 0
    fi
}
wg_lsmod() {
    if ! lsmod | grep wireguard >/dev/null 2>&1; then
        log_warn "Модуль wireguard не загружен. Его можно добавить в автозагрузку, в меню \"Установка\"."
        return 1
    else
        log "Модуль wireguard загружен."
        return 0
    fi
}

modules_check() {
awg_lsmod
wg_lsmod
#awg_lsmod=$(lsmod | grep amneziawg | awk '{print "    " $0}')
#printf "\n    Модуль amneziawg:\n%s\n" "$awg_all"
#printf "${nc}"
}

# --> Функции "system_check" <--
system_check() {
check_root
check_virt
validate_os_ver
}


# --> МЕНЮ: Диагностика <--
menu_diag() {
    declare mItems=("Проверка системы" "Проверка модулей AWG и WG")
    declare mActions=("system_check" "modules_check")
    declare mTitle="Диагностика"
    declare mDescr=""
    declare mType="section"
    show_menu
}
