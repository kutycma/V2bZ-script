#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./initconfig.sh

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

core=""
v2bz_prompt_core vless core <<< $'9\n3\n1' >/dev/null
[[ "$core" == "xray" ]]
v2bz_prompt_core anytls core <<< '2' >/dev/null
[[ "$core" == "sing" ]]
v2bz_prompt_core hysteria2 core <<< '3' >/dev/null
[[ "$core" == "hysteria2" ]]

V2BZ_CONFIG_DIR="${tmp_dir}/wizard"
v2bz_check_ipv6_support() { echo 0; }
v2bz_validate_panel() { return 0; }

generate_config_file <<'EOF' >/dev/null
https://panel.example.com/
server-token
1
vless
1

y

2
hysteria2
2

y
3
trojan
1


EOF

node - "$V2BZ_CONFIG_DIR/config.json" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

assert.deepEqual(config.Cores.map(core => core.Type), ['xray', 'sing']);
assert.equal(config.Nodes.length, 3);
assert.deepEqual(config.Nodes.map(node => node.Core), ['xray', 'sing', 'xray']);
assert.deepEqual(config.Nodes.map(node => node.NodeID), [1, 2, 3]);
assert.ok(config.Nodes.every(node => node.ApiHost === 'https://panel.example.com'));
assert.ok(config.Nodes.every(node => node.ApiKey === 'server-token'));
JS

V2BZ_CONFIG_DIR="${tmp_dir}/separate-panels"
generate_config_file <<'EOF' >/dev/null
https://panel-a.example.com
token-a
10
vless
1

y
n
https://panel-b.example.com
token-b
11
anytls
2


EOF

node - "$V2BZ_CONFIG_DIR/config.json" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

assert.deepEqual(config.Nodes.map(node => node.ApiHost), [
  'https://panel-a.example.com',
  'https://panel-b.example.com',
]);
assert.deepEqual(config.Nodes.map(node => node.ApiKey), ['token-a', 'token-b']);
JS

bash install.sh --quick --dry-run \
    --api-host https://panel.example.com \
    --api-key server-token \
    --node-id 3 \
    --node-type vless \
    --core xray >"${tmp_dir}/quick.json"

node - "$tmp_dir/quick.json" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

assert.equal(config.Cores.length, 1);
assert.equal(config.Cores[0].Type, 'xray');
assert.equal(config.Nodes.length, 1);
assert.equal(config.Nodes[0].NodeID, 3);
JS

echo "initconfig tests passed"
