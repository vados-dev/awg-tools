#!/usr/bin/env bash
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
cur_dir=${SELF%/*}
#dir_name=${cur_dir##*/}
me_ext=$(basename "$0")
me="${me_ext%.*}"

. /root/.${me}/.${me}-env

echo $me
echo "cur_dir=$cur_dir"
echo "dir_name=$dir_name"

. ${env_dir}/.${app_name}-colors
. ${env_dir}/.${app_name}-output
. ${env_dir}/.${app_name}-func

# --> Функции "system_check" <--
check_root() { if [ $(id -u) -ne 0 ]; then die "This script must be run as root."; fi }
check_virt() { if grep "container=" /proc/1/environ > /dev/null 2>&1; then die "Containers is not supported."; fi }
check_os() { . "/etc/os-release"; os_id="$ID"; os_ver="$VERSION_ID"; }
validate_os_ver() {
    case "$os_id" in
        "debian")
            if [ "$os_ver" -lt 12 ]; then
                die "Your version of Debian ${os_ver} is not supported. Please use Debian 12 or later."
            fi
            ;;
        "almalinux")
            MAJOR_VERSION="${os_ver%%.*}"
            if [ "$MAJOR_VERSION" -lt 9 ]; then
                die "Your version of Alma ${os_ver} is not supported. Please use Alma 9 or later."
            fi
            ;;
        "rocky")
            MAJOR_VERSION="${os_ver%%.*}"
            if [ "$MAJOR_VERSION" -lt 9 ]; then
                die "Your version of Rocky ${os_ver} is not supported. Please use Rocky 9 or later."
            fi
            ;;
        "centos")
            MAJOR_VERSION="${os_ver%%.*}"
            if [ "$MAJOR_VERSION" -lt 9 ]; then
                die "Your version of CentOS ${os_ver} is not supported. Please use CentOS 9 or later."
            fi
            ;;
        *)
            die "Your Linux distribution is not supported."
            ;;
    esac
}

check_root
check_virt
check_os
validate_os_ver

# --> ПРОВЕРКА ROOT <--
# - все операции требуют root -
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${bred}Запусти от root: sudo bash $0${nc}"
    exit 1
fi

