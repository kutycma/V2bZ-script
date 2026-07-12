#!/usr/bin/env bash
# Công cụ tạo cấu hình V2bZ cho ZicBoard qua UniProxy legacy.

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

V2BZ_CONFIG_DIR="${V2BZ_CONFIG_DIR:-/etc/V2bZ}"

v2bz_trim_trailing_slash() {
    local value="$1"
    while [[ "$value" == */ ]]; do
        value="${value%/}"
    done
    printf '%s' "$value"
}

v2bz_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

v2bz_render_dns_env_json() {
    local dns_env="$1"
    local result="{"
    local first=1
    local pair key value

    dns_env="${dns_env//$'\n'/,}"
    dns_env="${dns_env//$'\r'/,}"
    IFS=',' read -r -a pairs <<<"$dns_env"
    for pair in "${pairs[@]}"; do
        [[ "$pair" == *"="* ]] || continue
        key="${pair%%=*}"
        value="${pair#*=}"
        key="$(echo "$key" | xargs)"
        value="$(echo "$value" | xargs)"
        [[ -z "$key" ]] && continue
        if [[ "$first" == "0" ]]; then
            result+=", "
        fi
        result+="\"$(v2bz_json_escape "$key")\": \"$(v2bz_json_escape "$value")\""
        first=0
    done
    result+="}"
    printf '%s' "$result"
}

v2bz_bool_json() {
    case "$(tr '[:upper:]' '[:lower:]' <<<"$1")" in
        1|true|yes|y|on) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

v2bz_check_ipv6_support() {
    if command -v ip >/dev/null 2>&1 && ip -6 addr | grep -q 'inet6'; then
        echo 1
    else
        echo 0
    fi
}

v2bz_default_core_for_node() {
    case "$1" in
        hysteria|hysteria2|tuic|anytls) echo "sing" ;;
        *) echo "xray" ;;
    esac
}

v2bz_core_supported() {
    local core="$1"
    local node_type="$2"

    case "$core:$node_type" in
        xray:shadowsocks|xray:vmess|xray:vless|xray:trojan) return 0 ;;
        sing:shadowsocks|sing:vmess|sing:vless|sing:trojan|sing:hysteria|sing:hysteria2|sing:tuic|sing:anytls) return 0 ;;
        hysteria2:hysteria2) return 0 ;;
        *) return 1 ;;
    esac
}

v2bz_prompt_core() {
    local node_type="$1"
    local result_var="$2"
    local choice selected

    while true; do
        echo -e "${yellow}Chọn core cho node ${node_type}:${plain}"
        echo "1. xray"
        echo "2. sing"
        echo "3. hysteria2"
        read -rp "Nhập lựa chọn [1-3]: " choice
        case "$choice" in
            1) selected="xray" ;;
            2) selected="sing" ;;
            3) selected="hysteria2" ;;
            *)
                echo -e "${red}Lựa chọn không hợp lệ. Vui lòng chọn 1, 2 hoặc 3.${plain}"
                continue
                ;;
        esac
        if v2bz_core_supported "$selected" "$node_type"; then
            printf -v "$result_var" '%s' "$selected"
            return 0
        fi
        echo -e "${red}Core ${selected} không hỗ trợ node ${node_type}. Vui lòng chọn lại.${plain}"
    done
}

v2bz_print_support_matrix() {
    cat <<'EOF'
V2bZ đang chạy theo UniProxy legacy của ZicBoard.

Không chọn node ZicNode/V2Node trong panel khi dùng V2bZ.
Hãy tạo node legacy riêng: VMess, VLess, Trojan, Shadowsocks.

Matrix hỗ trợ:
  - xray: shadowsocks, vmess, vless, trojan
  - sing: shadowsocks, vmess, vless, trojan, hysteria, hysteria2, tuic, anytls
  - hysteria2: chỉ hysteria2

Network khuyến nghị cho xray:
  - vmess/vless: tcp, ws, grpc, httpupgrade, xhttp
  - trojan: tcp, ws, grpc
EOF
}

v2bz_normalize_node_type() {
    tr '[:upper:]' '[:lower:]' <<<"$1"
}

v2bz_normalize_core() {
    tr '[:upper:]' '[:lower:]' <<<"$1"
}

v2bz_validate_quick_values() {
    local api_host="$1"
    local api_key="$2"
    local node_id="$3"
    local node_type="$4"
    local core="$5"

    if [[ -z "$api_host" || -z "$api_key" || -z "$node_id" || -z "$node_type" || -z "$core" ]]; then
        echo -e "${red}Thiếu api-host, api-key, node-id, node-type hoặc core.${plain}" >&2
        return 1
    fi
    if ! [[ "$node_id" =~ ^[0-9]+$ ]]; then
        echo -e "${red}Node ID phải là số nguyên dương.${plain}" >&2
        return 1
    fi
    case "$node_type" in
        zicnode|v2node)
            echo -e "${red}V2bZ không chạy node ZicNode/V2Node. Hãy chọn node legacy qua UniProxy.${plain}" >&2
            return 1
            ;;
        shadowsocks|vmess|vless|trojan|hysteria|hysteria2|tuic|anytls) ;;
        *)
            echo -e "${red}NodeType không hợp lệ: ${node_type}.${plain}" >&2
            return 1
            ;;
    esac
    if ! v2bz_core_supported "$core" "$node_type"; then
        echo -e "${red}Core ${core} không hỗ trợ node ${node_type}.${plain}" >&2
        v2bz_print_support_matrix >&2
        return 1
    fi
}

v2bz_validate_cert_values() {
    local cert_mode="$(tr '[:upper:]' '[:lower:]' <<<"${1:-none}")"
    case "$cert_mode" in
        none|auto|file|http|dns|self) return 0 ;;
        *)
            echo -e "${red}CertMode không hợp lệ: ${cert_mode}. Hợp lệ: auto, none, file, http, dns, self.${plain}" >&2
            return 1
            ;;
    esac
}

v2bz_validate_panel() {
    local api_host="$1"
    local api_key="$2"
    local node_id="$3"
    local node_type="$4"
    local tmp_file
    local status

    tmp_file="$(mktemp)"
    status=$(curl -k -L -sS -m 20 -o "$tmp_file" -w '%{http_code}' \
        --get "${api_host}/api/v3/server/UniProxy/config" \
        --data-urlencode "node_type=${node_type}" \
        --data-urlencode "node_id=${node_id}" \
        --data-urlencode "token=${api_key}" 2>/dev/null)
    local curl_status=$?
    local body
    body="$(cat "$tmp_file" 2>/dev/null)"
    rm -f "$tmp_file"

    if [[ $curl_status -ne 0 ]]; then
        echo -e "${red}Không kết nối được panel ZicBoard. Kiểm tra API Host hoặc mạng VPS.${plain}" >&2
        return 1
    fi
    if [[ "$status" == "304" || "$status" == "200" ]]; then
        echo -e "${green}Đã kiểm tra UniProxy config thành công.${plain}"
        return 0
    fi

    echo -e "${red}Panel trả HTTP ${status}. Token, Node ID hoặc NodeType có thể sai.${plain}" >&2
    if [[ -n "$body" ]]; then
        echo -e "${yellow}${body}${plain}" >&2
    fi
    return 1
}

v2bz_render_core_config() {
    case "$1" in
        xray)
            cat <<'EOF'
    {
      "Type": "xray",
      "Log": {"Level": "error", "ErrorPath": "/etc/V2bZ/error.log"},
      "OutboundConfigPath": "/etc/V2bZ/custom_outbound.json",
      "RouteConfigPath": "/etc/V2bZ/route.json"
    }
EOF
            ;;
        sing)
            cat <<'EOF'
    {
      "Type": "sing",
      "Log": {"Level": "error", "Timestamp": true},
      "NTP": {"Enable": false, "Server": "time.apple.com", "ServerPort": 0},
      "OriginalPath": "/etc/V2bZ/sing_origin.json"
    }
EOF
            ;;
        hysteria2)
            cat <<'EOF'
    {
      "Type": "hysteria2",
      "Log": {"Level": "error"}
    }
EOF
            ;;
    esac
}

v2bz_render_node_config() {
    local api_host="$1"
    local api_key="$2"
    local node_id="$3"
    local node_type="$4"
    local core="$5"
    local cert_mode="${6:-none}"
    local cert_domain="${7:-}"
    local cert_provider="${8:-}"
    local cert_dns_env="${9:-}"
    local cert_self_fallback="${10:-0}"
    local listen_ip="0.0.0.0"
    local escaped_api_host escaped_api_key escaped_cert_domain escaped_cert_provider dns_env_json self_fallback_json

    if [[ "$(v2bz_check_ipv6_support)" == "1" && "$core" == "sing" ]]; then
        listen_ip="::"
    fi

    escaped_api_host="$(v2bz_json_escape "$api_host")"
    escaped_api_key="$(v2bz_json_escape "$api_key")"
    escaped_cert_domain="$(v2bz_json_escape "$cert_domain")"
    escaped_cert_provider="$(v2bz_json_escape "$cert_provider")"
    dns_env_json="$(v2bz_render_dns_env_json "$cert_dns_env")"
    self_fallback_json="$(v2bz_bool_json "$cert_self_fallback")"

    local extra_options
    case "$core" in
        xray)
            extra_options=',
      "EnableProxyProtocol": false,
      "EnableUot": true,
      "EnableTFO": true,
      "DNSType": "UseIPv4"'
            ;;
        sing)
            extra_options=',
      "EnableTFO": true,
      "EnableSniff": true'
            ;;
        hysteria2)
            extra_options=',
      "Hysteria2ConfigPath": "/etc/V2bZ/hy2config.yaml"'
            ;;
    esac

    cat <<EOF
    {
      "Core": "${core}",
      "ApiHost": "${escaped_api_host}",
      "ApiKey": "${escaped_api_key}",
      "NodeID": ${node_id},
      "NodeType": "${node_type}",
      "Timeout": 30,
      "ListenIP": "${listen_ip}",
      "SendIP": "0.0.0.0",
      "DeviceOnlineMinTraffic": 200,
      "ReportMinTraffic": 0${extra_options},
      "CertConfig": {
        "CertMode": "${cert_mode}",
        "RejectUnknownSni": false,
        "SelfFallback": ${self_fallback_json},
        "CertDomain": "${escaped_cert_domain}",
        "CertFile": "/etc/V2bZ/fullchain.cer",
        "KeyFile": "/etc/V2bZ/cert.key",
        "Email": "v2bz@zicboard.local",
        "Provider": "${escaped_cert_provider}",
        "DNSEnv": ${dns_env_json}
      }
    }
EOF
}

v2bz_render_full_config() {
    local cores_config="$1"
    local nodes_config="$2"

    cat <<EOF
{
  "Log": {"Level": "error", "Output": ""},
  "Cores": [
${cores_config}
  ],
  "Nodes": [
${nodes_config}
  ]
}
EOF
}

v2bz_render_config() {
    local core_config node_config

    core_config="$(v2bz_render_core_config "$5")"
    node_config="$(v2bz_render_node_config "$@")"
    v2bz_render_full_config "$core_config" "$node_config"
}

v2bz_write_aux_files() {
    mkdir -p "$V2BZ_CONFIG_DIR"

    cat >"${V2BZ_CONFIG_DIR}/custom_outbound.json" <<'EOF'
[
  {"tag":"IPv4_out","protocol":"freedom","settings":{"domainStrategy":"UseIPv4"}},
  {"tag":"IPv6_out","protocol":"freedom","settings":{"domainStrategy":"UseIPv6"}},
  {"tag":"block","protocol":"blackhole"}
]
EOF

    cat >"${V2BZ_CONFIG_DIR}/route.json" <<'EOF'
{
  "domainStrategy": "AsIs",
  "rules": [
    {"type":"field","outboundTag":"block","ip":["geoip:private","127.0.0.1/32","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16","fc00::/7","fe80::/10"]},
    {"type":"field","outboundTag":"block","protocol":["bittorrent"]},
    {"type":"field","outboundTag":"IPv4_out","network":"tcp,udp"}
  ]
}
EOF

    local dns_strategy="ipv4_only"
    if [[ "$(v2bz_check_ipv6_support)" == "1" ]]; then
        dns_strategy="prefer_ipv4"
    fi
    cat >"${V2BZ_CONFIG_DIR}/sing_origin.json" <<EOF
{
  "dns": {"servers": [{"tag":"cf","address":"1.1.1.1"}], "strategy":"${dns_strategy}"},
  "outbounds": [
    {"tag":"direct","type":"direct","domain_resolver":{"server":"cf","strategy":"${dns_strategy}"}},
    {"tag":"block","type":"block"}
  ],
  "route": {"rules": [
    {"ip_is_private": true, "outbound":"block"},
    {"protocol": "bittorrent", "outbound":"block"}
  ]},
  "experimental": {"cache_file": {"enabled": true}}
}
EOF

    cat >"${V2BZ_CONFIG_DIR}/hy2config.yaml" <<'EOF'
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
ignoreClientBandwidth: false
disableUDP: false
udpIdleTimeout: 60s
resolver:
  type: system
masquerade:
  type: 404
EOF
}

v2bz_write_config_parts() {
    local cores_config="$1"
    local nodes_config="$2"

    mkdir -p "$V2BZ_CONFIG_DIR"
    if [[ -f "${V2BZ_CONFIG_DIR}/config.json" ]]; then
        cp "${V2BZ_CONFIG_DIR}/config.json" "${V2BZ_CONFIG_DIR}/config.json.bak.$(date +%Y%m%d%H%M%S)"
    fi
    v2bz_render_full_config "$cores_config" "$nodes_config" >"${V2BZ_CONFIG_DIR}/config.json"
    v2bz_write_aux_files
    echo -e "${green}Đã tạo ${V2BZ_CONFIG_DIR}/config.json.${plain}"
}

v2bz_write_config() {
    local core_config node_config

    core_config="$(v2bz_render_core_config "$5")"
    node_config="$(v2bz_render_node_config "$@")"
    v2bz_write_config_parts "$core_config" "$node_config"
}

v2bz_quick_config() {
    local api_host
    local api_key="$2"
    local node_id="$3"
    local node_type
    local core
    local cert_mode="${6:-none}"
    local cert_domain="${7:-}"
    local cert_provider="${8:-}"
    local cert_dns_env="${9:-}"
    local cert_self_fallback="${10:-0}"
    local dry_run="${11:-0}"
    local skip_check="${12:-0}"

    api_host="$(v2bz_trim_trailing_slash "$1")"
    node_type="$(v2bz_normalize_node_type "$4")"
    core="$(v2bz_normalize_core "$5")"
    cert_mode="$(tr '[:upper:]' '[:lower:]' <<<"$cert_mode")"

    v2bz_validate_quick_values "$api_host" "$api_key" "$node_id" "$node_type" "$core" || return 1
    v2bz_validate_cert_values "$cert_mode" || return 1

    if [[ "$dry_run" == "1" ]]; then
        v2bz_render_config "$api_host" "$api_key" "$node_id" "$node_type" "$core" "$cert_mode" "$cert_domain" "$cert_provider" "$cert_dns_env" "$cert_self_fallback"
        return 0
    fi

    if [[ "$skip_check" != "1" ]]; then
        v2bz_validate_panel "$api_host" "$api_key" "$node_id" "$node_type" || return 1
    fi

    v2bz_write_config "$api_host" "$api_key" "$node_id" "$node_type" "$core" "$cert_mode" "$cert_domain" "$cert_provider" "$cert_dns_env" "$cert_self_fallback"
}

generate_config_file() {
    local api_host api_key node_id node_type core cert_mode cert_domain cert_provider cert_dns_env cert_self_fallback
    local add_more fixed_api_answer node_config core_config
    local cores_config="" nodes_config=""
    local reuse_api=1 reuse_prompted=0
    local core_xray=0 core_sing=0 core_hysteria2=0

    echo -e "${yellow}Trình tạo cấu hình V2bZ cho ZicBoard UniProxy${plain}"
    v2bz_print_support_matrix
    echo

    read -rp "Nhập URL panel ZicBoard (ví dụ https://panel.example.com): " api_host
    api_host="$(v2bz_trim_trailing_slash "$api_host")"
    read -rp "Nhập Server Token/API Key: " api_key

    while true; do
        while true; do
            read -rp "Nhập Node ID: " node_id
            [[ "$node_id" =~ ^[0-9]+$ ]] && break
            echo -e "${red}Node ID phải là số.${plain}"
        done

        while true; do
            read -rp "Nhập NodeType legacy (vmess/vless/trojan/shadowsocks/hysteria/hysteria2/tuic/anytls): " node_type
            node_type="$(v2bz_normalize_node_type "$node_type")"
            case "$node_type" in
                shadowsocks|vmess|vless|trojan|hysteria|hysteria2|tuic|anytls) break ;;
                zicnode|v2node) echo -e "${red}V2bZ không chạy ZicNode/V2Node. Hãy chọn node legacy qua UniProxy.${plain}" ;;
                *) echo -e "${red}NodeType không hợp lệ: ${node_type}.${plain}" ;;
            esac
        done

        v2bz_prompt_core "$node_type" core

        cert_mode="none"
        cert_domain=""
        cert_provider=""
        cert_dns_env=""
        cert_self_fallback="0"
        read -rp "V2bZ có cần fallback chứng chỉ local không? (auto/none/file/http/dns/self, mặc định none): " cert_mode
        cert_mode="${cert_mode:-none}"
        cert_mode="$(tr '[:upper:]' '[:lower:]' <<<"$cert_mode")"
        if [[ "$cert_mode" != "none" ]]; then
            read -rp "Nhập domain chứng chỉ: " cert_domain
        fi
        if [[ "$cert_mode" == "auto" || "$cert_mode" == "dns" ]]; then
            read -rp "Nhập DNS provider lego (ví dụ cloudflare, bỏ trống nếu dùng HTTP-01): " cert_provider
            read -rp "Nhập DNS env KEY=VALUE[,KEY=VALUE] (bỏ trống nếu không dùng DNS-01): " cert_dns_env
        fi
        if [[ "$cert_mode" == "auto" ]]; then
            read -rp "Bật self-signed fallback khi ACME lỗi? (y/N): " cert_self_fallback
        fi

        v2bz_validate_quick_values "$api_host" "$api_key" "$node_id" "$node_type" "$core" || return 1
        v2bz_validate_cert_values "$cert_mode" || return 1
        v2bz_validate_panel "$api_host" "$api_key" "$node_id" "$node_type" || return 1

        node_config="$(v2bz_render_node_config "$api_host" "$api_key" "$node_id" "$node_type" "$core" "$cert_mode" "$cert_domain" "$cert_provider" "$cert_dns_env" "$cert_self_fallback")"
        [[ -n "$nodes_config" ]] && nodes_config+=","$'\n'
        nodes_config+="$node_config"
        case "$core" in
            xray) core_xray=1 ;;
            sing) core_sing=1 ;;
            hysteria2) core_hysteria2=1 ;;
        esac

        read -rp "Bạn có muốn cấu hình thêm node nữa không? (y/N): " add_more
        [[ "$add_more" =~ ^[Yy]$ ]] || break

        if [[ "$reuse_prompted" == "0" ]]; then
            read -rp "Dùng chung URL panel và API Key cho các node tiếp theo? (Y/n): " fixed_api_answer
            [[ "$fixed_api_answer" =~ ^[Nn]$ ]] && reuse_api=0
            reuse_prompted=1
        fi
        if [[ "$reuse_api" == "0" ]]; then
            read -rp "Nhập URL panel ZicBoard (ví dụ https://panel.example.com): " api_host
            api_host="$(v2bz_trim_trailing_slash "$api_host")"
            read -rp "Nhập Server Token/API Key: " api_key
        fi
    done

    if [[ "$core_xray" == "1" ]]; then
        cores_config="$(v2bz_render_core_config xray)"
    fi
    if [[ "$core_sing" == "1" ]]; then
        core_config="$(v2bz_render_core_config sing)"
        [[ -n "$cores_config" ]] && cores_config+=","$'\n'
        cores_config+="$core_config"
    fi
    if [[ "$core_hysteria2" == "1" ]]; then
        core_config="$(v2bz_render_core_config hysteria2)"
        [[ -n "$cores_config" ]] && cores_config+=","$'\n'
        cores_config+="$core_config"
    fi

    v2bz_write_config_parts "$cores_config" "$nodes_config"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    generate_config_file
fi
