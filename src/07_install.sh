# --> Функции подменю "Установка" <--

check_and_install_updates() {
    log "Checking for system updates..."
    dnf check-update || true
    log "Installing system updates..."
    dnf update -y || true
}

# --> МЕНЮ: Установка <--
menu_install() {
    declare mItems=("Проверка и обновление системы" "Базовая установка" "Установка модуля ядра amneziawg" "Установка вспомогательных утилит")
    declare mActions=("check_and_install_updates" "basic_install" "menu_install_awg_mod" "menu_install_utils")
    declare mTitle="Установка"
    declare mDescr=""
    declare mType="section"
    show_menu
}
