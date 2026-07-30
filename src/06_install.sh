# --> Функции подменю "Установка" <--

install_deps() {
    dnf update -y || true
#    dnf check-update || true
    dnf config-manager --enable crb || true
    dnf install -y epel-release || true
    dnf clean all || true
    dnf makecache || true
    dnf install -y dkms || die "DKMS не установлен!"
}
remove_deps() {
    echo "dkms"
    dnf remove -y dkms
}

amf="/etc/modules-load.d/amneziawg.conf"
wmf="/etc/modules-load.d/wireguard.conf"

add_awg_to_modules() {
    mkdir -p "$(dirname "$amf")"
    if ! grep -qxF 'amneziawg' "$amf" 2>/dev/null; then
        if echo "amneziawg" > "$amf" 2>/dev/null; then log "Записан $amf."; else log_warn "Ошибка записи $amf!"; fi
        if ! modprobe amneziawg 2>/dev/null; then log "Модуль amneziawg загружен."; else log_error "Модуль amneziawg не загружен!"; fi
    fi
}
del_awg_from_modules() {
    if rm -f $amf 2>/dev/null; then log "$amf удалён."; else log_error "Ошибка удаления $amf!"; fi
}
add_wg_to_modules() {
    mkdir -p "$(dirname "$wmf")"
    if ! grep -qxF 'wireguard' "$wmf" 2>/dev/null; then
        if echo "wireguard" > "$wmf" 2>/dev/null; then log "Записан $wmf."; else log_warn "Ошибка записи $wmf!"; fi
        if modprobe wireguard 2>/dev/null; then log "Модуль wireguard загружен."; else log_error "Модуль wireguard не загружен!"; fi
    fi
}
del_wg_from_modules() {
    if rm -f $wmf 2>/dev/null; then log "$wmf удалён."; else log_error "Ошибка удаления $wmf!"; fi
}
mod_awg_install() {
    if ! dnf list installed "dkms" 2>/dev/null | grep -q "Installed Packages"; then
        install_deps
    fi
    rm -rf ./setup
    git clone https://github.com/vados-dev/amneziawg-linux-kernel-module.git ${AWG_MODULE_SETUP_DIR}
    cd ${AWG_MODULE_SETUP_DIR}/src && \
    sudo make dkms-install && \
    sudo dkms install "amneziawg/$(make print-version)"
    add_awg_to_modules
    rm -rf ${AWG_MODULE_SETUP_DIR}
}

mod_awg_remove() {
    sudo dkms remove "amneziawg/$(dkms status | grep amneziawg | awk -F'[/, ]+' '{print $2}' | head -1)" --all
    del_awg_from_modules
    del_wg_from_modules
}

mod_awg_reinstall() {
    mod_awg_remove
    mod_awg_install
}

# --> МЕНЮ: Установка <--
menu_install() {
    declare mItems=("Установка модуля amneziawg" "Переустановка/обновление модуля amneziawg" "Удаление модуля amneziawg" "Добавить в автозагрузку модуль wireguard" "Удалить из автозагрузки модуль wireguard")
    declare mActions=("mod_awg_install" "mod_awg_reinstall" "mod_awg_remove" "add_wg_to_modules" "del_wg_from_modules")
    declare mTitle="Установка"
    declare mDescr=""
    declare mType="section"
    show_menu
}
