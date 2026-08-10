# --> Функции подменю "Утилиты" -> "Firewalld" <--

########################
### функции проверок ###
########################
function fw_check_xml { ! command -v grep "error" | /etc/firewalld/tools/check.sh >&2 || return 1; }

###############################
### функции основной логики ###
###############################
fw_restart() {
_fw_restart=$(systemctl restart firewalld.service | awk '{print "    " $0}')
printf "\n    Перезапуск firewalld:${bgrn}%s\n${nc}" "${_fw_restart}";
}

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
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -r, restart           Перезапустить")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -rl, reload           Перечитать конфиги")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -pmt, perm            Перманентно")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -la, list-all         Вывод всех правил")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -laz, list-all-zones  Вывод всех зон")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " -h, --help            Показать эту справку и выйти")";
        printf "   ${bnc}│${blub}%s${bnc}│${nc}\n" "$(align::left $COLS_NUM " ")";
        printf "   ${bnc}└%s┘${nc}\n\n" "$(align::left $((${COLS_NUM})) "$dashes")";
}

fw_fwcmd() {
############################
### Обработка аргументов ###
############################
FW_CMD="firewall-cmd"; FW_NO_ARGS=0; FW_RUN_CMD=""; FW_RUN=""; FW_ARGS=""; FW_HELP_EXIT_RC=0;
let $# || { FW_NO_ARGS=1; FW_HELP=1; }
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|restart)           FW_RUN_CMD="fw_restart"; break ;;
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
if [[ "$FW_RUN_CMD" == "fw_restart" ]]; then fw_restart; exit $FW_HELP_EXIT_RC; fi
if [[ "$FW_RUN_CMD" == "fw_run_cmd" ]]; then fw_run_cmd $FW_RUN $FW_ARGS; exit $FW_HELP_EXIT_RC; fi
if [[ -z "$FW_RUN_CMD" ]]; then fw_show_help; else FW_ARGS="$1"; fw_run_once "$FW_ARGS"; exit $FW_HELP_EXIT_RC; fi
}
