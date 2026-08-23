#!/usr/bin/env bash
# --> BUILD <--
# - собирает модули из src/ в один файл ${dir_name}.sh -
# - порядок файлов важен: header первый, entry последний -

SELF="$(readlink -f "${BASH_SOURCE[0]}")" #export PATH="${SELF%/*}:$PATH"
cur_dir=${SELF%/*}
#PROJ_ENV=${cur_dir%/*}
dir_name=${cur_dir##*/}
PROJ_ROOT=${PROJ_ROOT:-/root/.${dir_name}}
SRC_DIR=${cur_dir}/src

#######################
### Подключаем env: ###
#######################
source ${PROJ_ENV:-${PROJ_ROOT}/.${dir_name}-env}
source ${PROJ_ENV:-${PROJ_ROOT}/.${dir_name}-colors}
#echo "cur_dir=$cur_dir"
#echo "dir_name=$dir_name"
#echo "PROJ_ROOT=$PROJ_ROOT"
#echo
#echo "me_ext=$me_ext"
#echo "me=$me"
#echo $sym_door
#exit 0

OUT_FILE="${PROJ_ROOT}/bin/${dir_name}.sh"

set -euo pipefail

#FW_TYPE="firewalld"
#if [[ "$FW_TYPE" = "firewalld" ]]; then fw="04e_firewalld.sh"; elif [[ "$FW_TYPE" = "ufw" ]]; then fw="04e_ufw.sh"; fi

# - порядок сборки: header -> модули -> меню -> entry -
FILES=(
    "00_header.sh"
    "01_info.sh"
    "03_awg3_common.sh"
    "03a_awg3_client.sh"
    "03b_awg3_server.sh"
    "05_install.sh"
    "06_install_utils.sh"
    "07_diag.sh"
    "08_nmcli.sh"
    "09_fwcmd.sh"
    "10_utils.sh"
#    "20_awg3_generator.sh"
    "main.sh"
    "99_entry.sh"
)

echo "Сборка ${code_name} v${version}..."
echo ""

# - начинаем с shebang -
echo '#!/usr/bin/env bash' > "$OUT_FILE"
echo '# =============================================================================' >> "$OUT_FILE"
echo "# ${code_name} v${version}" >> "$OUT_FILE"
echo "# ${pr_descr}" >> "$OUT_FILE"
echo "# Git-Hub: https://github.com/${pr_owner}/${repo_name}/" >> "$OUT_FILE"
echo "# Собран: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUT_FILE"
echo '# =============================================================================' >> "$OUT_FILE"
echo '' >> "$OUT_FILE"

TOTAL_LINES=0
MISSING=0

for f in "${FILES[@]}"; do
    src="${SRC_DIR}/${f}"
    if [[ ! -f "$src" ]]; then
        echo "  ПРОПУЩЕН: ${f} (файл не найден)"
        MISSING=$((MISSING + 1))
        continue
    fi

    lines=$(wc -l < "$src")
    TOTAL_LINES=$((TOTAL_LINES + lines))

    echo "" >> "$OUT_FILE"
    echo "# === ${f} ===" >> "$OUT_FILE"

    # - пропускаем shebang из модулей, он уже есть в начале -
    if head -1 "$src" | grep -q '^#!/'; then
        tail -n +2 "$src" >> "$OUT_FILE"
    else
        cat "$src" >> "$OUT_FILE"
    fi

    echo "  [OK] ${f} (${lines} строк)"
done

chmod +x "$OUT_FILE"

echo ""
echo "Готово: ${OUT_FILE}"
echo "Строк: ${TOTAL_LINES}"
echo "Модулей: ${#FILES[@]} (пропущено: ${MISSING})"
echo "Размер: $(du -h "$OUT_FILE" | awk '{print $1}')"
