#!/usr/bin/env bash
set -e

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

V2BZ_REPO="${V2BZ_REPO:-kutycma/V2bZ}"
V2BZ_SCRIPT_REPO="${V2BZ_SCRIPT_REPO:-kutycma/V2bZ-script}"
V2BZ_SCRIPT_BRANCH="${V2BZ_SCRIPT_BRANCH:-master}"
V2BZ_INSTALL_DIR="${V2BZ_INSTALL_DIR:-/usr/local/V2bZ}"
V2BZ_CONFIG_DIR="${V2BZ_CONFIG_DIR:-/etc/V2bZ}"

quick=0
dry_run=0
skip_panel_check=0
version=""
api_host=""
api_key=""
node_id=""
node_type=""
core=""
cert_mode="none"
cert_domain=""
cert_provider=""
cert_dns_env=""
cert_self_fallback="0"

usage() {
    cat <<EOF
Cài đặt V2bZ cho ZicBoard UniProxy legacy.

Ví dụ cài nhanh:
  bash install.sh --quick --api-host https://panel.example.com --api-key SERVER_TOKEN --node-id 1 --node-type vless --core xray

Tùy chọn:
  --quick                 Cài và sinh config ngay từ tham số
  --dry-run               Chỉ in config, không cần root và không cài đặt
  --api-host URL          URL panel ZicBoard
  --api-key TOKEN         Server Token/API Key
  --node-id ID            ID node legacy trong panel
  --node-type TYPE        vmess/vless/trojan/shadowsocks/hysteria/hysteria2/tuic/anytls
  --core CORE             xray/sing/hysteria2. Nếu bỏ trống trong terminal sẽ hiện menu chọn core
  --cert-mode MODE        auto/none/file/http/dns/self. Mặc định none
  --cert-domain DOMAIN    Domain chứng chỉ fallback local
  --cert-provider NAME    DNS provider lego, ví dụ cloudflare
  --cert-dns-env KV       KEY=VALUE[,KEY=VALUE] cho DNS provider
  --cert-self-fallback    Khi cert-mode auto, fallback sang cert tự ký nếu ACME lỗi
  --skip-panel-check      Không gọi thử UniProxy/config trước khi ghi config
  --repo OWNER/REPO       Repo binary V2bZ. Mặc định ${V2BZ_REPO}
  --script-repo OWNER/REPO Repo script. Mặc định ${V2BZ_SCRIPT_REPO}
  --version TAG           Cài tag chỉ định
  -h, --help              Hiển thị trợ giúp
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick) quick=1 ;;
        --dry-run) dry_run=1 ;;
        --skip-panel-check) skip_panel_check=1 ;;
        --api-host) api_host="$2"; shift ;;
        --api-key) api_key="$2"; shift ;;
        --node-id) node_id="$2"; shift ;;
        --node-type) node_type="$2"; shift ;;
        --core) core="$2"; shift ;;
        --cert-mode) cert_mode="$2"; shift ;;
        --cert-domain) cert_domain="$2"; shift ;;
        --cert-provider) cert_provider="$2"; shift ;;
        --cert-dns-env) cert_dns_env="$2"; shift ;;
        --cert-self-fallback) cert_self_fallback="1" ;;
        --repo) V2BZ_REPO="$2"; shift ;;
        --script-repo) V2BZ_SCRIPT_REPO="$2"; shift ;;
        --version) version="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            if [[ -z "$version" && "$1" != --* ]]; then
                version="$1"
            else
                echo -e "${red}Tham số không hợp lệ: $1${plain}"
                usage
                exit 1
            fi
            ;;
    esac
    shift
done

load_initconfig() {
    local script_dir raw_url tmp_file
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
    if [[ -n "$script_dir" && -f "${script_dir}/initconfig.sh" ]]; then
        # shellcheck source=/dev/null
        source "${script_dir}/initconfig.sh"
        return
    fi

    raw_url="https://raw.githubusercontent.com/${V2BZ_SCRIPT_REPO}/${V2BZ_SCRIPT_BRANCH}/initconfig.sh"
    tmp_file="$(mktemp)"
    if ! curl -fsSL "$raw_url" -o "$tmp_file"; then
        echo -e "${red}Không tải được initconfig.sh từ ${raw_url}.${plain}"
        rm -f "$tmp_file"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$tmp_file"
    rm -f "$tmp_file"
}

load_initconfig

read_with_default() {
    local prompt="$1"
    local current="$2"
    local answer

    if [[ -n "$current" ]]; then
        read -rp "${prompt} [${current}]: " answer
        printf '%s' "${answer:-$current}"
    else
        read -rp "${prompt}: " answer
        printf '%s' "$answer"
    fi
}

quick_missing_required() {
    [[ -z "$api_host" || -z "$api_key" || -z "$node_id" || -z "$node_type" ]]
}

prepare_quick_config() {
    local prompt_mode=0

    api_host="$(v2bz_trim_trailing_slash "$api_host")"
    node_type="$(v2bz_normalize_node_type "$node_type")"
    core="$(v2bz_normalize_core "$core")"

    if quick_missing_required; then
        prompt_mode=1
        if [[ ! -t 0 ]]; then
            echo -e "${red}Thiếu tham số cài nhanh và không có terminal để hỏi thêm.${plain}"
            echo -e "${yellow}Hãy truyền đủ --api-host, --api-key, --node-id, --node-type hoặc chạy script trong terminal tương tác.${plain}"
            exit 1
        fi
        echo -e "${yellow}Thiếu tham số cài nhanh. Chuyển sang wizard tiếng Việt để hỏi phần còn thiếu.${plain}"
        v2bz_print_support_matrix
        echo
    fi

    if [[ "$prompt_mode" != "1" ]]; then
        if [[ -z "$core" ]]; then
            if [[ -t 0 ]]; then
                v2bz_prompt_core "$node_type" core
            else
                core="$(v2bz_default_core_for_node "$node_type")"
            fi
        fi
        v2bz_validate_quick_values "$api_host" "$api_key" "$node_id" "$node_type" "$core"
        return
    fi

    while [[ -z "$api_host" ]]; do
        api_host="$(v2bz_trim_trailing_slash "$(read_with_default "Nhập URL panel ZicBoard" "$api_host")")"
    done
    while [[ -z "$api_key" ]]; do
        api_key="$(read_with_default "Nhập Server Token/API Key" "$api_key")"
    done
    while true; do
        node_id="$(read_with_default "Nhập Node ID" "$node_id")"
        [[ "$node_id" =~ ^[0-9]+$ ]] && break
        echo -e "${red}Node ID phải là số nguyên dương.${plain}"
        node_id=""
    done
    while true; do
        [[ -n "$node_type" ]] || v2bz_prompt_node_type node_type
        case "$node_type" in
            zicnode|v2node)
                echo -e "${red}V2bZ không chạy ZicNode/V2Node. Hãy chọn node legacy qua UniProxy.${plain}"
                node_type=""
                ;;
            shadowsocks|vmess|vless|trojan|hysteria|hysteria2|tuic|anytls)
                break
                ;;
            *)
                echo -e "${red}NodeType không hợp lệ: ${node_type}.${plain}"
                node_type=""
                ;;
        esac
    done

    if [[ -n "$core" ]] && ! v2bz_core_supported "$core" "$node_type"; then
        echo -e "${red}Core ${core} không hỗ trợ node ${node_type}.${plain}"
        core=""
    fi
    [[ -n "$core" ]] || v2bz_prompt_core "$node_type" core

    v2bz_validate_quick_values "$api_host" "$api_key" "$node_id" "$node_type" "$core"
}

if [[ "$quick" == "1" ]]; then
    prepare_quick_config
elif [[ -n "$node_type" && -z "$core" ]]; then
    core="$(v2bz_default_core_for_node "$(v2bz_normalize_node_type "$node_type")")"
fi

if [[ "$dry_run" == "1" ]]; then
    if [[ "$quick" != "1" ]]; then
        echo -e "${red}--dry-run cần dùng cùng --quick và đủ tham số node.${plain}"
        usage
        exit 1
    fi
    v2bz_quick_config "$api_host" "$api_key" "$node_id" "$node_type" "$core" "$cert_mode" "$cert_domain" "$cert_provider" "$cert_dns_env" "$cert_self_fallback" 1 1
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    echo -e "${red}Lỗi:${plain} Bạn phải chạy script này bằng quyền root."
    exit 1
fi

detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -Eqi 'alpine' /etc/issue 2>/dev/null; then
        release="alpine"
    elif grep -Eqi 'debian' /etc/issue 2>/dev/null || grep -Eqi 'debian' /proc/version 2>/dev/null; then
        release="debian"
    elif grep -Eqi 'ubuntu' /etc/issue 2>/dev/null || grep -Eqi 'ubuntu' /proc/version 2>/dev/null; then
        release="ubuntu"
    elif grep -Eqi 'centos|red hat|redhat|rocky|alma|oracle linux' /etc/issue 2>/dev/null || grep -Eqi 'centos|red hat|redhat|rocky|alma|oracle linux' /proc/version 2>/dev/null; then
        release="centos"
    elif grep -Eqi 'arch' /proc/version 2>/dev/null; then
        release="arch"
    else
        echo -e "${red}Không nhận diện được hệ điều hành.${plain}"
        exit 1
    fi

    arch="$(uname -m)"
    case "$arch" in
        x86_64|x64|amd64) arch="64" ;;
        aarch64|arm64) arch="arm64-v8a" ;;
        s390x) arch="s390x" ;;
        *)
            echo -e "${yellow}Không nhận diện được kiến trúc ${arch}, dùng mặc định 64.${plain}"
            arch="64"
            ;;
    esac
}

install_base() {
    case "$release" in
        centos)
            yum install -y epel-release wget curl unzip tar crontabs socat ca-certificates nano >/dev/null 2>&1 || true
            update-ca-trust force-enable >/dev/null 2>&1 || true
            ;;
        alpine)
            apk add --no-cache wget curl unzip tar socat ca-certificates nano >/dev/null
            update-ca-certificates >/dev/null 2>&1 || true
            ;;
        debian|ubuntu)
            apt-get update -y >/dev/null
            apt-get install -y wget curl unzip tar cron socat ca-certificates nano >/dev/null
            update-ca-certificates >/dev/null 2>&1 || true
            ;;
        arch)
            pacman -Sy --noconfirm >/dev/null
            pacman -S --noconfirm --needed wget curl unzip tar cronie socat ca-certificates nano >/dev/null
            ;;
    esac
}

latest_version() {
    curl -fsSL "https://api.github.com/repos/${V2BZ_REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1
}

install_binary() {
    local tag url zip_file
    tag="$version"
    if [[ -z "$tag" ]]; then
        tag="$(latest_version)"
    fi
    if [[ -z "$tag" ]]; then
        echo -e "${red}Không lấy được phiên bản mới nhất từ GitHub.${plain}"
        exit 1
    fi

    echo -e "${green}Cài V2bZ ${tag} từ ${V2BZ_REPO}.${plain}"
    rm -rf "$V2BZ_INSTALL_DIR"
    mkdir -p "$V2BZ_INSTALL_DIR" "$V2BZ_CONFIG_DIR"
    cd "$V2BZ_INSTALL_DIR"

    url="https://github.com/${V2BZ_REPO}/releases/download/${tag}/V2bZ-linux-${arch}.zip"
    zip_file="${V2BZ_INSTALL_DIR}/V2bZ-linux.zip"
    if ! wget --no-check-certificate -N --progress=bar -O "$zip_file" "$url"; then
        echo -e "${red}Tải V2bZ thất bại: ${url}${plain}"
        exit 1
    fi
    unzip -o "$zip_file" >/dev/null
    rm -f "$zip_file"
    chmod +x "${V2BZ_INSTALL_DIR}/V2bZ"

    [[ -f geoip.dat ]] && cp geoip.dat "$V2BZ_CONFIG_DIR/"
    [[ -f geosite.dat ]] && cp geosite.dat "$V2BZ_CONFIG_DIR/"
}

install_service() {
    if [[ "$release" == "alpine" ]]; then
        cat >/etc/init.d/V2bZ <<EOF
#!/sbin/openrc-run
name="V2bZ"
description="V2bZ"
command="${V2BZ_INSTALL_DIR}/V2bZ"
command_args="server --config ${V2BZ_CONFIG_DIR}/config.json"
command_user="root"
pidfile="/run/V2bZ.pid"
command_background="yes"
depend() { need net; }
EOF
        chmod +x /etc/init.d/V2bZ
        rc-update add V2bZ default >/dev/null 2>&1 || true
    else
        cat >/etc/systemd/system/V2bZ.service <<EOF
[Unit]
Description=V2bZ Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitNOFILE=999999
WorkingDirectory=${V2BZ_INSTALL_DIR}/
ExecStart=${V2BZ_INSTALL_DIR}/V2bZ server --config ${V2BZ_CONFIG_DIR}/config.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable V2bZ >/dev/null 2>&1 || true
    fi
}

install_manager() {
    local raw_url
    raw_url="https://raw.githubusercontent.com/${V2BZ_SCRIPT_REPO}/${V2BZ_SCRIPT_BRANCH}/V2bZ.sh"
    curl -fsSL "$raw_url" -o /usr/bin/V2bZ
    chmod +x /usr/bin/V2bZ
    ln -sf /usr/bin/V2bZ /usr/bin/v2bz
}

restart_service() {
    if [[ "$release" == "alpine" ]]; then
        service V2bZ restart || true
        service V2bZ status || true
    else
        systemctl restart V2bZ || true
        systemctl status V2bZ --no-pager -l || true
    fi
}

detect_os
echo -e "${green}Hệ điều hành: ${release}, kiến trúc release: ${arch}.${plain}"
install_base
install_binary
install_service
install_manager

if [[ "$quick" == "1" ]]; then
    if [[ -z "$core" && -n "$node_type" ]]; then
        core="$(v2bz_default_core_for_node "$(v2bz_normalize_node_type "$node_type")")"
    fi
    v2bz_quick_config "$api_host" "$api_key" "$node_id" "$node_type" "$core" "$cert_mode" "$cert_domain" "$cert_provider" "$cert_dns_env" "$cert_self_fallback" 0 "$skip_panel_check"
else
    if [[ ! -f "${V2BZ_CONFIG_DIR}/config.json" ]]; then
        echo -e "${yellow}Chưa có config. Bắt đầu wizard tạo cấu hình.${plain}"
        generate_config_file
    else
        echo -e "${yellow}Đã có ${V2BZ_CONFIG_DIR}/config.json, giữ nguyên cấu hình hiện tại.${plain}"
        v2bz_write_aux_files
    fi
fi

restart_service

cat <<EOF

${green}Cài đặt hoàn tất.${plain}
Lệnh quản lý:
  V2bZ            Mở menu
  V2bZ status     Xem trạng thái
  V2bZ log        Xem log
  V2bZ generate   Tạo lại cấu hình UniProxy

Lưu ý: Trong ZicBoard hãy dùng node legacy VMess/VLess/Trojan/Shadowsocks, không chọn ZicNode/V2Node cho V2bZ.
EOF
