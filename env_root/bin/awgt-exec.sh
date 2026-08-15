#!/usr/bin/env bash

set -o pipefail

me_alias="awgt"
default_run=_exec #show_help

SELF="$(readlink -f "${BASH_SOURCE[0]}")" #export PATH="${SELF%/*}:$PATH"
cur_dir=${SELF%/*}
#dir_name=${cur_dir##*/}
#me_ext=$(basename "$0")
#me="${me_ext%.*}"

PROJ_NAME="awg-tools"
PROJ_ROOT=${cur_dir%/*}
PROJ_ENV=${PROJ_ROOT:-${cur_dir%/*}}
PROJ_BIN="${PROJ_ROOT}/bin/"

#echo $PROJ_ENV; exit 0

SRC_ROOT="/etc/VPN/tools/${PROJ_NAME}"
BUILD_SCRIPT="${SRC_ROOT}/build.sh"
SRC_DIR="${SRC_ROOT}/src"

OUT_FILE="${PROJ_BIN}${PROJ_NAME}.sh"

###########################
### Подключаем инклюды: ###
###########################
. ${PROJ_ENV}/.${PROJ_NAME}-colors

##################
### Запускалки ###
##################
show_test() {
echo $OUT_FILE
echo $SRC_DIR
echo $BUILD_SCRIPT
exit 0
}

_build() {
    bash ${BUILD_SCRIPT} ${PROJ_ENV} ${PROJ_BIN}
}

_exec() {
    bash ${OUT_FILE}
}

_check(){
    if ! flock -n 9; then
        printstr "Скрипт уже запущен (lock: %s)\n" "${LOCKFILE}"
        return 0
    else
        return 1
    fi
}

show_help() {
    echo -e "${bld} Управление запуском скрипта${byel} ${me_alias}${bnc}."
    echo -e "┌──────────────────────────────────────────────────────────────────┐"
    echo -e "│          Использование: sudo bash ${bgrn}${me_alias}${bnc} [${byell}ОПЦИИ${bnc}]                   │"
    echo -e "├──────────────────────────────────────────────────────────────────┤"
    echo -e "│ ${byel}Опции${bnc}:                                                           │"
    echo -e "│   ${byel}build${bnc}, ${byel}-b${bnc}             - Собрать скрипт                         │"
    echo -e "│   ${byel}run${bnc}, ${byel}-r${bnc}               - Запустить скрипт                       │"
    echo -e "│   ${byel}test${bnc}, ${byel}-t${bnc}              - Запустить тестовую функцию и выйти     │"
    echo -e "│   ${byel}help${bnc}, ${byel}-h${bnc}              - Показать эту справку и выйти           │"
    echo -e "│   ${byel}без аргументов${bnc}        - Запустить default_run                  │"
    echo -e "│                                                                  │"
    echo -e "└──────────────────────────────────────────────────────────────────┘${nc}"
    exit "${EXIT_RC:-0}"
}
#######################
### Основная логика ###
#######################
echo -e ${nc}
if [ "$#" -lt 1 ]; then
        $default_run
else
#        if [ "$2" = "-y" ] || [ "$2" = "-Y" ]; then
#                commandConfirmed="true"
#        fi

        if [ "$1" = "build" ]||[ "$1" = "-b" ]; then
                _build
        elif [ "$1" = "start" ]||[ "$1" = "run" ]||[ "$1" = "-s" ]; then
                    _exec
        elif [ "$1" = "help" ]||[ "$1" = "-h" ]; then
                show_help
        elif [ "$1" = "test" ]||[ "$1" = "-t" ]; then
                show_test
        else
            show_help
        fi
fi
printf "%s\n" "$dashes"
