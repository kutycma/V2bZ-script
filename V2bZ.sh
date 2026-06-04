#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

V2BZ_REPO="${V2BZ_REPO:-kutycma/V2bZ}"
V2BZ_SCRIPT_REPO="${V2BZ_SCRIPT_REPO:-kutycma/V2bZ-script}"
V2BZ_SCRIPT_BRANCH="${V2BZ_SCRIPT_BRANCH:-master}"
V2BZ_INSTALL_DIR="${V2BZ_INSTALL_DIR:-/usr/local/V2bZ}"
V2BZ_CONFIG_DIR="${V2BZ_CONFIG_DIR:-/etc/V2bZ}"

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}Lỗi:${plain} Bạn phải chạy lệnh này bằng quyền root."
        exit 1
    fi
}

detect_release() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -Eqi 'alpine' /etc/issue 2>/dev/null; then
        release="alpine"
    else
        release="systemd"
    fi
}

service_cmd() {
    detect_release
    if [[ "$release" == "alpine" ]]; then
        service V2bZ "$1"
    else
        systemctl "$1" V2bZ
    fi
}

check_installed() {
    [[ -x "${V2BZ_INSTALL_DIR}/V2bZ" ]]
}

check_status() {
    if ! check_installed; then
        return 2
    fi
    detect_release
    if [[ "$release" == "alpine" ]]; then
        service V2bZ status >/dev/null 2>&1
    else
        systemctl is-active --quiet V2bZ
    fi
}

show_status() {
    check_status
    case $? in
        0) echo -e "Trạng thái V2bZ: ${green}đang chạy${plain}" ;;
        1) echo -e "Trạng thái V2bZ: ${yellow}đã cài nhưng chưa chạy${plain}" ;;
        2) echo -e "Trạng thái V2bZ: ${red}chưa cài đặt${plain}" ;;
    esac
}

pause_menu() {
    echo
    read -rp "Nhấn Enter để quay lại menu..." _
    show_menu
}

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

install_v2bz() {
    require_root
    bash <(curl -fsSL "https://raw.githubusercontent.com/${V2BZ_SCRIPT_REPO}/${V2BZ_SCRIPT_BRANCH}/install.sh") "$@"
}

update_v2bz() {
    require_root
    local version_arg=()
    if [[ -n "$1" ]]; then
        version_arg=(--version "$1")
    fi
    install_v2bz "${version_arg[@]}"
}

start_v2bz() {
    require_root
    service_cmd start
    show_status
}

stop_v2bz() {
    require_root
    service_cmd stop
    show_status
}

restart_v2bz() {
    require_root
    service_cmd restart
    show_status
}

status_v2bz() {
    require_root
    detect_release
    if [[ "$release" == "alpine" ]]; then
        service V2bZ status
    else
        systemctl status V2bZ --no-pager -l
    fi
}

log_v2bz() {
    require_root
    detect_release
    if [[ "$release" == "alpine" ]]; then
        echo -e "${yellow}Alpine không hỗ trợ journalctl. Hãy xem log theo OpenRC hoặc stdout service.${plain}"
    else
        journalctl -u V2bZ.service -e --no-pager -f
    fi
}

enable_v2bz() {
    require_root
    detect_release
    if [[ "$release" == "alpine" ]]; then
        rc-update add V2bZ default
    else
        systemctl enable V2bZ
    fi
}

disable_v2bz() {
    require_root
    detect_release
    if [[ "$release" == "alpine" ]]; then
        rc-update del V2bZ default
    else
        systemctl disable V2bZ
    fi
}

edit_config() {
    require_root
    ${EDITOR:-nano} "${V2BZ_CONFIG_DIR}/config.json"
    restart_v2bz
}

generate_config() {
    require_root
    load_initconfig
    generate_config_file
    restart_v2bz
}

version_v2bz() {
    if check_installed; then
        "${V2BZ_INSTALL_DIR}/V2bZ" version
    else
        echo -e "${red}V2bZ chưa cài đặt.${plain}"
    fi
}

x25519_v2bz() {
    if check_installed; then
        "${V2BZ_INSTALL_DIR}/V2bZ" x25519
    else
        echo -e "${red}V2bZ chưa cài đặt.${plain}"
    fi
}

update_shell() {
    require_root
    curl -fsSL "https://raw.githubusercontent.com/${V2BZ_SCRIPT_REPO}/${V2BZ_SCRIPT_BRANCH}/V2bZ.sh" -o /usr/bin/V2bZ
    chmod +x /usr/bin/V2bZ
    ln -sf /usr/bin/V2bZ /usr/bin/v2bz
    echo -e "${green}Đã cập nhật script quản lý.${plain}"
}

open_ports() {
    require_root
    systemctl stop firewalld.service 2>/dev/null || true
    systemctl disable firewalld.service 2>/dev/null || true
    setenforce 0 2>/dev/null || true
    ufw disable 2>/dev/null || true
    iptables -P INPUT ACCEPT 2>/dev/null || true
    iptables -P FORWARD ACCEPT 2>/dev/null || true
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    netfilter-persistent save 2>/dev/null || true
    echo -e "${green}Đã mở toàn bộ cổng tường lửa.${plain}"
}

uninstall_v2bz() {
    require_root
    read -rp "Bạn chắc chắn muốn gỡ V2bZ? Nhập yes để xác nhận: " answer
    [[ "$answer" != "yes" ]] && return 0
    detect_release
    if [[ "$release" == "alpine" ]]; then
        service V2bZ stop 2>/dev/null || true
        rc-update del V2bZ default 2>/dev/null || true
        rm -f /etc/init.d/V2bZ
    else
        systemctl stop V2bZ 2>/dev/null || true
        systemctl disable V2bZ 2>/dev/null || true
        rm -f /etc/systemd/system/V2bZ.service
        systemctl daemon-reload 2>/dev/null || true
        systemctl reset-failed 2>/dev/null || true
    fi
    rm -rf "$V2BZ_INSTALL_DIR" "$V2BZ_CONFIG_DIR"
    echo -e "${green}Đã gỡ V2bZ.${plain}"
}

usage() {
    cat <<'EOF'
Cách dùng:
  V2bZ                 Mở menu quản lý
  V2bZ install          Cài đặt
  V2bZ update [tag]     Cập nhật/cài tag chỉ định
  V2bZ start|stop|restart|status|log
  V2bZ config           Sửa config JSON
  V2bZ generate         Tạo config UniProxy legacy
  V2bZ x25519           Tạo khóa X25519
  V2bZ version          Xem phiên bản
  V2bZ uninstall        Gỡ cài đặt
EOF
}

show_menu() {
    clear 2>/dev/null || true
    echo -e "${green}V2bZ Manager cho ZicBoard UniProxy legacy${plain}"
    echo "Không dùng cho node ZicNode/V2Node. Hãy dùng node legacy VMess/VLess/Trojan/Shadowsocks."
    echo
    show_status
    cat <<'EOF'

  0. Sửa config JSON
  1. Cài đặt V2bZ
  2. Cập nhật V2bZ
  3. Gỡ cài đặt V2bZ
  4. Khởi động
  5. Dừng
  6. Khởi động lại
  7. Xem trạng thái
  8. Xem log
  9. Bật tự khởi động
 10. Tắt tự khởi động
 11. Tạo config UniProxy
 12. Tạo khóa X25519
 13. Xem phiên bản
 14. Cập nhật script quản lý
 15. Mở toàn bộ cổng tường lửa
 16. Thoát
EOF
    echo
    read -rp "Nhập lựa chọn [0-16]: " choice
    case "$choice" in
        0) edit_config; pause_menu ;;
        1) install_v2bz; pause_menu ;;
        2) update_v2bz; pause_menu ;;
        3) uninstall_v2bz; pause_menu ;;
        4) start_v2bz; pause_menu ;;
        5) stop_v2bz; pause_menu ;;
        6) restart_v2bz; pause_menu ;;
        7) status_v2bz; pause_menu ;;
        8) log_v2bz ;;
        9) enable_v2bz; pause_menu ;;
        10) disable_v2bz; pause_menu ;;
        11) generate_config; pause_menu ;;
        12) x25519_v2bz; pause_menu ;;
        13) version_v2bz; pause_menu ;;
        14) update_shell; pause_menu ;;
        15) open_ports; pause_menu ;;
        16) exit 0 ;;
        *) echo -e "${red}Lựa chọn không hợp lệ.${plain}"; pause_menu ;;
    esac
}

case "${1:-}" in
    install) shift; install_v2bz "$@" ;;
    update) shift; update_v2bz "${1:-}" ;;
    start) start_v2bz ;;
    stop) stop_v2bz ;;
    restart) restart_v2bz ;;
    status) status_v2bz ;;
    log) log_v2bz ;;
    enable) enable_v2bz ;;
    disable) disable_v2bz ;;
    config) edit_config ;;
    generate) generate_config ;;
    x25519) x25519_v2bz ;;
    version) version_v2bz ;;
    update_shell) update_shell ;;
    uninstall) uninstall_v2bz ;;
    help|-h|--help) usage ;;
    "") show_menu ;;
    *) usage; exit 1 ;;
esac
