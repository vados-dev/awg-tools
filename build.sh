#!/usr/bin/env bash
# --> BUILD <--
# - собирает модули из src/ в один файл awg_tools.sh -
# - порядок файлов важен: header первый, entry последний -

# Подключаем .[...]-env
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
#export PATH="${SELF%/*}:$PATH"
. ${SELF%/*}/.awg-tools-env AWG-Tools AWG-TOOLS
. ${SELF%/*}/.${dir_name}-colors
. ${SELF%/*}/.${dir_name}-output
. ${SELF%/*}/.${dir_name}-func

SRC_DIR=${SELF%/*}/src
OUT_FILE=${SELF%/*}/${dir_name}.sh

set -euo pipefail

#FW_TYPE="firewalld"
#if [[ "$FW_TYPE" = "firewalld" ]]; then fw="04e_firewalld.sh"; elif [[ "$FW_TYPE" = "ufw" ]]; then fw="04e_ufw.sh"; fi

# - порядок сборки: header -> модули -> меню -> entry -
FILES=(
    "00_header.sh"
    "01_info.sh"
    "02_utils.sh"
    "03_nmcli.sh"
    "04_fwcmd.sh"
    "05_diag.sh"
    "06_install.sh"
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
