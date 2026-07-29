#!/usr/bin/env bash

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
#cur_dir=${SELF%/*}
#dir_name=${cur_dir##*/}
#export PATH="${SELF%/*}:$PATH"

. ${SELF%/*}/.vpn-optimize-env

. /root/.bash_func

# Настройка sysctl (расширенная)
# ==============================================================================
_sysctl_buffers() {
    log "Настройка Адаптивных буферов sysctl..."
    ![ -d ${sysctl_dir} ] 2>/dev/null || mkdir -p ${sysctl_dir}
    local f="${sysctl_dir}/80-amneziawg-buffers.conf"
    # Адаптивные буферы по объёму RAM
    local rmem_max wmem_max netdev_backlog
    if [[ ${TOTAL_RAM_MB:-1024} -ge 2048 ]]; then
        rmem_max=16777216    # 16MB
        wmem_max=16777216
        netdev_backlog=5000
    else
        rmem_max=4194304     # 4MB
        wmem_max=4194304
        netdev_backlog=2500
    fi
    cat > "$f" << EOF
# --- Network Buffers (adaptive) ---
net.core.rmem_max = ${rmem_max}
net.core.wmem_max = ${wmem_max}
net.core.netdev_max_backlog = ${netdev_backlog}
EOF
    log "Применение sysctl..."
    if ! sysctl -p "$f" >/dev/null 2>&1; then
        log_warn "Некоторые параметры sysctl не применились (nf_conntrack будет доступен позже)."
        sysctl -p "$f" 2>/dev/null || true
    fi
}

_sysctl_ip_tcpip() {
    log "Настройка sysctl IP Forwarding и TCP/IP Hardening..."
    ![ -d ${sysctl_dir} ] 2>/dev/null || mkdir -p ${sysctl_dir}
    local f="$sysctl_dir/85-amneziawg-IP-tcpIP.conf"
    cat > "$f" << EOF
# --- IP Forwarding ---
net.ipv4.ip_forward = 1
$(if [[ "${DISABLE_IPV6:-1}" -eq 1 ]]; then
    echo "net.ipv6.conf.all.disable_ipv6 = 1"
    echo "net.ipv6.conf.default.disable_ipv6 = 1"
    echo "net.ipv6.conf.lo.disable_ipv6 = 1"
else
    echo "# IPv6 не отключен"
    echo "net.ipv6.conf.all.forwarding = 1"
fi)
# --- TCP/IP Hardening ---
# rp_filter = 2 (loose mode): проверяет source IP по ANY маршруту в таблице,
# а не по обратному маршруту через тот же интерфейс. Strict mode (=1) ломает
# routing на облачных хостерах (Hetzner и подобных) где шлюз в другой подсети,
# чем IP самой VPS — ответные пакеты не проходят strict reverse path check.
# Loose mode безопасен: подделанные source IP всё равно отсеиваются если для
# них нет маршрута вообще. Discussion #41 (z036).
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
net.ipv4.tcp_rfc1337 = 1
# --- Redirects ---
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
$(if [[ "${DISABLE_IPV6:-1}" -ne 1 ]]; then
    echo "net.ipv6.conf.all.accept_redirects = 0"
    echo "net.ipv6.conf.default.accept_redirects = 0"
fi)
EOF
    log "Применение sysctl..."
    if ! sysctl -p "$f" >/dev/null 2>&1; then
        log_warn "Некоторые параметры sysctl не применились (nf_conntrack будет доступен позже)."
        sysctl -p "$f" 2>/dev/null || true
    fi
}

_sysctl_ip_tcp() {
    log "Настройка sysctl BBR, Conntrack и Security..."
    ![ -d ${sysctl_dir} ] 2>/dev/null || mkdir -p ${sysctl_dir}
    local f="${sysctl_dir}/88-amneziawg-security.conf"
    cat > "$f" << EOF
# --- BBR Congestion Control ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- Conntrack ---
net.netfilter.nf_conntrack_max = 65536

# --- Security ---
vm.swappiness = 10
kernel.sysrq = 0
EOF
    log "Применение sysctl..."
    if ! sysctl -p "$f" >/dev/null 2>&1; then
        log_warn "Некоторые параметры sysctl не применились (nf_conntrack будет доступен позже)."
        sysctl -p "$f" 2>/dev/null || true
    fi
}

_sysctl_kernel_printk() {
    log "Настройка sysctl - Подавление kernel warning/notice messages в VNC-консоли хостера..."
    ![ -d ${sysctl_dir} ] 2>/dev/null || mkdir -p ${sysctl_dir}
    local f="$sysctl_dir/91-amneziawg-kernel_printk.conf"
    cat > "$f" << EOF
# Подавление kernel warning/notice messages в VNC-консоли хостера.
# Без этого fail2ban блокировки спамят VNC окно строками типа "[BLOCK]" и делают консоль непригодной для работы.
# Format: console_loglevel default_msg_loglevel min_console_loglevel default_console_loglevel
# Значение 3 = KERN_ERR — на консоль идут только ошибки и критические (Discussion #41 (z036)).
kernel.printk = 3 4 1 3
EOF

    log "Применение sysctl..."
    if ! sysctl -p "$f" >/dev/null 2>&1; then
        log_warn "Некоторые параметры sysctl не применились (nf_conntrack будет доступен позже)."
        sysctl -p "$f" 2>/dev/null || true
    fi
}

# Настройка sysctl (минимальная, для --no-tweaks)
# ==============================================================================
_sysctl_minimal() {
    log "Настройка минимального sysctl (--no-tweaks)..."
    ![ -d ${sysctl_dir} ] 2>/dev/null || mkdir -p ${sysctl_dir}
    local f="$sysctl_dir/51-amneziawg-forwarding.conf"
    cat > "$f" << SYSEOF
# AmneziaWG — минимальные настройки (--no-tweaks)
net.ipv4.ip_forward = 1
SYSEOF
    if [[ "${DISABLE_IPV6:-1}" -eq 1 ]]; then
        cat >> "$f" << SYSEOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
SYSEOF
    else
        cat >> "$f" << SYSEOF
net.ipv6.conf.all.forwarding = 1
SYSEOF
    fi
    sysctl -p "$f" >/dev/null 2>&1 || log_warn "Ошибка sysctl -p"
    log "Минимальный sysctl настроен."
}

optimize_nic() {
    log "Оптимизация сетевого интерфейса"
    if [[ -z "$ifext" ]]; then
        log_error "Основной NIC не определён, пропуск оптимизации."
        return 1
    fi
    if ! command -v ethtool &>/dev/null; then
        log_warn "ethtool не найден, пропуск NIC оптимизации."
        return 0
    fi
    log "Оптимизация NIC: $ifext"
    log "Отключение GRO/GSO/TSO — могут мешать VPN-трафику"
    ethtool -K $ifext gro off 2>/dev/null || log_warn "GRO: не поддерживается/уже выкл."
    ethtool -K $ifext gso off 2>/dev/null || log_warn "GSO: не поддерживается/уже выкл."
    ethtool -K $ifext tso off 2>/dev/null || log_warn "TSO: не поддерживается/уже выкл."
    log "NIC оптимизация завершена."
}

menu_main() {
    declare mItems=("Подавление kernel warning/notice" "Настройка Адаптивных буферов" "Настройка IP Forwarding и TCP/IP Hardening" "Настройка BBR, Conntrack и Security" "Настройка минимального sysctl" "Оптимизация сетевого интерфейса")
    declare mActions=("_sysctl_kernel_printk" "_sysctl_buffers" "_sysctl_ip_tcpip" "_sysctl_ip_tcp" "_sysctl_minimal" "optimize_nic")
    declare Title="VPN оптимизация"
    declare Descr=""
    declare Type="section"

    awg_header
      while true; do
        show_mItems

        case "$choice" in
            1) _sysctl_kernel_printk  || { print_warn "Ошибка в разделе $choise[1]"; menu_pause; } ;;
            2) _sysctl_buffers        || { print_warn "Ошибка в разделе $choise[2]"; menu_pause; } ;;
            3) _sysctl_ip_tcpip       || { print_warn "Ошибка в разделе $choise[3]"; menu_pause; } ;;
            4) _sysctl_ip_tcp         || { print_warn "Ошибка в разделе $choise[4]"; menu_pause; } ;;
            5) _sysctl_minimal        || { print_warn "Ошибка в разделе $choise[4]"; menu_pause; } ;;
            6) optimize_nic           || { print_warn "Ошибка в разделе $choise[4]"; menu_pause; } ;;
            0) echo ""; echo "  Выход."; echo ""; exit 0 ;;
            q) printf "\n    ${bred}Выход.\n${nc}"; exit 0 ;;
            *) print_warn "Введите число от 0 до 6"; menu_pause ;;
        esac
        menu_pause
        awg_header
    done
}

menu_main
printf "    %s\n" "$dashes"
