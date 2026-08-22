#!/usr/bin/env bash

#########################
### Заголовок скрипта ###
#########################
# AWG Tools: стартовые проверки

#####################
### Проверка bash ###
#####################
if [ -z "$BASH_VERSION" ]; then
    echo "Запустите через bash: bash $0!" >&2
    exit 1
fi

set -o pipefail

#set -o allexport
#export $(grep -v '^#' .env | xargs)
#set +o allexport

# Подключаем .[...]-env
SELF="$(readlink -f "${BASH_SOURCE[0]}")" #export PATH="${SELF%/*}:$PATH"
cur_dir=${SELF%/*}
dir_name=${cur_dir##*/}
PROJ_ENV=${cur_dir%/*}
me_ext=$(basename "$0")
me="${me_ext%.*}"

. ${PROJ_ENV}/.${me}-env

#echo $me; echo "cur_dir=$cur_dir"; echo "dir_name=$dir_name"; echo "PROJ_ENV=$PROJ_ENV"; exit 0

. ${PROJ_ENV}/.${app_name}-colors
. ${PROJ_ENV}/.${app_name}-output
. ${PROJ_ENV}/.${app_name}-func

LOCKFILE="/var/run/awg-tools-stack.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    log_error "Скрипт уже запущен (lock: ${LOCKFILE})!"
    ask_yn "${bnc}Хотите удалить и продолжить? " "n" dellock
    if [[ "$dellock" == "yes" ]]; then
        rm ${LOCKFILE}
    else
        die "$LOCKFILE не удалён, выход."
    fi
    echo -e ${nc}
fi

##########################
### Стартовые проверки ###
##########################
check_root
check_virt
validate_os_ver

#####################
### Проверка root ###
#####################
if [[ "$EUID" -ne 0 ]]; then
    die "${bred}Запустите от root: sudo bash $0!${nc}"
fi

