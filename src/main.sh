# --> ГЛАВНОЕ МЕНЮ <--
# - точка входа, навигация по разделам -

# --> ТОЧКА ВХОДА: ГЛАВНОЕ МЕНЮ <--
menu_main() {
    declare mItems=("Информация" "Утилиты" "AmneziaWG 3" "Управление firewalld" "Диагностика" "Установка" "Окружение" "NetworkManager")
    declare mActions=("menu_info" "menu_utils" "awg3_menu" "fwcmd_manage" "menu_diag" "menu_install" "menu_env" "nmcli_menu")
    declare mTitle="Главное меню $pr_name"
    declare mDescr=""
    declare mType="main"
    show_menu
}
