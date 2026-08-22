# --> Функции подменю "Установка AWG3" <--

# awg2_field FILE KEY -> значение из конфига AWG 2.0 (пусто, если нет).
awg2_field() {
    local file="$1" key="$2"
    [[ -r "$file" ]] || return 0
    awk -F'=' -v k="$key" '
        $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit
        }' "$file"
}

# gomod_go_version FILE -> минимальная версия Go из директивы `go` в go.mod.
gomod_go_version() {
    local file="${1:-}"
    [[ -r "$file" ]] || return 0
    awk '/^[[:space:]]*go[[:space:]]+[0-9]/ { print $2; exit }' "$file"
}

# check_go_toolchain REQUIRED CURRENT -> 0, если сборка возможна.
# Go >= 1.21 сам докачивает нужный toolchain, но только при GOTOOLCHAIN != local
# и наличии доступа к proxy.golang.org. Молча полагаться на это нельзя.
check_go_toolchain() {
    local required="${1:-}" current="${2:-}"
    [[ -n "$required" ]] || return 0
    if version_ge "$current" "$required"; then
        print_ok "Go ${current} покрывает требование go.mod (${required})"
        return 0
    fi
    local mode="${GOTOOLCHAIN:-auto}"
    if [[ "$mode" == "local" ]]; then
        log_error "go.mod требует Go >= ${required}, установлен ${current}, при этом GOTOOLCHAIN=local"
        log_error "варианты: export GOTOOLCHAIN=auto  либо поставить свежий Go вручную"
        return 1
    fi
    log_warn "go.mod требует Go >= ${required}, установлен ${current}"
    log "Go докачает toolchain сам (GOTOOLCHAIN=${mode}) — нужен доступ к proxy.golang.org"
    return 0
}

# safe_rm_tree PATH — удаление каталога с проверками.
# Пути берутся из переменных окружения (AWG3_PREFIX, AWG3_CONF_DIR), и пустое или короткое значение превратило бы rm -rf в катастрофу.
# Отвергаем всё, что не является абсолютным путём глубиной >= 2 внутри разрешённых префиксов.
awg3_safe_rm_tree() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        log_error "awg3_safe_rm_tree: пустой путь"; return 1
    fi
    if [[ "$target" != /* ]]; then
        log_error "awg3_safe_rm_tree: путь не абсолютный: '${target}'"; return 1
    fi
    if [[ "$target" == *..* ]]; then
        log_error "awg3_safe_rm_tree: путь содержит '..': '${target}'"; return 1
    fi
    local clean="${target%/}"
    local depth; depth="$(awk -F/ '{print NF - 1}' <<<"$clean")"
    if ((depth < 2)); then
        log_error "awg3_safe_rm_tree: путь слишком короткий, нужно >= 2 сегментов: '${target}'"
        return 1
    fi
    case "$clean" in
        /etc/VPN/helpers/awg3 | /etc/VPN/helpers/awg3/* | /etc/VPN/configs/awg3 | /etc/VPN/configs/awg3/*) : ;;
        *)
            log_error "awg3_safe_rm_tree: путь вне разрешённых префиксов: '${target}'"
            return 1
            ;;
    esac
    rm -rf -- "$clean"
}

# Читает конфиг AWG 2.0 и резервирует непересекающиеся порт и подсеть.
awg3_preflight() {
    step "Preflight: сосуществование с AWG 2.0"
    # Повторный запуск не должен менять порт: клиенты уже раздали конфиги
    # с прежним значением, и смена порта тихо оборвала бы их всех.
    if [[ -r "$AWG3_RESERVED_ENV" ]]; then
        local prev_port prev_subnet
        prev_port="$(awk -F= '/^AWG3_PORT=/{print $2}' "$AWG3_RESERVED_ENV")"
        prev_subnet="$(awk -F= '/^AWG3_SUBNET=/{print $2}' "$AWG3_RESERVED_ENV")"
        log_ok "переустановка: сохраняю прежний резерв"
        log "порт ${prev_port}, подсеть ${prev_subnet}"
        log "сбросить резерв: rm ${AWG3_RESERVED_ENV}"
        return 0
    fi
    local awg2_port="" awg2_addr="" awg2_net=""
    if [[ -r "$AWG2_CONF" ]]; then
        awg2_port="$(awg2_field "$AWG2_CONF" ListenPort)"
        awg2_addr="$(awg2_field "$AWG2_CONF" Address)"
        awg2_net="$(cidr_network "$awg2_addr")"
        log_ok "AWG 2.0 найден: ${AWG2_CONF}"
        [[ -n "$awg2_port" ]] && info "его порт   : ${awg2_port} (не займём)"
        [[ -n "$awg2_net"  ]] && info "его подсеть: ${awg2_net}/24 (обойдём)"
    else
        log "AWG 2.0 не найден — ставимся на чистый сервер"
    fi
    if [[ -d /sys/module/amneziawg ]]; then
        log_warn "загружен kernel-модуль amneziawg — это штатно, мы его не трогаем"
        log "именно поэтому AWG3 не пользуется awg-quick: при модуле он поднял бы"
        log "kernel-интерфейс вместо нашего userspace-демона"
    fi
    local our_port our_net
    our_port="$(pick_port "$awg2_port")"
    our_net="$(pick_subnet "$awg2_net")"
    validate_port "$our_port" || exit 1
    mkdir -p "$AWG3_CONF_DIR"; chmod 700 "$AWG3_CONF_DIR"
    cat >"$AWG3_RESERVED_ENV" <<EOF
# Зарезервировано установщиком AWG3 $(date -Is).
# Проверено на непересечение с AWG 2.0 на момент установки.
AWG3_IFACE=awg3
AWG3_PORT=${our_port}
AWG3_SUBNET=${our_net}/24
AWG3_ADDRESS=${our_net%.0}.1/24
AWG3_ROUTE_TABLE=${AWG3_ROUTE_TABLE}
AWG2_PORT_SEEN=${awg2_port:-none}
AWG2_SUBNET_SEEN=${awg2_net:-none}
EOF
    chmod 600 "$AWG3_RESERVED_ENV"
    log_ok "Зарезервировано: порт ${our_port}, подсеть ${our_net}/24, таблица ${AWG3_ROUTE_TABLE}."
    log "Записано в ${AWG3_RESERVED_ENV}."
}

# missing_tools -> список отсутствующих команд через пробел.
awg3_missing_tools() {
    local tool missing=()
    for tool in "$@"; do
         command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    printf '%s' "${missing[*]:-}"
}

awg3_check_dnf_updates() {
    read -rp "  Проверить обновления [y/N]: " confirm
    if [[ "$confirm" == "y" ]]; then
        dnf check-update -y > /dev/null 2>&1 || true
    else
        log "Не обновляю."
        return 0
    fi
}

# Догоняет недостающие утилиты. Вызывается и при установке, и при обновлении:
# на свежем сервере `--update` раньше падал на отсутствующем make уже после
# скачивания Go, оставляя половину установки.
awg3_ensure_tools() {
    if [[ "$os_type" == "rhel" ]]; then
        log "Проверка утилит ${AWG3_REQUIRED_TOLLS[@]}..."
        awg3_check_deps "${AWG3_REQUIRED_TOOLS[@]}" > /dev/null 2>&1 && log_ok "Все утилиты установлены." || log_error "Ошибка установки утилит!"
    else
        local missing
        missing="$(awg3_missing_tools "${AWG3_REQUIRED_TOOLS[@]}")"
        if [[ -z "$missing" ]]; then
            return 0
        fi
        log_warn "не хватает утилит: ${missing}"
        if ! command -v apt-get >/dev/null 2>&1; then
            die "apt-get недоступен — поставь вручную: ${missing}!"
        fi
        awg3_install_deps
        missing="$(awg3_missing_tools "${AWG3_REQUIRED_TOOLS[@]}")"
        if [[ -n "$missing" ]]; then
            die "После установки пакетов всё ещё нет: ${missing}!"
        fi
        log_ok "Недостающие утилиты доставлены."
    fi
}

# Функция от vados-dev в стиле dnf
awg3_check_deps() {
    local packages=("$@")
    local to_install=()
    local deps_pkg
    log "Список: ${packages[*]}"
    for deps_pkg in "${packages[@]}"; do
        if ! dnf list installed "$deps_pkg" 2>/dev/null | grep -q "Installed Packages"; then
             to_install+=("$deps_pkg")
        fi
    done
        if [ ${#to_install[@]} -eq 0 ]; then
            log_ok "Все зависимости установлены."
            return 0
        else
            log "Установка: ${to_install[*]}..."
            dnf install -y ${to_install[*]} > /dev/null 2>&1 && log_ok "Зависимости установлены." || return 1
        fi
}

awg3_install_deps() {
    if [[ "$os_type" == "rhel" ]]; then
        local deps=()
        deps=(git make curl python3 python3-pip)
        step "Проверка зависимостей: ${deps[@]}..."
        awg3_check_dnf_updates
        awg3_check_deps "${deps[@]}" > /dev/null 2>&1 && ok "Зависимости установлены" || return 1
    else
        step "Зависимости"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        # --no-install-recommends: иначе python3-pip тянет build-essential, gcc, g++, binutils, python3-dev — семьдесят пакетов вместо десяти.
        # У cryptography на amd64/arm64 есть готовые wheel, компилятор ей не нужен.
        apt-get install -y -qq --no-install-recommends \
        make curl ca-certificates iproute2 iptables python3 python3-venv python3-pip golang-go
        log_ok "базовые пакеты (включая golang-go из репозитория)"
    fi
}

# Ставит Go нужной версии: системный, если свежий, иначе официальный тарбол
# с проверкой контрольной суммы (fail-closed — без суммы не ставим).
# Печатает "filename sha256" для свежего стабильного Go под указанную арх.
# Разбор питоном, а не грепом: формат JSON у go.dev может быть как
# отформатированным, так и сжатым, и грep по нему — источник молчаливых сбоев.
awg3_fetch_go_release() {
        python3 - "$1" <<'PY' 2>/dev/null
import json, sys, urllib.request
arch = sys.argv[1]
try:
    with urllib.request.urlopen("https://go.dev/dl/?mode=json", timeout=30) as resp:
        releases = json.load(resp)
except Exception as exc:
    print(f"ошибка загрузки списка релизов: {exc}", file=sys.stderr)
    sys.exit(2)
for release in releases:
    if not release.get("stable"):
        continue
    for item in release.get("files", []):
        if (item.get("os") == "linux" and item.get("arch") == arch
                and item.get("kind") == "archive"):
            name, digest = item.get("filename"), item.get("sha256")
            if not name or not digest:
                continue
            print(name, digest)
            sys.exit(0)
sys.exit(1)
PY
}

# Ставит Go нужной версии: системный, если свежий, иначе официальный тарбол с обязательной проверкой sha256 (fail-closed).
# Запасной путь: если официальный тарбол недоступен, полагаемся на встроенный механизм Go (>= 1.21 сам докачивает toolchain).
# Работает только при GOTOOLCHAIN != local и доступе к proxy.golang.org — оба условия проверяем.
_fallback_toolchain() {
    local required="$1" sys_ver="$2"
    if [[ -z "$sys_ver" ]]; then
        log_error "Go не установлен и официальный тарбол недоступен!"
        log_error "Поставьте вручную: apt-get install -y golang-go!"
        return 1
    fi
    if ! version_ge "$sys_ver" "$GO_MIN"; then
        log_error "Go ${sys_ver} не умеет докачивать toolchain (нужен >= ${GO_MIN})!"
        return 1
    fi
    if [[ "${GOTOOLCHAIN:-auto}" == "local" ]]; then
        log_error "GOTOOLCHAIN=local запрещает докачку, а Go ${sys_ver} < ${required}!"
        log_error "Снимите ограничение: export GOTOOLCHAIN=auto!"
        return 1
    fi
    log_warn "Откат: собираю системным Go ${sys_ver} с автодокачкой toolchain."
    log "Нужен доступ к proxy.golang.org."
    GO_BIN="$(command -v go)"
    return 0
}

# ensure_go [REQUIRED] — обеспечивает toolchain нужной версии. REQUIRED берётся из go.mod исходников, поэтому вызывать после fetch_sources.
awg3_ensure_go() {
    local required="${1:-$GO_MIN}"
    step "Go toolchain (нужен >= ${required})"
    local sys_ver=""
    if command -v go >/dev/null 2>&1; then
        sys_ver="$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')"
        if [[ -n "$sys_ver" ]] && version_ge "$sys_ver" "$required"; then
        log_ok "Системный Go ${sys_ver} подходит."
        GO_BIN="$(command -v go)"
        return 0
        fi
        log "Системный Go ${sys_ver} младше ${required} — ставлю официальный."
    else
        log_warn "Go в системе не найден."
    fi
    # Уже собранный нами Go мог остаться от прошлой установки.
    if [[ -x "${AWG3_PREFIX}/go/bin/go" ]]; then
        local own_ver
        own_ver="$("${AWG3_PREFIX}/go/bin/go" version 2>/dev/null | awk '{print $3}' | sed 's/^go//')"
        if [[ -n "$own_ver" ]] && version_ge "$own_ver" "$required"; then
            log_ok "Собственный Go ${own_ver} в ${AWG3_PREFIX}/go подходит."
            GO_BIN="${AWG3_PREFIX}/go/bin/go"
            return 0
        fi
    fi
    local arch
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) die "Архитектура $(uname -m) не поддерживается!" ;;
    esac
    log "Тяну официальный Go для linux-${arch}."
    local release rc=0
    release="$(fetch_go_release "$arch")" || rc=$?
    if ((rc != 0)) || [[ -z "$release" ]]; then
        log_warn "Не удалось получить релиз Go с go.dev (код ${rc})."
        _fallback_toolchain "$required" "$sys_ver"
        return $?
    fi
    local filename digest
    filename="$(awk '{print $1}' <<<"$release")"
    digest="$(awk '{print $2}' <<<"$release")"
    # Fail-closed: без контрольной суммы установка не продолжается.
    if [[ -z "$filename" || -z "$digest" ]]; then
        die "В ответе go.dev нет имени файла или sha256 — отказываюсь ставить непроверенное!"
    fi
    log "релиз: ${filename}"
    local tarball="/tmp/${filename}"
    if ! curl -fsSL --retry 3 -o "$tarball" "https://go.dev/dl/${filename}"; then
        log_warn "Не скачался https://go.dev/dl/${filename}."
        _fallback_toolchain "$required" "$sys_ver"
        return $?
    fi
    local actual
    actual="$(sha256sum "$tarball" | awk '{print $1}')"
    if [[ "$actual" != "$digest" ]]; then
        rm -f "$tarball"
        log_error "sha256 не совпал для ${filename}!"
        log_error "  ожидался: ${digest}!"
        log_error "  получен : ${actual}!"
        exit 1
    fi
    log_ok "sha256 проверен."
    awg3_safe_rm_tree "${AWG3_PREFIX}/go" || true
    mkdir -p "$AWG3_PREFIX"
    tar -C "$AWG3_PREFIX" -xzf "$tarball"
    rm -f "$tarball"
    GO_BIN="${AWG3_PREFIX}/go/bin/go"
    [[ -x "$GO_BIN" ]] || { die "После распаковки нет ${GO_BIN}!"; }
    log_ok "Go установлен в ${AWG3_PREFIX}/go (изолированно, системный не тронут)."
}

# Клонирует исходники и определяет требуемую версию Go.
# Экспортирует GO_REQUIRED для ensure_go.
awg3_fetch_sources() {
    step "Исходники amneziawg-go"
    ensure_tools
    if [[ "$AWG3_BUILD_DIR" == /tmp/* ]]; then rm -rf -- "$AWG3_BUILD_DIR"; fi
    git clone --depth 1 "$GO_REPO" "$AWG3_BUILD_DIR" >/dev/null 2>&1 ||
        { die "git clone не удался: ${GO_REPO}!"; }
    # Проверяем поддержку AWG 3 до сборки, а не после.
    if grep -rqi "header_protection\|HeaderProtectionKey" "${AWG3_BUILD_DIR}/device/" 2>/dev/null; then
        log_ok "В исходниках найдена поддержка AWG 3 (header protection)."
    else
        log_warn "В device/ нет упоминаний header protection."
        log_warn "Собранный бинарь будет уметь только AWG 2.0 — probe это покажет."
    fi
    GO_REQUIRED="$(gomod_go_version "${AWG3_BUILD_DIR}/go.mod")"
    if [[ -n "$GO_REQUIRED" ]]; then
        log "go.mod требует Go >= ${GO_REQUIRED}."
    else
        GO_REQUIRED="$GO_MIN"
        log_warn "Версия в go.mod не найдена — беру минимальную ${GO_MIN}."
    fi
}

awg3_build_backend() {
    step "Сборка amneziawg-go"
    [[ -d "$AWG3_BUILD_DIR" ]] || { die "Нет исходников — сначала fetch_sources!"; }
    command -v make >/dev/null 2>&1 || {
        log_error "make не найден — сборка невозможна"
        log_error "поставь: apt-get install -y make"
        exit 1
    }
    ( cd "$AWG3_BUILD_DIR" && PATH="$(dirname "$GO_BIN"):$PATH" make >/dev/null ) ||
        { die "Сборка не удалась; повтори вручную: cd ${AWG3_BUILD_DIR} && make!"; }
    mkdir -p "$AWG3_BIN_DIR"
    install -m 0755 "${AWG3_BUILD_DIR}/amneziawg-go" "${AWG3_BIN_DIR}/amneziawg-go"
    # BUILD_DIR — константа под /tmp, но проверяем всё равно: правка константы на пустую строку не должна превращать уборку в снос корня.
    if [[ "$AWG3_BUILD_DIR" == /tmp/* ]]; then rm -rf -- "$AWG3_BUILD_DIR"; fi
    log_ok "amneziawg-go -> ${AWG3_BIN_DIR}/amneziawg-go"
}

# Раскладывает папку проекта в ${AWG3_PREFIX}/src.
# Два источника:
#   1. src/ рядом со скриптом — установка из клона репозитория;
#   2. свежий клон           — однокомандная установка и любое обновление.
# Ветки «обновить существующую папку через git pull» намеренно нет: в ${AWG3_SRC_DIR} лежит содержимое src/,
# а .git от корня репозитория восстановил бы туда весь корень и создал вложенный src/src. Клон поверхностный и дешёвый,
# а состояния после него не остаётся.
awg3_sync_sources() {
    step "Папка проекта"
    local source=""
    if [[ -d "${cur_dir}/src/awg3" ]]; then
        source="${cur_dir}/src"
        if [[ "$(cd "$source" && pwd)" == "$AWG3_SRC_DIR" ]]; then
            log_ok "работаю прямо в ${AWG3_SRC_DIR}"
            return 0
        fi
        log "беру из ${source}"
    else
        log "тяну ${AWG3_REPO} (${AWG3_BRANCH})"
        local clone="/tmp/awg3-repo"
        if [[ "$clone" == /tmp/* ]]; then rm -rf -- "$clone"; fi
        git clone --depth 1 --branch "$AWG3_BRANCH" "$AWG3_REPO" "$clone" >/dev/null 2>&1 ||
            { die "Не удалось склонировать ${AWG3_REPO}!"; }
        [[ -d "${clone}/src/awg3" ]] ||
            { die "В репозитории нет каталога src/awg3/!"; }
            source="${clone}/src"
    fi
    mkdir -p "$AWG3_PREFIX"
    # Старую папку сносим целиком: остатки прошлых версий, включая случайно оставшийся .git, не должны пережить обновление.
    awg3_safe_rm_tree "$AWG3_SRC_DIR" 2>/dev/null || true
    cp -r "$source" "$AWG3_SRC_DIR"
    if [[ -d "${AWG3_SRC_DIR}/.git" ]]; then
        awg3_safe_rm_tree "${AWG3_SRC_DIR}/.git" 2>/dev/null || rm -rf -- "${SRC_DIR}/.git"
    fi
    if [[ -d /tmp/awg3-repo ]]; then rm -rf -- /tmp/awg3-repo; fi
    log_ok "Папка проекта в ${AWG3_SRC_DIR}."
}

awg3_install_python() {
    step "Python-ядро"
    [[ -d "${AWG3_SRC_DIR}/awg3" ]] ||
        { die "Нет ${AWG3_SRC_DIR}/awg3 — сначала sync_sources!"; }
    python3 -m venv "$AWG3_VENV_DIR"
    "${AWG3_VENV_DIR}/bin/pip" install --quiet --upgrade pip
    "${AWG3_VENV_DIR}/bin/pip" install --quiet cryptography
    mkdir -p "$AWG3_LIB_DIR"
    awg3_safe_rm_tree "${AWG3_LIB_DIR}/awg3" 2>/dev/null || true
    cp -r "${AWG3_SRC_DIR}/awg3" "${AWG3_LIB_DIR}/awg3"
    find "${AWG3_LIB_DIR}/awg3" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
    log_ok "пакет -> ${AWG3_LIB_DIR}/awg3, venv -> ${AWG3_VENV_DIR}"
    cat >"$AWG3_PROBE_WRAPPER" <<EOF
#!/usr/bin/env bash
# Проверка имён UAPI-ключей AWG 3 на установленном бинаре.
exec env PYTHONPATH="${AWG3_LIB_DIR}" "${AWG3_VENV_DIR}/bin/python" -c '
from awg3.core.probe import probe_uapi_keys, format_report
print(format_report(probe_uapi_keys()))
' "\$@"
EOF
    chmod 0755 "$AWG3_PROBE_WRAPPER"
    log_ok "команда probe -> ${AWG3_PROBE_WRAPPER}"
    cat >"$AWG3_CLI_WRAPPER" <<EOF
#!/usr/bin/env bash
# Интерактивное меню управления AWG3.
if [[ "\$(id -u)" -ne 0 ]]; then
    echo "Нужен root: sudo awg3" >&2
    exit 1
fi
exec env PYTHONPATH="${AWG3_LIB_DIR}" "${AWG3_VENV_DIR}/bin/python" -m awg3 "\$@"
EOF
    chmod 0755 "$AWG3_CLI_WRAPPER"
    log_ok "меню -> ${AWG3_CLI_WRAPPER}"
    # Копия установщика рядом с проектом: пункт «Обновление» в меню запускает именно её, без повторного curl. Если копии нет — меню сходит на GitHub.
    if [[ -f "${cur_dir}/install.sh" ]]; then
        install -m 0755 "${cur_dir}/install.sh" "${AWG3_PREFIX}/install.sh"
        log_ok "установщик сохранён -> ${AWG3_PREFIX}/install.sh"
    fi
    mkdir -p ${AWG3_LOGS_DIR}
    touch "$AWG3_LOG_FILE"; chmod 640 "$AWG3_LOG_FILE"
}

awg3_install_units() {
# Шаблонный юнит: %i — имя интерфейса. Поднимает ТОЛЬКО демон; применение конфигурации через UAPI появится вместе с CLI.
# Поэтому enable не делаем. StartLimit* — чтобы демон с кривыми параметрами не уходил в цикл рестартов и не забивал журнал.
# Не шаблонный юнит и не голый демон: awg3 --up делает полный подъём — демон, адрес, конфигурация через UAPI, правила сети.
# Иначе после ребута интерфейс встаёт без параметров и клиенты не подключаются.
    step "systemd"
    cat >"$AWG3_UNIT_PATH" <<EOF
[Unit]
Description=AWG3 — AmneziaWG 3.0 tunnel
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=600
StartLimitBurst=5

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${AWG3_CLI_WRAPPER} --up
ExecStop=${AWG3_CLI_WRAPPER} --down
TimeoutStartSec=120
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    ok "юнит awg3.service установлен (включится при первом запуске туннеля)"
}

awg3_self_test() {
    step "Самотест моделей"
    local runner="python3"
    [[ -x "${AWG3_VENV_DIR}/bin/python" ]] && runner="${AWG3_VENV_DIR}/bin/python"
    local tests_dir="$AWG3_SRC_DIR/awg3"
    if [[ -f "${tests_dir}/test_models.py" ]]; then
        ( cd "$tests_dir" && "$runner" test_models.py ) ||
        { log_error "Cамотест провален — не ставь это в бой!"; return 1; }
    else
        log_warn "test_models.py не найден — пропускаю."
    fi
}

# Снимает ТОЛЬКО правила с нашим тегом. Разбираем iptables-save и удаляем по одному — никаких -F, соседние правила AWG 2.0 и Warp не наши.
remove_awg3_iptables() {
    local removed=0 table line rule
    command -v iptables-save >/dev/null 2>&1 || { echo 0; return 0; }
    for table in filter nat; do
        while IFS= read -r line; do
            [[ "$line" == -A*"${AWG3_IPTABLES_TAG}:"* ]] || continue
            rule="$(rule_to_delete "$line")" || continue
            # Словоделение здесь намеренное: rule — уже готовый набор аргументов. shellcheck disable=SC2086
            if iptables -t "$table" $rule 2>/dev/null; then
                removed=$((removed + 1))
            fi
        done < <(iptables-save -t "$table" 2>/dev/null)
    done
    log "${removed}."
}

# Снимает ТОЛЬКО правила с нашим тегом. Разбираем iptables-save и удаляем по одному — никаких -F, соседние правила AWG 2.0 и Warp не наши.
remove_awg3_fw_zone() {
    local rem_zone=0
    source /root/.firewalld/.fw_cmd-env
    rem_zone=$(${fwperm} --delete-zone=${AWG3_FW_ZONE})
    ${fwreload}
    log "${rem_zone}."
}


# Гасит интерфейсы AWG3, если остались поднятыми.
down_awg3_links() {
    local iface=${AWG3_IF}
    [[ -r "$AWG3_RESERVED_ENV" ]] &&
        iface="$(awk -F= '/^AWG3_IFACE=/{print $2}' "$AWG3_RESERVED_ENV")"
    local link
    for link in "$iface" awg3probe; do
        [[ -n "$link" ]] || continue
        if ip link show dev "$link" >/dev/null 2>&1; then
            ip link delete dev "$link" 2>/dev/null && log "Интерфейс ${link} погашен."
        fi
        rm -f "/var/run/amneziawg/${link}.sock"
    done
}

awg3_summary() {
    local version
    awg3_version="$(awk -F'"' '/^__version__/{print $2}' "${AWG3_SRC_DIR}/awg3/__init__.py" 2>/dev/null)"
    [[ -n "$awg3_version" ]] && print_info "  ${bnc}Версия: ${awg3_version}" && echo ""
    [[ -r "$AWG3_RESERVED_ENV" ]] && sed 's/^/  /' "$AWG3_RESERVED_ENV" | grep -v '^  #'
    local title="AWG3 — установка завершена"
    local descr="$awg3_version\n  Дальше:\n  ${bcy}sudo awg3-probe${bnc}      проверить ключи AWG 3 на этом бинаре\n  ${bcy}sudo awg3${bnc}            меню: сервер, клиенты, конфиги\n  Что НЕ тронуто:${bgrn} /etc/amnezia, awg0, таблица 200, правила AWG 2.0${nc}\n"
    print_banner $title $descr
}

awg3_install() {
    if [[ "$os_type" != "rhel" ]]; then
        awg3_preflight
        awg3_install_deps
        awg3_sync_sources
        awg3_fetch_sources
        awg3_ensure_go "$GO_REQUIRED"
        awg3_build_backend
        awg3_install_python
        awg3_install_units
        awg3_self_test || true
        awg3_summary
    else
        awg3_preflight
        awg3_install_deps
        awg3_sync_sources
        awg3_install_python
        awg3_install_units
        awg3_self_test || true
        awg3_summary
    fi
}

awg3_update() {
    if [[ "$os_type" != "rhel" ]]; then
        step "Обновление"
        awg3_ensure_tools
        awg3_sync_sources
        awg3_fetch_sources
        awg3_ensure_go "$GO_REQUIRED"
        awg3_build_backend
        awg3_install_python
        # Юнит переустанавливаем всегда: его определение меняется между версиями, а пропуск этого шага оставляет систему без автозапуска молча.
        awg3_install_units
    else
        step "Обновление"
        awg3_ensure_tools
        awg3_sync_sources
        awg3_install_python
        awg3_install_units
    fi
    print_ok "бинарь, ядро и юнит обновлены; ${AWG3_CONF_DIR} не тронут"
}

awg3_uninstall() {
    step "Удаление AWG3"
    print_delete "  ${AWG3_PREFIX} (бинари, venv, Go)."
    print_delete "  ${AWG3_PROBE_WRAPPER}, ${AWG3_CLI_WRAPPER}."
    print_delete "  ${AWG3_UNIT_PATH}."
    if [[ "$AWG3_PURGE" == "true" ]]; then
        print_delete "  ${AWG3_CONF_DIR} ${bred}(--purge)${bnc}."
    else
        print_save "  ${AWG3_CONF_DIR} сохраняется (снести: --uninstall --purge)."
    fi
    if [[ "$os_type" != "rhel" ]]; then
        print_delete "  правила iptables с тегом ${AWG3_IPTABLES_TAG}."
    else
        print_delete "  зона firewalld ${AWG3_FW_ZONE}."
    fi
    print_delete "  интерфейсы AWG3 будут погашены."
    print_save "  AWG 2.0 не затрагивается вообще."
    print_save "  ${AWG3_LOG_FILE} сохраняется — после аварии это единственный след."
    echo ""
    ask_yn "  ${bred}Подтвердите удаление: ${bnc}" "y" confirm
    [[ "$confirm" == "yes" ]] || { log_warn "Отменено."; return 0; }
    systemctl list-units 'awg3*' --no-legend 2>/dev/null | awk '{print $1}' |
        while read -r unit; do systemctl disable --now "$unit" 2>/dev/null || true; done
    down_awg3_links
    if [[ "$os_type" != "rhel" ]]; then
        local rules_removed; rules_removed="$(remove_awg3_iptables)"
        print_ok "Cнято правил iptables с тегом ${AWG3_IPTABLES_TAG}: ${rules_removed}."
    else
        local fw_zone_removed; fw_zone_removed="$(remove_awg3_fw_zone)"
        print_ok "Удалена firewalld зона ${AWG3_FW_ZONE}: ${fw_zone_removed}."
    fi
    rm -f "$AWG3_UNIT_PATH"; systemctl daemon-reload 2>/dev/null || true
    awg3_safe_rm_tree "$AWG3_PREFIX" || { log_error "Префикс не удалён — проверьте AWG3_PREFIX!"; return 1; }
    rm -f "$AWG3_PROBE_WRAPPER" "$AWG3_CLI_WRAPPER"
    if [[ "$AWG3_PURGE" == "true" ]]; then
        awg3_safe_rm_tree "$AWG3_CONF_DIR" || log_error "Конфиги не удалены — проверьте AWG3_CONF_DIR!"
    fi
    print_ok "Удалено."
    log "Правила без тега ${AWG3_IPTABLES_TAG} не тронуты — они не наши."
}

awg3_dry_run() {
    step "План установки (ничего не выполняется)"
    if [[ "$os_type" != "rhel" ]]; then
echo -e ${bnc}
        cat <<EOF
  1. awg3_preflight     прочитать ${AWG2_CONF}, зарезервировать порт и подсеть
  2. awg3_deps          git make curl iproute2 python3 python3-venv
  3. awg3_src           папка проекта -> ${AWG3_SRC_DIR}
  4. awg3_sources       клон ${GO_REPO}, чтение требуемой версии Go из go.mod
  5. awg3_go            системный Go нужной версии либо официальный тарбол с sha256
  6. awg3_build         make -> ${BIN_DIR}/amneziawg-go
  7. awg3_python        venv ${AWG3_VENV_DIR} + cryptography, пакет в ${AWG3_LIB_DIR}
  8. awg3_systemd       ${AWG3_UNIT_PATH} (устанавливается, но не включается)
  9. awg3_selftest      test_models.py

  Не создаётся и не удаляется ничего вне: ${AWG3_PREFIX}, ${AWG3_CONF_DIR},
  ${AWG3_UNIT_PATH}, ${AWG3_PROBE_WRAPPER}, ${AWG3_LOG_FILE}
EOF
echo -e ${nc}
    else
echo -e ${bnc}
        cat <<EOF
  1. awg3_preflight     прочитать ${AWG2_CONF}, зарезервировать порт и подсеть
  2. awg3_deps          git make curl iproute2 python3 python3-venv
  3. awg3_src           папка проекта -> ${SRC_DIR}
  4. awg3_python        venv ${AWG3_VENV_DIR} + cryptography, пакет в ${AWG3_LIB_DIR}
  5. awg3_systemd       ${AWG3_UNIT_PATH} (устанавливается, но не включается)
  6. awg3_selftest      test_models.py

  Не создаётся и не удаляется ничего вне: ${AWG3_PREFIX}, ${AWG3_CONF_DIR},
  ${AWG3_UNIT_PATH}, ${AWG3_PROBE_WRAPPER}, ${AWG3_LOG_FILE}
EOF
echo -e ${nc}
    fi
}

# --> МЕНЮ: Установка вспомогательных утилит <--
menu_install_awg3() {
    declare mItems=("План установки (dry-run)" "Установить" "Самотест" "Обновить" "Удалить AWG3 с сервера")
    declare mActions=("awg3_dry_run" "awg3_install" "awg3_self_test" "awg3_update" "awg3_uninstall")
    declare mTitle="Установка AmneziaWG 3"
    declare mDescr="Описание установки AWG3\n"
    declare mType="section"
    show_menu
}
