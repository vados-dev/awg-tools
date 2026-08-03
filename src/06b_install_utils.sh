# --> Функции подменю "Установка вспомогательных утилит" <--

install_packages() {
    local packages=("$@")
    local to_install=()
    local rpm_pkg
    local NEED_COPR=false
    local COPR=""
    log "Checking rpm packages: ${packages[*]}..."
    for rpm_pkg in "${packages[@]}"; do
        if ! dnf list installed "$rpm_pkg" 2>/dev/null | grep -q "Installed Packages"; then
            if [[ "$rpm_pkg" == "amneziawg-tools" ]]; then
                NEED_COPR=true;
            fi
             to_install+=("$rpm_pkg")
        fi
    done
        if [ ${#to_install[@]} -eq 0 ]; then
            echo "All rpm packages already installed."
            return 0
        else
            return 1
        fi

    local epel_url
    if [[ "$VERSION_ID" == "10" ]]; then
        epel_url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm"
    elif [[ "$VERSION_ID" == "9" ]]; then
        epel_url="https://dl.fedoraproject.org/pub/epel/epel{,-next}-release-latest-${VERSION_ID}.noarch.rpm"
    fi

#    dnf install -y kernel-headers-$(uname -r) kernel-devel-$(uname -r)

    read -rp "Install custom epel-release from url ${epel_url}? [y/N]: " -e -i "N" epel_custom < /dev/tty
    if [[ "$epel_custom" =~ ^[Yy]$ ]]; then
        EPEL=${epel_url}
    else
        EPEL=epel-release
    fi
    if [[ "$NEED_COPR" == true ]]; then
        read -rp "Enable copr amneziavpn/amneziawg centos-stream-10-$(arch)? [y/N]: " -e -i "N" amneziavpn < /dev/tty
        if [[ "$amneziavpn" =~ ^[Yy]$ ]]; then
            COPR="amneziavpn/amneziawg centos-stream-10-$(arch)"
        else
            read -rp "Enable copr tigro/amneziawg epel-${VERSION_ID}-$(arch) [y/N]: " -e -i "N" tigro < /dev/tty
            if [[ "$tigro" =~ ^[Yy]$ ]]; then
                COPR="tigro/amneziawg epel-${VERSION_ID}-$(arch)"
            fi
        fi
    fi

    dnf check-update || true
    dnf config-manager --enable crb || true
    dnf clean all || true
    dnf makecache || true

    if [[ ${EPEL} != "" ]]; then dnf install -y ${EPEL}; fi
    if [[ ${COPR} != "" ]]; then dnf copr enable -y ${COPR}; fi

    echo "Installing: ${to_install[*]}..."
    sudo dnf install -y ${to_install[*]} > /dev/null 2>&1
#    dnf install -y $INSTALLATION_PACKAGES[@]

    dnf remove -y amneziawg-tools
    dnf copr enable -y amneziavpn/amneziawg #centos-stream-10-$(arch)

}

choice_base_packages() {
    declare base_pkgs_menu=("Установить Midnight Commander" "Установить curl" "Установить wget" "Установить net-tools" "Установить git")
    declare base_pkgs_def=("true" "true" "true" "true" "true")
    declare base_pkgs=("mc" "curl" "wget" "net-tools" "git")
    declare mTitle="Установка базовых утилит"
    declare mHelpStr="${bnc} Help: Навигация |${magb}j or ↓\t\t=> down | k or ↑\t\t=> up | h or ↑\t\t=> left | l or ↑\t\t=> right |${bnc} Выбор: |$blub a \t\t=> все | n \t\t=> ничего | ⎵ (Пробел)\t=> Выбрать/Отмена выбора | ⏎ (Enter)\t=> Подтверждение выбора/Выход ${nc}"
#    OPTIONS_STRING=()
#    unset $OPTIONS_STRING
#    for ind in "${!base_pkgs_menu[@]}"; do
#        OPTIONS_STRING+="$((${ind} + 1)) ${base_pkgs_menu[$ind]};"
#    done

     sel_base_pkgs=()

#    awg_header
#     print_banner "Выберите необходимые пакеты для установки:"
     multiselect sel_base_pkgs base_pkgs_menu base_pkgs_def
#     prompt_for_multiselect sel_base_pkgs "$OPTIONS_STRING" "$base_pkgs_def"
# < /dev/tty # 

    local selected_base_packages=()
    local selected_base_packages_count=0
    local i=0
    for i in "${!sel_base_pkgs[@]}"; do
        if [ "${sel_base_pkgs[$i]}" == "true" ]; then
            selected_base_packages+=("${base_pkgs[$i]}")
            selected_base_packages_count=$((selected_base_packages_count + 1))
        fi
    done
    if (( selected_base_packages_count == 0 )); then
        log "Не выбрано не одного пакета для установки."
        return 1
    else
        log "Выбраны для установки: ${selected_base_packages[*]}"
        return 0
    fi
#    log "Запускаю установку выбранных пакетов..."
#    install_packages "${selected_base_packages[@]}"
}

configure_packages() {
    read -rp "Upgrade system and reboot? [y/N]: " -e -i "N" upgrade < /dev/tty
    if [[ "$upgrade" =~ ^[Yy]$ ]]; then
        dnf update -y && dnf upgrade -y && reboot
    fi

    INSTALLATION_PACKAGES=()
    read -rp "Install amneziawg-tools? [y/N]: " -e -i "N" atools < /dev/tty
    if [[ "$atools" =~ ^[Yy]$ ]]; then
        INSTALLATION_PACKAGES+=" amneziawg-tools"
    fi
    read -rp "Install wireguard-tools? [y/N]: " -e -i "N" wtools < /dev/tty
    if [[ "$wtools" =~ ^[Yy]$ ]]; then
        INSTALLATION_PACKAGES+=" wireguard-tools"
    fi
    read -rp "Install qrencode? [y/N]: " -e -i "N" qrencode < /dev/tty
    if [[ "$qrencode" =~ ^[Yy]$ ]]; then
        INSTALLATION_PACKAGES+=" qrencode"
    fi
    read -rp "Install fail2ban? [y/N]: " -e -i "N" fail2ban < /dev/tty
    if [[ "$fail2ban" =~ ^[Yy]$ ]]; then
        INSTALLATION_PACKAGES+=" fail2ban"
    else
        read -rp "Install firefalld? [y/N]: " -e -i "N" firewalld < /dev/tty
        if [[ "$firewalld" =~ ^[Yy]$ ]]; then
            INSTALLATION_PACKAGES+=" firewalld firewalld-filesystem"
        fi
        read -rp "Install nftables? [y/N]: " -e -i "N" nftables < /dev/tty
        if [[ "$nftables" =~ ^[Yy]$ ]]; then
            INSTALLATION_PACKAGES+=" nftables"
        fi
    fi
#export $INSTALLATION_PACKAGES
install_packages $INSTALLATION_PACKAGES
}

install_nm_awg() {
    TMP_DIR=$(mktemp -d -t install_nm_awg-XXXXXX)
    chmod 0700 "$TMP_DIR"
    git clone -b master "https://github.com/vovochka404/network-manager-amneziawg.git" "${TMP_DIR}" 2>/dev/null; cd "${TMP_DIR}" 2>/dev/null && log "Репозиотрий клонирован." || log_error "Ошибка клона репозитория!"
#git fetch origin master #git pull origin master
    mkdir -p build && cd build > /dev/null 2>&1 && log "Папка $TMP_DIR/build создана." || log_error "Ошибка создания директории build!"
    # System installation (for RPM packages)
    cmake .. -DWITH_GTK3=OFF -DWITH_GTK4=OFF -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib64 > /dev/null 2>&1 && log "Сборка прошла успешно." || log_error "Ошибка сборки \"cmake\"!"
    cmake --build . 2>/dev/null && log "Билд сделан." || log_error "Ошибка команды \"cmake build .\"!"
    cpack -G RPM > /dev/null 2>&1 && log "rpm пакет создан." || log_error "Ошибка создания rpm!"
    #rpm -i NetworkManager-amneziawg-*.rpm
    dnf -y install $(ls | grep NetworkManager-amneziawg-*.rpm) > /dev/null 2>&1 && log "rpm пекет установлен." || log_error "Ошибка установки \"dnf install\"!"
    rm -rf "$TMP_DIR" > /dev/null 2>&1 && log "Папка ${TMP_DIR} удалена." || log_error "Ошибка удаления ${TMP_DIR}!"
}

#configure_packages

# --> МЕНЮ: Установка вспомогательных утилит <--
menu_install_utils() {
    declare mItems=("Установка базовых утилит" "Установка плагина network-manager-amneziawg" "Установка amneziawg-tools" "Установка wireguard-tools" "Установка fail2ban")
    declare mActions=("choice_base_packages" "install_nm_awg" "install_amneziawg_tools" "install_wireguard_tools" "install_fail2ban")
    declare mTitle="Установка вспомогательных утилит"
    declare mDescr="- Базовые утилиты включают установку mc, curl, wget, net-tools, git.\n- При выборе amneziawg-tools, будет выбор дополнительных опций установки.\n  wireguard-tools, могут и не понадобится.\n  Поэтому рекомендуется устанавливать по порядку.\n"
    declare mType="section"
    show_menu
}
