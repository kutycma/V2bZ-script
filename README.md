# V2bZ Script


Script cài đặt và quản lý V2bZ cho ZicBoard theo hướng UniProxy legacy.

V2bZ không dùng cho node `ZicNode`/`V2Node` gom protocol. Trong ZicBoard hãy tạo node legacy riêng như `VMess`, `VLess`, `Trojan`, `Shadowsocks`, sau đó dùng đúng `Node ID` và `NodeType` của node đó.

## Cài Một Lệnh

Wizard tiếng Việt:

```bash
wget -N https://raw.githubusercontent.com/kutycma/V2bZ-script/master/install.sh && bash install.sh
```

Cài nhanh không cần wizard:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kutycma/V2bZ-script/master/install.sh) \
  --quick \
  --api-host https://panel.example.com \
  --api-key SERVER_TOKEN \
  --node-id 1 \
  --node-type vless \
  --core xray
```

Auto TLS khuyến nghị bật trong panel ZicBoard cho node legacy TLS. V2bZ sẽ đọc `tls_settings` từ panel, tự cấp/gia hạn chứng chỉ và report SHA256 để web tự thêm `pinnedPeerCertSha256` cho client. Các flag cert dưới đây chỉ là fallback local khi panel chưa cấu hình Auto TLS:

```bash
bash install.sh --quick --dry-run \
  --api-host https://panel.example.com \
  --api-key SERVER_TOKEN \
  --node-id 1 \
  --node-type vless \
  --core xray \
  --cert-mode auto \
  --cert-domain node.example.com \
  --cert-provider cloudflare \
  --cert-dns-env CF_DNS_API_TOKEN=xxxx \
  --cert-self-fallback
```

Nếu dùng `--quick` nhưng thiếu tham số, script sẽ chuyển sang wizard tiếng Việt để hỏi phần còn thiếu. Khi chạy không có terminal tương tác, script sẽ báo lỗi rõ và không ghi config.

Xem config sẽ sinh trước khi cài:

```bash
bash install.sh --quick --dry-run \
  --api-host https://panel.example.com \
  --api-key SERVER_TOKEN \
  --node-id 1 \
  --node-type vless \
  --core xray
```

## Matrix Hỗ Trợ

| Core | NodeType hỗ trợ |
|---|---|
| `xray` | `shadowsocks`, `vmess`, `vless`, `trojan` |
| `sing` | `shadowsocks`, `vmess`, `vless`, `trojan`, `hysteria`, `hysteria2`, `tuic`, `anytls` |
| `hysteria2` | `hysteria2` |

Network khuyến nghị khi dùng `xray`:

| Protocol | Network hỗ trợ |
|---|---|
| `vmess`, `vless` | `tcp`, `ws`, `grpc`, `httpupgrade`, `xhttp` |
| `trojan` | `tcp`, `ws`, `grpc` |

## Override Repo

Mặc định script tải binary từ `kutycma/V2bZ` và script từ `kutycma/V2bZ-script`. Có thể đổi bằng tham số hoặc biến môi trường:

```bash
bash install.sh --repo yourname/V2bZ --script-repo yourname/V2bZ-script
```

```bash
export V2BZ_REPO=yourname/V2bZ
export V2BZ_SCRIPT_REPO=yourname/V2bZ-script
```

## Lệnh Quản Lý

Sau khi cài:

```bash
V2bZ            # mở menu
V2bZ status     # xem trạng thái
V2bZ log        # xem log
V2bZ generate   # tạo lại cấu hình UniProxy
V2bZ restart    # khởi động lại service
```

## Lưu Ý ZicBoard

- API Host là URL panel, ví dụ `https://panel.example.com`.
- API Key là `server_token` trong cấu hình ZicBoard.
- `Node ID` là ID của node legacy tương ứng trong panel.
- Không nhập `zicnode` hoặc `v2node` cho V2bZ; hai loại này thuộc backend ZicNode riêng.
- Với `VMess`, `VLess`, `Trojan`, `Hysteria/Hysteria2`, `TUIC`, `AnyTLS`, có thể bật Auto TLS trong panel. `Shadowsocks` không dùng Auto TLS inbound trong phạm vi V2bZ.
