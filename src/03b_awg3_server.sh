# --> Функции подменю "Установка AWG3" <--

# ── Генерация параметров ────────────────────────────────────────────────────
# gen_sender_params: то, что каждое устройство вправе иметь своё.
# Заполняет G_Jc G_Jmin G_Jmax G_I1..G_I5 G_CPA G_RA G_RT G_RJ G_KA G_MHA.
gen_sender_params() {
    local IV jc jmin jmax
    _intensity_value
    case "$AWG3_INTENSITY" in
        low)    rand_int 64 256;  jmin=$REPLY; rand_int 256 512;  jmax=$REPLY ;;
        medium) rand_int 128 512; jmin=$REPLY; rand_int 512 1024; jmax=$REPLY ;;
        high)   rand_int 256 768; jmin=$REPLY; rand_int 768 1280; jmax=$REPLY ;;
    esac
    # Между границами нужен реальный разброс, иначе «случайная» длина таковой не является.
    if [[ "$jmax" -le $((jmin + 64)) ]]; then
        rand_int 64 256
        jmax=$((jmin + 64 + REPLY))
    fi
    if [[ "$AWG3_ROUTER_MODE" -eq 1 ]]; then
        rand_int 2 3; jc=$REPLY
        if [[ "$jmin" -gt 40 ]];  then jmin=40; fi
        if [[ "$jmax" -gt 128 ]]; then jmax=128; fi
    else
        rand_int 3 7; jc=$REPLY
    fi
    G_Jc=$jc; G_Jmin=$jmin; G_Jmax=$jmax
    cps_chain "$AWG3_PROFILE" "$IV"; G_I1="$CHAIN"
    if [[ "$AWG3_ROUTER_MODE" -eq 1 ]]; then
        G_I2=""; G_I3=""; G_I4=""; G_I5=""
    else
        entropy_chain "$IV"; G_I2="$CHAIN"
        entropy_chain "$IV"; G_I3="$CHAIN"
        entropy_chain "$IV"; G_I4="$CHAIN"
        entropy_chain "$IV"; G_I5="$CHAIN"
    fi
    local cpa_lo cpa_hi
    if [[ "$AWG3_ROUTER_MODE" -eq 1 ]]; then
        rand_int 4 16;  cpa_lo=$REPLY
        rand_int 8 24;  cpa_hi=$((cpa_lo + REPLY))
    else
        rand_int 16 64;  cpa_lo=$REPLY
        rand_int 16 120; cpa_hi=$((cpa_lo + REPLY))
    fi
    G_CPA="${cpa_lo}-${cpa_hi}"
    local rt_lo rt_hi ka_lo ka_hi ra_lo ra_hi rj_lo rj_hi at_lo at_hi
    rand_int 4 6;     rt_lo=$REPLY
    rand_int 1 4;     rt_hi=$((rt_lo + REPLY))
    rand_int 8 14;    ka_lo=$REPLY
    rand_int 2 8;     ka_hi=$((ka_lo + REPLY))
    rand_int 100 120; ra_lo=$REPLY
    rand_int 10 30;   ra_hi=$((ra_lo + REPLY))

    # RejectAfterTime обязан перекрывать RekeyAfterTime вместе с окнами keepalive и rekey.
    # Ниже этого принимающая сторона перестаёт обновлять ключи, и сессия умирает по достижении дедлайна.
    rj_lo=$((ra_hi + ka_hi + rt_hi + 15))
    if [[ "$rj_lo" -lt 170 ]]; then rj_lo=170; fi
    rand_int 10 30;   rj_hi=$((rj_lo + REPLY))
    rand_int 12 18;   at_lo=$REPLY
    rand_int 2 10;    at_hi=$((at_lo + REPLY))
    G_RA="${ra_lo}-${ra_hi}"
    G_RT="${rt_lo}-${rt_hi}"
    G_RJ="${rj_lo}-${rj_hi}"
    G_KA="${ka_lo}-${ka_hi}"
    G_MHA="${at_lo}-${at_hi}"
}

# gen_shared_params: то, что обязано совпадать на обоих концах. Заполняет G_S1..G_S4 G_H1..G_H4 G_HPK.
gen_shared_params() {
    local s1 s2 s3 s4
    local h1_lo h1_hi h2_lo h2_hi h3_lo h3_hi h4_lo h4_hi
    if [[ "$AWG3_ROUTER_MODE" -eq 1 ]]; then
        rand_int 1 20; s1=$REPLY
        rand_int 1 20; s2=$REPLY
    else
        rand_int 1 150; s1=$REPLY
        rand_int 1 150; s2=$REPLY
    fi
    rand_int 1 64; s3=$REPLY
    rand_int 1 "$S4_MAX"; s4=$REPLY
    # Защита заголовка в 3.0 берёт nonce из этого padding'а, поэтому он не может быть короче nonce.
    if [[ "$s1" -lt "$NONCE_SIZE" ]]; then s1=$NONCE_SIZE; fi
    if [[ "$s2" -lt "$NONCE_SIZE" ]]; then s2=$NONCE_SIZE; fi
    if [[ "$s3" -lt "$NONCE_SIZE" ]]; then s3=$NONCE_SIZE; fi
    if [[ "$s4" -lt "$NONCE_SIZE" ]]; then s4=$NONCE_SIZE; fi
    # len(init) = 148 + S1, len(resp) = 92 + S2. Равные размеры вернули бы отпечаток обратно.
    if [[ "$s2" -eq $((s1 + 56)) ]]; then s2=$((s2 + 1)); fi
    if [[ "$s3" -eq $((s1 + 56)) ]]; then s3=$((s3 + 1)); fi
    if [[ "$s3" -eq $((s2 + 92)) ]]; then s3=$((s3 + 1)); fi
    if [[ "$s4" -gt "$S4_MAX" ]]; then s4=$S4_MAX; fi
    # Четыре непересекающиеся зоны, все в стороне от 1-4, которые upstream
    # WireGuard резервирует под свои типы сообщений. Каждая граница берётся
    # отдельно, чтобы диапазоны не повторяли форму друг друга.
    rand_int 100000000 900000000;   h1_lo=$REPLY
    rand_int 1000 50000;            h1_hi=$((h1_lo + REPLY))
    rand_int 1200000000 2000000000; h2_lo=$REPLY
    rand_int 1000 50000;            h2_hi=$((h2_lo + REPLY))
    rand_int 2400000000 3200000000; h3_lo=$REPLY
    rand_int 1000 50000;            h3_hi=$((h3_lo + REPLY))
    rand_int 3600000000 4000000000; h4_lo=$REPLY
    rand_int 1000 50000;            h4_hi=$((h4_lo + REPLY))
    G_S1=$s1; G_S2=$s2; G_S3=$s3; G_S4=$s4
    G_H1="${h1_lo}-${h1_hi}"; G_H2="${h2_lo}-${h2_hi}"
    G_H3="${h3_lo}-${h3_hi}"; G_H4="${h4_lo}-${h4_hi}"
    rand_b64_32; G_HPK="$RAND_B64"
}

# ── Чтение серверного конфига ───────────────────────────────────────────────
# Значение ключа из секции [Interface] (до первого [Peer]).
_iface_value() {
    local key="$1"
    awk -v k="$key" '
        /^[[:space:]]*\[Peer\]/ { exit }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (index(line, "#") == 1) next
            split(line, kv, "=")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", kv[1])
            if (kv[1] == k) {
                sub(/^[^=]*=[[:space:]]*/, "", line)
                gsub(/[[:space:]]+$/, "", line)
                print line
                exit
            }
        }
    ' "$AWG3_SERVER_CONF"
}

# Заполняет S_S1..S_S4 S_H1..S_H4 S_HPK S_MTU S_PORT S_ADDR S_ADDR6.
load_server_params() {
    if ! [[ -r "$AWG3_SERVER_CONF" ]]; then
        log_warn "серверный конфиг недоступен: $AWG3_SERVER_CONF, server_init делался?";
        cmd_server_init
    fi
    S_S1=$(_iface_value S1); S_S2=$(_iface_value S2)
    S_S3=$(_iface_value S3); S_S4=$(_iface_value S4)
    S_H1=$(_iface_value H1); S_H2=$(_iface_value H2)
    S_H3=$(_iface_value H3); S_H4=$(_iface_value H4)
    S_HPK=$(_iface_value HeaderProtectionKey)
    S_MTU=$(_iface_value MTU)
    S_PORT=$(_iface_value ListenPort)
    local addr_line
    addr_line=$(_iface_value Address)
    S_ADDR=""; S_ADDR6=""
    local part
    IFS=',' read -ra _addr_parts <<< "$addr_line"
    for part in "${_addr_parts[@]}"; do
        part="${part//[[:space:]]/}"
        [[ -z "$part" ]] && continue
        if [[ "$part" == *:* ]]; then
            if [[ -z "$S_ADDR6" ]]; then S_ADDR6="$part"; fi
        else
            if [[ -z "$S_ADDR" ]]; then S_ADDR="$part"; fi
        fi
    done
    [[ -n "$S_ADDR" ]] || die "в $AWG3_SERVER_CONF не найден IPv4 Address сервера"
    [[ -n "$S_PORT" ]] || die "в $AWG3_SERVER_CONF не найден ListenPort"
}

server_is_awg3() {
    [[ -n "${S_HPK:-}" ]]
}

# Фактическое состояние сервера читается из PostUp, а не из отдельного файла
# настроек: конфиг — единственный источник истины, и расходиться с ним нечему.
server_isolation_state() {
    if grep -qE 'FORWARD -i %i -o %i -j DROP' "$AWG3_SERVER_CONF" 2>/dev/null; then
        printf 'on'
    else
        printf 'off'
    fi
}

server_ipv6_state() {
    if grep -q 'ip6tables' "$AWG3_SERVER_CONF" 2>/dev/null; then
        printf 'on'
    else
        printf 'off'
    fi
}

require_server_awg3() {
    if server_is_awg3; then return 0; fi
    log_error "сервер ещё не переведён на AWG 3.0: в $AWG3_SERVER_CONF нет HeaderProtectionKey."
    die "Сначала выполните: $0 server-upgrade"
}

# ── PostUp / PostDown ───────────────────────────────────────────────────────
#
# Правила перенесены из render_server_config апстрима (bivlked v5.23.0) без
# изменения семантики. %i раскрывается awg-quick в имя интерфейса.
#
# TCPMSS-clamping обязателен: путь до клиента уже съеден заголовками туннеля,
# и без правки MSS TCP-сессии зависают на больших пакетах там, где PMTUD
# упирается в чёрную дыру — та самая жалоба «ping идёт, а сайт не грузится».

# build_postup NIC MTU ISOLATION IPV6   (ISOLATION/IPV6: on|off)
build_postup() {
    local nic="$1" mtu="$2" isolation="$3" ipv6="$4"
    local mss4=$(( mtu - 40 )) mss6=$(( mtu - 60 ))
    local r

    r="iptables -I FORWARD -i %i -j ACCEPT"
    r="${r}; iptables -t nat -A POSTROUTING -o ${nic} -j MASQUERADE"
    r="${r}; iptables -t mangle -A FORWARD -o %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${mss4}"
    r="${r}; iptables -t mangle -A FORWARD -i %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${mss4}"

    if [[ "$isolation" == "on" ]]; then
        # Цикл, а не одиночное -D: прерванный прошлый запуск мог оставить
        # несколько одинаковых правил, снять нужно все.
        r="${r}; while iptables -D FORWARD -i %i -o %i -j DROP 2>/dev/null; do :; done"
        r="${r}; iptables -I FORWARD -i %i -o %i -j DROP"
    fi

    if [[ "$ipv6" == "on" ]]; then
        r="${r}; ip6tables -I FORWARD -i %i -j ACCEPT"
        r="${r}; ip6tables -t nat -A POSTROUTING -o ${nic} -j MASQUERADE"
        r="${r}; ip6tables -t mangle -A FORWARD -o %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${mss6}"
        r="${r}; ip6tables -t mangle -A FORWARD -i %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${mss6}"
        if [[ "$isolation" == "on" ]]; then
            r="${r}; while ip6tables -D FORWARD -i %i -o %i -j DROP 2>/dev/null; do :; done"
            r="${r}; ip6tables -I FORWARD -i %i -o %i -j DROP"
        fi
    fi

    printf '%s' "$r"
}

# build_postdown NIC MTU ISOLATION IPV6 — зеркало build_postup.
#
# DROP снимается с `|| true`: интерфейс может опускаться после того, как
# правило уже убрали вручную, и падать на этом PostDown не должен.
build_postdown() {
    local nic="$1" mtu="$2" isolation="$3" ipv6="$4"
    local mss4=$(( mtu - 40 )) mss6=$(( mtu - 60 ))
    local r

    r="iptables -D FORWARD -i %i -j ACCEPT"
    r="${r}; iptables -t nat -D POSTROUTING -o ${nic} -j MASQUERADE"
    r="${r}; iptables -t mangle -D FORWARD -o %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${mss4}"
    r="${r}; iptables -t mangle -D FORWARD -i %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${mss4}"

    if [[ "$isolation" == "on" ]]; then
        r="${r}; iptables -D FORWARD -i %i -o %i -j DROP 2>/dev/null || true"
    fi

    if [[ "$ipv6" == "on" ]]; then
        r="${r}; ip6tables -D FORWARD -i %i -j ACCEPT"
        r="${r}; ip6tables -t nat -D POSTROUTING -o ${nic} -j MASQUERADE"
        r="${r}; ip6tables -t mangle -D FORWARD -o %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${mss6}"
        r="${r}; ip6tables -t mangle -D FORWARD -i %i -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${mss6}"
        if [[ "$isolation" == "on" ]]; then
            r="${r}; ip6tables -D FORWARD -i %i -o %i -j DROP 2>/dev/null || true"
        fi
    fi

    printf '%s' "$r"
}

# ── Endpoint ────────────────────────────────────────────────────────────────
# Порядок: --endpoint > #_Endpoint из awg0.conf > Endpoint уже существующего клиента > внешний IP.
# Отдельного файла настроек нет — источник истины только awg0.conf, поэтому имя хоста хранится там же комментарием.
server_endpoint_name() {
    [[ -r "$AWG3_SERVER_CONF" ]] || return 0
    awk '
        /^[[:space:]]*\[Peer\]/ { exit }
        /^[[:space:]]*#_Endpoint[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/[[:space:]]+$/, "")
            print
            exit
        }
    ' "$AWG3_SERVER_CONF"
}

resolve_endpoint() {
    if [[ -n "$AWG3_ENDPOINT_OVERRIDE" ]]; then
        echo "${AWG3_ENDPOINT_OVERRIDE%%:*}"
        return 0
    fi
    local saved
    saved=$(server_endpoint_name)
    if [[ -n "$saved" ]]; then
        echo "$saved"
        return 0
    fi
    local f ep url name
    while IFS= read -r name; do
        f=$(client_conf_path "$name")
        [[ -f "$f" ]] || continue
        ep=$(grep -oP '^Endpoint\s*=\s*\K[^:]+' "$f" 2>/dev/null | head -1 || true)
        if [[ -n "$ep" ]]; then echo "$ep"; return 0; fi
    done < <(list_client_names)
    for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        ep=$(curl -fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ "$ep" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then echo "$ep"; return 0; fi
    done
    die "не удалось определить endpoint, укажите его явно: --endpoint HOST"
}

# Файлы должны остаться у владельца каталога awg, иначе старый
# manage_amneziawg.sh, запущенный не под root, перестанет их читать.
_fix_owner() {
    local target="$1" owner
    owner=$(stat -c '%u:%g' "$AWG3_SYSCONF_DIR" 2>/dev/null) || return 0
    chown "$owner" "$target" 2>/dev/null || true
}

_backup_file() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    # Объявление отдельно от присваивания: иначе local маскирует код возврата подстановки, и сбой date остался бы незамеченным.
    local bak
    bak="${f}.bak-$(date '+%Y%m%d%H%M%S')"
    cp -p "$f" "$bak" || die "не создан бэкап $bak"
    BACKUP_LAST="$bak"
    log_ok "бэкап: $bak"
}

# ── Применение конфигурации ─────────────────────────────────────────────────
# syncconf переносит только список пиров: параметры самого интерфейса
# (S/H/HeaderProtectionKey) им не меняются, поэтому смена общих параметров требует полного перезапуска.
apply_peers() {
    [[ "$AWG3_DO_APPLY" -eq 1 ]] || { log_warn "применение пропущено (--no-apply)"; return 0; }
    local fd
    exec {fd}>"$AWG3_LOCK_DIR/.awg_apply.lock"
    if ! flock -x -w 120 "$fd"; then
        exec {fd}>&-
        log_warn "не получен apply-lock, изменения записаны, но не применены"
        return 1
    fi
    local strip_out rc=0
    if strip_out=$(timeout 10 awg-quick strip "$AWG3_IFACE" 2>/dev/null) \
       && printf '%s\n' "$strip_out" | timeout 10 awg syncconf "$AWG3_IFACE" /dev/stdin 2>/dev/null; then
        log_ok "конфигурация применена (syncconf)"
    else
        log_warn "syncconf не сработал, перезапускаю сервис"
        systemctl restart "awg-quick@${AWG3_IFACE}" 2>/dev/null || rc=$?
        [[ $rc -eq 0 ]] && log_ok "сервис перезапущен" || log_warn "ошибка перезапуска сервиса"
    fi
    exec {fd}>&-
    return $rc
}

apply_restart() {
    [[ "$AWG3_DO_APPLY" -eq 1 ]] || { log_warn "применение пропущено (--no-apply)"; return 0; }
    local rc=0
    systemctl restart "awg-quick@${AWG3_IFACE}" 2>/dev/null || rc=$?
    [[ $rc -eq 0 ]] && log_ok "сервис перезапущен" || log_warn "ошибка перезапуска сервиса"
    return $rc
}

# ── Рендер серверного конфига ───────────────────────────────────────────────
generate_server_keys() {
    local priv pub
    priv=$(awg genkey) || log_error "не сгенерирован приватный ключ сервера"
    pub=$(printf '%s' "$priv" | awg pubkey) || log_error "не выведен публичный ключ сервера"
    ( umask 077; printf '%s\n' "$priv" > "$AWG3_SERVER_KEYS_DIR/server_private.key" ) || log_error "не записан server_private.key"
    ( umask 077; printf '%s\n' "$pub" > "$AWG3_SERVER_KEYS_DIR/server_public.key" ) || log_error "не записан server_public.key"
    chmod 600 "$AWG3_SERVER_KEYS_DIR/server_private.key" "$AWG3_SERVER_KEYS_DIR/server_public.key"
    _fix_owner "$AWG3_SERVER_KEYS_DIR/server_private.key"
    _fix_owner "$AWG3_SERVER_KEYS_DIR/server_public.key"
    log_ok "ключи сервера созданы"
}

# Адрес сервера в IPv6-подсети — первый адрес, ::1.
derive_ipv6_server_addr() {
    local subnet="$1" prefix len
    prefix="${subnet%%/*}"; len="${subnet##*/}"
    prefix="${prefix%::}"
    printf '%s::1/%s' "$prefix" "$len"
}

# Все блоки [Peer] из файла: от первого до конца либо до следующего
# [Interface], который в норме встречается только в начале.
extract_peers() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    awk '
        /^[[:space:]]*\[Peer\]/      { in_peer = 1 }
        /^[[:space:]]*\[Interface\]/ { in_peer = 0 }
        in_peer { print }
    ' "$f"
}

# render_server_conf OUT PRIVKEY ADDRESS PORT MTU POSTUP POSTDOWN [PEERS_SRC]
# Общие параметры берутся из G_S*/G_H*/G_HPK, отправительские — из G_Jc,
# G_Jmin, G_Jmax, G_I1..G_I5, G_CPA, поэтому вызывающая сторона обязана
# заранее вызвать gen_shared_params и gen_sender_params.
# Пиры дописываются во ВРЕМЕННЫЙ файл до mv: иначе сбой между записью конфига
# и добавлением пиров оставил бы живой сервер без единого клиента.
render_server_conf() {
    local out="$1" privkey="$2" address="$3" port="$4" mtu="$5"
    local postup="$6" postdown="$7" peers_src="${8:-}"
    local dir tmp
    dir=$(dirname "$out")
    mkdir -p "$dir" || log_error "не создан каталог $dir"
    chmod 700 "$dir" 2>/dev/null || true
    tmp=$(mktemp "${out}.tmp.XXXXXX") || log_error "mktemp не сработал"
    chmod 600 "$tmp"
    {
        printf '[Interface]\n'
        # Имя хоста для клиентских Endpoint. Хранится комментарием в самом
        # конфиге, как и #_Name у пиров: отдельного файла настроек нет, а выводить DNS-имя из адреса интерфейса неоткуда.
        if [[ -n "${AWG3_ENDPOINT_OVERRIDE:-}" ]]; then
            printf '#_Endpoint = %s\n' "${AWG3_ENDPOINT_OVERRIDE%%:*}"
        fi
        printf 'PrivateKey = %s\n' "$privkey"
        printf 'Address = %s\n' "$address"
        printf 'ListenPort = %s\n' "$port"
        printf 'MTU = %s\n' "$mtu"
        printf 'PostUp = %s\n' "$postup"
        printf 'PostDown = %s\n' "$postdown"
        printf '\n'
        printf 'S1 = %s\nS2 = %s\nS3 = %s\nS4 = %s\n' "$G_S1" "$G_S2" "$G_S3" "$G_S4"
        printf 'H1 = %s\nH2 = %s\nH3 = %s\nH4 = %s\n' "$G_H1" "$G_H2" "$G_H3" "$G_H4"
        printf 'HeaderProtectionKey = %s\n' "$G_HPK"
        printf 'ContentPaddingAddition = %s\n' "$G_CPA"
        printf 'Jc = %s\nJmin = %s\nJmax = %s\n' "$G_Jc" "$G_Jmin" "$G_Jmax"
        local n var
        for n in 1 2 3 4 5; do
            var="G_I${n}"
            if [[ -n "${!var}" ]]; then printf 'I%s = %s\n' "$n" "${!var}"; fi
        done
    } > "$tmp"
    if [[ -n "$peers_src" && -f "$peers_src" ]]; then
        local peers
        peers=$(extract_peers "$peers_src")
        if [[ -n "$peers" ]]; then
            printf '\n%s\n' "$peers" >> "$tmp"
        fi
    fi
    mv -f "$tmp" "$out" || { rm -f "$tmp"; die "не записан $out"; }
    chmod 600 "$out"
    _fix_owner "$out"
}

# Публичный ключ сервера: из сохранённого файла, иначе выводится из приватного.
server_public_key() {
    if [[ -r "$AWG3_SERVER_KEYS_DIR/server_public.key" ]]; then
        tr -d '[:space:]' < "$AWG3_SERVER_KEYS_DIR/server_public.key"
        return 0
    fi
    local priv
    priv=$(_iface_value PrivateKey)
    [[ -n "$priv" ]] || log_error "в $AWG3_SERVER_KEYS_DIR нет PrivateKey"
    printf '%s' "$priv" | awg pubkey
}

# ── Команда: server-init ────────────────────────────────────────────────────
# Создание сервера AWG 3.0 с нуля: ключи, параметры обфускации, NAT, конфиг,
# форвардинг. Промежуточной стадии 2.0 не существует, server-upgrade здесь не
# участвует — он остаётся только для уже существующих 2.0-серверов.
guard_existing_server() {
    if [[ -f "$AWG3_SERVER_CONF" && "$AWG3_SRV_FORCE" -ne 1 ]]; then
        log_error "сервер уже существует: $AWG3_SERVER_CONF"
        log_error "Пересоздать с переносом пиров: $0 server-init --force"
        return 1
    fi
    return 0
}

awg3_server_init() {
    guard_existing_server || exit 1
    [[ -n "$AWG3_SRV_PORT" ]] || { rand_int 1024 65000; AWG3_SRV_PORT=$REPLY; }
    validate_port "$AWG3_SRV_PORT" || exit 1
    validate_subnet   "$AWG3_SRV_SUBNET" || exit 1
    validate_mtu      "$AWG3_SRV_MTU"    || exit 1
    port_is_free "$AWG3_SRV_PORT" || log_error "UDP-порт $AWG3_SRV_PORT уже занят"
    local nic
    nic=${ifext} || log_error "не определён внешний интерфейс — проверьте маршрут по умолчанию"
    log "внешний интерфейс: $nic"
    local peers_src=""
    if [[ -f "$AWG3_SERVER_CONF" ]]; then
        # Имя хоста переживает пересоздание сервера: клиенты продолжат подключаться по тому же адресу, если его не задали заново.
        if [[ -z "${AWG3_ENDPOINT_OVERRIDE:-}" ]]; then
            AWG3_ENDPOINT_OVERRIDE=$(server_endpoint_name)
            [[ -z "$AWG3_ENDPOINT_OVERRIDE" ]] || log "имя хоста сохранено: $AWG3_ENDPOINT_OVERRIDE"
        fi
        _backup_file "$AWG3_SERVER_CONF"
        peers_src="$BACKUP_LAST"
    fi
    ROLLBACK_SERVER_BAK="$peers_src"
    ROLLBACK_ACTIVE=1
    trap '_rollback_server_init' EXIT
    mkdir -p "$AWG3_SERVER_KEYS_DIR"; chmod 700 "$AWG3_SERVER_KEYS_DIR"; _fix_owner "$AWG3_SERVER_KEYS_DIR"
    generate_server_keys
    local address="$AWG3_SRV_SUBNET"
    if [[ "$AWG3_SRV_IPV6" == "on" ]]; then
        address="${address}, $(derive_ipv6_server_addr "$AWG3_SRV_IPV6_SUBNET")"
    fi
    gen_shared_params
    gen_sender_params
    local postup postdown
    postup= #$(build_postup     "$nic" "$AWG3_SRV_MTU" "$AWG3_SRV_ISOLATION" "$AWG3_SRV_IPV6")
    postdown= #$(build_postdown "$nic" "$AWG3_SRV_MTU" "$AWG3_SRV_ISOLATION" "$AWG3_SRV_IPV6")
    local privkey
    privkey=$(tr -d '[:space:]' < "$AWG3_SERVER_KEYS_DIR/server_private.key")
    render_server_conf "$AWG3_SERVER_CONF" "$privkey" "$address" "$AWG3_SRV_PORT" "$AWG3_SRV_MTU" "$postup" "$postdown" "$peers_src"
    #enable_forwarding "$AWG3_SRV_IPV6" /etc/sysctl.d/99-awg3.conf || log_warn "форвардинг не настроен"
    ROLLBACK_ACTIVE=0
    trap - EXIT
    if [[ "$AWG3_DO_APPLY" -eq 1 ]]; then
        systemctl enable --now "awg-quick@${AWG3_IFACE}" 2>/dev/null || log_warn "сервис не запустился, смотрите: systemctl status awg-quick@${AWG3_IFACE}"
    fi
    log_ok "сервер AWG 3.0 создан: $AWG3_SERVER_CONF"
    log "  порт: ${AWG3_SRV_PORT}/udp, подсеть: ${AWG3_SRV_SUBNET}, MTU: ${AWG3_SRV_MTU}"
    log "  изоляция клиентов: ${AWG3_SRV_ISOLATION}, IPv6: ${AWG3_SRV_IPV6}"
    log "  добавить клиента: $0 add ИМЯ"
}

# Ловушка висит на EXIT, а не на ERR: die() выходит через exit, и ERR на нём не срабатывает.
_rollback_server_init() {
    local rc=$?
    if [[ "${ROLLBACK_ACTIVE:-0}" -ne 1 ]]; then return 0; fi
    ROLLBACK_ACTIVE=0
    log_error "сбой при создании сервера — откатываю"
    rm -f "$AWG3_SERVER_KEYS_DIR/server_private.key" "$AWG3_SERVER_KEYS_DIR/server_public.key" 2>/dev/null || true
    if [[ -n "${ROLLBACK_SERVER_BAK:-}" && -f "$ROLLBACK_SERVER_BAK" ]]; then
        if cp -p "$ROLLBACK_SERVER_BAK" "$AWG3_SERVER_CONF"; then
            log_ok "прежний конфиг восстановлен"
        fi
    else
        rm -f "$AWG3_SERVER_CONF" 2>/dev/null || true
    fi
    if [[ "$rc" -eq 0 ]]; then rc=1; fi
    exit "$rc"
}

# ── Команда: set-endpoint ───────────────────────────────────────────────────
# Меняет имя хоста для клиентских Endpoint, не трогая ничего больше. Отдельная
# команда нужна потому, что единственная альтернатива — server-init --force —
# перегенерирует общие параметры и обесценит все выданные конфиги.
cmd_set_endpoint() {
    local name="$1"
    [[ -n "$name" ]] || die "укажите имя хоста: $0 set-endpoint vpn.example.com"
    [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]] \
        || die "недопустимое имя хоста: '$name'"
    [[ -f "$AWG3_SERVER_CONF" ]] || die "серверный конфиг не найден: $AWG3_SERVER_CONF"
    local previous
    previous=$(server_endpoint_name)
    _backup_file "$AWG3_SERVER_CONF"
    local tmp
    tmp=$(mktemp "${SERVER_CONF}.tmp.XXXXXX") || log_error "mktemp не сработал"
    chmod 600 "$tmp"
    # Строка живёт в [Interface] сразу после заголовка. Прежняя убирается, а не дублируется: иначе server_endpoint_name читал бы первую попавшуюся.
    awk -v host="$name" '
        BEGIN { done = 0; in_peer = 0 }
        /^[[:space:]]*\[Peer\]/ { in_peer = 1 }
        # Прежняя строка удаляется независимо от флага: она идёт ПОСЛЕ
        # [Interface], то есть встречается уже со взведённым done, и проверка
        # на него оставила бы в файле обе строки разом.
        !in_peer && /^[[:space:]]*#_Endpoint[[:space:]]*=/ { next }
        /^[[:space:]]*\[Interface\]/ && !done {
            print
            printf "#_Endpoint = %s\n", host
            done = 1
            next
        }
        { print }
    ' "$AWG3_SERVER_CONF" > "$tmp" || { rm -f "$tmp"; die "не перестроен $AWG3_SERVER_CONF"; }
    grep -qxF "#_Endpoint = ${name}" "$tmp" \
        || { rm -f "$tmp"; die "строка не добавилась — в конфиге нет секции [Interface]?"; }
    mv -f "$tmp" "$AWG3_SERVER_CONF" || { rm -f "$tmp"; die "не записан $AWG3_SERVER_CONF"; }
    chmod 600 "$AWG3_SERVER_CONF"
    if [[ -n "$previous" ]]; then
        log_ok "имя хоста изменено: ${previous} → ${name}"
    else
        log_ok "имя хоста задано: ${name}"
    fi
    log "Уже выданные конфиги продолжат работать по прежнему адресу."
    log "Новое имя попадёт в конфиги, созданные дальше: $0 add ИМЯ"
}

awg3_gen() {
    gen_shared_params
    gen_sender_params
    cat <<EOF
# AmneziaWG ${AWG3_PROTOCOL} — сгенерировано awg3_generator.sh config version $(date '+%Y%m%d%H%M%S').
# S1-S4, H1-H4 и HeaderProtectionKey должны совпадать на ОБОИХ концах.
# Jc, Jmin, Jmax, I1-I5, ContentPaddingAddition и таймеры — sender-side:
# у каждого устройства могут быть свои, и разные значения лучше.

[Interface]
S1 = ${G_S1}
S2 = ${G_S2}
S3 = ${G_S3}
S4 = ${G_S4}
H1 = ${G_H1}
H2 = ${G_H2}
H3 = ${G_H3}
H4 = ${G_H4}
HeaderProtectionKey = ${G_HPK}
ContentPaddingAddition = ${G_CPA}
Jc = ${G_Jc}
Jmin = ${G_Jmin}
Jmax = ${G_Jmax}
EOF
    local n var
    for n in 1 2 3 4 5; do
        var="G_I${n}"
        if [[ -n "${!var}" ]]; then printf 'I%s = %s\n' "$n" "${!var}"; fi
    done
    cat <<EOF
RekeyAfterTime = ${G_RA}
RekeyTimeout = ${G_RT}
RejectAfterTime = ${G_RJ}
KeepaliveTimeout = ${G_KA}
MaxHandshakeAttempts = ${G_MHA}
# Требуется amneziawg-go >= 3.0.1 и amneziawg-tools с поддержкой 3.0.
# S1-S4 подняты минимум до ${NONCE_SIZE}: nonce шифра берётся из этого padding'а.
EOF
}

awg3_server_upgrade() {
    load_server_params
    if server_is_awg3; then
        log_warn "сервер уже на AWG 3.0 (HeaderProtectionKey присутствует)."
        log_warn "Повторный запуск сгенерирует НОВЫЕ общие параметры и разорвёт все текущие подключения."
        ask_yn "  ${byel}Всё равно перегенерировать? ${bnc}" "n" force_awg3
            if [[ "$force_awg3" == "n" ]]; then
                print_err "отменено"
                return 1
            fi
    fi
    log "После смены общих параметров все клиентские конфиги станут недействительны."
    log "Каждого клиента придётся создать заново: $0 remove ИМЯ, затем $0 add ИМЯ"
    ask_yn "  ${byel}Всё равно продолжить? ${bnc}" "n" continue
    if [[ "$continue" == "n" ]]; then
        print_err "отменено"
        return 1
    fi
    gen_shared_params
    _backup_file "$AWG3_SERVER_CONF"
    local tmp
    tmp=$(mktemp "${AWG3_SERVER_CONF}.tmp.XXXXXX") || log_error "mktemp не сработал"
    chmod 600 "$tmp"
    # Старые S/H/HPK/CPA вырезаются из [Interface], новые вставляются единым
    # блоком перед первым [Peer]. Всё остальное — PostUp, MTU, ListenPort, список пиров — переносится дословно.
    awk -v s1="$G_S1" -v s2="$G_S2" -v s3="$G_S3" -v s4="$G_S4" -v h1="$G_H1" -v h2="$G_H2" -v h3="$G_H3" -v h4="$G_H4" -v hpk="$G_HPK" -v cpa="$G_CPA" '
        function emit_block() {
            printf "\nS1 = %s\nS2 = %s\nS3 = %s\nS4 = %s\n", s1, s2, s3, s4
            printf "H1 = %s\nH2 = %s\nH3 = %s\nH4 = %s\n", h1, h2, h3, h4
            printf "HeaderProtectionKey = %s\n", hpk
            printf "ContentPaddingAddition = %s\n", cpa
        }
        BEGIN { in_iface = 0; done = 0 }
        /^[[:space:]]*\[Interface\]/ { in_iface = 1; print; next }
        /^[[:space:]]*\[Peer\]/ {
            if (in_iface && !done) { emit_block(); done = 1 }
            in_iface = 0; print; next
        }
        {
            if (in_iface) {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                split(line, kv, "=")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", kv[1])
                if (kv[1] ~ /^(S[1-4]|H[1-4]|HeaderProtectionKey|ContentPaddingAddition|Jc|Jmin|Jmax|I[1-5])$/) next
                if (line == "") next
            }
            print
        }
        END { if (in_iface && !done) emit_block() }
    ' "$AWG3_SERVER_CONF" > "$tmp" || { rm -f "$tmp"; log_error "не удалось перестроить $AWG3_SERVER_CONF"; }
    mv -f "$tmp" "$AWG3_SERVER_CONF" || { rm -f "$tmp"; log_error "не записан $AWG3_SERVER_CONF"; }
    chmod 600 "$AWG3_SERVER_CONF"
    log_ok "сервер переведён на AWG 3.0"
    # syncconf не меняет параметры интерфейса — только полный перезапуск.
    #apply_restart || true
    log_warn "старые конфиги больше не подключатся — пересоздайте клиентов заново"
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
    # Повторный запуск не должен менять порт: клиенты уже раздали конфиги с прежним значением, и смена порта тихо оборвала бы их всех.
    if [[ -r "$AWG3_RESERVED_ENV" ]]; then
            local prev_port prev_subnet
            prev_port="$(awk -F= '/^AWG3_PORT=/{print $2}' "$AWG3_RESERVED_ENV")"
            prev_subnet="$(awk -F= '/^AWG3_SUBNET=/{print $2}' "$AWG3_RESERVED_ENV")"
            log "Переустановка: сохраняю прежний резерв."
            log "Порт ${prev_port}, подсеть ${prev_subnet}."
            log "Сбросить резерв: rm ${AWG3_RESERVED_ENV}."
            return 0
    fi
    local awg2_port="" awg2_addr="" awg2_net=""
    if [[ -r "$AWG2_CONF" ]]; then
        awg2_port="$(awg2_field "$AWG2_CONF" ListenPort)"
        awg2_addr="$(awg2_field "$AWG2_CONF" Address)"
        awg2_net="$(cidr_network "$awg2_addr")"
        log_ok "AWG 2.0 найден: ${AWG2_CONF}"
        [[ -n "$awg2_port" ]] && log "Его порт   : ${awg2_port} (не займём)."
        [[ -n "$awg2_net"  ]] && log "Его подсеть: ${awg2_net}/24 (обойдём)."
    else
        log "AWG 2.0 не найден — ставимся на чистый сервер."
    fi
    if [[ -d /sys/module/amneziawg ]]; then
        log_warn "Загружен kernel-модуль amneziawg — это штатно, мы его не трогаем."
        log "Именно поэтому AWG3 не пользуется awg-quick: при модуле он поднял бы."
        log "Kernel-интерфейс вместо нашего userspace-демона."
    fi
    if [[ "$AWG3_PORT" == "" ]]; then
        AWG3_PORT="$(pick_port "$awg2_port")"
        validate_port "$AWG3_PORT" || exit 1
    fi
    if [[ "$AWG3_SUBNET" == "" ]]; then
        AWG3_SUBNET="$(pick_subnet "$awg2_net")"
    fi
    mkdir -p "$AWG3_CONF_DIR"; chmod 700 "$AWG3_CONF_DIR"
    cat >"$AWG3_RESERVED_ENV" <<EOF
# Зарезервировано установщиком AWG3 $(date -Is).
# Проверено на непересечение с AWG 2.0 на момент установки.
AWG3_PORT=${AWG3_PORT}
AWG3_IFACE=${AWG3_IF}
AWG3_ROUTE_TABLE=${AWG3_ROUTE_TABLE}
AWG2_PORT_SEEN=${awg2_port:-none}
AWG2_SUBNET_SEEN=${awg2_net:-none}
EOF
    chmod 600 "$AWG3_RESERVED_ENV"
    log_ok "Зарезервировано: порт ${our_port}, подсеть ${our_net}/24, таблица ${AWG3_ROUTE_TABLE}."
    log "Записано в ${AWG3_RESERVED_ENV}."
}

awg3_edit_default_env() {
    print_section "Параметры сервера AmneziaWG 3"
    if [[ -r "$AWG3_DEFAULT_ENV" ]]; then
        ask_yn "  ${byel}Переделываем $AWG3_DEFAULT_ENV? ${bnc}" "y" new_def_env
        if [[ "$new_def_env" == "yes" ]]; then
            print_delete "Переустановка: удаляю прежний $AWG3_DEFAULT_ENV."
            rm -f "$AWG3_DEFAULT_ENV" || true
            log "Пишем новый $AWG3_DEFAULT_ENV."
        fi
    else
        log "Файл резерва переменных окружения $AWG3_RESERVED_ENV не найден. Просто создаём новый."
        awg3_add_reserv
    fi
    local existing_subnets=""
    while IFS= read -r line; do
        local cidr
        cidr=$(echo "$line" | awk '{print $4}')
        [[ -n "$cidr" ]] && existing_subnets="${existing_subnets} ${cidr}"
    done < <(ip -o addr show | grep "inet " | grep -v "host lo")

    local def_endpoint_ip=${ipext}
    while true; do
        echo -e "  ${bnc}IP по которому клиенты подключаются к серверу."
        echo -e "  ${bnc}Если определён верно, просто нажми Enter."
        ask "Внешний IP (ENDPOINT): " "$def_endpoint_ip" AWG3_NEW_ENDPOINT
        validate_ip "$AWG3_NEW_ENDPOINT" && break
        log_error "Некорректный IP!"
    done
    print_ok "Внешний IP: ${AWG3_NEW_ENDPOINT}"

    local def_port=${AWG3_PORT}
    while true; do
        echo -e "  ${bld}UDP порт AmneziaWG. Дефолт $def_port, можно любой свободный."
        ask "UDP порт: " "$def_port" AWG3_NEW_PORT
        if ! validate_port "$AWG3_NEW_PORT"; then print_err "Порт 1-65535"; continue; fi
        if ss -H -uln 2>/dev/null | grep -Eq "[:.]${AWG3_NEW_PORT}[[:space:]]"; then
            print_warn "Порт ${AWG3_NEW_PORT} уже занят"; continue
        fi
        break
    done
    print_ok "Порт: ${AWG3_NEW_PORT}"

    # - интерфейс туннеля -
    local def_iface=${AWG3_IF}
    while true; do
        echo -e "  ${bnc}Интерфейс AmneziaWG. Дефолт ${bmag}${def_iface}${bnc}."
        ask "Имя интерфейса" "$def_iface" AWG3_NEW_IF
        if ! validate_tunnel_iface "$AWG3_NEW_IF"; then log_error "$AWG3_NEW_IF"; continue; fi
        break
    done
    print_ok "Интерфейс: ${AWG3_NEW_IF}"

    # - подсеть туннеля -
    local def_subnet=${AWG3_SUBNET}
    while true; do
        echo ""
        log "Подсети на интерфейсах сервера: ${existing_subnets}."
        log_warn "${byel}Убедись что подсеть не совпадает с домашней сетью клиента (роутер, гостевой WiFi). Иначе VPN работать не будет."
        ask "Подсеть туннеля: " "$def_subnet" AWG3_NEW_SUBNET
        if ! validate_cidr "$AWG3_NEW_SUBNET"; then log_error "Формат: 10.10.10.0/24"; continue; fi
        local tunnel_base=$(cidr_base "$AWG3_NEW_SUBNET")
        # - subnets_overlap() заточен под 10.X.0.0/24, этого достаточно для схемы AWG -
        if subnets_overlap "$tunnel_base" "$existing_subnets"; then
            log_error "Конфликт с подсетью сервера!"
            log "Попробуй: 10.3.3.0/24 или 10.33.33.0/24"
            continue
        fi
        # - предупреждение о типичных домашних подсетях -
        local _home_conflict=false
        for _hs in 192.168.0 192.168.1 192.168.100 10.0.0 10.0.1 10.10.0; do
            if [[ "$tunnel_base" == "$_hs" ]]; then
                echo ""
                print_warn "Подсеть ${AWG3_NEW_SUBNET} очень распространена на домашних роутерах!"
                print_warn "Если у клиента дома роутер раздаёт ${AWG3_NEW_SUBNET},"
                print_warn "VPN работать не будет (конфликт маршрутов)!"
                echo ""
                local _hc=""
                ask_yn "Всё равно использовать?" "n" _hc
                [[ "$_hc" != "yes" ]] && { _home_conflict=true; break; }
                break
            fi
        done
        $_home_conflict && continue
        break
    done
    local tunnel_base
    tunnel_base=$(cidr_base "$AWG3_NEW_SUBNET")
    AWG3_NEW_ADDRESS="${tunnel_base}.1"
    print_ok "Подсеть: ${AWG3_NEW_SUBNET}, IP сервера: ${AWG3_NEW_ADDRESS}"

    # - DNS -
    local def_dns="10.30.30.33, 8.8.4.4"
    echo ""
    echo -e "  ${bnc}DNS для клиентов:"
    if systemctl is-active --quiet unbound 2>/dev/null; then
        echo -e "  ${bnc}1) Unbound (IP туннеля): ${AWG3_NEW_ADDRESS}"
        echo -e "  ${bmag}2${bnc}) Предустановленные: ${def_dns}${nc}"
        echo ""
        while true; do
            ask_raw "$(printf '  \033[1mВыбор? \033[1;35m[2]\033[1m:\033[0m ')" AWG3_NEW_DNS "$def_dns" -
            case "${AWG3_NEW_DNS:-2}" in
                1) AWG3_NEW_DNS="${AWG3_NEW_ADDRESS}"; break ;;
                2) AWG3_NEW_DNS="${def_dns}"; break ;;
                *) AWG3_NEW_DNS="${def_dns}"; break ;;
            esac
        done
    elif systemctl is-active --quiet named 2>/dev/null; then
        echo -e "  ${bnc}1) Named (IP туннеля): ${AWG3_NEW_ADDRESS}"
        echo -e "  ${bmag}2${bnc}) Предустановленные: ${def_dns}${nc}"
        echo ""
        while true; do
            ask_raw "$(printf '  \033[1mВыбор? \033[1;35m[2]\033[1m:\033[0m ')" AWG3_NEW_DNS "$def_dns" -
            case "${AWG3_NEW_DNS:-2}" in
                1) AWG3_NEW_DNS="${AWG3_NEW_ADDRESS}"; break ;;
                2) AWG3_NEW_DNS="${def_dns}"; break ;;
                *) AWG3_NEW_DNS="${def_dns}"; break ;;
            esac
        done
    else
        log "Unbound или named не запущены, дефолт: ${AWG3_NEW_DNS}"
    fi
    print_ok "DNS: ${AWG3_NEW_DNS}"

    # - AllowedIPs -
    local def_allowed="0.0.0.0/0"
    local kill_switch="0.0.0.0/1, 128.0.0.0/1"
    echo ""
    echo -e "  ${bnc}Маршрутизация трафика:"
    echo -e "  ${bmag}1${bnc}) ${def_allowed} (весь трафик через VPN)"
    echo -e "  ${bnc}2) ${kill_switch} (kill switch)"
    echo -e "  ${bnc}3) ${AWG3_NEW_SUBNET} (только туннель)"
    echo -e "  ${bnc}4) Ввести вручную${nc}"
    echo ""
    while true; do
        ask_raw "$(printf '  \033[1mВыбор? \033[1;35m[1]\033[1m:\033[0m ')" AWG3_NEW_ALLOWED "$def_allowed" -
        case "${rt_ch:-1}" in
            1) AWG3_NEW_ALLOWED="$def_allowed"; break ;;
            2) AWG3_NEW_ALLOWED="$kill_switch"; break ;;
            3) AWG3_NEW_ALLOWED="$AWG3_NEW_SUBNET"; break ;;
            4) ask "AllowedIPs" $def_allowed AWG3_NEW_ALLOWED; break ;;
            *) AWG3_NEW_ALLOWED="$def_allowed"; break ;;
        esac
    done
    print_ok "AllowedIPs: ${AWG3_NEW_ALLOWED}"

    # -- MTU ТУННЕЛЯ --
    local def_mtu="1320"
    echo ""
    echo -e "  ${bnc}MTU туннеля:"
    echo -e "  ${bnc}1) 1280 - максимальная совместимость (мобильные сети, GTP)"
    echo -e "  ${bnc}2) 1300 - баланс и совместимость"
    echo -e "  ${bmag}3${bnc}) 1320 - баланс (рекомендуется 'ЭТО БАЗА')"
    echo -e "  ${bnc}4) 1360 - баланс и скорость"
    echo -e "  ${bnc}5) 1420 - максимальная скорость (чистый Ethernet)"
    echo -e "  ${bnc}6) Ввести вручную"${nc}
    while true; do
        ask_raw "$(printf '  \033[1mВыбор? \033[1;35m[3]\033[1m:\033[0m ')" AWG3_NEW_MTU "$def_mtu" -
        case "${AWG3_NEW_MTU:-3}" in
            1) AWG3_NEW_MTU="1280"; break ;;
            2) AWG3_NEW_MTU="1300"; break ;;
            3) AWG3_NEW_MTU="1320"; break ;;
            4) AWG3_NEW_MTU="1360"; break ;;
            5) AWG3_NEW_MTU="1420"; break ;;
            6) ask "MTU" $def_mtu AWG3_NEW_MTU; break ;;
            *) AWG3_NEW_MTU="$def_mtu"; break ;;
        esac
    done
    log_ok "MTU: ${AWG3_NEW_MTU}"

    # - Firewalld Policy -
    local def_fw_policy=${AWG3_FW_POLICY}
    echo ""
    echo -e "  ${bnc}Имя firewalld policy:"
    echo -e "  ${bmag}1${bnc}) ${def_fw_policy} (туннель в Интернет)"
    echo -e "  ${bnc}2) Ввести вручную${nc}"
    echo ""
    while true; do
        ask_raw "$(printf '  \033[1mВыбор? \033[1;35m[1]\033[1m:\033[0m ')" AWG3_NEW_FW_POLICY "$def_fw_policy" -
        case "${AWG3_NEW_FW_POLICY:-1}" in
            1) AWG3_NEW_FW_POLICY="$def_fw_policy"; break ;;
            2) ask "Имя firewalld policy: " $def_fw_policy AWG3_NEW_FW_POLICY; break ;;
            *) AWG3_NEW_FW_POLICY="$def_fw_policy"; break ;;
        esac
    done
    print_ok "Имя firewalld policy: ${AWG3_NEW_FW_POLICY}"

    # - Firewalld Service -
    local def_fw_service=${AWG3_FW_SERVICE}
    echo ""
    echo -e "  ${bnc}Имя firewalld service:"
    echo -e "  ${bmag}1${bnc}) ${def_fw_service}"
    echo -e "  ${bnc}2) Ввести вручную${nc}"
    echo ""
    while true; do
        ask_raw "$(printf '  \033[1mВыбор? \033[1;35m[1]\033[1m:\033[0m ')" AWG3_NEW_FW_SERVICE "$def_fw_service" -
        case "${AWG3_NEW_FW_SERVICE:-1}" in
            1) AWG3_NEW_FW_SERVICE="$def_fw_service"; break ;;
            2) ask "Имя firewalld service: " $def_fw_service AWG3_NEW_FW_SERVICE; break ;;
            *) AWG3_NEW_FW_SERVICE="$def_fw_service"; break ;;
        esac
    done
    print_ok "Имя firewalld service: ${AWG3_NEW_FW_SERVICE}"

    # - Firewalld Zone -
    local def_fw_zone=${AWG3_FW_ZONE}
    echo ""
    echo -e "  ${bnc}Имя firewalld zone:"
    echo -e "  ${bmag}1${bnc}) ${def_fw_zone}"
    echo -e "  ${bnc}2) Ввести вручную${nc}"
    echo ""
    while true; do
        ask_raw "$(printf '  \033[1mВыбор? \033[1;35m[1]\033[1m:\033[0m ')" AWG3_NEW_FW_ZONE "$def_fw_zone" -
        case "${AWG3_NEW_FW_ZONE:-1}" in
            1) AWG3_NEW_FW_ZONE="$def_fw_zone"; break ;;
            2) ask "Имя firewalld zone: " $def_fw_zone AWG3_NEW_FW_ZONE; break ;;
            *) AWG3_NEW_FW_ZONE="$def_fw_zone"; break ;;
        esac
    done
    print_ok "Имя firewalld zone: ${AWG3_NEW_FW_ZONE}"

    local force_create_reserv
    [[ "$AWG3_NEW_ENDPOINT" != "$AWG3_ENDPOINT" ]] && AWG3_ENDPOINT="$AWG3_NEW_ENDPOINT" || true
    [[ "$AWG3_NEW_PORT" != "$AWG3_PORT" ]] && AWG3_PORT="$AWG3_NEW_PORT" || true
    [[ "$AWG3_NEW_IF" != "$AWG3_IF" ]] && AWG3_IF="$AWG3_NEW_IF" || true
    [[ "$AWG3_NEW_SUBNET" != "$AWG3_SUBNET" ]] && AWG3_SUBNET="$AWG3_NEW_SUBNET" || true
    [[ "$AWG3_NEW_ADDRESS" != "$AWG3_ADDRESS" ]] && AWG3_ADDRESS="$AWG3_NEW_ADDRESS" || true
    [[ "$AWG3_NEW_DNS" != "$AWG3_DNS" ]] && AWG3_DNS="$AWG3_NEW_DNS" || true
    [[ "$AWG3_NEW_ALLOWED" != "$AWG3_ALLOWED" ]] && AWG3_ALLOWED="$AWG3_NEW_ALLOWED" || true
    [[ "$AWG3_NEW_MTU" != "$AWG3_MTU" ]] && AWG3_MTU="$AWG3_NEW_MTU" || true
    [[ "$AWG3_NEW_FW_POLICY" != "$AWG3_FW_POLICY" ]] && AWG3_FW_POLICY="$AWG3_NEW_FW_POLICY" || true
    [[ "$AWG3_NEW_FW_SERVICE" != "$AWG3_FW_SERVICE" ]] && AWG3_FW_SERVICE="$AWG3_NEW_FW_SERVICE" || true
    [[ "$AWG3_NEW_FW_ZONE" != "$AWG3_FW_ZONE" ]] && AWG3_FW_ZONE="$AWG3_NEW_FW_ZONE" || true
#    if [[ "$AWG3_PORT" == "" ]]; then
#        AWG3_PORT="$(pick_port "$awg2_port")"
#        validate_port "$AWG3_PORT" || exit 1
#    fi
#    if [[ "$AWG3_SUBNET" == "" ]]; then
#        AWG3_SUBNET="$(pick_subnet "$awg2_net")"
#    fi
    AWG3_DEFAULT_ENV=${AWG3_DEFAULT_ENV_DIR}/${AWG3_IF:-$AWG3_IFACE}.env
    cat >"${AWG3_DEFAULT_ENV}" <<EOF
# Зарезервировано установщиком AWG3 $(date -Is).
# Проверено на непересечение с AWG 2.0 на момент установки.
AWG3_PORT=${AWG3_PORT}
AWG3_IFACE=${AWG3_IF}
AWG3_ENDPOINT=${AWG3_ENDPOINT}
AWG3_SUBNET=${AWG3_SUBNET}
AWG3_ADDRESS=${AWG3_ADDRESS}/24
AWG3_DNS=${AWG3_DNS}
AWG3_ALLOWED_IPS=${AWG3_ALLOWED_IPS}
AWG3_MTU=${AWG3_MTU}
AWG3_FW_POLICY=${AWG3_FW_POLICY}
AWG3_FW_SERVICE=${AWG3_FW_SERVICE}
AWG3_FW_ZONE=${AWG3_FW_ZONE}
EOF
    chmod 600 "$AWG3_DEFAULT_ENV"
    log_ok "Зарезервировано: порт ${AWG3_PORT}, подсеть ${AWG3_SUBNET}/24, policy ${AWG3_FW_POLICY}."
    log "Записано в ${AWG3_DEFAULT_ENV}."
}

remove_awg3_fw_policy() {
    local del_policy=0
    del_policy=$(${fwperm} --delete-policy=${AWG3_FW_POLICY})
    ${fwreload}
    log "${del_policy}."
}

remove_awg3_fw_service() {
    local del_service=0
    del_service=$(${fwperm} --delete-service=${AWG3_FW_SERVICE})
    ${fwreload}
    log "${del_service}."
}

remove_awg3_fw_zone() {
    local rem_zone=0
    del_zone=$(${fwperm} --delete-zone=${AWG3_FW_ZONE})
    ${fwreload}
    log "${del_zone}."
}

# --> МЕНЮ: Управление AWG 3 <--
awg3_manager_menu() {
    declare mItems=("AWG3 генератор" "Редактировать дефолтное окружение" "Инициализировать сервер" "Создать клиента" "Обновить сервер" "Переноа конфигов" "Резервное копирование" "Рестарт awg" "Состояние" "Статистика")
    declare mActions=("awg3_gen" "awg3_edit_default_env" "awg3_server_init" "awg3_add_client" "awg3_server_upgrade" "ask_migrate_name" "awg3_backup" "awg3_restart" "awg3_show" "awg3_stats")
    declare mTitle="Управление AmneziaWG 3"
    declare mDescr="Описание управления AWG3\n"
    declare mType="section"
    show_menu
}
