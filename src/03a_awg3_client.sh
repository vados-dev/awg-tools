# --> Функции подменю "Управление AWG3 клиентами" <--

# Наименьший свободный адрес в подсети сервера.
get_next_client_ip() {
    local net_int bcast_int
    read -r net_int bcast_int < <(_cidr_bounds "$S_ADDR") || log_error "не разобрана подсеть сервера '$S_ADDR'"
    declare -A used
    used["$(_int_to_ipv4 $((net_int + 1)))"]=1
    local ip
    while IFS= read -r ip; do
        used["$ip"]=1
    done < <(grep -oP 'AllowedIPs\s*=\s*\K[0-9.]+' "$AWG3_SERVER_CONF" 2>/dev/null || true)
    local i candidate
    for (( i = net_int + 2; i <= bcast_int - 1; i++ )); do
        candidate=$(_int_to_ipv4 "$i")
        if [[ -z "${used[$candidate]+x}" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    log_error "в подсети ${S_ADDR} нет свободных адресов"
}

# IPv6 клиента выводится из его IPv4 по смещению в подсети — уникальному при
# любой маске. Для /24 смещение равно последнему октету, иначе кодируется hex.
get_client_ipv6() {
    local ipv4="$1"
    [[ -n "${S_ADDR6:-}" ]] || return 0
    local net_int bcast_int offset suffix prefix tprefix
    read -r net_int bcast_int < <(_cidr_bounds "$S_ADDR") || return 0
    offset=$(( $(_ipv4_to_int "$ipv4") - net_int ))
    tprefix="${S_ADDR##*/}"
    if [[ "$tprefix" == "24" ]]; then suffix="$offset"; else suffix=$(printf '%x' "$offset"); fi
    prefix="${S_ADDR6%%::*}"
    [[ "$prefix" == *:* ]] || return 0
    echo "${prefix}::${suffix}"
}

# ── Рендер клиентского конфига ──────────────────────────────────────────────
# render_client_conf <файл> <privkey> <address> <server_pubkey> <endpoint> <port> [psk]
# Общие параметры берутся из S_*, sender-side — из G_*, поэтому вызывающая
# сторона обязана предварительно вызвать load_server_params и gen_sender_params.
render_client_conf() {
    local out="$1" privkey="$2" address="$3" srv_pub="$4" endpoint="$5" port="$6" psk="${7:-}"
    local mtu="${AWG3_MTU_OVERRIDE:-${S_MTU:-1280}}"
    local tmp
    tmp=$(mktemp "${out}.tmp.XXXXXX") || log_error "mktemp не сработал"
    chmod 600 "$tmp"
    {
        printf '[Interface]\n'
        printf 'PrivateKey = %s\n' "$privkey"
        printf 'Address = %s\n' "$address"
        printf 'DNS = %s\n' "$AWG3_CLIENT_DNS"
        printf 'MTU = %s\n' "$mtu"
        printf '\n'
        printf 'S1 = %s\nS2 = %s\nS3 = %s\nS4 = %s\n' "$S_S1" "$S_S2" "$S_S3" "$S_S4"
        printf 'H1 = %s\nH2 = %s\nH3 = %s\nH4 = %s\n' "$S_H1" "$S_H2" "$S_H3" "$S_H4"
        printf 'HeaderProtectionKey = %s\n' "$S_HPK"
        printf 'ContentPaddingAddition = %s\n' "$G_CPA"
        printf 'Jc = %s\nJmin = %s\nJmax = %s\n' "$G_Jc" "$G_Jmin" "$G_Jmax"
        local n
        for n in 1 2 3 4 5; do
            local var="G_I${n}"
            if [[ -n "${!var}" ]]; then printf 'I%s = %s\n' "$n" "${!var}"; fi
        done
        printf 'RekeyAfterTime = %s\n' "$G_RA"
        printf 'RekeyTimeout = %s\n' "$G_RT"
        printf 'RejectAfterTime = %s\n' "$G_RJ"
        printf 'KeepaliveTimeout = %s\n' "$G_KA"
        printf 'MaxHandshakeAttempts = %s\n' "$G_MHA"
        printf '\n'
        printf '[Peer]\n'
        printf 'PublicKey = %s\n' "$srv_pub"
        if [[ -n "$psk" ]]; then printf 'PresharedKey = %s\n' "$psk"; fi
        printf 'Endpoint = %s:%s\n' "$endpoint" "$port"
        printf 'AllowedIPs = %s\n' "$AWG3_CLIENT_ALLOWED_IPS"
        printf 'PersistentKeepalive = 33\n'
    } > "$tmp"
    mv -f "$tmp" "$out" || { rm -f "$tmp"; die "не записан $out"; }
    chmod 600 "$out"
    _fix_owner "$out"
}

# generate_qr <имя> <путь к conf> — PNG кладётся рядом с конфигом.
generate_qr() {
    local name="$1" conf="$2"
    [[ "$AWG3_MAKE_QR" -eq 1 ]] || return 0
    if ! command -v qrencode >/dev/null 2>&1; then
        log_warn "qrencode не установлен, QR-код для '$name' не создан"
        return 0
    fi
    local png="${conf%.conf}.png" tmp
    tmp=$(mktemp "${png}.tmp.XXXXXX") || return 1
    if qrencode -t png -o "$tmp" < "$conf"; then
        chmod 600 "$tmp"
        mv -f "$tmp" "$png"
        _fix_owner "$png"
        log_ok "QR-код: $png"
    else
        rm -f "$tmp"
        log_warn "не удалось создать QR-код для '$name'"
    fi
}

# ── Ссылка vpn:// для приложения Amnezia ────────────────────────────────────
# Формат ровно тот, который приложение AmneziaVPN принимает при импорте
# ссылки: vpn:// + base64url( BE32(длина JSON) || zlib(JSON) )
# Четыре байта длины впереди — это формат QByteArray::qCompress из Qt, на
# котором построен клиент; без них qUncompress не разожмёт поток.
# Внутри JSON лежит ВТОРОЙ JSON строкой в поле last_config, а тот несёт
# целиком текст клиентского конфига в поле config. Двойная вложенность не
# наша выдумка — так устроен формат.
# Параметры, которых в структурированных полях формата нет
# (HeaderProtectionKey, ContentPaddingAddition, таймеры 3.0), кладутся туда
# же по именам ключей конфига: приложение, которое их не знает, лишние поля
# проигнорирует, а полный текст конфига в любом случае едет в config.
# Обрезка пробелов по краям — значения из конфига приходят с ними постоянно.
_trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Экранирование строки для JSON. Пяти символов достаточно: другого управляющего в конфиге взяться неоткуда.
_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

# adler32 по stdin — хвост zlib-потока. Печатается восемью hex-цифрами.
_adler32() {
    od -An -v -tu1 | awk '
        BEGIN { a = 1; b = 0 }
        {
            for (i = 1; i <= NF; i++) {
                a = (a + $i) % 65521
                b = (b + a) % 65521
            }
        }
        # Двумя половинами: %x от 32-битного значения в mawk переполняется.
        END { printf "%04x%04x", b, a }
    '
}

# Четыре байта числа, старший вперёд.
_be32() {
    local n="$1"
    printf '%b' "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' \
        "$(( (n >> 24) & 255 ))" "$(( (n >> 16) & 255 ))" \
        "$(( (n >> 8) & 255 ))"  "$(( n & 255 ))")"
}

# zlib-поток из файла в stdout.
# Отдельного упаковщика zlib в системе может не быть, зато gzip есть всегда,
# а deflate внутри у них один и тот же — различаются только обёртки. С флагом
# -n gzip не пишет в заголовок имя файла и время, поэтому заголовок ровно
# 10 байт, а хвост (CRC32 + размер) — 8; остаётся заменить их на пару 0x78 0x9c впереди и adler32 в конце.
_zlib_compress() {
    local src="$1" gz size head4 adler
    gz="${src}.gz"
    # Внутри сжатого — приватный ключ клиента, поэтому файл создаётся сразу
    # закрытым: umask ставится в подоболочке вместе с самим перенаправлением.
    ( umask 077; gzip -c -n -9 < "$src" > "$gz" ) || { rm -f "$gz"; return 1; }
    size=$(wc -c < "$gz"); size=$(_trim_ws "$size")
    head4=$(head -c 4 "$gz" | od -An -v -tx1 | tr -d ' \n')
    # Заголовок обязан быть каноническим: 1f8b (магия), 08 (deflate), 00 (флагов нет). Иначе смещения ниже уедут и получится мусор.
    if [[ "$head4" != "1f8b0800" ]]; then
        rm -f "$gz"
        log_warn "неожиданный заголовок gzip ($head4)"
        return 1
    fi
    adler=$(_adler32 < "$src")
    printf '\x78\x9c'
    tail -c +11 "$gz" | head -c "$(( size - 18 ))"
    printf '%b' "\\x${adler:0:2}\\x${adler:2:2}\\x${adler:4:2}\\x${adler:6:2}"
    rm -f "$gz"
}

# build_vpn_uri <конфиг> [описание] — печатает ссылку vpn:// в stdout.
# Описание — имя сервера в списке приложения; по умолчанию берётся хост из Endpoint.
build_vpn_uri() {
    local conf="$1" desc="${2:-}"
    [[ -f "$conf" ]] || { log_warn "конфиг не найден: $conf"; return 1; }
    local dep
    for dep in gzip base64 od head tail; do
        command -v "$dep" >/dev/null 2>&1 \
            || { log_warn "нет команды $dep — ссылка vpn:// не создана"; return 1; }
    done
    local priv pub psk addr dns mtu endpoint_raw aips keepalive
    priv=$(_conf_value "$conf" PrivateKey interface)
    addr=$(_conf_value "$conf" Address interface)
    dns=$(_conf_value "$conf" DNS interface)
    mtu=$(_conf_value "$conf" MTU interface)
    pub=$(_conf_value "$conf" PublicKey peer)
    psk=$(_conf_value "$conf" PresharedKey peer)
    endpoint_raw=$(_conf_value "$conf" Endpoint peer)
    aips=$(_conf_value "$conf" AllowedIPs peer)
    keepalive=$(_conf_value "$conf" PersistentKeepalive peer)
    [[ -n "$priv" ]] || { log_warn "в $conf нет PrivateKey"; return 1; }
    [[ -n "$pub" ]]  || { log_warn "в $conf нет PublicKey сервера"; return 1; }
    [[ -n "$endpoint_raw" ]] || { log_warn "в $conf нет Endpoint"; return 1; }
    # Хост и порт. IPv6 приходит в скобках — [::1]:443, поэтому обрезать по последнему двоеточию нельзя.
    local host port
    if [[ "$endpoint_raw" == \[*\]:* ]]; then
        host="${endpoint_raw%%]:*}"; host="${host#\[}"
        port="${endpoint_raw##*]:}"
    else
        host="${endpoint_raw%:*}"
        port="${endpoint_raw##*:}"
    fi
    # port уезжает в JSON единственным числом без кавычек: пустое или
    # нечисловое значение сделало бы JSON синтаксически битым, и приложение молча откажется импортировать ссылку.
    [[ "$port" =~ ^[0-9]+$ ]] || { log_warn "непонятный Endpoint '$endpoint_raw'"; return 1; }
    local ip4="" ip6="" part
    while IFS= read -r part; do
        part=$(_trim_ws "$part")
        [[ -n "$part" ]] || continue
        part="${part%%/*}"
        if [[ "$part" == *:* ]]; then ip6="${ip6:-$part}"; else ip4="${ip4:-$part}"; fi
    done < <(printf '%s\n' "${addr//,/$'\n'}")
    local dns1 dns2
    dns1=$(_trim_ws "${dns%%,*}")
    if [[ "$dns" == *,* ]]; then dns2=$(_trim_ws "${dns#*,}"); dns2="${dns2%%,*}"; else dns2="$dns1"; fi
    dns1="${dns1:-1.1.1.1}"; dns2="${dns2:-$dns1}"
    mtu="${mtu:-1280}"
    keepalive="${keepalive:-33}"
    desc="${desc:-$host}"
    # AllowedIPs в формате уезжает массивом, а не строкой.
    local aips_json="" first=1
    while IFS= read -r part; do
        part=$(_trim_ws "$part")
        [[ -n "$part" ]] || continue
        if [[ "$first" -eq 1 ]]; then first=0; else aips_json+=","; fi
        aips_json+="\"$(_json_escape "$part")\""
    done < <(printf '%s\n' "${aips//,/$'\n'}")
    [[ -n "$aips_json" ]] || aips_json='"0.0.0.0/0"'
    local inner="{" key val
    for key in H1 H2 H3 H4 Jc Jmin Jmax S1 S2 S3 S4; do
        val=$(_conf_value "$conf" "$key" interface)
        inner+="\"${key}\":\"$(_json_escape "$val")\","
    done
    # I1-I5 в режиме роутера пустуют, а пустые поля приложение принимает за заданные — поэтому только непустые.
    for key in I1 I2 I3 I4 I5; do
        val=$(_conf_value "$conf" "$key" interface)
        [[ -n "$val" ]] || continue
        inner+="\"${key}\":\"$(_json_escape "$val")\","
    done
    for key in HeaderProtectionKey ContentPaddingAddition RekeyAfterTime \
               RekeyTimeout RejectAfterTime KeepaliveTimeout MaxHandshakeAttempts; do
        val=$(_conf_value "$conf" "$key" interface)
        [[ -n "$val" ]] || continue
        inner+="\"${key}\":\"$(_json_escape "$val")\","
    done
    inner+="\"allowed_ips\":[${aips_json}],"
    inner+="\"client_ip\":\"$(_json_escape "$ip4")\","
    inner+="\"client_ipv6\":\"$(_json_escape "$ip6")\","
    inner+="\"client_priv_key\":\"$(_json_escape "$priv")\","
    # Без psk_key импорт теряет PresharedKey, и рукопожатие не проходит — текста конфига в поле config для этого недостаточно.
    if [[ -n "$psk" ]]; then inner+="\"psk_key\":\"$(_json_escape "$psk")\","; fi
    inner+="\"config\":\"$(_json_escape "$(<"$conf")")\","
    inner+="\"hostName\":\"$(_json_escape "$host")\",\"mtu\":\"$(_json_escape "$mtu")\","
    inner+="\"persistent_keep_alive\":\"$(_json_escape "$keepalive")\",\"port\":${port},"
    inner+="\"server_pub_key\":\"$(_json_escape "$pub")\"}"
    local outer="{"
    outer+='"containers":[{"awg":{"isThirdPartyConfig":true,'
    outer+="\"last_config\":\"$(_json_escape "$inner")\","
    outer+="\"port\":\"${port}\",\"protocol_version\":\"2\",\"transport_proto\":\"udp\"},"
    outer+='"container":"amnezia-awg"}],'
    outer+='"defaultContainer":"amnezia-awg",'
    outer+="\"description\":\"$(_json_escape "$desc")\","
    outer+="\"dns1\":\"$(_json_escape "$dns1")\",\"dns2\":\"$(_json_escape "$dns2")\","
    outer+="\"hostName\":\"$(_json_escape "$host")\"}"
    # Приватный ключ клиента идёт через файл рядом с конфигом (каталог 700), а не через /tmp, который читаем всем.
    local tmp size b64
    tmp=$(mktemp "${conf}.uri.XXXXXX") || { log_warn "mktemp не сработал"; return 1; }
    chmod 600 "$tmp"
    printf '%s' "$outer" > "$tmp" || { rm -f "$tmp" "${tmp}.gz"; return 1; }
    size=$(wc -c < "$tmp"); size=$(_trim_ws "$size")
    if ! b64=$({ _be32 "$size"; _zlib_compress "$tmp"; } | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '='); then
        rm -f "$tmp" "${tmp}.gz"
        log_warn "не удалось собрать ссылку vpn://"
        return 1
    fi
    rm -f "$tmp" "${tmp}.gz"
    [[ -n "$b64" ]] || { log_warn "пустая ссылка vpn://"; return 1; }

    printf 'vpn://%s\n' "$b64"
}

# generate_link <имя> <путь к conf> — файл со ссылкой рядом с конфигом. Готовая ссылка остаётся в LINK_LAST, чтобы её можно было ещё и напечатать.
generate_link() {
    local name="$1" conf="$2"
    LINK_LAST=""
    [[ "$AWG3_MAKE_LINK" -eq 1 ]] || return 0
    local uri file="${conf%.conf}.vpnuri" tmp
    if ! uri=$(build_vpn_uri "$conf"); then
        log_warn "ссылка vpn:// для '$name' не создана"
        return 1
    fi
    tmp=$(mktemp "${file}.tmp.XXXXXX") || { log_warn "mktemp не сработал"; return 1; }
    chmod 600 "$tmp"
    printf '%s\n' "$uri" > "$tmp" || { rm -f "$tmp"; return 1; }
    if ! mv -f "$tmp" "$file"; then
        rm -f "$tmp"
        log_warn "не записана ссылка $file"
        return 1
    fi
    _fix_owner "$file"
    LINK_LAST="$uri"
    log_ok "ссылка: $file"
}

# ── Команда: add ────────────────────────────────────────────────────────────
awg3_add_client(){
    local name=""
    ask "Имя нового клиента: " "" name
    [[ "$name" != "" ]] && awg3_gen_add $name
}

awg3_gen_add() {
    local name="$1"
    validate_client_name "$name"
    load_server_params
    require_server_awg3
    local cdir conf
    cdir=$(client_dir "$name")
    conf="$cdir/${name}.conf"
    [[ ! -f "$conf" ]] || log_error "клиент '$name' уже существует: $conf"
    [[ ! -f "$AWG3_CLIENTS_ROOT/${name}.conf" ]] || log_error "клиент '$name' уже существует в старой раскладке: $AWG3_CLIENTS_ROOT/${name}.conf"
    if grep -qxF "#_Name = ${name}" "$AWG3_SERVER_CONF" 2>/dev/null; then
        log_error "пир '$name' уже есть в $AWG3_SERVER_CONF"
    fi
    local endpoint
    endpoint=$(resolve_endpoint)
    # Блокировка на время правки серверного конфига — тот же файл, что использует manage_amneziawg.sh, поэтому параллельный запуск безопасен.
    local lock_fd
    exec {lock_fd}>"$AWG3_LOCK_DIR/.awg_config.lock"
    flock -x -w 10 "$lock_fd" || log_error "не получен config-lock"
    local client_ip client_ip6 privkey pubkey address
    client_ip=$(get_next_client_ip)
    client_ip6=$(get_client_ipv6 "$client_ip")
    privkey=$(awg genkey)
    pubkey=$(printf '%s' "$privkey" | awg pubkey)
    if [[ -n "$client_ip6" ]]; then
        address="${client_ip}/32, ${client_ip6}/128"
    else
        address="${client_ip}/32"
        # У клиента нет IPv6-адреса, значит ::/0 в AllowedIPs — маршрут в
        # никуда. Хуже того, awg-quick на машине с отключённым IPv6 падает на
        # нём с «IPv6 is disabled on nexthop device» и не поднимает туннель
        # вообще. Убираем, если пользователь не потребовал явно.
        if [[ "$AWG3_CLIENT_ALLOWED_IPS_EXPLICIT" -eq 0 ]]; then
            AWG3_CLIENT_ALLOWED_IPS=$(strip_ipv6_routes "$AWG3_CLIENT_ALLOWED_IPS")
        fi
    fi
    # Дальше идут изменения на диске: при сбое откатываем всё, что успели.
    # Ловушка висит на EXIT, а не только на ERR: die() выходит через exit,
    # и на нём ERR не срабатывает.
    ROLLBACK_NAME="$name"
    ROLLBACK_SERVER_BAK=""
    ROLLBACK_ACTIVE=1
    trap '_rollback_add' EXIT
    mkdir -p "$cdir"; chmod 700 "$cdir"; _fix_owner "$cdir"
    printf '%s\n' "$privkey" > "$cdir/${name}.private"
    printf '%s\n' "$pubkey"  > "$cdir/${name}.public"
    chmod 600 "$cdir/${name}.private" "$cdir/${name}.public"
    _fix_owner "$cdir/${name}.private"; _fix_owner "$cdir/${name}.public"
    _backup_file "$AWG3_SERVER_CONF"
    ROLLBACK_SERVER_BAK="$BACKUP_LAST"
    {
        printf '\n[Peer]\n'
        printf '#_Name = %s\n' "$name"
        printf 'PublicKey = %s\n' "$pubkey"
        if [[ -n "$client_ip6" ]]; then
            printf 'AllowedIPs = %s/32, %s/128\n' "$client_ip" "$client_ip6"
        else
            printf 'AllowedIPs = %s/32\n' "$client_ip"
        fi
    } >> "$AWG3_SERVER_CONF"
    chmod 600 "$AWG3_SERVER_CONF"
    gen_sender_params
    render_client_conf "$conf" "$privkey" "$address" "$(server_public_key)" "$endpoint" "$S_PORT"
    ROLLBACK_ACTIVE=0
    trap - EXIT
    exec {lock_fd}>&-
    generate_qr "$name" "$conf"
    # Ссылка — приятное дополнение, а не условие успеха: клиент уже создан, применён и работоспособен с конфигом и QR даже без неё.
    generate_link "$name" "$conf" || true
    apply_peers || true
    log_ok "клиент '$name' создан: ${client_ip}${client_ip6:+, $client_ip6}"
    log "  каталог: $cdir"
    log "  конфиг: $conf"
    if [[ -f "${conf%.conf}.vpnuri" ]]; then log "  ссылка: ${conf%.conf}.vpnuri"; fi
    log "  профиль обфускации: AWG 3.0 / ${AWG3_PROFILE} / ${AWG3_INTENSITY}"
}

_rollback_add() {
    local rc=$?
    if [[ "${ROLLBACK_ACTIVE:-0}" -ne 1 ]]; then return 0; fi
    ROLLBACK_ACTIVE=0
    log_error "сбой при создании клиента — откатываю изменения"
    # Каталог создаётся этим же вызовом, поэтому удаляется целиком; чужого в нём быть не может — существование клиента проверено до начала работы.
    rm -rf "${AWG3_CLIENTS_ROOT:?}/${ROLLBACK_NAME:?}" 2>/dev/null || true
    if [[ -n "${ROLLBACK_SERVER_BAK:-}" && -f "$ROLLBACK_SERVER_BAK" ]]; then
        if cp -p "$ROLLBACK_SERVER_BAK" "$AWG3_SERVER_CONF"; then
            log_ok "серверный конфиг восстановлен"
        fi
    fi
    if [[ "$rc" -eq 0 ]]; then rc=1; fi
    exit "$rc"
}

# --> МЕНЮ: Управления клиентами AWG 3 <--
awg3_clients_menu() {
    declare mItems=("Список клиентов" "Добавить клиента" "Удалить клиента" "Перенос конфигов" "Создать ссылку" "Список имён клиентов" "Статус пиров" "Дамп пиров" "Статистика")
    declare mActions=("awg3_list" "awg3_add_client" "ask_remove_name_" "ask_migrate_name" "generate_link" "list_client_names" "peer_status" "load_peer_dump" "awg3_stats")
    declare mTitle="Меню клиентов AmneziaWG 3"
    declare mDescr="Управление клиентами AWG3\n"
    declare mType="section"
    show_menu
}
