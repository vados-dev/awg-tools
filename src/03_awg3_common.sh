# --> Функции подменю "Установка AWG3" <--

source ${AWG3_DEFAULT_ENV}
source ${AWG3_PREFIX}/.awg3-func
source /root/.firewalld/.fw_cmd-env

CUSTOM_LOGS_DIR=/var/log/awg3
CUSTOM_LOG_FILE=awg3_server.log
source ${PROJ_ENV}/.${me}-env

AWG3_LEGACY_KEYS_DIR=${AWG3_CLIENTS_ROOT}/keys

client_dir() { printf '%s/%s' "$AWG3_CLIENTS_ROOT" "$1"; }
client_keys_dir() { printf '%s/%s/keys' "$AWG3_CLIENTS_ROOT" "$1"; }
# Путь к конфигу клиента: новая схема в приоритете, затем старая. Для несуществующего клиента возвращается путь по новой схеме — туда и создаём.
client_conf_path() {
    local name="$1"
    if [[ -f "$AWG3_CLIENTS_ROOT/$name/$name.conf" ]]; then
        printf '%s/%s/%s.conf' "$AWG3_CLIENTS_ROOT" "$name" "$name"
    elif [[ -f "$AWG3_CLIENTS_ROOT/$name.conf" ]]; then
        printf '%s/%s.conf' "$AWG3_CLIENTS_ROOT" "$name"
    else
        printf '%s/%s/%s.conf' "$AWG3_CLIENTS_ROOT" "$name" "$name"
    fi
}

# ── Команда: link ───────────────────────────────────────────────────────────
# Пересобирает файл со ссылкой по уже существующему конфигу. Нужна тем, у
# кого клиенты созданы прежними версиями скрипта, и после правки конфига
# руками. Ключи и пир при этом не трогаются: ссылка — производная от конфига.
#gen_link() {}
awg3_link() {
    local names=()
    if [[ $# -gt 0 ]]; then
        names=("$@")
    else
        mapfile -t names < <(list_client_names)
        [[ "${#names[@]}" -gt 0 ]] || log_warn "клиентов нет"
    fi
    # Команду вызвали явно, значит ссылка нужна вопреки --no-qr-подобным умолчаниям.
    MAKE_LINK=1
    local name conf ok=0 failed=0
    for name in "${names[@]}"; do
        validate_client_name "$name"
        conf=$(client_conf_path "$name")
        if [[ ! -f "$conf" ]]; then
            log_error "'$name': конфиг не найден"
            failed=$((failed + 1))
            continue
        fi
        if generate_link "$name" "$conf"; then
            ok=$((ok + 1))
            # Одно имя — почти всегда «покажи мне ссылку»; списком же печатать ссылки бессмысленно, они по несколько килобайт.
            if [[ "${#names[@]}" -eq 1 ]]; then printf '%s\n' "$LINK_LAST"; fi
        else
            failed=$((failed + 1))
        fi
    done
    if [[ "${#names[@]}" -gt 1 ]]; then log "Готово: ссылок $ok, с ошибками $failed"; fi
    [[ "$failed" -eq 0 ]]
}

# ── Чтение клиентского конфига ──────────────────────────────────────────────
_conf_value() {
    local file="$1" key="$2" section="${3:-any}"
    awk -v k="$key" -v want="$section" '
        /^[[:space:]]*\[Interface\]/ { sec = "interface"; next }
        /^[[:space:]]*\[Peer\]/      { sec = "peer"; next }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (index(line, "#") == 1) next
            if (want != "any" && sec != want) next
            split(line, kv, "=")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", kv[1])
            if (kv[1] == k) {
                sub(/^[^=]*=[[:space:]]*/, "", line)
                gsub(/[[:space:]]+$/, "", line)
                print line
                exit
            }
        }
    ' "$file"
}

# Имена клиентов из обеих раскладок, без повторов и в алфавитном порядке.
list_client_names() {
    local d f base
    {
        for d in "$AWG3_CLIENTS_ROOT"/*/; do
            [[ -d "$d" ]] || continue
            base=$(basename "$d")
            if [[ -f "$d/$base.conf" ]]; then printf '%s\n' "$base"; fi
        done
        for f in "$AWG3_CLIENTS_ROOT"/*.conf; do
            [[ -f "$f" ]] || continue
            # Серверный конфиг, если он оказался в том же каталоге, клиентом не является: у него есть ListenPort, которого у клиента не бывает.
            if [[ "$f" -ef "$AWG3_SERVER_CONF" ]]; then continue; fi
            if grep -qE '^[[:space:]]*ListenPort[[:space:]]*=' "$f" 2>/dev/null; then continue; fi
            printf '%s\n' "$(basename "$f" .conf)"
        done
    } | sort -u
}

# ── Команда: list ───────────────────────────────────────────────────────────
# Выравнивание ячейки по ШИРИНЕ В СИМВОЛАХ. printf считает байты, поэтому
# колонка с кириллицей съезжает ровно на число многобайтовых символов.
_pad() {
    local s="$1" w="$2" chars bytes
    chars=${#s}
    bytes=$(LC_ALL=C printf '%s' "$s" | wc -c)
    printf "%-*s " "$((w + bytes - chars))" "$s"
}

awg3_list() {
    load_server_params
    load_name_to_pk
    load_peer_dump
    _pad "КЛИЕНТ" 20; _pad "АДРЕС" 14; _pad "ВЕРСИЯ" 6; _pad "СВЯЗЬ" 14; _pad "РАСКЛАДКА" 9
    printf '%s\n' "СОВМЕСТИМ"
    printf '%s\n' "$dashes"
    local name conf addr hpk ver match c_s1 c_h1 layout
    while IFS= read -r name; do
        conf=$(client_conf_path "$name")
        if [[ "$conf" == "$AWG3_CLIENTS_ROOT/$name/$name.conf" ]]; then
            layout="папка"
        else
            layout="старая"
        fi
        addr=$(_conf_value "$conf" Address interface)
        hpk=$(_conf_value "$conf" HeaderProtectionKey interface)
        c_s1=$(_conf_value "$conf" S1 interface)
        c_h1=$(_conf_value "$conf" H1 interface)
        if [[ -n "$hpk" ]]; then ver="3.0"; else ver="2.0"; fi
        if [[ "$c_s1" == "${S_S1}" && "$c_h1" == "${S_H1}" && "$hpk" == "${S_HPK}" ]]; then
            match="$(cecho Gs)да"
        else
            match="$(cecho Rs) нет — клиент не подключится"
        fi
        local pk="${NAME_PK[$name]:-}" link
        if [[ -n "$pk" ]]; then link=$(peer_status "${PK_HS[$pk]:-0}"); else link="нет пира"; fi
        _pad "$name" 20; _pad "${addr%%,*}" 14; _pad "$ver" 6
        _pad "$link" 14; _pad "$layout" 9
        printf '%s\n' "$match"
    done < <(list_client_names)
    printf '\n'
    if server_is_awg3; then
        printf 'Сервер: AWG 3.0 (S1=%s H1=%s)\n' "$S_S1" "$S_H1"
    else
        printf 'Сервер: AWG 2.0 — HeaderProtectionKey отсутствует\n'
    fi
    printf '  порт: %s/udp, подсеть: %s, MTU: %s\n' \
        "${S_PORT:-?}" "${S_ADDR:-?}" "${S_MTU:-?}"
    printf '  изоляция клиентов: %s, IPv6: %s\n' \
        "$(server_isolation_state)" "$(server_ipv6_state)"
    local ep
    ep=$(server_endpoint_name)
    if [[ -n "$ep" ]]; then
        printf '  имя хоста для клиентов: %s\n' "$ep"
    else
        printf '  имя хоста для клиентов: не задано (берётся внешний IP)\n'
    fi
}

# ── Команда: migrate ────────────────────────────────────────────────────────
# Переносит клиентов из плоской раскладки в ~/awg/ИМЯ/. Файлы перемещаются,
# а не копируются: две копии приватного ключа на диске никому не нужны. Повторный запуск безопасен — уже перенесённые пропускаются.
ask_migrate_name(){
    local name=""
    list_client_names
    ask "Кого переносить? " "" name
    [[ "$name" != "" ]] && awg3_migrate $name
}

migrate_one() {
    local name="$1"
    local cdir moved=0
    cdir=$(client_dir "$name")
    if [[ -f "$cdir/${name}.conf" ]]; then
        log "'$name': уже в своём каталоге, пропускаю"
        return 0
    fi
    [[ -f "$AWG3_CLIENTS_ROOT/${name}.conf" ]] || { log_error "'$name': конфиг не найден"; return 1; }
    mkdir -p "$cdir" || { log_error "'$name': не создан каталог $cdir"; return 1; }
    chmod 700 "$cdir"; _fix_owner "$cdir"
    local src dst

    for src in "$AWG3_CLIENTS_ROOT/${name}.conf" "$AWG3_CLIENTS_ROOT/${name}.png" \
               "$AWG3_CLIENTS_ROOT/${name}.vpnuri" "$AWG3_CLIENTS_ROOT/${name}.vpnuri.png" \
               "$AWG3_LEGACY_KEYS_DIR/${name}.private" "$AWG3_LEGACY_KEYS_DIR/${name}.public"; do
        [[ -f "$src" ]] || continue
        dst="$cdir/$(basename "$src")"
        if mv -f "$src" "$dst"; then
            _fix_owner "$dst"
            moved=$((moved + 1))
        else
            log_error "'$name': не перенесён $src"
            return 1
        fi
    done
    # Бэкапы конфигов, накопленные прежними запусками, едут следом: иначе они осиротеют в корне каталога.
    local bak
    for bak in "$AWG3_CONF_DIR/${name}.conf".bak-*; do
        [[ -f "$bak" ]] || continue
        if mv -f "$bak" "$cdir/"; then moved=$((moved + 1)); fi
    done
    log_ok "'$name': перенесено файлов — $moved → $cdir"
    return 0
}

awg3_migrate() {
    local names=() name flat=()
    mapfile -t names < <(list_client_names)
    [[ "${#names[@]}" -gt 0 ]] || log_warn "клиентов не найдено"
    for name in "${names[@]}"; do
        if [[ ! -f "$AWG3_CLIENTS_ROOT/$name/$name.conf" && -f "$AWG3_CLIENTS_ROOT/${name}.conf" ]]; then
            flat+=("$name")
        fi
    done
    if [[ "${#flat[@]}" -eq 0 ]]; then
        log_ok "переносить нечего: все клиенты уже разложены по каталогам"
        return 0
    fi
    log "Будут перенесены в собственные каталоги: ${flat[*]}"
    log "Файлы перемещаются (conf, png, ключи, бэкапы), сервер не затрагивается."
    confirm "Продолжить?" || log "отменено"
    local ok=0 fail=0
    for name in "${flat[@]}"; do
        if migrate_one "$name"; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
    done
    # Каталог keys/ остаётся на месте, даже если опустел: удаление файлов — отдельное решение, скрипт его за пользователя не принимает.
    if [[ -d "$AWG3_LEGACY_KEYS_DIR" ]]; then
        local left
        left=$(find "$AWG3_LEGACY_KEYS_DIR" -type f 2>/dev/null | wc -l)
        if [[ "$left" -eq 0 ]]; then
            log "Каталог $AWG3_LEGACY_KEYS_DIR опустел — можно удалить вручную."
        else
            log_warn "В $AWG3_LEGACY_KEYS_DIR осталось файлов: $left (ключи без клиента?)"
        fi
    fi
    log "Готово: перенесено $ok, с ошибками $fail"
    [[ "$fail" -eq 0 ]]
}

# ── Данные живого интерфейса ────────────────────────────────────────────────
# `awg show <iface> dump` отдаёт по строке на пира: pubkey \t psk \t endpoint \t allowed-ips \t handshake \t rx \t tx \t keepalive
# Первая строка описывает сам интерфейс и пропускается. Заполняет ассоциативные массивы PK_HS, PK_RX, PK_TX, PK_EP (ключ — pubkey).
declare -A PK_HS PK_RX PK_TX PK_EP
load_peer_dump() {
    local dump pk psk ep aips hs rx tx ka
    dump=$(awg show "$AWG3_IFACE" dump 2>/dev/null) || return 0
    [[ -n "$dump" ]] || return 0
    while IFS=$'\t' read -r pk psk ep aips hs rx tx ka; do
        [[ -n "$pk" ]] || continue
        PK_HS["$pk"]="$hs"; PK_RX["$pk"]="$rx"; PK_TX["$pk"]="$tx"; PK_EP["$pk"]="$ep"
    done < <(printf '%s\n' "$dump" | tail -n +2)
}

# Имя клиента -> публичный ключ, по маркерам #_Name в серверном конфиге.
declare -A NAME_PK
load_name_to_pk() {
    local line cur=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "#_Name = "* ]]; then
            cur="${line#\#_Name = }"; cur="${cur//[[:space:]]/}"
        elif [[ -n "$cur" && "$line" == "PublicKey = "* ]]; then
            local pk="${line#PublicKey = }"; pk="${pk//[[:space:]]/}"
            if [[ -n "$pk" ]]; then NAME_PK["$cur"]="$pk"; fi
            cur=""
        fi
    done < "$AWG3_SERVER_CONF"
}

# Человекочитаемый статус по времени последнего рукопожатия.
peer_status() {
    local hs="${1:-0}" now diff
    if ! [[ "$hs" =~ ^[0-9]+$ ]] || [[ "$hs" -eq 0 ]]; then
        printf 'нет связи'; return 0
    fi
    now=$(date +%s); diff=$((now - hs))
    if   [[ "$diff" -lt 180 ]];   then printf 'активен'
    elif [[ "$diff" -lt 86400 ]]; then printf 'был %dч назад' "$((diff / 3600))"
    else printf 'был %dд назад' "$((diff / 86400))"
    fi
}

format_bytes() {
    local b="${1:-0}"
    if ! [[ "$b" =~ ^[0-9]+$ ]]; then printf '0 B'; return; fi
    if   [[ "$b" -ge 1073741824 ]]; then awk "BEGIN{printf \"%.2f GiB\", $b/1073741824}"
    elif [[ "$b" -ge 1048576 ]];    then awk "BEGIN{printf \"%.2f MiB\", $b/1048576}"
    elif [[ "$b" -ge 1024 ]];       then awk "BEGIN{printf \"%.1f KiB\", $b/1024}"
    else printf '%d B' "$b"
    fi
}

# ── Команда: remove ─────────────────────────────────────────────────────────
# Вырезает из серверного конфига секцию [Peer] с указанным #_Name.
_drop_peer_section() {
    local name="$1" tmp
    tmp=$(mktemp "${AWG3_SERVER_CONF}.tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    # Секция копится в буфере до её конца, и только тогда решается судьба: печатать или выбросить. Маркер #_Name стоит внутри секции, а не перед ней.
    awk -v target="$name" '
        function flush_buf() {
            if (nbuf > 0 && !drop) { for (i = 1; i <= nbuf; i++) print buf[i] }
            nbuf = 0; drop = 0
        }
        /^[[:space:]]*\[Peer\]/ { flush_buf(); in_peer = 1; buf[++nbuf] = $0; next }
        /^[[:space:]]*\[Interface\]/ { flush_buf(); in_peer = 0; print; next }
        {
            if (in_peer) {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                if (line == "#_Name = " target) drop = 1
                buf[++nbuf] = $0
            } else print
        }
        END { flush_buf() }
    ' "$AWG3_SERVER_CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
    if ! grep -qxF "#_Name = ${name}" "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$AWG3_SERVER_CONF" || { rm -f "$tmp"; return 1; }
        chmod 600 "$AWG3_SERVER_CONF"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

ask_remove_name(){
    local name=""
    list_client_names
    ask "Кого удалять?" "" name
    [[ "$name" != "" ]] && awg3_remove $name
}

awg3_remove() {
    load_server_params
    local names=("$@") name valid=()
    [[ "${#names[@]}" -gt 0 ]] || log_warn "укажите имя клиента"
    for name in "${names[@]}"; do
        validate_client_name "$name"
        if grep -qxF "#_Name = ${name}" "$AWG3_SERVER_CONF" 2>/dev/null; then
            valid+=("$name")
        else
            log_warn "'$name': пира нет в $AWG3_SERVER_CONF"
            # Файлы могли остаться от прошлой неудачной попытки — заберём и их.
            if [[ -d "$(client_dir "$name")" || -f "$AWG3_CLIENTS_ROOT/${name}.conf" ]]; then
                valid+=("$name")
            fi
        fi
    done
    [[ "${#valid[@]}" -gt 0 ]] || log_warn "нечего удалять"
    log "Будет удалено безвозвратно:"
    for name in "${valid[@]}"; do
        local cdir; cdir=$(client_dir "$name")
        printf '  %s\n' "$name"
        if [[ -d "$cdir" ]]; then find "$cdir" -type f -printf '      %p\n' 2>/dev/null || true; fi
        if [[ -f "$AWG3_CLIENTS_ROOT/${name}.conf" ]]; then printf '      %s\n' "$AWG3_CLIENTS_ROOT/${name}.conf"; fi
        if grep -qxF "#_Name = ${name}" "$AWG3_SERVER_CONF" 2>/dev/null; then
            printf '      [Peer] в %s\n' "$AWG3_SERVER_CONF"
        fi
    done
    confirm "Удалить?" || log "отменено"
    local lock_fd
    exec {lock_fd}>"$AWG3_LOCK_DIR/.awg_config.lock"
    flock -x -w 10 "$lock_fd" || log_warn "не получен config-lock"
    _backup_file "$AWG3_SERVER_CONF"
    local removed=0 failed=0
    for name in "${valid[@]}"; do
        if grep -qxF "#_Name = ${name}" "$AWG3_SERVER_CONF" 2>/dev/null; then
            if ! _drop_peer_section "$name"; then
                log_error "'$name': не удалён из серверного конфига"
                failed=$((failed + 1))
                continue
            fi
        fi
        # Приватный ключ затирается, а не просто отвязывается от имени файла.
        local cdir; cdir=$(client_dir "$name")
        if [[ -d "$cdir" ]]; then
            find "$cdir" -type f -name '*.private' -exec shred -u {} \; 2>/dev/null || true
            rm -rf "${AWG3_CLIENTS_ROOT:?}/${name:?}"
        fi
        rm -f "$AWG3_CLIENTS_ROOT/${name}.conf" "$AWG3_CLIENTS_ROOT/${name}.png" \
              "$AWG3_CLIENTS_ROOT/${name}.vpnuri" "$AWG3_CLIENTS_ROOT/${name}.vpnuri.png" \
              "$AWG3_CLIENTS_ROOT/${name}.conf".bak-* 2>/dev/null || true
        if [[ -f "$AWG3_LEGACY_KEYS_DIR/${name}.private" ]]; then
            shred -u "$AWG3_LEGACY_KEYS_DIR/${name}.private" 2>/dev/null || true
        fi
        rm -f "$AWG3_LEGACY_KEYS_DIR/${name}.public" 2>/dev/null || true
        log_ok "'$name' удалён"
        removed=$((removed + 1))
    done
    exec {lock_fd}>&-
    if [[ "$removed" -gt 0 ]]; then apply_peers || true; fi
    log "Готово: удалено $removed, с ошибками $failed"
    [[ "$failed" -eq 0 ]]
}

# ── Команда: stats ──────────────────────────────────────────────────────────
awg3_stats() {
    load_server_params
    load_name_to_pk
    load_peer_dump
    _pad "КЛИЕНТ" 20; _pad "ПРИНЯТО" 12; _pad "ОТДАНО" 12; _pad "СОСТОЯНИЕ" 16
    printf '%s\n' "ОТКУДА"
    printf '%s\n' "--------------------------------------------------------------------------------"
    local name pk total_rx=0 total_tx=0 ep
    while IFS= read -r name; do
        pk="${NAME_PK[$name]:-}"
        if [[ -z "$pk" ]]; then
            _pad "$name" 20; printf '%s\n' "нет пира в конфиге"
            continue
        fi
        local rx="${PK_RX[$pk]:-0}" tx="${PK_TX[$pk]:-0}"
        [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
        [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
        total_rx=$((total_rx + rx)); total_tx=$((total_tx + tx))
        ep="${PK_EP[$pk]:-}"
        if [[ -z "$ep" || "$ep" == "(none)" ]]; then ep="-"; fi
        _pad "$name" 20
        _pad "$(format_bytes "$rx")" 12
        _pad "$(format_bytes "$tx")" 12
        _pad "$(peer_status "${PK_HS[$pk]:-0}")" 16
        printf '%s\n' "$ep"
    done < <(list_client_names)
    printf '\n'
    printf 'Всего: принято %s, отдано %s\n' "$(format_bytes "$total_rx")" "$(format_bytes "$total_tx")"
}

# ── Команды: show, restart ──────────────────────────────────────────────────
awg3_show() {
    awg show "$AWG3_IFACE" || log_warn "интерфейс $AWG3_IFACE не поднят"
}

awg3_restart() {
    log "Перезапуск awg-quick@${AWG3_IFACE}..."
    if systemctl restart "awg-quick@${AWG3_IFACE}"; then
        log_ok "сервис перезапущен"
    else
        log_warn "перезапуск не удался, смотрите: systemctl status awg-quick@${AWG3_IFACE}"
    fi
    systemctl is-active "awg-quick@${AWG3_IFACE}"
}

# ── Команда: backup ─────────────────────────────────────────────────────────
# Архив кладётся в ~/awg/backups и содержит серверный конфиг, каталоги
# клиентов и ключи сервера. Старые архивы НЕ удаляются сами: чистка — только явным --prune N, и с подтверждением.
awg3_backup() {
    local bdir="$AWG3_BACKUPS_DIR"
    mkdir -p "$bdir" || log_warn "не создан $bdir"
    chmod 700 "$bdir"; _fix_owner "$bdir"
    # Миллисекунды в имени: два бэкапа в одну секунду (backup сразу после remove, например) иначе молча затирают друг друга.
    local ts archive
    ts=$(date '+%Y%m%d-%H%M%S.%3N')
    archive="$bdir/awg_backup_${ts}.tar.gz"
    local staging
    staging=$(mktemp -d "${bdir}/.stage.XXXXXX") || log_warn "mktemp не сработал"
    mkdir -p "$staging/server" "$staging/clients"
    if [[ -f "$AWG3_SERVER_CONF" ]]; then cp -a "$AWG3_SERVER_CONF" "$staging/server/"; fi
    local f
    for f in "$AWG3_SERVER_KEYS_DIR/server_private.key" "$AWG3_SERVER_KEYS_DIR/server_public.key"; do
        if [[ -f "$f" ]]; then cp -a "$f" "$staging/server/"; fi
    done
    local name cdir count=0
    while IFS= read -r name; do
        cdir=$(client_dir "$name")
        if [[ -d "$cdir" ]]; then
            cp -a "$cdir" "$staging/clients/"
        else
            mkdir -p "$staging/clients/$name"
            cp -a "$AWG3_CLIENTS_ROOT/${name}.conf" "$staging/clients/$name/" 2>/dev/null || true
            cp -a "$AWG3_LEGACY_KEYS_DIR/${name}."* "$staging/clients/$name/" 2>/dev/null || true
        fi
        count=$((count + 1))
    done < <(list_client_names)
    if ! tar -czf "$archive" -C "$staging" server clients; then
        rm -rf "$staging"
        log_error "не создан архив $archive"
    fi
    rm -rf "$staging"
    chmod 600 "$archive"; _fix_owner "$archive"
    log_ok "бэкап создан: $archive"
    log "  клиентов в архиве: $count, размер: $(du -h "$archive" | cut -f1)"
    local total
    total=$(find "$bdir" -maxdepth 1 -name 'awg_backup_*.tar.gz' | wc -l)
    log "  всего архивов: $total"
    if [[ -n "$AWG3_PRUNE_KEEP" ]]; then
        local old=()
        mapfile -t old < <(find "$bdir" -maxdepth 1 -name 'awg_backup_*.tar.gz' | sort -r | tail -n +$((AWG3_PRUNE_KEEP + 1)))
        if [[ "${#old[@]}" -eq 0 ]]; then
            log "  удалять нечего, архивов не больше $AWG3_PRUNE_KEEP"
            return 0
        fi
        log "Будут удалены старые архивы:"
        printf '  %s\n' "${old[@]}"
        confirm "Удалить?" || { log "чистка отменена"; return 0; }
        rm -f "${old[@]}"
        log_ok "удалено архивов: ${#old[@]}"
    fi
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
            log_error "apt-get недоступен — поставь вручную: ${missing}!"
        fi
        awg3_install_deps
        missing="$(awg3_missing_tools "${AWG3_REQUIRED_TOOLS[@]}")"
        if [[ -n "$missing" ]]; then
            log_error "После установки пакетов всё ещё нет: ${missing}!"
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
        log_error "В ответе go.dev нет имени файла или sha256 — отказываюсь ставить непроверенное!"
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
    [[ -x "$GO_BIN" ]] || { log_error "После распаковки нет ${GO_BIN}!"; }
    log_ok "Go установлен в ${AWG3_PREFIX}/go (изолированно, системный не тронут)."
}

# Клонирует исходники и определяет требуемую версию Go.
# Экспортирует GO_REQUIRED для ensure_go.
awg3_fetch_sources() {
    step "Исходники amneziawg-go"
    ensure_tools
    if [[ "$AWG3_BUILD_DIR" == /tmp/* ]]; then rm -rf -- "$AWG3_BUILD_DIR"; fi
    git clone --depth 1 "$GO_REPO" "$AWG3_BUILD_DIR" >/dev/null 2>&1 ||
        { log_error "git clone не удался: ${GO_REPO}!"; }
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
    [[ -d "$AWG3_BUILD_DIR" ]] || { log_error "Нет исходников — сначала fetch_sources!"; }
    command -v make >/dev/null 2>&1 || {
        log_error "make не найден — сборка невозможна."
        log_error "Поставь: apt-get install -y make."
        exit 1
    }
    ( cd "$AWG3_BUILD_DIR" && PATH="$(dirname "$GO_BIN"):$PATH" make >/dev/null ) ||
        { log_error "Сборка не удалась; повтори вручную: cd ${AWG3_BUILD_DIR} && make!"; }
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
            { log_error "Не удалось склонировать ${AWG3_REPO}!"; }
        [[ -d "${clone}/src/awg3" ]] ||
            { log_error "В репозитории нет каталога src/awg3/!"; }
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
        { log_error "Нет ${AWG3_SRC_DIR}/awg3 — сначала sync_sources!"; }
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
    log_ok "Команда probe -> ${AWG3_PROBE_WRAPPER}."
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
    ok "Юнит awg3.service установлен (включится при первом запуске туннеля)."
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

awg3_run_cli() {
    [[ -x "$AWG3_CLI_WRAPPER" ]] || { log_error "AWG3 не установлен — сначала пункт 1!"; return 1; }
    "$AWG3_CLI_WRAPPER"
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

# --> МЕНЮ: Главное меню AWG 3 <--
awg3_menu() {
    declare mItems=("Управление сервером" "Управление клиентами" "awg3_list" "list_client_names" "Удалить клиента" "Удалить AWG3 с сервера")
    declare mActions=("awg3_manager_menu" "awg3_clients_menu" "awg3_list" "list_client_names" "ask_remove_name" "awg3_uninstall")
    declare mTitle="Главное меню AmneziaWG 3"
    declare mDescr="Описание установки AWG3\n"
    declare mType="section"
    show_menu
}
