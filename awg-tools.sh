#!/usr/bin/env bash
# =============================================================================
# awg-tools v0.0.1
# Менеджер AWG стека: WG/AWG VPN
# Git-Hub: https://github.com/vados-dev/awg-tools/
# Собран: 2026-07-30T08:48:58Z
# =============================================================================


# === 00_header.sh ===
# --> ЗАГОЛОВОК СКРИПТА <--
# - AWG Tools: общие функции, переменные, book блок -

# - проверка bash -
if [ -z "$BASH_VERSION" ]; then 
    echo "Запусти через bash: bash $0" >&2
    exit 1
fi

set -o pipefail

LOCKFILE="/var/run/awg-tools-stack.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "Скрипт уже запущен (lock: ${LOCKFILE})"
    exit 1
fi

#set -o allexport
#export $(grep -v '^#' .env | xargs)
#set +o allexport

# Подключаем .[...]-env
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
#export PATH="${SELF%/*}:$PATH"
. ${SELF%/*}/.awg-tools-env
. ${SELF%/*}/.${dir_name}-colors
. ${SELF%/*}/.${dir_name}-output
. ${SELF%/*}/.${dir_name}-func

check_root() {
    if [ $(id -u) -ne 0 ]; then
        die "This script must be run as root."
    fi
}
check_virt() {
    if grep "container=" /proc/1/environ > /dev/null 2>&1; then
        die "Containers is not supported."
    fi
}

check_os() {
    . "/etc/os-release"
    os_id="$ID"
    os_ver="$VERSION_ID"
}

validate_os_ver() {
    case "$os_id" in
        "debian")
            if [ "$os_ver" -lt 12 ]; then
                echo "Your version of Debian ${os_ver} is not supported. Please use Debian 12 or later."
                exit 1
            fi
            ;;
        "almalinux")
            MAJOR_VERSION="${os_ver%%.*}"
            if [ "$MAJOR_VERSION" -lt 9 ]; then
                echo "Your version of Alma ${os_ver} is not supported. Please use Alma 9 or later."
                exit 1
            fi
            ;;
        "rocky")
            MAJOR_VERSION="${os_ver%%.*}"
            if [ "$MAJOR_VERSION" -lt 9 ]; then
                echo "Your version of Rocky ${os_ver} is not supported. Please use Rocky 9 or later."
                exit 1
            fi
            ;;
        "centos")
            MAJOR_VERSION="${os_ver%%.*}"
            if [ "$MAJOR_VERSION" -lt 9 ]; then
                echo "Your version of CentOS ${os_ver} is not supported. Please use CentOS 9 or later."
                exit 1
            fi
            ;;
        *)
            echo "Your Linux distribution is not supported."
            exit 1
            ;;
    esac
}

# --> ПРОВЕРКА ROOT <--
# - все операции требуют root -
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${bred}Запусти от root: sudo bash $0${nc}"
    exit 1
fi

check_root
check_virt
check_os
validate_os_ver

# === 01_info.sh ===
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
printf "\n    AWG Соединения:\n%s\n" $(log $awg_all)
printf "${nc}"
}

# --> МЕНЮ: Инфо <--
menu_info() {
    declare mItems=("Просмотр соединений и маршрутов" "Просмотр соединений AWG")
    declare mActions=("ip_show" "awg_show")
    declare mTitle="Информация"
    declare mDescr=""
    declare mType="section"
    show_menu
}

# === 02_utils.sh ===
# --> Функции подменю "Утилиты" <--

#####################################
### Функции подменю "Оптимизация" ###
#####################################
# Настройка sysctl (расширенная)
# ==============================================================================
awg_optimize_sysctl_buffers() {
    log "Настройка Адаптивных буферов sysctl..."
    ![ -d ${AWG_OPTIMIZE_SYSCTL_DIR} ] 2>/dev/null || mkdir -p ${AWG_OPTIMIZE_SYSCTL_DIR}
    local f="${AWG_OPTIMIZE_SYSCTL_DIR}/80-amneziawg-buffers.conf"
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
    if [[ "$AWG_OPTIMIZE_SYSCTL_DIR" == "/etc/sysctl.d" ]]; then
        log "Применение sysctl..."
        if ! sysctl -p "$f" >/dev/null 2>&1; then
            log_warn "Некоторые параметры sysctl не применились."
            sysctl -p "$f" 2>/dev/null || true
        fi
    else
        log "Параметры были записаны в файл $f."
        log "Его можно скопировать в /etc/sysctl.d и применить командой sysctl -p /etc/sysctl.d/80-amneziawg-buffers.conf."
    fi
}

awg_optimize_sysctl_ip_tcpip() {
    log "Настройка sysctl IP Forwarding и TCP/IP Hardening..."
    ![ -d ${AWG_OPTIMIZE_SYSCTL_DIR} ] 2>/dev/null || mkdir -p ${AWG_OPTIMIZE_SYSCTL_DIR}
    local f="${AWG_OPTIMIZE_SYSCTL_DIR}/85-amneziawg-IP-tcpIP.conf"
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
    if [[ "$AWG_OPTIMIZE_SYSCTL_DIR" == "/etc/sysctl.d" ]]; then
        log "Применение sysctl..."
        if ! sysctl -p "$f" >/dev/null 2>&1; then
            log_warn "Некоторые параметры sysctl не применились."
            sysctl -p "$f" 2>/dev/null || true
        fi
    else
        log "Параметры были записаны в файл $f."
        log "Его можно скопировать в /etc/sysctl.d и применить командой sysctl -p /etc/sysctl.d/85-amneziawg-IP-tcpIP.conf."
    fi
}

awg_optimize_sysctl_ip_tcp() {
    log "Настройка sysctl BBR, Conntrack и Security..."
    ![ -d ${AWG_OPTIMIZE_SYSCTL_DIR} ] 2>/dev/null || mkdir -p ${AWG_OPTIMIZE_SYSCTL_DIR}
    local f="${AWG_OPTIMIZE_SYSCTL_DIR}/88-amneziawg-security.conf"
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
    if [[ "$AWG_OPTIMIZE_SYSCTL_DIR" == "/etc/sysctl.d" ]]; then
        log "Применение sysctl..."
        if ! sysctl -p "$f" >/dev/null 2>&1; then
            log_warn "Некоторые параметры sysctl не применились (nf_conntrack будет доступен позже)."
            sysctl -p "$f" 2>/dev/null || true
        fi
    else
        log "Параметры были записаны в файл $f."
        log "Его можно скопировать в /etc/sysctl.d и применить командой sysctl -p /etc/sysctl.d/88-amneziawg-security.conf."
    fi
}

awg_optimize_sysctl_kernel_printk() {
    log "Настройка sysctl - Подавление kernel warning/notice messages в VNC-консоли хостера..."
    ![ -d ${AWG_OPTIMIZE_SYSCTL_DIR} ] 2>/dev/null || mkdir -p ${AWG_OPTIMIZE_SYSCTL_DIR}
    local f="${AWG_OPTIMIZE_SYSCTL_DIR}/91-amneziawg-kernel_printk.conf"
    cat > "$f" << EOF
# Подавление kernel warning/notice messages в VNC-консоли хостера.
# Без этого fail2ban блокировки спамят VNC окно строками типа "[BLOCK]" и делают консоль непригодной для работы.
# Format: console_loglevel default_msg_loglevel min_console_loglevel default_console_loglevel
# Значение 3 = KERN_ERR — на консоль идут только ошибки и критические (Discussion #41 (z036)).
kernel.printk = 3 4 1 3
EOF
    if [[ "$AWG_OPTIMIZE_SYSCTL_DIR" == "/etc/sysctl.d" ]]; then
        log "Применение sysctl..."
        if ! sysctl -p "$f" >/dev/null 2>&1; then
            log_warn "Некоторые параметры sysctl не применились."
            sysctl -p "$f" 2>/dev/null || true
        fi
    else
        log "Параметры были записаны в файл $f."
        log "Его можно скопировать в /etc/sysctl.d и применить командой sysctl -p /etc/sysctl.d/91-amneziawg-kernel_printk.conf."
    fi
}

# Настройка sysctl (минимальная, для --no-tweaks)
# ==============================================================================
awg_optimize_sysctl_minimal() {
    log "Настройка минимального sysctl (--no-tweaks)..."
    ![ -d ${AWG_OPTIMIZE_SYSCTL_DIR} ] 2>/dev/null || mkdir -p ${AWG_OPTIMIZE_SYSCTL_DIR}
    local f="${AWG_OPTIMIZE_SYSCTL_DIR}/51-amneziawg-forwarding.conf"
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

    if [[ "$AWG_OPTIMIZE_SYSCTL_DIR" == "/etc/sysctl.d" ]]; then
        log "Применение sysctl..."
        if ! sysctl -p "$f" >/dev/null 2>&1; then
            log_warn "Ошибка sysctl -p"
            sysctl -p "$f" 2>/dev/null || true
        fi
    else
        log "Минимальный sysctl настроен."
        log "Параметры были записаны в файл $f."
        log "Его можно скопировать в /etc/sysctl.d и применить командой sysctl -p /etc/sysctl.d/51-amneziawg-forwarding.conf."
    fi
}

awg_optimize_nic() {
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

menu_awg_optimize() {
    declare mItems=("Подавление kernel warning/notice" "Настройка Адаптивных буферов" "Настройка IP Forwarding и TCP/IP Hardening" "Настройка BBR, Conntrack и Security" "Настройка минимального sysctl" "Оптимизация сетевого интерфейса")
    declare mActions=("awg_optimize_sysctl_kernel_printk" "awg_optimize_sysctl_buffers" "awg_optimize_sysctl_ip_tcpip" "awg_optimize_sysctl_ip_tcp" "awg_optimize_sysctl_minimal" "awg_optimize_nic")
    declare mTitle="AWG оптимизация"
    declare mDescr=""
    declare mType="section"
    show_menu
}

menu_utils() {
    declare mItems=("AWG оптимизация" "Просмотр девайсов" "Просмотр Окружения")
    declare mActions=("menu_awg_optimize" "show_devices" "show_environment")
    declare mTitle="Утилиты"
    declare mDescr=""
    declare mType="section"
    show_menu
}
# === 03_nmcli.sh ===
# --> Функции подменю "NetworkManager" <--
nmcli_show_conn() {
mn_show_conn=$(nmcli -c yes con show | awk '{print "    " $0}')
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

# === 04_fwcmd.sh ===
# --> Функции подменю "Утилиты" -> "Firewalld" <--

########################
### функции проверок ###
########################
function fw_check_xml { ! command -v grep "error" | /etc/firewalld/tools/check.sh >&2 || return 1; }

###############################
### функции основной логики ###
###############################
function show_command { printf "${bnc}Запуск ${bgrn}%s${bnc} c аргументами: [${byel} %s ${bnc}].${nc}\n" "$1" "$2"; }
fw_def_cmd() {
    if ! fw_check_xml 2>&1; then
        _run=${FW_CMD}
        _arg=${ARGS:-"--help"}
        show_command "${_run}" "${_arg}"
        _ret=$($_run $_arg 2>&1)
        if [ $? -eq 0 ]; then
            printf "${bgrn}%s${nc}\n" "${_ret}"
        else
            printf "${bred}%s${nc}\n" "${_ret}"
        fi
    fi
}
fw_run_once() {
    if ! fw_check_xml 2>&1; then
        _run="echo -en"
        _arg="$ARGS"
        show_command "${_run}" "${_arg}"
        printf "${bnc}%s${nc}\n" "${ret}"
    fi
}
fw_run_cmd() {
    if ! fw_check_xml 2>&1; then
        _run="$RUN"
        _arg="$RUN $ARGS"
        show_command "$0" "${_arg}"
        _ret=$($_run $_arg 2>&1)
        if [ $? -eq 0 ]; then
            printf "${bnc}%s${nc}\n" "${_ret}"
        else
            printf "${bred}%s${nc}\n" "${_ret}"
        fi
    fi
}


######################
### Другие функции ###
######################
function mark { export $1=`pwd`; }
function _msg { echo -e `date +"%Y-%m-%d %T"` "$1"; }
function _stamp { _msg "$1$2 ##########################################################################"; }

disp_iptables() {
echo -e ${bnc}"Display iptables: "${byel} && iptables -L -v -n && echo -e ${bnc}"Done"${nc}
}
reset_iptables() {
echo -e ${bnc}"Reset iptables: "${bred} iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X && echo -e ${bnc}"Done"${nc}
}

function list-all {
  firewall-cmd --list-rich-rules
  firewall-cmd --get-active-zones
  firewall-cmd --get-default-zone
  firewall-cmd --get-zones
  return=$?
}
function IPT_DNS {
  _msg "FWD $1 filter: DNS $2 $3"
  firewall-cmd $3 $2 --$1-service=dns
  return $?
}
function IPT_DHCPserver {
  _msg "FWD $1 filter: DHCPserver $2 $3"
  firewall-cmd $3 $2 --$1-service=dhcp
  return $?
}
function IPT_DHCPclient {
  _msg "FWD $1 filter: DHCPclient $2 $3"
  firewall-cmd $3 $2 --$1-service=dhcpv6-client
  return $?
}
function IPT_ZeroConfig {
  _msg "FWD $1 filter: ZeroConfig $2 $3"
  firewall-cmd $3 $2 --$1-service=mdns
  return $?
}
function IPT_UPnP {
  _msg "FWD $1 filter: UPnP $2 $3"
  firewall-cmd $3 $2 --$1-service=upnp-client
  return $?
}
function IPT_nfs {
  _msg "FWD $1 filter: nfs $2 $3"
  firewall-cmd $3 $2 --$1-service=nfs --$1-service=nfs3 --$1-service=mountd --$1-service=rpc-bind
  return $?
}
function FWD_reload {
  _msg "FWD $1 filter: reload $2 $3"
  firewall-cmd --reload
  return $?
}

ret=0
case "$opt1" in
  IFadd)
    FWD_IFadd "$actn" "$zone" "$perm"
    ret=$?
    ;;
  DNS)
    IPT_DNS "$actn" "$zone" "$perm"
    ret=$?
    ;;
  DHCPserver)
    IPT_DHCPserver "$actn" "$zone" "$perm"
    ret=$?
    ;;
  DHCPclient)
    IPT_DHCPclient "$actn" "$zone" "$perm"
    ret=$?
    ;;
  ZeroConfig)
    IPT_ZeroConfig "$actn" "$zone" "$perm"
    ret=$?
    ;;
  UPnP)
    IPT_UPnP "$actn" "$zone" "$perm"
    ret=$?
    ;;
  nfs)
    IPT_nfs "$actn" "$zone" "$perm"
    ret=$?
    ;;
  reload)
    FWD_reload "$actn" "$zone" "$perm"
    ret=$?
    ;;
#  list-all)
#    list-all
#    ret=$?
#    ;;
  version)
    ret="$version"
    ;;
  *) echo # fwcmd "$1 $2 $3 $4"
    ;;
#    echo "Usage: ${0##*/} 4pump | list | version | noFW | IFadd | notICMPvisible | web | sambaclient | samba | mqtt | mqttws | DNS | ssh | mosh | rdp | rsync | CUPS | openVPN | NTP | cntlm | Warpin | fcgi | nodered | DHCPserver | syncthing | shellinabox | DHCPclient | ZeroConfig | UPnP | nfs | FAUXMO | ftp | ftps | hostapd | redis | redisHA | authelia | reload"
#    ret=1
esac

fw_show_help() {
        printf "   ${bnc}┌%s┐${nc}\n" "$(align::left $COLS_NUM "$dashes")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " ")";
        printf "   ${bnc}│${blub}${byel}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " Опции:")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -rl, reload           Перечитать конфиги")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -pmt, perm            Перманентно")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -la, list-all         Вывод всех правил")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -laz, list-all-zones  Вывод всех зон")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -h, --help            Показать эту справку и выйти")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " ")";
        printf "   ${bnc}└%s┘${nc}\n" "$(align::left $((${COLS_NUM})) "$dashes")";
        echo
}

fw_fwcmd() {
############################
### Обработка аргументов ###
############################
FW_CMD="firewall-cmd"; FW_NO_ARGS=0; FW_RUN_CMD=""; FW_RUN=""; FW_ARGS=""; FW_HELP_EXIT_RC=0;
let $# || { FW_NO_ARGS=1; FW_HELP=1; }
while [[ $# -gt 0 ]]; do
    case $1 in
        -rl|reload)           FW_RUN_CMD="fw_def_cmd"; FW_ARGS="--reload"; break ;;
        -pmt|perm)            FW_RUN_CMD="fw_def_cmd"; FW_ARGS="--permanent $2 $3 $4"; break ;;
        -la|list-all)         FW_RUN_CMD="fw_def_cmd"; FW_ARGS="--list-all"; break ;;
        -laz|list-all-zones)  FW_RUN_CMD="fw_def_cmd"; FW_ARGS="--list-all-zones"; break ;;
        -h|--help)            RUN_CMD="help"; HELP_EXIT_RC=0; break ;;
        *) FW_RUN_CMD="fw_run_once"; FW_RUN="$1"; FW_ARGS="$1"; break ;;
    esac
    shift
done

#######################
### Основная логика ###
#######################
if [[ "$FW_NO_ARGS" -eq 1 ]]; then echo -e " ${bred}Пустые аргументы [${byel}ОПЦИИ${bred}]! ${bnc}\n${nc}"; FW_RUN_CMD="fw_help"; fi
if [[ "$FW_RUN_CMD" == "fw_help" ]]; then fw_show_help "$FW_HELP_EXIT_RC"; exit $FW_HELP_EXIT_RC; fi
if [[ "$FW_RUN_CMD" == "fw_def_cmd" ]]; then fw_def_cmd $FW_ARGS; exit $FW_HELP_EXIT_RC; fi
if [[ "$FW_RUN_CMD" == "fw_run_cmd" ]]; then fw_run_cmd $FW_RUN $FW_ARGS; exit $FW_HELP_EXIT_RC; fi
if [[ -z "$FW_RUN_CMD" ]]; then fw_show_help; else FW_ARGS="$1"; fw_run_once "$FW_ARGS"; exit $FW_HELP_EXIT_RC; fi
}

# === main.sh ===
# --> ГЛАВНОЕ МЕНЮ <--
# - точка входа, навигация по разделам -

# --> ТОЧКА ВХОДА: ГЛАВНОЕ МЕНЮ <--
menu_main() {
    declare mItems=("Информация" "Утилиты" "NetworkManager" "Управление firewalld" "Окружение")
    declare mActions=("menu_info" "menu_utils" "nmcli_menu" "fwcmd_manage" "menu_env")
    declare mTitle="Главное меню $pr_name"
    declare mDescr=""
    declare mType="main"
    show_menu
}

# === 99_entry.sh ===
# --> ЗАПУСК <--
# - точка входа в скрипт -
show_menu() {
    local choice
    local index=0
    awg_header
    while true; do
        printf "${blub}╔%s╗${nc}\n" "$(align::center $COLS_NUM "$equals ${mTitle} $equals")"
        printf "${blub}║%s║${nc}\n" "$(align::center $COLS_NUM " ")"
        for idx in ${!mItems[@]}; do
            printf "${blub}║%s║${nc}\n" "$(align::left $COLS_NUM "  $((idx + 1))  -  ${mItems[$idx]}")"
            index=$((index + 1))
        done
        printf "${blub}║ ${und}%s${nc}${blub} ║${nc}\n" "$(align::center $((COLS_NUM-2)) ' ')"
        printf "${magb}║%s║${nc}\n" "$(align::center $COLS_NUM " ")"

        if [[ "$mType" != "main" ]]; then
            printf "${magb}║%s║${nc}\n" "$(align::left $COLS_NUM " 0  -  Назад")"
        fi

        printf "${redb}║%s║${nc}\n" "$(align::left $COLS_NUM " q  -  Выход")"
        printf "${redb}╚%s╝${nc}\n" "$(align::left $((${COLS_NUM})) "$equals")"
        _read_choice choice
        printf "${bnc}"

        if [[ "$mType" != "main" ]] && [[ "$choice" == "0" ]]; then
            printf "\n    ${byel}%s\n${nc}\n" "Возврат."
            return 0
        fi

        if [[ "$choice" == "q" ]]; then
            printf "\n    ${bred}%s\n${nc}\n" "Выход."
            exit 0
        fi

        if [[ "$choice" =~ ^[1-9]+$ ]] && (( choice >= 1 && choice <= ${#mActions[@]} )); then
            "${mActions[choice - 1]}"
        else
            printf "\n    ${bred}%s %d.${nc}\n\n" "Введите число от 1 до " ${index}
        fi
    if [[ "$mType" == "section" ]]; then
        menu_pause
    fi
    awg_header
    done
}

menu_main

printf "    %s\n" "$dashes"

