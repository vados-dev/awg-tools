# --> ГЛАВНОЕ МЕНЮ <--
# - точка входа, навигация по разделам -

# --> ТОЧКА ВХОДА: ГЛАВНОЕ МЕНЮ <--
menu_main() {
    declare mItems=("Информация" "Утилиты" "NetworkManager" "Управление firewalld" "Диагностика" "Установка" "Окружение")
    declare mActions=("menu_info" "menu_utils" "nmcli_menu" "fwcmd_manage" "menu_diag" "menu_install" "menu_env")
    declare mTitle="Главное меню $pr_name"
    declare mDescr=""
    declare mType="main"
    show_menu
}
